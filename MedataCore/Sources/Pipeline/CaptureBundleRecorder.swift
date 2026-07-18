import CaptureKit
import CoreGraphics
import Foundation
import ImageIO
import os
import PortableContracts
import Segmentation
import SwiftProtobuf
import UniformTypeIdentifiers

// Developer-phase capture recorder (capture-bundle-recorder smolspec). Writes
// one PbMealFixture per estimation attempt into a directory the App layer
// exposes via the Files app, so field captures replay offline through
// HarnessCLI (FixtureLoader + FixtureRunner) with no harness changes.
// Deliberately NOT gated by DEBUG or HARNESS_ENABLED: field-day builds are
// Release configuration and must record (decision log, Decision 2).
//
// Estimation-path boundary (MaskArtefactWriter precedent): consumes
// already-computed values, and every encode/write failure is logged to the
// CaptureBundle category and swallowed — recording can never alter, delay,
// or fail the estimation result. The actor serialises writes so at most one
// bundle (~200 MB at camera resolution, probs-dominated) is being encoded
// at a time.
public actor CaptureBundleRecorder {

    // Everything the recorder needs, extracted by `Pipeline.estimate` before
    // hand-off. The non-Sendable PipelineDiagnostics accumulator never
    // crosses; only these Sendable values do.
    public struct Payload: Sendable {
        public let captureResult: CaptureResult
        public let nadirSegmentation: SegmentationResult?
        public let obliqueSegmentation: SegmentationResult?
        // The loader compares this verbatim against `--checkpoint-sha256`:
        // the loaded model's checkpoint prefix, or the pipeline's
        // segmenterSource lineage tag when no Core ML model is loaded
        // (dev-stub builds).
        public let segmenterVersion: String
        // Same value as the attempt's EstimationAttemptRecord.timestampMs —
        // the join key between Estimation Log rows and bundle filenames.
        public let timestampMs: Int64
        public let outcome: String   // "success" | "refused"

        public init(
            captureResult: CaptureResult,
            nadirSegmentation: SegmentationResult?,
            obliqueSegmentation: SegmentationResult?,
            segmenterVersion: String,
            timestampMs: Int64,
            outcome: String
        ) {
            self.captureResult = captureResult
            self.nadirSegmentation = nadirSegmentation
            self.obliqueSegmentation = obliqueSegmentation
            self.segmenterVersion = segmenterVersion
            self.timestampMs = timestampMs
            self.outcome = outcome
        }
    }

    // Matches tools/segmenter/make_fixtures.py.
    static let fixtureRevision = "rev-1"
    // FixtureLoader's guard table: the real-checkpoint path.
    static let estimatorPath = "single_dominant"

    private static let log = Logger(subsystem: "ie.medata.app", category: "CaptureBundle")

    private let directoryURL: URL

    public init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    // Never throws: any failure is logged and swallowed so the attempt that
    // already completed is unaffected.
    public func record(_ payload: Payload) {
        do {
            let fixture = try Self.makeFixture(payload)
            let data: Data = try fixture.serializedBytes()
            let url = try uniqueBundleURL(
                timestampMs: payload.timestampMs, outcome: payload.outcome
            )
            // .atomic writes to a temporary file and renames, so a mid-write
            // kill can never leave a truncated bundle for a batch replay to
            // choke on.
            try data.write(to: url, options: .atomic)
            Self.log.info("event=bundle.recorded file=\(url.lastPathComponent, privacy: .public) bytes=\(data.count, privacy: .public)")
        } catch {
            Self.log.error("event=bundle.record.failed timestampMs=\(payload.timestampMs, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Fixture assembly

    // Static and internal so the round-trip test can exercise assembly and
    // the loader contract without touching the filesystem actor.
    static func makeFixture(_ payload: Payload) throws -> PbMealFixture {
        let capture = payload.captureResult
        let nadir = capture.nadirFrame

        var fx = PbMealFixture()
        fx.fixtureID = Self.filenameStem(
            timestampMs: payload.timestampMs, outcome: payload.outcome
        )
        fx.fixtureRevision = Self.fixtureRevision
        fx.paletteVersion = capture.paletteVersion
        fx.databaseEdition = capture.databaseEdition
        fx.segmenterCheckpointSha256 = payload.segmenterVersion
        fx.estimatorPath = Self.estimatorPath
        fx.capturePathCanonical = capture.capturePath.rawValue
        fx.gravity = nadir.gravity.pb
        fx.nadirIntrinsics = nadir.intrinsics.pb
        fx.nadirImage = try encodeRGB8PNG(nadir)
        if let depth = nadir.depth {
            fx.nadirDepth = depth.pb
        }
        // Probs/argmax copy byte-for-byte: ProbabilityTensor.bytes is already
        // FP16 LE HWC at camera resolution (post-processing resizes to the
        // frame dims the intrinsics declare — the FixtureRunner sizing
        // contract), ArgmaxMap.pixels is UInt8 [H, W].
        if let seg = payload.nadirSegmentation {
            fx.nadirProbs = seg.probabilities.bytes
            fx.nadirArgmax = seg.argmax.pixels
        }
        if let oblique = capture.obliqueFrame {
            fx.obliqueImage = try encodeRGB8PNG(oblique)
            fx.obliqueIntrinsics = oblique.intrinsics.pb
            fx.t1To2 = PipelineBridges.transform1To2(nadir: nadir, oblique: oblique).pb
            if let seg = payload.obliqueSegmentation {
                fx.obliqueProbs = seg.probabilities.bytes
                fx.obliqueArgmax = seg.argmax.pixels
            }
        }
        // Ground-truth fields stay at proto3 defaults; weighed truth is
        // back-filled off-device.
        return fx
    }

    // MARK: - PNG encoding

    enum EncodeError: Error {
        case unexpectedByteCount(expected: Int, got: Int)
        case cgImageCreationFailed
        case destinationCreationFailed
        case encodeFailed
    }

    // The fixture contract is PNG-encoded RGB8 in sRGB, top-left origin.
    // Device frames arrive BGRA8, so repack explicitly to 3-channel RGB
    // before encoding rather than trusting the encoder's channel handling
    // of an alpha-carrying CGImage.
    static func encodeRGB8PNG(_ frame: RawFrame) throws -> Data {
        let rgb = try rgb8Bytes(frame)
        guard let provider = CGDataProvider(data: rgb as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cgImage = CGImage(
                width: frame.imageWidth,
                height: frame.imageHeight,
                bitsPerComponent: 8,
                bitsPerPixel: 24,
                bytesPerRow: frame.imageWidth * 3,
                space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else {
            throw EncodeError.cgImageCreationFailed
        }
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw EncodeError.destinationCreationFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw EncodeError.encodeFailed
        }
        return out as Data
    }

    static func rgb8Bytes(_ frame: RawFrame) throws -> Data {
        let pixelCount = frame.imageWidth * frame.imageHeight
        let bytesPerPixel: Int
        switch frame.pixelFormat {
        case .rgb8: bytesPerPixel = 3
        case .bgra8, .rgba8: bytesPerPixel = 4
        }
        guard frame.imageBytes.count == pixelCount * bytesPerPixel else {
            throw EncodeError.unexpectedByteCount(
                expected: pixelCount * bytesPerPixel, got: frame.imageBytes.count
            )
        }
        if frame.pixelFormat == .rgb8 {
            return frame.imageBytes
        }
        var rgb = Data(count: pixelCount * 3)
        rgb.withUnsafeMutableBytes { dst in
            frame.imageBytes.withUnsafeBytes { src in
                let d = dst.bindMemory(to: UInt8.self).baseAddress!
                let s = src.bindMemory(to: UInt8.self).baseAddress!
                let bgra = frame.pixelFormat == .bgra8
                for p in 0..<pixelCount {
                    let si = p * 4
                    let di = p * 3
                    if bgra {
                        d[di] = s[si + 2]; d[di + 1] = s[si + 1]; d[di + 2] = s[si]
                    } else {
                        d[di] = s[si]; d[di + 1] = s[si + 1]; d[di + 2] = s[si + 2]
                    }
                }
            }
        }
        return rgb
    }

    // MARK: - Filenames

    // Zero-padded so FixtureLoader's lexicographic sort is chronological;
    // `.fixture` because that is the extension the loader filters on.
    static func filenameStem(timestampMs: Int64, outcome: String) -> String {
        String(format: "%013lld-%@", timestampMs, outcome)
    }

    private func uniqueBundleURL(timestampMs: Int64, outcome: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: directoryURL, withIntermediateDirectories: true
        )
        let stem = Self.filenameStem(timestampMs: timestampMs, outcome: outcome)
        var url = directoryURL.appendingPathComponent("\(stem).fixture")
        var suffix = 2
        // Collisions get a numeric suffix, never an overwrite.
        while FileManager.default.fileExists(atPath: url.path) {
            url = directoryURL.appendingPathComponent("\(stem)-\(suffix).fixture")
            suffix += 1
        }
        return url
    }
}

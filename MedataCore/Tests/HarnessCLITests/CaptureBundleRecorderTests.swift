#if HARNESS_ENABLED
import XCTest
import CaptureKit
import Foundation
import ImageIO
import PortableContracts
import Segmentation
@testable import HarnessCore
@testable import Pipeline

// capture-bundle-recorder smolspec, task 1: a device-recorded bundle must pass
// FixtureLoader unmodified and satisfy the FixtureRunner sizing contract
// (probs/argmax dimensions agree with the intrinsics the runner sizes from).
final class CaptureBundleRecorderTests: XCTestCase {

    private let segmenterVersion = "abc123def456"

    func testRecordedBundleLoadsAndSizingContractHolds() async throws {
        let dir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = CaptureBundleRecorder(directoryURL: dir)
        await recorder.record(makePayload(timestampMs: 1_752_800_000_000, outcome: "success"))

        let loaded = try FixtureLoader.load(from: dir, checkpointSHA256: segmenterVersion)
        XCTAssertEqual(loaded.count, 1)
        let fx = loaded[0]

        XCTAssertEqual(fx.estimatorPath, "single_dominant")
        XCTAssertEqual(fx.fixtureRevision, "rev-1")
        XCTAssertEqual(fx.segmenterCheckpointSha256, segmenterVersion)
        XCTAssertEqual(fx.capturePathCanonical, "single_view_lidar")
        XCTAssertEqual(fx.paletteVersion, "test-palette")
        XCTAssertEqual(fx.databaseEdition, "CoFID Test")
        XCTAssertEqual(fx.fixtureID, "1752800000000-success")
        XCTAssertTrue(fx.hasNadirDepth)

        // FixtureRunner sizes segmentation buffers from the intrinsics.
        let w = Int(fx.nadirIntrinsics.imageWidth)
        let h = Int(fx.nadirIntrinsics.imageHeight)
        let classes = palette.totalClasses
        XCTAssertEqual((w, h).0, 4)
        XCTAssertEqual(h, 3)
        XCTAssertEqual(fx.nadirProbs.count, w * h * classes * 2)
        XCTAssertEqual(fx.nadirArgmax.count, w * h)

        // The stored image decodes as a PNG at frame dimensions.
        let source = CGImageSourceCreateWithData(fx.nadirImage as CFData, nil)
        let image = source.flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        XCTAssertEqual(image?.width, 4)
        XCTAssertEqual(image?.height, 3)
    }

    // A refusal that never produced segmentation output still records a bundle
    // (RGB + depth remain valuable for re-segmentation); the single_dominant
    // loader path accepts empty probs.
    func testRefusedAttemptWithoutSegmentationRecords() async throws {
        let dir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = CaptureBundleRecorder(directoryURL: dir)
        await recorder.record(makePayload(
            timestampMs: 1_752_800_000_001, outcome: "refused", withSegmentation: false
        ))

        let loaded = try FixtureLoader.load(from: dir, checkpointSHA256: segmenterVersion)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].fixtureID, "1752800000001-refused")
        XCTAssertTrue(loaded[0].nadirProbs.isEmpty)
        XCTAssertFalse(loaded[0].nadirImage.isEmpty)
    }

    // Same-timestamp attempts must both survive: numeric suffix, no overwrite.
    func testFilenameCollisionAppendsSuffix() async throws {
        let dir = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let recorder = CaptureBundleRecorder(directoryURL: dir)
        await recorder.record(makePayload(timestampMs: 42, outcome: "success"))
        await recorder.record(makePayload(timestampMs: 42, outcome: "success"))

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertEqual(files, ["0000000000042-success-2.fixture", "0000000000042-success.fixture"].sorted())
    }

    // BGRA→RGB8 repack drops alpha and swaps channels.
    func testRGB8RepackFromBGRA() throws {
        let frame = makeFrame(imageBytes: Data([
            10, 20, 30, 255,   // B G R A → R G B = 30 20 10
            40, 50, 60, 255,
        ]), width: 2, height: 1)
        let rgb = try CaptureBundleRecorder.rgb8Bytes(frame)
        XCTAssertEqual([UInt8](rgb), [30, 20, 10, 60, 50, 40])
    }

    // MARK: - Helpers

    private let palette = ClassPalette(
        foodClasses: ["rice"], background: 1, unknownFood: 2,
        unsupportedLiquid: 3, version: "test-palette"
    )

    private func makeTemporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFrame(imageBytes: Data, width: Int, height: Int) -> RawFrame {
        RawFrame(
            imageBytes: imageBytes,
            pixelFormat: .bgra8,
            colourSpace: .sRGB,
            orientation: 1,
            imageWidth: width,
            imageHeight: height,
            timestampMonotonicNs: 0,
            intrinsics: CameraIntrinsics(
                fx: 100, fy: 100, cx: Float(width) / 2, cy: Float(height) / 2,
                imageWidth: width, imageHeight: height
            ),
            gravity: Vec3(x: 0, y: 0, z: -1),
            worldFromCamera: .identity,
            depth: DepthMap(
                depthBytesMm: Data(count: 2 * 2 * 4),
                confidenceBytes: Data(count: 2 * 2),
                width: 2, height: 2, rowStrideBytes: 8,
                depthIntrinsics: CameraIntrinsics(
                    fx: 50, fy: 50, cx: 1, cy: 1, imageWidth: 2, imageHeight: 2
                ),
                depthFromColour: .identity
            )
        )
    }

    private func makePayload(
        timestampMs: Int64, outcome: String, withSegmentation: Bool = true
    ) -> CaptureBundleRecorder.Payload {
        let width = 4, height = 3
        let frame = makeFrame(
            imageBytes: Data(count: width * height * 4), width: width, height: height
        )
        let capture = CaptureResult(
            capturePath: .singleViewLidar,
            lidar: LiDARStatus(available: true, foodRegionCoveragePercent: 80),
            nadirFrame: frame,
            obliqueFrame: nil,
            databaseEdition: "CoFID Test",
            paletteVersion: "test-palette"
        )
        let segmentation: SegmentationResult? = withSegmentation ? SegmentationResult(
            probabilities: ProbabilityTensor(
                bytes: Data(count: width * height * palette.totalClasses * 2),
                height: height, width: width,
                classes: palette.totalClasses, palette: palette
            ),
            argmax: ArgmaxMap(pixels: Data(count: width * height), height: height, width: width),
            perClassMeanProb: [:],
            sigmaSeg: 0.1
        ) : nil
        return CaptureBundleRecorder.Payload(
            captureResult: capture,
            nadirSegmentation: segmentation,
            obliqueSegmentation: nil,
            segmenterVersion: segmenterVersion,
            timestampMs: timestampMs,
            outcome: outcome
        )
    }
}
#endif

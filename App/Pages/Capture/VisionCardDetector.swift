import CaptureKit
import CardDetection
import CoreGraphics
import Foundation
import ImageIO
#if DEBUG
import os
#endif
import PortableContracts
// `@preconcurrency` silences Sendable warnings from the Vision module, which
// doesn't annotate `VNDetectRectanglesRequest`. The single instance lives on a
// class that's `@unchecked Sendable` and is only touched from this file's
// serial queue, so the closure capture is safe in practice.
@preconcurrency import Vision

#if DEBUG
// Same `ie.medata.app` / `Shutter` channel as the rest of the shutter-path logs
// (Pipeline `supportplane.start`, CaptureFlowModel `estimate.start` /
// `estimate.end`) so one Console predicate captures the full trail.
private let cardDetectorLog = Logger(subsystem: "ie.medata.app", category: "Shutter")
#endif

// Vision-backed `CardDetector` per spec `pipeline-real-device-correctness` design
// §VisionCardDetector. A single `VNDetectRectanglesRequest` is constructed at
// init time and reused on every detect() call so the second and later
// invocations pay warm-path latency (Reqs 5.6, 5.7). The wrapped request is
// configured for an ID-1 aspect envelope (53.98 / 85.60 ≈ 0.631 ± 10%).
//
// Concurrent invocation is not contemplated — `Pipeline.estimate` calls
// `detect(in:)` exactly once per shutter-tap and `CaptureFlowModel` schedules
// `warmup()` once at `.ready` entry. The internal serial queue is belt-and-
// braces against a future caller racing the two: it serialises access to the
// mutable `VNDetectRectanglesRequest.results` and moves the synchronous Vision
// work off the calling actor.
final class VisionCardDetector: CardDetector, @unchecked Sendable {
    private let request: VNDetectRectanglesRequest
    private let queue = DispatchQueue(
        label: "ie.medata.vision-card-detector",
        qos: .userInitiated
    )

    init() {
        let r = VNDetectRectanglesRequest()
        // ID-1 short/long ≈ 0.631. Vision's `minimumAspectRatio` / `maximumAspectRatio`
        // are the short-over-long ratio of the candidate quad; ±10 % absorbs
        // moderate perspective skew on a nadir capture.
        r.minimumAspectRatio = 0.55
        r.maximumAspectRatio = 0.70
        // 5 % of the shorter image edge. An ID-1 at ~30 cm on iPhone 13 Pro Max
        // occupies ~8 % of the shorter edge, so 5 % gives margin without admitting
        // tiny noise rectangles.
        r.minimumSize = 0.05
        // Brightest / largest single match wins; multi-card frames are out of scope
        // for this spec.
        r.maximumObservations = 1
        r.quadratureTolerance = 20
        self.request = r
    }

    // Req 5.7: pre-warm Vision's pipeline so the first shutter-tap of a session
    // pays warm-path latency only. Runs the configured request on a 64×64 black
    // BGRA buffer and drops the result.
    func warmup() async {
        let bytes = Self.blackBGRA(width: 64, height: 64)
        let request = self.request
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            queue.async {
                if let cg = Self.cgImageFromBGRA8(bytes, width: 64, height: 64) {
                    let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
                    _ = try? handler.perform([request])
                }
                cont.resume()
            }
        }
    }

    func detect(in frame: RawFrame) async -> [PixelCorner]? {
        let bytes = frame.imageBytes
        let width = frame.imageWidth
        let height = frame.imageHeight
        let request = self.request
        return await withCheckedContinuation { (cont: CheckedContinuation<[PixelCorner]?, Never>) in
            queue.async {
                cont.resume(returning: Self.runDetection(
                    request: request,
                    imageBytes: bytes,
                    width: width,
                    height: height
                ))
            }
        }
    }

    // MARK: - Detection

    private static func runDetection(
        request: VNDetectRectanglesRequest,
        imageBytes: Data,
        width: Int,
        height: Int
    ) -> [PixelCorner]? {
        let startNs = DispatchTime.now().uptimeNanoseconds

        guard let cg = cgImageFromBGRA8(imageBytes, width: width, height: height) else {
            logEnd(success: false, cornerCount: 0, startNs: startNs)
            return nil
        }
        // `.up` is correct because `RawFrame.imageBytes` is already in image-display
        // orientation per the `rawframe-rgb-conversion` spec (`imageWidth = 1920`,
        // `imageHeight = 1440` is the landscape colour grid). Vision's normalised
        // corner coordinates are then relative to that grid directly, so the only
        // axis swap on the way out is on Y.
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            logEnd(success: false, cornerCount: 0, startNs: startNs)
            return nil
        }
        guard let observation = request.results?.first else {
            logEnd(success: false, cornerCount: 0, startNs: startNs)
            return nil
        }

        // Vision returns observation corners in normalised image coordinates with
        // origin bottom-left and +y up. `PixelCorner` is in pixel coordinates with
        // origin top-left and +y down (matches `CardPoseSolver.solve`'s contract
        // at `CardPoseSolver.swift:11-16`). Only the Y axis flips — the X axis is
        // already left-to-right in both frames since we passed `.up` orientation.
        let w = Float(width)
        let h = Float(height)
        let corners: [PixelCorner] = [
            PixelCorner(Float(observation.topLeft.x) * w,     (1 - Float(observation.topLeft.y))     * h),
            PixelCorner(Float(observation.topRight.x) * w,    (1 - Float(observation.topRight.y))    * h),
            PixelCorner(Float(observation.bottomRight.x) * w, (1 - Float(observation.bottomRight.y)) * h),
            PixelCorner(Float(observation.bottomLeft.x) * w,  (1 - Float(observation.bottomLeft.y))  * h)
        ]
        logEnd(success: true, cornerCount: corners.count, startNs: startNs)
        return corners
    }

    private static func logEnd(success: Bool, cornerCount: Int, startNs: UInt64) {
        #if DEBUG
        let elapsedNs = DispatchTime.now().uptimeNanoseconds - startNs
        let elapsedMs = Int(elapsedNs / 1_000_000)
        cardDetectorLog.debug(
            "event=carddetect.end success=\(success, privacy: .public) cornerCount=\(cornerCount, privacy: .public) latencyMs=\(elapsedMs, privacy: .public)"
        )
        #endif
    }

    // MARK: - Pixel buffer helpers

    private static func blackBGRA(width: Int, height: Int) -> Data {
        let bpp = 4
        var bytes = [UInt8](repeating: 0, count: width * height * bpp)
        var i = 3
        while i < bytes.count {
            bytes[i] = 255
            i += bpp
        }
        return Data(bytes)
    }

    // BGRA8 row-major bytes → CGImage. Layout matches the `RawFrame.imageBytes`
    // contract from the `rawframe-rgb-conversion` spec: byte order B, G, R, A;
    // no row padding. `byteOrder32Little` + `premultipliedFirst` is the canonical
    // CG mapping for kCVPixelFormatType_32BGRA.
    private static func cgImageFromBGRA8(_ bytes: Data, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        guard bytes.count >= bytesPerRow * height else { return nil }
        let nsData = bytes as NSData
        guard let provider = CGDataProvider(data: nsData) else { return nil }
        let colourSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: CGBitmapInfo = [
            .byteOrder32Little,
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        ]
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colourSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

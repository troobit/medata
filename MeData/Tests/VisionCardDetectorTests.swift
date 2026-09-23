import CaptureKit
import CardDetection
import Foundation
import PortableContracts
import Testing
@testable import MeData

// Tests for the App-target VisionCardDetector per spec
// `pipeline-real-device-correctness` design §VisionCardDetector and Reqs 5.1, 5.4,
// 5.6, 8.5. The synthetic fixture is a 1920×1440 BGRA buffer with a single bright
// ID-1-aspect rectangle on a black background — exactly the shape Vision is asked
// to find on a real nadir frame, minus the noise.
//
// The on-device latency budget (Req 5.6) is verified manually per
// `prerequisites.md`; this suite asserts the on-host warm latency stays inside the
// same envelope so a regression in detector wiring trips CI rather than waiting for
// a tethered run.

@Suite("VisionCardDetector synthetic ID-1 detection")
struct VisionCardDetectorTests {

    // Centred ID-1-aspect rectangle on a 1920×1440 grid. Width 400 px, height 252
    // px → aspect 0.63 (ID-1 is 53.98/85.60 ≈ 0.631). Both corners well inside the
    // frame so the test isn't sensitive to edge-clipping in Vision.
    private static let rectX = 760
    private static let rectY = 594
    private static let rectW = 400
    private static let rectH = 252

    @Test("detects a synthesised ID-1 rectangle and returns corners in TL→TR→BR→BL order")
    func detectsId1Rectangle() async {
        let detector = VisionCardDetector()
        await detector.warmup()
        let frame = makeRawFrame(imageBytes: makeRectangleBGRA(
            rect: (Self.rectX, Self.rectY, Self.rectW, Self.rectH)
        ))

        guard let corners = await detector.detect(in: frame) else {
            Issue.record("Vision returned no rectangle for the synthetic ID-1 fixture")
            return
        }

        #expect(corners.count == 4)
        guard corners.count == 4 else { return }

        // Tolerance: Vision's quadratureTolerance is set to 20° in the design and
        // its rectangle edge detection on a synthetic hard-edged fixture sits
        // within a few pixels of truth. ±8 px keeps the assertion meaningful
        // without spuriously failing on filter ringing at the rectangle edge.
        let tolerance: Float = 8
        let expected: [(label: String, u: Float, v: Float)] = [
            ("TL", Float(Self.rectX),                      Float(Self.rectY)),
            ("TR", Float(Self.rectX + Self.rectW),         Float(Self.rectY)),
            ("BR", Float(Self.rectX + Self.rectW),         Float(Self.rectY + Self.rectH)),
            ("BL", Float(Self.rectX),                      Float(Self.rectY + Self.rectH))
        ]
        for (i, e) in expected.enumerated() {
            #expect(
                abs(corners[i].u - e.u) <= tolerance,
                "\(e.label).u: got \(corners[i].u), expected \(e.u) ± \(tolerance)"
            )
            #expect(
                abs(corners[i].v - e.v) <= tolerance,
                "\(e.label).v: got \(corners[i].v), expected \(e.v) ± \(tolerance)"
            )
        }
    }

    @Test("returns nil for an unrecognisable (all-black) buffer — Req 5.4")
    func emptyBufferReturnsNil() async {
        let detector = VisionCardDetector()
        await detector.warmup()
        let frame = makeRawFrame(imageBytes: makeRectangleBGRA(rect: nil))

        let corners = await detector.detect(in: frame)
        #expect(corners == nil)
    }

    @Test("warm detection completes within the on-device budget on the synthetic fixture — Req 5.6")
    func warmDetectionWithinBudget() async {
        let detector = VisionCardDetector()
        await detector.warmup()
        let frame = makeRawFrame(imageBytes: makeRectangleBGRA(
            rect: (Self.rectX, Self.rectY, Self.rectW, Self.rectH)
        ))

        let clock = ContinuousClock()
        let start = clock.now
        _ = await detector.detect(in: frame)
        let elapsed = clock.now - start

        // Req 5.6 caps warm detection at 250 ms on iPhone 13 Pro Max. The on-host
        // run is dev-machine dependent so the assertion uses a roomier 750 ms
        // ceiling — still tight enough to catch a regression that adds an extra
        // pipeline pass or trips a cold-path code branch.
        #expect(
            elapsed <= .milliseconds(750),
            "warm detect() took \(elapsed) — exceeds the host CI ceiling of 750 ms"
        )
    }
}

// MARK: - Fixture builders

private func makeRawFrame(
    imageBytes: Data,
    width: Int = 1920,
    height: Int = 1440
) -> RawFrame {
    let intrinsics = CameraIntrinsics(
        fx: 1500, fy: 1500,
        cx: Float(width) / 2, cy: Float(height) / 2,
        distortion: [],
        imageWidth: width, imageHeight: height
    )
    return RawFrame(
        imageBytes: imageBytes,
        pixelFormat: .bgra8,
        colourSpace: .sRGB,
        orientation: 1,
        imageWidth: width, imageHeight: height,
        timestampMonotonicNs: 1_000_000_000,
        intrinsics: intrinsics,
        gravity: Vec3(0, -1, 0),
        worldFromCamera: .identity,
        depth: nil
    )
}

// Build a 1920×1440 BGRA buffer with a single white rectangle on a black
// background. Memory layout matches what `PixelBufferAdapter` produces from a
// real `ARFrame.capturedImage` per the rawframe-rgb-conversion spec: byte order
// B, G, R, A; row-major, no padding.
private func makeRectangleBGRA(
    width: Int = 1920,
    height: Int = 1440,
    rect: (x: Int, y: Int, w: Int, h: Int)?
) -> Data {
    let bpp = 4
    var bytes = [UInt8](repeating: 0, count: width * height * bpp)
    // Alpha=255 on every pixel — black BGRA pixels are (0,0,0,255), not all-zero,
    // which matches what the BGRA producer emits and keeps Vision from treating
    // the buffer as fully transparent.
    var i = 3
    while i < bytes.count {
        bytes[i] = 255
        i += bpp
    }
    guard let r = rect else { return Data(bytes) }
    for y in r.y..<(r.y + r.h) {
        let rowOffset = y * width * bpp
        for x in r.x..<(r.x + r.w) {
            let off = rowOffset + x * bpp
            bytes[off + 0] = 255   // B
            bytes[off + 1] = 255   // G
            bytes[off + 2] = 255   // R
            bytes[off + 3] = 255   // A
        }
    }
    return Data(bytes)
}

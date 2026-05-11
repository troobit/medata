import XCTest
@testable import Segmentation
@testable import CaptureKit

final class PreProcessingTests: XCTestCase {

    // MARK: - Pixel-format canonicalisation (Step 1 of §6.5, P3 / P9 fix)

    func testRGB8Canonicalisation_NoOp() {
        let src = Data([
            100, 150, 200,   10,  20,  30,
              5,   6,   7,   40,  50,  60
        ])
        let rgb = canonicaliseToRGB8(src, format: .rgb8, width: 2, height: 2)
        XCTAssertEqual(rgb, src)
    }

    func testBGRA8Canonicalisation_ChannelSwapAndAlphaDrop() {
        // BGRA8 layout: each pixel is [B, G, R, A]. Output is RGB.
        let src = Data([
            100, 150, 200, 255,   10,  20,  30, 250,
              5,   6,   7, 240,   40,  50,  60, 200
        ])
        let rgb = canonicaliseToRGB8(src, format: .bgra8, width: 2, height: 2)
        let expected = Data([
            200, 150, 100,   30,  20,  10,
              7,   6,   5,   60,  50,  40
        ])
        XCTAssertEqual(rgb, expected)
    }

    func testRGBA8Canonicalisation_AlphaDropPreservesChannelOrder() {
        let src = Data([
            100, 150, 200, 255,   10,  20,  30, 250,
              5,   6,   7, 240,   40,  50,  60, 200
        ])
        let rgb = canonicaliseToRGB8(src, format: .rgba8, width: 2, height: 2)
        let expected = Data([
            100, 150, 200,   10,  20,  30,
              5,   6,   7,   40,  50,  60
        ])
        XCTAssertEqual(rgb, expected)
    }

    // MARK: - Letterbox resize (Steps 2–3 of §6.5)

    func testLetterboxResize_WideAspectProducesExpectedDims() throws {
        // 800×400 input, target 513 → scale = 513/800 ≈ 0.64125 → (513, 257).
        let w = 800, h = 400
        let bytes = Data(repeating: 128, count: w * h * 3)
        let out = try SegmenterPreProcessor.process(
            imageBytes: bytes, pixelFormat: .rgb8, width: w, height: h, targetSize: 513
        )
        XCTAssertEqual(out.targetSize, 513)
        XCTAssertEqual(out.scaledWidth, 513)
        XCTAssertEqual(out.scaledHeight, 257)
        // FP16 buffer is HWC row-major: target × target × 3 × 2 bytes.
        XCTAssertEqual(out.bytes.count, 513 * 513 * 3 * 2)
    }

    func testLetterboxResize_TallAspectProducesExpectedDims() throws {
        // 400×800 input, target 513 → (257, 513).
        let w = 400, h = 800
        let bytes = Data(repeating: 128, count: w * h * 3)
        let out = try SegmenterPreProcessor.process(
            imageBytes: bytes, pixelFormat: .rgb8, width: w, height: h, targetSize: 513
        )
        XCTAssertEqual(out.scaledWidth, 257)
        XCTAssertEqual(out.scaledHeight, 513)
    }

    func testLetterboxResize_SquareAspect() throws {
        let bytes = Data(repeating: 128, count: 600 * 600 * 3)
        let out = try SegmenterPreProcessor.process(
            imageBytes: bytes, pixelFormat: .rgb8, width: 600, height: 600, targetSize: 513
        )
        XCTAssertEqual(out.scaledWidth, 513)
        XCTAssertEqual(out.scaledHeight, 513)
    }

    // MARK: - Post-normalisation padding (Step 6 of §6.5)

    func testLetterboxPad_HoldsPostNormalisationBlack() throws {
        // 400×800 input → (257, 513). The right-hand 256 columns of the padded canvas
        // are pure pad value `(0 − mean[c]) / std[c]`.
        let w = 400, h = 800
        let bytes = Data(repeating: 128, count: w * h * 3)
        let out = try SegmenterPreProcessor.process(
            imageBytes: bytes, pixelFormat: .rgb8, width: w, height: h, targetSize: 513
        )
        let pad: (Float, Float, Float) = (
            (0 - 0.485) / 0.229,
            (0 - 0.456) / 0.224,
            (0 - 0.406) / 0.225
        )
        // Sample a pixel deep in the pad region (column 400, row 250).
        let (r, g, b) = sampleFP16Pixel(in: out.bytes, x: 400, y: 250, width: 513)
        XCTAssertEqual(r, pad.0, accuracy: 5e-3)
        XCTAssertEqual(g, pad.1, accuracy: 5e-3)
        XCTAssertEqual(b, pad.2, accuracy: 5e-3)
    }

    func testNormalisation_BlackInputMatchesPadValue() throws {
        // All-black image: (0 − mean) / std for every pixel — same value as the pad fill,
        // by design (so the model can't distinguish padding from genuine black input).
        let w = 100, h = 100
        let bytes = Data(repeating: 0, count: w * h * 3)
        let out = try SegmenterPreProcessor.process(
            imageBytes: bytes, pixelFormat: .rgb8, width: w, height: h, targetSize: 513
        )
        let pad: (Float, Float, Float) = (
            (0 - 0.485) / 0.229,
            (0 - 0.456) / 0.224,
            (0 - 0.406) / 0.225
        )
        // Centre of the scaled region.
        let (r, g, b) = sampleFP16Pixel(in: out.bytes, x: 25, y: 25, width: 513)
        XCTAssertEqual(r, pad.0, accuracy: 5e-3)
        XCTAssertEqual(g, pad.1, accuracy: 5e-3)
        XCTAssertEqual(b, pad.2, accuracy: 5e-3)
    }

    func testInvalidInputBytes_Throws() {
        // BGRA8 expects 4 bytes/pixel; a 3-byte/pixel buffer of the wrong size must throw.
        let bytes = Data(repeating: 0, count: 10 * 10 * 3)
        XCTAssertThrowsError(try SegmenterPreProcessor.process(
            imageBytes: bytes, pixelFormat: .bgra8, width: 10, height: 10
        )) { err in
            guard case .invalidInputDimensions = err as? SegmentationError else {
                return XCTFail("expected invalidInputDimensions, got \(err)")
            }
        }
    }

    // MARK: - helpers

    private func sampleFP16Pixel(in data: Data, x: Int, y: Int, width: Int) -> (Float, Float, Float) {
        let pixIdx = y * width + x
        return data.withUnsafeBytes { rawBuf in
            let f = rawBuf.bindMemory(to: Float16.self).baseAddress!
            return (Float(f[pixIdx * 3]), Float(f[pixIdx * 3 + 1]), Float(f[pixIdx * 3 + 2]))
        }
    }
}

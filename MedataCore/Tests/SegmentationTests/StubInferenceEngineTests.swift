import XCTest
@testable import Segmentation
@testable import CaptureKit
import PortableContracts

// Tests for the Phase 1 dev-stub segmenter (Req §23.2, Decision 42).
// Verifies the engine produces a deterministic per-pixel probability tensor
// that assigns ≥ 0.99 to a single non-background class, that the FP16 HWC
// row-major layout from design §3.5 / §6.0 round-trips cleanly through
// CoreMLSegmenter, and that the engine meets the < 50 ms per-view budget.
final class StubInferenceEngineTests: XCTestCase {

    private func makePalette(numFoodClasses: Int = 24) -> ClassPalette {
        ClassPalette(
            foodClasses: (0..<numFoodClasses).map { "food_\($0)" },
            background: numFoodClasses,
            unknownFood: numFoodClasses + 1,
            unsupportedLiquid: numFoodClasses + 2,
            version: "v1"
        )
    }

    private func makeFrame(width: Int = 32, height: Int = 32) -> RawFrame {
        RawFrame(
            imageBytes: Data(repeating: 128, count: width * height * 4),
            pixelFormat: .bgra8,
            colourSpace: .sRGB,
            orientation: 1,
            imageWidth: width, imageHeight: height,
            timestampMonotonicNs: 1,
            intrinsics: CameraIntrinsics(
                fx: 1500, fy: 1500,
                cx: Float(width) / 2, cy: Float(height) / 2,
                distortion: [], imageWidth: width, imageHeight: height
            ),
            gravity: Vec3(0, -1, 0),
            worldFromCamera: .identity,
            depth: nil
        )
    }

    // MARK: - Determinism

    // Same palette + targetSize → identical logits across runs. The stub does not
    // depend on the input bytes (design §3.5: it bypasses image pre-processing),
    // so the only inputs that can vary the output are palette and dominantClass.
    func testRunInferenceIsDeterministicAcrossRuns() async throws {
        let palette = makePalette()
        let stub = StubInferenceEngine(palette: palette)
        let targetSize = 16
        let bytes = Data(repeating: 0, count: targetSize * targetSize * 3 * 2)
        let (a, ca) = try await stub.runInference(inputFP16Bytes: bytes, targetSize: targetSize)
        let (b, cb) = try await stub.runInference(inputFP16Bytes: bytes, targetSize: targetSize)
        XCTAssertEqual(ca, cb)
        XCTAssertEqual(ca, palette.totalClasses)
        XCTAssertEqual(a, b, "two runs with the same palette + targetSize must produce identical logits")
    }

    func testRunInferenceIgnoresInputBytes() async throws {
        // The stub bypasses image pre-processing entirely (design §3.5). Two runs
        // with different inputs but the same shape produce identical outputs.
        let palette = makePalette()
        let stub = StubInferenceEngine(palette: palette)
        let targetSize = 16
        let zeros = Data(repeating: 0, count: targetSize * targetSize * 3 * 2)
        let ones = Data(repeating: 0xFF, count: targetSize * targetSize * 3 * 2)
        let (a, _) = try await stub.runInference(inputFP16Bytes: zeros, targetSize: targetSize)
        let (b, _) = try await stub.runInference(inputFP16Bytes: ones, targetSize: targetSize)
        XCTAssertEqual(a, b)
    }

    // MARK: - Argmax and probability mass

    func testArgmaxOfEveryPixelEqualsDominantClass_defaultDominantZero() async throws {
        let palette = makePalette()
        let stub = StubInferenceEngine(palette: palette)             // default dominantClass = 0
        let segmenter = CoreMLSegmenter(modelPath: "/dev/null", palette: palette, engine: stub)
        let frame = makeFrame()
        let result = try await segmenter.segment(frame)
        let unique = uniqueClassIds(in: result.argmax)
        XCTAssertEqual(unique, [0], "every pixel should be labelled the dominant class (default 0)")
    }

    func testArgmaxOfEveryPixelEqualsDominantClass_explicitDominantFive() async throws {
        let palette = makePalette()
        let stub = StubInferenceEngine(palette: palette, dominantClass: 5)
        let segmenter = CoreMLSegmenter(modelPath: "/dev/null", palette: palette, engine: stub)
        let frame = makeFrame()
        let result = try await segmenter.segment(frame)
        let unique = uniqueClassIds(in: result.argmax)
        XCTAssertEqual(unique, [5])
    }

    // Per Req §23.2: mass at `dominantClass` ≥ 0.99 and remaining classes sum to ≤ 0.01.
    // After softmax in post-processing the per-pixel distribution at the dominant
    // class is ≥ 0.99; the remaining 1-mass is shared across the other classes.
    func testDominantClassProbabilityAtLeastZeroPointNineNine() async throws {
        let palette = makePalette()
        let stub = StubInferenceEngine(palette: palette, dominantClass: 0)
        let segmenter = CoreMLSegmenter(modelPath: "/dev/null", palette: palette, engine: stub)
        let frame = makeFrame()
        let result = try await segmenter.segment(frame)
        let probs = result.probabilities
        let classes = probs.classes
        let pixelCount = probs.height * probs.width
        XCTAssertEqual(probs.bytes.count, pixelCount * classes * 2,
                       "FP16 byte size must equal H*W*C*2 (portable HWC row-major contract)")
        let decoded = FP16Bytes.decode(probs.bytes, count: pixelCount * classes)
        for pixel in 0..<pixelCount {
            let off = pixel * classes
            let mDominant = decoded[off + 0]
            XCTAssertGreaterThanOrEqual(
                mDominant, 0.99,
                "pixel \(pixel) dominantClass mass \(mDominant) below 0.99 contract"
            )
            var remaining: Float = 0
            for c in 1..<classes { remaining += decoded[off + c] }
            XCTAssertLessThanOrEqual(
                remaining, 0.01 + 1e-5,
                "pixel \(pixel) remaining-class sum \(remaining) above 0.01 contract"
            )
        }
    }

    // MARK: - Portable layout

    func testProbabilityTensorPortableLayoutHWCRowMajor() async throws {
        let palette = makePalette()
        let stub = StubInferenceEngine(palette: palette)
        let segmenter = CoreMLSegmenter(modelPath: "/dev/null", palette: palette, engine: stub)
        let width = 28, height = 20
        let frame = makeFrame(width: width, height: height)
        let result = try await segmenter.segment(frame)
        XCTAssertEqual(result.probabilities.height, height)
        XCTAssertEqual(result.probabilities.width, width)
        XCTAssertEqual(result.probabilities.classes, palette.totalClasses)
        // HWC row-major: bytes = H*W*C*2 (FP16 little-endian per §6.0)
        XCTAssertEqual(result.probabilities.bytes.count,
                       height * width * palette.totalClasses * 2)
        XCTAssertEqual(result.probabilities.palette, palette)
        // Argmax map has the same H*W contract.
        XCTAssertEqual(result.argmax.pixels.count, height * width)
    }

    // MARK: - Performance (Req §23.2: under 50 ms on v1 hardware)

    func testInferenceCompletesUnderFiftyMilliseconds() async throws {
        let palette = makePalette()
        let stub = StubInferenceEngine(palette: palette)
        let targetSize = SegmenterPreProcessor.defaultTargetSize
        let bytes = Data(repeating: 0, count: targetSize * targetSize * 3 * 2)
        // Warm-up run to amortise first-call allocation.
        _ = try await stub.runInference(inputFP16Bytes: bytes, targetSize: targetSize)
        let start = Date()
        _ = try await stub.runInference(inputFP16Bytes: bytes, targetSize: targetSize)
        let elapsed = Date().timeIntervalSince(start)
        // Req §23.2 caps at 50 ms on the v1 device. macOS / simulator beats this
        // comfortably; the assertion guards against accidental O(targetSize²·C²)
        // regressions in the stub implementation.
        XCTAssertLessThan(elapsed, 0.050,
                          "stub took \(String(format: "%.3f", elapsed * 1000)) ms; budget is 50 ms (Req §23.2)")
    }

    // MARK: - Helpers

    private func uniqueClassIds(in map: ArgmaxMap) -> Set<UInt8> {
        var ids = Set<UInt8>()
        map.pixels.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<map.pixels.count { ids.insert(buf[i]) }
        }
        return ids
    }
}

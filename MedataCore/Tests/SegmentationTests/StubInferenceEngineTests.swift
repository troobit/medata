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

    // MARK: - Argmax distribution (centred-ellipse predicate, Decision 8)

    // Pre-spec all-ones argmax (`unique == [0]`) is replaced by a two-class
    // distribution: dominantClass inside the centred ellipse, background
    // outside. The exact pixel count is asserted by the area test below.
    func testArgmaxIsDominantOrBackground_defaultDominantZero() async throws {
        let palette = makePalette()
        let stub = StubInferenceEngine(palette: palette)             // default dominantClass = 0
        let segmenter = CoreMLSegmenter(modelPath: "/dev/null", palette: palette, engine: stub)
        let frame = makeFrame()
        let result = try await segmenter.segment(frame)
        let unique = uniqueClassIds(in: result.argmax)
        XCTAssertEqual(unique, Set([UInt8(0), UInt8(palette.background)]),
                       "stub should produce dominantClass inside the ellipse and background outside")
    }

    func testArgmaxIsDominantOrBackground_explicitDominantFive() async throws {
        let palette = makePalette()
        let stub = StubInferenceEngine(palette: palette, dominantClass: 5)
        let segmenter = CoreMLSegmenter(modelPath: "/dev/null", palette: palette, engine: stub)
        let frame = makeFrame()
        let result = try await segmenter.segment(frame)
        let unique = uniqueClassIds(in: result.argmax)
        XCTAssertEqual(unique, Set([UInt8(5), UInt8(palette.background)]))
    }

    // Decision 8: the dev-stub returns a centred-ellipse food region covering
    // 30 ± 2 % of the input frame area. Asserted at the inference layer (raw
    // logits) so the test is decoupled from CoreMLSegmenter's post-process
    // downsampling. Iterates a 256×256 logits buffer at targetSize = 256.
    func testFoodPixelCountIsThirtyPercentOfFrameAtTargetSize256() async throws {
        let palette = makePalette()
        let dominantClass = 0
        let stub = StubInferenceEngine(palette: palette, dominantClass: dominantClass)
        let targetSize = 256
        let bytes = Data(repeating: 0, count: targetSize * targetSize * 3 * 2)
        let (logits, classes) = try await stub.runInference(
            inputFP16Bytes: bytes, targetSize: targetSize
        )
        XCTAssertEqual(classes, palette.totalClasses)
        var foodPixels = 0
        for pixel in 0..<(targetSize * targetSize) {
            let off = pixel * classes
            var bestClass = 0
            var bestLogit: Float = -.infinity
            for c in 0..<classes where logits[off + c] > bestLogit {
                bestLogit = logits[off + c]
                bestClass = c
            }
            if bestClass == dominantClass { foodPixels += 1 }
        }
        let totalPixels = targetSize * targetSize
        let coverage = Float(foodPixels) / Float(totalPixels)
        XCTAssertGreaterThanOrEqual(coverage, 0.28,
                                    "food coverage \(coverage) below Decision 8 floor 28 %")
        XCTAssertLessThanOrEqual(coverage, 0.32,
                                 "food coverage \(coverage) above Decision 8 ceiling 32 %")
    }

    // Inside-ellipse pixels carry ≥ 0.99 mass at dominantClass; outside-ellipse
    // pixels carry ≥ 0.99 mass at the palette's background class. Verified at
    // the CoreMLSegmenter output (post-softmax) to mirror downstream consumers.
    func testInsideEllipseDominantAndOutsideEllipseBackgroundMassAreAtLeast099() async throws {
        let palette = makePalette()
        let dominantClass = 0
        let stub = StubInferenceEngine(palette: palette, dominantClass: dominantClass)
        let segmenter = CoreMLSegmenter(modelPath: "/dev/null", palette: palette, engine: stub)
        let frame = makeFrame()
        let result = try await segmenter.segment(frame)
        let probs = result.probabilities
        let classes = probs.classes
        let pixelCount = probs.height * probs.width
        XCTAssertEqual(probs.bytes.count, pixelCount * classes * 2,
                       "FP16 byte size must equal H*W*C*2 (portable HWC row-major contract)")
        let decoded = FP16Bytes.decode(probs.bytes, count: pixelCount * classes)
        let argmaxBytes = result.argmax.pixels
        argmaxBytes.withUnsafeBytes { rawArg in
            let argBuf = rawArg.bindMemory(to: UInt8.self).baseAddress!
            for pixel in 0..<pixelCount {
                let off = pixel * classes
                let label = Int(argBuf[pixel])
                if label == dominantClass {
                    let mDominant = decoded[off + dominantClass]
                    XCTAssertGreaterThanOrEqual(
                        mDominant, 0.99,
                        "inside-ellipse pixel \(pixel) dominant mass \(mDominant) below 0.99"
                    )
                } else {
                    XCTAssertEqual(label, palette.background,
                                   "outside-ellipse pixel \(pixel) labelled \(label); expected background")
                    let mBackground = decoded[off + palette.background]
                    XCTAssertGreaterThanOrEqual(
                        mBackground, 0.99,
                        "outside-ellipse pixel \(pixel) background mass \(mBackground) below 0.99"
                    )
                }
            }
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

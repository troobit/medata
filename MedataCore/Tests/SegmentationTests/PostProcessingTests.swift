import XCTest
@testable import Segmentation

final class PostProcessingTests: XCTestCase {

    // MARK: - helpers

    /// Test palette: 2 food classes + bg(2) + unknownFood(3) + unsupportedLiquid(4) = 5 classes.
    func makeTestPalette(numFoodClasses: Int = 2) -> ClassPalette {
        ClassPalette(
            foodClasses: (0..<numFoodClasses).map { "food_\($0)" },
            background: numFoodClasses,
            unknownFood: numFoodClasses + 1,
            unsupportedLiquid: numFoodClasses + 2,
            version: "test_v1"
        )
    }

    /// Build a one-hot logits buffer (large magnitude → softmax peak ≈ 1.0).
    func makeOneHotLogits(
        targetSize: Int, classes: Int,
        labelAt: (Int, Int) -> Int,
        magnitude: Float = 12
    ) -> [Float] {
        var logits = [Float](repeating: 0, count: targetSize * targetSize * classes)
        for y in 0..<targetSize {
            for x in 0..<targetSize {
                let lab = labelAt(y, x)
                logits[(y * targetSize + x) * classes + lab] = magnitude
            }
        }
        return logits
    }

    // MARK: - Resize-back (Step 10 of §6.5)

    func testResizeBackToOriginalDimensions() throws {
        let palette = makeTestPalette()
        let targetSize = 8
        let classes = palette.totalClasses
        // Half-full padded canvas: scaledW=8, scaledH=4 (from a 16×8 original).
        let logits = makeOneHotLogits(targetSize: targetSize, classes: classes) { _, _ in 0 }
        let out = try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: 8, scaledHeight: 4,
            originalWidth: 16, originalHeight: 8,
            palette: palette
        )
        XCTAssertEqual(out.probabilities.height, 8)
        XCTAssertEqual(out.probabilities.width, 16)
        XCTAssertEqual(out.probabilities.classes, classes)
        XCTAssertEqual(out.argmax.height, 8)
        XCTAssertEqual(out.argmax.width, 16)
        XCTAssertEqual(out.probabilities.bytes.count, 8 * 16 * classes * 2)
        // Every pixel argmaxes to class 0.
        out.argmax.pixels.forEach { XCTAssertEqual($0, 0) }
    }

    func testResizeBackPreservesPixelCentreAlignment() throws {
        let palette = makeTestPalette()
        let targetSize = 4
        let classes = palette.totalClasses
        // Left half → class 0, right half → class 1 (in padded space).
        let logits = makeOneHotLogits(targetSize: targetSize, classes: classes) { _, x in
            x < 2 ? 0 : 1
        }
        let out = try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: 4, scaledHeight: 4,
            originalWidth: 4, originalHeight: 4,
            palette: palette
        )
        // Identity resize: left half labelled 0, right half labelled 1.
        out.argmax.pixels.withUnsafeBytes { rawBuf in
            let buf = rawBuf.bindMemory(to: UInt8.self)
            for y in 0..<4 {
                XCTAssertEqual(buf[y * 4 + 0], 0)
                XCTAssertEqual(buf[y * 4 + 1], 0)
                XCTAssertEqual(buf[y * 4 + 2], 1)
                XCTAssertEqual(buf[y * 4 + 3], 1)
            }
        }
    }

    // MARK: - σ_seg (Step 12, M8 pin)

    func testSigmaSeg_ExcludesSpecialClasses() throws {
        let palette = makeTestPalette()
        let targetSize = 4
        let classes = palette.totalClasses
        // Rows 0–1 → food classes; row 2 → unknown_food; row 3 → unsupported_liquid.
        // All four rows are in silhouette (q[bg] ≈ 0 because softmax peak is on a non-bg class).
        let logits = makeOneHotLogits(targetSize: targetSize, classes: classes) { y, _ in
            switch y {
            case 0: return 0
            case 1: return 1
            case 2: return palette.unknownFood
            default: return palette.unsupportedLiquid
            }
        }
        let out = try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: targetSize, scaledHeight: targetSize,
            originalWidth: targetSize, originalHeight: targetSize,
            palette: palette
        )
        // σ_seg averages only the 8 food pixels in rows 0–1.
        XCTAssertEqual(out.sigmaSeg, 0.99999, accuracy: 0.001)
        // Per-class mean covers only the two food classes.
        XCTAssertEqual(out.perClassMeanProb.count, 2)
        XCTAssertNotNil(out.perClassMeanProb["food_0"])
        XCTAssertNotNil(out.perClassMeanProb["food_1"])
    }

    func testSigmaSeg_IsMeanOfTopProbabilityAcrossAllClasses() throws {
        // Build a tensor where the top probability per food pixel is exactly 0.6 so the
        // mean is verifiable.
        let palette = makeTestPalette()
        let targetSize = 2
        let classes = palette.totalClasses
        var logits = [Float](repeating: 0, count: targetSize * targetSize * classes)
        // Each pixel: food_0 = 0.6, food_1 = 0.1, bg = 0.1, unknown = 0.1, liq = 0.1.
        // Use log-probs as logits (softmax recovers them).
        let target: [Float] = [0.6, 0.1, 0.1, 0.1, 0.1]
        for pix in 0..<(targetSize * targetSize) {
            for c in 0..<classes { logits[pix * classes + c] = Foundation.log(target[c]) }
        }
        let out = try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: targetSize, scaledHeight: targetSize,
            originalWidth: targetSize, originalHeight: targetSize,
            palette: palette
        )
        // top prob over all classes is 0.6 → σ_seg = 0.6.
        XCTAssertEqual(out.sigmaSeg, 0.6, accuracy: 1e-3)
    }

    // MARK: - Refusal predicate (M8 / edge case 3)

    func testNoFoodPixels_RefusalAlignedWithSilhouetteTest() throws {
        // Pure background (high-magnitude one-hot at bg) → q[bg] ≈ 1 → silhouette empty.
        let palette = makeTestPalette()
        let targetSize = 4
        let classes = palette.totalClasses
        let logits = makeOneHotLogits(targetSize: targetSize, classes: classes) { _, _ in
            palette.background
        }
        XCTAssertThrowsError(try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: targetSize, scaledHeight: targetSize,
            originalWidth: targetSize, originalHeight: targetSize,
            palette: palette
        )) { error in
            XCTAssertEqual(error as? SegmentationError, .noFoodPixels)
        }
    }

    func testRefusal_NotTriggeredByArgmaxBg_IfSilhouetteSatisfied() throws {
        // Pixel where bg is argmax (q[bg] = 0.45) but silhouette passes (1 − 0.45 = 0.55).
        // Per design §6.5 / §5 refusal table: do NOT throw noFoodPixels — silhouette is non-empty.
        let palette = makeTestPalette()
        let targetSize = 4
        let classes = palette.totalClasses
        let target: [Float] = [0.30, 0.20, 0.45, 0.025, 0.025]   // food_0, food_1, bg, unk, liq
        var logits = [Float](repeating: 0, count: targetSize * targetSize * classes)
        for pix in 0..<(targetSize * targetSize) {
            for c in 0..<classes { logits[pix * classes + c] = Foundation.log(target[c]) }
        }
        let out = try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: targetSize, scaledHeight: targetSize,
            originalWidth: targetSize, originalHeight: targetSize,
            palette: palette
        )
        // Every pixel argmaxes to bg → 0 food pixels for σ_seg averaging.
        XCTAssertEqual(out.sigmaSeg, 0, accuracy: 1e-4)
        XCTAssertTrue(out.perClassMeanProb.isEmpty)
        // But no refusal — silhouette pixels exist.
    }

    // MARK: - perClassMeanProb (Step 13)

    func testPerClassMeanProb_OnlyFoodClassesIncluded() throws {
        // Half pixels argmax to food_0, half to food_1. Both food classes appear in perClassMeanProb.
        let palette = makeTestPalette()
        let targetSize = 4
        let classes = palette.totalClasses
        let logits = makeOneHotLogits(targetSize: targetSize, classes: classes) { y, _ in
            y < 2 ? 0 : 1
        }
        let out = try SegmenterPostProcessor.process(
            logitsFP32: logits, targetSize: targetSize, classes: classes,
            scaledWidth: targetSize, scaledHeight: targetSize,
            originalWidth: targetSize, originalHeight: targetSize,
            palette: palette
        )
        XCTAssertEqual(out.perClassMeanProb.count, 2)
        XCTAssertEqual(out.perClassMeanProb["food_0"]!, 0.99999, accuracy: 1e-3)
        XCTAssertEqual(out.perClassMeanProb["food_1"]!, 0.99999, accuracy: 1e-3)
        XCTAssertNil(out.perClassMeanProb["background"])
    }
}

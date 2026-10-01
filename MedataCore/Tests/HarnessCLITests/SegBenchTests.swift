#if HARNESS_ENABLED
import PortableContracts
import Segmentation
import XCTest
@testable import HarnessCore

// Tests for SegBench — task 63: segmenter mIoU bench (Req 8.9).
final class SegBenchTests: XCTestCase {

    // Perfect prediction: predicted == ground truth → mIoU = 1.0 for every food class.
    func testPerfectPredictionYieldsMeanIoUOne() {
        let palette = makeTestPalette()
        // 4×4 argmax entirely class 0 (food).
        let argmax = [UInt8](repeating: 0, count: 16)
        let sample = SegBenchSample(
            fixtureID: "s1",
            predictedArgmax: argmax,
            groundTruthArgmax: argmax,
            width: 4, height: 4
        )

        let report = SegBench.evaluate(samples: [sample], palette: palette)

        XCTAssertEqual(report.perClassIoU[0]!, 1.0, accuracy: 1e-5)
        XCTAssertEqual(report.meanFoodClassIoU, 1.0, accuracy: 1e-5)
    }

    // Zero overlap: predicted all class 0 but GT all class 1 → IoU = 0 for both.
    func testZeroOverlapYieldsMeanIoUZero() {
        let palette = makeTestPalette()
        let predicted = [UInt8](repeating: 0, count: 16)
        let gt        = [UInt8](repeating: 1, count: 16)
        let sample = SegBenchSample(
            fixtureID: "s2", predictedArgmax: predicted,
            groundTruthArgmax: gt, width: 4, height: 4
        )

        let report = SegBench.evaluate(samples: [sample], palette: palette)

        XCTAssertEqual(report.perClassIoU[0]!, 0.0, accuracy: 1e-5)
        XCTAssertEqual(report.perClassIoU[1]!, 0.0, accuracy: 1e-5)
    }

    // Mean IoU is computed ONLY over food classes (excludes background, unknown_food,
    // unsupported_liquid per Decision 14).
    func testMeanIoUExcludesSpecialClasses() {
        // palette: classes 0,1 are food; class 2 is background; class 3 unknownFood;
        // class 4 unsupportedLiquid.
        let palette = ClassPalette(
            foodClasses: ["rice", "pasta"],
            background: 2,
            unknownFood: 3,
            unsupportedLiquid: 4,
            version: "test"
        )
        // All pixels predicted as background (2), GT is class 0 (food).
        let predicted = [UInt8](repeating: 2, count: 16)
        let gt        = [UInt8](repeating: 0, count: 16)
        let sample = SegBenchSample(
            fixtureID: "s3", predictedArgmax: predicted,
            groundTruthArgmax: gt, width: 4, height: 4
        )

        let report = SegBench.evaluate(samples: [sample], palette: palette)

        // Background (class 2) has IoU but must not contribute to meanFoodClassIoU.
        // Food class 0: TP=0, FP=0, FN=16 → IoU=0.
        // Food class 1: all zero → IoU=0 (0/(0+0+0)=0 by our convention).
        XCTAssertEqual(report.meanFoodClassIoU, 0.0, accuracy: 1e-5)
    }

    // Known IoU value: predicted and GT overlap on half the pixels for class 0.
    func testKnownIoUValue() {
        let palette = makeTestPalette()
        // 8-pixel image. First 4 pixels: GT=0, predicted=0 (TP). Last 4: GT=0, predicted=1 (FN).
        let predicted: [UInt8] = [0, 0, 0, 0, 1, 1, 1, 1]
        let gt:        [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0]
        let sample = SegBenchSample(
            fixtureID: "s4", predictedArgmax: predicted,
            groundTruthArgmax: gt, width: 8, height: 1
        )

        let report = SegBench.evaluate(samples: [sample], palette: palette)

        // Class 0: TP=4, FP=0, FN=4 → IoU = 4/(4+0+4) = 0.5
        XCTAssertEqual(report.perClassIoU[0]!, 0.5, accuracy: 1e-5)
    }

    // A poor prediction reports a low mean and no verdict: the 0.48 bar this
    // asserted was removed with segmenter-foundation Decision 38.
    func testPoorPredictionReportsALowMeanAndNoVerdict() {
        let palette = makeTestPalette()
        // Class 0 IoU 0.5, class 1 IoU 0 → mean food-class IoU 0.25.
        let predicted: [UInt8] = [0, 0, 1, 1]
        let gt:        [UInt8] = [0, 0, 0, 0]
        let sample = SegBenchSample(
            fixtureID: "s5", predictedArgmax: predicted,
            groundTruthArgmax: gt, width: 4, height: 1
        )
        let report = SegBench.evaluate(samples: [sample], palette: palette)
        XCTAssertEqual(report.meanFoodClassIoU, 0.25, accuracy: 1e-5)
    }

    // Confusion matrix has correct shape (C × C) and totals match pixel count.
    func testConfusionMatrixShape() {
        let palette = makeTestPalette()
        let argmax = [UInt8](repeating: 0, count: 16)
        let sample = SegBenchSample(
            fixtureID: "s6", predictedArgmax: argmax,
            groundTruthArgmax: argmax, width: 4, height: 4
        )
        let report = SegBench.evaluate(samples: [sample], palette: palette)

        XCTAssertEqual(report.confusionMatrix.count, palette.totalClasses)
        for row in report.confusionMatrix {
            XCTAssertEqual(row.count, palette.totalClasses)
        }
        let total = report.confusionMatrix.flatMap { $0 }.reduce(0, +)
        XCTAssertEqual(total, 16)
    }

    // Multiple samples are aggregated correctly.
    func testMultipleSamplesAreAggregated() {
        let palette = makeTestPalette()
        // Sample A: perfect. Sample B: 50% overlap.
        let argmaxA = [UInt8](repeating: 0, count: 4)
        let argmaxB_pred: [UInt8] = [0, 0, 1, 1]
        let argmaxB_gt:   [UInt8] = [0, 0, 0, 0]
        let samples = [
            SegBenchSample(fixtureID: "a", predictedArgmax: argmaxA,
                           groundTruthArgmax: argmaxA, width: 4, height: 1),
            SegBenchSample(fixtureID: "b", predictedArgmax: argmaxB_pred,
                           groundTruthArgmax: argmaxB_gt, width: 4, height: 1),
        ]
        let report = SegBench.evaluate(samples: samples, palette: palette)
        // Total: class 0 TP=6 (4+2), FP=0, FN=2 → IoU = 6/8 = 0.75
        XCTAssertEqual(report.perClassIoU[0]!, 0.75, accuracy: 1e-5)
    }

    // MARK: - Helpers

    // Two food classes (0, 1), background = 2, unknownFood = 3, unsupportedLiquid = 4.
    // MARK: - Sample building (seg-bench-silently-drops-mis-sized-fixtures)
    // runSegBench used to drop a mis-sized fixture via a compactMap guard —
    // no message, no count. The builder now throws so the batch driver can
    // carry the skip.

    func testMisSizedProbsThrowsWithFixtureIDAndCounts() {
        var fx = PbMealFixture()
        fx.fixtureID = "bad_bundle"
        fx.nadirIntrinsics.imageWidth = 2
        fx.nadirIntrinsics.imageHeight = 1
        fx.nadirProbs = Data(count: 6)  // expected 1*2*5*2 = 20 for C=5
        XCTAssertThrowsError(
            try SegBench.sample(from: fx, palette: makeTestPalette())
        ) { error in
            guard case FixtureRunner.Error.probsSizeMismatch(
                let id, let expected, let got) = error else {
                return XCTFail("wrong error: \(error)")
            }
            XCTAssertEqual(id, "bad_bundle")
            XCTAssertEqual(expected, 20)
            XCTAssertEqual(got, 6)
        }
    }

    func testWellFormedFixtureBuildsSampleWithDecodedArgmax() throws {
        // 1x2 image, C=5 (2 food + background/unknown/unsupported).
        // Pixel 0 peaks class 3, pixel 1 peaks class 0.
        var probs = [Float16](repeating: 0.01, count: 10)
        probs[3] = 0.9
        probs[5] = 0.9
        var fx = PbMealFixture()
        fx.fixtureID = "good_bundle"
        fx.nadirIntrinsics.imageWidth = 2
        fx.nadirIntrinsics.imageHeight = 1
        fx.nadirProbs = probs.withUnsafeBytes { Data($0) }
        fx.nadirArgmax = Data([3, 0])

        // `.disabled` because this asserts the FP16 decode, not the cleanup: at
        // `.standard` the two 1-pixel regions are both under minRegionArea and
        // the speckle rule swaps them.
        let sample = try SegBench.sample(
            from: fx, palette: makeTestPalette(), regularisation: .disabled)

        XCTAssertEqual(sample.fixtureID, "good_bundle")
        XCTAssertEqual(sample.predictedArgmax, [3, 0])
        XCTAssertEqual(sample.groundTruthArgmax, [3, 0])
        XCTAssertEqual(sample.width, 2)
        XCTAssertEqual(sample.height, 1)
    }

    // MARK: - Regularised predictions (unknown-food-nameable task 3)
    // The bench scores the mask the app ships, so `sample` runs the same
    // regularisation `SegmenterPostProcessor.process` runs on device. Without
    // this the sliver fraction would have been tuned against a raw argmax the
    // app never produces.

    // A `pasta` sliver inside a large `rice` region is absorbed before scoring,
    // so the bench sees the cleaned mask rather than the raw argmax.
    func testSampleAppliesSliverAbsorptionToPrediction() throws {
        let palette = makeTestPalette()
        // 8×8 all rice (class 0) except a 2×2 pasta (class 1) block: 4 of 64
        // food-like pixels = 6.25 %, a sliver at 0.10 and not at 0.05.
        let w = 8, h = 8, c = 5
        var labels = [UInt8](repeating: 0, count: w * h)
        for y in 3..<5 { for x in 3..<5 { labels[y * w + x] = 1 } }
        var probs = [Float16](repeating: 0.01, count: w * h * c)
        for i in 0..<(w * h) { probs[i * c + Int(labels[i])] = 0.9 }

        var fx = PbMealFixture()
        fx.fixtureID = "sliver_bundle"
        fx.nadirIntrinsics.imageWidth = Int32(w)
        fx.nadirIntrinsics.imageHeight = Int32(h)
        fx.nadirProbs = probs.withUnsafeBytes { Data($0) }
        fx.nadirArgmax = Data(labels)

        let raw = try SegBench.sample(from: fx, palette: palette, regularisation: .disabled)
        XCTAssertEqual(raw.predictedArgmax, labels, "disabled must decode unchanged")

        let absorbed = try SegBench.sample(
            from: fx, palette: palette,
            regularisation: MaskRegularisationConfig(minRegionArea: 0, sliverFraction: 0.10))
        XCTAssertEqual(
            absorbed.predictedArgmax, [UInt8](repeating: 0, count: w * h),
            "a 6.25 % pasta block is a sliver at 0.10 and joins the rice around it")

        let kept = try SegBench.sample(
            from: fx, palette: palette,
            regularisation: MaskRegularisationConfig(minRegionArea: 0, sliverFraction: 0.05))
        XCTAssertEqual(kept.predictedArgmax, labels, "6.25 % is above the 5 % threshold")
    }

    // Ground truth is the yardstick and must never be reshaped — regularising it
    // too would score a cleaned prediction against a cleaned truth and hide the
    // rule's real cost.
    func testSampleLeavesGroundTruthUnregularised() throws {
        let palette = makeTestPalette()
        let w = 8, h = 8, c = 5
        var labels = [UInt8](repeating: 0, count: w * h)
        for y in 3..<5 { for x in 3..<5 { labels[y * w + x] = 1 } }
        var probs = [Float16](repeating: 0.01, count: w * h * c)
        for i in 0..<(w * h) { probs[i * c + Int(labels[i])] = 0.9 }

        var fx = PbMealFixture()
        fx.fixtureID = "gt_bundle"
        fx.nadirIntrinsics.imageWidth = Int32(w)
        fx.nadirIntrinsics.imageHeight = Int32(h)
        fx.nadirProbs = probs.withUnsafeBytes { Data($0) }
        fx.nadirArgmax = Data(labels)

        let sample = try SegBench.sample(
            from: fx, palette: palette,
            regularisation: MaskRegularisationConfig(minRegionArea: 0, sliverFraction: 0.10))

        XCTAssertEqual(sample.groundTruthArgmax, labels)
        XCTAssertNotEqual(sample.predictedArgmax, sample.groundTruthArgmax)
    }

    private func makeTestPalette() -> ClassPalette {
        ClassPalette(
            foodClasses: ["rice", "pasta"],
            background: 2,
            unknownFood: 3,
            unsupportedLiquid: 4,
            version: "test-v1"
        )
    }
}
#endif

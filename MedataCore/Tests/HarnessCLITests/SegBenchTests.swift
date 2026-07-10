#if HARNESS_ENABLED
import XCTest
import Segmentation
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
        XCTAssertTrue(report.passesBar, "Perfect prediction must pass the 0.48 bar")
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

    // CI fails (passesBar == false) when meanFoodClassIoU < 0.48
    // (segmenter-foundation Decision 5).
    func testCIFailWhenBelowBar() {
        let palette = makeTestPalette()
        // Class 0 IoU 0.5, class 1 IoU 0 → mean food-class IoU 0.25, fails bar.
        let predicted: [UInt8] = [0, 0, 1, 1]
        let gt:        [UInt8] = [0, 0, 0, 0]
        let sample = SegBenchSample(
            fixtureID: "s5", predictedArgmax: predicted,
            groundTruthArgmax: gt, width: 4, height: 1
        )
        let report = SegBench.evaluate(samples: [sample], palette: palette)
        XCTAssertFalse(report.passesBar,
                       "Expected bar failure when mIoU=\(report.meanFoodClassIoU) < 0.48")
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

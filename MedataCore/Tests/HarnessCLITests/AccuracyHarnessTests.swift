import XCTest
import Foods
import PortableContracts
@testable import HarnessCore

// Tests for AccuracyHarness — task 59: point-estimate MAPE, MAE, per-class breakdown,
// per-stage latency stats (Req 21.2–21.5).
final class AccuracyHarnessTests: XCTestCase {

    // MAPE and MAE point estimates are computed correctly.
    func testPointEstimateMAPEAndMAE() {
        // Three meals: predicted 100, 90, 110 vs actual 100, 100, 100.
        // APE: 0%, 10%, 10% → MAPE = 20/3 ≈ 6.67%
        // AE:  0,  10,  10 → MAE = 20/3 ≈ 6.67 g
        let meals = [
            makeMeal("m1", predicted: 100, actual: 100),
            makeMeal("m2", predicted: 90,  actual: 100),
            makeMeal("m3", predicted: 110, actual: 100),
        ]

        let report = AccuracyHarness.evaluate(meals: meals)

        XCTAssertEqual(report.mape, 20.0 / 3.0, accuracy: 0.01)
        XCTAssertEqual(report.mae, 20.0 / 3.0, accuracy: 0.01)
    }

    // MAPE < 20% AND MAE ≤ 10 g → passesBar true.
    func testPassesBarWhenMetrics() {
        let meals = (0..<10).map { i -> MealEvalInput in
            makeMeal("m\(i)", predicted: 95, actual: 100)
        }
        let report = AccuracyHarness.evaluate(meals: meals)
        XCTAssertTrue(report.passesBar,
                      "Expected bar pass; MAPE=\(report.mape) MAE=\(report.mae)")
    }

    // MAPE ≥ 20% → passesBar false.
    func testFailsBarWhenMAPEExceeds20() {
        // predicted 50, actual 100 → APE = 50% > 20%
        let meals = (0..<5).map { i in makeMeal("m\(i)", predicted: 50, actual: 100) }
        let report = AccuracyHarness.evaluate(meals: meals)
        XCTAssertFalse(report.passesBar)
    }

    // MAE > 10 g → passesBar false.
    func testFailsBarWhenMAEExceeds10g() {
        // predicted 120, actual 100 → AE = 20 g > 10 g
        let meals = (0..<5).map { i in makeMeal("m\(i)", predicted: 120, actual: 100) }
        let report = AccuracyHarness.evaluate(meals: meals)
        XCTAssertFalse(report.passesBar)
    }

    // Per-class breakdown distinguishes calibrated, uncalibrated_pooled, uncalibrated_unity.
    func testPerClassBreakdownDistinguishesStatuses() {
        let meals = [
            MealEvalInput(
                fixtureID: "m1", capturePath: .twoViewSfS,
                predictedCarbsPerClass: ["rice": 50, "salad": 10],
                statusPerClass: ["rice": .calibrated, "salad": .uncalibratedPooled],
                groundTruthTotalCarbsG: 60
            ),
            MealEvalInput(
                fixtureID: "m2", capturePath: .singleViewLidar,
                predictedCarbsPerClass: ["rice": 40, "soup": 20],
                statusPerClass: ["rice": .calibrated, "soup": .uncalibratedUnity],
                groundTruthTotalCarbsG: 60
            ),
        ]

        let report = AccuracyHarness.evaluate(meals: meals)

        XCTAssertEqual(report.perClassStats["rice"]?.calibrationStatus, .calibrated)
        XCTAssertEqual(report.perClassStats["salad"]?.calibrationStatus, .uncalibratedPooled)
        XCTAssertEqual(report.perClassStats["soup"]?.calibrationStatus, .uncalibratedUnity)
    }

    // Per-stage latency stats are produced for both capturePath values (Req 21.5).
    func testPerStageLatencyStatsForBothCapturePaths() {
        let latencySingle: [String: Double] = ["segmentation": 0.120, "volume": 0.300]
        let latencyTwo:    [String: Double] = ["segmentation": 0.115, "volume": 0.800]
        let meals = [
            MealEvalInput(
                fixtureID: "s1", capturePath: .singleViewLidar,
                predictedCarbsPerClass: ["rice": 50],
                statusPerClass: ["rice": .calibrated],
                groundTruthTotalCarbsG: 50,
                stageLatenciesSeconds: latencySingle
            ),
            MealEvalInput(
                fixtureID: "t1", capturePath: .twoViewSfS,
                predictedCarbsPerClass: ["rice": 50],
                statusPerClass: ["rice": .calibrated],
                groundTruthTotalCarbsG: 50,
                stageLatenciesSeconds: latencyTwo
            ),
        ]

        let report = AccuracyHarness.evaluate(meals: meals)

        // Both stage names must appear.
        XCTAssertNotNil(report.latencyStats["segmentation"])
        XCTAssertNotNil(report.latencyStats["volume"])
        // Both capture paths must appear inside at least one stage.
        let segKeys = report.latencyStats["segmentation"]?.keys
        let segPaths = Set(segKeys?.map { $0 } ?? [])
        XCTAssertTrue(segPaths.contains(CapturePath.singleViewLidar.rawValue),
                      "singleViewLidar missing from latency stats")
        XCTAssertTrue(segPaths.contains(CapturePath.twoViewSfS.rawValue),
                      "twoViewSfS missing from latency stats")
    }

    // CI is reported when n ≥ 30 (Req 21.8), nil otherwise.
    func testCIReportedWhenLargeSample() {
        let meals = (0..<35).map { i in makeMeal("m\(i)", predicted: 95, actual: 100) }
        let report = AccuracyHarness.evaluate(meals: meals)
        XCTAssertNotNil(report.ci95Lower)
        XCTAssertNotNil(report.ci95Upper)
    }

    func testCINotReportedWhenSmallSample() {
        let meals = (0..<10).map { i in makeMeal("m\(i)", predicted: 95, actual: 100) }
        let report = AccuracyHarness.evaluate(meals: meals)
        XCTAssertNil(report.ci95Lower)
        XCTAssertNil(report.ci95Upper)
    }

    // MARK: - Helpers

    private func makeMeal(
        _ id: String,
        predicted: Float,
        actual: Float,
        capturePath: CapturePath = .twoViewSfS
    ) -> MealEvalInput {
        MealEvalInput(
            fixtureID: id,
            capturePath: capturePath,
            predictedCarbsPerClass: ["rice": predicted],
            statusPerClass: ["rice": .calibrated],
            groundTruthTotalCarbsG: actual
        )
    }
}

#if HARNESS_ENABLED
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

    // MAPE < 20% AND MAE ≤ 25 g → passesBar true.
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

    // MAE > 25 g (with MAPE < 20%, so the MAE term is what fails) → passesBar false.
    func testFailsBarWhenMAEExceeds25g() {
        // predicted 230, actual 200 → AE = 30 g > 25 g, APE = 15% < 20%
        let meals = (0..<5).map { i in makeMeal("m\(i)", predicted: 230, actual: 200) }
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

    // MARK: - Untruthed meals (bugfix: accuracy-harness-scores-untruthed-fixtures-as-zero)

    // A run where NO meal carries truth must not report a perfect score. Before
    // the fix this returned MAPE 0% and MAE = the predicted grams, so a device
    // replay could pass the bar without a single measurement.
    func testAllUntruthedMealsScoreNothingAndFailTheBar() {
        // Predicted 20 g against proto3-default zero truth. The old behaviour:
        // MAPE 0% (guard act > 0 → 0) and MAE 20 g ≤ 25 g → passesBar true.
        let meals = (0..<5).map { i in makeMeal("m\(i)", predicted: 20, actual: 0) }

        let report = AccuracyHarness.evaluate(meals: meals)

        XCTAssertEqual(report.scoredCount, 0)
        XCTAssertEqual(report.unscoredCount, 5)
        XCTAssertFalse(report.passesBar,
                       "A run that scored nothing must not pass the accuracy bar")
        XCTAssertEqual(report.rows.count, 5)
        XCTAssertTrue(report.rows.allSatisfy { !$0.isScored })
        // Absent, not zero — a zero would read as an exact prediction.
        XCTAssertTrue(report.rows.allSatisfy { $0.absoluteErrorG == nil })
        XCTAssertTrue(report.rows.allSatisfy { $0.percentError == nil })
    }

    // Untruthed meals are excluded from the aggregates rather than dragging them
    // toward zero: the metrics must equal those of the truthed meals alone.
    func testUntruthedMealsAreExcludedFromMetrics() {
        let truthed = [
            makeMeal("t1", predicted: 90,  actual: 100),
            makeMeal("t2", predicted: 110, actual: 100),
        ]
        let mixed = truthed + [makeMeal("u1", predicted: 500, actual: 0)]

        let truthedOnly = AccuracyHarness.evaluate(meals: truthed)
        let report = AccuracyHarness.evaluate(meals: mixed)

        XCTAssertEqual(report.scoredCount, 2)
        XCTAssertEqual(report.unscoredCount, 1)
        XCTAssertEqual(report.mape, truthedOnly.mape, accuracy: 0.0001,
                       "An untruthed meal must not move MAPE")
        XCTAssertEqual(report.mae, truthedOnly.mae, accuracy: 0.0001,
                       "An untruthed meal must not move MAE")
        // The wildly-wrong untruthed prediction is still reported, just unscored.
        XCTAssertEqual(report.rows.count, 3)
        XCTAssertEqual(report.rows.last?.predictedCarbsG, 500)
        XCTAssertFalse(report.rows.last?.isScored ?? true)
    }

    // Scored rows carry the per-fixture error the aggregates are built from.
    func testScoredRowsCarryPerFixtureError() {
        let report = AccuracyHarness.evaluate(meals: [
            makeMeal("m1", predicted: 75, actual: 100),
        ])

        let row = try? XCTUnwrap(report.rows.first)
        XCTAssertEqual(row?.fixtureID, "m1")
        XCTAssertEqual(row?.groundTruthCarbsG, 100)
        XCTAssertEqual(row?.predictedCarbsG, 75)
        XCTAssertEqual(row?.absoluteErrorG ?? 0, 25, accuracy: 0.0001)
        XCTAssertEqual(row?.percentError ?? 0, 25, accuracy: 0.0001)
        XCTAssertTrue(row?.isScored ?? false)
    }

    // An empty run scores nothing and must not pass the bar either.
    func testEmptyRunFailsTheBar() {
        let report = AccuracyHarness.evaluate(meals: [])
        XCTAssertEqual(report.scoredCount, 0)
        XCTAssertEqual(report.unscoredCount, 0)
        XCTAssertTrue(report.rows.isEmpty)
        XCTAssertFalse(report.passesBar)
    }

    // A negative or non-finite truth is not usable truth.
    func testNonPositiveAndNonFiniteTruthIsNotScored() {
        let report = AccuracyHarness.evaluate(meals: [
            makeMeal("neg", predicted: 50, actual: -10),
            makeMeal("nan", predicted: 50, actual: .nan),
            makeMeal("inf", predicted: 50, actual: .infinity),
        ])
        XCTAssertEqual(report.scoredCount, 0)
        XCTAssertEqual(report.unscoredCount, 3)
        XCTAssertFalse(report.passesBar)
    }

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
#endif

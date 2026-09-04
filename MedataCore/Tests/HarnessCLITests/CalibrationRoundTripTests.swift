#if HARNESS_ENABLED
import XCTest
import Foods
import PortableContracts
@testable import HarnessCore

// Tests for the β_c calibration round-trip — task 61: §6.13.
// Starting from a synthetic dataset with known ground truth, calibrate β_c values
// and then evaluate the accuracy harness on the disjoint eval subset.
// Asserts that the MAPE and MAE bars are met on the synthetic eval set.
final class CalibrationRoundTripTests: XCTestCase {

    // End-to-end: calibrate → apply β → evaluate. With exact ground truth the
    // calibration should drive eval-set MAPE and MAE to near zero.
    func testCalibrateAndEvalMeetsAccuracyBar() {
        let trueBeta: Float = 0.7
        // 100 meals: 60 cal, 40 eval — all calibratable.
        let meals = makeSyntheticMeals(count: 100, trueBeta: trueBeta)

        let calResult = BetaCalibrator.calibrate(meals: meals)
        XCTAssertEqual(calResult.statusPerClass["rice"], .calibrated)

        let recoveredBeta = calResult.betaPerClass["rice"]!
        // Recovered β within 5% of true β.
        XCTAssertEqual(recoveredBeta, trueBeta, accuracy: trueBeta * 0.05)

        // Build eval meals applying the calibrated β.
        let evalMeals: [MealEvalInput] = calResult.evalIndices.sorted().map { i in
            let m = meals[i]
            let predicted = (m.predictedCarbsPerClass["rice"] ?? 0) * recoveredBeta
            return MealEvalInput(
                fixtureID: m.fixtureID,
                capturePath: m.capturePath,
                predictedCarbsPerClass: ["rice": predicted],
                statusPerClass: ["rice": calResult.statusPerClass["rice"]!],
                groundTruthTotalCarbsG: m.groundTruthTotalCarbsG
            )
        }

        let report = AccuracyHarness.evaluate(meals: evalMeals)
        XCTAssertTrue(report.passesBar,
                      "Round-trip failed accuracy bar: MAPE=\(report.mape)%, MAE=\(report.mae)g")
    }

    // With a single deterministic β the recovered value is exact to floating-point precision.
    func testRoundTripBetaIsAnalyticallyExact() {
        let trueBeta: Float = 0.85
        // All meals have identical predicted_carbs → log-residual = ln(trueBeta) exactly.
        let meals = (0..<80).map { i in
            MealCalibrationInput(
                fixtureID: "meal-\(i)", capturePath: .twoViewSfS, dominantClass: "rice",
                predictedCarbsPerClass: ["rice": 10.0],
                actualCarbsPerClass: ["rice": 10.0 * trueBeta],
                groundTruthTotalCarbsG: 10.0 * trueBeta
            )
        }

        let result = BetaCalibrator.calibrate(meals: meals)
        let recovered = result.betaPerClass["rice"]!
        // log-residual on constant data → exact recovery.
        XCTAssertEqual(recovered, trueBeta, accuracy: 1e-5)
    }

    // Distribution shift between cal and eval should not prevent bar pass when
    // the shift is within a realistic range (±10% of true β).
    func testEvalBarMetDespiteSmallDistributionShift() {
        // Cal meals: predicted scaled by 1.0, actual scaled by trueBeta.
        // Eval meals: predicted scaled by 1.1 (slight shift), actual = predicted * trueBeta.
        let trueBeta: Float = 0.8
        let calMeals = (0..<60).map { i -> MealCalibrationInput in
            let p = Float(i + 1) * 5.0
            return MealCalibrationInput(
                fixtureID: "c-\(i)", capturePath: .twoViewSfS, dominantClass: "chicken",
                predictedCarbsPerClass: ["chicken": p],
                actualCarbsPerClass: ["chicken": p * trueBeta],
                groundTruthTotalCarbsG: p * trueBeta
            )
        }
        let evalInputs = (0..<40).map { i -> MealCalibrationInput in
            let p = Float(i + 1) * 5.5
            return MealCalibrationInput(
                fixtureID: "e-\(i)", capturePath: .twoViewSfS, dominantClass: "chicken",
                predictedCarbsPerClass: ["chicken": p],
                actualCarbsPerClass: ["chicken": p * trueBeta],
                groundTruthTotalCarbsG: p * trueBeta
            )
        }
        let allMeals = calMeals + evalInputs

        let calResult = BetaCalibrator.calibrate(meals: allMeals)
        let beta = calResult.betaPerClass["chicken"] ?? 1.0

        let evalMeals = calResult.evalIndices.sorted().map { i -> MealEvalInput in
            let m = allMeals[i]
            let predicted = (m.predictedCarbsPerClass["chicken"] ?? 0) * beta
            return MealEvalInput(
                fixtureID: m.fixtureID, capturePath: m.capturePath,
                predictedCarbsPerClass: ["chicken": predicted],
                statusPerClass: ["chicken": calResult.statusPerClass["chicken"]!],
                groundTruthTotalCarbsG: m.groundTruthTotalCarbsG
            )
        }

        let report = AccuracyHarness.evaluate(meals: evalMeals)
        // With only a 10% distribution shift the bar should still be reachable.
        XCTAssertTrue(report.passesBar,
                      "Bar failed with 10% shift: MAPE=\(report.mape)%, MAE=\(report.mae)g")
    }

    // MARK: - Helpers

    private func makeSyntheticMeals(count: Int, trueBeta: Float) -> [MealCalibrationInput] {
        (0..<count).map { i in
            let predicted: Float = Float(i + 1) * 5.0
            return MealCalibrationInput(
                fixtureID: "meal-\(i)",
                capturePath: .twoViewSfS,
                dominantClass: "rice",
                predictedCarbsPerClass: ["rice": predicted],
                actualCarbsPerClass: ["rice": predicted * trueBeta],
                groundTruthTotalCarbsG: predicted * trueBeta
            )
        }
    }
}
#endif

#if HARNESS_ENABLED
import XCTest
import Foods
import PortableContracts
@testable import HarnessCore

// Tests for BetaCalibrator — task 57: §6.9 log-residual closed-form calibration.
final class BetaCalibratorTests: XCTestCase {

    // Synthetic set where ground-truth β is known; recovered β must be within 5%.
    func testRecoversTrueBetaWithinFivePercent() {
        let trueBeta: Float = 0.75
        // 80 meals so 60% cal = 48 ≥ 30 → calibrated
        let meals = makeMeals(count: 80, capturePath: .twoViewSfS,
                              className: "rice", trueBeta: trueBeta)

        let result = BetaCalibrator.calibrate(meals: meals)

        let recovered = result.betaPerClass["rice"]!
        XCTAssertEqual(recovered, trueBeta, accuracy: trueBeta * 0.05,
                       "Recovered β \(recovered) not within 5% of true β \(trueBeta)")
        XCTAssertEqual(result.statusPerClass["rice"], .calibrated)
    }

    // Two-view path: β > 1.0 must be clamped to 1.0 (M7 fix).
    func testTwoViewClampAtOne() {
        // actual >> predicted → raw β ≈ 3.0 → clamped to 1.0 for two-view
        let meals = makeMeals(count: 80, capturePath: .twoViewSfS,
                              className: "chips", trueBeta: 3.0)

        let result = BetaCalibrator.calibrate(meals: meals)

        XCTAssertEqual(result.betaPerClass["chips"]!, 1.0, accuracy: 1e-4)
        XCTAssertEqual(result.statusPerClass["chips"], .calibrated)
    }

    // Single-view path: β > 1.5 must be clamped to 1.5 (M7 fix).
    func testSingleViewClampAtOnePointFive() {
        let meals = makeMeals(count: 80, capturePath: .singleViewLidar,
                              className: "pasta", trueBeta: 3.0)

        let result = BetaCalibrator.calibrate(meals: meals)

        XCTAssertLessThanOrEqual(result.betaPerClass["pasta"]!, 1.5 + 1e-4)
        XCTAssertEqual(result.statusPerClass["pasta"], .calibrated)
    }

    // Fewer than 30 meals per class → uncalibrated_pooled, pooled fallback applied.
    func testUnderThresholdBecomesUncalibratedPooled() {
        // 20 meals total: 60% = 12 cal meals < 30 → pooled
        let meals = makeMeals(count: 20, capturePath: .twoViewSfS,
                              className: "salad", trueBeta: 0.8)

        let result = BetaCalibrator.calibrate(meals: meals)

        // With only 12 cal meals, fewer than 30 → uncalibrated_pooled (or unity if pool also small)
        let status = result.statusPerClass["salad"]!
        XCTAssertTrue(status == .uncalibratedPooled || status == .uncalibratedUnity,
                      "Expected pooled or unity; got \(status)")
    }

    // Pool < 30 meals → re-flag under-sampled classes as uncalibrated_unity, β = 1.0.
    func testPooledFallbackBecomesUnityWhenPoolTooSmall() {
        // Only 10 total meals → 6 cal < 30 → pool also < 30 → unity
        let meals = makeMeals(count: 10, capturePath: .twoViewSfS,
                              className: "soup", trueBeta: 0.6)

        let result = BetaCalibrator.calibrate(meals: meals)

        XCTAssertEqual(result.statusPerClass["soup"], .uncalibratedUnity)
        XCTAssertEqual(result.betaPerClass["soup"]!, 1.0, accuracy: 1e-6)
    }

    // Any meal with predicted_c < 1e-9 must trigger pooled fallback for that class.
    func testDenominatorCollapseTriggersPooled() {
        var meals = makeMeals(count: 60, capturePath: .twoViewSfS,
                              className: "bread", trueBeta: 0.9)
        // Inject one near-zero predicted value in the calibration portion.
        let idx = 0  // first meal is in cal set (60% split)
        let m = meals[idx]
        meals[idx] = MealCalibrationInput(
            fixtureID: m.fixtureID, capturePath: m.capturePath,
            dominantClass: m.dominantClass,
            predictedCarbsPerClass: ["bread": 0.0],  // < 1e-9
            actualCarbsPerClass: m.actualCarbsPerClass,
            groundTruthTotalCarbsG: m.groundTruthTotalCarbsG
        )

        let result = BetaCalibrator.calibrate(meals: meals)

        let status = result.statusPerClass["bread"]!
        XCTAssertTrue(status == .uncalibratedPooled || status == .uncalibratedUnity,
                      "Expected pooled or unity after denominator collapse; got \(status)")
    }

    // Stratified split: 60% calibration, 40% evaluation indices — no overlap.
    func testStratifiedSplitProducesDisjointSets() {
        let meals = makeMeals(count: 50, capturePath: .twoViewSfS,
                              className: "potato", trueBeta: 0.9)

        let result = BetaCalibrator.calibrate(meals: meals)

        XCTAssertTrue(result.calibrationIndices.isDisjoint(with: result.evalIndices))
        XCTAssertEqual(result.calibrationIndices.union(result.evalIndices).count, meals.count)
    }

    // Pool is computed correctly when two under-sampled classes are pooled together.
    func testPooledFallbackAcrossTwoClasses() {
        // 40 meals for "classA" and 40 for "classB" — each has 24 cal meals < 30.
        // Pool = 48 ≥ 30 → uncalibrated_pooled with shared β_pool.
        var meals: [MealCalibrationInput] = []
        for i in 0..<40 {
            meals.append(MealCalibrationInput(
                fixtureID: "a-\(i)", capturePath: .twoViewSfS, dominantClass: "classA",
                predictedCarbsPerClass: ["classA": 10.0],
                actualCarbsPerClass: ["classA": 8.0],   // trueBeta = 0.8
                groundTruthTotalCarbsG: 8.0
            ))
            meals.append(MealCalibrationInput(
                fixtureID: "b-\(i)", capturePath: .twoViewSfS, dominantClass: "classB",
                predictedCarbsPerClass: ["classB": 10.0],
                actualCarbsPerClass: ["classB": 8.0],
                groundTruthTotalCarbsG: 8.0
            ))
        }

        let result = BetaCalibrator.calibrate(meals: meals)

        // Both classes should share the same pooled β ≈ 0.8.
        XCTAssertEqual(result.statusPerClass["classA"], .uncalibratedPooled)
        XCTAssertEqual(result.statusPerClass["classB"], .uncalibratedPooled)
        XCTAssertEqual(result.betaPerClass["classA"]!, result.betaPool, accuracy: 1e-5)
        XCTAssertEqual(result.betaPerClass["classB"]!, result.betaPool, accuracy: 1e-5)
        XCTAssertEqual(result.betaPool, 0.8, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func makeMeals(
        count: Int,
        capturePath: CapturePath,
        className: String,
        trueBeta: Float
    ) -> [MealCalibrationInput] {
        (0..<count).map { i in
            let predicted: Float = Float(i + 1) * 5.0
            let actual = predicted * trueBeta
            return MealCalibrationInput(
                fixtureID: "meal-\(i)",
                capturePath: capturePath,
                dominantClass: className,
                predictedCarbsPerClass: [className: predicted],
                actualCarbsPerClass: [className: actual],
                groundTruthTotalCarbsG: actual
            )
        }
    }
}
#endif

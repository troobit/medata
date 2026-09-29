#if HARNESS_ENABLED
import Foods
import Foundation
import PortableContracts
import Testing
@testable import HarnessCore

// Tests for BetaCalibrator's new PerClassFit outputs and CalibrationMerge
// arbitration (spec task 15, design §Extended CalibrationResult, Req 5.2/5.4,
// Decision 16).

@Suite("BetaCalibrator PerClassFit")
struct BetaCalibratorPerClassFitTests {

    // 32 single-dominant meals for one class with alternating log-residuals.
    func makeMeals(ratioA: Float, ratioB: Float, count: Int = 32,
                   className: String = "white_rice") -> [MealCalibrationInput] {
        (0..<count).map { i in
            let pred: Float = 50
            let ratio = i % 2 == 0 ? ratioA : ratioB
            return MealCalibrationInput(
                fixtureID: "fx_\(i)",
                capturePath: .singleViewLidar,
                dominantClass: className,
                predictedCarbsPerClass: [className: pred],
                actualCarbsPerClass: [className: pred * ratio],
                groundTruthTotalCarbsG: pred * ratio
            )
        }
    }

    @Test("Fit value and clamp are unchanged — calibrateWithFit mirrors calibrate exactly")
    func fitValueUnchanged() {
        // 60 meals: the 60/40 split leaves 36 (≥ 30) in calibration, and the
        // alternating ratios give the same closed-form β on any even-count
        // subset — so the split-based result and the all-plates bake fit must
        // agree exactly.
        let meals = makeMeals(ratioA: 1.1, ratioB: 0.9, count: 60)
        let legacy = BetaCalibrator.calibrate(meals: meals)
        let (result, fit) = BetaCalibrator.calibrateWithFit(meals: meals)

        #expect(result.betaPerClass == legacy.betaPerClass)
        #expect(result.statusPerClass == legacy.statusPerClass)
        #expect(fit.classes["white_rice"]?.beta == legacy.betaPerClass["white_rice"])
    }

    @Test("PerClassFit reports the log-residual standard error and effective-sample count")
    func perClassFitReportsSpread() throws {
        // `fit` mirrors the split-based fit: 50 meals → the 60/40 split fits
        // the closed form on the first 30 (one stratum, sorted order). The
        // no-holdout bake basis is obtained by passing all qualifying plates.
        let meals = makeMeals(ratioA: 1.1, ratioB: 0.9, count: 50)
        let (_, fit) = BetaCalibrator.calibrateWithFit(meals: meals)
        let cls = try #require(fit.classes["white_rice"])

        // Closed form over the 30 calibration-split meals:
        // β = exp(mean(log r)); SE = sd(log r)/√n.
        let logs = (0..<30).map { i in Float(log(i % 2 == 0 ? 1.1 : 0.9)) }
        let mean = logs.reduce(0, +) / 30
        let sd = (logs.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / 29).squareRoot()
        let expectedSE = sd / Float(30).squareRoot()

        #expect(abs(cls.beta - exp(mean)) <= 1e-4)
        #expect(cls.effectiveSample == 30)
        let se = try #require(cls.logResidualSE)
        #expect(abs(se - expectedSE) <= 1e-4)
        #expect(cls.status == .calibrated)
        #expect(!cls.clamped)
    }

    @Test("bakeFit holds nothing out — a 30-49 plate class calibrates on the bake basis")
    func bakeFitUsesAllQualifyingPlates() throws {
        // Design §Split reconciliation: the baked β fits each class on ALL
        // qualifying plates, so a staple needs the 30-plate floor, not ~50.
        // 35 meals: the 60/40 self-evaluation split leaves only 21 in the
        // calibration subset (under the floor → pooled/unity), but the bake
        // basis fits all 35 and calibrates.
        let meals = makeMeals(ratioA: 1.1, ratioB: 0.9, count: 35)
        let (_, splitFit) = BetaCalibrator.calibrateWithFit(meals: meals)
        #expect(splitFit.classes["white_rice"]?.status != .calibrated)

        let bake = BetaCalibrator.bakeFit(meals: meals)
        let cls = try #require(bake.classes["white_rice"])
        #expect(cls.status == .calibrated)
        #expect(cls.effectiveSample == 35)
        // Same closed form over all 35 meals (18 × 1.1, 17 × 0.9).
        let logs = (0..<35).map { i in Float(log(i % 2 == 0 ? 1.1 : 0.9)) }
        let mean = logs.reduce(0, +) / 35
        #expect(abs(cls.beta - exp(mean)) <= 1e-4)
    }

    @Test("A clamped class carries the clamped flag (Req 5.6) with the value unchanged")
    func clampedFlagCarried() throws {
        // ratio 2.0 everywhere → β = 2.0 → clamped to the 1.5 ceiling.
        // 60 meals so the split-based result also calibrates (36 ≥ 30) and both
        // paths surface the same clamped value.
        let meals = makeMeals(ratioA: 2.0, ratioB: 2.0, count: 60)
        let (result, fit) = BetaCalibrator.calibrateWithFit(meals: meals)
        let cls = try #require(fit.classes["white_rice"])
        #expect(cls.clamped)
        #expect(cls.beta == 1.5)
        #expect(result.betaPerClass["white_rice"] == 1.5)
    }

    @Test("An under-sampled class reports its effective sample with no SE")
    func underSampledClassReported() throws {
        // 10 meals → 6 in the calibration split, below the 30-meal floor.
        let meals = makeMeals(ratioA: 1.1, ratioB: 0.9, count: 10)
        let (_, fit) = BetaCalibrator.calibrateWithFit(meals: meals)
        let cls = try #require(fit.classes["white_rice"])
        #expect(cls.effectiveSample == 6)
        #expect(cls.logResidualSE == nil)
        #expect(cls.status != .calibrated)
    }
}

@Suite("CalibrationMerge arbitration")
struct CalibrationMergeTests {

    // Builders for the two fit inputs.
    func sdFit(_ classes: [String: BetaCalibrator.PerClassFit.ClassFit])
        -> BetaCalibrator.PerClassFit {
        BetaCalibrator.PerClassFit(classes: classes, betaPool: 1.0)
    }

    func sdClass(beta: Float, status: BetaCalibrationStatus, se: Float?,
                 n: Int, clamped: Bool = false) -> BetaCalibrator.PerClassFit.ClassFit {
        .init(beta: beta, status: status, logResidualSE: se,
              effectiveSample: n, clamped: clamped)
    }

    func mixResult(beta: [String: Float] = [:], se: [String: Float] = [:],
                   n: [String: Int] = [:], identifiable: [String: Bool] = [:],
                   clamped: Set<String> = []) -> MixtureBetaCalibrator.Result {
        .init(betaPerClass: beta, standardErrorPerClass: se,
              effectiveSamplePerClass: n, identifiablePerClass: identifiable,
              conditionNumber: 1, excludedPlates: [], liquidExcludedPlates: [],
              fixedOffsetClasses: [], clampedClasses: clamped)
    }

    @Test("Single-dominant β wins when it clears effective-sample ≥ 30 AND relative SE ≤ 0.15")
    func singleDominantWinsWhenQualified() throws {
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit(["white_rice":
                sdClass(beta: 0.82, status: .calibrated, se: 0.05, n: 40)]),
            mixture: mixResult(beta: ["white_rice": 0.75], se: ["white_rice": 0.02],
                               n: ["white_rice": 100], identifiable: ["white_rice": true])
        )
        let c = try #require(merged["white_rice"])
        #expect(c.beta == 0.82)
        #expect(c.status == .calibrated)
        #expect(c.provenance == .n5kSingleDominant)
        #expect(c.effectiveSample == 40)
    }

    @Test("A strong mixture fit is KEPT when single-dominant is merely under-sampled")
    func mixtureKeptWhenSingleDominantUnderSampled() throws {
        // The "perverse discard" case: SD has only 8 plates; mixture is strong.
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit(["pasta":
                sdClass(beta: 0.9, status: .uncalibratedPooled, se: nil, n: 8)]),
            mixture: mixResult(beta: ["pasta": 0.78], se: ["pasta": 0.03],
                               n: ["pasta": 60], identifiable: ["pasta": true])
        )
        let c = try #require(merged["pasta"])
        #expect(c.beta == 0.78)
        #expect(c.status == .calibrated)
        #expect(c.provenance == .n5kMixture)
    }

    @Test("Enough plates but large SE stays pooled — never calibrated on raw count (Req 5.4)")
    func largeSEStaysPooled() throws {
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit(["broccoli":
                sdClass(beta: 0.7, status: .uncalibratedPooled, se: 0.30, n: 45)]),
            mixture: mixResult()
        )
        let c = try #require(merged["broccoli"])
        #expect(c.status != .calibrated)
        #expect(c.provenance == BetaProvenance.none)
    }

    @Test("Unidentifiable mixture classes never win, even with many plates")
    func unidentifiableMixtureLosesToFallback() throws {
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit([:]),
            mixture: mixResult(beta: ["carrot": 0.6], se: ["carrot": 5.0],
                               n: ["carrot": 80], identifiable: ["carrot": false])
        )
        let c = try #require(merged["carrot"])
        #expect(c.status != .calibrated)
        #expect(c.provenance == BetaProvenance.none)
    }

    @Test("The clamped flag propagates from whichever fit wins")
    func clampedFlagPropagates() throws {
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit(["chips_fries":
                sdClass(beta: 1.5, status: .calibrated, se: 0.04, n: 50, clamped: true)]),
            mixture: mixResult(beta: ["beans_baked": 1.5], se: ["beans_baked": 0.02],
                               n: ["beans_baked": 90], identifiable: ["beans_baked": true],
                               clamped: ["beans_baked"])
        )
        #expect(merged["chips_fries"]?.clamped == true)
        #expect(merged["beans_baked"]?.clamped == true)
        #expect(merged["beans_baked"]?.provenance == .n5kMixture)
    }

    @Test("Provenance is a dimension separate from status — pooled classes read none")
    func provenanceSeparateFromStatus() throws {
        let merged = CalibrationMerge.merge(
            singleDominant: sdFit(["apple":
                sdClass(beta: 1.0, status: .uncalibratedUnity, se: nil, n: 2)]),
            mixture: mixResult()
        )
        let c = try #require(merged["apple"])
        #expect(c.status == .uncalibratedUnity)
        #expect(c.provenance == BetaProvenance.none)
        #expect(c.beta == 1.0)
    }
}
#endif

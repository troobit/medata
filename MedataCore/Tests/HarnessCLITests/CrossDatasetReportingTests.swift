#if HARNESS_ENABLED
import Foods
import Foundation
import Testing
@testable import HarnessCore

// Tests for the cross-dataset reporting additions (cross-dataset-calibration
// Reqs 8.2/10.1/10.2, spec task 17). All reported figures, never bake gates.
@Suite("Cross-dataset reporting")
struct CrossDatasetReportingTests {

    func cal(_ name: String, beta: Float, status: BetaCalibrationStatus,
             n: Int) -> CalibrationMerge.ClassCalibration {
        .init(className: name, beta: beta, status: status,
              provenance: status == .calibrated ? .n5kMixture : .none,
              standardError: nil, effectiveSample: n, clamped: false)
    }

    // MARK: - β / coverage delta (Req 8.2, 10.1)

    @Test("Coverage rows report effective sample and status before vs after, plus the β delta")
    func coverageDeltaRows() throws {
        let before = [
            "white_rice": cal("white_rice", beta: 1.0, status: .uncalibratedUnity, n: 10),
            "broccoli": cal("broccoli", beta: 0.5, status: .calibrated, n: 34),
        ]
        let after = [
            "white_rice": cal("white_rice", beta: 0.72, status: .calibrated, n: 42),
            "broccoli": cal("broccoli", beta: 0.52, status: .calibrated, n: 40),
            "potato_boiled": cal("potato_boiled", beta: 0.8, status: .calibrated, n: 31),
        ]
        let delta = AccuracyHarness.betaCoverageDelta(before: before, after: after)

        let rice = try #require(delta["white_rice"])
        #expect(rice.statusBefore == "uncalibrated_unity")
        #expect(rice.statusAfter == "calibrated")
        #expect(rice.effectiveSampleBefore == 10)
        #expect(rice.effectiveSampleAfter == 42)
        #expect(abs(rice.betaDelta - (0.72 - 1.0)) < 1e-6)

        // A class N5k never saw at all still gets an honest before-state.
        let potato = try #require(delta["potato_boiled"])
        #expect(potato.statusBefore == "uncalibrated_unity")
        #expect(potato.effectiveSampleBefore == 0)
        #expect(potato.statusAfter == "calibrated")
    }

    // MARK: - Carb accuracy delta (Req 10.1)

    func plate(id: String, volume: Float, masses: [String: Float],
               carbs: [String: Float]) -> N5kEvalPlate {
        N5kEvalPlate(fixtureID: id, estimatorPath: .mixture,
                     totalHullVolumeCm3: volume, massByClassG: masses,
                     gtCarbsByClassG: carbs, gtProteinByClassG: [:],
                     gtFatByClassG: [:], wholeDishCarbsG: carbs.values.reduce(0, +),
                     inOfficialTestSplit: false)
    }

    let composition = ClassComposition(
        densityByClass: ["white_rice": 1.0, "pasta": 1.0],
        carbFractionPer100g: ["white_rice": 28, "pasta": 25],
        proteinFractionPer100g: [:], fatFractionPer100g: [:])

    @Test("The combined β improves the reported carb MAPE where it corrects a real bias")
    func combinedBetaImprovesCarbMAPE() throws {
        // 12 single-class rice plates whose hull over-reads volume 25%:
        // GT mass 80 g but hull 100 cm³ at ρ = 1. The true correction is
        // β = 0.8; baseline leaves β = 1.
        let plates = (0..<12).map { i in
            plate(id: "p\(i)", volume: 100,
                  masses: ["white_rice": 80],
                  carbs: ["white_rice": 80 * 0.28])
        }
        let report = AccuracyHarness.carbAccuracyDelta(
            plates: plates,
            baselineBeta: [:],
            combinedBeta: ["white_rice": 0.8],
            composition: composition,
            staples: ["white_rice"])

        #expect(report.overall.evalPlateCount == 12)
        #expect(abs(report.overall.mapeBaseline - 25) < 0.1)
        #expect(report.overall.mapeCombined < 0.1)
        let rice = try #require(report.perClass["white_rice"])
        #expect(rice.mapeCombined < rice.mapeBaseline)
        #expect(report.unvalidatedStaples.isEmpty)
    }

    @Test("Per-class deltas below the eval-plate floor are suppressed with their count")
    func thinClassesAreSuppressed() throws {
        // 12 rice plates (reportable) + 3 pasta plates (below the floor of 10).
        var plates = (0..<12).map { i in
            plate(id: "r\(i)", volume: 100, masses: ["white_rice": 80],
                  carbs: ["white_rice": 22.4])
        }
        plates += (0..<3).map { i in
            plate(id: "q\(i)", volume: 90, masses: ["pasta": 70],
                  carbs: ["pasta": 17.5])
        }
        let report = AccuracyHarness.carbAccuracyDelta(
            plates: plates, baselineBeta: [:], combinedBeta: [:],
            composition: composition, staples: ["white_rice", "pasta"])

        #expect(report.perClass["white_rice"] != nil)
        #expect(report.perClass["pasta"] == nil,
                "3 plates is sampling noise, not a per-class accuracy figure")
        #expect(report.suppressedBelowMinCount["pasta"] == 3)
        #expect(report.unvalidatedStaples.isEmpty,
                "suppressed-but-present is not the same as absent")
    }

    @Test("A staple absent from the eval pool is named as having no in-harness validation")
    func absentStapleIsNamedUnvalidated() {
        let plates = (0..<12).map { i in
            plate(id: "r\(i)", volume: 100, masses: ["white_rice": 80],
                  carbs: ["white_rice": 22.4])
        }
        let report = AccuracyHarness.carbAccuracyDelta(
            plates: plates, baselineBeta: [:], combinedBeta: [:],
            composition: composition,
            staples: ["white_rice", "potato_mashed", "bread_white"])

        #expect(report.unvalidatedStaples == ["bread_white", "potato_mashed"])
    }

    // MARK: - Held-out split (Req 10.2)

    @Test("The held-out split is deterministic for a fixed seed and independent of input order")
    func heldOutSplitIsDeterministic() {
        let ids = (0..<40).map { "mf3d_\($0)" }
        let a = AccuracyHarness.heldOutSplit(ids: ids, fraction: 0.25, seed: 42)
        let b = AccuracyHarness.heldOutSplit(ids: ids.reversed(), fraction: 0.25, seed: 42)
        #expect(a == b)
        #expect(a.count == 10)
        // A different seed selects a different subset (with overwhelming
        // probability on 40-choose-10; pinned here as a regression).
        let c = AccuracyHarness.heldOutSplit(ids: ids, fraction: 0.25, seed: 43)
        #expect(a != c)
        #expect(AccuracyHarness.heldOutSplit(ids: ids, fraction: 0, seed: 42).isEmpty)
    }

    // MARK: - Held-out anchor (Req 10.2)

    @Test("The anchor predicts mass as V_est·β·ρ_DB and reports MAPE, per class")
    func anchorPredictsMass() throws {
        let observations = [
            // Perfect prediction: 100 cm³ × 0.8 × 1.05 = 84 g.
            SingleFoodObservation(fixtureID: "a", className: "white_rice",
                                  estimatedVolumeCm3: 100, groundTruthMassG: 84),
            // 10% over: predicted 84 vs true 76.36…
            SingleFoodObservation(fixtureID: "b", className: "white_rice",
                                  estimatedVolumeCm3: 100,
                                  groundTruthMassG: 84 / 1.1),
        ]
        let report = AccuracyHarness.heldOutAnchor(
            observations: observations,
            beta: ["white_rice": 0.8],
            densityByClass: ["white_rice": 1.05])

        #expect(report.sampleCount == 2)
        let mape = try #require(report.massMAPEPercent)
        #expect(abs(mape - 5) < 0.01, "mean of 0% and 10% is 5%")
        #expect(report.broccoliCrossCheckMAPE == nil, "no broccoli objects present")
    }

    @Test("The broccoli cross-check reads broccoli's anchor MAPE where present")
    func broccoliCrossCheck() throws {
        let observations = [
            SingleFoodObservation(fixtureID: "a", className: "broccoli",
                                  estimatedVolumeCm3: 200, groundTruthMassG: 100),
        ]
        // Predicted: 200 × 0.5 × 1.0 = 100 → exact.
        let report = AccuracyHarness.heldOutAnchor(
            observations: observations,
            beta: ["broccoli": 0.5],
            densityByClass: ["broccoli": 1.0])
        let cross = try #require(report.broccoliCrossCheckMAPE)
        #expect(cross < 0.01)
    }

    @Test("Objects without a density or truth are unscored, and an empty pool reads absent")
    func anchorUnscoredHandling() {
        let report = AccuracyHarness.heldOutAnchor(
            observations: [
                SingleFoodObservation(fixtureID: "a", className: "mystery",
                                      estimatedVolumeCm3: 100, groundTruthMassG: 80),
                SingleFoodObservation(fixtureID: "b", className: "white_rice",
                                      estimatedVolumeCm3: 0, groundTruthMassG: 80),
            ],
            beta: [:],
            densityByClass: ["white_rice": 1.0])

        #expect(report.massMAPEPercent == nil, "an unmeasured anchor is absent, not 0%")
        #expect(report.sampleCount == 0)
        #expect(report.unscoredCount == 2)
    }
}
#endif

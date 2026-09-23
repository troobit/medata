#if HARNESS_ENABLED
import Foundation
import Testing
@testable import HarnessCore

// Tests for the AccuracyHarness k-fold calibration eval and report content
// (spec task 19, Req 4.4/4.5/6.1–6.8, design §Accuracy reporting / §Split
// reconciliation). Synthetic mini-split: plates generated from known β, ρ, κ.
@Suite("AccuracyHarness calibration eval")
struct CalibrationEvalTests {

    // DB composition (per 100 g).
    static let composition = ClassComposition(
        densityByClass: ["white_rice": 0.73, "pasta": 0.58, "potato_boiled": 0.59,
                         "soup": 1.0],
        carbFractionPer100g: ["white_rice": 28, "pasta": 25, "potato_boiled": 17,
                              "soup": 5],
        proteinFractionPer100g: ["white_rice": 2.6, "pasta": 4.2, "potato_boiled": 1.8,
                                 "soup": 2.0],
        fatFractionPer100g: ["white_rice": 0.3, "pasta": 1.1, "potato_boiled": 0.2,
                             "soup": 1.0]
    )

    static let betaTrue: [String: Float] = [
        "white_rice": 0.8, "pasta": 0.9, "potato_boiled": 0.85,
    ]

    static let config = CalibrationEvalConfig(
        folds: 3,
        seed: 0xC0FFEE,
        liquidClasses: ["soup"],
        carbPriorityStaples: ["white_rice", "pasta", "potato_boiled"]
    )

    // Plates whose hull volume is exactly Σ m/(ρ·β_true) and whose GT macros
    // follow the DB fractions (a perfectly consistent world): the β_c run
    // should recover ≈0 error while β=1 carries the systematic |1/β − 1|.
    static func makePlates(count: Int, seed: UInt64,
                           officialSplit: Bool = false) -> [N5kEvalPlate] {
        var rng = SplitMix64(seed: seed)
        func unit() -> Float { Float(rng.next() % 10_000) / 10_000 }
        let classes = Array(betaTrue.keys).sorted()
        return (0..<count).map { i in
            var masses: [String: Float] = [:]
            let start = Int(rng.next() % UInt64(classes.count))
            for k in 0..<2 {
                masses[classes[(start + k) % classes.count]] = 40 + unit() * 160
            }
            var v: Float = 0
            var carbs: [String: Float] = [:]
            var protein: [String: Float] = [:]
            var fat: [String: Float] = [:]
            for (c, m) in masses {
                v += m / (composition.densityByClass[c]! * betaTrue[c]!)
                carbs[c] = m * composition.carbFractionPer100g[c]! / 100
                protein[c] = m * composition.proteinFractionPer100g[c]! / 100
                fat[c] = m * composition.fatFractionPer100g[c]! / 100
            }
            return N5kEvalPlate(
                fixtureID: "dish_\(officialSplit ? "test_" : "")\(i)",
                estimatorPath: .mixture,
                totalHullVolumeCm3: v,
                massByClassG: masses,
                gtCarbsByClassG: carbs,
                gtProteinByClassG: protein,
                gtFatByClassG: fat,
                wholeDishCarbsG: carbs.values.reduce(0, +),
                inOfficialTestSplit: officialSplit
            )
        }
    }

    static let poolCounts = PoolCounts(rgbdDishCount: 200, depthTestSplitCount: 7,
                                       ingestionSkipCount: 3)

    func evaluate(calibration: [N5kEvalPlate]? = nil,
                  official: [N5kEvalPlate]? = nil,
                  config: CalibrationEvalConfig = CalibrationEvalTests.config) -> CalibrationReport {
        AccuracyHarness.evaluateCalibration(
            calibrationPlates: calibration ?? Self.makePlates(count: 120, seed: 11),
            officialSplitPlates: official ?? [],
            composition: Self.composition,
            config: config,
            pool: Self.poolCounts
        )
    }

    @Test("Reports MAPE and MAE for BOTH β=1.0 and β_c, per staple and overall (Req 6.3)")
    func reportsBaselineAndCalibrated() {
        let report = evaluate()
        // β_true ≈ 0.8–0.9 → β=1 systematically over-reads; β_c leaves only
        // the oracle mass-proportion attribution residual (est/GT per class is
        // (V/M)·ρ_c·β_c, which mixes co-occurring densities — the recorded
        // oracle caveat), well under the baseline's systematic error.
        let rice = report.carbs.perStaple["white_rice"]!
        #expect(rice.mapeBaseline > 20)
        #expect(rice.mapeCalibrated < rice.mapeBaseline)
        #expect(rice.mapeCalibrated <= 12)
        #expect(report.carbs.overall.maeBaseline > report.carbs.overall.maeCalibrated)
        #expect(report.carbs.overall.sampleCount == 120)
    }

    @Test("Protein and fat report on the same mapped-classes-only basis (Req 6.6)")
    func proteinAndFatReported() {
        let report = evaluate()
        // β corrects volume→mass, so protein/fat improve identically.
        #expect(report.protein.overall.mapeCalibrated < report.protein.overall.mapeBaseline)
        #expect(report.fat.overall.mapeCalibrated < report.fat.overall.mapeBaseline)
        #expect(report.protein.perStaple["pasta"] != nil)
    }

    @Test("One recorded seed drives selection + folds; the run is reproducible (Req 4.4/6.1)")
    func seededAndDeterministic() {
        let a = evaluate()
        let b = evaluate()
        #expect(a.seed == Self.config.seed)
        #expect(a.foldCount == 3)
        #expect(a.carbs.overall.mapeCalibrated == b.carbs.overall.mapeCalibrated)
        #expect(a.carbs.overall.maeBaseline == b.carbs.overall.maeBaseline)
    }

    @Test("Per-class dispersion: mixture classes report the regression SE (Req 6.4)")
    func dispersionReported() {
        let report = evaluate()
        for staple in Self.config.carbPriorityStaples {
            #expect(report.dispersionPerClass[staple] != nil,
                    "\(staple) missing regression-SE dispersion")
        }
    }

    @Test("The MAPE < 20% target is a reported result, not a gate (Req 6.5)")
    func mapeTargetReported() {
        let report = evaluate()
        #expect(report.mapeTargetPercent == 20)
        #expect(report.staplesMeetingTarget["white_rice"] == true)
    }

    @Test("Cross-macro consistency: carb agrees, protein diverges → class flagged (Req 6.7)")
    func crossMacroFlagRaised() {
        // Pasta's N5k GT protein is double what the DB composition implies —
        // a mapping/composition-source error the carb figures cannot see.
        let plates = Self.makePlates(count: 120, seed: 11).map { p -> N5kEvalPlate in
            var protein = p.gtProteinByClassG
            if let v = protein["pasta"] { protein["pasta"] = v * 2 }
            return N5kEvalPlate(
                fixtureID: p.fixtureID, estimatorPath: p.estimatorPath,
                totalHullVolumeCm3: p.totalHullVolumeCm3,
                massByClassG: p.massByClassG,
                gtCarbsByClassG: p.gtCarbsByClassG,
                gtProteinByClassG: protein,
                gtFatByClassG: p.gtFatByClassG,
                wholeDishCarbsG: p.wholeDishCarbsG,
                inOfficialTestSplit: p.inOfficialTestSplit)
        }
        let report = evaluate(calibration: plates)
        #expect(report.crossMacroFlags.contains("pasta"))
        #expect(!report.crossMacroFlags.contains("white_rice"))
    }

    @Test("Official-split whole-dish section: MAE, MAE÷mean, counts, coverage, caveat (Req 6.8)")
    func officialSplitSection() {
        // Official dishes carry 12 g of unmapped carbs on top of 100 g rice:
        // unmapped contributes zero to the estimate but full GT carbs.
        let official = (0..<5).map { i -> N5kEvalPlate in
            let m: Float = 100
            let mappedCarbs = m * 28 / 100                       // 28 g
            return N5kEvalPlate(
                fixtureID: "dish_official_\(i)", estimatorPath: .mixture,
                totalHullVolumeCm3: m / (0.73 * 0.8),
                massByClassG: ["white_rice": m],
                gtCarbsByClassG: ["white_rice": mappedCarbs],
                gtProteinByClassG: ["white_rice": m * 2.6 / 100],
                gtFatByClassG: ["white_rice": m * 0.3 / 100],
                wholeDishCarbsG: mappedCarbs + 12,
                inOfficialTestSplit: true)
        }
        let report = evaluate(official: official)
        let section = report.officialSplit

        // β_c recovers the mapped 28 g → MAE ≈ the 12 g unmapped gap.
        #expect(abs(section.maeCalibratedG - 12) <= 1.5)
        // β=1 over-reads to 35 g, partially cancelling the unmapped gap —
        // exactly why the β_c judgement lives in Req 6.3, not here.
        #expect(section.maeBaselineG < section.maeCalibratedG)
        #expect(abs(section.maeOverMeanCalibrated - 12.0 / 40.0) <= 0.05)
        #expect(section.evaluatedDishCount == 5)
        #expect(section.splitTotalCount == Self.poolCounts.depthTestSplitCount)
        #expect(abs(section.mappedCarbCoverageFraction - 0.7) <= 0.02)
        #expect(section.caveat.contains("reported alongside"))
    }

    @Test("Pool arithmetic report: RGB-D − split − skips − exclusions, per-path effective samples (Req 4.5)")
    func poolArithmeticReported() {
        // One liquid-bearing plate joins the calibration set and must be
        // excluded and counted.
        var plates = Self.makePlates(count: 120, seed: 11)
        plates.append(N5kEvalPlate(
            fixtureID: "dish_soupy", estimatorPath: .mixture,
            totalHullVolumeCm3: 500,
            massByClassG: ["soup": 50, "white_rice": 150],
            gtCarbsByClassG: ["white_rice": 42],
            gtProteinByClassG: ["white_rice": 3.9],
            gtFatByClassG: ["white_rice": 0.45],
            wholeDishCarbsG: 44.5,
            inOfficialTestSplit: false))
        let report = evaluate(calibration: plates)
        let pool = report.pool

        #expect(pool.rgbdDishCount == 200)
        #expect(pool.depthTestSplitCount == 7)
        #expect(pool.ingestionSkipCount == 3)
        #expect(pool.liquidExcludedCount == 1)
        #expect(pool.qualifyingPlateCount == 120)
        // Effective samples broken out per estimator path (all mixture here).
        let mixtureSamples = pool.effectiveSamplesByPath["mixture"] ?? [:]
        #expect(mixtureSamples["white_rice", default: 0] >= 30)
        #expect(pool.effectiveSamplesByPath["single_dominant", default: [:]].isEmpty)
        // Insufficient classes are a documented accepted outcome, not a failure.
        #expect(!pool.insufficientClasses.contains("white_rice"))
    }
}
#endif

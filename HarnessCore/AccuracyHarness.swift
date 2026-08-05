#if HARNESS_ENABLED
import Foundation
import Foods
import PortableContracts
import SupportPlane

// Per-meal evaluation result used by the accuracy harness.
public struct MealEvalInput: Sendable {
    public let fixtureID: String
    public let capturePath: CapturePath
    // Per-class predicted carbs after applying β (calibrated or fallback).
    public let predictedCarbsPerClass: [String: Float]
    // Calibration status for each class present in this meal.
    public let statusPerClass: [String: BetaCalibrationStatus]
    public let groundTruthTotalCarbsG: Float
    // Per-stage wall-clock durations in seconds (stage name → elapsed).
    public let stageLatenciesSeconds: [String: Double]
    // Which surface the support plane referenced (Req 4.4). nil where no plane was
    // derived from depth — the two-view path, or an attempt that never reached the
    // fitter — and those attempts stay out of the fallback-rate denominator.
    public let supportPlaneReference: SupportPlaneReference?

    public init(
        fixtureID: String,
        capturePath: CapturePath,
        predictedCarbsPerClass: [String: Float],
        statusPerClass: [String: BetaCalibrationStatus],
        groundTruthTotalCarbsG: Float,
        stageLatenciesSeconds: [String: Double] = [:],
        supportPlaneReference: SupportPlaneReference? = nil
    ) {
        self.fixtureID = fixtureID
        self.capturePath = capturePath
        self.predictedCarbsPerClass = predictedCarbsPerClass
        self.statusPerClass = statusPerClass
        self.groundTruthTotalCarbsG = groundTruthTotalCarbsG
        self.stageLatenciesSeconds = stageLatenciesSeconds
        self.supportPlaneReference = supportPlaneReference
    }
}

// How often the restricted fit was rejected, across the corpus, segmented by
// reference (Reqs 4.4, 4.5). Decision 11's argument for this architecture rests
// on the rate being measurable; an unreported rate makes it unfalsifiable.
public struct FallbackRateReport: Sendable, Equatable {
    // Reference raw value → attempts. Segmented rather than reduced to one
    // figure because the counts on either side of it are not comparable: a
    // `.foodSupport` row's candidate/inlier counts are native depth samples and
    // an `.edgeBand` row's are colour-grid points, ~56x more.
    public let countsByReference: [String: Int]
    // Attempts that derived no plane from depth — two-view, or card-only.
    public let unreportedCount: Int
    // Attempts eligible for the rate: the denominator.
    public let depthDerivedCount: Int
    // Attempts that fell back to the edge-band fit: the numerator.
    public let fallbackCount: Int
    // nil when nothing was depth-derived. A rate over zero attempts is ABSENT,
    // not zero — reporting 0 % would read as "the fallback never fired" on a run
    // where the restricted fit never ran.
    public let fallbackRate: Float?
}

// Accuracy metrics for one class.
public struct ClassAccuracyStats: Sendable, Equatable {
    public let mape: Float
    public let mae: Float
    public let sampleCount: Int
    public let calibrationStatus: BetaCalibrationStatus
}

// Per-stage latency statistics (P50, P95, mean).
public struct LatencyStats: Sendable {
    public let p50: Double
    public let p95: Double
    public let mean: Double
}

// Per-meal error row. `absoluteErrorG`/`percentError` are nil for an untruthed
// meal: no truth means no error, and reporting zero (or |pred − 0|) would read
// as a perfect or merely-large result rather than an absent measurement.
public struct MealErrorRow: Sendable, Equatable {
    public let fixtureID: String
    public let capturePath: String
    public let groundTruthCarbsG: Float
    public let predictedCarbsG: Float
    public let absoluteErrorG: Float?
    public let percentError: Float?

    public var isScored: Bool { absoluteErrorG != nil }
}

// Full accuracy report emitted to CI.
public struct AccuracyReport: Sendable {
    // Point-estimate MAPE (%) over the SCORED eval meals (Req 21.3).
    public let mape: Float
    // Point-estimate MAE (g) over the SCORED eval meals.
    public let mae: Float
    // CI (bootstrap 95%) per Req 21.8 — nil when scored n < 30.
    public let ci95Lower: Float?
    public let ci95Upper: Float?
    // Per-class breakdown distinguishing cal/pooled/unity statuses (Req 21.4).
    public let perClassStats: [String: ClassAccuracyStats]
    // Per-stage latency keyed by stage name, then by capturePath raw value (Req 21.5).
    public let latencyStats: [String: [String: LatencyStats]]
    // Meals carrying usable ground truth, and those that do not. Device capture
    // bundles record truth as zero by design (back-filled off-device), so an
    // unscored count is the normal case for a field replay, not an error.
    public let scoredCount: Int
    public let unscoredCount: Int
    // Per-meal rows, scored and unscored alike, in input order.
    public let rows: [MealErrorRow]
    // Req 4.4: the fallback rate over the corpus. Independent of scoring — a field
    // replay scores nothing, and that is the run whose rate matters most.
    public let fallback: FallbackRateReport

    // Whether the accuracy bar is met (MAPE < 20% AND MAE ≤ 25 g, per Req 21.3).
    // A run that scored nothing cannot pass a bar it never measured.
    public var passesBar: Bool { scoredCount > 0 && mape < 20.0 && mae <= 25.0 }
}

// Computes MAPE, MAE, per-class breakdown, and latency stats from eval meals.
public enum AccuracyHarness {

    public static func evaluate(meals: [MealEvalInput]) -> AccuracyReport {
        let rows = meals.map { m -> MealErrorRow in
            let predicted = m.predictedCarbsPerClass.values.reduce(0, +)
            let truth = m.groundTruthTotalCarbsG
            let scored = isScorable(truth)
            return MealErrorRow(
                fixtureID: m.fixtureID,
                capturePath: m.capturePath.rawValue,
                groundTruthCarbsG: truth,
                predictedCarbsG: predicted,
                absoluteErrorG: scored ? abs(predicted - truth) : nil,
                percentError: scored ? abs(predicted - truth) / truth * 100 : nil
            )
        }

        // Only meals with usable ground truth contribute to MAPE/MAE. Scoring an
        // untruthed meal against zero yields MAPE 0% and MAE = the predicted
        // grams — a confident pass on a measurement that never happened.
        let scoredMeals = meals.filter { isScorable($0.groundTruthTotalCarbsG) }
        let unscoredCount = meals.count - scoredMeals.count

        guard !scoredMeals.isEmpty else {
            return AccuracyReport(
                mape: 0, mae: 0, ci95Lower: nil, ci95Upper: nil,
                perClassStats: perClassStats(meals: meals),
                latencyStats: latencyStats(meals: meals),
                scoredCount: 0, unscoredCount: unscoredCount, rows: rows,
                fallback: fallbackRate(meals: meals)
            )
        }

        // Total predicted carbs per scored meal.
        let predictedTotals = scoredMeals.map { m in
            m.predictedCarbsPerClass.values.reduce(0, +)
        }
        let groundTruths = scoredMeals.map(\.groundTruthTotalCarbsG)

        let mape = pointMAPE(predicted: predictedTotals, actual: groundTruths)
        let mae  = pointMAE(predicted: predictedTotals, actual: groundTruths)

        let (ciLower, ciUpper): (Float?, Float?)
        if scoredMeals.count >= 30 {
            let ci = bootstrapCI95(predicted: predictedTotals, actual: groundTruths)
            ciLower = ci.lower
            ciUpper = ci.upper
        } else {
            ciLower = nil
            ciUpper = nil
        }

        // Per-class and latency breakdowns are descriptive of the whole run
        // (they report predicted distribution, status and timing, not error),
        // so they stay over every meal.
        let perClass = perClassStats(meals: meals)
        let latency  = latencyStats(meals: meals)

        return AccuracyReport(
            mape: mape, mae: mae,
            ci95Lower: ciLower, ci95Upper: ciUpper,
            perClassStats: perClass,
            latencyStats: latency,
            scoredCount: scoredMeals.count,
            unscoredCount: unscoredCount,
            rows: rows,
            fallback: fallbackRate(meals: meals)
        )
    }

    // A meal is scorable when it carries a finite, strictly positive truth.
    // Proto3 defaults an unset ground_truth_total_carbs_g to 0.
    static func isScorable(_ truth: Float) -> Bool { truth.isFinite && truth > 0 }

    // Aggregate the reference each attempt recorded (Reqs 4.4, 4.5). Computed over
    // EVERY meal, not just the scored ones: ground truth and plane selection are
    // independent, and the corpus that most needs the rate is the untruthed one.
    static func fallbackRate(meals: [MealEvalInput]) -> FallbackRateReport {
        var counts: [String: Int] = [:]
        var unreported = 0
        for m in meals {
            guard let reference = m.supportPlaneReference else { unreported += 1; continue }
            counts[reference.rawValue, default: 0] += 1
        }
        let depthDerived = meals.count - unreported
        let fallbacks = counts[SupportPlaneReference.edgeBand.rawValue, default: 0]
        return FallbackRateReport(
            countsByReference: counts,
            unreportedCount: unreported,
            depthDerivedCount: depthDerived,
            fallbackCount: fallbacks,
            fallbackRate: depthDerived > 0 ? Float(fallbacks) / Float(depthDerived) : nil
        )
    }

    // MARK: - Metric helpers

    static func pointMAPE(predicted: [Float], actual: [Float]) -> Float {
        guard !predicted.isEmpty else { return 0 }
        let sum = zip(predicted, actual).map { (pred, act) -> Float in
            guard act > 0 else { return 0 }
            return abs(pred - act) / act * 100
        }.reduce(0, +)
        return sum / Float(predicted.count)
    }

    static func pointMAE(predicted: [Float], actual: [Float]) -> Float {
        guard !predicted.isEmpty else { return 0 }
        return zip(predicted, actual).map { abs($0 - $1) }.reduce(0, +) / Float(predicted.count)
    }

    // Stratified bootstrap CI for MAPE (1000 resamples).
    static func bootstrapCI95(predicted: [Float], actual: [Float]) -> (lower: Float, upper: Float) {
        let n = predicted.count
        var mapes = [Float]()
        mapes.reserveCapacity(1000)
        // Deterministic seed for reproducibility.
        var rng = SplitMix64(seed: 0xDEAD_BEEF_CAFE_BABE)
        for _ in 0..<1000 {
            var sampPred = [Float]()
            var sampAct  = [Float]()
            sampPred.reserveCapacity(n)
            sampAct.reserveCapacity(n)
            for _ in 0..<n {
                let idx = Int(rng.next() % UInt64(n))
                sampPred.append(predicted[idx])
                sampAct.append(actual[idx])
            }
            mapes.append(pointMAPE(predicted: sampPred, actual: sampAct))
        }
        mapes.sort()
        return (mapes[24], mapes[974])   // 2.5th and 97.5th percentile
    }

    // Per-class MAPE/MAE, grouped by calibration status.
    static func perClassStats(meals: [MealEvalInput]) -> [String: ClassAccuracyStats] {
        // Gather all class names.
        let classes = Set(meals.flatMap { $0.predictedCarbsPerClass.keys })
        var result: [String: ClassAccuracyStats] = [:]
        for c in classes {
            let mealsWithClass = meals.filter { $0.predictedCarbsPerClass[c] != nil }
            guard !mealsWithClass.isEmpty else { continue }
            let pred = mealsWithClass.map { $0.predictedCarbsPerClass[c]! }
            // Per-class ground-truth is not available directly in MealEvalInput.
            // AccuracyHarness works at meal-total level; per-class breakdown reports
            // predicted distribution and status only.
            let status = mealsWithClass.compactMap { $0.statusPerClass[c] }.first ?? .uncalibratedUnity
            let dummy: [Float] = Array(repeating: 0, count: pred.count)
            result[c] = ClassAccuracyStats(
                mape: pointMAPE(predicted: pred, actual: dummy),
                mae: pointMAE(predicted: pred, actual: dummy),
                sampleCount: mealsWithClass.count,
                calibrationStatus: status
            )
        }
        return result
    }

    // Per-stage latency breakdown by capturePath.
    static func latencyStats(meals: [MealEvalInput]) -> [String: [String: LatencyStats]] {
        // Collect durations: stage → path → [duration]
        var byStage: [String: [String: [Double]]] = [:]
        for m in meals {
            let pathKey = m.capturePath.rawValue
            for (stage, dur) in m.stageLatenciesSeconds {
                byStage[stage, default: [:]][pathKey, default: []].append(dur)
            }
        }
        return byStage.mapValues { byPath in
            byPath.mapValues { durations in
                let sorted = durations.sorted()
                let n = sorted.count
                return LatencyStats(
                    p50: sorted[max(0, Int(Double(n) * 0.50) - 1)],
                    p95: sorted[max(0, Int(Double(n) * 0.95) - 1)],
                    mean: sorted.reduce(0, +) / Double(n)
                )
            }
        }
    }
}

// MARK: - N5k calibration eval (nutrition5k-calibration Req 4.4/4.5/6.1–6.8)

// Which estimator fitted a plate's β (Req 3.7). Only single-dominant carries
// the Req 5.1 masking guarantee; the pool report breaks samples out per path.
public enum EstimatorPath: String, Sendable, Codable {
    case singleDominant = "single_dominant"
    case mixture
}

// One evaluated plate. GT macros come from N5k per-ingredient values (mapped
// classes only, Req 6.2/6.6) — NOT re-derived from the DB composition, so a
// composition-source error is visible to the Req 6.7 cross-macro check.
public struct N5kEvalPlate: Sendable {
    public let fixtureID: String
    public let estimatorPath: EstimatorPath
    public let totalHullVolumeCm3: Float
    public let massByClassG: [String: Float]
    public let gtCarbsByClassG: [String: Float]
    public let gtProteinByClassG: [String: Float]
    public let gtFatByClassG: [String: Float]
    public let wholeDishCarbsG: Float          // full GT incl unmapped (Req 6.8)
    public let inOfficialTestSplit: Bool

    public init(fixtureID: String, estimatorPath: EstimatorPath,
                totalHullVolumeCm3: Float, massByClassG: [String: Float],
                gtCarbsByClassG: [String: Float], gtProteinByClassG: [String: Float],
                gtFatByClassG: [String: Float], wholeDishCarbsG: Float,
                inOfficialTestSplit: Bool) {
        self.fixtureID = fixtureID
        self.estimatorPath = estimatorPath
        self.totalHullVolumeCm3 = totalHullVolumeCm3
        self.massByClassG = massByClassG
        self.gtCarbsByClassG = gtCarbsByClassG
        self.gtProteinByClassG = gtProteinByClassG
        self.gtFatByClassG = gtFatByClassG
        self.wholeDishCarbsG = wholeDishCarbsG
        self.inOfficialTestSplit = inOfficialTestSplit
    }
}

// Per-class DB values used to turn attributed volume into macro estimates —
// the same ρ and fractions the pipeline uses at inference (Req 5.3).
public struct ClassComposition: Sendable {
    public let densityByClass: [String: Float]
    public let carbFractionPer100g: [String: Float]
    public let proteinFractionPer100g: [String: Float]
    public let fatFractionPer100g: [String: Float]

    public init(densityByClass: [String: Float],
                carbFractionPer100g: [String: Float],
                proteinFractionPer100g: [String: Float],
                fatFractionPer100g: [String: Float]) {
        self.densityByClass = densityByClass
        self.carbFractionPer100g = carbFractionPer100g
        self.proteinFractionPer100g = proteinFractionPer100g
        self.fatFractionPer100g = fatFractionPer100g
    }
}

public struct CalibrationEvalConfig: Sendable {
    public let folds: Int
    public let seed: UInt64                    // ONE seed: selection + folds (Req 4.4)
    public let liquidClasses: Set<String>
    public let carbPriorityStaples: [String]

    public init(folds: Int = 5, seed: UInt64,
                liquidClasses: Set<String> = [],
                carbPriorityStaples: [String]) {
        self.folds = folds
        self.seed = seed
        self.liquidClasses = liquidClasses
        self.carbPriorityStaples = carbPriorityStaples
    }
}

// β=1.0 baseline and β_c figures side by side (Req 6.3).
public struct MacroAccuracy: Sendable {
    public let mapeBaseline: Float
    public let mapeCalibrated: Float
    public let maeBaseline: Float
    public let maeCalibrated: Float
    public let sampleCount: Int
}

public struct MacroSection: Sendable {
    public let overall: MacroAccuracy
    public let perStaple: [String: MacroAccuracy]
}

// Whole-dish figures on the official depth test split (Req 6.8, Decision 21).
public struct OfficialSplitReport: Sendable {
    public let maeBaselineG: Float
    public let maeCalibratedG: Float
    public let maeOverMeanBaseline: Float
    public let maeOverMeanCalibrated: Float
    public let evaluatedDishCount: Int
    public let splitTotalCount: Int            // enumerates Req 3.4/3.8 skips
    public let mappedCarbCoverageFraction: Float
    public let caveat: String
}

// Upstream counts the harness cannot derive itself (Req 4.5 pool arithmetic).
public struct PoolCounts: Sendable {
    public let rgbdDishCount: Int
    public let depthTestSplitCount: Int
    public let ingestionSkipCount: Int
    // Mixture plates excluded for unmapped mass above the ingestion threshold
    // (Req 4.1, design §Unmapped-volume bias) — from the ingestion run summary.
    public let unmappedExcludedCount: Int

    public init(rgbdDishCount: Int, depthTestSplitCount: Int, ingestionSkipCount: Int,
                unmappedExcludedCount: Int = 0) {
        self.rgbdDishCount = rgbdDishCount
        self.depthTestSplitCount = depthTestSplitCount
        self.ingestionSkipCount = ingestionSkipCount
        self.unmappedExcludedCount = unmappedExcludedCount
    }
}

public struct PoolReport: Sendable {
    public let rgbdDishCount: Int
    public let depthTestSplitCount: Int
    public let ingestionSkipCount: Int
    public let unmappedExcludedCount: Int      // Req 4.1
    public let liquidExcludedCount: Int        // Req 4.7
    public let stackingExcludedCount: Int      // Req 4.3
    public let qualifyingPlateCount: Int
    // estimator path raw value → class → plates at mass fraction ≥ τ_eff.
    public let effectiveSamplesByPath: [String: [String: Int]]
    // Documented accepted outcomes, not failures (Req 4.5).
    public let insufficientClasses: [String]
}

public struct CalibrationReport: Sendable {
    public let seed: UInt64
    public let foldCount: Int
    public let carbs: MacroSection
    public let protein: MacroSection
    public let fat: MacroSection
    // Per-class β dispersion; mixture classes carry the regression SE (Req 6.4).
    public let dispersionPerClass: [String: Float]
    // Reported result, not a bake gate (Req 6.5, Decision 6).
    public let mapeTargetPercent: Float
    public let staplesMeetingTarget: [String: Bool]
    // Classes whose carb agrees but protein/fat diverges (Req 6.7).
    public let crossMacroFlags: [String]
    public let officialSplit: OfficialSplitReport
    public let pool: PoolReport
}

public extension AccuracyHarness {
    // Documented cross-macro tolerance (Req 6.7): flag when protein or fat
    // MAPE exceeds 1.5× the class carb MAPE. The 5-point absolute floor stops
    // the ratio test firing on numerically tiny errors.
    static let crossMacroToleranceFactor: Float = 1.5
    static let crossMacroAbsoluteFloorPercent: Float = 5

    static let officialSplitCaveat =
        "Whole-dish figures consume ground-truth class identity via the "
        + "ingredient mapping; they are reported alongside, not claimed "
        + "comparable with, the Nutrition5k paper's image-only RGB-D baseline "
        + "(Table 3). The β_c-vs-baseline judgement lives in the mapped-only "
        + "figures (Req 6.3)."

    // K-fold CV over the calibration pool plus the official-split whole-dish
    // section and the Req 4.5 pool arithmetic. The bake itself fits on ALL
    // qualifying plates (design §Split reconciliation); the folds exist only
    // so held-out accuracy never strands a staple below the sample floor.
    static func evaluateCalibration(
        calibrationPlates: [N5kEvalPlate],
        officialSplitPlates: [N5kEvalPlate],
        composition: ClassComposition,
        config: CalibrationEvalConfig,
        pool: PoolCounts
    ) -> CalibrationReport {
        // Same plate guards as the calibrator (Req 4.3/4.7), applied to the
        // eval pool so excluded plates neither fit nor score.
        var liquidExcluded = 0
        var stackingExcluded = 0
        var evalPlates: [N5kEvalPlate] = []
        for p in calibrationPlates {
            let totalMass = p.massByClassG.values.reduce(0, +)
            guard totalMass > 0 else { continue }
            let liquidMass = p.massByClassG
                .filter { config.liquidClasses.contains($0.key) }
                .values.reduce(0, +)
            if liquidMass / totalMass >= MixtureBetaCalibrator.liquidSignificantFraction {
                liquidExcluded += 1
                continue
            }
            let expectedMin = p.massByClassG.reduce(Float(0)) { acc, kv in
                guard !config.liquidClasses.contains(kv.key),
                      let rho = composition.densityByClass[kv.key] else { return acc }
                return acc + kv.value / rho
            }
            if p.totalHullVolumeCm3 < MixtureBetaCalibrator.stackingKappa * expectedMin {
                stackingExcluded += 1
                continue
            }
            evalPlates.append(p)
        }

        // Bake fit over ALL qualifying plates: dispersion (Req 6.4), the β_c
        // used on the official split, and pool diagnostics.
        let bakeFit = MixtureBetaCalibrator.fit(
            evalPlates.map(observation(for:)),
            densityByClass: composition.densityByClass,
            liquidClasses: config.liquidClasses)

        // Seeded fold assignment (Req 4.4): shuffle once, round-robin.
        var rng = SplitMix64(seed: config.seed)
        var order = Array(evalPlates.indices)
        for i in stride(from: order.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            order.swapAt(i, j)
        }
        var foldOf = [Int](repeating: 0, count: evalPlates.count)
        for (rank, idx) in order.enumerated() { foldOf[idx] = rank % max(1, config.folds) }

        // Held-out estimates per plate.
        var accum = MacroAccumulators()
        for fold in 0..<max(1, config.folds) {
            let trainObs = evalPlates.indices
                .filter { foldOf[$0] != fold }
                .map { observation(for: evalPlates[$0]) }
            guard !trainObs.isEmpty else { continue }
            let foldFit = MixtureBetaCalibrator.fit(
                trainObs, densityByClass: composition.densityByClass,
                liquidClasses: config.liquidClasses)
            for idx in evalPlates.indices where foldOf[idx] == fold {
                score(plate: evalPlates[idx], beta: foldFit.betaPerClass,
                      composition: composition, liquidClasses: config.liquidClasses,
                      into: &accum)
            }
        }

        let carbs = accum.carbs.section(staples: config.carbPriorityStaples)
        let protein = accum.protein.section(staples: config.carbPriorityStaples)
        let fat = accum.fat.section(staples: config.carbPriorityStaples)

        var meetsTarget: [String: Bool] = [:]
        var crossFlags: [String] = []
        for staple in config.carbPriorityStaples {
            guard let carbAcc = carbs.perStaple[staple] else { continue }
            meetsTarget[staple] = carbAcc.mapeCalibrated < 20
            // Req 6.7: carb agrees (meets the reported target) but protein or
            // fat diverges beyond the documented tolerance.
            if carbAcc.mapeCalibrated < 20 {
                let bound = max(crossMacroToleranceFactor * carbAcc.mapeCalibrated,
                                crossMacroAbsoluteFloorPercent)
                let proteinMAPE = protein.perStaple[staple]?.mapeCalibrated ?? 0
                let fatMAPE = fat.perStaple[staple]?.mapeCalibrated ?? 0
                if proteinMAPE > bound || fatMAPE > bound {
                    crossFlags.append(staple)
                }
            }
        }

        let official = officialSplitSection(
            plates: officialSplitPlates, beta: bakeFit.betaPerClass,
            composition: composition, liquidClasses: config.liquidClasses,
            splitTotal: pool.depthTestSplitCount)

        // Pool arithmetic (Req 4.5): effective samples per estimator path.
        var effectiveByPath: [String: [String: Int]] = [:]
        var effectiveTotal: [String: Int] = [:]
        for p in evalPlates {
            let totalMass = p.massByClassG.values.reduce(0, +)
            guard totalMass > 0 else { continue }
            for (c, m) in p.massByClassG where !config.liquidClasses.contains(c) {
                if m / totalMass >= MixtureBetaCalibrator.tauEff {
                    effectiveByPath[p.estimatorPath.rawValue, default: [:]][c, default: 0] += 1
                    effectiveTotal[c, default: 0] += 1
                }
            }
        }
        let allSolid = Set(evalPlates.flatMap { $0.massByClassG.keys })
            .subtracting(config.liquidClasses)
        let insufficient = allSolid
            .filter { effectiveTotal[$0, default: 0] < MixtureBetaCalibrator.effectiveSampleMin }
            .sorted()

        return CalibrationReport(
            seed: config.seed,
            foldCount: config.folds,
            carbs: carbs, protein: protein, fat: fat,
            dispersionPerClass: bakeFit.standardErrorPerClass,
            mapeTargetPercent: 20,
            staplesMeetingTarget: meetsTarget,
            crossMacroFlags: crossFlags.sorted(),
            officialSplit: official,
            pool: PoolReport(
                rgbdDishCount: pool.rgbdDishCount,
                depthTestSplitCount: pool.depthTestSplitCount,
                ingestionSkipCount: pool.ingestionSkipCount,
                unmappedExcludedCount: pool.unmappedExcludedCount,
                liquidExcludedCount: liquidExcluded,
                stackingExcludedCount: stackingExcluded,
                qualifyingPlateCount: evalPlates.count,
                effectiveSamplesByPath: effectiveByPath,
                insufficientClasses: insufficient
            )
        )
    }

    // MARK: eval internals

    private static func observation(for plate: N5kEvalPlate)
        -> MixtureBetaCalibrator.PlateObservation {
        .init(fixtureID: plate.fixtureID,
              totalHullVolumeCm3: plate.totalHullVolumeCm3,
              massByClassG: plate.massByClassG)
    }

    // Oracle-composition estimate (design §Split reconciliation, a recorded
    // caveat): attribute the measured hull across mapped solid classes by GT
    // mass proportions; each share × ρ_c × β_c × macro-fraction. Liquid-mapped
    // classes contribute zero estimate.
    private static func estimatedMasses(
        plate: N5kEvalPlate, beta: [String: Float],
        composition: ClassComposition, liquidClasses: Set<String>
    ) -> [String: Float] {
        let solid = plate.massByClassG.filter { !liquidClasses.contains($0.key) }
        let totalMass = solid.values.reduce(0, +)
        guard totalMass > 0 else { return [:] }
        var out: [String: Float] = [:]
        for (c, m) in solid {
            guard let rho = composition.densityByClass[c] else { continue }
            let share = m / totalMass
            out[c] = share * plate.totalHullVolumeCm3 * rho * beta[c, default: 1.0]
        }
        return out
    }

    private struct MacroAccumulator {
        var overallPctBase: [Float] = [], overallPctCal: [Float] = []
        var overallAbsBase: [Float] = [], overallAbsCal: [Float] = []
        var perClassPctBase: [String: [Float]] = [:], perClassPctCal: [String: [Float]] = [:]
        var perClassAbsBase: [String: [Float]] = [:], perClassAbsCal: [String: [Float]] = [:]

        mutating func add(class c: String, gt: Float, base: Float, cal: Float) {
            guard gt > 0 else { return }
            perClassPctBase[c, default: []].append(abs(base - gt) / gt * 100)
            perClassPctCal[c, default: []].append(abs(cal - gt) / gt * 100)
            perClassAbsBase[c, default: []].append(abs(base - gt))
            perClassAbsCal[c, default: []].append(abs(cal - gt))
        }

        mutating func addOverall(gt: Float, base: Float, cal: Float) {
            guard gt > 0 else { return }
            overallPctBase.append(abs(base - gt) / gt * 100)
            overallPctCal.append(abs(cal - gt) / gt * 100)
            overallAbsBase.append(abs(base - gt))
            overallAbsCal.append(abs(cal - gt))
        }

        func section(staples: [String]) -> MacroSection {
            func mean(_ xs: [Float]) -> Float {
                xs.isEmpty ? 0 : xs.reduce(0, +) / Float(xs.count)
            }
            var perStaple: [String: MacroAccuracy] = [:]
            for s in staples {
                guard let pctBase = perClassPctBase[s] else { continue }
                perStaple[s] = MacroAccuracy(
                    mapeBaseline: mean(pctBase),
                    mapeCalibrated: mean(perClassPctCal[s] ?? []),
                    maeBaseline: mean(perClassAbsBase[s] ?? []),
                    maeCalibrated: mean(perClassAbsCal[s] ?? []),
                    sampleCount: pctBase.count)
            }
            return MacroSection(
                overall: MacroAccuracy(
                    mapeBaseline: mean(overallPctBase),
                    mapeCalibrated: mean(overallPctCal),
                    maeBaseline: mean(overallAbsBase),
                    maeCalibrated: mean(overallAbsCal),
                    sampleCount: overallPctBase.count),
                perStaple: perStaple)
        }
    }

    private struct MacroAccumulators {
        var carbs = MacroAccumulator()
        var protein = MacroAccumulator()
        var fat = MacroAccumulator()
    }

    private static func score(
        plate: N5kEvalPlate, beta: [String: Float],
        composition: ClassComposition, liquidClasses: Set<String>,
        into accum: inout MacroAccumulators
    ) {
        let massBase = estimatedMasses(plate: plate, beta: [:],
                                       composition: composition, liquidClasses: liquidClasses)
        let massCal = estimatedMasses(plate: plate, beta: beta,
                                      composition: composition, liquidClasses: liquidClasses)
        var totals = (gtC: Float(0), baseC: Float(0), calC: Float(0),
                      gtP: Float(0), baseP: Float(0), calP: Float(0),
                      gtF: Float(0), baseF: Float(0), calF: Float(0))
        for c in massBase.keys {
            let kappa = composition.carbFractionPer100g[c, default: 0] / 100
            let prot = composition.proteinFractionPer100g[c, default: 0] / 100
            let fatF = composition.fatFractionPer100g[c, default: 0] / 100
            let gtC = plate.gtCarbsByClassG[c, default: 0]
            let gtP = plate.gtProteinByClassG[c, default: 0]
            let gtF = plate.gtFatByClassG[c, default: 0]
            let baseC = massBase[c, default: 0] * kappa
            let calC = massCal[c, default: 0] * kappa
            let baseP = massBase[c, default: 0] * prot
            let calP = massCal[c, default: 0] * prot
            let baseF = massBase[c, default: 0] * fatF
            let calF = massCal[c, default: 0] * fatF
            accum.carbs.add(class: c, gt: gtC, base: baseC, cal: calC)
            accum.protein.add(class: c, gt: gtP, base: baseP, cal: calP)
            accum.fat.add(class: c, gt: gtF, base: baseF, cal: calF)
            totals.gtC += gtC; totals.baseC += baseC; totals.calC += calC
            totals.gtP += gtP; totals.baseP += baseP; totals.calP += calP
            totals.gtF += gtF; totals.baseF += baseF; totals.calF += calF
        }
        accum.carbs.addOverall(gt: totals.gtC, base: totals.baseC, cal: totals.calC)
        accum.protein.addOverall(gt: totals.gtP, base: totals.baseP, cal: totals.calP)
        accum.fat.addOverall(gt: totals.gtF, base: totals.baseF, cal: totals.calF)
    }

    private static func officialSplitSection(
        plates: [N5kEvalPlate], beta: [String: Float],
        composition: ClassComposition, liquidClasses: Set<String>,
        splitTotal: Int
    ) -> OfficialSplitReport {
        var absBase: [Float] = []
        var absCal: [Float] = []
        var actuals: [Float] = []
        var mappedCarbs: Float = 0
        var wholeDishCarbs: Float = 0
        for p in plates {
            // Whole-dish basis: unmapped AND liquid-mapped ingredients
            // contribute zero estimate but full GT carbs (Req 6.8).
            let massBase = estimatedMasses(plate: p, beta: [:],
                                           composition: composition, liquidClasses: liquidClasses)
            let massCal = estimatedMasses(plate: p, beta: beta,
                                          composition: composition, liquidClasses: liquidClasses)
            func carbTotal(_ masses: [String: Float]) -> Float {
                masses.reduce(0) { acc, kv in
                    acc + kv.value * composition.carbFractionPer100g[kv.key, default: 0] / 100
                }
            }
            absBase.append(abs(carbTotal(massBase) - p.wholeDishCarbsG))
            absCal.append(abs(carbTotal(massCal) - p.wholeDishCarbsG))
            actuals.append(p.wholeDishCarbsG)
            mappedCarbs += p.gtCarbsByClassG
                .filter { !liquidClasses.contains($0.key) }
                .values.reduce(0, +)
            wholeDishCarbs += p.wholeDishCarbsG
        }
        func mean(_ xs: [Float]) -> Float { xs.isEmpty ? 0 : xs.reduce(0, +) / Float(xs.count) }
        let meanActual = mean(actuals)
        return OfficialSplitReport(
            maeBaselineG: mean(absBase),
            maeCalibratedG: mean(absCal),
            maeOverMeanBaseline: meanActual > 0 ? mean(absBase) / meanActual : 0,
            maeOverMeanCalibrated: meanActual > 0 ? mean(absCal) / meanActual : 0,
            evaluatedDishCount: plates.count,
            splitTotalCount: splitTotal,
            mappedCarbCoverageFraction: wholeDishCarbs > 0 ? mappedCarbs / wholeDishCarbs : 0,
            caveat: officialSplitCaveat
        )
    }
}

// SplitMix64 PRNG — deterministic, no external dependency.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}
#endif

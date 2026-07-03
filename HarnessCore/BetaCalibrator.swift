#if HARNESS_ENABLED
import Foundation
import Foods
import PortableContracts

// Input bundle for one meal in the calibration / evaluation set.
// Predicted carbs are pre-computed with β = 1 (uncorrected).
public struct MealCalibrationInput: Sendable {
    public let fixtureID: String
    public let capturePath: CapturePath
    // Most-prevalent food class; used to stratify the cal/eval split.
    public let dominantClass: String?
    // Per-class predicted carbs (β = 1): V_c^uncal · ρ_c · κ_c / 100
    public let predictedCarbsPerClass: [String: Float]
    // Per-class actual carbs from gravimetric mass: m_c^* · κ_c / 100
    public let actualCarbsPerClass: [String: Float]
    // Ground-truth total for MAPE / MAE
    public let groundTruthTotalCarbsG: Float
    // Per-class uncorrected volumes (β = 1), needed by the τ_purity volume gate
    // on single-dominant N5k fixtures (Req 4.2) — carb ratios cannot stand in
    // for volume ratios because ρ and κ differ per class.
    public let perClassVolumesCm3: [String: Float]
    // Plate-plane fit residual, recorded per plate (Req 3.6).
    public let supportPlaneResidualMm: Float?

    public init(
        fixtureID: String,
        capturePath: CapturePath,
        dominantClass: String?,
        predictedCarbsPerClass: [String: Float],
        actualCarbsPerClass: [String: Float],
        groundTruthTotalCarbsG: Float,
        perClassVolumesCm3: [String: Float] = [:],
        supportPlaneResidualMm: Float? = nil
    ) {
        self.fixtureID = fixtureID
        self.capturePath = capturePath
        self.dominantClass = dominantClass
        self.predictedCarbsPerClass = predictedCarbsPerClass
        self.actualCarbsPerClass = actualCarbsPerClass
        self.groundTruthTotalCarbsG = groundTruthTotalCarbsG
        self.perClassVolumesCm3 = perClassVolumesCm3
        self.supportPlaneResidualMm = supportPlaneResidualMm
    }
}

// Output of the §6.9 calibration pass.
public struct CalibrationResult: Sendable {
    public let betaPerClass: [String: Float]
    public let statusPerClass: [String: BetaCalibrationStatus]
    // β_pool applied to uncalibrated_pooled classes; 1.0 when pool was uncomputable.
    public let betaPool: Float
    // Indices (into the original meals array) in each subset.
    public let calibrationIndices: Set<Int>
    public let evalIndices: Set<Int>
}

// Implements the §6.9 β_c calibration algorithm.
public enum BetaCalibrator {
    // Minimum meals per class required for a `calibrated` status.
    public static let minCalibrationMeals = 30
    static let betaFloor: Float = 0.05

    // Per-class fit statistics for the tightened Req 5.4 gate and the
    // CalibrationMerge arbitration (nutrition5k-calibration design §Extended
    // CalibrationResult). The fit value and clamp are the unchanged §6.9
    // closed form; this only surfaces the spread CalibrationResult discards.
    public struct PerClassFit: Sendable {
        public struct ClassFit: Sendable {
            public let beta: Float
            public let status: BetaCalibrationStatus
            // SE of the mean log-residual, sd(log r)/√n — approximately the
            // relative SE on β. nil when the class did not reach the
            // closed-form fit (under-sampled or degenerate).
            public let logResidualSE: Float?
            // On the single-dominant harness path each qualifying meal is
            // dominated by the class (τ_route at ingestion, τ_purity in the
            // harness), so the meal count IS the effective-sample count.
            public let effectiveSample: Int
            public let clamped: Bool                 // Req 5.6 warning input

            public init(beta: Float, status: BetaCalibrationStatus,
                        logResidualSE: Float?, effectiveSample: Int, clamped: Bool) {
                self.beta = beta
                self.status = status
                self.logResidualSE = logResidualSE
                self.effectiveSample = effectiveSample
                self.clamped = clamped
            }
        }
        public let classes: [String: ClassFit]
        public let betaPool: Float

        public init(classes: [String: ClassFit], betaPool: Float) {
            self.classes = classes
            self.betaPool = betaPool
        }
    }

    // Run §6.9 calibration. Returns per-class β values and the cal/eval split.
    public static func calibrate(meals: [MealCalibrationInput]) -> CalibrationResult {
        calibrateWithFit(meals: meals).result
    }

    // §6.9 calibration plus the per-class spread outputs (log-residual SE,
    // effective-sample count, clamped flag). `fit` describes exactly the same
    // split-based fit as `result` — same closed form, same clamp, same meals —
    // it only surfaces the spread that CalibrationResult discards. Callers that
    // want the no-holdout bake basis (design §Split reconciliation) pass all
    // qualifying plates and take the fit's numbers from that run.
    public static func calibrateWithFit(
        meals: [MealCalibrationInput]
    ) -> (result: CalibrationResult, fit: PerClassFit) {
        let (calIdx, evalIdx) = stratifiedSplit(meals: meals, calFraction: 0.6)
        let calMeals = calIdx.sorted().map { meals[$0] }

        let split = fitClasses(over: calMeals)
        let result = CalibrationResult(
            betaPerClass: split.beta,
            statusPerClass: split.status,
            betaPool: split.betaPool,
            calibrationIndices: calIdx,
            evalIndices: evalIdx
        )

        var classes: [String: PerClassFit.ClassFit] = [:]
        for c in split.counts.keys {
            classes[c] = PerClassFit.ClassFit(
                beta: split.beta[c] ?? 1.0,
                status: split.status[c] ?? .uncalibratedUnity,
                logResidualSE: split.logResidualSE[c],
                effectiveSample: split.counts[c] ?? 0,
                clamped: split.clamped.contains(c)
            )
        }
        return (result, PerClassFit(classes: classes, betaPool: split.betaPool))
    }

    // The §6.9 per-class closed form + pooled fallback over one meal set.
    private struct ClassFitOutputs {
        var beta: [String: Float] = [:]
        var status: [String: BetaCalibrationStatus] = [:]
        var logResidualSE: [String: Float] = [:]
        var counts: [String: Int] = [:]
        var clamped: Set<String> = []
        var betaPool: Float = 1.0
    }

    private static func fitClasses(over meals: [MealCalibrationInput]) -> ClassFitOutputs {
        let allClasses = Set(meals.flatMap { $0.predictedCarbsPerClass.keys })
        var out = ClassFitOutputs()
        var underSampledClasses: Set<String> = []

        for c in allClasses.sorted() {
            let classMeals = meals.filter {
                $0.predictedCarbsPerClass[c] != nil && $0.actualCarbsPerClass[c] != nil
            }
            out.counts[c] = classMeals.count
            guard classMeals.count >= minCalibrationMeals else {
                underSampledClasses.insert(c)
                out.status[c] = .uncalibratedPooled
                continue
            }
            // Denominator-collapse guard: any near-zero predicted carb invalidates the fit.
            let hasTiny = classMeals.contains { ($0.predictedCarbsPerClass[c] ?? 0) < 1e-9 }
            if hasTiny {
                underSampledClasses.insert(c)
                out.status[c] = .uncalibratedPooled
                continue
            }
            // Log-residual (geometric-mean) closed form per §6.9.
            let logs = classMeals
                .map { m -> Float in log(m.actualCarbsPerClass[c]! / m.predictedCarbsPerClass[c]!) }
            let logBeta = logs.reduce(0, +) / Float(logs.count)
            var beta = exp(logBeta)
            let betaMax: Float = dominantPath(meals: classMeals) == .twoViewSfS ? 1.0 : 1.5
            if beta < betaFloor || beta > betaMax {
                beta = max(betaFloor, min(betaMax, beta))
                out.clamped.insert(c)
            }
            out.beta[c] = beta
            out.status[c] = .calibrated
            let variance = logs.map { ($0 - logBeta) * ($0 - logBeta) }.reduce(0, +)
                / Float(max(1, logs.count - 1))
            out.logResidualSE[c] = variance.squareRoot() / Float(logs.count).squareRoot()
        }

        // Pooled fallback over all under-sampled classes combined.
        let pooledMeals = meals.filter { m in
            m.predictedCarbsPerClass.keys.contains { underSampledClasses.contains($0) }
        }
        if pooledMeals.count >= minCalibrationMeals {
            out.betaPool = computePoolBeta(meals: pooledMeals, classes: underSampledClasses)
            for c in underSampledClasses {
                out.beta[c] = out.betaPool
                // status remains .uncalibratedPooled
            }
        } else {
            out.betaPool = 1.0
            for c in underSampledClasses {
                out.beta[c] = 1.0
                out.status[c] = .uncalibratedUnity
            }
        }
        return out
    }

    // MARK: - Private helpers

    // Stratified 60/40 split by (capturePath, dominantClass).
    static func stratifiedSplit(
        meals: [MealCalibrationInput],
        calFraction: Float
    ) -> (cal: Set<Int>, eval: Set<Int>) {
        var strata: [String: [Int]] = [:]
        for (i, m) in meals.enumerated() {
            let key = "\(m.capturePath.rawValue)|\(m.dominantClass ?? "__none__")"
            strata[key, default: []].append(i)
        }
        var cal: Set<Int> = []
        var eval: Set<Int> = []
        for indices in strata.values.map({ $0.sorted() }) {
            let nCal = max(1, Int((Float(indices.count) * calFraction).rounded()))
            for (offset, idx) in indices.enumerated() {
                if offset < nCal { cal.insert(idx) } else { eval.insert(idx) }
            }
        }
        return (cal, eval)
    }

    // Dominant capture path (by count) in a set of meals.
    static func dominantPath(meals: [MealCalibrationInput]) -> CapturePath {
        let twoView = meals.filter { $0.capturePath == .twoViewSfS }.count
        return twoView * 2 >= meals.count ? .twoViewSfS : .singleViewLidar
    }

    // Log-residual β_pool over pooled under-sampled classes.
    static func computePoolBeta(meals: [MealCalibrationInput], classes: Set<String>) -> Float {
        var logSum: Float = 0
        var count = 0
        for m in meals {
            for c in classes {
                guard let pred = m.predictedCarbsPerClass[c],
                      let actual = m.actualCarbsPerClass[c],
                      pred >= 1e-9 else { continue }
                logSum += log(actual / pred)
                count += 1
            }
        }
        return count > 0 ? exp(logSum / Float(count)) : 1.0
    }
}
#endif

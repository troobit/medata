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

    public init(
        fixtureID: String,
        capturePath: CapturePath,
        dominantClass: String?,
        predictedCarbsPerClass: [String: Float],
        actualCarbsPerClass: [String: Float],
        groundTruthTotalCarbsG: Float
    ) {
        self.fixtureID = fixtureID
        self.capturePath = capturePath
        self.dominantClass = dominantClass
        self.predictedCarbsPerClass = predictedCarbsPerClass
        self.actualCarbsPerClass = actualCarbsPerClass
        self.groundTruthTotalCarbsG = groundTruthTotalCarbsG
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

    // Run §6.9 calibration. Returns per-class β values and the cal/eval split.
    public static func calibrate(meals: [MealCalibrationInput]) -> CalibrationResult {
        let (calIdx, evalIdx) = stratifiedSplit(meals: meals, calFraction: 0.6)
        let calMeals = calIdx.sorted().map { meals[$0] }

        let allClasses = Set(calMeals.flatMap { $0.predictedCarbsPerClass.keys })

        var betaPerClass: [String: Float] = [:]
        var statusPerClass: [String: BetaCalibrationStatus] = [:]
        var underSampledClasses: Set<String> = []

        for c in allClasses.sorted() {
            let classMeals = calMeals.filter {
                $0.predictedCarbsPerClass[c] != nil && $0.actualCarbsPerClass[c] != nil
            }
            guard classMeals.count >= minCalibrationMeals else {
                underSampledClasses.insert(c)
                statusPerClass[c] = .uncalibratedPooled
                continue
            }
            // Denominator-collapse guard: any near-zero predicted carb invalidates the fit.
            let hasTiny = classMeals.contains { ($0.predictedCarbsPerClass[c] ?? 0) < 1e-9 }
            if hasTiny {
                underSampledClasses.insert(c)
                statusPerClass[c] = .uncalibratedPooled
                continue
            }
            // Log-residual (geometric-mean) closed form per §6.9.
            let logBeta = classMeals
                .map { m -> Float in log(m.actualCarbsPerClass[c]! / m.predictedCarbsPerClass[c]!) }
                .reduce(0, +) / Float(classMeals.count)
            var beta = exp(logBeta)
            let betaMax: Float = dominantPath(meals: classMeals) == .twoViewSfS ? 1.0 : 1.5
            if beta < betaFloor || beta > betaMax {
                beta = max(betaFloor, min(betaMax, beta))
            }
            betaPerClass[c] = beta
            statusPerClass[c] = .calibrated
        }

        // Pooled fallback over all under-sampled classes combined.
        let pooledMeals = calMeals.filter { m in
            m.predictedCarbsPerClass.keys.contains { underSampledClasses.contains($0) }
        }
        let betaPool: Float
        if pooledMeals.count >= minCalibrationMeals {
            betaPool = computePoolBeta(meals: pooledMeals, classes: underSampledClasses)
            for c in underSampledClasses {
                betaPerClass[c] = betaPool
                // statusPerClass[c] remains .uncalibratedPooled
            }
        } else {
            betaPool = 1.0
            for c in underSampledClasses {
                betaPerClass[c] = 1.0
                statusPerClass[c] = .uncalibratedUnity
            }
        }

        return CalibrationResult(
            betaPerClass: betaPerClass,
            statusPerClass: statusPerClass,
            betaPool: betaPool,
            calibrationIndices: calIdx,
            evalIndices: evalIdx
        )
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

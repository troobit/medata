#if HARNESS_ENABLED
import Foods
import Foundation

// Cross-dataset accuracy reporting (cross-dataset-calibration Reqs 8.2, 10.1,
// 10.2, design §Reporting). Everything here is REPORTED, never a bake gate
// (Decision 9): the held-out anchor and the carb delta exist so the coverage
// gain can be judged, not so it can block.

// Per-class coverage row: effective sample and status before (N5k-only) vs
// after (combined), and the β change attributable to adding MetaFood3D
// (Req 8.2, 10.1).
public struct BetaCoverageDelta: Sendable, Equatable {
    public let betaBefore: Float
    public let betaAfter: Float
    public let betaDelta: Float
    public let effectiveSampleBefore: Int
    public let effectiveSampleAfter: Int
    public let statusBefore: String
    public let statusAfter: String
}

// Carb MAPE/MAE on the N5k eval pool under the baseline (N5k-only) versus the
// combined β (Req 10.1).
public struct CarbDeltaReport: Sendable {
    public struct ClassDelta: Sendable, Equatable {
        public let mapeBaseline: Float
        public let mapeCombined: Float
        public let maeBaseline: Float
        public let maeCombined: Float
        public let evalPlateCount: Int
    }

    public let overall: ClassDelta
    // Per-class deltas ONLY above the minimum eval-plate count; classes with
    // fewer scored plates land in `suppressedBelowMinCount` with their count,
    // so a thin per-class figure is absent rather than misleading.
    public let perClass: [String: ClassDelta]
    public let suppressedBelowMinCount: [String: Int]
    // Staples with NO eval plates at all: no in-harness accuracy validation
    // exists for them, and the report says so by name (Req 10.1).
    public let unvalidatedStaples: [String]
    public let minEvalPlateCount: Int
}

// Held-out MetaFood3D anchor (Req 10.2): predicted mass = V_est·β·ρ_DB on
// objects excluded from the fit. Reported, not a bake gate.
public struct HeldOutAnchorReport: Sendable {
    // nil when nothing was scorable — absent, not zero.
    public let massMAPEPercent: Float?
    public let sampleCount: Int
    public let perClassMAPE: [String: Float]
    // The one overlapping calibrated N5k class (design §Reporting): its
    // anchor MAPE where broccoli objects are present, nil otherwise.
    public let broccoliCrossCheckMAPE: Float?
    // Objects skipped for a missing density or non-positive volume/mass.
    public let unscoredCount: Int
}

// One held-out single-food object.
public struct SingleFoodObservation: Sendable {
    public let fixtureID: String
    public let className: String
    public let estimatedVolumeCm3: Float
    public let groundTruthMassG: Float

    public init(fixtureID: String, className: String,
                estimatedVolumeCm3: Float, groundTruthMassG: Float) {
        self.fixtureID = fixtureID
        self.className = className
        self.estimatedVolumeCm3 = estimatedVolumeCm3
        self.groundTruthMassG = groundTruthMassG
    }
}

public extension AccuracyHarness {
    // Documented floor for a per-class accuracy delta (Req 10.1): below this
    // many scored eval plates a per-class MAPE is sampling noise, so the
    // class is suppressed from the per-class table and listed with its count.
    static let minEvalPlateCountForClassDelta = 10

    // Per-class β/coverage delta between the N5k-only and combined merges
    // (Req 8.2, 10.1). Every class present on either side gets a row — a
    // class absent before reads its unity/pool state from `after` only when
    // it exists there, and vice versa.
    static func betaCoverageDelta(
        before: [String: CalibrationMerge.ClassCalibration],
        after: [String: CalibrationMerge.ClassCalibration]
    ) -> [String: BetaCoverageDelta] {
        var out: [String: BetaCoverageDelta] = [:]
        for c in Set(before.keys).union(after.keys) {
            let b = before[c]
            let a = after[c]
            let betaBefore = b?.beta ?? 1.0
            let betaAfter = a?.beta ?? betaBefore
            out[c] = BetaCoverageDelta(
                betaBefore: betaBefore,
                betaAfter: betaAfter,
                betaDelta: betaAfter - betaBefore,
                effectiveSampleBefore: b?.effectiveSample ?? 0,
                effectiveSampleAfter: a?.effectiveSample ?? 0,
                statusBefore: b?.status.rawValue
                    ?? BetaCalibrationStatus.uncalibratedUnity.rawValue,
                statusAfter: a?.status.rawValue
                    ?? BetaCalibrationStatus.uncalibratedUnity.rawValue)
        }
        return out
    }

    // Carb accuracy under baseline vs combined β over the N5k eval pool
    // (Req 10.1). Attribution mirrors the k-fold eval's oracle
    // mass-proportion estimate: share of hull volume by GT mass, × ρ_c × β_c
    // × κ_c. Per-class deltas are gated on the eval-plate floor; staples with
    // no eval plates are named as having no in-harness accuracy validation.
    static func carbAccuracyDelta(
        plates: [N5kEvalPlate],
        baselineBeta: [String: Float],
        combinedBeta: [String: Float],
        composition: ClassComposition,
        liquidClasses: Set<String> = [],
        staples: [String],
        minEvalPlateCount: Int = minEvalPlateCountForClassDelta
    ) -> CarbDeltaReport {
        var overallPctBase: [Float] = [], overallPctComb: [Float] = []
        var overallAbsBase: [Float] = [], overallAbsComb: [Float] = []
        var perClassPctBase: [String: [Float]] = [:], perClassPctComb: [String: [Float]] = [:]
        var perClassAbsBase: [String: [Float]] = [:], perClassAbsComb: [String: [Float]] = [:]

        func estimatedCarbs(_ plate: N5kEvalPlate, beta: [String: Float]) -> [String: Float] {
            let solid = plate.massByClassG.filter { !liquidClasses.contains($0.key) }
            let totalMass = solid.values.reduce(0, +)
            guard totalMass > 0 else { return [:] }
            var out: [String: Float] = [:]
            for (c, m) in solid {
                guard let rho = composition.densityByClass[c] else { continue }
                let share = m / totalMass
                let mass = share * plate.totalHullVolumeCm3 * rho * beta[c, default: 1.0]
                out[c] = mass * composition.carbFractionPer100g[c, default: 0] / 100
            }
            return out
        }

        for plate in plates {
            let base = estimatedCarbs(plate, beta: baselineBeta)
            let comb = estimatedCarbs(plate, beta: combinedBeta)
            var gtTotal: Float = 0, baseTotal: Float = 0, combTotal: Float = 0
            for c in base.keys {
                let gt = plate.gtCarbsByClassG[c, default: 0]
                gtTotal += gt
                baseTotal += base[c, default: 0]
                combTotal += comb[c, default: 0]
                guard gt > 0 else { continue }
                perClassPctBase[c, default: []].append(abs(base[c, default: 0] - gt) / gt * 100)
                perClassPctComb[c, default: []].append(abs(comb[c, default: 0] - gt) / gt * 100)
                perClassAbsBase[c, default: []].append(abs(base[c, default: 0] - gt))
                perClassAbsComb[c, default: []].append(abs(comb[c, default: 0] - gt))
            }
            if gtTotal > 0 {
                overallPctBase.append(abs(baseTotal - gtTotal) / gtTotal * 100)
                overallPctComb.append(abs(combTotal - gtTotal) / gtTotal * 100)
                overallAbsBase.append(abs(baseTotal - gtTotal))
                overallAbsComb.append(abs(combTotal - gtTotal))
            }
        }

        func mean(_ xs: [Float]) -> Float {
            xs.isEmpty ? 0 : xs.reduce(0, +) / Float(xs.count)
        }

        var perClass: [String: CarbDeltaReport.ClassDelta] = [:]
        var suppressed: [String: Int] = [:]
        for (c, pctBase) in perClassPctBase {
            if pctBase.count >= minEvalPlateCount {
                perClass[c] = CarbDeltaReport.ClassDelta(
                    mapeBaseline: mean(pctBase),
                    mapeCombined: mean(perClassPctComb[c] ?? []),
                    maeBaseline: mean(perClassAbsBase[c] ?? []),
                    maeCombined: mean(perClassAbsComb[c] ?? []),
                    evalPlateCount: pctBase.count)
            } else {
                suppressed[c] = pctBase.count
            }
        }
        let unvalidated = staples.filter { perClassPctBase[$0] == nil }.sorted()

        return CarbDeltaReport(
            overall: CarbDeltaReport.ClassDelta(
                mapeBaseline: mean(overallPctBase),
                mapeCombined: mean(overallPctComb),
                maeBaseline: mean(overallAbsBase),
                maeCombined: mean(overallAbsComb),
                evalPlateCount: overallPctBase.count),
            perClass: perClass,
            suppressedBelowMinCount: suppressed,
            unvalidatedStaples: unvalidated,
            minEvalPlateCount: minEvalPlateCount)
    }

    // Fixed-seed held-out selection (Req 10.2): shuffle the sorted ids with
    // the run seed and take the leading fraction. Deterministic for a given
    // (id set, fraction, seed) regardless of input order.
    static func heldOutSplit(ids: [String], fraction: Float, seed: UInt64) -> Set<String> {
        guard fraction > 0, !ids.isEmpty else { return [] }
        var order = ids.sorted()
        var rng = SplitMix64(seed: seed)
        for i in stride(from: order.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            order.swapAt(i, j)
        }
        let n = min(order.count, Int((Float(order.count) * min(fraction, 1)).rounded()))
        return Set(order.prefix(n))
    }

    // The anchor itself: mass MAPE of V_est·β·ρ_DB over held-out objects.
    static func heldOutAnchor(
        observations: [SingleFoodObservation],
        beta: [String: Float],
        densityByClass: [String: Float]
    ) -> HeldOutAnchorReport {
        var pctByClass: [String: [Float]] = [:]
        var unscored = 0
        for obs in observations {
            guard let rho = densityByClass[obs.className],
                  obs.estimatedVolumeCm3 > 0, obs.groundTruthMassG > 0 else {
                unscored += 1
                continue
            }
            let predicted = obs.estimatedVolumeCm3
                * beta[obs.className, default: 1.0] * rho
            pctByClass[obs.className, default: []].append(
                abs(predicted - obs.groundTruthMassG) / obs.groundTruthMassG * 100)
        }
        let all = pctByClass.values.flatMap { $0 }
        let perClass = pctByClass.mapValues { $0.reduce(0, +) / Float($0.count) }
        return HeldOutAnchorReport(
            massMAPEPercent: all.isEmpty ? nil : all.reduce(0, +) / Float(all.count),
            sampleCount: all.count,
            perClassMAPE: perClass,
            broccoliCrossCheckMAPE: perClass["broccoli"],
            unscoredCount: unscored)
    }
}
#endif

import Foundation

// Promotion gate (Req 7.2, design lane B "Promotion tolerance", Decision 10).
// A model promotion is judged on the SAME meal set under both lineages:
// paired per-meal error deltas remove between-meal variance — the dominant
// noise term at N ≈ 20 — and a seeded bootstrap ties the tolerance to the
// observed dispersion instead of a fixed gram threshold.

public struct PromotionVerdict: Sendable, Equatable {
    public enum Decision: String, Sendable {
        case promote
        case revert
        // A completed-count drop of exactly 1 on the shared set: not an
        // automatic revert, but flagged for the human gate that executes
        // promotions anyway.
        case manualCall
    }

    public let decision: Decision
    // Meals completed under BOTH lineages — the paired-delta population.
    public let pairedMealCount: Int
    // Mean of (new − old) per-meal absolute errors; positive = regression.
    // nil when no meal completed under both lineages.
    public let deltaMAEGrams: Double?
    // One-sided 95% bootstrap lower bound of the mean delta (5th percentile
    // of 10 000 resample means). A lower bound above zero is a CI-confident
    // regression. nil when there are no pairs.
    public let ciLowerBoundGrams: Double?
    // Completed-meal count drop on the shared attempted set (old − new);
    // negative = the candidate completed more.
    public let completedCountDrop: Int

    public init(
        decision: Decision, pairedMealCount: Int, deltaMAEGrams: Double?,
        ciLowerBoundGrams: Double?, completedCountDrop: Int
    ) {
        self.decision = decision
        self.pairedMealCount = pairedMealCount
        self.deltaMAEGrams = deltaMAEGrams
        self.ciLowerBoundGrams = ciLowerBoundGrams
        self.completedCountDrop = completedCountDrop
    }
}

extension BenchmarkReport {

    // Two-tier revert thresholds (design lane B): small noisy regressions can
    // ship; large or statistically confident ones cannot.
    public static let pointRegressionRevertGrams = 2.0
    public static let bootstrapResampleCount = 10_000

    public static func promotionVerdict(
        old: Report, new: Report, seed: UInt64
    ) -> PromotionVerdict {
        // Shared set: meals attempted under both lineages. A meal present in
        // only one report never pairs and never counts as a completion drop —
        // the design's re-run protocol deliberately breaks pairing by minting
        // a new meal when truth cannot be re-plated.
        let oldRows = Dictionary(uniqueKeysWithValues: old.rows.map { ($0.mealID, $0) })
        let sharedNewRows = new.rows.filter { oldRows[$0.mealID] != nil }

        var deltas: [Double] = []
        var oldCompleted = 0
        var newCompleted = 0
        for newRow in sharedNewRows {
            let oldRow = oldRows[newRow.mealID]!
            if oldRow.completed { oldCompleted += 1 }
            if newRow.completed { newCompleted += 1 }
            if let oldError = oldRow.absoluteErrorG, let newError = newRow.absoluteErrorG {
                deltas.append(newError - oldError)
            }
        }
        let completedCountDrop = oldCompleted - newCompleted

        let deltaMAE = deltas.isEmpty ? nil : deltas.reduce(0, +) / Double(deltas.count)
        let ciLowerBound = deltas.isEmpty
            ? nil : bootstrapLowerBound(deltas: deltas, seed: seed)

        let decision: PromotionVerdict.Decision
        if completedCountDrop >= 2 {
            decision = .revert
        } else if let deltaMAE, deltaMAE > pointRegressionRevertGrams {
            // Tier (a): order-of-magnitude bar, significance irrelevant.
            decision = .revert
        } else if let ciLowerBound, ciLowerBound > 0 {
            // Tier (b): any regression whose one-sided 95% CI excludes zero.
            decision = .revert
        } else if completedCountDrop == 1 {
            decision = .manualCall
        } else {
            decision = .promote
        }

        return PromotionVerdict(
            decision: decision,
            pairedMealCount: deltas.count,
            deltaMAEGrams: deltaMAE,
            ciLowerBoundGrams: ciLowerBound,
            completedCountDrop: completedCountDrop
        )
    }

    // 5th percentile of the bootstrap distribution of the mean paired delta:
    // resample the deltas with replacement, same size, 10 000 times.
    // Deterministic for a given seed (SplitMix64; the system generator is not
    // seedable).
    private static func bootstrapLowerBound(deltas: [Double], seed: UInt64) -> Double {
        var rng = SplitMix64(seed: seed)
        let n = deltas.count
        var means: [Double] = []
        means.reserveCapacity(bootstrapResampleCount)
        for _ in 0..<bootstrapResampleCount {
            var sum = 0.0
            for _ in 0..<n {
                sum += deltas[Int(rng.next(upperBound: UInt64(n)))]
            }
            means.append(sum / Double(n))
        }
        means.sort()
        return means[bootstrapResampleCount / 20]
    }
}

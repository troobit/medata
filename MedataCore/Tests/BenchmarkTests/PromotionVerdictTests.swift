import Foundation
import Persistence
import Testing
@testable import Benchmark

// BenchmarkReport.promotionVerdict (Req 7.2, design lane B "Promotion
// tolerance", Decision 10). Paired per-meal error deltas over meals completed
// under BOTH lineages; 10 000 bootstrap resamples of the mean delta with a
// seeded SplitMix64 so the verdict is deterministic and re-runnable. Two-tier
// revert rule: (a) point ΔMAE regression > 2 g reverts regardless of
// significance, (b) any regression whose one-sided 95% CI excludes zero
// reverts, (c) a completed-count drop ≥ 2 on the shared set reverts; a drop
// of exactly 1 marks the verdict for a manual call.

// Builds a Report whose rows carry the given per-meal outcome: a Double is a
// completed meal's absolute error, nil an attempted-but-never-completed meal.
// Aggregates are filled consistently; fields the verdict never reads are
// minimal.
private func report(
    _ outcomes: [(id: UUID, error: Double?)], lineage: String = "L"
) -> Report {
    let rows = outcomes.map { entry in
        Report.MealRow(
            mealID: entry.id,
            name: "m",
            truthCarbsG: 50,
            estimateCarbsG: entry.error.map { 50 + $0 },
            absoluteErrorG: entry.error,
            attemptCount: 1,
            completed: entry.error != nil
        )
    }
    let errors = outcomes.compactMap(\.error)
    return Report(
        lineage: lineage,
        mealCount: rows.count,
        completedMealCount: errors.count,
        completionRate: rows.isEmpty ? 0 : Double(errors.count) / Double(rows.count),
        maeGrams: errors.isEmpty ? nil : errors.reduce(0, +) / Double(errors.count),
        mapePercent: nil,
        within10gShare: nil,
        meanAttemptsPerMeal: rows.isEmpty ? nil : 1,
        totalAttemptCount: rows.count,
        refusedAttemptCount: rows.count - errors.count,
        rows: rows,
        headlineValid: false,
        missingStaples: [],
        anchorVerdict: .insufficientData
    )
}

private func mealIDs(_ count: Int) -> [UUID] {
    (0..<count).map { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", $0))! }
}

@Suite("BenchmarkReport.promotionVerdict")
struct PromotionVerdictTests {

    @Test("same seed reproduces the identical verdict")
    func deterministicForFixedSeed() {
        let ids = mealIDs(3)
        let old = report([(ids[0], 3), (ids[1], 23), (ids[2], 10)])
        let new = report([(ids[0], 6), (ids[1], 19), (ids[2], 12)])
        let first = BenchmarkReport.promotionVerdict(old: old, new: new, seed: 42)
        let second = BenchmarkReport.promotionVerdict(old: old, new: new, seed: 42)
        #expect(first == second)
        #expect(first.pairedMealCount == 3)
        #expect(first.ciLowerBoundGrams != nil)
    }

    // MARK: - Tier (a): point regression > 2 g regardless of significance

    @Test("point regression of exactly 2 g does not trip the order-of-magnitude bar")
    func pointRegressionAtBoundaryPromotes() {
        // Deltas +10 and −6: mean exactly 2, but the bootstrap CI includes
        // zero — neither tier fires.
        let ids = mealIDs(2)
        let old = report([(ids[0], 0), (ids[1], 6)])
        let new = report([(ids[0], 10), (ids[1], 0)])
        let verdict = BenchmarkReport.promotionVerdict(old: old, new: new, seed: 1)
        #expect(verdict.deltaMAEGrams != nil && abs(verdict.deltaMAEGrams! - 2.0) < 1e-9)
        #expect(verdict.decision == .promote)
    }

    @Test("point regression above 2 g reverts even when the CI includes zero")
    func pointRegressionAboveBoundaryReverts() {
        let ids = mealIDs(2)
        let old = report([(ids[0], 0), (ids[1], 6)])
        let new = report([(ids[0], 10.02), (ids[1], 0)])
        let verdict = BenchmarkReport.promotionVerdict(old: old, new: new, seed: 1)
        #expect(verdict.deltaMAEGrams != nil && verdict.deltaMAEGrams! > 2)
        #expect(verdict.decision == .revert)
    }

    // MARK: - Tier (b): CI-confident regression of any size

    @Test("a small but CI-confident regression reverts")
    func confidentSmallRegressionReverts() {
        // Ten pairs, every delta +0.5: mean 0.5 ≤ 2 g, but every bootstrap
        // resample mean is 0.5 — the CI excludes zero.
        let ids = mealIDs(10)
        let old = report(ids.map { ($0, Double?(4)) })
        let new = report(ids.map { ($0, Double?(4.5)) })
        let verdict = BenchmarkReport.promotionVerdict(old: old, new: new, seed: 7)
        #expect(verdict.deltaMAEGrams != nil && abs(verdict.deltaMAEGrams! - 0.5) < 1e-9)
        #expect(verdict.ciLowerBoundGrams != nil && verdict.ciLowerBoundGrams! > 0)
        #expect(verdict.decision == .revert)
    }

    @Test("a consistent improvement promotes")
    func improvementPromotes() {
        let ids = mealIDs(10)
        let old = report(ids.map { ($0, Double?(5)) })
        let new = report(ids.map { ($0, Double?(4)) })
        let verdict = BenchmarkReport.promotionVerdict(old: old, new: new, seed: 7)
        #expect(verdict.deltaMAEGrams != nil && abs(verdict.deltaMAEGrams! + 1.0) < 1e-9)
        #expect(verdict.decision == .promote)
    }

    // MARK: - Tier (c): completed-count drop on the shared set

    @Test("a completed-count drop of 2 reverts even with unchanged errors")
    func completedDropOfTwoReverts() {
        let ids = mealIDs(5)
        let old = report(ids.map { ($0, Double?(5)) })
        let new = report([
            (ids[0], Double?(5)), (ids[1], Double?(5)), (ids[2], Double?(5)),
            (ids[3], nil), (ids[4], nil)  // attempted, refused under the candidate
        ])
        let verdict = BenchmarkReport.promotionVerdict(old: old, new: new, seed: 3)
        #expect(verdict.completedCountDrop == 2)
        #expect(verdict.decision == .revert)
    }

    @Test("a completed-count drop of exactly 1 marks a manual call")
    func completedDropOfOneMarksManualCall() {
        let ids = mealIDs(5)
        let old = report(ids.map { ($0, Double?(5)) })
        let new = report([
            (ids[0], Double?(5)), (ids[1], Double?(5)), (ids[2], Double?(5)),
            (ids[3], Double?(5)), (ids[4], nil)
        ])
        let verdict = BenchmarkReport.promotionVerdict(old: old, new: new, seed: 3)
        #expect(verdict.completedCountDrop == 1)
        #expect(verdict.decision == .manualCall)
    }

    @Test("revert outranks the manual-call marker")
    func revertOutranksManualCall() {
        let ids = mealIDs(5)
        let old = report(ids.map { ($0, Double?(5)) })
        let new = report([
            (ids[0], Double?(10)), (ids[1], Double?(10)), (ids[2], Double?(10)),
            (ids[3], Double?(10)), (ids[4], nil)  // drop 1 AND ΔMAE +5
        ])
        let verdict = BenchmarkReport.promotionVerdict(old: old, new: new, seed: 3)
        #expect(verdict.completedCountDrop == 1)
        #expect(verdict.decision == .revert)
    }

    @Test("a completion gain never penalises")
    func completionGainPromotes() {
        let ids = mealIDs(4)
        let old = report([
            (ids[0], Double?(5)), (ids[1], Double?(5)), (ids[2], nil), (ids[3], nil)
        ])
        let new = report(ids.map { ($0, Double?(5)) })
        let verdict = BenchmarkReport.promotionVerdict(old: old, new: new, seed: 3)
        #expect(verdict.completedCountDrop == -2)
        #expect(verdict.decision == .promote)
    }

    // MARK: - Shared-set scoping

    @Test("meals attempted under only one lineage are outside the shared set")
    func unsharedMealsIgnored() {
        let ids = mealIDs(2)
        // ids[1] was never attempted under the candidate — its absence is not
        // a completion drop; only shared meals compare (design re-run
        // protocol: a re-weighed meal deliberately breaks pairing).
        let old = report([(ids[0], Double?(5)), (ids[1], Double?(5))])
        let new = report([(ids[0], Double?(5))])
        let verdict = BenchmarkReport.promotionVerdict(old: old, new: new, seed: 9)
        #expect(verdict.pairedMealCount == 1)
        #expect(verdict.completedCountDrop == 0)
        #expect(verdict.decision == .promote)
    }

    @Test("no pairs yields nil deltas and falls through to the count rule")
    func noPairsFallsThroughToCountRule() {
        let ids = mealIDs(1)
        let old = report([(ids[0], nil)])
        let new = report([(ids[0], nil)])
        let verdict = BenchmarkReport.promotionVerdict(old: old, new: new, seed: 9)
        #expect(verdict.pairedMealCount == 0)
        #expect(verdict.deltaMAEGrams == nil)
        #expect(verdict.ciLowerBoundGrams == nil)
        #expect(verdict.decision == .promote)
    }
}

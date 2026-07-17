import Foundation
import Persistence
import Testing
@testable import Benchmark

// BenchmarkReport.compute (specs/estimation/snaq-parity Req 1.1/1.4/1.5/1.6,
// design lane B). Pure and deterministic over (meals, outcomes, lineage):
// per-lineage attempt-vs-meal semantics (Decision 9), the SNAQ anchor block
// (Req 1.4), headline-validity floors (Req 1.6), and refusals counted — never
// excluded (Req 1.5). MAE is structurally inseparable from the completion
// rate: both live on the same Report value (Req 1.1).

// MARK: - Fixtures

private let lineage = "coreml_aaa111bbb222"

private func makeMeal(
    name: String = "meal",
    classID: String = "lemon",
    grams: Double = 100,
    truth: Double
) -> BenchmarkMeal {
    BenchmarkMeal(
        name: name,
        createdAtMs: 1_000,
        items: [BenchmarkMealItem(classID: classID, grams: grams)],
        truthCarbsG: truth,
        dbEdition: "e1",
        fidelity: .weighed
    )
}

private func success(
    on meal: BenchmarkMeal,
    t: Int64,
    estimate: Double,
    id: UUID = UUID(),
    modelVersion: String = lineage
) -> EstimationOutcome {
    EstimationOutcome(
        id: id,
        timestampMs: t,
        outcome: "success",
        failureJSON: nil,
        measurementsJSON: #"{"v":1,"decomposition":[{"carbsG":\#(estimate)}]}"#,
        mealID: UUID(),
        modelVersion: modelVersion,
        benchmarkMealID: meal.id
    )
}

private func refusal(
    on meal: BenchmarkMeal,
    t: Int64,
    id: UUID = UUID(),
    modelVersion: String = lineage
) -> EstimationOutcome {
    EstimationOutcome(
        id: id,
        timestampMs: t,
        outcome: "refused",
        failureJSON: #"{"domain":"estimation","case":"noFoodVolumeRecovered"}"#,
        measurementsJSON: #"{"v":1}"#,
        mealID: nil,
        modelVersion: modelVersion,
        benchmarkMealID: meal.id
    )
}

private func orderedUUID(_ ordinal: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", ordinal))!
}

@Suite("BenchmarkReport.compute")
struct BenchmarkReportComputeTests {

    // MARK: - Core statistics (Req 1.1)

    @Test("MAE, MAPE, ±10 g share, completion rate, N, and attempts-per-meal")
    func coreStatistics() {
        // Meal A: truth 100, estimate 90 → error 10, APE 10%, within ±10 g.
        // Meal B: truth 50, estimate 65 → error 15, APE 30%, outside ±10 g.
        // Meal C: refused only → attempted, never completed.
        let a = makeMeal(name: "a", truth: 100)
        let b = makeMeal(name: "b", truth: 50)
        let c = makeMeal(name: "c", truth: 30)
        let outcomes = [
            success(on: a, t: 1, estimate: 90),
            success(on: b, t: 2, estimate: 65),
            refusal(on: b, t: 1),
            refusal(on: c, t: 3)
        ]
        let report = BenchmarkReport.compute(meals: [a, b, c], outcomes: outcomes, lineage: lineage)

        #expect(report.mealCount == 3)
        #expect(report.completedMealCount == 2)
        #expect(report.completionRate == 2.0 / 3.0)
        #expect(report.maeGrams != nil && abs(report.maeGrams! - 12.5) < 1e-9)
        #expect(report.mapePercent != nil && abs(report.mapePercent! - 20.0) < 1e-9)
        #expect(report.within10gShare != nil && abs(report.within10gShare! - 0.5) < 1e-9)
        #expect(report.totalAttemptCount == 4)
        #expect(report.refusedAttemptCount == 2)
        #expect(report.meanAttemptsPerMeal != nil
            && abs(report.meanAttemptsPerMeal! - 4.0 / 3.0) < 1e-9)
    }

    @Test("estimate sums the per-class decomposition of the scoring attempt")
    func estimateSumsDecomposition() {
        let m = makeMeal(truth: 60)
        let multi = EstimationOutcome(
            timestampMs: 1,
            outcome: "success",
            failureJSON: nil,
            measurementsJSON: #"{"v":1,"decomposition":[{"carbsG":30.0},{"carbsG":12.5}]}"#,
            mealID: UUID(),
            modelVersion: lineage,
            benchmarkMealID: m.id
        )
        let report = BenchmarkReport.compute(meals: [m], outcomes: [multi], lineage: lineage)
        #expect(report.rows.count == 1)
        #expect(report.rows[0].estimateCarbsG != nil
            && abs(report.rows[0].estimateCarbsG! - 42.5) < 1e-6)
        #expect(report.rows[0].absoluteErrorG != nil
            && abs(report.rows[0].absoluteErrorG! - 17.5) < 1e-6)
    }

    @Test("meals never attempted under the lineage stay out of the report")
    func unattemptedMealsExcluded() {
        let attempted = makeMeal(name: "attempted", truth: 40)
        let created = makeMeal(name: "created only", truth: 40)
        let report = BenchmarkReport.compute(
            meals: [attempted, created],
            outcomes: [success(on: attempted, t: 1, estimate: 40)],
            lineage: lineage
        )
        #expect(report.mealCount == 1)
        #expect(report.rows.map(\.mealID) == [attempted.id])
    }

    @Test("attempts under another lineage are invisible")
    func otherLineageInvisible() {
        let m = makeMeal(truth: 40)
        let report = BenchmarkReport.compute(
            meals: [m],
            outcomes: [success(on: m, t: 1, estimate: 40, modelVersion: "coreml_other000000")],
            lineage: lineage
        )
        #expect(report.mealCount == 0)
        #expect(report.rows.isEmpty)
        #expect(report.maeGrams == nil)
    }

    @Test("empty input yields a no-data report, not a crash")
    func emptyInput() {
        let report = BenchmarkReport.compute(meals: [], outcomes: [], lineage: lineage)
        #expect(report.mealCount == 0)
        #expect(report.completionRate == 0)
        #expect(report.maeGrams == nil)
        #expect(report.headlineValid == false)
        #expect(report.anchorVerdict == .insufficientData)
    }

    // MARK: - Latest-completed-attempt selection (Decision 9)

    @Test("the latest completed attempt scores the meal")
    func latestCompletedAttemptWins() {
        let m = makeMeal(truth: 20)
        let outcomes = [
            success(on: m, t: 1, estimate: 10),
            success(on: m, t: 2, estimate: 30),
            refusal(on: m, t: 3)  // a later refusal never displaces a completion
        ]
        let report = BenchmarkReport.compute(meals: [m], outcomes: outcomes, lineage: lineage)
        #expect(report.rows[0].estimateCarbsG != nil
            && abs(report.rows[0].estimateCarbsG! - 30) < 1e-6)
        #expect(report.rows[0].completed)
    }

    @Test("equal timestamps break ties by id, matching store eviction order")
    func timestampTieBreaksByID() {
        let m = makeMeal(truth: 20)
        let outcomes = [
            success(on: m, t: 5, estimate: 10, id: orderedUUID(1)),
            success(on: m, t: 5, estimate: 30, id: orderedUUID(2))
        ]
        let report = BenchmarkReport.compute(meals: [m], outcomes: outcomes, lineage: lineage)
        #expect(report.rows[0].estimateCarbsG != nil
            && abs(report.rows[0].estimateCarbsG! - 30) < 1e-6)
    }

    // MARK: - Anchor block (Req 1.4)

    @Test("anchor constants carry the published SNAQ and reference figures")
    func anchorConstants() {
        #expect(BenchmarkAnchors.snaqMAEGrams == 13.1)
        #expect(BenchmarkAnchors.snaqMAPEPercent == 44.3)
        #expect(BenchmarkAnchors.goCarbWithin10gPercent == 37.0)
        #expect(BenchmarkAnchors.dietitiansWithin10gPercent == 35.2)
    }

    @Test("verdict: clearly better than the anchor")
    func verdictBetter() {
        let meals = (0..<4).map { makeMeal(name: "m\($0)", truth: 50) }
        let outcomes = meals.enumerated().map { i, m in
            success(on: m, t: Int64(i), estimate: 52)  // every error 2 g
        }
        let report = BenchmarkReport.compute(meals: meals, outcomes: outcomes, lineage: lineage)
        #expect(report.anchorVerdict == .betterThanAnchor)
    }

    @Test("verdict: clearly worse than the anchor")
    func verdictWorse() {
        let meals = (0..<4).map { makeMeal(name: "m\($0)", truth: 50) }
        let outcomes = meals.enumerated().map { i, m in
            success(on: m, t: Int64(i), estimate: 80)  // every error 30 g
        }
        let report = BenchmarkReport.compute(meals: meals, outcomes: outcomes, lineage: lineage)
        #expect(report.anchorVerdict == .worseThanAnchor)
    }

    @Test("verdict: within noise when the anchor sits inside MAE ± SE")
    func verdictWithinNoise() {
        // Errors 3 and 23: MAE 13, sample SD √200 ≈ 14.14, SE = 10 —
        // the 13.1 g anchor lies well inside the band.
        let a = makeMeal(name: "a", truth: 50)
        let b = makeMeal(name: "b", truth: 50)
        let outcomes = [
            success(on: a, t: 1, estimate: 53),
            success(on: b, t: 2, estimate: 73)
        ]
        let report = BenchmarkReport.compute(meals: [a, b], outcomes: outcomes, lineage: lineage)
        #expect(report.anchorVerdict == .withinNoiseOfAnchor)
    }

    // MARK: - Headline validity (Req 1.6)

    private func stapleCoveredMeals(count: Int, dropStaple: String? = nil) -> [BenchmarkMeal] {
        let staples = BenchmarkStaples.classIDs.filter { $0 != dropStaple }
        return (0..<count).map { i in
            let classID = i < staples.count ? staples[i] : "lemon"
            return makeMeal(name: "m\(i)", classID: classID, truth: 40)
        }
    }

    @Test("staple set mirrors validation.py's carb-priority classes")
    func stapleSet() {
        #expect(BenchmarkStaples.classIDs == [
            "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
            "potato_boiled", "potato_mashed", "chips_fries"
        ])
    }

    @Test("N = 20 with full staple coverage is headline-valid — refusals included")
    func headlineValidAtTwenty() {
        let meals = stapleCoveredMeals(count: 20)
        // Staple meals refuse (the honest expected state for weak staples,
        // Req 1.5/1.6) — they still count towards N and coverage.
        let outcomes = meals.enumerated().map { i, m in
            i < BenchmarkStaples.classIDs.count
                ? refusal(on: m, t: Int64(i))
                : success(on: m, t: Int64(i), estimate: 40)
        }
        let report = BenchmarkReport.compute(meals: meals, outcomes: outcomes, lineage: lineage)
        #expect(report.mealCount == 20)
        #expect(report.headlineValid)
        #expect(report.missingStaples.isEmpty)
    }

    @Test("N = 19 is below the meal floor")
    func headlineInvalidAtNineteen() {
        let meals = stapleCoveredMeals(count: 19)
        let outcomes = meals.enumerated().map { i, m in
            success(on: m, t: Int64(i), estimate: 40)
        }
        let report = BenchmarkReport.compute(meals: meals, outcomes: outcomes, lineage: lineage)
        #expect(report.mealCount == 19)
        #expect(!report.headlineValid)
    }

    @Test("a missing staple blocks headline validity and is named")
    func missingStapleNamed() {
        let meals = stapleCoveredMeals(count: 20, dropStaple: "chips_fries")
        let outcomes = meals.enumerated().map { i, m in
            success(on: m, t: Int64(i), estimate: 40)
        }
        let report = BenchmarkReport.compute(meals: meals, outcomes: outcomes, lineage: lineage)
        #expect(report.mealCount == 20)
        #expect(!report.headlineValid)
        #expect(report.missingStaples == ["chips_fries"])
    }

    // MARK: - Property-based invariants (design Testing Strategy)

    // Small seeded generator over meal/outcome sets — deliberately modest
    // (MVP gate): enough shapes to exercise empty meals, refusal-only meals,
    // and mixed attempt histories.
    private func randomFixture(
        rng: inout SplitMix64
    ) -> (meals: [BenchmarkMeal], outcomes: [EstimationOutcome]) {
        let mealCount = Int(rng.next(upperBound: 6 as UInt64))
        var meals: [BenchmarkMeal] = []
        var outcomes: [EstimationOutcome] = []
        for i in 0..<mealCount {
            let meal = makeMeal(
                name: "m\(i)",
                truth: Double(rng.next(upperBound: 120 as UInt64)) + 1
            )
            meals.append(meal)
            let attempts = Int(rng.next(upperBound: 4 as UInt64))
            for a in 0..<attempts {
                let t = Int64(rng.next(upperBound: 10 as UInt64))
                if rng.next(upperBound: 2 as UInt64) == 0 {
                    outcomes.append(refusal(on: meal, t: t, id: orderedUUID(i * 100 + a)))
                } else {
                    let estimate = Double(rng.next(upperBound: 150 as UInt64))
                    outcomes.append(success(
                        on: meal, t: t, estimate: estimate, id: orderedUUID(i * 100 + a)
                    ))
                }
            }
        }
        return (meals, outcomes)
    }

    @Test("invariants: completion rate in [0, 1] and MAE never negative")
    func invariantBounds() {
        var rng = SplitMix64(seed: 0xBEEF)
        for _ in 0..<100 {
            let (meals, outcomes) = randomFixture(rng: &rng)
            let report = BenchmarkReport.compute(meals: meals, outcomes: outcomes, lineage: lineage)
            #expect(report.completionRate >= 0 && report.completionRate <= 1)
            if let mae = report.maeGrams {
                #expect(mae >= 0)
            }
            #expect(report.completedMealCount <= report.mealCount)
        }
    }

    @Test("invariant: adding a refused attempt never raises the completion rate")
    func refusalNeverRaisesCompletionRate() {
        var rng = SplitMix64(seed: 0xF00D)
        for i in 0..<100 {
            var (meals, outcomes) = randomFixture(rng: &rng)
            // Refuse either an existing meal or a brand-new one.
            let target: BenchmarkMeal
            if meals.isEmpty || rng.next(upperBound: 3 as UInt64) == 0 {
                target = makeMeal(name: "fresh", truth: 40)
                meals.append(target)
            } else {
                target = meals[Int(rng.next(upperBound: UInt64(meals.count)))]
            }
            let before = BenchmarkReport.compute(
                meals: meals, outcomes: outcomes, lineage: lineage
            )
            outcomes.append(refusal(on: target, t: 99, id: orderedUUID(9_000 + i)))
            let after = BenchmarkReport.compute(
                meals: meals, outcomes: outcomes, lineage: lineage
            )
            #expect(after.completionRate <= before.completionRate)
            #expect(after.completedMealCount == before.completedMealCount)
        }
    }
}

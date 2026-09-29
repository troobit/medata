import Foundation
import Persistence

// SNAQ-comparable carb-accuracy report (specs/estimation/snaq-parity Req 1,
// design lane B). `compute` is a pure, deterministic function of
// (meals, outcomes, lineage): attempt-vs-meal semantics per Decision 9 —
// a meal counts completed under a lineage when at least one attempt under it
// completed AND its estimate decodes; the meal's error uses the LATEST such
// attempt with ties on timestamp broken by id (matching store eviction
// order). A completed attempt whose measurements JSON yields no estimate is
// excluded from scoring — never a silent 0 g — and surfaced via
// `undecodableAttemptCount`; refused attempts are counted, never excluded
// (Req 1.5).

public struct Report: Sendable, Equatable {
    // One attempted meal under the lineage. `estimateCarbsG` sums the
    // per-class decomposition of the scoring attempt; nil while the meal has
    // no decodable completed attempt.
    public struct MealRow: Sendable, Equatable {
        public let mealID: UUID
        public let name: String
        public let truthCarbsG: Double
        public let estimateCarbsG: Double?
        public let absoluteErrorG: Double?
        public let attemptCount: Int
        public let completed: Bool

        public init(
            mealID: UUID, name: String, truthCarbsG: Double,
            estimateCarbsG: Double?, absoluteErrorG: Double?,
            attemptCount: Int, completed: Bool
        ) {
            self.mealID = mealID
            self.name = name
            self.truthCarbsG = truthCarbsG
            self.estimateCarbsG = estimateCarbsG
            self.absoluteErrorG = absoluteErrorG
            self.attemptCount = attemptCount
            self.completed = completed
        }
    }

    // Comparison against the SNAQ anchor (Req 1.4). "Within noise" means the
    // anchor lies inside MAE ± 1.96 standard errors (~95%, matching the
    // one-sided 95% promotion standard — Decision 15) of our own per-meal
    // absolute errors, OR fewer than two meals completed (SE is meaningless
    // at n = 1, so no hard verdict is honest). The band is derived from
    // observed dispersion, not a fixed tolerance, honouring the note's
    // order-of-magnitude caveat.
    public enum AnchorVerdict: String, Sendable {
        case betterThanAnchor
        case withinNoiseOfAnchor
        case worseThanAnchor
        case insufficientData
    }

    public let lineage: String
    // N: meals with at least one attempt under the lineage (Req 1.6 floor).
    public let mealCount: Int
    public let completedMealCount: Int
    // completed ÷ attempted; 0 when nothing was attempted. MAE is never
    // separable from this figure — both live on the same value (Req 1.1).
    public let completionRate: Double
    public let maeGrams: Double?  // nil until a meal completes
    public let mapePercent: Double?  // mean per-meal APE; truth-zero meals skipped
    public let within10gShare: Double?  // share of completed meals within ±10 g
    public let meanAttemptsPerMeal: Double?
    public let totalAttemptCount: Int
    public let refusedAttemptCount: Int  // Req 1.5: refusals stay visible
    // Completed attempts whose measurements JSON yields no estimate
    // (malformed, missing decomposition, or an empty one) — excluded from
    // scoring rather than contributing |0 − truth| to MAE.
    public let undecodableAttemptCount: Int
    public let rows: [MealRow]
    // Req 1.6: N ≥ 20 AND every staple-floor class present in the attempted
    // meal set. Absent staples are named so a below-floor report states why.
    public let headlineValid: Bool
    public let missingStaples: [String]
    public let anchorVerdict: AnchorVerdict

    public init(
        lineage: String, mealCount: Int, completedMealCount: Int,
        completionRate: Double, maeGrams: Double?, mapePercent: Double?,
        within10gShare: Double?, meanAttemptsPerMeal: Double?,
        totalAttemptCount: Int, refusedAttemptCount: Int,
        undecodableAttemptCount: Int = 0, rows: [MealRow],
        headlineValid: Bool, missingStaples: [String], anchorVerdict: AnchorVerdict
    ) {
        self.lineage = lineage
        self.mealCount = mealCount
        self.completedMealCount = completedMealCount
        self.completionRate = completionRate
        self.maeGrams = maeGrams
        self.mapePercent = mapePercent
        self.within10gShare = within10gShare
        self.meanAttemptsPerMeal = meanAttemptsPerMeal
        self.totalAttemptCount = totalAttemptCount
        self.refusedAttemptCount = refusedAttemptCount
        self.undecodableAttemptCount = undecodableAttemptCount
        self.rows = rows
        self.headlineValid = headlineValid
        self.missingStaples = missingStaples
        self.anchorVerdict = anchorVerdict
    }
}

public enum BenchmarkReport {

    // Headline meal-count floor (Req 1.6): the bottom of the reference
    // studies' range (24–54 meals), an order-of-magnitude bar.
    public static let headlineMealFloor = 20

    public static func compute(
        meals: [BenchmarkMeal], outcomes: [EstimationOutcome], lineage: String
    ) -> Report {
        let mealIDs = Set(meals.map(\.id))
        var attemptsByMeal: [UUID: [EstimationOutcome]] = [:]
        for outcome in outcomes {
            guard let mealID = outcome.benchmarkMealID,
                  mealIDs.contains(mealID),
                  outcome.modelVersion == lineage else { continue }
            attemptsByMeal[mealID, default: []].append(outcome)
        }

        // Rows in the caller's meal order, restricted to attempted meals —
        // a created-but-never-attempted meal is not part of the lineage's
        // denominator (Decision 9).
        var rows: [Report.MealRow] = []
        var undecodableAttempts = 0
        for meal in meals {
            guard let attempts = attemptsByMeal[meal.id] else { continue }
            // Completed attempts latest-first; the scoring attempt is the
            // first whose estimate decodes, so an undecodable latest attempt
            // falls back to the next-latest decodable one instead of scoring
            // a silent 0 g.
            let estimates = attempts
                .filter { $0.outcome == EstimationOutcomeKind.success.rawValue }
                .sorted { lhs, rhs in
                    (lhs.timestampMs, lhs.id.uuidString) > (rhs.timestampMs, rhs.id.uuidString)
                }
                .map(estimateCarbsG(of:))
            undecodableAttempts += estimates.filter { $0 == nil }.count
            let estimate = estimates.compactMap { $0 }.first
            rows.append(Report.MealRow(
                mealID: meal.id,
                name: meal.name,
                truthCarbsG: meal.truthCarbsG,
                estimateCarbsG: estimate,
                absoluteErrorG: estimate.map { abs($0 - meal.truthCarbsG) },
                attemptCount: attempts.count,
                completed: estimate != nil
            ))
        }

        let mealCount = rows.count
        let completedRows = rows.filter(\.completed)
        let errors = completedRows.compactMap(\.absoluteErrorG)
        let totalAttempts = rows.reduce(0) { $0 + $1.attemptCount }
        let refusedAttempts = attemptsByMeal.values
            .joined()
            .filter { $0.outcome == EstimationOutcomeKind.refused.rawValue }
            .count

        let mae = errors.isEmpty ? nil : errors.reduce(0, +) / Double(errors.count)
        let apes = completedRows.compactMap { row -> Double? in
            guard let error = row.absoluteErrorG, row.truthCarbsG > 0 else { return nil }
            return error / row.truthCarbsG * 100
        }
        let mape = apes.isEmpty ? nil : apes.reduce(0, +) / Double(apes.count)
        let within10g: Double? = errors.isEmpty
            ? nil
            : Double(errors.filter { $0 <= BenchmarkAnchors.within10gBandGrams }.count)
                / Double(errors.count)

        let missingStaples = BenchmarkStaples.classIDs.filter { staple in
            !rows.contains { row in
                meals.first { $0.id == row.mealID }?
                    .items.contains { $0.classID == staple } ?? false
            }
        }

        return Report(
            lineage: lineage,
            mealCount: mealCount,
            completedMealCount: completedRows.count,
            completionRate: mealCount == 0
                ? 0 : Double(completedRows.count) / Double(mealCount),
            maeGrams: mae,
            mapePercent: mape,
            within10gShare: within10g,
            meanAttemptsPerMeal: mealCount == 0
                ? nil : Double(totalAttempts) / Double(mealCount),
            totalAttemptCount: totalAttempts,
            refusedAttemptCount: refusedAttempts,
            undecodableAttemptCount: undecodableAttempts,
            rows: rows,
            headlineValid: mealCount >= headlineMealFloor && missingStaples.isEmpty,
            missingStaples: missingStaples,
            anchorVerdict: anchorVerdict(errors: errors)
        )
    }

    // MARK: - internals

    // Minimal decode of the opaque measurements JSON: the estimate is the sum
    // of the per-class decomposition's carb grams (the Req 3.4 snapshot the
    // pipeline embeds in every success record — stampSuccess always sets it).
    private struct MeasurementsEnvelope: Decodable {
        struct DecompositionEntry: Decodable {
            let carbsG: Double
        }
        let decomposition: [DecompositionEntry]?
    }

    // Nil when the JSON is malformed or the decomposition is missing/empty —
    // such an attempt must never score as a 0 g estimate.
    private static func estimateCarbsG(of outcome: EstimationOutcome) -> Double? {
        guard
            let envelope = try? JSONDecoder().decode(
                MeasurementsEnvelope.self, from: Data(outcome.measurementsJSON.utf8)
            ),
            let decomposition = envelope.decomposition,
            !decomposition.isEmpty
        else { return nil }
        return decomposition.reduce(0) { $0 + $1.carbsG }
    }

    // Band: MAE ± 1.96 standard errors (~95%), consistent with the one-sided
    // 95% promotion standard; the anchor's own sampling noise is consciously
    // ignored (Decision 15). Hard better/worse verdicts additionally require
    // n ≥ 2 — a single completed meal has SE = 0 and must not read as a
    // confident comparison.
    private static func anchorVerdict(errors: [Double]) -> Report.AnchorVerdict {
        guard !errors.isEmpty else { return .insufficientData }
        guard errors.count >= 2 else { return .withinNoiseOfAnchor }
        let n = Double(errors.count)
        let mae = errors.reduce(0, +) / n
        let variance = errors.reduce(0) { $0 + ($1 - mae) * ($1 - mae) } / (n - 1)
        let band = 1.96 * (variance / n).squareRoot()
        if mae + band < BenchmarkAnchors.snaqMAEGrams {
            return .betterThanAnchor
        }
        if mae - band > BenchmarkAnchors.snaqMAEGrams {
            return .worseThanAnchor
        }
        return .withinNoiseOfAnchor
    }
}

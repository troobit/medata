// The relabel shortlist ordering (estimation/alternative-class-candidates
// Req 7, Decision 7 as amended). Pure and deterministic: the same recency
// history and the same candidate evidence always produce the same order.
import Foundation

public enum ShortlistOrdering {
    /// The ordering shipped by `ui/meal-review` Req 3.1 — recency plus the
    /// blind eligible top-up. Named on every correction record written before
    /// candidate evidence existed, so the value is fixed (Req 7.6).
    public static let recencySource = "recency"
    /// Recency, then candidate-evidence fills, then the top-up (Req 7.6).
    public static let combinedSource = "recency_plus_candidates"

    /// Three layers, in order:
    ///
    /// 1. `recency` — entries in their exact shipped positions (Req 7.2);
    /// 2. `candidates` — evidence-ranked ids for the detected food, filling
    ///    the slots the top-up would otherwise have taken (Req 7.3);
    /// 3. `topUp` — the shipped eligible-list order, for any slot still empty.
    ///
    /// Evidence displaces only the blind top-up, never a recency entry. With
    /// `candidates` empty, layers 1 and 3 reproduce the shipped list exactly
    /// (Req 7.4).
    ///
    /// All three inputs are already-eligible class ids: eligibility and phase
    /// filtering (Req 7.8, 7.9) stay with the caller, exactly as shipped.
    /// Duplicates are skipped in layer order, so an id present in two layers
    /// keeps its earliest position.
    public static func combined(
        recency: [String],
        candidates: [String],
        topUp: [String],
        limit: Int = 5
    ) -> [String] {
        guard limit > 0 else { return [] }
        var out: [String] = []
        out.reserveCapacity(limit)
        var seen = Set<String>()
        for layer in [recency, candidates, topUp] {
            for id in layer {
                guard out.count < limit else { return out }
                if seen.insert(id).inserted { out.append(id) }
            }
        }
        return out
    }
}

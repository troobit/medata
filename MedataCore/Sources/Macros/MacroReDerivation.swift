import Foods
import Foundation
import Volume

// Shared macro re-derivation (meal-review Decision 8's impact clause: the
// recomputation must share Pipeline's derivation rather than reimplement it).
// Pipeline's own derivation is Macros.compute over β-corrected volumes, so a
// relabel routed through here reproduces exactly what the pipeline would have
// computed had the segmenter chosen that food first (meal-review Req 3.5).
public extension Macros {

    // The β-correction table the pipeline applies during volume estimation.
    // Mirrors Pipeline's private buildBeta: one entry per class id with a
    // database row; classes without a row (and liquid classes, which are
    // never passed in) fall back to BetaCorrection.defaultBeta of 1.0.
    static func betaCorrection(
        for classIds: [String],
        database: FoodDatabase,
        edition: String
    ) -> BetaCorrection {
        var entries: [String: Float] = [:]
        for classId in classIds {
            if let entry = database.entry(for: classId, edition: edition) {
                entries[classId] = entry.beta
            }
        }
        return BetaCorrection(entries: entries)
    }

    // Re-derives one food from its pre-β volume under a target class
    // (meal-review Req 3.5): applies the target class's own β_c, then
    // density and coefficient through Macros.compute, which stamps
    // betaUsed and betaStatus from the database row — that carries
    // Req 3.7's calibration indication for free. Always derive from the
    // predicted side's pre-β volume, never from a previous corrected
    // value, or repeated relabels compound Float32 drift.
    //
    // The result holds exactly one perClass entry (the target class), or
    // none where the database has no row for it — a case Req 3.8 makes
    // unreachable from the relabel UI. `totalCarbsG` is that food's
    // contribution only, never a meal total (design.md, meal-total rule).
    // `liquidClassIds` and `liquidOverEstimate` are passed through so a
    // liquid's over-read flag is not silently dropped.
    static func reDerive(
        preBetaVolumeCm3: Float,
        as classId: String,
        beta: BetaCorrection,
        database: FoodDatabase,
        edition: String,
        liquidClassIds: Set<String> = [],
        liquidOverEstimate: Bool = false
    ) -> MacroResult {
        let postBetaVolumeCm3 = preBetaVolumeCm3 * beta.beta(for: classId)
        return Macros.compute(
            perClassVolumesCm3: [classId: postBetaVolumeCm3],
            database: database,
            edition: edition,
            liquidClassIds: liquidClassIds,
            liquidOverEstimate: liquidOverEstimate
        )
    }

    // Fallback for records written before the pre-β map was persisted
    // (meal-review Decision 17): recover the pre-β volume by dividing the
    // stored post-β volume by the β applied. Returns nil — the relabel is
    // refused — where betaUsed is zero, negative, or not finite, rather
    // than shipping one class's β on another's figure. Reject, absent and
    // amount adjustment stay available in that case (Decision 14).
    static func preBetaVolume(
        storedVolumeCm3: Float,
        betaUsed: Float
    ) -> Float? {
        guard betaUsed.isFinite, betaUsed > 0 else { return nil }
        return storedVolumeCm3 / betaUsed
    }

    // Fat and protein for a corrected meal (specs/data/insulin-dosing Req 8.3,
    // 8.8 — the F1 gate). A correction asserts a MASS per food, so the two
    // figures follow from that mass on the same per-100 g lines
    // `Macros.compute` uses — the derivation is shared rather than
    // reimplemented, exactly as `reDerive` above shares it for a relabel.
    // Deriving from the corrected mass is what makes a scaled or user-set
    // amount carry through: `reDerive`'s own per-class figures describe the
    // volume it was handed, which a later scale supersedes.
    //
    // Returns nil where NO class resolved in the database — a meal whose fat
    // cannot be derived reads as absent, never as fat-free (Req 8.1). A class
    // that fails to resolve inside an otherwise resolvable meal is skipped,
    // matching `Macros.compute`'s own silent skip.
    static func correctedFatAndProtein(
        massGByClassID: [String: Double],
        database: FoodDatabase,
        edition: String
    ) -> (fatG: Double, proteinG: Double)? {
        var fatG = 0.0
        var proteinG = 0.0
        var resolvedAny = false

        for (classID, massG) in massGByClassID {
            guard let entry = database.entry(for: classID, edition: edition) else { continue }
            resolvedAny = true
            fatG += massG * Double(entry.fatG) / 100.0
            proteinG += massG * Double(entry.proteinG) / 100.0
        }

        return resolvedAny ? (fatG: fatG, proteinG: proteinG) : nil
    }
}

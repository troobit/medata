#if HARNESS_ENABLED
import Foods
import Foundation
import Macros

// The review screen's verdict on one field capture: which segmenter classes the
// user renamed, and which regions they removed. `make field-derive` writes it
// into each checkpoint group's run_summary.json (`fixtures.<id>.review`) from
// the corpus `corrections` table, and `accuracy` and `calibrate` read it through
// `--ingest-summary`.
//
// A capture bundle records the segmenter's labels, so a replay measures each
// region under the segmenter's class. The weighed truth is recorded under the
// class the user settled on in review: MD-29 makes a wrong class a one-tap fix,
// so the class the review names is the truth about the food. Without this, a
// plate the user relabelled bread_white → bread_wholemeal replays as bread_white
// and the τ_purity gate drops it for disagreeing with its own truth.
//
// Amount corrections are not applied. The volume is the quantity being
// measured, and the weighed mass is its truth; an amount the user typed is
// neither. Nutrition5k and MetaFood3D summaries carry no review, and a fixture
// without one replays unchanged.
public struct FieldReview: Sendable, Equatable {
    // Segmenter class → the class the review named.
    public let relabelled: [String: String]
    // Segmenter classes whose region the review removed.
    public let rejected: Set<String>

    public init(relabelled: [String: String] = [:], rejected: Set<String> = []) {
        self.relabelled = relabelled
        self.rejected = rejected
    }

    // Volumes under the reviewed classes. A removed region is dropped, a renamed
    // region joins any region already carrying its new class, and every class
    // the review did not touch passes through. Each label maps once from the
    // segmenter's class, so renaming A → B and B → C moves A's region to B and
    // B's to C rather than chaining A to C.
    public func volumes(_ labelled: [String: Float]) -> [String: Float] {
        var out: [String: Float] = [:]
        for (className, volume) in labelled where !rejected.contains(className) {
            out[relabelled[className] ?? className, default: 0] += volume
        }
        return out
    }

    // A replayed meal re-priced at the reviewed classes: predicted carbs are
    // recomputed from the reviewed volumes at β = 1, exactly as `FixtureRunner`
    // prices the segmenter's labels. Truth is untouched.
    public func apply(to input: MealCalibrationInput, database: any FoodDatabase,
                      edition: String) -> MealCalibrationInput {
        let reviewed = volumes(input.perClassVolumesCm3)
        let macros = Macros.compute(perClassVolumesCm3: reviewed, database: database,
                                    edition: edition)
        return MealCalibrationInput(
            fixtureID: input.fixtureID,
            capturePath: input.capturePath,
            dominantClass: reviewed.max(by: { $0.value < $1.value })?.key,
            predictedCarbsPerClass: macros.perClass.mapValues(\.carbsG),
            actualCarbsPerClass: input.actualCarbsPerClass,
            groundTruthTotalCarbsG: input.groundTruthTotalCarbsG,
            perClassVolumesCm3: reviewed,
            supportPlaneResidualMm: input.supportPlaneResidualMm,
            supportPlaneReference: input.supportPlaneReference,
            regionGrowth: input.regionGrowth)
    }
}
#endif

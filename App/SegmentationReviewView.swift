import Persistence
import SwiftUI

// Stub registered in task 12. The full segmentation-review screen is task 17,
// which is cross-stream blocked on the palette colour table (task 4) and the
// store artefact-transport API (task 7) — both live in stream 1's worktree.
// Kept compilable here so the shell builds; do NOT reference MedataCore APIs
// that only exist after those tasks land (artefactData, the id→colour table).
struct SegmentationReviewView: View {
    let record: MealRecord
    var onCarbs: () -> Void = {}

    var body: some View {
        EmptyView()
    }
}

import Persistence
import SwiftUI

// Stub registered in task 12. The manual-correction screen is task 19,
// cross-stream blocked on `appendCorrection` emitting `eventsDidChange`
// (task 9, stream 1's worktree). Kept compilable here so the shell builds.
struct ManualCorrectionView: View {
    let record: MealRecord
    var onSave: () -> Void = {}

    var body: some View {
        EmptyView()
    }
}

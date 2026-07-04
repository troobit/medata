import Persistence
import SwiftUI

// Stub registered in task 12. The meal-overview screen is task 21 (stream 3),
// which binds the shared MaskOverlayLoader and the palette colour table. Kept
// compilable here so the shell swap builds.
struct MealOverviewView: View {
    let store: any PersistenceStore
    let record: MealRecord

    var body: some View {
        EmptyView()
    }
}

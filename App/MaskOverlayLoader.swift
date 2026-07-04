import Persistence
import SwiftUI

// Stub registered in task 12. The real loader (raw-bitmap mask decode via
// CGDataProvider, tinted per the palette colour table) is task 17, cross-stream
// blocked on the store artefact-transport API (task 7) and the id→colour table
// (task 4). Do NOT reference those MedataCore APIs here.
struct MaskOverlayLoader: View {
    let store: any PersistenceStore
    let mealId: UUID

    var body: some View {
        EmptyView()
    }
}

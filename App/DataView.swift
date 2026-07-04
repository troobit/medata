import Persistence
import SwiftUI

// Stub registered in task 12. The Data (meal log) screen — day grouping,
// anonymous rows, correction composition — is task 20 (stream 3). Kept
// compilable here so the shell swap builds.
struct DataView: View {
    let store: any PersistenceStore

    var body: some View {
        NavigationStack {
            Text("Data")
                .navigationTitle("Data")
        }
    }
}

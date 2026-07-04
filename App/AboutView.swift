import SwiftUI

// Stub registered in task 12. The About screen (CoFID + AFCD attribution,
// method paragraph, not-a-medical-device, on-device privacy) is task 23
// (stream 3), reached via a NavigationLink from Settings.
struct AboutView: View {
    var body: some View {
        Text("About")
            .navigationTitle("About")
    }
}

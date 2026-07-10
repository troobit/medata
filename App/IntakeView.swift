import SwiftUI

// Decision 12 compile placeholder — owned by `manual-carb-intake` (Track C),
// which replaces this file wholesale with the carb-entry surface (quick-add
// presets + manual entry). Home-router owns only the `ActiveSheet.intake`
// route and the one-line cover branch in AppRoot that presents this view.
// An empty surface with the standard cover close control; no placeholder
// copy (developer-phase no-disclaimer rule).
struct IntakeView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Color.surfacePrimary
                .ignoresSafeArea()
                .navigationTitle("Intake")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        CloseCoverButton { dismiss() }
                    }
                }
        }
    }
}

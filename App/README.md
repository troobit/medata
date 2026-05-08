# App target — iOS SwiftUI shell

Placeholder location for the iOS app target (design §2.1). The SwiftUI views
(`App.swift`, `CaptureFlowView.swift`, `ResultView.swift`, `SettingsView.swift`)
are wired up in **task 53**, after the Pipeline orchestrator (task 50) is in place.

The Xcode project itself is created interactively via Xcode's "New Project →
App" template at task 53; this folder will hold the per-target Swift sources.
The Swift Package (`Package.swift` at the repo root) provides `MedataCore` as
a local dependency; the iOS app imports `Pipeline` only, per design §2.1.

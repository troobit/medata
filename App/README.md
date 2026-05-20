# App target — iOS SwiftUI shell

SwiftUI views for the iOS app (design §2.1). The Xcode project at
`MeData/MeData.xcodeproj` (repo root) references these files in place via
`../App/*.swift`; they live here, not duplicated into the project's source
folder.

| File | Role |
|---|---|
| `App.swift` | `@main struct MedataApp` — app entry point, mounts `CaptureFlowView` |
| `CaptureFlowView.swift` | Placeholder capture view + `CaptureFlowViewModel`; also hosts the **Run self-check** diagnostic button used to verify the SPM link at runtime |
| `ResultView.swift` | Displays a finished `MealRecord` (carb estimate + confidence) |
| `SettingsView.swift` | Retention / IFCDB overlay toggles via `@AppStorage` |

The Swift Package at the repo root exposes `MedataCore` (the `Pipeline`
target). The app uses `import Pipeline`; `Pipeline.swift` re-exports
`Persistence` and `PortableContracts` so `MealRecord`, `EstimationFailure`,
and the `Pb*` types are reachable through that single import.

For build / run instructions see `docs/ios-device-setup.md`.

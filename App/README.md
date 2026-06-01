# App target — iOS SwiftUI shell

The SwiftUI capture-flow shell for the iOS app (per `specs/ui/design.md`). The Xcode
project at `MeData/MeData.xcodeproj` (repo root) references these files in place via
`../App/*.swift`; they live here, not duplicated into the project's source folder.

Behaviour lives in `CaptureFlowModel` (an `@Observable @MainActor` state machine);
the views are composition only. See [`docs/agent-notes/ui-capture-flow.md`](../docs/agent-notes/ui-capture-flow.md)
for module-level gotchas, and [`docs/architecture.md`](../docs/architecture.md) §4 for
the architecture overview.

| File | Role |
|---|---|
| `App.swift` | `@main MedataApp` — entry point, owns `CaptureFlowModel`, forwards `scenePhase` |
| `CaptureFlowView.swift` | `NavigationStack` root composing AR preview, live indicators, shutter, refusal overlay, settings entry |
| `CaptureFlowModel.swift` | The `@Observable @MainActor` state machine and `CaptureFlowDelegate` conformance |
| `CaptureState.swift` | `CaptureState` enum (initialising, ready, capturing, estimating, showingResult, refused, …) |
| `GatingSnapshot.swift` | Frozen-at-shutter snapshot of tilt / distance / coverage / path hint |
| `CapturePathDecider.swift` | [AUTO_CAPTURE_MODE flag — deferred, Req 3.9] Auto-derives path from LiDAR coverage; inactive in v1 (Decision 35 uses user toggle instead) |
| `LiveIndicatorModel.swift` | Child `@Observable` holding ~60 Hz tilt / distance / coverage |
| `LiveIndicatorView.swift` | Child view rendering those indicators |
| `LiveSampleObserver.swift` | `@MainActor` observer iterating `engine.frames`, computing per-frame metrics |
| `ARPreviewView.swift` | `UIViewRepresentable` over `ARView`; engine adopts the view's `ARSession` (one session only) |
| `RefusalBanner.swift` | Inline `EstimationFailure.localisedMessage` banner with "Try Again" |
| `ResultView.swift` | Total carbs (rounded) + four-tier confidence pill (Decision 17); Very-Low retake / Keep as-is surface below σ 0.20 (Req §9.3) |
| `SettingsView.swift` | Retention + IFCDB toggles via `@AppStorage`; Export archive → `ShareSheet` |
| `ShareSheet.swift` | `UIViewControllerRepresentable` wrapping `UIActivityViewController` |
| `Colors.swift` | Brand colour tokens (`medataAccent #63ff00`, confidence pill colours) |

## SPM import boundary

The Swift Package at the repo root exposes `MedataCore` (the `Pipeline` target). The app
uses `import Pipeline`; `Pipeline.swift` re-exports `Persistence` and `PortableContracts`
so `MealRecord`, `EstimationFailure`, and the `Pb*` proto types are reachable through that
single import. `CaptureKit` is imported directly where the app needs `ARKitCaptureEngine`
and `CaptureSession`.

For build, sign, and side-load instructions see
[`docs/ios-device-setup.md`](../docs/ios-device-setup.md).
</content>

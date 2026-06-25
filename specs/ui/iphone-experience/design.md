# UI — Design

**Version:** 1.1
**Date:** 2026-05-29
**Status:** Done (v1.1 — all 60 tasks landed). The 2026-06-20 consistency pass (GAPS Group C) reconciled this document with the as-built code and the later UI decisions (15, 17, 18) / `research` §0: four-tier confidence pill, iOS 26.5 floor, `CapturePathDecider` behind the deferred `AUTO_CAPTURE_MODE` flag, retention/IFCDB removed, `eventsDidChange` / `events`-table persistence shape, and `SettingsKeys.captureMode` (not a bare literal). Superseded v1.0 task content is retained in `tasks.md` with inline markers for history.

## Overview

iOS SwiftUI tab shell with three tabs (Photo / Meals / Settings) driving `MedataCore`'s `CaptureSession` + `Pipeline.estimate(_:mode:)`. The Photo tab hosts the capture flow specified in v1.0; the Meals tab is a new history list reading from the same `meals.sqlite` the Pipeline writes to; the Settings tab consolidates the v1.0 settings surface. New code lives in `App/` (iOS-shell only); the SPM is touched only via the v1.0 additive extensions to `ARKitCaptureEngine` and `PipelineEstimator`. Capture state remains owned by `CaptureFlowModel`; tab selection state lives on a new `AppRoot` owner.

**Visual design.** All visual tokens (colour, type, spacing, motion) live in `design-system/MASTER.md` and the page-specific overrides `design-system/pages/photo-tab.md` and `design-system/pages/meals-tab.md`. The implementation SHALL consume those tokens (Req §20.1); this design document SHALL NOT duplicate the token definitions. The styling brief is a clean, professional capture aesthetic — content-first OLED-black capture/result screens, a single consolidated indicator chip, a capsule capture-mode pill, photo-led Meals rows. The v1.0 `RefusalBanner` and three-corner indicator layout are explicitly superseded by Req §20.4 / §20.7.

## Architecture

### Tab shell (`AppRoot`)

Root of the SwiftUI scene becomes `AppRoot`, owning a `TabView` with three tabs. One `NavigationStack` per tab — the iOS rule that pushed views must come from a stack inside the current tab applies here (see swift.md "Toolbar Placement in NavigationSplitView" / per-tab NavigationStack guidance).

```swift
@MainActor struct AppRoot: View {
    @AppStorage("selectedTab") private var selectedTab: Tab = .photo
    @State private var captureModel: CaptureFlowModel
    @State private var historyModel: MealHistoryModel
    let engine: ARKitCaptureEngine
    let store: any PersistenceStore

    enum Tab: String, Hashable { case photo, meals, settings }

    var body: some View {
        TabView(selection: $selectedTab) {
            CaptureFlowView(model: captureModel, engine: engine, store: store)
                .tabItem { Label("Photo", systemImage: "camera.fill") }
                .tag(Tab.photo)
            MealsTabView(model: historyModel, store: store)
                .tabItem { Label("Meals", systemImage: "fork.knife") }
                .tag(Tab.meals)
            SettingsView(store: store)
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .tint(.medataAccent)
        .onChange(of: selectedTab) { _, new in captureModel.tabSelectionChanged(to: new) }
    }
}
```

**Capture-session lifecycle vs tab switching.** `CaptureFlowModel.tabSelectionChanged(to:)` follows the same logic as `scenePhaseChanged(.background)`: if the new tab is not `.photo`, release the engine and reset the model to `.initialising`; on `.photo` re-entry, re-acquire. Exception per Req §1.7: when state is `.estimating`, do NOT cancel — let the in-flight `Pipeline.estimate(_:mode:)` complete, persist the result, and present it on next `.photo` entry by transitioning to `.showingResult(record)` instead of `.initialising`.

**Why one stack per tab.** Each `NavigationStack` is rooted inside its `tabItem` view. Sharing a single stack across tabs would (a) make a `popToRoot` on tab-tap (Req §18.5) ambiguous, and (b) break the per-tab navigation state preservation the system provides by default. The Photo tab's `NavigationStack` is needed for `.navigationDestination(for: MealRecord.self) -> ResultView`; the Meals tab's stack is needed for the list → detail push (Req §19.4); the Settings tab's stack carries the share-sheet sheet from §11.4.

**Tab-tap pop-to-root.** Req §18.5 is the system's default `TabView` behaviour on iOS 18+ (re-tapping the selected tab pops its `NavigationStack` to root) — no custom code required. Tested via XCUITest hitting the active tab item twice and asserting the visible view.

### ARSession ownership and the live-frame stream

`ARKitCaptureEngine` owns one `ARSession` and is its sole `ARSessionDelegate`. ARKit allows one session and one delegate per process — the SwiftUI preview cannot create a second session or register a second delegate. Two additive accessors on the engine expose what the UI needs:

```swift
// Additive changes in MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift
public extension ARKitCaptureEngine {
    /// The underlying ARSession, exposed so an iOS-shell preview view can
    /// render the camera feed by assigning it to ARView. The engine remains
    /// the sole `ARSessionDelegate`; callers MUST NOT reassign
    /// `session.delegate`.
    var arSession: ARSession { session }

    /// Live AR frames observed by the engine's ARSessionDelegate hook, fanned
    /// out for non-capture consumers (preview overlays, tilt indicator,
    /// LiDAR-coverage gauge). The stream is per-subscriber and back-pressured
    /// via `BufferingPolicy.bufferingNewest(1)` — slow consumers see the
    /// latest frame, not a backlog. Cancelling the iteration unsubscribes.
    var frames: AsyncStream<ARFrame> { ... }
}
```

These are the only SPM-side changes in this spec. Test seam (`PipelineEstimator` protocol) is a third SPM-side addition documented below.

The frame-contention risk between `ARView`'s draw cycle (reads `currentFrame.capturedImage` per render) and the engine's `captureNadir/Oblique` (also reads the same frame) is real but bounded: `captureNadir/Oblique` runs once per user shutter tap (not per-frame), grabs the current frame snapshot, and returns within a single ARKit frame interval. `ARView` draws may drop one frame around a capture tap. Acceptable under requirements §14.2's 30 fps floor; no explicit gating.

### Live-signal source: `AsyncStream<ARFrame>`, not delegate methods

`CaptureFlowDelegate` declares `didUpdateTilt(angleDegrees:)` and `didUpdateLiDARCoverage(percent:)` but neither has a producer in `MedataCore`. The UI consumes the new `frames: AsyncStream<ARFrame>` and computes tilt + coverage directly per frame. The two unimplemented delegate methods stay on the protocol as forward-compat stubs (no-op conformance on `CaptureFlowModel`); a future spec may add producers or remove the methods. Recorded in `decision_log.md` Decision 11.

### State machine (single source of truth)

`CaptureFlowModel` (an `@Observable` class) holds:

```swift
@Observable @MainActor final class CaptureFlowModel {
    var state: CaptureState = .initialising
    // Live observation surface (high-churn — split into child @Observable
    // `LiveIndicatorModel` consumed only by indicator subviews to keep
    // CaptureFlowView body redraws bounded; see Components section).
    var lastMeal: MealRecord? = nil
}

enum CaptureState: Equatable {
    case initialising                                       // AR not yet at .normal tracking
    case permissionDenied(PermissionSubject)                // camera or motion denied
    case trackingLost                                       // AR session lost normal tracking — discard any partial capture
    case ready(GatingSnapshot)                              // shutter armed; snapshot frozen at tap-time
    case capturing(stage: CaptureStage, frozen: GatingSnapshot, mode: CaptureMode)
    case estimating(captureResult: CaptureResult, mode: CaptureMode)
    case showingResult(MealRecord)                          // NavigationStack pushed ResultView
    case refused(EstimationFailure, retryStage: CaptureStage)
}

// CaptureMode lives in MedataCore; bound to SettingsKeys.captureMode in UserDefaults.
// Default = .double on first install. See research design §0.
// NOTE: use the named SettingsKeys.captureMode constant ("medata.captureMode"), NOT a
// bare "captureMode" literal — the literal silently diverged from the reader's namespaced
// key and caused the single-mode-toggle-key-mismatch bug (now fixed).
@AppStorage(SettingsKeys.captureMode) var captureMode: CaptureMode = .double

enum CaptureStage: Equatable { case nadir, oblique }
enum PermissionSubject: Equatable { case camera, motion }
struct GatingSnapshot: Equatable, Sendable {
    let tiltInRange: Bool
    let distanceCm: Float?                                  // nil when LiDAR unavailable
    let lidarCoveragePercent: Float                         // 0 when LiDAR unavailable
}
```

Transitions (exhaustive — every other input is a programmer error and triggers `assertionFailure` in debug):

| From | Event | To | Requirement |
|---|---|---|---|
| `.initialising` | `AVCaptureDevice` reports camera denied | `.permissionDenied(.camera)` | §1.3, §13.1, §13.3 |
| `.initialising` | `CMMotionManager` reports motion denied | `.permissionDenied(.motion)` | §13.2, §13.3 |
| `.initialising` | `ARSession` reports `.normal` tracking AND permissions granted | `.ready(snapshot)` | §1.6 |
| `.permissionDenied` | user re-grants and re-enters app | `.initialising` | §13.3 |
| `.ready(snapshot)` | live coverage/tilt write changes `snapshot` | `.ready(newSnapshot)` (re-emit) | §2.x |
| `.ready(snapshot)` | shutter tap AND `snapshot.tiltInRange` AND distance gate OK | `.capturing(.nadir, frozen: snapshot, mode: captureMode)` | §7.2, §14.3 |
| `.ready(_)` | user toggles `captureMode` segmented control | `.ready(_)` (model writes UserDefaults; no state change; mode is read at tap-time) | §4.1, §4.4 |
| `.capturing(.nadir, _, mode: .single)` | nadir frame returned | `.estimating(captureResult, mode: .single)` | — |
| `.capturing(.nadir, snap, mode: .double)` | nadir frame returned | `.ready(snap)` (await oblique tap; mode locked to .double for the rest of this capture) | §5.1, §5.3 |
| `.capturing(stage, _, _)` | `CaptureSession.captureFrame` throws | `.refused(.captureFailed(...), retryStage: stage)` | §10.1 |
| `.capturing(.nadir, _, _)` | AR tracking degrades during/after capture | `.trackingLost` (discard nadir) | §5.6 |
| `.ready` (after first view, awaiting oblique, mode locked .double) | AR tracking degrades | `.trackingLost` (discard first view) | §5.5 |
| `.capturing(.oblique, _, .double)` | oblique frame returned | `.estimating(captureResult, mode: .double)` | — |
| `.estimating(_, mode)` | `Pipeline.estimate(_, mode:)` returns success | `.showingResult(record)` (also writes `lastMeal = record`) | §9.1 |
| `.estimating` | `Pipeline.estimate` throws | `.refused(failure, retryStage:)` | §10.1 |
| `.showingResult` | user dismisses result view (back button or "New capture") | `.ready(freshSnapshot)` | §9.4 |
| `.refused` | user taps "Try again" | `.capturing(retryStage, frozen: freshSnapshot)` | §10.2 |
| `.trackingLost` | AR session returns to `.normal` tracking | `.ready(snapshot)` | §3.7, §16.1 |
| any `.capturing` or `.estimating` | app backgrounded | `Task.cancel()`; on foreground reset to `.initialising` (§8.3 caveat: see Decision 12) | §1.2, §8.3 |
| any | `ARSession.sessionWasInterrupted` (phone call, lock) | release engine; on `sessionInterruptionEnded` re-call `engine.start()` and reset to `.initialising` | §16.1 |
| any | rapid second tap before state leaves `.capturing` | ignored (no-op) | §7.4 |

**Tap-time mode freeze rule.** When the user taps the shutter while `.ready(snapshot)`, the model reads the current `captureMode` from `UserDefaults` and transitions to `.capturing(.nadir, frozen: snapshot, mode: captureMode)` **synchronously on the same MainActor tick as the tap**. The frozen snapshot AND the mode are the values the pipeline uses; subsequent toggle changes do not affect the in-progress capture. This is the §14.3 tap-to-busy guarantee + the §4.4 mid-flight mode-immutability guarantee.

**LiveIndicatorModel write-gating.** The `frames` stream uses `BufferingPolicy.bufferingNewest(1)` which means a frame may already be buffered when the model transitions out of `.ready`. `LiveSampleObserver` checks `model.state` before each write; if not `.ready`, the frame is dropped. Prevents indicator flicker mid-capture without requiring stream-drain coordination.

**`engine.start()` idempotency.** The existing `ARKitCaptureEngine.start()` is idempotent by construction: `session.run(_:options:)` with `.resetTracking | .removeExistingAnchors` is safe to call multiple times, and `CMMotionManager.startDeviceMotionUpdates()` no-ops on the second call. The model calls `start()` unconditionally on `.initialising` entry; documented here so re-entry from `sessionInterruptionEnded` or cold-launch take the same path.

**Re-entry asymmetry (.trackingLost → .ready vs .permissionDenied → .initialising).** Intentional: `.trackingLost` means the engine is running (just lost tracking); when tracking returns to `.normal` we go straight back to `.ready`. `.permissionDenied` means we never successfully ran `engine.start()`; on re-grant we go to `.initialising` to re-trigger the start sequence.

**Permission re-check.** `AVCaptureDevice.authorizationStatus(for:)` doesn't push changes. The model re-checks both camera and motion authorisation on `scenePhase == .active` transitions (forwarded from `App.swift`); on a flip from `.denied` to `.authorized`, state moves from `.permissionDenied` to `.initialising`.

**§1.2 release timing.** The model owns the `CaptureSession`; on `scenePhase == .background` it calls `try await session.stop()` which delegates to `engine.release()` and inherits research Req 2.5's 200 ms ceiling.

### Integration points (file map)

| File | Change |
|---|---|
| `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` | Add three additive accessors: `var arSession: ARSession`, `var frames: AsyncStream<ARFrame>`, `var interruptions: AsyncStream<InterruptionEvent>`. Implement the two `ARSessionObserver` interruption methods to feed the interruption stream. Both streams use per-subscriber continuations with `BufferingPolicy.bufferingNewest(1)`. ~40 lines. |
| `MedataCore/Sources/Pipeline/PipelineEstimator.swift` | **New** — `public protocol PipelineEstimator: Sendable { func estimate(captureResult: CaptureResult) async throws -> MealRecord }` plus `extension Pipeline: PipelineEstimator {}`. ~6 lines. Test seam per Decision 13. |
| `App/App.swift` | Owns `CaptureFlowModel` as `@State`; passes to `CaptureFlowView` via initialiser. Observes `@Environment(\.scenePhase)` for background/foreground transitions and forwards to the model. |
| `App/CaptureFlowView.swift` | Rewrite from placeholder; root view of the app's `NavigationStack(path: $model.navigationPath)`. |
| `App/LiveIndicatorView.swift` | **New** — child SwiftUI view consuming a child `@Observable LiveIndicatorModel` (split from the main model) to isolate 60Hz redraws from the rest of the capture view. Renders tilt indicator, distance state, LiDAR coverage gauge, capture-path indicator. |
| `App/LiveSampleObserver.swift` | **New** — `@MainActor` actor that iterates `engine.frames` (the new AsyncStream), computes per-frame tilt + distance + LiDAR coverage, writes to `LiveIndicatorModel`. Stops iteration when `CaptureFlowModel.state` enters `.capturing` or `.estimating` (subscribed via Observation tracking). |
| `App/ARPreviewView.swift` | **New** — `UIViewRepresentable` wrapping `ARView(frame:.zero, cameraMode:.ar, automaticallyConfigureSession: false)`. In `makeUIView`, assigns `arView.session = engine.arSession` and immediately re-asserts `engine.session.delegate = engine` to guard against `ARView` reassigning the delegate (test asserts this on init — see Test Strategy). |
| `App/RefusalBanner.swift` | **Superseded in v1.1** by `App/RefusalSheet.swift` per Req §20.7. The v1.0 top-banner overlay is removed. |
| `App/RefusalSheet.swift` | **New (v1.1)** — bottom-sheet view presented via `.sheet(item: $model.refusal)` with `.presentationDetents([.fraction(0.35)])` and `.presentationDragIndicator(.visible)`. SF Symbol + title + one-line copy + single "Try again" CTA. Spec: `design-system/pages/photo-tab.md` §"Refusal banner". |
| `App/CaptureTopBar.swift` | **New (v1.1)** — minimal top-chrome view per `design-system/pages/photo-tab.md` §"Top chrome". Hosts the close (`xmark`) button and the flash/torch toggle. White SF Symbols in 40pt `captureChromeBG` capsules. |
| `App/LiveIndicatorBadge.swift` | **New (v1.1)** — single consolidated indicator chip replacing the v1.0 three-corner `LiveIndicatorView`. Inline tilt / distance / LiDAR-coverage sub-elements. Auto-hide after 5 s in-range `.ready`, re-show on tap or out-of-range. Spec: `design-system/pages/photo-tab.md` §"Indicator badge". |
| `App/LiveIndicatorView.swift` | **Superseded in v1.1** by `LiveIndicatorBadge.swift` per Req §20.4. The v1.0 three-corner layout is removed; the `LiveIndicatorModel` change-tracking surface is preserved and consumed by the new badge view. |
| `App/CaptureModeToggle.swift` | **Modified (v1.1)** — capsule pill with an animated inner accent pill, replacing the v1.0 segmented control. Same `@AppStorage(SettingsKeys.captureMode)` binding (the namespaced key — not a bare `"captureMode"` literal). Spec: `design-system/pages/photo-tab.md` §"Capture-mode pill". |
| `App/ShutterButton.swift` | **New (v1.1)** — 76pt circular shutter extracted out of `CaptureFlowView`. Press feedback per Req §20.6. Spec: `design-system/pages/photo-tab.md` §"Shutter". |
| `App/ConfidencePill.swift` | **New (v1.1)** — shared view rendering the four-tier confidence pill (High / Moderate / Low / Very Low; icon + label + value) reused by `ResultView` and `MealRow`. Four-tier per Decision 17 (supersedes the three-tier Decision 8). SF Symbols added per the `color-not-only` rule. |
| `App/ResultView.swift` | Rewrite from placeholder; consumes `MealRecord`. |
| `App/SettingsView.swift` | Extend placeholder with "Export archive" button → `ShareSheet`. |
| `App/ShareSheet.swift` | **New** — `UIViewControllerRepresentable` wrapping `UIActivityViewController`. |
| `App/Colors.swift` | **New** — brand colour tokens. |
| `App/CaptureModeToggle.swift` | **New** — `View` rendering the persistent `Single` / `Double` segmented control bound to `@AppStorage(SettingsKeys.captureMode)` (the namespaced key). Disables `Single` when `!supportsLiDAR`. Disabled visually while `model.state` is anything other than `.ready` / `.refused` / `.permissionDenied` / `.trackingLost`. |
| `App/CaptureFlowModel.swift` | **New** — `@Observable @MainActor` state model + `CaptureFlowDelegate` conformance (no-op for `didUpdateTilt`/`didUpdateLiDARCoverage`; routes `didProduceEstimate` and `didDetectInterClassOcclusion`). Adds `tabSelectionChanged(to:)` method per Architecture §"Tab shell". |
| `App/LiveIndicatorModel.swift` | **New** — child `@Observable` holding `liveTiltDegrees`, `liveDistanceCm`, `liveLiDARCoveragePercent`. Owned by `CaptureFlowModel`, passed to `LiveIndicatorView` only. |
| `App/AppRoot.swift` | **New** (v1.1) — `TabView` owner per Architecture §"Tab shell". Owns `CaptureFlowModel` and `MealHistoryModel`. Replaces the v1.0 entry point where `App.swift` directly presented `CaptureFlowView`. |
| `App/MealsTabView.swift` | **New** (v1.1) — Meals tab root: `NavigationStack` wrapping `MealListView` and a `.navigationDestination(for: MealRecord.self) { ResultView(record: $0, mode: .historyDetail) }`. |
| `App/MealListView.swift` | **New** (v1.1) — `List` of `MealRow` over `model.meals` with `swipeActions(edge: .trailing)` providing Delete (Req §19.7), and an empty-state placeholder (Req §19.5). |
| `App/MealRow.swift` | **New** (v1.1) — list-row view: thumbnail (resolved via `PHImageManager.requestImage(for:targetSize:contentMode:options:resultHandler:)` keyed on `record.photoAssetID`), timestamp, carbohydrate total, confidence pill (shared component reused from `ResultView`), and the yellow "Placeholder" chip when `record.segmenterSource == "dev_stub"` (Req §19.3). |
| `App/MealHistoryModel.swift` | **New** (v1.1) — `@Observable @MainActor` model owning `meals: [MealRecord]`. Subscribes to `PersistenceStore.eventsDidChange: AsyncStream<Void>` (new — see below) to refresh within 500 ms of a new meal landing (Req §19.6). Loads initial state via `store.allMeals()` on first appearance. |
| `MedataCore/Sources/Persistence/PersistenceStore.swift` | **Additive (v1.1)** — new methods `func allMeals() async throws -> [MealRecord]` (reads `event_type = meal` rows from the `events` table, sorted by `createdAt` desc — see event-log-schema spec), `func deleteMeal(id: UUID) async throws` (removes the event row + artefact directory; does NOT touch the `PHAsset`), and a `var eventsDidChange: AsyncStream<Void>` change-notification stream emitted on every `save`, `deleteMeal`, and `updatePhotoAssetID`. The GRDB-backed conformer implements all three. |
| `App/SettingsView.swift` | Extend placeholder with "Export archive" button → `ShareSheet`. v1.1: the previous in-capture-view navigation entry is removed; the view is reached only via the Settings tab (Req §11.1). |
| `MeData/MeData.xcodeproj/project.pbxproj` | New files added to the `MeData` target. `Info.plist` keys: `NSCameraUsageDescription`, `NSMotionUsageDescription`, `NSPhotoLibraryUsageDescription` (for `PHImageManager` thumbnail fetches per Req §19.2), `UIRequiredDeviceCapabilities = [arkit]`, `UISupportedInterfaceOrientations = [UIInterfaceOrientationPortrait]`. |

Asset pipeline (`static/icon.svg` → `Assets.xcassets/AppIcon.appiconset/*.png`) is a one-off shell-script task captured in `tasks.md`, not a code-time concern.

## Components and Interfaces

### `CaptureFlowModel` — the orchestrator

`@Observable @MainActor final class CaptureFlowModel: CaptureFlowDelegate` — owns `CaptureState`, holds strong references to the `CaptureSession`, the `any PipelineEstimator`, and the child `LiveIndicatorModel`. Conforms to `CaptureFlowDelegate` so `Pipeline.estimate` can call back to it.

Behavioural contracts not visible in signatures:

- **Estimation is wrapped in a `Task` stored on the model** so the model's `cancelInFlight()` can be called from scene-phase hooks. The model writes `lastMeal` only on `Pipeline.estimate` *returning*. ⚠️ §8.3 caveat per Decision 12: MedataCore's `Pipeline.estimate` has no cooperative cancellation points; `Task.cancel()` from the UI does NOT actually interrupt the in-flight pipeline. The UI's contribution to §8.3 is limited to (a) ignoring the result if a cancellation was requested before the pipeline returns, and (b) showing the `.initialising` state on foreground. A `MealRecord` may still appear in the persisted store; correcting that requires the sibling Pipeline-cancellation spec.
- **`databaseEdition` and `paletteVersion`** are read once at app launch and cached on the model. Sources: `FoodDatabase.currentEdition` and the bundled segmenter palette. Read via a small `AppEnvironment` helper instantiated in the model's initialiser.
- **Live observation runs only while `state` is `.ready`.** When state enters `.capturing`, `.estimating`, `.showingResult`, `.refused`, `.permissionDenied`, or `.trackingLost`, the model cancels its `frames` iteration task. On return to `.ready`, a fresh iteration task is launched.
- **`captureMode` is read at shutter-tap time, not derived.** The persistent segmented control is the single source of truth; in v1 there is no active auto-derivation from LiDAR coverage. `App/CapturePathDecider.swift` still exists but is compiled out behind the deferred `#if AUTO_CAPTURE_MODE` flag (research Req 3.9 / Decision 35) and plays no part in the v1 flow. The previous floating capture-path hint and `.forcingTwoView` transient state are removed per research design §0 / Decision 35.
- **`didDetectInterClassOcclusion` and the live-signal protocol methods (`didUpdateTilt`, `didUpdateLiDARCoverage`) are no-ops** in the v1 model (Decisions 9 and 11). The protocol conformance exists for forward compatibility.

### `CaptureModeToggle` — persistent segmented control

```swift
struct CaptureModeToggle: View {
    @AppStorage(SettingsKeys.captureMode) private var mode: CaptureMode = .double   // namespaced key, not bare "captureMode"
    let supportsLiDAR: Bool
    let interactive: Bool   // false while .capturing/.estimating

    var body: some View {
        Picker("Capture mode", selection: $mode) {
            Text("Single").tag(CaptureMode.single).disabled(!supportsLiDAR)
            Text("Double").tag(CaptureMode.double)
        }
        .pickerStyle(.segmented)
        .disabled(!interactive)
    }
}
```

Single source of truth for the active capture path per requirements §4. `@AppStorage` persists across launches; the `CaptureMode` value is read at shutter-tap time by `CaptureFlowModel`. Tested for: persistence across re-instantiation; Single is disabled when `supportsLiDAR == false`; the control is non-interactive while a capture or estimation is in flight (§4.4).

### `LiveSampleObserver`

`@MainActor final class LiveSampleObserver` — iterates `engine.frames` (the new `AsyncStream<ARFrame>` accessor on `ARKitCaptureEngine`) and writes per-frame:

- `liveTiltDegrees` ← computed from `frame.camera.transform`'s gravity-aligned column.
- `liveDistanceCm` ← median of `frame.sceneDepth?.depthMap` over a centre-window crop (research design §6.0 references the same crop) — `nil` when `sceneDepth` is unavailable.
- `liveLiDARCoveragePercent` ← fraction of depth pixels with `confidence >= τ_conf = 0.66`, ×100. Same threshold as research design §6.0.

Started/cancelled by `CaptureFlowModel` based on state (see CaptureFlowModel contract). `BufferingPolicy.bufferingNewest(1)` on the stream means slow consumers see the latest frame, not a backlog. Writes go to the child `LiveIndicatorModel` (a sibling `@Observable`), not directly to `CaptureFlowModel`, so 60-Hz writes don't retrigger `CaptureFlowView.body`.

### `ARPreviewView` — `UIViewRepresentable`

Wraps `ARView(frame:.zero, cameraMode:.ar, automaticallyConfigureSession: false)` from RealityKit (iOS 17+). The view's `session` is set to `engine.arSession`. Both `makeUIView` AND `updateUIView` re-assert `engine.session.delegate = engine` — RealityKit's `ARView` has historically reassigned the delegate during internal lifecycle events, not just at init. A single re-assertion at `makeUIView` time is not sufficient. The re-assertion is cheap (a property write) and idempotent.

`ARView` rather than `ARSCNView`: SceneKit is the Apple-deprecated direction; RealityKit's `ARView` is the modern path and natively renders the camera feed.

### `RefusalBanner`

SwiftUI overlay (`.overlay(alignment: .top)`) on the capture view. Shows the `EstimationFailure.localisedMessage` plus a "Try again" button. **Non-dismissable by tap-outside** (requirements §10 implication, decision_log Decision 5 promotion): only "Try again" clears it. Implementation: a `ZStack` overlay with `.allowsHitTesting(true)` on the banner, `.allowsHitTesting(false)` on a backdrop pass-through that just blocks shutter tap. The live preview continues to render behind.

### `ResultView`

Pushed onto `NavigationStack` via `.navigationDestination(for: MealRecord.self)`. `MealRecord` is already `Hashable` (shipped). View body:

- **Total carbs** (large numeric, accent colour): `"\(Int(record.macros.totalCarbsG.rounded())) g"`. When `sigmaMeal < 0.20`, append a "(rough estimate)" suffix in `caption` weight beneath the numeric.
- **Confidence pill**: four labels keyed off `record.confidence.sigmaMeal` per requirements §9.2 thresholds (Decision 17 supersedes Decision 8). Pill background uses four discrete colour tokens defined in `Colors.swift`.
- **Very-low-confidence surface** (conditional on `sigmaMeal < 0.20`, per requirements §9.3): a two-line `caption` block reading "This estimate may be wrong by orders of magnitude. Capture was at \(Δθ)° from target." (Δθ pulled from `record.confidence.deltaThetaNadirDeg` for single-view; `max(deltaThetaNadirDeg, deltaThetaObliqueDeg ?? 0)` for two-view), followed by a row of two side-by-side buttons: "Retake" (pops back, resets `state` to `.ready`) and "Keep as-is" (dismisses the surface but leaves the result view; the meal is already persisted).
- **"New capture" button**: pops the result view. Hidden when presented from the Meals tab.

No per-class breakdown, no clinical macros (requirements §9.5, Decision 3).

### `SettingsView`

The retention picker and IFCDB toggle were **removed** (research §0 / Decision 39, research task 74; photo lifecycle is delegated to the Photos library, CoFID + AFCD are always bundled). The live settings are the persistent `captureMode` toggle (Decision 35) plus:

- **"Export archive" button** — calls into `PersistenceStore.exportArchive() async throws -> URL`, then presents `ShareSheet(items: [url])` via `.sheet(item:)`. `ShareSheet` is `UIViewControllerRepresentable` wrapping `UIActivityViewController(activityItems:applicationActivities:)`.

### Meals tab (v1.1)

`MealHistoryModel` is `@Observable @MainActor`:

```swift
@Observable @MainActor final class MealHistoryModel {
    var meals: [MealRecord] = []
    private let store: any PersistenceStore
    private var changeSubscription: Task<Void, Never>?

    init(store: any PersistenceStore) { self.store = store }

    func start() async {
        meals = (try? await store.allMeals()) ?? []
        changeSubscription = Task { [weak self] in
            guard let stream = self?.store.eventsDidChange else { return }
            for await _ in stream {
                self?.meals = (try? await self?.store.allMeals()) ?? []
            }
        }
    }

    func delete(_ record: MealRecord) async {
        try? await store.deleteMeal(id: record.id)
        // eventsDidChange will re-fire and refresh meals
    }
}
```

`MealRow` shares the confidence-pill rendering code with `ResultView` — both consume a `ConfidencePill(sigmaMeal:)` view extracted into a small shared component. The placeholder chip is rendered conditionally on `record.segmenterSource == "dev_stub"` (Req §19.3) using the same yellow background as the result-view placeholder banner (research Req 23.3).

`ResultView` is reused as the meal-detail view in the Meals tab. It already takes a `MealRecord`; no new view is introduced. The "New capture" button is hidden when the result view is presented from the Meals tab (it's only meaningful right after a capture). A presentation-context enum drives this:

```swift
enum ResultPresentation { case justCaptured, historyDetail }
struct ResultView: View {
    let record: MealRecord
    let mode: ResultPresentation
    // ...
}
```

Photos-library reads. `MealRow` and `ResultView` request thumbnails via `PHImageManager.default().requestImage(for:targetSize:contentMode:options:resultHandler:)`. When the user has denied or limited Photos access, `requestImage` returns `nil` for the image and the row/result view fall back to a `photo.fill` SF Symbol placeholder. No additional permission prompt is triggered by the Meals tab; the `.addOnly` request from research task 73 is the only Photos prompt the app makes in v1.

### Colour tokens

```swift
// App/Colors.swift
extension Color {
    static let medataAccent      = Color(red: 0x63/255, green: 0xFF/255, blue: 0x00/255)
    static let confidenceHigh    = medataAccent
    static let confidenceModerate = Color.orange
    static let confidenceLow     = Color.red
    static let confidenceVeryLow = Color(white: 0.35)        // greyscale: "essentially worthless"
}
```

The four-tier scheme replaces the three-tier scheme from Decision 8. `confidenceVeryLow` is intentionally desaturated rather than red — red was used at the "Low" tier already, and the Very Low tier needs to read as "use this with skepticism" rather than as "alarm." The pill renders monochrome at this tier so the user notices the surrounding inline explanation copy rather than the pill colour. See UI `decision_log.md` Decision 17.

Applied to the SwiftUI scene via `.tint(.medataAccent)` on `WindowGroup`'s root view (requirements §15.1).

### Test seam — `PipelineEstimator` protocol

```swift
// MedataCore/Sources/Pipeline/PipelineEstimator.swift
public protocol PipelineEstimator: Sendable {
    func estimate(captureResult: CaptureResult) async throws -> MealRecord
}
extension Pipeline: PipelineEstimator {}
```

`CaptureFlowModel` holds `any PipelineEstimator`. Tests pass a `MockPipeline` struct conforming to the protocol with a programmable `Result<MealRecord, Error>`. Production code passes a real `Pipeline`. Placement in MedataCore per Decision 13 — the abstraction is API-shaped, not UI-internal.

## Data Models

No new persistent types. App-side enums introduced: `CaptureState`, `CaptureStage`, `PermissionSubject`, `GatingSnapshot` (above). `MealRecord`, `EstimationFailure`, `CapturePath`, `CaptureResult`, `RawFrame` are consumed verbatim from MedataCore.

## Error Handling

`Pipeline.estimate(_:)` and `CaptureSession.captureNadir/Oblique` are the throw sites reaching the UI. Failure path in `CaptureFlowModel`:

1. `try await pipeline.estimate(captureResult:)` is wrapped in `do { ... } catch let f as EstimationFailure { state = .refused(f, retryStage:) } catch is CancellationError { /* swallowed; foreground path resets state */ } catch { state = .refused(.captureFailed(error.localizedDescription), retryStage:) }`.
2. `try await session.captureNadir()` (and `captureOblique`) similarly: `CaptureError` is mapped to a generic `.refused` with the captured-frame error message.

Permission denial is detected at `CaptureFlowModel.init` via `AVCaptureDevice.authorizationStatus(for: .video)` and `CMMotionManager.isDeviceMotionAvailable`. Denial sets `state = .permissionDenied(.camera | .motion)`; the view renders the §1.3 deep-link button.

AR-session interruption is consumed via the `interruptions: AsyncStream<InterruptionEvent>` accessor on `ARKitCaptureEngine` (declared in the Integration Points table above; the engine implements the previously-unimplemented `ARSessionObserver.sessionWasInterrupted/Ended` methods to feed it). `CaptureFlowModel` iterates `interruptions` for the lifetime of the model: `.began` → `state = .trackingLost` + release the engine; `.ended` → re-call `engine.start()` (idempotent — see state-machine notes) and `state = .initialising`. The full enum definition: `enum InterruptionEvent: Sendable { case began, ended }`.

## Testing Strategy

- **`CapturePathDecider`** (deferred — `#if AUTO_CAPTURE_MODE` only) — XCTest table: `[(supportsLiDAR, coverage, expectedPath)]` × five boundary rows. This covers the dormant auto-derivation logic preserved behind the compile flag (research Req 3.9 / Decision 35); it is **not** the v1 active path (the `captureMode` toggle is authoritative).
- **`CaptureFlowModel` state transitions** — XCTest with a `MockCaptureSession` (returns canned `RawFrame` fixtures) and a `MockPipeline: PipelineEstimator` (programmable `Result<MealRecord, Error>`). Drive each transition row from the state-machine table; assert resulting state and rejection of illegal transitions (in debug builds via `assertionFailure` capture).
- **Gating-snapshot freeze rule** — XCTest: enter `.ready` with snapshot A, change a live gating value, immediately fire shutter tap on the same MainActor tick; assert the `.capturing(.nadir, frozen:)` carries snapshot A, not the post-change one. (The frozen value is the gating snapshot — `captureMode` is read directly from the toggle at tap time, not derived from coverage.)
- **`LiveSampleObserver` distance + coverage maths** — unit tests with synthesised `CVPixelBuffer` depth/confidence pairs (existing fixtures in `CaptureKitTests`); assert centre-crop median and `≥ τ_conf` count.
- **`ARKitCaptureEngine.frames` and `.interruptions` streams** — `CaptureKitTests` additions: assert subscriber receives latest-only frame on slow consumption (`BufferingPolicy.bufferingNewest(1)`); assert interruption stream yields `.began` and `.ended` in order from mocked `ARSession` delegate calls; assert cancelling iteration unsubscribes without leaking continuations.
- **Delegate-reassignment guard in `ARPreviewView`** — XCTest: after `ARView` is created with `engine.arSession`, assert `engine.session.delegate === engine` immediately and after a forced `updateUIView` invocation. Both `makeUIView` and `updateUIView` re-assert the delegate (RealityKit may install itself at either lifecycle point).
- **Rapid shutter taps (§7.4 debounce)** — XCTest: model in `.ready`, fire shutter tap, then fire a second tap before the first transition completes; assert the second tap is no-op (state observation count ≤ 1).
- **Confidence pill thresholds** (four-tier per Decision 17) — XCTest table: σ_meal ∈ {0.0, 0.19, 0.20, 0.59, 0.60, 0.74, 0.75, 1.0} → expected pill label (Very Low / Very Low / Low / Low / Moderate / Moderate / High / High); retake prompt fires only for σ < 0.20.
- **AR interruption recovery (§16.1)** — XCTest with mocked engine: emit `.began` on the interruption stream → assert `state = .trackingLost`; emit `.ended` → assert `engine.start()` re-called and `state = .initialising`.
- **Permission-denied state (§13.3)** — XCTest with stubbed `AVCaptureDevice.authorizationStatus(for:)` returning `.denied`; assert model initialises to `.permissionDenied(.camera)`.
- **Refusal banner** — XCUITest: trip `EstimationFailure.noScaleAvailable` via a fixture, assert banner appears with Irish-English message, "Try again" returns to `.capturing` at the right stage.
- **Backgrounding** (requirements §8.3, best-effort per Decision 12) — XCUITest: tap shutter, background app via `XCUIDevice.shared.press(.home)`, foreground; assert the UI is in `.initialising`. (Note: with no pipeline cancellation, a `MealRecord` may exist in the in-memory store; this test asserts UI state only.)
- **End-to-end on-device** — manual; not automated in this spec. Performance is covered by the research spec's single end-to-end **30 s soft check** (research task 75 / Req 16.1) on the iPhone 13 Pro Max test device; the per-stage `XCTClockMetric` P95 assertions were removed (research §0 / Decision 40).
- **Property-based tests** — not appropriate here: the state machine has a finite, small transition graph (better covered by exhaustive example tests); no parsers, serialisers, or invariants that benefit from PBT.

**v1.1 additions:**

- **`AppRoot` tab persistence (Req §18.6)** — XCUITest: launch app, switch to Meals tab, kill app, relaunch; assert Meals tab is selected. Reset `@AppStorage("selectedTab")` between tests via launch argument.
- **Tab-switch capture lifecycle (Req §1.7, §18.7)** — XCTest: model in `.ready`, switch tab away → assert `.initialising` on Photo re-entry and `engine.release()` was called within 200 ms; model in `.estimating`, switch away → assert `Pipeline.estimate` is NOT cancelled and the resulting `MealRecord` lands; on Photo re-entry the state SHALL be `.showingResult(record)`.
- **`MealHistoryModel` change-stream refresh (Req §19.6)** — XCTest with a fake `PersistenceStore` exposing a controllable `eventsDidChange` continuation; emit a tick, assert `model.meals` reloads within 500 ms.
- **`MealRow` placeholder chip (Req §19.3)** — XCTest: render `MealRow` with `segmenterSource = "dev_stub"` and `segmenterSource = "coreml_v0.1"`; assert chip presence/absence via accessibility-identifier visibility.
- **Meal delete (Req §19.7)** — XCTest: seed two meals, call `MealHistoryModel.delete(meals[0])`; assert `store.allMeals()` returns one row, the corresponding artefact directory is removed, and `PHPhotoLibrary` is NOT touched (mock `PHPhotoLibrary` to assert no `performChanges` call).
- **Meals empty state (Req §19.5)** — XCUITest: launch on a fresh container, switch to Meals tab, assert the empty-state copy and fork-knife icon are visible; no list rows present.
- **Result-view presentation mode (design §"Meals tab")** — XCTest: render `ResultView(record:, mode: .historyDetail)` and assert the "New capture" button is hidden; render with `mode: .justCaptured` and assert it is shown.
- **Tab-bar re-tap pop-to-root (Req §18.5)** — XCUITest: Meals tab → tap a row to push the detail view → re-tap Meals tab item; assert the list view is visible (detail popped).

## Out of Scope (consistency check vs requirements Non-Goals)

| Non-goal | Design verifies absent |
|---|---|
| Accessibility / VoiceOver | No `accessibilityLabel`/`accessibilityValue`/`accessibilityElement` modifiers specified beyond what SwiftUI ships by default. |
| Corrections UI | `ResultView` carries no editable fields. `PersistenceStore.appendCorrection` is not called from the UI. |
| Data import | No code path consumes the export archive format. Settings tab exposes only `exportArchive()`; no `importArchive(_:)` button. |
| Model / inference info panel | No `SettingsView` row reads `MealRecord.segmenterSource` or any `Pipeline` introspection — the persisted `segmenterSource` is surfaced only via the per-row placeholder chip (Req §19.3) and result-view banner (research Req §23.3). |
| Debug info panel | No `SettingsView` row reads compile-flag state, build configuration, or `EstimationFailure` history. |
| Per-class breakdown / clinical macros | `ResultView` body shows only `record.macros.totalCarbsG` (rounded) + `record.confidence.sigmaMeal` pill. |
| iPad / Watch layouts | No size-class checks; portrait-only constraint set via Info.plist `UISupportedInterfaceOrientations` (iPhone only). |
| Onboarding flow | App root scene is `AppRoot` (TabView with Photo tab selected). No pre-tab intro view. |
| Meal-list search / filter / multi-select | `MealListView` is a plain `List(model.meals)` with one trailing `swipeActions` delete. No `.searchable`, no `EditButton`, no selection binding. |

# UI capture flow (App/)

> **Shell superseded by `specs/ui/design-handoff-00/` (2026-07-04).** The tab shell is gone:
> **Graph** (`TrendsView`, renamed in UI only — Decision 21) is the launch root, and Capture /
> Data / Settings present as mutually-exclusive `.fullScreenCover`s from Graph's toolbar
> (`AppRoot.ActiveSheet`, Decisions 19–20). The AR session runs ONLY while the Capture cover
> is frontmost: `CaptureFlowModel.capturePresented()` arms (via `.initialising`),
> `captureDismissed()` releases; `evaluatePermissions` is gated on `isCapturePresented`, so
> launch shows no camera prompt. The old `tabSelectionChanged`/`sheetDidPresent` hooks are
> these same bodies renamed. Capture chrome: close control (top-leading, returns to Graph),
> mode capsule (`1-VIEW · LiDAR` / `2-VIEW · NADIR` / `2-VIEW · OBLIQUE`), 76 pt bubble level
> (stage-relative, non-gating), telemetry capsule, bottom row = mode + shutter (torch,
> Trends/Data/Settings buttons all gone). Navigation: route enums only — `CaptureRoute`
> (review/result/correction) on the capture stack, `MealRoute` on Graph/Data stacks;
> `navigationDestination(for: MealRecord.self)` no longer exists, and an `.onChange` on
> `navigationPath` resyncs `.showingResult` if the user pops via back-gesture (soft-lock fix).
> Developer-phase copy rule (CLAUDE.md / Req 14.5): no reassurance/disclaimer strings.
> Retired dead files: `CaptureTopBar`, `CaptureModeToggle`, `RefusalSheet` (replaced by
> `CaptureErrorOverlay`), `MealsTabView`, `MealRow`. The architecture notes below (state
> machine, gating, pre-shutter mask, one-ARSession rule) remain accurate.

The iOS SwiftUI capture flow per `specs/ui/iphone-experience/` (shell/chrome now per
`design-handoff-00`, see banner). New code lives in `App/`; the
Xcode project (`MeData/MeData.xcodeproj`) references the files in place via
`../App/*.swift`. All spec tasks (1–28) are implemented.

## Architecture

`CaptureFlowModel` (`@Observable @MainActor`) is the single source of truth.
It owns the `CaptureState` state machine, a `CaptureSession`, an
`any PipelineEstimator`, and the child `LiveIndicatorModel`. The view layer is
composition only; all behaviour is in the model and is unit-tested.

- **CaptureFlowModel** — drives the state machine from `specs/ui/iphone-experience/design.md`.
  Public commands: `shutter()`, `forceTwoView()`, `tryAgain()`,
  `dismissResult()`, `scenePhaseChanged(_:)`, `liveSampleDidUpdate(...)`,
  `trackingDegraded()`, `handleInterruption(_:)`. Derived view state:
  `canShutter`, `currentSnapshot`, `isBusy`, `awaitingObliqueView`. Conforms to
  `CaptureFlowDelegate` with no-op `didUpdateTilt`/`didUpdateLiDARCoverage`/
  `didDetectInterClassOcclusion` (Decisions 9, 11).
- **LiveSampleObserver** — iterates `engine.frames`, computes per-frame
  tilt/distance/coverage via `LiveSampleMath` (pure, testable on simd +
  CVPixelBuffer because `ARFrame` has no public init), forwards to the model.
  Write-gating lives in `apply(_:)`: samples are dropped unless state is
  `.ready`/`.forcingTwoView`/`.initialising`/`.trackingLost`.
- **ARPreviewView** — `UIViewRepresentable` over `ARView`. `ARView.session` is
  get-only, so the engine's own session can't be injected into the view.
  Instead the engine **adopts the ARView's session** as the one authoritative
  `ARSession` via `engine.bindPreviewSession(_:)` (called from both makeUIView
  and updateUIView through the testable `bind(to:)` seam). The engine becomes
  that session's sole delegate and runs the world-tracking config on it. This
  is the single-session realisation of Decision 11/14. Tests drive `bind(to:)`
  with a plain `ARSession` because the SwiftUI `Context` has no public init.

## Gotchas / non-obvious behaviour

- **`ARPreviewView`'s ARView must stay `isUserInteractionEnabled = false`.** RealityKit's
  `ARView` is a real UIView with its own gesture recognisers; UIKit resolves touches to it
  ahead of SwiftUI-drawn siblings, and `allowsHitTesting(false)`/`zIndex` on the
  representable are NOT reliable across that boundary (the 3429ddc fix that didn't take on
  device — Retry/2-view dead, Cancel alive). The preview is render-only; all controls are
  SwiftUI. Regression: `specs/bugfixes/capture-no-flat-surface-gravity-frame/report.md`.
- **Full-width SwiftUI buttons: sizing/`contentShape` go INSIDE the Button label.** A
  Button's tap gesture covers only its label; `.frame(maxWidth:)`/`.contentShape` applied
  outside the Button draw a wide pill whose surface is dead. `CaptureErrorOverlay` is the
  reference pattern.
- **`RawFrame.gravity` is world-up in the §6.0 camera frame — pose-dependent.** Derived
  per-frame via `CameraGravity.worldUpInCameraFrame(worldFromCamera:)` (CaptureKit); a
  constant only looks right at the identity pose and kills the plane fitter's ±15° gravity
  gate on every real capture (`supportplane.end candidates=N inliers=0` → "no flat
  surface" in both modes). Treat `inliers=0` with large `candidates` as a convention/input
  bug, never a scene problem. Same bugfix report as above.

- **RefusalSheet dismissal is wired through `dismissRefusal()`, not the binding setter (Decision 20).** `model.refusal` is strictly derived from `state == .refused` — the setter on the model is gone. The view-side `refusalBinding` calls `model.dismissRefusal()` when SwiftUI writes nil (swipe-down on the sheet). The model transitions `.refused → .ready(freshSnapshot())`, clearing `firstFrame`/`firstFrameTiltDeg`/`inFlightMode`. `tabSelectionChanged(to: nonPhoto)` also dismisses `.refused` (same shape as `.ready`/`.trackingLost`); `.permissionDenied` still preserves across tab switches. The explicit `tryAgain()` path is unchanged. Regression: `specs/bugfixes/surface-not-detected/report.md`.


- **One ARSession only — the engine adopts the ARView's session.** A regression
  (fixed, Decision 14) had `ARKitCaptureEngine` running its OWN `ARSession` while
  `ARView` ran a second one. Two AR sessions contend for the single camera capture
  source → repeated `FigCaptureSourceRemote` failures (`err=-12784`/`-17281` in the
  device log) and a `sessionWasInterrupted ↔ Ended` loop that flashed the UI between
  `.initialising`/`.trackingLost`. Fix: the engine no longer runs its placeholder
  session; `bindPreviewSession(_:)` swaps in the ARView's session and runs the config
  there (gated by `isRunning` so repeated `updateUIView` calls don't reset tracking).
  `start()` records intent and defers the run to bind if the view isn't up yet. **Do
  not reintroduce a second `ARSession`.** All session mutation happens on the main
  actor (`bindPreviewSession`/`start`/`release` via `MainActor.run`).
- **`performFlow` awaits `startTask` before capturing.** `CaptureSession`
  throws `.sessionNotStarted` if `captureNadir/Oblique` races ahead of the
  fire-and-forget `session.start()` kicked off on `.initialising` entry. In
  production start finishes during initialising; tests forced the race.
- **Tilt target depends on stage.** `liveSampleDidUpdate` takes raw
  `tiltDegrees` (angle from straight-down); the model computes in-range against
  0° for nadir and 25° once `firstFrame != nil` (awaiting oblique, §2.2/§2.3).
- **Nadir shutter is gated on a usable pre-shutter mask (`hasUsablePreShutterMask`).**
  `canShutter` (and the `shutter()` command) refuse the nadir stage until
  `preShutterSegmenter.latest` exists and is within the same 750 ms freshness
  bound `performFlow` applies at the nadir-capture instant. Without this, the
  first tap of a session could fire while `latest` was still nil →
  `maskAgeMs=-1` → `emptyFoodMask` → `noFoodPixels` refusal; the second tap then
  succeeded. The gate is bypassed when no segmenter is injected (tests / legacy;
  `App.swift` always passes one) so the shutter is never permanently disabled.
  Disabled-nadir state reuses the existing `ShutterButtonState.disabled` "waiting"
  UX. Regression: `specs/bugfixes/first-shot-nofoodpixels-race/report.md`.
- **Path hint is frozen at shutter tap** and locked to `.twoViewSfS` while
  awaiting the oblique view (so a coverage flip can't switch paths mid-sequence).
- **§8.3 is best-effort (Decision 12).** Backgrounding cancels the in-flight
  `flowTask` and resets UI to `.initialising`; the pipeline has no cooperative
  cancellation so a `MealRecord` may still be persisted.
- **Real pipeline, dev-stub segmenter.** `App.swift` now wires
  `Pipeline.makeForDevice(store:cardDetector:)` (the `PendingPipeline` stand-in
  was deleted — research task 81). Under `DEV_STUB_SEGMENTER` (Phase 1) the
  pipeline runs end-to-end with `StubInferenceEngine`, producing a placeholder
  carb value rather than a refusal. Capture, gating, refusal, and persistence all
  work; real estimates await the Phase 3 trained model (Blocker 1 in
  [`pipeline-wiring-status.md`](pipeline-wiring-status.md)).

## Tests

Unit tests are in `MeData/Tests/` using Swift Testing (`@Test`/`#expect`) with
`@testable import MeData`. XCUITests are in `MeData/UITests/` (XCTest).
**Neither is wired into the committed Xcode project** (no test targets exist —
the pre-existing `CapturePathDeciderTests.swift` is the same).

**Convention (2026-07-03): the files in `MeData/Tests/` and `MeData/UITests/`
are documentation contracts, not an executable suite.** They compile against
the app source and record intended behaviour, but no committed target runs
them. Agents MUST NOT claim to have "run" them, count them in test totals
(`make test` covers the SwiftPM core only), or write new app-target tests
expecting execution — the MVP gate for app/UI work is "does it build + does it
look right on device" (see CLAUDE.md). If execution is ever genuinely needed,
the historical recipe is a temporary unit-test target with
`TEST_HOST = $(BUILT_PRODUCTS_DIR)/MeData.app/MeData` (validated once: all 40
passed on the iPhone 17 Pro simulator).

## Adding a new file under `App/` — pbxproj checklist

`App/*.swift` files are NOT auto-discovered (unlike `MeData/MeData/`, which is
a file-system-synchronised group). Each file must be registered in
`MeData/MeData.xcodeproj/project.pbxproj` in **four places** (copy the
`RefusalSheet.swift` entries as a template, generating fresh 24-hex IDs):

1. `PBXBuildFile` section — `<buildID> /* X.swift in Sources */ = {isa = PBXBuildFile; fileRef = <fileID> …};`
2. `PBXFileReference` section — with `path = ../App/X.swift; sourceTree = SOURCE_ROOT;`
3. The `PBXGroup` children list that holds the other App files
4. The `PBXSourcesBuildPhase` files list

Miss one and the build either fails or silently omits the file. Conversely,
files dropped INSIDE `MeData/MeData/` are auto-added to the target including
Copy Bundle Resources — which is why `MeData/Info.plist` (build stamp) lives
outside that folder ("Multiple commands produce Info.plist" otherwise).

### XCUITests and the DEBUG harness (tasks 26–28)

The capture flow is AR-gated — the shutter only arms once a live `ARSession`
reaches `.ready`, and ARKit does not run on the simulator. So the three XCUITests
launch the app with `-uitest` and drive the flow through a `#if DEBUG` harness in
`App.swift` rather than a real camera:

- **`UITestSupport`** — reads launch args. `-uitest` activates the harness;
  `-uitestPipeline refuse|stall` selects the stub pipeline (refuse is default).
- **`UITestHarness`** — builds the `CaptureFlowModel` with a `UITestCaptureEngine`
  (capture blocks until released, so `.capturing` is observable), a stub pipeline,
  and an interruption `AsyncStream` it owns. Exposes `driveToReady()`,
  `releaseCapture()`, `emitInterruptionBegan/Ended()`.
- **`UITestControlPanel`** — hidden buttons (leading edge, clear of shutter/banner)
  that call those harness methods, queried by accessibility identifier
  (`uitest.driveToReady`, `uitest.releaseCapture`, `uitest.interruptionBegan/Ended`).

Other accessibility identifiers the tests query: `shutter`,
`hint.{initialising,trackingLost,estimating,capturing}`, `refusal.message`
(also asserted by verbatim text per §12.2), `refusal.tryAgain`. Note: an
`accessibilityIdentifier` on a plain SwiftUI container (e.g. the refusal banner
`VStack`) does not reliably surface as a queryable element — query the Label/Button
inside instead, which is why the refusal test keys off `refusal.message` not the
banner container.

`driveToReady()` calls `model.liveSampleDidUpdate(...)` directly because `ARFrame`
has no public init, so `LiveSampleObserver`'s real path can't be exercised on the
simulator. The interruption test asserts the UI proxy (`.initialising` hint) for
the `engine.start()` re-call, which is itself covered by the CaptureFlowModel unit
tests. Running these requires a device + a UI-test target (same separate-validation
pattern as the unit tests). Compilation was validated by building the app target
for the iPhone 17 Pro simulator after temporarily repointing the SPM to the local
`MedataCore` (see Build-path caveat).

## Build-path caveat

The Xcode project's `XCLocalSwiftPackageReference` is `relativePath = ../../medata`
— it only resolves when the repo is checked out at a directory literally named
`medata`. In a checkout named otherwise (e.g. `ui`), the package resolves to a
stale sibling and the SPM-prerequisite symbols (`ARKitCaptureEngine.frames`/
`.interruptions`/`InterruptionEvent`, `PipelineEstimator`) go missing. Point the
path at the actual checkout to build locally; do not commit that change.

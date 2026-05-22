# UI capture flow (App/)

The iOS SwiftUI capture flow per `specs/ui/`. New code lives in `App/`; the
Xcode project (`MeData/MeData.xcodeproj`) references the files in place via
`../App/*.swift`. All spec tasks (1–28) are implemented.

## Architecture

`CaptureFlowModel` (`@Observable @MainActor`) is the single source of truth.
It owns the `CaptureState` state machine, a `CaptureSession`, an
`any PipelineEstimator`, and the child `LiveIndicatorModel`. The view layer is
composition only; all behaviour is in the model and is unit-tested.

- **CaptureFlowModel** — drives the state machine from `specs/ui/design.md`.
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
  get-only, so the engine's session can't be injected; the engine stays the
  sole session owner/delegate and `reassertDelegate()` (called from both
  makeUIView and updateUIView) keeps it wired. Tests drive `reassertDelegate()`
  directly because the SwiftUI `Context` has no public init.

## Gotchas / non-obvious behaviour

- **`performFlow` awaits `startTask` before capturing.** `CaptureSession`
  throws `.sessionNotStarted` if `captureNadir/Oblique` races ahead of the
  fire-and-forget `session.start()` kicked off on `.initialising` entry. In
  production start finishes during initialising; tests forced the race.
- **Tilt target depends on stage.** `liveSampleDidUpdate` takes raw
  `tiltDegrees` (angle from straight-down); the model computes in-range against
  0° for nadir and 25° once `firstFrame != nil` (awaiting oblique, §2.2/§2.3).
- **Path hint is frozen at shutter tap** and locked to `.twoViewSfS` while
  awaiting the oblique view (so a coverage flip can't switch paths mid-sequence).
- **§8.3 is best-effort (Decision 12).** Backgrounding cancels the in-flight
  `flowTask` and resets UI to `.initialising`; the pipeline has no cooperative
  cancellation so a `MealRecord` may still be persisted.
- **`PendingPipeline` stand-in** in `App.swift` throws `.noScaleAvailable` until
  the segmenter-weights smolspec lands a real `Pipeline` (Decision 13). Capture,
  gating, and the refusal flow work; estimation surfaces a refusal for now.

## Tests

Unit tests are in `MeData/Tests/` using Swift Testing (`@Test`/`#expect`) with
`@testable import MeData`. XCUITests are in `MeData/UITests/` (XCTest).
**Neither is wired into the committed Xcode project** (no test targets exist —
the pre-existing `CapturePathDeciderTests.swift` is the same). To run unit tests,
add a temporary unit-test target with
`TEST_HOST = $(BUILT_PRODUCTS_DIR)/MeData.app/MeData`. Validated: all 40 tests
pass on the iPhone 17 Pro simulator.

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

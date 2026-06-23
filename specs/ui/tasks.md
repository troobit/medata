---
references:
    - specs/ui/requirements.md
    - specs/ui/design.md
    - specs/ui/decision_log.md
---
# UI — Implementation Tasks

> **Reading note — v1.0 tasks superseded by v1.1.** This list is layered: the **v1.1 sections**
> ("Tab navigation + Meals tab", "Visual design", "Tilt-tolerant capture") supersede earlier v1.0 task
> content where they conflict. The authoritative current behaviour is the **latest** decision (UI
> decision log Decisions 15–20) + `research/requirements.md`. Specifically, against the as-built code:
> - **Confidence pill is four-tier** (High / Moderate / Low / Very Low, retake at σ < 0.20) per Decision 17
>   / tasks 52–60 — the **three-tier** thresholds (σ < 0.60 prompt, Low/Moderate/High at 0.60/0.75) in the
>   v1.0 tasks (5, 20, 43) are superseded.
> - **No active auto path-selection.** `CapturePathDecider` (tasks 8–9) exists only behind the deferred
>   `#if AUTO_CAPTURE_MODE` flag (research Req 3.9 / Decision 35); the `captureMode` toggle is authoritative.
> - **`.forcingTwoView` was removed** from `CaptureState` (Decision 35) — `CaptureState` has 8 cases.
> - **OS floor is iOS 26.5** (research Req 1.2 / §0; UI Decision 4's iOS-17 baseline is superseded).
> - **Retention picker + IFCDB toggle removed** (research §0 / Decision 39).

## SPM prerequisites

- [x] 1. Write tests for ARKitCaptureEngine streams and interruption observer methods <!-- id:7pbwp43 -->
  - Add CaptureKitTests/ARKitCaptureEngineStreamsTests.swift
  - Assert frames stream emits ARFrame via simulated session(_:didUpdate:) calls
  - Assert latest-only delivery under BufferingPolicy.bufferingNewest(1)
  - Assert interruption stream emits .began on sessionWasInterrupted and .ended on sessionInterruptionEnded in order
  - Assert cancelling iteration removes the continuation (no leaks)
  - Assert engine.session.delegate === engine after frames subscription
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [16.1](requirements.md#16.1)

- [x] 2. Implement ARKitCaptureEngine accessors arSession, frames, interruptions plus ARSessionObserver interruption methods <!-- id:7pbwp44 -->
  - Edit MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift
  - Add public var arSession (returns the existing private session)
  - Add public var frames: AsyncStream<ARFrame> using AsyncStream.makeStream with bufferingNewest(1) per subscriber via a continuation-set actor
  - Add public enum InterruptionEvent { case began, ended } and var interruptions: AsyncStream<InterruptionEvent>
  - Implement session(_:wasInterrupted:) and sessionInterruptionEnded(_:) to yield to interruption continuations
  - Yield to frames continuations from the existing session(_:didUpdate:) hook
  - Make the tests from task 1 pass
  - Blocked-by: 7pbwp43 (Write tests for ARKitCaptureEngine streams and interruption observer methods)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [16.1](requirements.md#16.1)

- [x] 3. Add PipelineEstimator protocol and Pipeline conformance <!-- id:7pbwp45 -->
  - Create MedataCore/Sources/Pipeline/PipelineEstimator.swift
  - Declare public protocol PipelineEstimator: Sendable with single func estimate(captureResult: CaptureResult) async throws -> MealRecord
  - Add extension Pipeline: PipelineEstimator {} (empty — Pipeline.estimate signature already matches)
  - Per Decision 13: protocol lives in MedataCore not App/
  - Exempt from TDD pairing — pure interface declaration
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1), [9.1](requirements.md#9.1), [10.1](requirements.md#10.1)

- [x] 4. Port brand assets icon.svg and favicon.ico from main branch <!-- id:7pbwp46 -->
  - git checkout main -- static/icon.svg static/favicon.ico
  - Verify the icon.svg stroke colour is #63ff00 (consumed by tasks 5 and 25)
  - Commit alongside other UI-spec work
  - Per Decision 7
  - Exempt from TDD — asset copy
  - Stream: 2
  - Requirements: [15.2](requirements.md#15.2)

## UI building blocks

- [x] 5. Add App/Colors.swift with brand colour tokens <!-- id:7pbwp47 -->
  - extension Color { static let medataAccent = Color(red: 0x63/255, green: 0xFF/255, blue: 0x00/255); static let confidenceHigh = medataAccent; static let confidenceModerate = Color.orange; static let confidenceLow = Color.red }
  - Exempt from TDD — colour constants
  - Blocked-by: 7pbwp46 (Port brand assets icon.svg and favicon.ico from main branch)
  - Stream: 1
  - Requirements: [15.1](requirements.md#15.1), [9.2](requirements.md#9.2)

- [x] 6. Add App/GatingSnapshot.swift struct <!-- id:7pbwp48 -->
  - struct GatingSnapshot: Equatable, Sendable with pathHint, tiltInRange, distanceCm, lidarCoveragePercent fields
  - Include withPath(_ newPath: CapturePath) -> GatingSnapshot helper
  - Per design.md state-machine section
  - Exempt from TDD — type definition
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [7.2](requirements.md#7.2)

- [x] 7. Add App/CaptureState.swift enum and PermissionSubject + CaptureStage sub-enums <!-- id:7pbwp49 -->
  - Define the 8 cases of CaptureState per design.md (initialising, permissionDenied(.camera|.motion), trackingLost, ready, capturing(stage, frozen), estimating(captureResult), showingResult(MealRecord), refused(EstimationFailure, retryStage)). **Note:** the original `.forcingTwoView` case was removed per Decision 35 (the `captureMode` toggle is authoritative; no auto-derivation), leaving 8 cases.
  - Conform to Equatable
  - Define PermissionSubject and CaptureStage sub-enums
  - Exempt from TDD — type definitions
  - Blocked-by: 7pbwp48 (Add App/GatingSnapshot.swift struct)
  - Stream: 1
  - Requirements: [1.6](requirements.md#1.6), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [13.3](requirements.md#13.3), [16.1](requirements.md#16.1)

- [x] 8. Write tests for CapturePathDecider boundary table (deferred `AUTO_CAPTURE_MODE` path) <!-- id:7pbwp4a -->
  - **Note:** `CapturePathDecider` is compiled out behind `#if AUTO_CAPTURE_MODE` (research Req 3.9 / Decision 35) and is not the v1 active path — the `captureMode` toggle is authoritative. These tests cover the dormant deferred logic.
  - MeData/Tests/CapturePathDeciderTests.swift
  - Table rows: (supportsLiDAR: false, coverage: 100, expected: .twoViewSfs), (true, 0, .twoViewSfs), (true, 79.99, .twoViewSfs), (true, 80, .singleViewLidar), (true, 100, .singleViewLidar)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1)

- [x] 9. Implement App/CapturePathDecider.swift (behind `#if AUTO_CAPTURE_MODE`) <!-- id:7pbwp4b -->
  - The whole file is wrapped in `#if AUTO_CAPTURE_MODE` — dormant in v1 (research Req 3.9 / Decision 35).
  - enum CapturePathDecider { static func decide(supportsLiDAR: Bool, latestCoveragePercent: Float) -> CapturePath { supportsLiDAR && latestCoveragePercent >= 80 ? .singleViewLidar : .twoViewSfs } }
  - Make the tests from task 8 pass
  - Blocked-by: 7pbwp4a (Write tests for CapturePathDecider boundary table)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1)

- [x] 10. Add App/LiveIndicatorModel.swift child @Observable <!-- id:7pbwp4c -->
  - @Observable @MainActor final class LiveIndicatorModel with liveTiltDegrees: Float, liveDistanceCm: Float?, liveLiDARCoveragePercent: Float
  - Per design.md — split from CaptureFlowModel to bound CaptureFlowView body redraws against the 60Hz frame stream
  - Exempt from TDD — observable holder, no logic
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [3.1](requirements.md#3.1), [4.1](requirements.md#4.1)

- [x] 11. Add App/ShareSheet.swift UIViewControllerRepresentable wrapper <!-- id:7pbwp4d -->
  - struct ShareSheet: UIViewControllerRepresentable wrapping UIActivityViewController(activityItems:applicationActivities: nil)
  - Exempt from TDD — straight UIKit-bridge boilerplate
  - Stream: 1
  - Requirements: [11.4](requirements.md#11.4)

## UI components

- [x] 12. Write tests for CaptureFlowModel state-machine transitions <!-- id:7pbwp4e -->
  - MeData/Tests/CaptureFlowModelTests.swift
  - MockCaptureSession returning canned RawFrame; MockPipeline conforming to PipelineEstimator with programmable Result<MealRecord, Error>
  - One test per transition row from design.md state-machine table (~18 rows)
  - Include path-hint freeze rule test (snapshot A at tap, change coverage, assert frozen snapshot is A)
  - Include rapid-shutter ignored case (§7.4)
  - Include backgrounding cancels in-flight Task and resets state to .initialising (§8.3, best-effort per Decision 12)
  - Include permission-denied init (stubbed AVCaptureDevice.authorizationStatus(for:) returning .denied)
  - Include AR interruption .began → .trackingLost + .ended → .initialising
  - Blocked-by: 7pbwp44 (Implement ARKitCaptureEngine accessors arSession, frames, interruptions plus ARSessionObserver interruption methods), 7pbwp45 (Add PipelineEstimator protocol and Pipeline conformance), 7pbwp48 (Add App/GatingSnapshot.swift struct), 7pbwp49 (Add App/CaptureState.swift enum and PermissionSubject + CaptureStage sub-enums), 7pbwp4c (Add App/LiveIndicatorModel.swift child @Observable)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.6](requirements.md#1.6), [2.4](requirements.md#2.4), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [9.1](requirements.md#9.1), [9.4](requirements.md#9.4), [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [13.1](requirements.md#13.1), [13.2](requirements.md#13.2), [13.3](requirements.md#13.3), [14.3](requirements.md#14.3), [16.1](requirements.md#16.1)

- [x] 13. Implement App/CaptureFlowModel.swift orchestrator <!-- id:7pbwp4f -->
  - @Observable @MainActor final class CaptureFlowModel conforming to CaptureFlowDelegate
  - Holds CaptureSession, any PipelineEstimator, LiveIndicatorModel
  - Implements full state machine per design.md transition table
  - Path-hint freeze on shutter tap (synchronous state write before any await)
  - Wraps Pipeline.estimate in a Task stored on self for cancelInFlight()
  - Iterates engine.interruptions for the model's lifetime
  - Re-checks AVCaptureDevice.authorizationStatus on scenePhase == .active
  - didUpdateTilt / didUpdateLiDARCoverage / didDetectInterClassOcclusion are no-op conformances (Decisions 9, 11)
  - Make the tests from task 12 pass
  - Blocked-by: 7pbwp4e (Write tests for CaptureFlowModel state-machine transitions)
  - Stream: 1
  - Requirements: [1.6](requirements.md#1.6), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [5.1](requirements.md#5.1), [5.3](requirements.md#5.3), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [13.3](requirements.md#13.3), [14.3](requirements.md#14.3), [16.1](requirements.md#16.1)

- [x] 14. Write tests for LiveSampleObserver per-frame computation and write-gating <!-- id:7pbwp4g -->
  - MeData/Tests/LiveSampleObserverTests.swift
  - Synthesise CVPixelBuffer depth/confidence fixtures (reuse CaptureKitTests fixtures)
  - Assert tilt from frame.camera.transform gravity-aligned column
  - Assert distance = median of centre-crop depth in cm; nil when sceneDepth absent
  - Assert LiDAR coverage = fraction of pixels with confidence >= τ_conf=0.66, ×100
  - Assert write-gating: while CaptureFlowModel.state is not .ready, frame writes are dropped (no flicker) (`.forcingTwoView` removed per Decision 35)
  - Blocked-by: 7pbwp44 (Implement ARKitCaptureEngine accessors arSession, frames, interruptions plus ARSessionObserver interruption methods), 7pbwp4c (Add App/LiveIndicatorModel.swift child @Observable)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [4.1](requirements.md#4.1)

- [x] 15. Implement App/LiveSampleObserver.swift <!-- id:7pbwp4h -->
  - @MainActor final class LiveSampleObserver
  - Iterates engine.frames AsyncStream
  - Writes to LiveIndicatorModel only when CaptureFlowModel.state is .ready (`.forcingTwoView` removed per Decision 35)
  - Started/cancelled by CaptureFlowModel based on state observation
  - Make the tests from task 14 pass
  - Blocked-by: 7pbwp4g (Write tests for LiveSampleObserver per-frame computation and write-gating)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [4.1](requirements.md#4.1)

- [x] 16. Write tests for ARPreviewView delegate-reassertion guard <!-- id:7pbwp4i -->
  - MeData/Tests/ARPreviewViewTests.swift
  - After ARPreviewView.makeUIView creates ARView with engine.arSession, assert engine.session.delegate === engine
  - After forcing updateUIView invocation, assert engine.session.delegate === engine still
  - Both lifecycle points must re-assert (per design.md — RealityKit reassigns the delegate at either point historically)
  - Blocked-by: 7pbwp44 (Implement ARKitCaptureEngine accessors arSession, frames, interruptions plus ARSessionObserver interruption methods)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1)

- [x] 17. Implement App/ARPreviewView.swift UIViewRepresentable <!-- id:7pbwp4j -->
  - struct ARPreviewView: UIViewRepresentable wrapping ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
  - makeUIView: assign arView.session = engine.arSession then re-assert engine.session.delegate = engine
  - updateUIView: re-assert engine.session.delegate = engine (idempotent property write)
  - Make the tests from task 16 pass
  - Blocked-by: 7pbwp4i (Write tests for ARPreviewView delegate-reassertion guard)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1)

- [x] 18. Implement App/RefusalBanner.swift overlay view <!-- id:7pbwp4k -->
  - struct RefusalBanner: View taking EstimationFailure and a retry closure
  - Sits in .overlay(alignment: .top) on CaptureFlowView
  - .allowsHitTesting(true) on banner ZStack; only Try Again control clears it (no tap-outside dismiss per Decision 5)
  - Renders failure.localisedMessage verbatim (per requirements §12.2)
  - Exempt from TDD — visual composition; refusal flow integration tested in task 26
  - Blocked-by: 7pbwp47 (Add App/Colors.swift with brand colour tokens)
  - Stream: 1
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [12.2](requirements.md#12.2)

- [x] 19. Implement App/LiveIndicatorView.swift child view <!-- id:7pbwp4l -->
  - struct LiveIndicatorView: View taking LiveIndicatorModel via @Bindable
  - Renders tilt indicator (in-range visually distinct), distance state (measured cm or 30-40cm guidance), LiDAR coverage gauge, capture-path indicator label
  - Surface gating-mode-active hint per §3.3
  - Exempt from TDD — visual composition; behaviour tested via CaptureFlowModel tests
  - Blocked-by: 7pbwp47 (Add App/Colors.swift with brand colour tokens), 7pbwp4c (Add App/LiveIndicatorModel.swift child @Observable)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1)

- [x] 20. Write tests for ResultView confidence pill thresholds <!-- id:7pbwp4m -->
  - **Superseded by tasks 58 & 60** (Decision 17): the pill is now four-tier and the retake prompt fires at σ < 0.20, not σ < 0.60. The three-tier thresholds below are the original v1.0 content.
  - MeData/Tests/ResultViewTests.swift
  - Table over σ_meal ∈ {0.0, 0.59, 0.60, 0.74, 0.75, 1.0} → expected pill label (Low / Low / Moderate / Moderate / High / High)
  - Assert uncertain-prompt visibility when σ < 0.60
  - Assert per-class breakdown and clinical-macros absent (Decision 3, §9.5)
  - Snapshot or ViewInspector style assertion
  - Stream: 1
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.5](requirements.md#9.5)

- [x] 21. Rewrite App/ResultView.swift <!-- id:7pbwp4n -->
  - **Superseded by tasks 58 & 60** (Decision 17): four-tier pill; retake prompt at σ < 0.20.
  - Display total carbs in grams rounded to nearest 1g (Int(record.macros.totalCarbsG.rounded()))
  - Three-state confidence pill keyed off record.confidence.sigmaMeal *(now four-tier — task 58)*
  - Uncertain-estimate prompt with Retake control when σ < 0.60 *(now σ < 0.20 — task 60)*
  - New-capture control that pops the result view
  - No per-class breakdown, no clinical macros
  - Make the tests from task 20 pass
  - Blocked-by: 7pbwp47 (Add App/Colors.swift with brand colour tokens), 7pbwp4m (Write tests for ResultView confidence pill thresholds)
  - Stream: 1
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4), [9.5](requirements.md#9.5), [12.1](requirements.md#12.1)

- [x] 22. Extend App/SettingsView.swift with Export archive control <!-- id:7pbwp4o -->
  - **Note:** the retention-period picker and IFCDB toggle were since **removed** (research §0 / Decision 39, research task 74). The live settings are the `captureMode` toggle (Decision 35) plus the Export archive control below.
  - Add Export archive button that calls PersistenceStore.exportArchive() async throws -> URL
  - Present the produced file via .sheet(item:) hosting ShareSheet
  - Exempt from TDD — UI plumbing; archive functionality covered by Persistence tests in research spec
  - Blocked-by: 7pbwp4d (Add App/ShareSheet.swift UIViewControllerRepresentable wrapper)
  - Stream: 1
  - Requirements: [11.1](requirements.md#11.1), [11.2](requirements.md#11.2), [11.3](requirements.md#11.3), [11.4](requirements.md#11.4)

- [x] 23. Rewrite App/CaptureFlowView.swift root view <!-- id:7pbwp4p -->
  - NavigationStack(path: $model.navigationPath)
  - Composes ARPreviewView (preview), LiveIndicatorView (indicators), RefusalBanner (overlay), shutter button, settings navigation
  - .navigationDestination(for: MealRecord.self) { ResultView(record: $0) }
  - Shutter enabled only when state is .ready, snapshot.tiltInRange, distance gate OK, no in-flight estimation (§7.2)
  - Permission-denied view branch with Settings deep-link (§1.3)
  - Exempt from TDD — view composition; behaviour tested via CaptureFlowModel and XCUITests
  - Blocked-by: 7pbwp4f (Implement App/CaptureFlowModel.swift orchestrator), 7pbwp4h (Implement App/LiveSampleObserver.swift), 7pbwp4j (Implement App/ARPreviewView.swift UIViewRepresentable), 7pbwp4k (Implement App/RefusalBanner.swift overlay view), 7pbwp4l (Implement App/LiveIndicatorView.swift child view), 7pbwp4n (Rewrite App/ResultView.swift), 7pbwp4o (Extend App/SettingsView.swift with Export archive control)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [9.4](requirements.md#9.4)

- [x] 24. Update App/App.swift for scenePhase forwarding to CaptureFlowModel <!-- id:7pbwp4q -->
  - @State private var model = CaptureFlowModel(...)
  - @Environment(\.scenePhase) and .onChange forwarding .active/.background/.inactive to model.scenePhaseChanged(_:)
  - .tint(.medataAccent) on the root view per §15.1
  - Exempt from TDD — wiring; lifecycle covered by task 12 backgrounding test
  - Blocked-by: 7pbwp47 (Add App/Colors.swift with brand colour tokens), 7pbwp4f (Implement App/CaptureFlowModel.swift orchestrator), 7pbwp4p (Rewrite App/CaptureFlowView.swift root view)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [8.3](requirements.md#8.3), [15.1](requirements.md#15.1)

## Asset generation

- [x] 25. Write SVG-to-PNG AppIcon generation script <!-- id:7pbwp4r -->
  - Create tools/appicon/generate.sh
  - Use rsvg-convert (preferred) or sips to render static/icon.svg at all Apple-required sizes: 40, 58, 60, 80, 87, 120, 180, 1024 pixels square
  - Write each to MeData/MeData/Assets.xcassets/AppIcon.appiconset/icon-{size}.png
  - Generate matching Contents.json entries
  - Run once and commit the generated PNGs alongside the script
  - Exempt from TDD — build tooling; manual verification by opening Xcode and viewing the icon set
  - Blocked-by: 7pbwp46 (Port brand assets icon.svg and favicon.ico from main branch)
  - Stream: 2
  - Requirements: [15.2](requirements.md#15.2)

## End-to-end verification

- [x] 26. Write XCUITest for refusal flow <!-- id:7pbwp4s -->
  - MeData/UITests/RefusalFlowUITests.swift
  - Inject fixture that trips EstimationFailure.noScaleAvailable
  - Assert refusal banner appears with the localised Irish-English message
  - Tap Try Again
  - Assert banner dismisses and state returns to .capturing at the right stage
  - Blocked-by: 7pbwp4p (Rewrite App/CaptureFlowView.swift root view), 7pbwp4q (Update App/App.swift for scenePhase forwarding to CaptureFlowModel)
  - Stream: 1
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [12.1](requirements.md#12.1), [12.2](requirements.md#12.2)

- [x] 27. Write XCUITest for backgrounding behaviour (best-effort §8.3) <!-- id:7pbwp4t -->
  - MeData/UITests/BackgroundingUITests.swift
  - Tap shutter to enter .estimating
  - XCUIDevice.shared.press(.home)
  - Foreground the app
  - Assert UI is in .initialising (capture-flow main view)
  - Note: per Decision 12, a MealRecord may exist in the persistent store — this test asserts UI state only
  - Blocked-by: 7pbwp4p (Rewrite App/CaptureFlowView.swift root view), 7pbwp4q (Update App/App.swift for scenePhase forwarding to CaptureFlowModel)
  - Stream: 1
  - Requirements: [8.3](requirements.md#8.3)

- [x] 28. Write XCUITest for AR interruption recovery <!-- id:7pbwp4u -->
  - MeData/UITests/InterruptionUITests.swift
  - Simulate ARSession sessionWasInterrupted via a test helper that emits .began on engine.interruptions stream
  - Assert state transitions to .trackingLost (UI shows tracking-lost banner)
  - Emit .ended
  - Assert engine.start() re-called and state returns to .initialising
  - Blocked-by: 7pbwp4p (Rewrite App/CaptureFlowView.swift root view), 7pbwp4q (Update App/App.swift for scenePhase forwarding to CaptureFlowModel)
  - Stream: 1
  - Requirements: [16.1](requirements.md#16.1)

## v1.1 — Tab navigation + Meals tab

- [x] 29. Write tests for additive PersistenceStore methods (allMeals, deleteMeal, eventsDidChange) <!-- id:7pbwp4v -->
  - `allMeals()` returns `event_type = meal` rows from the `events` table sorted by `createdAt` desc; `segmenterSource` (research task 82) is read from the `MealRecord` inside the event `metadata` JSON, not a SQL column (see event-log-schema spec).
  - `deleteMeal(id:)` removes the event row, removes the per-meal artefact directory, and DOES NOT call any `PHPhotoLibrary` API.
  - `eventsDidChange` yields a tick after `save` and after `deleteMeal`. Two subscribers both receive the tick (per-subscriber stream).
  - Mock the artefact-directory FileManager calls; use an in-memory GRDB queue.
  - Stream: 2
  - Requirements: [19.1](requirements.md#19.1), [19.6](requirements.md#19.6), [19.7](requirements.md#19.7)

- [x] 30. Implement PersistenceStore.allMeals / deleteMeal / eventsDidChange in GRDBPersistenceStore <!-- id:7pbwp4w -->
  - Add three methods to the `PersistenceStore` protocol and implement them on `GRDBPersistenceStore`.
  - `eventsDidChange` uses per-subscriber `AsyncStream<Void>` with `BufferingPolicy.bufferingNewest(1)`; emit on every successful write.
  - Artefact directory cleanup is best-effort: log and continue if a file is already gone.
  - Decision: 15
  - Blocked-by: 7pbwp4v (Write tests for additive PersistenceStore methods (allMeals, deleteMeal, eventsDidChange))
  - Stream: 2
  - Requirements: [19.1](requirements.md#19.1), [19.6](requirements.md#19.6), [19.7](requirements.md#19.7)

- [x] 31. Write tests for MealHistoryModel <!-- id:7pbwp4x -->
  - Initial `start()` loads `meals` from a fake store; subsequent `eventsDidChange` tick triggers a reload.
  - `delete(_:)` calls `store.deleteMeal(id:)`; the resulting `eventsDidChange` tick refreshes `meals`.
  - Cancelling the model's subscription task removes the subscription without leaking the continuation.
  - Stream: 2
  - Requirements: [19.1](requirements.md#19.1), [19.6](requirements.md#19.6), [19.7](requirements.md#19.7)

- [x] 32. Implement MealHistoryModel <!-- id:7pbwp4y -->
  - `@Observable @MainActor final class MealHistoryModel` in `App/MealHistoryModel.swift`. See `specs/ui/design.md` §"Meals tab" for the sketch.
  - Subscription `Task` cancelled in `deinit` (use a `cancellable` reference).
  - Blocked-by: 7pbwp4w (Implement PersistenceStore.allMeals / deleteMeal / eventsDidChange in GRDBPersistenceStore), 7pbwp4x (Write tests for MealHistoryModel)
  - Stream: 2
  - Requirements: [19.1](requirements.md#19.1), [19.6](requirements.md#19.6)

- [x] 33. Write tests for MealRow rendering <!-- id:7pbwp4z -->
  - Placeholder chip is present when `record.segmenterSource == "dev_stub"` and absent otherwise (assert via accessibility identifier visibility).
  - Confidence pill matches `ResultView`'s confidence thresholds (four-tier per Decision 17 / task 58; reuse the `ConfidencePill` component extracted in task 36).
  - Photo-denied fallback renders the `photo.fill` SF Symbol when `PHImageManager.requestImage` returns nil.
  - Timestamp formatter matches `dd MMM yyyy, HH:mm` in `en_IE` locale.
  - Stream: 2
  - Requirements: [19.2](requirements.md#19.2), [19.3](requirements.md#19.3)

- [x] 34. Implement MealRow view <!-- id:7pbwp50 -->
  - `App/MealRow.swift`. Uses `PHImageManager.default().requestImage(for:targetSize:contentMode:options:resultHandler:)` for the thumbnail.
  - The placeholder chip uses the same yellow background colour token as the result-view placeholder banner from research task 83.
  - Blocked-by: 7pbwp4z (Write tests for MealRow rendering), 7pbwp52 (Add ResultPresentation parameter to ResultView; extract shared ConfidencePill)
  - Stream: 2
  - Requirements: [19.2](requirements.md#19.2), [19.3](requirements.md#19.3)

- [x] 35. Write tests for ResultView presentation mode (justCaptured vs historyDetail) <!-- id:7pbwp51 -->
  - `mode = .justCaptured` shows the "New capture" button; `mode = .historyDetail` hides it.
  - Both modes show the carb total, confidence pill, thumbnail, and (where applicable) placeholder banner.
  - Stream: 2
  - Requirements: [19.4](requirements.md#19.4)

- [x] 36. Add ResultPresentation parameter to ResultView; extract shared ConfidencePill <!-- id:7pbwp52 -->
  - Add `enum ResultPresentation { case justCaptured, historyDetail }` and a `mode: ResultPresentation` field to `ResultView`.
  - Extract `ConfidencePill(sigmaMeal:)` into a small shared component so `MealRow` can reuse the same rendering.
  - Existing Photo-tab call site passes `.justCaptured`; new Meals-tab call site (task 37) passes `.historyDetail`.
  - Blocked-by: 7pbwp51 (Write tests for ResultView presentation mode (justCaptured vs historyDetail))
  - Stream: 2
  - Requirements: [19.4](requirements.md#19.4)

- [x] 37. Implement MealsTabView (list, empty state, swipe delete, navigation destination) <!-- id:7pbwp53 -->
  - `App/MealsTabView.swift` wraps `MealListView` in its own `NavigationStack` with `.navigationDestination(for: MealRecord.self) { ResultView(record: $0, mode: .historyDetail) }`.
  - `App/MealListView.swift` is a `List(model.meals) { MealRow(record: $0) }` with `swipeActions(edge: .trailing)` providing a single Delete action wired to `await model.delete(record)`.
  - Empty state: when `model.meals.isEmpty`, render the Irish-English copy and `fork.knife` SF Symbol per Req §19.5 in place of the list.
  - No `.searchable`, no `EditButton`, no selection binding (Req §19.8).
  - Blocked-by: 7pbwp4y (Implement MealHistoryModel), 7pbwp50 (Implement MealRow view), 7pbwp52 (Add ResultPresentation parameter to ResultView; extract shared ConfidencePill)
  - Stream: 2
  - Requirements: [19.1](requirements.md#19.1), [19.4](requirements.md#19.4), [19.5](requirements.md#19.5), [19.7](requirements.md#19.7), [19.8](requirements.md#19.8)

- [x] 38. Write tests for CaptureFlowModel.tabSelectionChanged <!-- id:7pbwp54 -->
  - Switching away from `.photo` while state is `.ready` releases the engine within 200 ms and resets to `.initialising` on Photo re-entry.
  - Switching away during `.estimating` DOES NOT cancel the pipeline; on Photo re-entry the state is `.showingResult(record)` once the pipeline completes.
  - Switching to a non-photo tab while state is already `.refused` or `.permissionDenied` is a no-op.
  - Stream: 2
  - Requirements: [1.7](requirements.md#1.7), [18.7](requirements.md#18.7)

- [x] 39. Add tabSelectionChanged(to:) method to CaptureFlowModel <!-- id:7pbwp55 -->
  - Mirrors `scenePhaseChanged(.background)` for non-Photo tabs except: when state is `.estimating`, let the in-flight `Pipeline.estimate(_:mode:)` complete and route the result to `.showingResult(record)` for next Photo re-entry.
  - Decision: 15
  - Blocked-by: 7pbwp54 (Write tests for CaptureFlowModel.tabSelectionChanged)
  - Stream: 2
  - Requirements: [1.7](requirements.md#1.7), [18.7](requirements.md#18.7)

- [x] 40. Implement AppRoot TabView + wire from App.swift; add NSPhotoLibraryUsageDescription <!-- id:7pbwp56 -->
  - Create `App/AppRoot.swift` per design §"Tab shell (`AppRoot`)".
  - `MedataApp.body` returns `AppRoot(engine:, store:)` instead of the v1.0 direct `CaptureFlowView` presentation.
  - Add `NSPhotoLibraryUsageDescription` Info.plist string in Irish-English ("MeData reads thumbnails of your captured meal photos to show them in your meal history.").
  - Do NOT set a custom tab-bar appearance — the system Liquid Glass material on iOS 26.5 is required (Req §18.4).
  - Decision: 15
  - Blocked-by: 7pbwp53 (Implement MealsTabView (list, empty state, swipe delete, navigation destination)), 7pbwp55 (Add tabSelectionChanged(to:) method to CaptureFlowModel)
  - Stream: 2
  - Requirements: [18.1](requirements.md#18.1), [18.2](requirements.md#18.2), [18.3](requirements.md#18.3), [18.4](requirements.md#18.4), [18.6](requirements.md#18.6)

- [x] 41. Write XCUITest suite for v1.1 (tab persistence, re-tap pop, empty state, new-meal within 500 ms) <!-- id:7pbwp57 -->
  - Tab persistence: launch, switch to Meals, terminate, relaunch — Meals is selected.
  - Re-tap pop-to-root: Meals → tap row → detail visible → re-tap Meals tab item → list visible.
  - Empty state: launch on a fresh container → switch to Meals → empty-state copy and icon visible.
  - New-meal-within-500-ms: with the UITestHarness, drive a successful capture from the Photo tab; while on Meals, assert the new row appears within 500 ms of `eventsDidChange` emitting.
  - Each XCUITest resets `@AppStorage("selectedTab")` via a launch argument.
  - Blocked-by: 7pbwp56 (Implement AppRoot TabView + wire from App.swift; add NSPhotoLibraryUsageDescription)
  - Stream: 2
  - Requirements: [18.5](requirements.md#18.5), [18.6](requirements.md#18.6), [19.5](requirements.md#19.5), [19.6](requirements.md#19.6)

## v1.1 — Visual design

- [x] 42. Add Color tokens to App/Colors.swift per design-system/MASTER.md <!-- id:7pbwp58 -->
  - Add token names (`captureBackground`, `captureChromeText`, `captureChromeBG`, `captureScrim`, `surfacePrimary`, `surfaceElevated`, `placeholderBG`, `placeholderFG`) per `design-system/MASTER.md` §"Colour tokens".
  - Confidence pill colours move from inline values into named tokens (`confidenceHigh`, `confidenceModerate`, `confidenceLow`).
  - Tests: a snapshot test verifies hex resolution under both light and dark mode for tokens that adapt; a static test asserts `medataAccent.cgColor` equals `#63FF00`.
  - Decision: 16
  - Stream: 2
  - Requirements: [20.1](requirements.md#20.1), [20.2](requirements.md#20.2)

- [x] 43. Implement ConfidencePill shared view (icon + label + value) <!-- id:7pbwp59 -->
  - **Extended to four tiers by task 58** (Decision 17): a `.veryLow` tier (σ < 0.20) was added below "Low". The three-tier rendering below is the original v1.0 content.
  - Extract `App/ConfidencePill.swift` consumed by `ResultView` and `MealRow`.
  - Three-tier rendering: `checkmark.seal.fill` + "High" for σ ≥ 0.75; `exclamationmark.triangle.fill` + "Moderate" for 0.60 ≤ σ < 0.75; `xmark.octagon.fill` + "Low" for σ < 0.60. Icon satisfies the `color-not-only` accessibility rule.
  - Body: pill (capsule shape), 28pt tall, `padding(.horizontal, 12)`, semibold body text.
  - Tests: σ ∈ {0.0, 0.59, 0.60, 0.74, 0.75, 1.0} → expected (icon, label, background). Reuses the existing threshold-test fixture from task 20.
  - Blocked-by: 7pbwp58 (Add Color tokens to App/Colors.swift per design-system/MASTER.md)
  - Stream: 2
  - Requirements: [20.8](requirements.md#20.8)

- [x] 44. Write tests for LiveIndicatorBadge (consolidated chip, auto-hide, re-show on tap or out-of-range) <!-- id:7pbwp5a -->
  - Initial render shows all three sub-elements (tilt, distance, LiDAR coverage) when `supportsLiDAR`; omits the latter two when not.
  - After 5 s of in-range `.ready` state, the chip fades to opacity 0.0 (still hit-testable via 48pt `hitSlop`).
  - Tap on the hidden chip re-shows it; an out-of-range tilt write also re-shows it.
  - Sub-element tint is green when its value is in-range, white otherwise.
  - Reduced-motion: the 5 s auto-hide becomes a snap-to-opacity-0 with no fade.
  - Stream: 2
  - Requirements: [20.4](requirements.md#20.4)

- [x] 45. Implement LiveIndicatorBadge; supersede LiveIndicatorView <!-- id:7pbwp5b -->
  - Create `App/LiveIndicatorBadge.swift` consuming `LiveIndicatorModel`.
  - Layout per `design-system/pages/photo-tab.md` §"Indicator badge": single chip with three sub-elements separated by an 8pt hairline.
  - Auto-hide via `Task.sleep(5_000_000_000)` started when state enters `.ready` and all values in-range; cancelled on any out-of-range write or tap.
  - Delete `App/LiveIndicatorView.swift` and remove its references from `CaptureFlowView`.
  - Decision: 16
  - Blocked-by: 7pbwp5a (Write tests for LiveIndicatorBadge (consolidated chip, auto-hide, re-show on tap or out-of-range))
  - Stream: 2
  - Requirements: [20.3](requirements.md#20.3), [20.4](requirements.md#20.4)

- [x] 46. Implement CaptureTopBar (close + flash/torch) <!-- id:7pbwp5c -->
  - Create `App/CaptureTopBar.swift` per `design-system/pages/photo-tab.md` §"Top chrome".
  - Close (`xmark`) button: SF Symbol, 24pt, white, in a 40pt `captureChromeBG` capsule. Action: pop the navigation stack if any view is presented above the capture view; otherwise no-op.
  - Flash/torch toggle: SF Symbol `bolt.fill` / `bolt.slash.fill`, same capsule. Bound to `AVCaptureDevice.torchMode`. Hidden when the AR session is off or the device has no torch.
  - Tests: close action behaviour with and without a presented sheet; torch toggle updates `AVCaptureDevice.torchMode`; both buttons announce VoiceOver labels in Irish-English.
  - Stream: 2
  - Requirements: [20.3](requirements.md#20.3)

- [x] 47. Rewrite CaptureModeToggle as capsule pill <!-- id:7pbwp5d -->
  - Replace the v1.0 segmented control rendering with the pill design per `design-system/pages/photo-tab.md` §"Capture-mode pill".
  - Animated inner accent pill slides between Single and Double positions with spring `.bouncy(duration: 0.2)`.
  - Same `@AppStorage(SettingsKeys.captureMode)` binding (the namespaced key, not a bare `"captureMode"` literal — see single-mode-toggle-key-mismatch bugfix); no model changes.
  - Disabled state for "Single" when `!supportsLiDAR`: label opacity 0.4, tap emits the existing Irish-English no-LiDAR refusal.
  - Tests: tap toggles UserDefaults; disabled-Single tap emits refusal; reduced-motion replaces the slide with a crossfade.
  - Stream: 2
  - Requirements: [20.3](requirements.md#20.3), [20.5](requirements.md#20.5)

- [x] 48. Implement ShutterButton (76pt circle, press feedback) <!-- id:7pbwp5e -->
  - Extract shutter rendering out of `CaptureFlowView` into `App/ShutterButton.swift`.
  - 76pt outer ring (4pt stroke white) + 60pt inner fill (white). On press: inner shrinks to 52pt + ring widens to 6pt over 100ms; on release: spring back over 150ms `.snappy`.
  - Position: horizontally centred, ≥24pt above the tab bar top edge + safe area bottom.
  - Disabled state: inner opacity 0.4, non-interactive.
  - Accessibility: `accessibilityLabel("Capture meal")`, `accessibilityHint("Double-tap to take a photo")`, `accessibilityValue` differs per state (Ready / Capturing / Disabled).
  - Tests: press-feedback timing under reduced-motion; layout never shifts surrounding chrome during the animation.
  - Stream: 2
  - Requirements: [20.3](requirements.md#20.3), [20.6](requirements.md#20.6), [20.10](requirements.md#20.10)

- [x] 49. Replace RefusalBanner with RefusalSheet bottom sheet <!-- id:7pbwp5f -->
  - Create `App/RefusalSheet.swift` per `design-system/pages/photo-tab.md` §"Refusal banner". Bottom sheet via `.sheet(item: $model.refusal)` with `.presentationDetents([.fraction(0.35)])` and `.presentationDragIndicator(.visible)`.
  - Content: SF Symbol matching the failure, large title (Irish-English), one-line copy, single "Try again" primary CTA.
  - Dismiss by swipe-down or "Try again" tap → `state = .capturing(retryStage, ...)`.
  - Delete `App/RefusalBanner.swift` and its references in `CaptureFlowView`.
  - Tests: each `EstimationFailure` case maps to a distinct symbol + copy; "Try again" returns to the right `retryStage`; swipe-down dismisses without state change.
  - Decision: 16
  - Stream: 2
  - Requirements: [20.7](requirements.md#20.7)

- [x] 50. Restyle ResultView to display-scale carb total + dimmed photo background <!-- id:7pbwp5g -->
  - Layout per `design-system/pages/photo-tab.md` §"ResultView": full-bleed photo (via `PHImageManager`, dimmed by the top/bottom black-to-transparent scrim), centred carb total at 72pt heavy monospaced (`Color.captureChromeText`), confidence pill below, placeholder chip below that when `segmenterSource == "dev_stub"`.
  - `.contentTransition(.numericText())` on the carb total; falls back to snap-in under reduced motion.
  - Dynamic Type clamp at AX5: maximum display size 88pt to prevent overflow.
  - Action row (`Retake` outline + `Done` solid) hidden in `mode == .historyDetail` (per task 36).
  - Tests: numeric transition under reduced-motion; carb total clamps at AX5; placeholder chip presence/absence matches `segmenterSource`.
  - Blocked-by: 7pbwp58 (Add Color tokens to App/Colors.swift per design-system/MASTER.md), 7pbwp59 (Implement ConfidencePill shared view (icon + label + value)), 7pbwp52 (Add ResultPresentation parameter to ResultView; extract shared ConfidencePill)
  - Stream: 2
  - Requirements: [20.2](requirements.md#20.2), [20.8](requirements.md#20.8), [20.11](requirements.md#20.11), [20.12](requirements.md#20.12)

- [x] 51. Restyle MealRow to feed-style layout <!-- id:7pbwp5h -->
  - Replace the v1.1 compact row layout with the feed-style layout per `design-system/pages/meals-tab.md` §"`MealRow`": full-width 4:3 photo with `.clipShape(RoundedRectangle(cornerRadius: 14))`, then caption row (carb total at 24pt heavy mono + ConfidencePill + optional placeholder chip), then timestamp.
  - 24pt gap between rows; `.listStyle(.plain)` on the parent List.
  - Thumbnail target size = 2× row width, NOT `PHImageManagerMaximumSize`.
  - Whole row is the navigation tap target; press feedback `.scale(0.98)` 100ms.
  - Tests: photo aspect ratio is 4:3 for every row regardless of source asset shape; carb-total digits don't shift width on scroll-in (monospaced-digit); placeholder chip presence matches `segmenterSource`.
  - Blocked-by: 7pbwp58 (Add Color tokens to App/Colors.swift per design-system/MASTER.md), 7pbwp59 (Implement ConfidencePill shared view (icon + label + value)), 7pbwp50 (Implement MealRow view)
  - Stream: 2
  - Requirements: [20.9](requirements.md#20.9), [20.10](requirements.md#20.10)

- [x] 52. Wire CaptureFlowView to the new chrome (CaptureTopBar, LiveIndicatorBadge, ShutterButton, RefusalSheet, restyled CaptureModeToggle) <!-- id:7pbwp5i -->
  - Compose the new components into `App/CaptureFlowView.swift`. Black background, ARPreviewView full-bleed, top chrome via safe area, indicator badge via top-center overlay, capture-mode pill + shutter via bottom overlay.
  - Refusal: `.sheet(item: $model.refusal) { failure in RefusalSheet(failure: failure, retry: { model.retry() }) }`.
  - Delete dead references to `LiveIndicatorView` and `RefusalBanner`.
  - Tests: XCUITest covers the close button, flash toggle, mode-pill switch, shutter armed state, refusal-sheet present/dismiss; existing v1.0 XCUITest for refusal copy is rewritten to expect the sheet, not the banner.
  - Blocked-by: 7pbwp58 (Add Color tokens to App/Colors.swift per design-system/MASTER.md), 7pbwp5b (Implement LiveIndicatorBadge; supersede LiveIndicatorView), 7pbwp5c (Implement CaptureTopBar (close + flash/torch)), 7pbwp5d (Rewrite CaptureModeToggle as capsule pill), 7pbwp5e (Implement ShutterButton (76pt circle, press feedback)), 7pbwp5f (Replace RefusalBanner with RefusalSheet bottom sheet)
  - Stream: 2
  - Requirements: [20.2](requirements.md#20.2), [20.3](requirements.md#20.3), [20.4](requirements.md#20.4), [20.5](requirements.md#20.5), [20.6](requirements.md#20.6), [20.7](requirements.md#20.7)

- [x] 53. Add design-system token assertions to CI <!-- id:7pbwp5j -->
  - XCTest that asserts every `Color` referenced in the new views resolves through a `Color.<token>` named accessor in `App/Colors.swift` — guards against future inline `Color(red:green:blue:)` or hex string usage in view bodies.
  - Implementation: a `swift-syntax`-based source-scan or a simple grep step in the test target's setUp; flag violations.
  - Token coverage report listed in the test output.
  - Stream: 2
  - Requirements: [20.1](requirements.md#20.1)

## Tilt-tolerant capture (Decisions 17–19; research Decisions 43–47)

- [x] 54. Convert `LiveIndicatorBadge` tilt sub-element to continuous Δθ + σ_tilt% readout <!-- id:7pbwp5k -->
  - In `App/LiveIndicatorBadge.swift`, replace the binary green/white tilt colour state with a greyscale two-line readout: `\(Int(deltaThetaDeg))°` and `\(Int(cos(deltaThetaRad) * 100))%`. Both monospaced, white.
  - `LiveSampleObserver` already publishes `tiltAngleDeg`; the σ_tilt percentage is computed in the view from `cos()`.
  - Update `design-system/pages/photo-tab.md` §"Indicator badge — `LiveIndicatorBadge`" to reflect the greyscale treatment.
  - Tests: snapshot at Δθ = 5°, 17°, 35°; readout never shows green/red; chip remains tappable at every Δθ.
  - Decision: 19
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [20.4](requirements.md#20.4)

- [x] 55. Re-anchor chip auto-hide rule to `σ_tilt > 0.95 for 5 s` <!-- id:7pbwp5l -->
  - In `CaptureFlowModel` (or wherever the chip-visibility timer lives), change the auto-hide predicate from "tilt in ±5°" to "σ_tilt > 0.95 AND distance in-range AND coverage in-range AND state == .ready, all stable for 5 s".
  - Re-show on any predicate violation or on tap (existing behaviour).
  - Tests: chip hides after 5 s at Δθ = 10° (σ_tilt = 0.985) but not at Δθ = 20° (σ_tilt = 0.940).
  - Decision: 19
  - Blocked-by: 7pbwp5k (Convert `LiveIndicatorBadge` tilt sub-element to continuous Δθ + σ_tilt% readout)
  - Requirements: [20.4](requirements.md#20.4)

- [x] 56. Remove tilt clause from shutter-enable gate; add oblique hard cap message <!-- id:7pbwp5m -->
  - In `CaptureFlowModel.GatingSnapshot` and `ShutterButton`'s enable predicate, remove the tilt-in-range condition.
  - Add the oblique-stage hard cap predicate: when `activeStage == .oblique` and `|Δθ_oblique − 25°| > 30°`, disable the shutter and show an inline "tilt closer to 25°" message above the shutter (or in the existing refusal sheet path — UX choice for the implementer; the requirement only says it must be surfaced).
  - Map the new research `EstimationFailure.obliqueTiltOutOfRange` case to the Irish-English string "Tilt the camera closer to 25° for the angled view."
  - Tests: nadir-stage shutter is enabled at Δθ = 0°, 15°, 30°, 60° (no tilt gate); oblique-stage shutter is disabled at |Δθ−25°| = 31°+.
  - Decision: 18; research Decision 43
  - Requirements: [2.3](requirements.md#2.3), [7.2](requirements.md#7.2)

- [x] 57. Rewrite `ConfidencePill` for four tiers <!-- id:7pbwp5n -->
  - Update `App/ConfidencePill.swift` (the shared component used by `ResultView` and `MealRow`) to render four labels: "High", "Moderate", "Low", "Very Low" with thresholds per UI Req 9.2.
  - Map to `Color.confidenceHigh / .confidenceModerate / .confidenceLow / .confidenceVeryLow` per design §"Colour tokens".
  - Update all snapshot tests covering the pill to assert four tiers.
  - Decision: 17
  - Requirements: [9.2](requirements.md#9.2)

- [x] 58. Add `confidenceVeryLow` colour token <!-- id:7pbwp5o -->
  - In `App/Colors.swift`, add `static let confidenceVeryLow = Color(white: 0.35)` per design §"Colour tokens".
  - Update `design-system/MASTER.md` colour token table to include the new token.
  - Decision: 17
  - Requirements: [9.2](requirements.md#9.2)

- [x] 59. Implement Very-Low-confidence surface on `ResultView` (inline explanation + Retake / Keep as-is) <!-- id:7pbwp5p -->
  - In `App/ResultView.swift`, gate a new section on `record.confidence.sigmaMeal < 0.20` containing the captions and buttons listed below.
  - One-line caption: "This estimate may be wrong by orders of magnitude."
  - Second-line caption: "Capture was at \(Int(deltaTheta))° from target." (deltaTheta from `record.confidence.deltaThetaNadirDeg`; for two-view records use `max(deltaThetaNadirDeg, deltaThetaObliqueDeg ?? 0)`).
  - Two side-by-side buttons: "Retake" (pops the view, resets state to `.ready`) and "Keep as-is" (dismisses the surface only; the meal is already persisted at capture time).
  - The "Keep as-is" button hides the surface for the current view session; navigating away and back re-shows it (no persistent "dismissed" flag).
  - Tests: surface appears at σ = 0.15, hidden at σ = 0.25; Δθ string updates per record; both buttons wired.
  - Decision: 17
  - Blocked-by: 7pbwp5n (Rewrite `ConfidencePill` for four tiers)
  - Requirements: [9.3](requirements.md#9.3)

- [x] 60. Remove old uncertain-estimate prompt (σ < 0.60 path) from `ResultView` <!-- id:7pbwp5q -->
  - Delete the prior one-line "uncertain estimate" prompt and its Retake button from `ResultView.swift` — superseded by task 59.
  - Update any XCUITest cases that asserted the prompt appeared at σ ≈ 0.55 to instead assert no prompt at that range and the new prompt at σ < 0.20.
  - Decision: 17
  - Blocked-by: 7pbwp5p (Implement Very-Low-confidence surface on `ResultView` (inline explanation + Retake / Keep as-is)), surface, surface, surface, surface, surface, surface, surface
  - Requirements: [9.3](requirements.md#9.3)

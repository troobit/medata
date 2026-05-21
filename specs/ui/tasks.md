---
references:
    - specs/ui/requirements.md
    - specs/ui/design.md
    - specs/ui/decision_log.md
---
# UI — Implementation Tasks

## SPM prerequisites

- [ ] 1. Write tests for ARKitCaptureEngine streams and interruption observer methods <!-- id:7pbwp43 -->
  - Add CaptureKitTests/ARKitCaptureEngineStreamsTests.swift
  - Assert frames stream emits ARFrame via simulated session(_:didUpdate:) calls
  - Assert latest-only delivery under BufferingPolicy.bufferingNewest(1)
  - Assert interruption stream emits .began on sessionWasInterrupted and .ended on sessionInterruptionEnded in order
  - Assert cancelling iteration removes the continuation (no leaks)
  - Assert engine.session.delegate === engine after frames subscription
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [16.1](requirements.md#16.1)

- [ ] 2. Implement ARKitCaptureEngine accessors arSession, frames, interruptions plus ARSessionObserver interruption methods <!-- id:7pbwp44 -->
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

- [ ] 3. Add PipelineEstimator protocol and Pipeline conformance <!-- id:7pbwp45 -->
  - Create MedataCore/Sources/Pipeline/PipelineEstimator.swift
  - Declare public protocol PipelineEstimator: Sendable with single func estimate(captureResult: CaptureResult) async throws -> MealRecord
  - Add extension Pipeline: PipelineEstimator {} (empty — Pipeline.estimate signature already matches)
  - Per Decision 13: protocol lives in MedataCore not App/
  - Exempt from TDD pairing — pure interface declaration
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1), [9.1](requirements.md#9.1), [10.1](requirements.md#10.1)

- [ ] 4. Port brand assets icon.svg and favicon.ico from main branch <!-- id:7pbwp46 -->
  - git checkout main -- static/icon.svg static/favicon.ico
  - Verify the icon.svg stroke colour is #63ff00 (consumed by tasks 5 and 25)
  - Commit alongside other UI-spec work
  - Per Decision 7
  - Exempt from TDD — asset copy
  - Stream: 2
  - Requirements: [15.2](requirements.md#15.2)

## UI building blocks

- [ ] 5. Add App/Colors.swift with brand colour tokens <!-- id:7pbwp47 -->
  - extension Color { static let medataAccent = Color(red: 0x63/255, green: 0xFF/255, blue: 0x00/255); static let confidenceHigh = medataAccent; static let confidenceModerate = Color.orange; static let confidenceLow = Color.red }
  - Exempt from TDD — colour constants
  - Blocked-by: 7pbwp46 (Port brand assets icon.svg and favicon.ico from main branch)
  - Stream: 1
  - Requirements: [15.1](requirements.md#15.1), [9.2](requirements.md#9.2)

- [ ] 6. Add App/GatingSnapshot.swift struct <!-- id:7pbwp48 -->
  - struct GatingSnapshot: Equatable, Sendable with pathHint, tiltInRange, distanceCm, lidarCoveragePercent fields
  - Include withPath(_ newPath: CapturePath) -> GatingSnapshot helper
  - Per design.md state-machine section
  - Exempt from TDD — type definition
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [7.2](requirements.md#7.2)

- [ ] 7. Add App/CaptureState.swift enum and PermissionSubject + CaptureStage sub-enums <!-- id:7pbwp49 -->
  - Define all 9 cases of CaptureState per design.md (initialising, permissionDenied(.camera|.motion), trackingLost, ready, forcingTwoView, capturing(stage, frozen), estimating(captureResult), showingResult(MealRecord), refused(EstimationFailure, retryStage))
  - Conform to Equatable
  - Define PermissionSubject and CaptureStage sub-enums
  - Exempt from TDD — type definitions
  - Blocked-by: 7pbwp48 (Add App/GatingSnapshot.swift struct)
  - Stream: 1
  - Requirements: [1.6](requirements.md#1.6), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [13.3](requirements.md#13.3), [16.1](requirements.md#16.1)

- [ ] 8. Write tests for CapturePathDecider boundary table <!-- id:7pbwp4a -->
  - MeData/Tests/CapturePathDeciderTests.swift
  - Table rows: (supportsLiDAR: false, coverage: 100, expected: .twoViewSfs), (true, 0, .twoViewSfs), (true, 79.99, .twoViewSfs), (true, 80, .singleViewLidar), (true, 100, .singleViewLidar)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1)

- [ ] 9. Implement App/CapturePathDecider.swift <!-- id:7pbwp4b -->
  - enum CapturePathDecider { static func decide(supportsLiDAR: Bool, latestCoveragePercent: Float) -> CapturePath { supportsLiDAR && latestCoveragePercent >= 80 ? .singleViewLidar : .twoViewSfs } }
  - Make the tests from task 8 pass
  - Blocked-by: 7pbwp4a (Write tests for CapturePathDecider boundary table)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1)

- [ ] 10. Add App/LiveIndicatorModel.swift child @Observable <!-- id:7pbwp4c -->
  - @Observable @MainActor final class LiveIndicatorModel with liveTiltDegrees: Float, liveDistanceCm: Float?, liveLiDARCoveragePercent: Float
  - Per design.md — split from CaptureFlowModel to bound CaptureFlowView body redraws against the 60Hz frame stream
  - Exempt from TDD — observable holder, no logic
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [3.1](requirements.md#3.1), [4.1](requirements.md#4.1)

- [ ] 11. Add App/ShareSheet.swift UIViewControllerRepresentable wrapper <!-- id:7pbwp4d -->
  - struct ShareSheet: UIViewControllerRepresentable wrapping UIActivityViewController(activityItems:applicationActivities: nil)
  - Exempt from TDD — straight UIKit-bridge boilerplate
  - Stream: 1
  - Requirements: [11.4](requirements.md#11.4)

## UI components

- [ ] 12. Write tests for CaptureFlowModel state-machine transitions <!-- id:7pbwp4e -->
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

- [ ] 13. Implement App/CaptureFlowModel.swift orchestrator <!-- id:7pbwp4f -->
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

- [ ] 14. Write tests for LiveSampleObserver per-frame computation and write-gating <!-- id:7pbwp4g -->
  - MeData/Tests/LiveSampleObserverTests.swift
  - Synthesise CVPixelBuffer depth/confidence fixtures (reuse CaptureKitTests fixtures)
  - Assert tilt from frame.camera.transform gravity-aligned column
  - Assert distance = median of centre-crop depth in cm; nil when sceneDepth absent
  - Assert LiDAR coverage = fraction of pixels with confidence >= τ_conf=0.66, ×100
  - Assert write-gating: while CaptureFlowModel.state is not .ready or .forcingTwoView, frame writes are dropped (no flicker)
  - Blocked-by: 7pbwp44 (Implement ARKitCaptureEngine accessors arSession, frames, interruptions plus ARSessionObserver interruption methods), 7pbwp4c (Add App/LiveIndicatorModel.swift child @Observable)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [4.1](requirements.md#4.1)

- [ ] 15. Implement App/LiveSampleObserver.swift <!-- id:7pbwp4h -->
  - @MainActor final class LiveSampleObserver
  - Iterates engine.frames AsyncStream
  - Writes to LiveIndicatorModel only when CaptureFlowModel.state is .ready or .forcingTwoView
  - Started/cancelled by CaptureFlowModel based on state observation
  - Make the tests from task 14 pass
  - Blocked-by: 7pbwp4g (Write tests for LiveSampleObserver per-frame computation and write-gating)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [4.1](requirements.md#4.1)

- [ ] 16. Write tests for ARPreviewView delegate-reassertion guard <!-- id:7pbwp4i -->
  - MeData/Tests/ARPreviewViewTests.swift
  - After ARPreviewView.makeUIView creates ARView with engine.arSession, assert engine.session.delegate === engine
  - After forcing updateUIView invocation, assert engine.session.delegate === engine still
  - Both lifecycle points must re-assert (per design.md — RealityKit reassigns the delegate at either point historically)
  - Blocked-by: 7pbwp44 (Implement ARKitCaptureEngine accessors arSession, frames, interruptions plus ARSessionObserver interruption methods)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1)

- [ ] 17. Implement App/ARPreviewView.swift UIViewRepresentable <!-- id:7pbwp4j -->
  - struct ARPreviewView: UIViewRepresentable wrapping ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
  - makeUIView: assign arView.session = engine.arSession then re-assert engine.session.delegate = engine
  - updateUIView: re-assert engine.session.delegate = engine (idempotent property write)
  - Make the tests from task 16 pass
  - Blocked-by: 7pbwp4i (Write tests for ARPreviewView delegate-reassertion guard)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1)

- [ ] 18. Implement App/RefusalBanner.swift overlay view <!-- id:7pbwp4k -->
  - struct RefusalBanner: View taking EstimationFailure and a retry closure
  - Sits in .overlay(alignment: .top) on CaptureFlowView
  - .allowsHitTesting(true) on banner ZStack; only Try Again control clears it (no tap-outside dismiss per Decision 5)
  - Renders failure.localisedMessage verbatim (per requirements §12.2)
  - Exempt from TDD — visual composition; refusal flow integration tested in task 26
  - Blocked-by: 7pbwp47 (Add App/Colors.swift with brand colour tokens)
  - Stream: 1
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [12.2](requirements.md#12.2)

- [ ] 19. Implement App/LiveIndicatorView.swift child view <!-- id:7pbwp4l -->
  - struct LiveIndicatorView: View taking LiveIndicatorModel via @Bindable
  - Renders tilt indicator (in-range visually distinct), distance state (measured cm or 30-40cm guidance), LiDAR coverage gauge, capture-path indicator label
  - Surface gating-mode-active hint per §3.3
  - Exempt from TDD — visual composition; behaviour tested via CaptureFlowModel tests
  - Blocked-by: 7pbwp47 (Add App/Colors.swift with brand colour tokens), 7pbwp4c (Add App/LiveIndicatorModel.swift child @Observable)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1)

- [ ] 20. Write tests for ResultView confidence pill thresholds <!-- id:7pbwp4m -->
  - MeData/Tests/ResultViewTests.swift
  - Table over σ_meal ∈ {0.0, 0.59, 0.60, 0.74, 0.75, 1.0} → expected pill label (Low / Low / Moderate / Moderate / High / High)
  - Assert uncertain-prompt visibility when σ < 0.60
  - Assert per-class breakdown and clinical-macros absent (Decision 3, §9.5)
  - Snapshot or ViewInspector style assertion
  - Stream: 1
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.5](requirements.md#9.5)

- [ ] 21. Rewrite App/ResultView.swift <!-- id:7pbwp4n -->
  - Display total carbs in grams rounded to nearest 1g (Int(record.macros.totalCarbsG.rounded()))
  - Three-state confidence pill keyed off record.confidence.sigmaMeal
  - Uncertain-estimate prompt with Retake control when σ < 0.60
  - New-capture control that pops the result view
  - No per-class breakdown, no clinical macros
  - Make the tests from task 20 pass
  - Blocked-by: 7pbwp47 (Add App/Colors.swift with brand colour tokens), 7pbwp4m (Write tests for ResultView confidence pill thresholds)
  - Stream: 1
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4), [9.5](requirements.md#9.5), [12.1](requirements.md#12.1)

- [ ] 22. Extend App/SettingsView.swift with Export archive control <!-- id:7pbwp4o -->
  - Existing placeholder keeps the retention-period picker and IFCDB toggle (already wired)
  - Add Export archive button that calls PersistenceStore.exportArchive() async throws -> URL
  - Present the produced file via .sheet(item:) hosting ShareSheet
  - Exempt from TDD — UI plumbing; archive functionality covered by Persistence tests in research spec
  - Blocked-by: 7pbwp4d (Add App/ShareSheet.swift UIViewControllerRepresentable wrapper)
  - Stream: 1
  - Requirements: [11.1](requirements.md#11.1), [11.2](requirements.md#11.2), [11.3](requirements.md#11.3), [11.4](requirements.md#11.4)

- [ ] 23. Rewrite App/CaptureFlowView.swift root view <!-- id:7pbwp4p -->
  - NavigationStack(path: $model.navigationPath)
  - Composes ARPreviewView (preview), LiveIndicatorView (indicators), RefusalBanner (overlay), shutter button, settings navigation
  - .navigationDestination(for: MealRecord.self) { ResultView(record: $0) }
  - Shutter enabled only when state is .ready, snapshot.tiltInRange, distance gate OK, no in-flight estimation (§7.2)
  - Permission-denied view branch with Settings deep-link (§1.3)
  - Exempt from TDD — view composition; behaviour tested via CaptureFlowModel and XCUITests
  - Blocked-by: 7pbwp4f (Implement App/CaptureFlowModel.swift orchestrator), 7pbwp4h (Implement App/LiveSampleObserver.swift), 7pbwp4j (Implement App/ARPreviewView.swift UIViewRepresentable), 7pbwp4k (Implement App/RefusalBanner.swift overlay view), 7pbwp4l (Implement App/LiveIndicatorView.swift child view), 7pbwp4n (Rewrite App/ResultView.swift), 7pbwp4o (Extend App/SettingsView.swift with Export archive control)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [9.4](requirements.md#9.4)

- [ ] 24. Update App/App.swift for scenePhase forwarding to CaptureFlowModel <!-- id:7pbwp4q -->
  - @State private var model = CaptureFlowModel(...)
  - @Environment(\.scenePhase) and .onChange forwarding .active/.background/.inactive to model.scenePhaseChanged(_:)
  - .tint(.medataAccent) on the root view per §15.1
  - Exempt from TDD — wiring; lifecycle covered by task 12 backgrounding test
  - Blocked-by: 7pbwp47 (Add App/Colors.swift with brand colour tokens), 7pbwp4f (Implement App/CaptureFlowModel.swift orchestrator), 7pbwp4p (Rewrite App/CaptureFlowView.swift root view)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [8.3](requirements.md#8.3), [15.1](requirements.md#15.1)

## Asset generation

- [ ] 25. Write SVG-to-PNG AppIcon generation script <!-- id:7pbwp4r -->
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

- [ ] 26. Write XCUITest for refusal flow <!-- id:7pbwp4s -->
  - MeData/UITests/RefusalFlowUITests.swift
  - Inject fixture that trips EstimationFailure.noScaleAvailable
  - Assert refusal banner appears with the localised Irish-English message
  - Tap Try Again
  - Assert banner dismisses and state returns to .capturing at the right stage
  - Blocked-by: 7pbwp4p (Rewrite App/CaptureFlowView.swift root view), 7pbwp4q (Update App/App.swift for scenePhase forwarding to CaptureFlowModel)
  - Stream: 1
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [12.1](requirements.md#12.1), [12.2](requirements.md#12.2)

- [ ] 27. Write XCUITest for backgrounding behaviour (best-effort §8.3) <!-- id:7pbwp4t -->
  - MeData/UITests/BackgroundingUITests.swift
  - Tap shutter to enter .estimating
  - XCUIDevice.shared.press(.home)
  - Foreground the app
  - Assert UI is in .initialising (capture-flow main view)
  - Note: per Decision 12, a MealRecord may exist in the persistent store — this test asserts UI state only
  - Blocked-by: 7pbwp4p (Rewrite App/CaptureFlowView.swift root view), 7pbwp4q (Update App/App.swift for scenePhase forwarding to CaptureFlowModel)
  - Stream: 1
  - Requirements: [8.3](requirements.md#8.3)

- [ ] 28. Write XCUITest for AR interruption recovery <!-- id:7pbwp4u -->
  - MeData/UITests/InterruptionUITests.swift
  - Simulate ARSession sessionWasInterrupted via a test helper that emits .began on engine.interruptions stream
  - Assert state transitions to .trackingLost (UI shows tracking-lost banner)
  - Emit .ended
  - Assert engine.start() re-called and state returns to .initialising
  - Blocked-by: 7pbwp4p (Rewrite App/CaptureFlowView.swift root view), 7pbwp4q (Update App/App.swift for scenePhase forwarding to CaptureFlowModel)
  - Stream: 1
  - Requirements: [16.1](requirements.md#16.1)

import AVFoundation
import CaptureKit
import CoreMotion
import Foundation
import Observation
import os
import Pipeline
import SwiftUI

// Resolves the persistent CaptureMode from UserDefaults. When the key is unset
// (fresh install) the default forks on device capability: 1-view on LiDAR
// devices, 2-view on non-LiDAR devices (Req 16.2 / Decision 9). Existing
// installs that wrote the key keep their choice. `nonisolated` is required
// because the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which
// would otherwise make this free function implicitly MainActor-isolated and
// incompatible with the `@Sendable () -> CaptureMode` parameter type. The
// UserDefaults read is thread-safe (Apple documents internal locking).
nonisolated
func defaultCaptureModeReader(hasLiDAR: Bool) -> CaptureMode {
    let raw = UserDefaults.standard.string(forKey: SettingsKeys.captureMode)
    if let stored = raw.flatMap(CaptureMode.init(rawValue:)) { return stored }
    return hasLiDAR ? .single : .double
}

// Orchestrator for the capture flow per `specs/ui/iphone-experience/design.md`. Owns the state
// machine, drives the `CaptureSession` and `PipelineEstimator`, observes
// AR-session interruptions, and re-evaluates permissions on scene-phase
// transitions. `@MainActor` because every state read or write happens from
// SwiftUI bodies; AR / Core Motion deliver on the main thread already.
//
// Decision 35: `CaptureMode` is a persistent user-selected toggle. It is read
// at shutter-tap time (so mid-session changes don't affect an in-flight
// estimation) via the injected `captureModeReader` closure, which production
// resolves to UserDefaults under `SettingsKeys.captureMode`.
@Observable
@MainActor
final class CaptureFlowModel: CaptureFlowDelegate {
    var state: CaptureState = .initialising
    var lastMeal: MealRecord?
    var navigationPath = NavigationPath()
    let indicators: LiveIndicatorModel
    let supportsLiDAR: Bool
    // Per-capture reference-card override (fork sheet §3.2). Seeds from the
    // `alwaysIncludeCard` default when the fork sheet opens; the sheet mutates it
    // for the next capture only. NOT persisted — it drives card-placement
    // guidance during two-view capture; card detection itself stays automatic in
    // the pipeline.
    var includeCardThisCapture: Bool = false
    // Benchmark-capture tag (snaq-parity design lane B): set by the benchmark
    // surface before launching a capture, cleared when the benchmark flow ends.
    // While set, every persisted outcome row carries the meal id so attempts
    // group under (benchmark meal, model lineage) in the store's split bounds.
    var benchmarkMealID: UUID?
    // Benchmark tag frozen at the shutter tap that began the in-flight attempt
    // (review fix). The persist runs on a detached write-behind task, so
    // reading the live `benchmarkMealID` there could pick up a value the
    // benchmark UI cleared or set after the attempt — mistagging the row and
    // placing it in the wrong eviction population. Written only by
    // `beginCapture`; the benchmark surface never touches it.
    private var inFlightBenchmarkMealID: UUID?

    private let session: CaptureSession
    // `var` (not `let`): `Pipeline` is a value type, so the attempt-record
    // delegate must be stamped onto the copy THIS model holds — see the end
    // of `init`. Never reassigned elsewhere.
    private var pipeline: any PipelineEstimator
    private let store: (any PersistenceStore)?
    private let photoSaver: (any PhotoLibrarySaver)?
    private let databaseEdition: String
    private let paletteVersion: String
    private let cameraAuthorisation: @Sendable () -> AVAuthorizationStatus
    private let motionAvailable: @Sendable () -> Bool
    private let captureModeReader: @Sendable () -> CaptureMode
    // Pre-shutter food-region mask source per spec
    // `pipeline-real-device-correctness/`. Optional so existing tests
    // constructed before task 13 continue to compile; production callers
    // (App.swift) pass a non-nil instance so the freeze-at-nadir flow runs.
    private let preShutterSegmenter: (any PreShutterMaskSource)?
    // Segmenter lineage tag ("dev_stub" / "coreml_<modelVersion>") stamped as
    // modelVersion onto the slim capture-stage refusal records this model
    // writes itself (snaq-parity lane A); pipeline-produced records carry the
    // pipeline's own stamp. App.swift passes `Pipeline.segmenterSource`.
    // Non-private so AppRoot can scope the benchmark report and log to the
    // current lineage (snaq-parity lane B).
    let segmenterSource: String
    // Baseline for the per-attempt pre-shutter error delta (snaq-parity Req
    // 3.2). `PreShutterSegmenter.segmentationErrorCount` is lifetime-cumulative
    // with no reset, so persisting it raw would misattribute every earlier
    // attempt's errors to the current one. The attempt's window is "since the
    // last persisted attempt, or Capture presentation, whichever came later":
    // reset in `capturePresented()`, advanced to the counter's current value
    // by each successful persist (a failed store write leaves the baseline so
    // the window's errors roll into the next attempt instead of vanishing).
    private var preShutterErrorBaseline = 0

    private(set) var flowTask: Task<Void, Never>?
    private var interruptionTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    // True while the Capture surface is the presented full-screen cover (Graph
    // is the launch root — Decision 20). Set by `capturePresented`, cleared by
    // `captureDismissed`. Gates the AR session arm in `evaluatePermissions` so
    // the session runs ONLY while Capture is on screen: a fresh launch or a
    // foreground transition (`scenePhaseChanged(.active)`) while Graph / Data /
    // Settings is frontmost never starts the camera (Req 1.5).
    private var isCapturePresented = false
    private var firstFrame: RawFrame?
    // Tilt-at-shutter (degrees from straight-down) for the nadir frame, captured
    // when the user taps the shutter on the first stage. Stamped onto the
    // CaptureResult per Decision 44 / task 86 so σ_tilt reflects the camera pose
    // at the moment the photo was taken, not at the moment the pipeline runs.
    private var firstFrameTiltDeg: Float?
    // Pre-shutter mask frozen at the nadir-capture instant (Decision 11). For
    // single-view captures this is read directly into CaptureResult at the
    // same callsite. For two-view captures it travels with `firstFrame` /
    // `firstFrameTiltDeg` through the oblique tap; cleared in lockstep with
    // `firstFrame = nil` at every existing lifecycle site (Decision 11 table).
    var firstFrameMaskBox: PreShutterSegmenter.MaskBox?
    // Age of `firstFrameMaskBox` at the original nadir-tap instant, in
    // milliseconds. Stashed at the nadir tap so the oblique-stage CaptureResult
    // carries the same non-negative age recorded then (smolspec
    // no-food-pixels-on-fruit-plate-mvp / 2026-06-14 bugfix). Without this,
    // every double-mode oblique CaptureResult had preShutterMaskAgeMs == nil →
    // `event=estimate.start maskAgeMs=-1` → `failure=noFoodPixels`.
    var firstFrameMaskAgeMs: Int?

    private let log = Logger(subsystem: "ie.medata.app", category: "Shutter")
    // Mode frozen at the shutter-tap that began the in-flight capture. The
    // pipeline runs against this value; mid-session toggle changes are
    // ignored until the result view is shown.
    private var inFlightMode: CaptureMode?

    init(
        session: CaptureSession,
        pipeline: any PipelineEstimator,
        indicators: LiveIndicatorModel,
        interruptions: AsyncStream<ARKitCaptureEngine.InterruptionEvent>,
        supportsLiDAR: Bool,
        databaseEdition: String,
        paletteVersion: String,
        segmenterSource: String,
        store: (any PersistenceStore)? = nil,
        photoSaver: (any PhotoLibrarySaver)? = nil,
        preShutterSegmenter: (any PreShutterMaskSource)? = nil,
        cameraAuthorisation: @escaping @Sendable () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .video)
        },
        motionAvailable: @escaping @Sendable () -> Bool = {
            CMMotionManager().isDeviceMotionAvailable
        },
        captureModeReader: (@Sendable () -> CaptureMode)? = nil
    ) {
        self.session = session
        self.pipeline = pipeline
        self.store = store
        self.photoSaver = photoSaver
        self.indicators = indicators
        self.supportsLiDAR = supportsLiDAR
        self.databaseEdition = databaseEdition
        self.paletteVersion = paletteVersion
        self.segmenterSource = segmenterSource
        self.preShutterSegmenter = preShutterSegmenter
        self.cameraAuthorisation = cameraAuthorisation
        self.motionAvailable = motionAvailable
        // When no explicit reader is injected, resolve the persistent mode with
        // the capability-aware default (Req 16.2). `hasLiDAR` captures the Bool
        // param, keeping the closure @Sendable.
        let hasLiDAR = supportsLiDAR
        self.captureModeReader = captureModeReader ?? { defaultCaptureModeReader(hasLiDAR: hasLiDAR) }

        evaluatePermissions()
        observeInterruptions(stream: interruptions)

        // Wire the attempt-record handoff (snaq-parity lane A). `Pipeline` is
        // a struct, so the weak delegate reference must be set on the copy
        // this model retains — a post-construction `pipeline.delegate = model`
        // in App.swift would mutate a dead copy. Mock estimators injected by
        // tests are not `Pipeline` and take their own delivery path (none).
        if var concrete = pipeline as? Pipeline {
            concrete.delegate = self
            self.pipeline = concrete
        }
    }

    // MARK: - Derived view state

    // Shutter is armed in .ready with the distance gate satisfied and no
    // capture / estimation in flight (§7.2). Tilt no longer gates the nadir
    // stage (Decision 18 / research Decision 43); the oblique stage retains a
    // hard cap of |Δθ − 25°| ≤ 15° (closeout-trail Decision 1, tightening the
    // ±30° aspect of research Decision 18/43 after three device trails overshot).
    var canShutter: Bool {
        switch state {
        case .ready(let snapshot):
            guard distanceGateOK(snapshot) else { return false }
            if firstFrame != nil {
                return obliqueTiltOk(degrees: indicators.liveTiltDegrees)
            }
            // First-shot race (fix/first-shot-nofoodpixels): the nadir shutter
            // must not arm until a usable pre-shutter food mask exists. Without
            // this, the very first tap of a session could fire while
            // `preShutterSegmenter.latest` is still nil — `performFlow` then
            // built a CaptureResult with `maskAgeMs=-1`, the support-plane
            // fitter's empty-mask gate refused, and the tap mapped to
            // `EstimationFailure.noFoodPixels`. The second tap (mask now ready)
            // succeeded. Gating here turns that failed first shot into the
            // existing disabled-shutter "waiting" UX instead of a refusal.
            return hasUsablePreShutterMask
        default:
            return false
        }
    }

    // True iff the pre-shutter producer currently holds a mask fresh enough to
    // survive the nadir-instant staleness gate. The 750 ms bound mirrors the
    // ceiling applied in `performFlow` at the nadir-capture instant so the
    // shutter never arms on a mask that the capture path would then discard
    // (no arm-then-refuse). When no producer is injected (legacy / unit-test
    // callers, App.swift always passes one) the gate is bypassed so the shutter
    // is never permanently disabled.
    private var hasUsablePreShutterMask: Bool {
        guard let producer = preShutterSegmenter else { return true }
        guard let ts = producer.latest else { return false }
        return millisecondsBetween(ts.producedAt, ContinuousClock.now) <= 750
    }

    // True iff the live tilt is within the oblique hard cap window
    // (|Δθ − 25°| ≤ 15° — closeout-trail Decision 1). Used both by `canShutter`
    // and by the inline above-shutter message that surfaces when the user is on
    // the oblique stage but outside the cap.
    var obliqueTiltMessage: String? {
        guard firstFrame != nil, case .ready = state else { return nil }
        if obliqueTiltOk(degrees: indicators.liveTiltDegrees) { return nil }
        // Copy inventory §2.1 clause: oblique guidance above the shutter reads
        // `Target 25°` — the same string as the §4 tilt hint.
        return "Target 25°"
    }

    // Transient chip shown above the shutter when a blocked tap lands (design:
    // parity audit — replaces the old badge reveal). Names the failing gate in
    // ≤ 3 words per the §4 chip vocabulary (copy inventory). nil when the
    // shutter is not blocked for a nameable reason.
    var failingShutterGate: String? {
        switch state {
        case .trackingLost:
            return "hold steady"
        case .initialising:
            return "wait"
        case .ready(let snapshot):
            if !distanceGateOK(snapshot) { return "too far" }
            if firstFrame == nil, !hasUsablePreShutterMask { return "wait" }
            return nil
        default:
            return nil
        }
    }

    var currentSnapshot: GatingSnapshot? {
        switch state {
        case .ready(let snapshot), .capturing(_, let snapshot):
            return snapshot
        default:
            return nil
        }
    }

    var isBusy: Bool {
        switch state {
        case .capturing, .estimating: return true
        default: return false
        }
    }

    var awaitingObliqueView: Bool { firstFrame != nil }

    // The captured nadir frame, surfaced so the viewfinder can show a
    // confirmation thumbnail while the user aims the oblique view.
    var capturedNadirFrame: RawFrame? { firstFrame }

    // Wraps the current refusal in an Identifiable surface so the bottom-sheet
    // refusal can bind to it via `.sheet(item:)` (Req §20.7 / Decision 16).
    // The `id` derives from the underlying failure so consecutive presentations
    // of the same failure don't trip SwiftUI's diffing. The setter is a no-op:
    // SwiftUI writes nil on swipe-down but the dismissal path is the explicit
    // `dismissRefusal()` command, called from the view's `refusalBinding.set`.
    // Keeping the setter unimplemented makes "where dismissal happens" a single
    // call site instead of two.
    var refusal: ActiveRefusal? {
        if case let .refused(failure, stage) = state {
            return ActiveRefusal(failure: failure, retryStage: stage)
        }
        return nil
    }

    // MARK: - Public commands

    func shutter() {
        guard case let .ready(snapshot) = state,
              distanceGateOK(snapshot)
        else { return }
        // Decision 18 / research Decision 43: only the oblique stage retains a
        // tilt hard cap; nadir captures always proceed regardless of tilt.
        if firstFrame != nil, !obliqueTiltOk(degrees: indicators.liveTiltDegrees) {
            return
        }
        // First-shot race (fix/first-shot-nofoodpixels): mirror the `canShutter`
        // nadir gate so a programmatic / racing fire can't begin a nadir capture
        // before a usable pre-shutter mask exists. The UI already disables the
        // button when `canShutter` is false; this is the matching command-side
        // guard, consistent with the distance / oblique-tilt re-checks above.
        if firstFrame == nil, !hasUsablePreShutterMask {
            return
        }

        // Pick up the persistent mode at the shutter tap and freeze it for the
        // rest of the flow (mid-session toggle changes are ignored).
        let mode = inFlightMode ?? captureModeReader()
        inFlightMode = mode

        let stage: CaptureStage = firstFrame != nil ? .oblique : .nadir
        log.info("\(self.gatingLog(event: "fired", extra: "mode=\(mode.rawValue) stage=\(stage.name)"), privacy: .public)")
        beginCapture(stage: stage, frozen: snapshot, mode: mode)
    }

    // Diagnostic for taps on the .disabled shutter. Does not mutate state.
    // The old badge reveal is gone (design: parity audit) — the view surfaces a
    // transient failing-gate chip instead. This still emits one .info log line
    // with the full gating snapshot so a Console.app subscriber can see which
    // gate is blocking.
    func shutterBlockedTapped() {
        log.info("\(self.gatingLog(event: "blocked"), privacy: .public)")
    }

    // Alias for the bottom-sheet "Try again" CTA (Req §20.7 / Decision 16).
    func retry() { tryAgain() }

    func tryAgain() {
        guard case let .refused(_, retryStage) = state else { return }
        let snapshot = freshSnapshot()
        // Retake from the same stage. If retryStage is .oblique we keep firstFrame
        // so the user does not have to retake the nadir view (req §5.4). If
        // retryStage is .nadir, drop any previously captured nadir.
        if retryStage == .nadir { firstFrame = nil; firstFrameTiltDeg = nil; firstFrameMaskBox = nil; firstFrameMaskAgeMs = nil }
        let mode = inFlightMode ?? captureModeReader()
        inFlightMode = mode
        beginCapture(stage: retryStage, frozen: snapshot, mode: mode)
    }

    func dismissResult() {
        guard case .showingResult = state else { return }
        navigationPath = NavigationPath()
        firstFrame = nil; firstFrameTiltDeg = nil; firstFrameMaskBox = nil; firstFrameMaskAgeMs = nil
        inFlightMode = nil
        state = .ready(freshSnapshot())
    }

    // Fresh-capture ⋯ Delete (Decision 17): the meal is already persisted, so
    // discarding means deleting it from the store, then clearing the capture
    // stack. `ResultView` holds no store reference — it calls this. The
    // `.showingResult` guard in `dismissResult()` still holds because the delete
    // runs asynchronously and this method calls `dismissResult()` synchronously
    // before yielding.
    func deleteAndDismiss(_ record: MealRecord) {
        guard case .showingResult = state else { return }
        if let store {
            Task { [store] in try? await store.deleteMeal(id: record.id) }
        }
        dismissResult()
    }

    // Error-overlay `2-view` action (§4). A plain `retry()` would re-run the
    // frozen single-mode attempt; instead clear `inFlightMode`, persist `.double`
    // (same semantics as tapping the mode toggle), and return to a live `.ready`
    // state so the next shutter runs the two-view path with the AR session live.
    func switchToTwoViewAndRetry() {
        guard case .refused = state else { return }
        UserDefaults.standard.set(CaptureMode.double.rawValue, forKey: SettingsKeys.captureMode)
        firstFrame = nil; firstFrameTiltDeg = nil; firstFrameMaskBox = nil; firstFrameMaskAgeMs = nil
        inFlightMode = nil
        state = .ready(freshSnapshot())
    }

    // popRoute() was retired with the `.correction` route (serving-adjust PRD
    // Req 5): the capture stack no longer pushes a screen that pops itself.

    // Sheet swipe-down on the RefusalSheet (Req §20.7 / Decision 16). Clears
    // the captured nadir and any in-flight mode so the user lands back at the
    // viewfinder in a fresh state. The explicit retry path (`tryAgain`) is
    // unchanged — it preserves `firstFrame` when retrying from oblique stage.
    func dismissRefusal() {
        guard case .refused = state else { return }
        firstFrame = nil; firstFrameTiltDeg = nil; firstFrameMaskBox = nil; firstFrameMaskAgeMs = nil
        inFlightMode = nil
        state = .ready(freshSnapshot())
    }

    func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background, .inactive:
            cancelInFlight()
            switch state {
            case .capturing, .estimating:
                state = .initialising
                firstFrame = nil; firstFrameTiltDeg = nil; firstFrameMaskBox = nil; firstFrameMaskAgeMs = nil
                inFlightMode = nil
            default:
                break
            }
            Task { [session] in try? await session.stop() }
            startTask = nil
        case .active:
            evaluatePermissions()
        @unknown default:
            break
        }
    }

    // Capture-cover present arm per Req §1.5 / Decision 20 (Graph is the launch
    // root; the `.refused` arm is superseded — see specs/bugfixes/
    // surface-not-detected/report.md). Presenting the Capture cover arms the AR
    // session. Calling `evaluatePermissions()` is idempotent — it bails out on
    // permission-denied and only spawns a fresh start task when one is not
    // already in flight. A single-item cover state means dismiss-then-present is
    // sequential, so the AR session never double-toggles.
    func capturePresented() {
        isCapturePresented = true
        // Fresh aiming window for the pre-shutter error delta: whatever the
        // lifetime counter accumulated before this presentation belongs to
        // earlier sessions, not to this session's first attempt.
        preShutterErrorBaseline = preShutterSegmenter?.segmentationErrorCount ?? 0
        evaluatePermissions()
    }

    // The Capture cover was dismissed (Req §1.5 / Decision 20): release the AR
    // session within 200 ms. Mirrors `scenePhaseChanged(.background)` with one
    // carve-out: when the model is already in `.estimating`, the pipeline runs
    // to completion and the result is presented on the next return to Capture.
    // Permission-denied is preserved (no engine to release); `.refused` is
    // treated as an implicit dismissal — same baseline as `.ready`.
    func captureDismissed() {
        isCapturePresented = false
        switch state {
        case .estimating:
            // Let the pipeline finish; `flowTask` already routes the result
            // into `.showingResult(record)`. Release the engine in the
            // background (no AR session needed while we wait for the result).
            Task { [session] in try? await session.stop() }
            startTask = nil
        case .permissionDenied:
            // No engine to release. Leave the state alone.
            return
        case .refused:
            // Leaving Photo while refused dismisses the refusal — the user
            // does not return to a sheet they cannot interactively dismiss
            // before leaving (see surface-not-detected bugfix).
            firstFrame = nil; firstFrameTiltDeg = nil; firstFrameMaskBox = nil; firstFrameMaskAgeMs = nil
            inFlightMode = nil
            state = .initialising
            Task { [session] in try? await session.stop() }
            startTask = nil
        case .capturing:
            // Capture in flight but estimation hasn't started: cancel and
            // reset to the same baseline as backgrounding.
            cancelInFlight()
            firstFrame = nil; firstFrameTiltDeg = nil; firstFrameMaskBox = nil; firstFrameMaskAgeMs = nil
            state = .initialising
            Task { [session] in try? await session.stop() }
            startTask = nil
        case .initialising, .ready, .trackingLost, .showingResult:
            firstFrame = nil; firstFrameTiltDeg = nil; firstFrameMaskBox = nil; firstFrameMaskAgeMs = nil
            // This arm never matches `.estimating` (handled above), so the reset
            // to `.initialising` is unconditional.
            state = .initialising
            Task { [session] in try? await session.stop() }
            startTask = nil
        }
    }

    // Called by LiveSampleObserver per frame. `tiltDegrees` is the camera's
    // angle from straight-down (0° = nadir). Per the write-gating rule in
    // design.md the model drops live updates unless the user can actually act
    // on them, preventing indicator flicker during capture / estimation.
    func liveSampleDidUpdate(
        tiltDegrees: Float,
        distanceCm: Float?,
        lidarCoveragePercent: Float,
        trackingIsNormal: Bool,
        tiltVector: SIMD2<Float> = .zero
    ) {
        let snapshot = GatingSnapshot(
            tiltInRange: tiltInRange(degrees: tiltDegrees),
            distanceCm: distanceCm,
            lidarCoveragePercent: lidarCoveragePercent
        )

        // Indicator display values are written only in states where the user
        // is acting on them; capture / estimation freeze them (no flicker).
        switch state {
        case .initialising where trackingIsNormal:
            writeIndicators(tiltDegrees, distanceCm, lidarCoveragePercent, tiltVector)
            state = .ready(snapshot)
        case .ready:
            writeIndicators(tiltDegrees, distanceCm, lidarCoveragePercent, tiltVector)
            state = .ready(snapshot)
        case .trackingLost where trackingIsNormal:
            writeIndicators(tiltDegrees, distanceCm, lidarCoveragePercent, tiltVector)
            state = .ready(snapshot)
        default:
            break
        }
    }

    private func writeIndicators(
        _ tilt: Float, _ distanceCm: Float?, _ coverage: Float, _ tiltVector: SIMD2<Float>
    ) {
        indicators.liveTiltDegrees = tilt
        indicators.liveTiltVector = tiltVector
        indicators.liveDistanceCm = distanceCm
        indicators.liveLiDARCoveragePercent = coverage
    }

    // Hook for the engine to report tracking degraded outside of an in-flight
    // capture. Distinct from the capture-time path which discards the frame.
    func trackingDegraded() {
        switch state {
        case .ready:
            state = .trackingLost
            firstFrame = nil; firstFrameTiltDeg = nil; firstFrameMaskBox = nil; firstFrameMaskAgeMs = nil
        case .capturing(stage: .nadir, _):
            cancelInFlight()
            state = .trackingLost
        default:
            break
        }
    }

    // MARK: - CaptureFlowDelegate (forward-compat no-ops per Decisions 9, 11)

    nonisolated func didUpdateTilt(angleDegrees: Float) {}
    nonisolated func didUpdateLiDARCoverage(percent: Float) {}
    nonisolated func didDetectInterClassOcclusion() {}
    nonisolated func didProduceEstimate(_ record: MealRecord) {}

    // Write-behind persistence of the attempt record (snaq-parity Req 2.1,
    // 2.4). Fired by the pipeline exactly once per non-cancelled attempt.
    // Detached so the store write is decoupled from the estimation task: a
    // cancelled flow can never cancel the persist, and the estimation result
    // is never delayed or blocked by it.
    nonisolated func didCompleteAttempt(_ record: EstimationAttemptRecord) {
        Task.detached { [weak self] in
            await self?.persistAttemptRecord(record)
        }
    }

    // Merges the App-owned measurements into the snapshot and writes the
    // outcome row. Store errors are logged to the Shutter category and
    // swallowed (MaskArtefactWriter.persistMask precedent): a recording
    // failure must neither alter nor block the estimation result (Req 2.4).
    private func persistAttemptRecord(_ record: EstimationAttemptRecord) async {
        guard let store else { return }
        var merged = record
        var counterAtMerge: Int?
        if let segmenter = preShutterSegmenter {
            // Per-attempt delta (Req 3.2): the producer's counter is lifetime-
            // cumulative, so persist only its growth since the baseline.
            let count = segmenter.segmentationErrorCount
            merged = record.withPreShutterSegmentationErrorCount(
                max(0, count - preShutterErrorBaseline)
            )
            counterAtMerge = count
        }
        do {
            let outcome = try EstimationOutcome(
                record: merged, benchmarkMealID: inFlightBenchmarkMealID
            )
            try await store.saveEstimationOutcome(outcome)
            // Advance the baseline only once the row is durably saved: a
            // failed write must leave the window open so its errors roll into
            // the next attempt's delta instead of vanishing with the lost row.
            if let counterAtMerge { preShutterErrorBaseline = counterAtMerge }
        } catch {
            log.error("event=outcome.persist.failed error=\(String(describing: error), privacy: .public)")
        }
    }

    // Slim outcome record for a capture-stage refusal that never reached
    // `Pipeline.estimate` (snaq-parity design lane A): outcome refused,
    // failure domain "capture", no stage measurements — the log covers every
    // attempt the user experienced, not only those that reached the pipeline.
    // Cancellation never routes here (not an outcome).
    private func persistCaptureRefusal(caseName: String, payload: String?, mode: CaptureMode) {
        let record = EstimationAttemptRecord(
            v: EstimationAttemptRecord.currentSchemaVersion,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            outcome: .refused,
            failure: EstimationAttemptRecord.FailureInfo(
                domain: "capture", caseName: caseName, payload: payload
            ),
            modelVersion: segmenterSource,
            mealID: nil,
            capturePath: mode.capturePath.rawValue
        )
        Task.detached { [weak self] in
            await self?.persistAttemptRecord(record)
        }
    }

    // MARK: - Internals

    func handleInterruption(_ event: ARKitCaptureEngine.InterruptionEvent) {
        switch event {
        case .began:
            cancelInFlight()
            firstFrame = nil; firstFrameTiltDeg = nil; firstFrameMaskBox = nil; firstFrameMaskAgeMs = nil
            inFlightMode = nil
            state = .trackingLost
            Task { [session] in try? await session.stop() }
            startTask = nil
        case .ended:
            state = .initialising
            startTask = nil
            evaluatePermissions()
        }
    }

    private func evaluatePermissions() {
        let camera = cameraAuthorisation()
        if camera == .denied || camera == .restricted {
            state = .permissionDenied(.camera)
            return
        }
        if !motionAvailable() {
            state = .permissionDenied(.motion)
            return
        }
        if case .permissionDenied = state {
            state = .initialising
        }
        // Arm the AR session only while the Capture surface is the presented
        // cover (Req 1.5 / Decision 20). At launch and while Graph / Data /
        // Settings is frontmost this is false, so neither a fresh launch nor a
        // foreground transition starts the camera; `capturePresented()` arms it.
        if startTask == nil, isCapturePresented {
            startTask = Task { [session] in try? await session.start() }
        }
    }

    private func beginCapture(stage: CaptureStage, frozen: GatingSnapshot, mode: CaptureMode) {
        // Freeze the benchmark tag for every record this attempt persists —
        // see `inFlightBenchmarkMealID`.
        inFlightBenchmarkMealID = benchmarkMealID
        state = .capturing(stage: stage, frozen: frozen)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performFlow(stage: stage, frozen: frozen, mode: mode)
        }
        flowTask = task
    }

    private func performFlow(stage: CaptureStage, frozen: GatingSnapshot, mode: CaptureMode) async {
        // Ensure the session has finished starting before we capture; the start
        // is kicked off fire-and-forget on .initialising entry and CaptureSession
        // throws .sessionNotStarted if captureNadir/Oblique races ahead of it.
        await startTask?.value
        // Snapshot the live tilt before the await — `liveTiltDegrees` is the
        // most recent value published by `LiveSampleObserver`, which matches the
        // moment the user tapped the shutter (per Decision 44 / task 86). The
        // post-capture tilt may have drifted (the user lowers the phone after
        // tapping); we want the pre-capture value.
        let tiltAtShutterDeg = indicators.liveTiltDegrees
        do {
            log.info("event=capture.start stage=\(stage.name, privacy: .public)")
            let frame = try await capture(stage: stage)
            log.info("event=capture.end stage=\(stage.name, privacy: .public) success=true width=\(frame.imageWidth) height=\(frame.imageHeight)")
            guard !Task.isCancelled else { return }
            guard case .capturing = state else { return }

            // Snapshot the pre-shutter mask at the nadir-capture instant per
            // Decision 11 and Decision 13. `awaitPaused()` drains any
            // in-flight inference so the subsequent `latest` read is atomic
            // with respect to the producer (no TOCTOU). The 750 ms staleness
            // ceiling is applied here, at the nadir tap, not at
            // `CaptureResult` construction time — the oblique-tap delay must
            // not invalidate a fresh nadir-instant pairing.
            let nadirMaskBox: PreShutterSegmenter.MaskBox?
            let nadirMaskAgeMs: Int?
            if stage == .nadir, let producer = preShutterSegmenter {
                await producer.awaitPaused()
                if let ts = producer.latest {
                    let ageMs = millisecondsBetween(ts.producedAt, ContinuousClock.now)
                    if ageMs <= 750 {
                        nadirMaskBox = ts.box
                        nadirMaskAgeMs = ageMs
                    } else {
                        nadirMaskBox = nil
                        nadirMaskAgeMs = nil
                    }
                } else {
                    nadirMaskBox = nil
                    nadirMaskAgeMs = nil
                }
            } else if stage == .oblique {
                // Oblique tap: read back the mask + age stashed at the
                // original nadir tap. The 750 ms staleness check already
                // fired at the nadir instant (Decision 11) so the oblique-
                // tap delay must NOT invalidate the pairing.
                nadirMaskBox = firstFrameMaskBox
                nadirMaskAgeMs = firstFrameMaskAgeMs
            } else {
                nadirMaskBox = nil
                nadirMaskAgeMs = nil
            }

            // Two-view (Double) mode: after the nadir tap, stash the frame
            // and wait for the user to take the oblique tap. The nadir-instant
            // mask age is stashed alongside `firstFrameMaskBox` so the
            // oblique-stage CaptureResult carries it through to
            // `event=estimate.start maskAgeMs=N` (smolspec bugfix
            // no-food-pixels-on-fruit-plate-mvp / 2026-06-14).
            if stage == .nadir, mode == .double {
                firstFrame = frame
                firstFrameTiltDeg = tiltAtShutterDeg
                firstFrameMaskBox = nadirMaskBox
                firstFrameMaskAgeMs = nadirMaskAgeMs
                state = .ready(frozen)
                return
            }

            // Per Decision 44 the σ_tilt computation runs over the angular
            // deviation from each stage's target axis (0° for nadir, 25° for
            // oblique). We persist the raw angle (degrees from straight-down)
            // and let the pipeline convert to Δθ per stage.
            let nadirAngle = stage == .oblique ? (firstFrameTiltDeg ?? 0) : tiltAtShutterDeg
            let obliqueAngle: Float? = stage == .oblique ? tiltAtShutterDeg : nil

            // For the oblique tap, the relevant mask is the one frozen at the
            // earlier nadir tap (Decision 11). For single-view, it's the
            // mask we just snapshotted above.
            let preShutterMaskBox: PreShutterSegmenter.MaskBox? =
                stage == .oblique ? firstFrameMaskBox : nadirMaskBox

            // `foodRegionCoveragePercent: 0` — Pipeline.estimate recomputes
            // the real value against the pre-shutter mask + depth confidence
            // buffer per Decision 14 and Req 4.1. The old wiring of
            // `frozen.lidarCoveragePercent` is removed because that value
            // measured whole-frame coverage, not food-region coverage.
            let captureResult = CaptureResult(
                capturePath: mode.capturePath,
                lidar: LiDARStatus(
                    available: supportsLiDAR,
                    foodRegionCoveragePercent: 0
                ),
                nadirFrame: stage == .oblique ? (firstFrame ?? frame) : frame,
                obliqueFrame: stage == .oblique ? frame : nil,
                databaseEdition: databaseEdition,
                paletteVersion: paletteVersion,
                nadirAngleAtCaptureDeg: nadirAngle,
                obliqueAngleAtCaptureDeg: obliqueAngle,
                preShutterFoodMask: preShutterMaskBox?.mask,
                preShutterMaskAgeMs: nadirMaskAgeMs
            )
            await runEstimation(captureResult: captureResult, mode: mode, retryStage: stage)
        } catch is CancellationError {
            // Cancellation is not an outcome (snaq-parity design): a user-
            // abandoned capture writes no record.
            return
        } catch CaptureError.worldTrackingDegraded {
            log.info("event=capture.end stage=\(stage.name, privacy: .public) success=false error=worldTrackingDegraded")
            persistCaptureRefusal(caseName: "worldTrackingDegraded", payload: nil, mode: mode)
            state = .trackingLost
        } catch let captureError as CaptureError {
            let caseName = captureError.failureCaseName
            log.info("event=capture.end stage=\(stage.name, privacy: .public) success=false error=\(caseName, privacy: .public)")
            // Typed capture error (Req 2.1): record the real case name rather
            // than collapsing to "internalError"; `captureFailed`'s associated
            // message flattens into the payload (FailureInfo(estimation:)
            // precedent).
            persistCaptureRefusal(
                caseName: caseName, payload: captureError.failurePayload, mode: mode
            )
            state = .refused(.internalError(caseName), retryStage: stage)
        } catch let failure as EstimationFailure {
            log.info("event=capture.end stage=\(stage.name, privacy: .public) success=false error=\(String(describing: failure), privacy: .public)")
            // Thrown before the pipeline ran, so no didCompleteAttempt fired:
            // record it here, under the capture domain, keeping the typed
            // case name and payload.
            let info = EstimationAttemptRecord.FailureInfo(estimation: failure)
            persistCaptureRefusal(caseName: info.caseName, payload: info.payload, mode: mode)
            state = .refused(failure, retryStage: stage)
        } catch {
            let typeName = String(describing: type(of: error))
            log.info("event=estimate.end stage=\(stage.name, privacy: .public) success=false error=\(typeName, privacy: .public)")
            // Non-typed capture error: preserve the underlying description in
            // the record, Release builds included (Req 3.3).
            persistCaptureRefusal(
                caseName: "internalError", payload: String(reflecting: error), mode: mode
            )
            state = .refused(.internalError(typeName), retryStage: stage)
        }
    }

    private func capture(stage: CaptureStage) async throws -> RawFrame {
        switch stage {
        case .nadir: return try await session.captureNadir()
        case .oblique: return try await session.captureOblique()
        }
    }

    private func runEstimation(
        captureResult: CaptureResult,
        mode: CaptureMode,
        retryStage: CaptureStage
    ) async {
        state = .estimating(captureResult: captureResult)
        log.info("event=estimate.start capturePath=\(captureResult.capturePath.rawValue, privacy: .public)")
        do {
            let record = try await pipeline.estimate(captureResult: captureResult, mode: mode)
            guard !Task.isCancelled else { return }
            guard case .estimating = state else { return }

            // Decision 37 / Req §17.3: save the captured nadir frame to Photos
            // and stamp the returned PHAsset.localIdentifier on the persisted
            // meal. A denied Photos prompt is NOT an error — the meal still
            // surfaces; the result view falls back to a placeholder.
            let stamped = await saveNadirPhoto(record: record, frame: captureResult.nadirFrame)
            firstFrame = nil; firstFrameTiltDeg = nil; firstFrameMaskBox = nil; firstFrameMaskAgeMs = nil
            inFlightMode = nil
            lastMeal = stamped
            log.info("event=estimate.end success=true mealId=\(stamped.id.uuidString, privacy: .public) capturePath=\(captureResult.capturePath.rawValue, privacy: .public)")
            state = .showingResult(stamped)
            // Flow lands on Segmentation review first (§1.3); its Carbs action
            // pushes `.result`. `.showingResult` holds across review → result →
            // correction, so dismissResult/deleteAndDismiss guards still fire.
            navigationPath.append(CaptureRoute.review(stamped))
        } catch is CancellationError {
            return
        } catch let failure as EstimationFailure {
            log.info("event=estimate.end success=false failure=\(String(describing: failure), privacy: .public)")
            guard case .estimating = state else { return }
            state = .refused(failure, retryStage: retryStage)
        } catch {
            guard case .estimating = state else { return }
            let typeName = String(describing: type(of: error))
            log.info("event=estimate.end success=false error=\(typeName, privacy: .public)")
            state = .refused(.internalError(typeName), retryStage: retryStage)
        }
    }

    // Saves the captured nadir frame to the user's Photos library (if a saver
    // is injected) and stamps the returned PHAsset.localIdentifier on the
    // persisted meal. Returns the record updated with the asset ID. Throws
    // nothing — Photos failures degrade to an empty identifier.
    private func saveNadirPhoto(record: MealRecord, frame: RawFrame) async -> MealRecord {
        guard let photoSaver else { return record }
        let assetID: String
        do {
            assetID = try await photoSaver.saveNadirFrame(frame)
        } catch {
            // Encoding / performChanges failure — degrade to empty identifier.
            assetID = ""
        }
        guard !assetID.isEmpty else { return record }
        if let store {
            try? await store.updatePhotoAssetID(mealId: record.id, photoAssetID: assetID)
        }
        return record.withPhotoAssetID(assetID)
    }

    private func cancelInFlight() {
        flowTask?.cancel()
        flowTask = nil
    }

    private func freshSnapshot() -> GatingSnapshot {
        GatingSnapshot(
            tiltInRange: false,
            distanceCm: indicators.liveDistanceCm,
            lidarCoveragePercent: indicators.liveLiDARCoveragePercent
        )
    }

    private func distanceGateOK(_ snapshot: GatingSnapshot) -> Bool {
        // No LiDAR ⇒ distance is guidance-only and does not gate (§3.2).
        guard let cm = snapshot.distanceCm else { return true }
        return cm >= 25 && cm <= 50
    }

    // Oblique-stage hard cap (closeout-trail Decision 1, tightening research
    // Req 3.3 / Decision 43): the SfS volume estimator runs off-envelope outside
    // |Δθ − 25°| ≤ 15°, so the oblique shutter stays disabled there even after
    // the nadir tilt gate was removed. The window was narrowed from ±30° to ±15°
    // after three device trails fired the oblique at ~50° and refused with
    // noFoodVolumeRecovered.
    private func obliqueTiltOk(degrees: Float) -> Bool {
        abs(degrees - 25) <= 15
    }

    // Retained for the gating log: indicates whether the *displayed* tilt is
    // within the σ_tilt > 0.95 auto-hide band (≈ Δθ < 18° from the per-stage
    // target). No longer used as a shutter gate; the field name is kept so
    // existing log subscribers continue to parse the same key.
    private func tiltInRange(degrees: Float) -> Bool {
        let target: Float = firstFrame != nil ? 25 : 0
        return LiveIndicatorBadgeState.isSigmaTiltSufficient(
            deltaThetaDegrees: abs(degrees - target)
        )
    }

    private func observeInterruptions(
        stream: AsyncStream<ARKitCaptureEngine.InterruptionEvent>
    ) {
        interruptionTask = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                self.handleInterruption(event)
            }
        }
    }

    // Builds a single space-separated `key=value` line for the shutter logger.
    // Fields match the smolspec Requirements list; an extra suffix is appended
    // verbatim for the `fired` event (mode + stage).
    fileprivate func gatingLog(event: String, extra: String? = nil) -> String {
        let target: Float = firstFrame != nil ? 25 : 0
        let tilt = indicators.liveTiltDegrees
        let dist = indicators.liveDistanceCm.map { String(format: "%.1f", $0) } ?? "nil"
        var line =
            "event=\(event) " +
            "state=\(state.logName) " +
            "tiltDegrees=\(String(format: "%.1f", tilt)) " +
            "tiltVec=[\(String(format: "%.1f", indicators.liveTiltVector.x)),\(String(format: "%.1f", indicators.liveTiltVector.y))] " +
            "targetTilt=\(Int(target)) " +
            "tiltInRange=\(tiltInRange(degrees: tilt)) " +
            "distanceCm=\(dist) " +
            "lidarCoveragePercent=\(String(format: "%.1f", indicators.liveLiDARCoveragePercent)) " +
            "supportsLiDAR=\(supportsLiDAR) " +
            "canShutter=\(canShutter) " +
            "flowTaskActive=\(flowTask != nil) " +
            "startTaskActive=\(startTask != nil)"
        if let extra { line += " " + extra }
        return line
    }
}

// Pre-shutter mask staleness computation (Req 1.2 / Decision 11). Mirrors the
// helper in PreShutterSegmenter so freshness is measured with the same clock
// the producer uses for `producedAt`.
private func millisecondsBetween(
    _ start: ContinuousClock.Instant,
    _ end: ContinuousClock.Instant
) -> Int {
    let d = end - start
    let comps = d.components
    return Int(comps.seconds * 1_000 + comps.attoseconds / 1_000_000_000_000_000)
}

private extension CaptureState {
    var logName: String {
        switch self {
        case .initialising: return "initialising"
        case .permissionDenied: return "permissionDenied"
        case .trackingLost: return "trackingLost"
        case .ready: return "ready"
        case .capturing: return "capturing"
        case .estimating: return "estimating"
        case .showingResult: return "showingResult"
        case .refused: return "refused"
        }
    }
}

private extension CaptureStage {
    var name: String {
        switch self {
        case .nadir: return "nadir"
        case .oblique: return "oblique"
        }
    }
}

// Record encoding for typed capture errors (snaq-parity Req 2.1): every case
// persists its real name, so a `sessionNotStarted` is distinguishable from a
// genuine internal error in the outcome log.
private extension CaptureError {
    var failureCaseName: String {
        switch self {
        case .lidarUnavailable: return "lidarUnavailable"
        case .sessionNotStarted: return "sessionNotStarted"
        case .captureFailed: return "captureFailed"
        case .worldTrackingDegraded: return "worldTrackingDegraded"
        case .releaseTimedOut: return "releaseTimedOut"
        }
    }

    var failurePayload: String? {
        if case .captureFailed(let message) = self { return message }
        return nil
    }
}

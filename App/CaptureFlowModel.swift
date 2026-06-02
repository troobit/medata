import AVFoundation
import CaptureKit
import CoreMotion
import Foundation
import Observation
import os
import Pipeline
import SwiftUI

// Resolves the persistent CaptureMode from UserDefaults; defaults to `.double`
// on first install (Decision 35). Defined at file scope (not on the @MainActor
// class) so it can be used as the default parameter for the @Sendable closure.
@Sendable
func defaultCaptureModeReader() -> CaptureMode {
    let raw = UserDefaults.standard.string(forKey: SettingsKeys.captureMode)
    return raw.flatMap(CaptureMode.init(rawValue:)) ?? .double
}

// Orchestrator for the capture flow per `specs/ui/design.md`. Owns the state
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

    private let session: CaptureSession
    private let pipeline: any PipelineEstimator
    private let store: (any PersistenceStore)?
    private let photoSaver: (any PhotoLibrarySaver)?
    private let databaseEdition: String
    private let paletteVersion: String
    private let cameraAuthorisation: @Sendable () -> AVAuthorizationStatus
    private let motionAvailable: @Sendable () -> Bool
    private let captureModeReader: @Sendable () -> CaptureMode

    private(set) var flowTask: Task<Void, Never>?
    private var interruptionTask: Task<Void, Never>?
    private var startTask: Task<Void, Never>?
    private var firstFrame: RawFrame?
    // Tilt-at-shutter (degrees from straight-down) for the nadir frame, captured
    // when the user taps the shutter on the first stage. Stamped onto the
    // CaptureResult per Decision 44 / task 86 so σ_tilt reflects the camera pose
    // at the moment the photo was taken, not at the moment the pipeline runs.
    private var firstFrameTiltDeg: Float?

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
        store: (any PersistenceStore)? = nil,
        photoSaver: (any PhotoLibrarySaver)? = nil,
        cameraAuthorisation: @escaping @Sendable () -> AVAuthorizationStatus = {
            AVCaptureDevice.authorizationStatus(for: .video)
        },
        motionAvailable: @escaping @Sendable () -> Bool = {
            CMMotionManager().isDeviceMotionAvailable
        },
        captureModeReader: @escaping @Sendable () -> CaptureMode = defaultCaptureModeReader
    ) {
        self.session = session
        self.pipeline = pipeline
        self.store = store
        self.photoSaver = photoSaver
        self.indicators = indicators
        self.supportsLiDAR = supportsLiDAR
        self.databaseEdition = databaseEdition
        self.paletteVersion = paletteVersion
        self.cameraAuthorisation = cameraAuthorisation
        self.motionAvailable = motionAvailable
        self.captureModeReader = captureModeReader

        evaluatePermissions()
        observeInterruptions(stream: interruptions)
    }

    // MARK: - Derived view state

    // Shutter is armed in .ready with the distance gate satisfied and no
    // capture / estimation in flight (§7.2). Tilt no longer gates the nadir
    // stage (Decision 18 / research Decision 43); the oblique stage retains a
    // hard cap of |Δθ − 25°| ≤ 30° (research Req 3.3).
    var canShutter: Bool {
        switch state {
        case .ready(let snapshot):
            guard distanceGateOK(snapshot) else { return false }
            if firstFrame != nil {
                return obliqueTiltOk(degrees: indicators.liveTiltDegrees)
            }
            return true
        default:
            return false
        }
    }

    // True iff the live tilt is within the oblique hard cap window
    // (research Req 3.3: |Δθ − 25°| ≤ 30°). Used both by `canShutter` and by
    // the inline above-shutter message that surfaces when the user is on the
    // oblique stage but outside the cap.
    var obliqueTiltMessage: String? {
        guard firstFrame != nil, case .ready = state else { return nil }
        if obliqueTiltOk(degrees: indicators.liveTiltDegrees) { return nil }
        return EstimationFailure.obliqueTiltOutOfRange.localisedMessage
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

    // Wraps the current refusal in an Identifiable surface so the bottom-sheet
    // refusal can bind to it via `.sheet(item:)` (Req §20.7 / Decision 16).
    // The `id` derives from the underlying failure so consecutive presentations
    // of the same failure don't trip SwiftUI's diffing. Setting `nil` clears
    // the refusal back into `.ready` via the standard tryAgain path.
    var refusal: ActiveRefusal? {
        get {
            if case let .refused(failure, stage) = state {
                return ActiveRefusal(failure: failure, retryStage: stage)
            }
            return nil
        }
        set {
            if newValue == nil, case .refused = state {
                // Swipe-down dismisses without state change (still .refused);
                // explicit retry uses `retry()` instead.
            }
        }
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

        // Pick up the persistent mode at the shutter tap and freeze it for the
        // rest of the flow (mid-session toggle changes are ignored).
        let mode = inFlightMode ?? captureModeReader()
        inFlightMode = mode

        let stage: CaptureStage = firstFrame != nil ? .oblique : .nadir
        log.info("\(self.gatingLog(event: "fired", extra: "mode=\(mode.rawValue) stage=\(stage.name)"), privacy: .public)")
        beginCapture(stage: stage, frozen: snapshot, mode: mode)
    }

    // Diagnostic for taps on the .disabled shutter. Does not mutate state.
    // Surfaces the auto-hidden indicator badge and emits one .info log line
    // with the full gating snapshot so a Console.app subscriber can see which
    // gate is blocking.
    func shutterBlockedTapped() {
        indicators.reveal()
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
        if retryStage == .nadir { firstFrame = nil; firstFrameTiltDeg = nil }
        let mode = inFlightMode ?? captureModeReader()
        inFlightMode = mode
        beginCapture(stage: retryStage, frozen: snapshot, mode: mode)
    }

    func dismissResult() {
        guard case .showingResult = state else { return }
        navigationPath = NavigationPath()
        firstFrame = nil; firstFrameTiltDeg = nil
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
                firstFrame = nil; firstFrameTiltDeg = nil
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

    // Tab-switch lifecycle per UI Req §1.7 / §18.7 (Decision 15). Mirrors
    // `scenePhaseChanged(.background)` for non-Photo tabs with one carve-out:
    // when the model is already in `.estimating`, the pipeline runs to
    // completion and the result is presented on the next return to Photo.
    // Permission-denied and refusal states are preserved across the switch so
    // the user finds the same surface when they come back.
    func tabSelectionChanged(to tab: AppTab) {
        if tab == .photo {
            // Re-arm the AR session on return. The non-Photo branch below
            // calls `session.stop()` and clears `startTask`; nothing in the
            // SwiftUI lifecycle restarts it (TabView retains views, so
            // ARPreviewView's `updateUIView` is not guaranteed to fire on
            // re-select). Calling `evaluatePermissions()` is idempotent — it
            // bails out on permission-denied and only spawns a fresh start
            // task when one is not already in flight.
            evaluatePermissions()
            return
        }
        switch state {
        case .estimating:
            // Let the pipeline finish; `flowTask` already routes the result
            // into `.showingResult(record)`. Release the engine in the
            // background (no AR session needed while we wait for the result).
            Task { [session] in try? await session.stop() }
            startTask = nil
        case .permissionDenied, .refused:
            // No engine to release (permission), or a banner the user will
            // return to (refused). Leave the state alone.
            return
        case .capturing:
            // Capture in flight but estimation hasn't started: cancel and
            // reset to the same baseline as backgrounding.
            cancelInFlight()
            firstFrame = nil; firstFrameTiltDeg = nil
            state = .initialising
            Task { [session] in try? await session.stop() }
            startTask = nil
        case .initialising, .ready, .trackingLost, .showingResult:
            firstFrame = nil; firstFrameTiltDeg = nil
            if case .estimating = state {} else { state = .initialising }
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
        trackingIsNormal: Bool
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
            writeIndicators(tiltDegrees, distanceCm, lidarCoveragePercent)
            state = .ready(snapshot)
        case .ready:
            writeIndicators(tiltDegrees, distanceCm, lidarCoveragePercent)
            state = .ready(snapshot)
        case .trackingLost where trackingIsNormal:
            writeIndicators(tiltDegrees, distanceCm, lidarCoveragePercent)
            state = .ready(snapshot)
        default:
            break
        }
    }

    private func writeIndicators(_ tilt: Float, _ distanceCm: Float?, _ coverage: Float) {
        indicators.liveTiltDegrees = tilt
        indicators.liveDistanceCm = distanceCm
        indicators.liveLiDARCoveragePercent = coverage
    }

    // Hook for the engine to report tracking degraded outside of an in-flight
    // capture. Distinct from the capture-time path which discards the frame.
    func trackingDegraded() {
        switch state {
        case .ready:
            state = .trackingLost
            firstFrame = nil; firstFrameTiltDeg = nil
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

    // MARK: - Internals

    func handleInterruption(_ event: ARKitCaptureEngine.InterruptionEvent) {
        switch event {
        case .began:
            cancelInFlight()
            firstFrame = nil; firstFrameTiltDeg = nil
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
        if startTask == nil {
            startTask = Task { [session] in try? await session.start() }
        }
    }

    private func beginCapture(stage: CaptureStage, frozen: GatingSnapshot, mode: CaptureMode) {
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

            // Two-view (Double) mode: after the nadir tap, stash the frame
            // and wait for the user to take the oblique tap.
            if stage == .nadir, mode == .double {
                firstFrame = frame
                firstFrameTiltDeg = tiltAtShutterDeg
                state = .ready(frozen)
                return
            }

            // Per Decision 44 the σ_tilt computation runs over the angular
            // deviation from each stage's target axis (0° for nadir, 25° for
            // oblique). We persist the raw angle (degrees from straight-down)
            // and let the pipeline convert to Δθ per stage.
            let nadirAngle = stage == .oblique ? (firstFrameTiltDeg ?? 0) : tiltAtShutterDeg
            let obliqueAngle: Float? = stage == .oblique ? tiltAtShutterDeg : nil

            let captureResult = CaptureResult(
                capturePath: mode.capturePath,
                lidar: LiDARStatus(
                    available: supportsLiDAR,
                    foodRegionCoveragePercent: frozen.lidarCoveragePercent
                ),
                nadirFrame: stage == .oblique ? (firstFrame ?? frame) : frame,
                obliqueFrame: stage == .oblique ? frame : nil,
                databaseEdition: databaseEdition,
                paletteVersion: paletteVersion,
                nadirAngleAtCaptureDeg: nadirAngle,
                obliqueAngleAtCaptureDeg: obliqueAngle
            )
            await runEstimation(captureResult: captureResult, mode: mode, retryStage: stage)
        } catch is CancellationError {
            return
        } catch CaptureError.worldTrackingDegraded {
            log.info("event=capture.end stage=\(stage.name, privacy: .public) success=false error=worldTrackingDegraded")
            state = .trackingLost
        } catch let failure as EstimationFailure {
            log.info("event=capture.end stage=\(stage.name, privacy: .public) success=false error=\(String(describing: failure), privacy: .public)")
            state = .refused(failure, retryStage: stage)
        } catch {
            log.info("event=capture.end stage=\(stage.name, privacy: .public) success=false error=\(String(describing: type(of: error)), privacy: .public)")
            state = .refused(.noScaleAvailable, retryStage: stage)
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
            firstFrame = nil; firstFrameTiltDeg = nil
            inFlightMode = nil
            lastMeal = stamped
            log.info("event=estimate.end success=true mealId=\(stamped.id.uuidString, privacy: .public) capturePath=\(captureResult.capturePath.rawValue, privacy: .public)")
            state = .showingResult(stamped)
            navigationPath.append(stamped)
        } catch is CancellationError {
            return
        } catch let failure as EstimationFailure {
            log.info("event=estimate.end success=false failure=\(String(describing: failure), privacy: .public)")
            guard case .estimating = state else { return }
            state = .refused(failure, retryStage: retryStage)
        } catch {
            log.info("event=estimate.end success=false error=\(String(describing: type(of: error)), privacy: .public)")
            guard case .estimating = state else { return }
            state = .refused(.noScaleAvailable, retryStage: retryStage)
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

    // Oblique-stage hard cap (research Req 3.3 / Decision 43): the SfS volume
    // estimator runs off-envelope outside |Δθ − 25°| ≤ 30°, so the oblique
    // shutter stays disabled there even after the nadir tilt gate was removed.
    private func obliqueTiltOk(degrees: Float) -> Bool {
        abs(degrees - 25) <= 30
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

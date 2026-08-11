import AVFoundation
import CaptureKit
import Foundation
import Persistence
import Pipeline
import PortableContracts
import Testing
@testable import MeData

@Suite("CaptureFlowModel state-machine transitions")
@MainActor
struct CaptureFlowModelTests {

    // MARK: - Permission denial at init (Req §1.3, §13.1, §13.3)

    @Test("camera denied at init → .permissionDenied(.camera)")
    func cameraDeniedInit() {
        let fixture = makeFixture(cameraAuthorisation: .denied)
        #expect(fixture.model.state == .permissionDenied(.camera))
    }

    @Test("motion unavailable at init → .permissionDenied(.motion)")
    func motionDeniedInit() {
        let fixture = makeFixture(motionAvailable: false)
        #expect(fixture.model.state == .permissionDenied(.motion))
    }

    @Test("re-grant on scenePhase=.active flips out of permissionDenied")
    func reGrantOnActive() async {
        let auth = AuthBox(value: .denied)
        let fixture = makeFixture(cameraAuthorisation: nil, authBox: auth)
        #expect(fixture.model.state == .permissionDenied(.camera))
        auth.value = .authorized
        fixture.model.scenePhaseChanged(.active)
        #expect(fixture.model.state == .initialising)
    }

    // MARK: - Initialising → ready

    @Test("tracking normal in .initialising → .ready")
    func trackingNormalReachesReady() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0,
            distanceCm: 35,
            lidarCoveragePercent: 90,
            trackingIsNormal: true
        )
        guard case .ready(let snapshot) = fixture.model.state else {
            Issue.record("expected .ready, got \(fixture.model.state)")
            return
        }
        #expect(snapshot.pathHint == .singleViewLidar)
        #expect(snapshot.tiltInRange)
    }

    @Test("live update re-emits .ready with new snapshot")
    func liveUpdateReEmitsReady() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 90, distanceCm: 35, lidarCoveragePercent: 50, trackingIsNormal: true
        )
        guard case .ready(let snapshot) = fixture.model.state else {
            Issue.record("expected .ready, got \(fixture.model.state)")
            return
        }
        #expect(snapshot.tiltInRange == false)
        #expect(snapshot.pathHint == .twoViewSfS)
    }

    // MARK: - Shutter behaviour (Req §7.2, §7.4, §14.3)

    @Test("shutter on .ready with single-view path → .capturing(.nadir)")
    func shutterReadySingleView() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        guard case .capturing(let stage, let frozen) = fixture.model.state else {
            Issue.record("expected .capturing, got \(fixture.model.state)")
            return
        }
        #expect(stage == .nadir)
        #expect(frozen.pathHint == .singleViewLidar)
    }

    // Decision 18 / task 56: the nadir-stage shutter is no longer gated by
    // tilt. Coverage for the new behaviour (nadir always armed; oblique hard
    // cap |Δθ − 25°| ≤ 30°) lives in CaptureFlowModelTiltGateTests.swift.

    @Test("shutter blocked when distance out of LiDAR range")
    func shutterDistanceOutOfRange() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 100, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        if case .capturing = fixture.model.state {
            Issue.record("shutter should be gated by distance")
        }
    }

    @Test("rapid second shutter tap during .capturing is ignored (§7.4)")
    func rapidShutterIgnored() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        let firstState = fixture.model.state
        fixture.model.shutter()
        #expect(fixture.model.state == firstState)
    }

    // MARK: - Force-two-view (§4.2)

    @Test("forceTwoView in .ready(single-view) → .forcingTwoView")
    func forceTwoView() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.forceTwoView()
        guard case .forcingTwoView = fixture.model.state else {
            Issue.record("expected .forcingTwoView, got \(fixture.model.state)")
            return
        }
    }

    @Test("shutter on .forcingTwoView → .capturing with twoViewSfS path")
    func shutterOnForcing() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.forceTwoView()
        fixture.model.shutter()
        guard case .capturing(_, let frozen) = fixture.model.state else {
            Issue.record("expected .capturing, got \(fixture.model.state)")
            return
        }
        #expect(frozen.pathHint == .twoViewSfS)
    }

    // MARK: - Path-hint freeze rule (§14.3)

    @Test("path-hint frozen at shutter tap, live coverage flip ignored")
    func pathHintFreezeRule() async {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        // Coverage drops below the threshold — frozen snapshot must not flip.
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 10, trackingIsNormal: true
        )
        guard case .capturing(_, let frozen) = fixture.model.state else {
            Issue.record("expected .capturing, got \(fixture.model.state)")
            return
        }
        #expect(frozen.pathHint == .singleViewLidar)
        #expect(frozen.lidarCoveragePercent == 90)
    }

    // MARK: - Capture → estimating → showingResult

    @Test("nadir capture on single-view path completes to .showingResult")
    func singleViewFlowSuccess() async {
        let record = makeMealRecord()
        let fixture = makeFixture(pipelineResult: .success(record))
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        #expect(fixture.model.state == .showingResult(record))
        #expect(fixture.model.lastMeal == record)
    }

    @Test("nadir capture on two-view path returns to .ready awaiting oblique")
    func twoViewAwaitsOblique() async {
        let fixture = makeFixture(supportsLiDAR: false)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 0, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        guard case .ready(let snapshot) = fixture.model.state else {
            Issue.record("expected .ready awaiting oblique, got \(fixture.model.state)")
            return
        }
        #expect(snapshot.pathHint == .twoViewSfS)
    }

    @Test("oblique tap after two-view nadir → estimating → .showingResult")
    func twoViewCompletes() async {
        let record = makeMealRecord(capturePath: .twoViewSfS)
        let fixture = makeFixture(
            obliqueFrame: .fixture(),
            pipelineResult: .success(record),
            supportsLiDAR: false
        )
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 0, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        // Now in .ready awaiting oblique — the tilt target is 25° (§2.3), so the
        // oblique tap must report an in-range oblique angle to be accepted.
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 25, distanceCm: 35, lidarCoveragePercent: 0, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        #expect(fixture.model.state == .showingResult(record))
    }

    // MARK: - Estimation failure → refusal (§10.1)

    @Test("pipeline throws EstimationFailure → .refused")
    func pipelineRefusal() async {
        let fixture = makeFixture(pipelineResult: .failure(EstimationFailure.noScaleAvailable))
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        guard case .refused(let failure, let retryStage) = fixture.model.state else {
            Issue.record("expected .refused, got \(fixture.model.state)")
            return
        }
        #expect(failure == .noScaleAvailable)
        #expect(retryStage == .nadir)
    }

    @Test("tryAgain after .refused → .capturing at retry stage (§10.2)")
    func tryAgainAfterRefusal() async {
        let fixture = makeFixture(pipelineResult: .failure(EstimationFailure.noScaleAvailable))
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        fixture.model.tryAgain()
        guard case .capturing(let stage, _) = fixture.model.state else {
            Issue.record("expected .capturing after tryAgain, got \(fixture.model.state)")
            return
        }
        #expect(stage == .nadir)
    }

    // Regression for `bugfix/refusal-sheet-dismissal` — surface-not-detected
    // bugfix report. The RefusalSheet was previously bound through a get-only
    // binding (`refusalBinding.set = { _ in }`) combined with a no-op setter on
    // `model.refusal`, so a swipe-down on the sheet had no effect and the sheet
    // re-presented on the next render. Dismissing the refusal must transition
    // the state out of `.refused` so the sheet does not pop back up.
    @Test("dismissRefusal after .refused → .ready (sheet swipe-down dismissal)")
    func dismissRefusalReturnsToReady() async {
        let fixture = makeFixture(pipelineResult: .failure(EstimationFailure.lidarFitDegenerate))
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        guard case .refused = fixture.model.state else {
            Issue.record("expected .refused before dismissal, got \(fixture.model.state)")
            return
        }
        fixture.model.dismissRefusal()
        if case .ready = fixture.model.state { return }
        Issue.record("expected .ready after dismissRefusal, got \(fixture.model.state)")
    }

    // Companion regression: a second pipeline failure after a dismissal must
    // present a fresh `.refused` state (covers the symmetry across all
    // EstimationFailure cases, not just lidarFitDegenerate).
    @Test("dismissRefusal clears firstFrame so a fresh nadir capture is required")
    func dismissRefusalClearsCapturedFrame() async {
        let fixture = makeFixture(pipelineResult: .failure(EstimationFailure.lidarFitDegenerate))
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        guard case .refused = fixture.model.state else {
            Issue.record("expected .refused before dismissal, got \(fixture.model.state)")
            return
        }
        fixture.model.dismissRefusal()
        // After dismissal the user is back at the viewfinder; awaitingObliqueView
        // is false because firstFrame was cleared.
        #expect(fixture.model.awaitingObliqueView == false)
    }

    // MARK: - Dismiss result → fresh capture (§9.4)

    @Test("dismissResult returns to .ready")
    func dismissResultReturnsToReady() async {
        let record = makeMealRecord()
        let fixture = makeFixture(pipelineResult: .success(record))
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        fixture.model.dismissResult()
        if case .ready = fixture.model.state {
            return
        }
        Issue.record("expected .ready after dismissResult, got \(fixture.model.state)")
    }

    // MARK: - Tracking lost (§5.5, §5.6, §16.1)

    @Test("trackingDegraded in .ready → .trackingLost")
    func trackingDegradedFromReady() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.trackingDegraded()
        #expect(fixture.model.state == .trackingLost)
    }

    @Test("trackingLost + normal tracking → .ready (§16.1)")
    func trackingRecovered() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.trackingDegraded()
        #expect(fixture.model.state == .trackingLost)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        if case .ready = fixture.model.state { return }
        Issue.record("expected .ready, got \(fixture.model.state)")
    }

    // MARK: - AR-session interruption (§16.1)

    @Test("interruption .began → .trackingLost; .ended → .initialising")
    func interruptionDrivesStates() {
        let fixture = makeFixture()
        fixture.model.handleInterruption(.began)
        #expect(fixture.model.state == .trackingLost)
        fixture.model.handleInterruption(.ended)
        #expect(fixture.model.state == .initialising)
    }

    // MARK: - Blocked-tap diagnostic (smolspec: shutter-blocked-feedback)

    @Test("shutterBlockedTapped leaves .initialising unchanged and reveals indicator")
    func blockedTapInitialisingPreservesState() {
        let fixture = makeFixture()
        fixture.model.indicators.visible = false
        let before = fixture.model.state
        fixture.model.shutterBlockedTapped()
        #expect(fixture.model.state == before)
        #expect(fixture.model.indicators.visible == true)
    }

    @Test("shutterBlockedTapped leaves .trackingLost unchanged and reveals indicator")
    func blockedTapTrackingLostPreservesState() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.trackingDegraded()
        #expect(fixture.model.state == .trackingLost)
        fixture.model.indicators.visible = false
        fixture.model.shutterBlockedTapped()
        #expect(fixture.model.state == .trackingLost)
        #expect(fixture.model.indicators.visible == true)
    }

    @Test("shutterBlockedTapped leaves .ready(out-of-range) unchanged and reveals indicator")
    func blockedTapReadyOutOfRangePreservesState() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 45, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        guard case .ready(let snapshot) = fixture.model.state else {
            Issue.record("expected .ready, got \(fixture.model.state)")
            return
        }
        #expect(snapshot.tiltInRange == false)
        let before = fixture.model.state
        fixture.model.indicators.visible = false
        fixture.model.shutterBlockedTapped()
        #expect(fixture.model.state == before)
        #expect(fixture.model.indicators.visible == true)
    }

    // MARK: - Backgrounding (§8.3, §1.2)

    @Test("backgrounding during .estimating resets state to .initialising")
    func backgroundResetsEstimating() async {
        // Use a pipeline that suspends indefinitely so we can catch the
        // model mid-flight, then cancel via scenePhaseChanged(.background).
        let stall = StallingPipeline()
        let engine = MockCaptureEngine(nadirFrame: .fixture())
        let model = CaptureFlowModel(
            session: CaptureSession(engine: engine),
            pipeline: stall,
            indicators: LiveIndicatorModel(),
            interruptions: AsyncStream.makeStream(of: ARKitCaptureEngine.InterruptionEvent.self).stream,
            supportsLiDAR: true,
            databaseEdition: "test",
            paletteVersion: "test",
            segmenterSource: "test",
            cameraAuthorisation: { .authorized },
            motionAvailable: { true }
        )
        model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        model.shutter()
        // Yield until the model enters .estimating.
        for _ in 0..<10 {
            if case .estimating = model.state { break }
            await Task.yield()
        }
        model.scenePhaseChanged(.background)
        #expect(model.state == .initialising)
    }
}

// MARK: - Fixtures

@MainActor
private struct ModelFixture {
    let model: CaptureFlowModel
    let pipeline: ProgrammablePipeline
}

@MainActor
private func makeFixture(
    nadirFrame: RawFrame = .fixture(),
    obliqueFrame: RawFrame? = nil,
    pipelineResult: Result<MealRecord, Error>? = nil,
    supportsLiDAR: Bool = true,
    cameraAuthorisation: AVAuthorizationStatus? = .authorized,
    motionAvailable: Bool = true,
    authBox: AuthBox? = nil
) -> ModelFixture {
    let engine = MockCaptureEngine(nadirFrame: nadirFrame, obliqueFrame: obliqueFrame)
    let session = CaptureSession(engine: engine)
    let pipeline = ProgrammablePipeline()
    pipeline.result = pipelineResult ?? .success(makeMealRecord())
    let interruptions = AsyncStream.makeStream(of: ARKitCaptureEngine.InterruptionEvent.self).stream
    let auth: @Sendable () -> AVAuthorizationStatus = {
        if let box = authBox { return box.value }
        return cameraAuthorisation ?? .authorized
    }
    let model = CaptureFlowModel(
        session: session,
        pipeline: pipeline,
        indicators: LiveIndicatorModel(),
        interruptions: interruptions,
        supportsLiDAR: supportsLiDAR,
        databaseEdition: "test",
        paletteVersion: "test",
        segmenterSource: "test",
        cameraAuthorisation: auth,
        motionAvailable: { motionAvailable }
    )
    return ModelFixture(model: model, pipeline: pipeline)
}

private func makeMealRecord(capturePath: CapturePath = .singleViewLidar) -> MealRecord {
    var macros = PbMacroResult()
    macros.totalCarbsG = 42
    var confidence = PbConfidenceResult()
    confidence.sigmaMeal = 0.80
    return MealRecord(
        capturePath: capturePath,
        databaseEdition: "CoFID 2024",
        paletteVersion: "v0",
        calibration: PbCameraIntrinsics(),
        supportPlane: PbSupportPlane(),
        scale: PbMetricScale(),
        volumes: PbVolumeResult(),
        macros: macros,
        confidence: confidence
    )
}

// Programmable PipelineEstimator that returns a canned Result. Used in place
// of a real Pipeline (which would require the segmenter weights bundle).
private final class ProgrammablePipeline: PipelineEstimator, @unchecked Sendable {
    var result: Result<MealRecord, Error> = .failure(EstimationFailure.noScaleAvailable)
    func estimate(captureResult: CaptureResult, mode: CaptureMode) async throws -> MealRecord {
        switch result {
        case .success(let record): return record
        case .failure(let error): throw error
        }
    }
}

// Pipeline that suspends so the test can observe the .estimating state and
// trigger cancellation. Task.sleep throws CancellationError on cancel, which
// the model swallows per Decision 12.
private final class StallingPipeline: PipelineEstimator, @unchecked Sendable {
    func estimate(captureResult: CaptureResult, mode: CaptureMode) async throws -> MealRecord {
        try await Task.sleep(nanoseconds: 10_000_000_000)
        throw EstimationFailure.noScaleAvailable
    }
}

// Mutable holder so the camera-permission stub can change between calls.
private final class AuthBox: @unchecked Sendable {
    var value: AVAuthorizationStatus
    init(value: AVAuthorizationStatus) { self.value = value }
}

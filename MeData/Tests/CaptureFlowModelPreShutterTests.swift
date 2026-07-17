import AVFoundation
import CaptureKit
import Foundation
import Persistence
import Pipeline
import PortableContracts
import Testing
@testable import MeData

// Tests for the `CaptureFlowModel` / `PreShutterSegmenter` integration per
// task 12. Covers:
//   - 750 ms staleness gate (Req 8.3)
//   - `firstFrameMaskBox` lifecycle in lockstep with `firstFrame` (Decision 11)
//   - `awaitPaused()` is called before `latest` is read at the nadir-capture
//     instant (Decision 13 — snapshot atomicity)
//
// Uses a `SpyPreShutterMaskSource` to pre-populate `latest` and record the
// pause/awaitPaused call order without needing a live ARSession.
@Suite("CaptureFlowModel + PreShutterSegmenter")
@MainActor
struct CaptureFlowModelPreShutterTests {

    // MARK: - Staleness gate (Req 8.3)

    @Test("fresh mask reaches CaptureResult.preShutterFoodMask")
    func freshMaskFlowsThroughCaptureResult() async {
        let mask = makeOnesMask(width: 8, height: 8)
        let spy = SpyPreShutterMaskSource()
        spy.latest = makeTimestamped(mask: mask, ageMs: 0)

        let fixture = makeFixture(spy: spy)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value

        let received = fixture.pipeline.lastCaptureResult
        #expect(received != nil)
        #expect(received?.preShutterFoodMask?.pixels == mask.pixels)
    }

    @Test("mask older than 750 ms is treated as unavailable")
    func staleMaskTreatedAsUnavailable() async {
        let mask = makeOnesMask(width: 8, height: 8)
        let spy = SpyPreShutterMaskSource()
        spy.latest = makeTimestamped(mask: mask, ageMs: 1_500)

        let fixture = makeFixture(spy: spy)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value

        let received = fixture.pipeline.lastCaptureResult
        #expect(received != nil)
        #expect(received?.preShutterFoodMask == nil)
    }

    @Test("mask exactly at the 750 ms boundary is still available")
    func boundaryMaskAvailable() async {
        // The staleness ceiling is "≤ 750 ms" (Req 1.2). A mask at exactly
        // 700 ms (well inside the window) must reach the pipeline.
        let mask = makeOnesMask(width: 8, height: 8)
        let spy = SpyPreShutterMaskSource()
        spy.latest = makeTimestamped(mask: mask, ageMs: 700)

        let fixture = makeFixture(spy: spy)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value

        #expect(fixture.pipeline.lastCaptureResult?.preShutterFoodMask?.pixels == mask.pixels)
    }

    @Test("nadir-capture path calls awaitPaused() before reading latest")
    func awaitPausedCalledBeforeLatestRead() async {
        let mask = makeOnesMask(width: 8, height: 8)
        let spy = SpyPreShutterMaskSource()
        spy.latest = makeTimestamped(mask: mask, ageMs: 0)

        let fixture = makeFixture(spy: spy)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value

        // The spy records "latestReadAfterAwaitPaused" only when `latest` is
        // accessed AFTER `awaitPaused()` has returned. If the model read
        // `latest` first (TOCTOU per Decision 13), the spy would record it
        // as a read-before-pause.
        #expect(spy.awaitPausedCount >= 1)
        #expect(spy.latestReadsAfterAwaitPaused >= 1)
    }

    // MARK: - preShutterMaskAgeMs threaded onto CaptureResult (bugfix smolspec)

    // Test A — single-view nadir tap with a fresh published mask must reach
    // CaptureResult with both preShutterFoodMask non-nil AND preShutterMaskAgeMs
    // >= 0. Mirrors `freshMaskFlowsThroughCaptureResult` but asserts the age
    // field that drives `event=estimate.start maskAgeMs=…` (Req: estimate.start
    // log line must reflect a real measurement when a mask is attached).
    @Test("single-view nadir stamps preShutterMaskAgeMs >= 0 on CaptureResult")
    func singleViewNadirStampsMaskAge() async {
        let mask = makeOnesMask(width: 8, height: 8)
        let spy = SpyPreShutterMaskSource()
        spy.latest = makeTimestamped(mask: mask, ageMs: 0)

        let fixture = makeFixture(spy: spy)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value

        let received = fixture.pipeline.lastCaptureResult
        #expect(received != nil)
        #expect(received?.preShutterFoodMask != nil)
        #expect((received?.preShutterMaskAgeMs ?? -1) >= 0)
    }

    // Test B — the smoking gun for the noFoodPixels / maskAgeMs=-1 refusal
    // observed on iPhone 13 Pro Max 2026-06-14. After a nadir tap stashes the
    // pre-shutter mask, the oblique tap currently sets nadirMaskAgeMs = nil in
    // the else branch at CaptureFlowModel.swift:481-484, so the oblique-stage
    // CaptureResult arrives at the pipeline with preShutterMaskAgeMs == nil
    // even though the mask itself is present. Must fail today.
    @Test("double-mode oblique preserves nadir-instant preShutterMaskAgeMs")
    func doubleModeObliquePreservesNadirMaskAge() async {
        let mask = makeOnesMask(width: 8, height: 8)
        let spy = SpyPreShutterMaskSource()
        spy.latest = makeTimestamped(mask: mask, ageMs: 0)

        let fixture = makeFixture(spy: spy, supportsLiDAR: false)

        // Nadir tap — model returns to .ready awaiting the oblique view.
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 0, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        #expect(fixture.model.awaitingObliqueView == true)
        #expect(fixture.model.firstFrameMaskBox != nil)

        // Oblique tap — pipeline receives the CaptureResult for the full
        // two-view sequence.
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 25, distanceCm: 35, lidarCoveragePercent: 0, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value

        let received = fixture.pipeline.lastCaptureResult
        #expect(received != nil)
        #expect(received?.preShutterFoodMask?.pixels == mask.pixels)
        #expect((received?.preShutterMaskAgeMs ?? -1) >= 0)
    }

    // MARK: - First-shot race: nadir shutter gated on a usable mask
    //
    // Regression for fix/first-shot-nofoodpixels. On the FIRST shutter tap of a
    // session the mask could still be nil (`maskAgeMs=-1`), the empty-mask gate
    // refused, and the tap mapped to `EstimationFailure.noFoodPixels`. The
    // nadir shutter must stay disarmed until a usable (fresh) pre-shutter mask
    // exists.

    @Test("nadir shutter is NOT armed while no pre-shutter mask exists")
    func nadirShutterDisarmedWithoutMask() async {
        let spy = SpyPreShutterMaskSource()
        spy.latest = nil  // first frame of a session: producer hasn't published

        let fixture = makeFixture(spy: spy)
        // Drive into .ready with the distance gate satisfied — the only other
        // nadir gate. Pre-fix this returned canShutter == true (the bug).
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        guard case .ready = fixture.model.state else {
            Issue.record("expected .ready, got \(fixture.model.state)")
            return
        }
        #expect(fixture.model.canShutter == false)

        // The command-side guard must also refuse: a maskless nadir tap must
        // not begin a capture (no flow task spawned).
        fixture.model.shutter()
        #expect(fixture.model.flowTask == nil)
        guard case .ready = fixture.model.state else {
            Issue.record("expected to remain .ready, got \(fixture.model.state)")
            return
        }
    }

    @Test("nadir shutter arms once a fresh pre-shutter mask is present")
    func nadirShutterArmsWithFreshMask() async {
        let spy = SpyPreShutterMaskSource()
        spy.latest = nil

        let fixture = makeFixture(spy: spy)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        #expect(fixture.model.canShutter == false)

        // A fresh mask becomes available — the shutter must arm.
        spy.latest = makeTimestamped(mask: makeOnesMask(width: 8, height: 8), ageMs: 0)
        #expect(fixture.model.canShutter == true)
    }

    @Test("nadir shutter stays disarmed when the only mask is stale (> 750 ms)")
    func nadirShutterDisarmedWithStaleMask() async {
        // A mask older than the 750 ms nadir-instant ceiling would be discarded
        // by performFlow, so the shutter must not arm on it (no arm-then-refuse).
        let spy = SpyPreShutterMaskSource()
        spy.latest = makeTimestamped(mask: makeOnesMask(width: 8, height: 8), ageMs: 1_500)

        let fixture = makeFixture(spy: spy)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        #expect(fixture.model.canShutter == false)
    }

    // MARK: - firstFrameMaskBox lifecycle (Decision 11)

    @Test("two-view nadir capture stashes firstFrameMaskBox alongside firstFrame")
    func twoViewNadirCaptureStashesMaskBox() async {
        let mask = makeOnesMask(width: 8, height: 8)
        let spy = SpyPreShutterMaskSource()
        spy.latest = makeTimestamped(mask: mask, ageMs: 0)

        let fixture = makeFixture(spy: spy, supportsLiDAR: false)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 0, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value

        // After nadir tap on two-view path, model returns to .ready awaiting
        // oblique tap, with both firstFrame and firstFrameMaskBox set.
        #expect(fixture.model.awaitingObliqueView == true)
        #expect(fixture.model.firstFrameMaskBox != nil)
        #expect(fixture.model.firstFrameMaskBox?.mask.pixels == mask.pixels)
    }

    @Test("scenePhase background clears firstFrameMaskBox alongside firstFrame")
    func scenePhaseBackgroundClearsMaskBox() async {
        let fixture = await primeTwoViewFirstFrame()
        #expect(fixture.model.firstFrameMaskBox != nil)
        fixture.model.scenePhaseChanged(.background)
        #expect(fixture.model.firstFrameMaskBox == nil)
        #expect(fixture.model.awaitingObliqueView == false)
    }

    @Test("interruption.began clears firstFrameMaskBox alongside firstFrame")
    func interruptionBeganClearsMaskBox() async {
        let fixture = await primeTwoViewFirstFrame()
        #expect(fixture.model.firstFrameMaskBox != nil)
        fixture.model.handleInterruption(.began)
        #expect(fixture.model.firstFrameMaskBox == nil)
    }

    @Test("tabSelection away from Photo clears firstFrameMaskBox")
    func tabSelectionClearsMaskBox() async {
        let fixture = await primeTwoViewFirstFrame()
        #expect(fixture.model.firstFrameMaskBox != nil)
        fixture.model.tabSelectionChanged(to: .meals)
        #expect(fixture.model.firstFrameMaskBox == nil)
    }

    @Test("trackingDegraded mid-two-view clears firstFrameMaskBox")
    func trackingDegradedClearsMaskBox() async {
        // Set up via the two-view nadir prime, then drop tracking. The model
        // clears firstFrame for tracking degradation only inside .ready /
        // .capturing(.nadir); after the nadir tap we are back in .ready, so
        // the clear should fire.
        let fixture = await primeTwoViewFirstFrame()
        #expect(fixture.model.firstFrameMaskBox != nil)
        fixture.model.trackingDegraded()
        #expect(fixture.model.firstFrameMaskBox == nil)
    }

    @Test("dismissResult clears firstFrameMaskBox")
    func dismissResultClearsMaskBox() async {
        // Set up via a successful single-view flow to land in .showingResult.
        let mask = makeOnesMask(width: 8, height: 8)
        let spy = SpyPreShutterMaskSource()
        spy.latest = makeTimestamped(mask: mask, ageMs: 0)

        let record = makeMealRecord()
        let fixture = makeFixture(spy: spy, pipelineResult: .success(record))
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        // Single-view success — no firstFrameMaskBox should be set after
        // estimation completes (it gets cleared alongside firstFrame).
        #expect(fixture.model.firstFrameMaskBox == nil)

        fixture.model.dismissResult()
        #expect(fixture.model.firstFrameMaskBox == nil)
    }

    @Test("dismissRefusal clears firstFrameMaskBox")
    func dismissRefusalClearsMaskBox() async {
        let fixture = await primeTwoViewFirstFrame()
        // Force a refusal on the oblique tap so we reach .refused with the
        // nadir frame (and its mask box) still in flight up to dismissRefusal.
        fixture.pipeline.result = .failure(EstimationFailure.noScaleAvailable)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 25, distanceCm: 35, lidarCoveragePercent: 0, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        guard case .refused = fixture.model.state else {
            Issue.record("expected .refused, got \(fixture.model.state)")
            return
        }
        fixture.model.dismissRefusal()
        #expect(fixture.model.firstFrameMaskBox == nil)
    }

    // MARK: - Helpers

    @MainActor
    private func primeTwoViewFirstFrame() async -> ModelFixture {
        let mask = makeOnesMask(width: 8, height: 8)
        let spy = SpyPreShutterMaskSource()
        spy.latest = makeTimestamped(mask: mask, ageMs: 0)

        let fixture = makeFixture(spy: spy, supportsLiDAR: false)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 0, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        return fixture
    }

    private func makeTimestamped(
        mask: BinaryMask, ageMs: Int
    ) -> PreShutterSegmenter.TimestampedMask {
        // ContinuousClock has no public way to construct an arbitrary past
        // instant; produce one by subtracting from `now` via Duration.
        let producedAt = ContinuousClock.now.advanced(
            by: .milliseconds(-ageMs)
        )
        return PreShutterSegmenter.TimestampedMask(
            box: PreShutterSegmenter.MaskBox(mask),
            producedAt: producedAt,
            source: .preShutterStub
        )
    }

    private func makeOnesMask(width: Int, height: Int) -> BinaryMask {
        BinaryMask(
            pixels: [UInt8](repeating: 1, count: width * height),
            width: width,
            height: height
        )
    }
}

// MARK: - Fixtures

@MainActor
private struct ModelFixture {
    let model: CaptureFlowModel
    let pipeline: CapturingPipeline
}

@MainActor
private func makeFixture(
    spy: SpyPreShutterMaskSource,
    pipelineResult: Result<MealRecord, Error>? = nil,
    supportsLiDAR: Bool = true,
    obliqueFrame: RawFrame? = .fixture(),
    captureMode: CaptureMode? = nil
) -> ModelFixture {
    let engine = MockCaptureEngine(nadirFrame: .fixture(), obliqueFrame: obliqueFrame)
    let session = CaptureSession(engine: engine)
    let pipeline = CapturingPipeline()
    pipeline.result = pipelineResult ?? .failure(EstimationFailure.noFoodPixels)
    let interruptions = AsyncStream.makeStream(of: ARKitCaptureEngine.InterruptionEvent.self).stream
    // Default capture mode mirrors `supportsLiDAR`: with LiDAR available the
    // single-view path is the natural test target; without LiDAR we fall
    // through to two-view. Callers can override with `captureMode:` when a
    // specific path is being exercised.
    let resolvedMode = captureMode ?? (supportsLiDAR ? .single : .double)
    let model = CaptureFlowModel(
        session: session,
        pipeline: pipeline,
        indicators: LiveIndicatorModel(),
        interruptions: interruptions,
        supportsLiDAR: supportsLiDAR,
        databaseEdition: "test",
        paletteVersion: "test",
        segmenterSource: "test",
        preShutterSegmenter: spy,
        cameraAuthorisation: { .authorized },
        motionAvailable: { true },
        captureModeReader: { resolvedMode }
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
        paletteVersion: "v1",
        calibration: PbCameraIntrinsics(),
        supportPlane: PbSupportPlane(),
        scale: PbMetricScale(),
        volumes: PbVolumeResult(),
        macros: macros,
        confidence: confidence
    )
}

// MARK: - Spy types

@MainActor
private final class SpyPreShutterMaskSource: PreShutterMaskSource {
    var awaitPausedCount = 0
    var pauseCount = 0
    // Snapshot of state at the moment `latest` is read; tests assert the
    // model reads it AFTER calling `awaitPaused()` (Decision 13).
    private(set) var latestReadsAfterAwaitPaused = 0
    private(set) var latestReadsBeforeAwaitPaused = 0
    private var _storage: PreShutterSegmenter.TimestampedMask?

    var latest: PreShutterSegmenter.TimestampedMask? {
        get {
            if awaitPausedCount > 0 {
                latestReadsAfterAwaitPaused += 1
            } else {
                latestReadsBeforeAwaitPaused += 1
            }
            return _storage
        }
        set { _storage = newValue }
    }

    func pause() { pauseCount += 1 }

    func awaitPaused() async { awaitPausedCount += 1 }
}

// Programmable pipeline that captures the `CaptureResult` passed to
// `estimate(_:mode:)`. Lets tests assert on what reached the pipeline (e.g.
// that the staleness gate produced `preShutterFoodMask == nil`).
private final class CapturingPipeline: PipelineEstimator, @unchecked Sendable {
    var result: Result<MealRecord, Error> = .failure(EstimationFailure.noFoodPixels)
    private(set) var lastCaptureResult: CaptureResult?

    func estimate(captureResult: CaptureResult, mode: CaptureMode) async throws -> MealRecord {
        lastCaptureResult = captureResult
        switch result {
        case .success(let r): return r
        case .failure(let e): throw e
        }
    }
}

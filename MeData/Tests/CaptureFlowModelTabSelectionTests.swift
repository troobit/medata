import AVFoundation
import CaptureKit
import Foundation
import Persistence
import Pipeline
import PortableContracts
import Testing
@testable import MeData

// Tests for v1.1 `CaptureFlowModel.tabSelectionChanged(to:)` per UI Req §1.7 /
// §18.7 (task 38). Mirrors `scenePhaseChanged(.background)` for non-Photo
// tabs, with a carve-out for `.estimating`: the pipeline runs to completion
// so the result lands when the user returns to the Photo tab.
@Suite("CaptureFlowModel.tabSelectionChanged — non-Photo tabs")
@MainActor
struct CaptureFlowModelTabSelectionTests {

    @Test("switching away from Photo while .ready resets to .initialising")
    func switchAwayFromReadyResetsModel() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        if case .ready = fixture.model.state {} else {
            Issue.record("expected .ready, got \(fixture.model.state)")
            return
        }
        fixture.model.tabSelectionChanged(to: .meals)
        #expect(fixture.model.state == .initialising)
    }

    @Test("switching back to Photo does not change state from .initialising")
    func returningToPhotoLeavesInitialising() {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.tabSelectionChanged(to: .meals)
        fixture.model.tabSelectionChanged(to: .photo)
        #expect(fixture.model.state == .initialising)
    }

    @Test("switching away during .estimating does NOT cancel the pipeline (Req §1.7, §18.7)")
    func switchAwayDuringEstimatingPreservesPipeline() async {
        let record = makeMealRecord()
        let fixture = makeFixture(pipelineResult: .success(record))
        let pipeline = SlowPipeline(record: record, delayNs: 100_000_000)
        let model = makeModel(pipeline: pipeline)
        model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        model.shutter()
        // Yield until estimating starts.
        for _ in 0 ..< 50 {
            if case .estimating = model.state { break }
            await Task.yield()
        }
        if case .estimating = model.state {} else {
            Issue.record("expected .estimating, got \(model.state)")
            _ = fixture
            return
        }

        model.tabSelectionChanged(to: .meals)
        // The pipeline should still run; the result lands so a Photo-tab
        // re-entry sees `.showingResult(record)`.
        await model.flowTask?.value
        #expect(model.lastMeal == record)
        if case .showingResult = model.state {} else {
            Issue.record("expected .showingResult after pipeline completes, got \(model.state)")
        }
        _ = fixture
    }

    @Test("switching away while .permissionDenied is a no-op")
    func permissionDeniedNoOp() {
        let fixture = makeFixture(cameraAuthorisation: .denied)
        #expect(fixture.model.state == .permissionDenied(.camera))
        fixture.model.tabSelectionChanged(to: .meals)
        #expect(fixture.model.state == .permissionDenied(.camera))
    }

    @Test("switching away while .refused leaves the refusal alone")
    func refusedNoOp() async {
        let fixture = makeFixture(pipelineResult: .failure(EstimationFailure.noScaleAvailable))
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        guard case .refused = fixture.model.state else {
            Issue.record("expected .refused, got \(fixture.model.state)")
            return
        }
        fixture.model.tabSelectionChanged(to: .meals)
        guard case .refused = fixture.model.state else {
            Issue.record("refused state must persist across tab switch, got \(fixture.model.state)")
            return
        }
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
    pipelineResult: Result<MealRecord, Error>? = nil,
    cameraAuthorisation: AVAuthorizationStatus = .authorized
) -> ModelFixture {
    let engine = MockCaptureEngine(nadirFrame: .fixture())
    let session = CaptureSession(engine: engine)
    let pipeline = ProgrammablePipeline()
    pipeline.result = pipelineResult ?? .success(makeMealRecord())
    let interruptions = AsyncStream.makeStream(of: ARKitCaptureEngine.InterruptionEvent.self).stream
    let model = CaptureFlowModel(
        session: session,
        pipeline: pipeline,
        indicators: LiveIndicatorModel(),
        interruptions: interruptions,
        supportsLiDAR: true,
        databaseEdition: "test",
        paletteVersion: "test",
        cameraAuthorisation: { cameraAuthorisation },
        motionAvailable: { true }
    )
    return ModelFixture(model: model, pipeline: pipeline)
}

@MainActor
private func makeModel(pipeline: any PipelineEstimator) -> CaptureFlowModel {
    let engine = MockCaptureEngine(nadirFrame: .fixture())
    let session = CaptureSession(engine: engine)
    let interruptions = AsyncStream.makeStream(of: ARKitCaptureEngine.InterruptionEvent.self).stream
    return CaptureFlowModel(
        session: session,
        pipeline: pipeline,
        indicators: LiveIndicatorModel(),
        interruptions: interruptions,
        supportsLiDAR: true,
        databaseEdition: "test",
        paletteVersion: "test",
        cameraAuthorisation: { .authorized },
        motionAvailable: { true }
    )
}

private func makeMealRecord() -> MealRecord {
    var macros = PbMacroResult()
    macros.totalCarbsG = 42
    var confidence = PbConfidenceResult()
    confidence.sigmaMeal = 0.80
    return MealRecord(
        capturePath: .singleViewLidar,
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

private final class ProgrammablePipeline: PipelineEstimator, @unchecked Sendable {
    var result: Result<MealRecord, Error> = .failure(EstimationFailure.noScaleAvailable)
    func estimate(captureResult: CaptureResult) async throws -> MealRecord {
        switch result {
        case .success(let record): return record
        case .failure(let error): throw error
        }
    }
}

private final class SlowPipeline: PipelineEstimator, @unchecked Sendable {
    let record: MealRecord
    let delayNs: UInt64
    init(record: MealRecord, delayNs: UInt64) {
        self.record = record
        self.delayNs = delayNs
    }
    func estimate(captureResult: CaptureResult) async throws -> MealRecord {
        // Deliberately NOT cancellable: tab-switch must NOT abort the work.
        let deadline = ContinuousClock.now.advanced(by: .nanoseconds(Int64(delayNs)))
        while ContinuousClock.now < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return record
    }
}

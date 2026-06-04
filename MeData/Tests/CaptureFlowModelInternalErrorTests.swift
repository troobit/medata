import AVFoundation
import CaptureKit
import Foundation
import Pipeline
import PortableContracts
import Testing
@testable import MeData

// Task 6 / flow-catch-all-test (red baseline) → Task 7 / flow-catch-all-impl
// (green). Locks Req 6.5 of `specs/rawframe-rgb-conversion/`: a non-typed error
// thrown by the injected pipeline must surface as `.refused(.internalError(typeName))`
// — never as `.refused(.noScaleAvailable)`, which would borrow the scale-error
// label for an unrelated failure (the 2026-06-04 device-log incident).
@Suite("CaptureFlowModel catch-all routes to .internalError")
@MainActor
struct CaptureFlowModelInternalErrorTests {

    @Test("non-EstimationFailure pipeline error → .refused(.internalError(typeName))")
    func nonTypedErrorRoutesToInternalError() async {
        let fixture = makeFixture(
            pipelineResult: .failure(TestErrorType.synthetic)
        )
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value

        guard case let .refused(failure, retryStage) = fixture.model.state else {
            Issue.record("expected .refused, got \(fixture.model.state)")
            return
        }
        #expect(retryStage == .nadir)
        // Negative assertion (Req 6.5): the catch-all must NOT borrow the
        // scale label for a non-scale failure.
        #expect(failure != .noScaleAvailable,
                "untyped pipeline errors must not be mapped to .noScaleAvailable")
        // Positive assertion: failure is `.internalError("TestErrorType")`.
        guard case let .internalError(typeName) = failure else {
            Issue.record("expected .internalError, got \(failure)")
            return
        }
        #expect(typeName == "TestErrorType")
    }
}

// MARK: - Test doubles

private enum TestErrorType: Error {
    case synthetic
}

@MainActor
private struct ModelFixture {
    let model: CaptureFlowModel
}

@MainActor
private func makeFixture(
    pipelineResult: Result<MealRecord, Error>
) -> ModelFixture {
    let engine = MockCaptureEngine(nadirFrame: .fixture())
    let session = CaptureSession(engine: engine)
    let pipeline = ProgrammablePipeline()
    pipeline.result = pipelineResult
    let interruptions = AsyncStream.makeStream(of: ARKitCaptureEngine.InterruptionEvent.self).stream
    let model = CaptureFlowModel(
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
    return ModelFixture(model: model)
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

import AVFoundation
import CaptureKit
import Foundation
import Persistence
import Pipeline
import PortableContracts
import Testing
@testable import MeData

// Task 56 / Decision 18 / research Decision 43 / closeout-trail Decision 1. The
// nadir-stage shutter is no longer gated by tilt — any Δθ from straight-down
// produces a valid capture. The oblique stage retains a hard cap
// (|Δθ − 25°| ≤ 15°, tightened from ±30°) because the SfS volume estimator falls
// off-envelope outside that window and device trails overshot the ±30° band.
@Suite("CaptureFlowModel — tilt gate (nadir always armed; oblique hard cap)")
@MainActor
struct CaptureFlowModelTiltGateTests {

    // MARK: - Nadir stage: no tilt gate at all (Decision 18)

    @Test(
        "nadir-stage shutter is enabled at Δθ = 0°, 15°, 30°, 60°",
        arguments: [Float(0), 15, 30, 60]
    )
    func nadirShutterArmedAtAnyTilt(tilt: Float) {
        let fixture = makeFixture()
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: tilt, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true
        )
        #expect(fixture.model.canShutter)
        fixture.model.shutter()
        if case .ready = fixture.model.state {
            Issue.record("expected .capturing/.estimating after shutter at Δθ=\(tilt)°")
        }
    }

    // MARK: - Oblique-stage hard cap (research Req 3.3 / Decision 43)

    @Test(
        "oblique-stage shutter is disabled when |Δθ − 25°| > 15°",
        arguments: [Float(0), 45, 60, 90]
    )
    func obliqueShutterDisabledOutsideCap(tilt: Float) async {
        // Push the model to the awaiting-oblique state by completing a nadir
        // capture under two-view mode (no LiDAR forces two-view).
        let fixture = makeFixture(supportsLiDAR: false)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 0, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value
        #expect(fixture.model.awaitingObliqueView)

        fixture.model.liveSampleDidUpdate(
            tiltDegrees: tilt, distanceCm: 35, lidarCoveragePercent: 0, trackingIsNormal: true
        )
        #expect(!fixture.model.canShutter)
        #expect(fixture.model.obliqueTiltMessage != nil)
    }

    @Test(
        "oblique-stage shutter is enabled inside the ±15° cap",
        arguments: [Float(10), 25, 40]
    )
    func obliqueShutterArmedInsideCap(tilt: Float) async {
        let fixture = makeFixture(supportsLiDAR: false)
        fixture.model.liveSampleDidUpdate(
            tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 0, trackingIsNormal: true
        )
        fixture.model.shutter()
        await fixture.model.flowTask?.value

        fixture.model.liveSampleDidUpdate(
            tiltDegrees: tilt, distanceCm: 35, lidarCoveragePercent: 0, trackingIsNormal: true
        )
        #expect(fixture.model.canShutter)
        #expect(fixture.model.obliqueTiltMessage == nil)
    }

    // MARK: - Failure copy

    @Test("EstimationFailure.obliqueTiltOutOfRange surfaces the 25° guidance copy")
    func obliqueFailureCopy() {
        #expect(
            EstimationFailure.obliqueTiltOutOfRange.localisedMessage ==
            "Tilt the camera closer to 25° for the angled view."
        )
    }
}

// MARK: - Fixture (mirrors CaptureFlowModelTests but trimmed to what this suite needs)

@MainActor
private struct Fixture {
    let model: CaptureFlowModel
}

@MainActor
private func makeFixture(
    supportsLiDAR: Bool = true
) -> Fixture {
    let engine = MockCaptureEngine(nadirFrame: .fixture(), obliqueFrame: .fixture())
    let session = CaptureSession(engine: engine)
    let pipeline = StubPipeline()
    let model = CaptureFlowModel(
        session: session,
        pipeline: pipeline,
        indicators: LiveIndicatorModel(),
        interruptions: AsyncStream.makeStream(of: ARKitCaptureEngine.InterruptionEvent.self).stream,
        supportsLiDAR: supportsLiDAR,
        databaseEdition: "test",
        paletteVersion: "test",
        segmenterSource: "test",
        cameraAuthorisation: { .authorized },
        motionAvailable: { true },
        captureModeReader: { supportsLiDAR ? .single : .double }
    )
    return Fixture(model: model)
}

private final class StubPipeline: PipelineEstimator, @unchecked Sendable {
    func estimate(captureResult: CaptureResult, mode: CaptureMode) async throws -> MealRecord {
        var macros = PbMacroResult()
        macros.totalCarbsG = 30
        var confidence = PbConfidenceResult()
        confidence.sigmaMeal = 0.8
        return MealRecord(
            capturePath: mode.capturePath,
            databaseEdition: "test",
            paletteVersion: "v0",
            calibration: PbCameraIntrinsics(),
            supportPlane: PbSupportPlane(),
            scale: PbMetricScale(),
            volumes: PbVolumeResult(),
            macros: macros,
            confidence: confidence
        )
    }
}

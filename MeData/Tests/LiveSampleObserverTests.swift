import ARKit
import CaptureKit
import CoreVideo
import Foundation
import Pipeline
import PortableContracts
import simd
import Testing
@testable import MeData

@Suite("LiveSampleObserver per-frame maths and write-gating")
@MainActor
struct LiveSampleObserverTests {

    // MARK: - Tilt (Req §2.1)

    @Test("camera pointing straight down → 0° tilt")
    func tiltStraightDown() {
        // forward = (0,-1,0) ⇒ column 2 (backward) = (0,1,0)
        let m = matrix(column2: simd_float4(0, 1, 0, 0))
        let tilt = LiveSampleMath.tiltDegrees(worldFromCamera: m)
        #expect(abs(tilt - 0) < 0.5)
    }

    @Test("camera pointing at the horizon → 90° tilt")
    func tiltHorizontal() {
        // forward = (0,0,-1) ⇒ column 2 = (0,0,1)
        let m = matrix(column2: simd_float4(0, 0, 1, 0))
        let tilt = LiveSampleMath.tiltDegrees(worldFromCamera: m)
        #expect(abs(tilt - 90) < 0.5)
    }

    @Test("camera at ~25° off vertical → ~25° tilt")
    func tiltOblique() {
        let rad = Float(25) * .pi / 180
        // forward tilted 25° from straight down within the Y-Z plane.
        let forward = simd_float3(0, -cos(rad), -sin(rad))
        let m = matrix(column2: simd_float4(-forward.x, -forward.y, -forward.z, 0))
        let tilt = LiveSampleMath.tiltDegrees(worldFromCamera: m)
        #expect(abs(tilt - 25) < 0.5)
    }

    // MARK: - Distance (Req §3.1)

    @Test("median centre-crop depth of 0.35 m → 35 cm")
    func distanceMedian() {
        let depth = makeDepthBuffer(width: 40, height: 40, metres: 0.35)
        let cm = LiveSampleMath.medianDistanceCm(depthMap: depth)
        #expect(cm != nil)
        #expect(abs((cm ?? 0) - 35) < 0.01)
    }

    @Test("all-zero depth crop → nil (no usable depth)")
    func distanceEmpty() {
        let depth = makeDepthBuffer(width: 40, height: 40, metres: 0)
        #expect(LiveSampleMath.medianDistanceCm(depthMap: depth) == nil)
    }

    // MARK: - LiDAR coverage (Req §3.1, §4.1)

    @Test("all high-confidence pixels → 100% coverage")
    func coverageFull() {
        let conf = makeConfidenceBuffer(width: 32, height: 32, level: UInt8(ARConfidenceLevel.high.rawValue))
        #expect(abs(LiveSampleMath.lidarCoveragePercent(confidenceMap: conf) - 100) < 0.01)
    }

    @Test("all low-confidence pixels → 0% coverage")
    func coverageNone() {
        let conf = makeConfidenceBuffer(width: 32, height: 32, level: UInt8(ARConfidenceLevel.low.rawValue))
        #expect(LiveSampleMath.lidarCoveragePercent(confidenceMap: conf) == 0)
    }

    @Test("medium-confidence pixels fall below τ_conf=0.66 → 0% coverage")
    func coverageMedium() {
        let conf = makeConfidenceBuffer(width: 32, height: 32, level: UInt8(ARConfidenceLevel.medium.rawValue))
        #expect(LiveSampleMath.lidarCoveragePercent(confidenceMap: conf) == 0)
    }

    @Test("half high / half low pixels → 50% coverage")
    func coverageHalf() {
        let conf = makeSplitConfidenceBuffer(width: 32, height: 32)
        #expect(abs(LiveSampleMath.lidarCoveragePercent(confidenceMap: conf) - 50) < 0.01)
    }

    // MARK: - Write-gating (design.md)

    @Test("apply forwards to model in .ready")
    func gatingForwardsInReady() {
        let model = makeReadyModel()
        let observer = LiveSampleObserver(model: model)
        observer.apply(.init(tiltDegrees: 0, distanceCm: 42, lidarCoveragePercent: 88, trackingIsNormal: true))
        #expect(model.indicators.liveDistanceCm == 42)
        #expect(model.indicators.liveLiDARCoveragePercent == 88)
    }

    @Test("apply drops sample when state is not .ready/.forcingTwoView")
    func gatingDropsOutsideReady() {
        let model = makeReadyModel()
        let observer = LiveSampleObserver(model: model)
        observer.apply(.init(tiltDegrees: 0, distanceCm: 42, lidarCoveragePercent: 88, trackingIsNormal: true))
        // Move to a state where indicators should freeze.
        model.state = .permissionDenied(.camera)
        observer.apply(.init(tiltDegrees: 30, distanceCm: 99, lidarCoveragePercent: 5, trackingIsNormal: true))
        #expect(model.indicators.liveDistanceCm == 42)
        #expect(model.indicators.liveLiDARCoveragePercent == 88)
    }
}

// MARK: - Fixtures

@MainActor
private func makeReadyModel() -> CaptureFlowModel {
    let engine = MockCaptureEngine(nadirFrame: .fixture())
    let model = CaptureFlowModel(
        session: CaptureSession(engine: engine),
        pipeline: NoopPipeline(),
        indicators: LiveIndicatorModel(),
        interruptions: AsyncStream.makeStream(of: ARKitCaptureEngine.InterruptionEvent.self).stream,
        supportsLiDAR: true,
        databaseEdition: "test",
        paletteVersion: "test",
        cameraAuthorisation: { .authorized },
        motionAvailable: { true }
    )
    model.liveSampleDidUpdate(tiltDegrees: 0, distanceCm: 35, lidarCoveragePercent: 90, trackingIsNormal: true)
    return model
}

private func matrix(column2: simd_float4) -> simd_float4x4 {
    simd_float4x4(columns: (
        simd_float4(1, 0, 0, 0),
        simd_float4(0, 1, 0, 0),
        column2,
        simd_float4(0, 0, 0, 1)
    ))
}

private func makeDepthBuffer(width: Int, height: Int, metres: Float) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_DepthFloat32, nil, &pb)
    let buffer = pb!
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let base = CVPixelBufferGetBaseAddress(buffer)!
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for row in 0..<height {
        let rowPtr = base.advanced(by: row * stride).assumingMemoryBound(to: Float.self)
        for col in 0..<width { rowPtr[col] = metres }
    }
    return buffer
}

private func makeConfidenceBuffer(width: Int, height: Int, level: UInt8) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8, nil, &pb)
    let buffer = pb!
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let base = CVPixelBufferGetBaseAddress(buffer)!
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    for row in 0..<height {
        let rowPtr = base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self)
        for col in 0..<width { rowPtr[col] = level }
    }
    return buffer
}

// Left half high-confidence, right half low-confidence → 50% coverage.
private func makeSplitConfidenceBuffer(width: Int, height: Int) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent8, nil, &pb)
    let buffer = pb!
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let base = CVPixelBufferGetBaseAddress(buffer)!
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let high = UInt8(ARConfidenceLevel.high.rawValue)
    let low = UInt8(ARConfidenceLevel.low.rawValue)
    for row in 0..<height {
        let rowPtr = base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self)
        for col in 0..<width { rowPtr[col] = col < width / 2 ? high : low }
    }
    return buffer
}

private final class NoopPipeline: PipelineEstimator, @unchecked Sendable {
    func estimate(captureResult: CaptureResult) async throws -> MealRecord {
        throw EstimationFailure.noScaleAvailable
    }
}

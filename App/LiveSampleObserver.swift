import ARKit
import CaptureKit
import CoreVideo
import Foundation
import simd

// Iterates the engine's live `frames` stream, computes per-frame tilt /
// distance / LiDAR coverage, and forwards them to `CaptureFlowModel` for the
// indicator surface. Started / stopped by the view based on `CaptureFlowModel`
// state so the per-frame depth median only runs while the user can act on it
// (design.md write-gating). The per-frame maths live in `LiveSampleMath` so
// they are unit-testable without an `ARFrame` (which has no public init).
@MainActor
final class LiveSampleObserver {
    struct Sample: Equatable {
        var tiltDegrees: Float
        var distanceCm: Float?
        var lidarCoveragePercent: Float
        var trackingIsNormal: Bool
    }

    private let model: CaptureFlowModel
    private var task: Task<Void, Never>?

    init(model: CaptureFlowModel) {
        self.model = model
    }

    func start(frames: AsyncStream<ARFrame>) {
        task?.cancel()
        task = Task { [weak self] in
            for await frame in frames {
                guard let self else { return }
                self.apply(LiveSampleMath.sample(from: frame))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // Write-gating: only forward to the model when the user is acting on the
    // indicators. Capture / estimation / result / refusal states drop the
    // sample so the displayed values do not flicker mid-flight.
    func apply(_ sample: Sample) {
        switch model.state {
        case .ready, .forcingTwoView, .initialising, .trackingLost:
            model.liveSampleDidUpdate(
                tiltDegrees: sample.tiltDegrees,
                distanceCm: sample.distanceCm,
                lidarCoveragePercent: sample.lidarCoveragePercent,
                trackingIsNormal: sample.trackingIsNormal
            )
        default:
            break
        }
    }
}

// Pure per-frame computations. Operate on plain simd / CVPixelBuffer values so
// they can be exercised with synthesised fixtures.
enum LiveSampleMath {
    static let confidenceThreshold: Float = 0.66
    static let cropFraction: Float = 0.2

    static func sample(from frame: ARFrame) -> LiveSampleObserver.Sample {
        let tilt = tiltDegrees(worldFromCamera: frame.camera.transform)
        let depth = frame.sceneDepth
        let distance = depth.flatMap { medianDistanceCm(depthMap: $0.depthMap) }
        let coverage = depth?.confidenceMap.map {
            lidarCoveragePercent(confidenceMap: $0)
        } ?? 0
        return LiveSampleObserver.Sample(
            tiltDegrees: tilt,
            distanceCm: distance,
            lidarCoveragePercent: coverage,
            trackingIsNormal: frame.camera.trackingState == .normal
        )
    }

    // Angle between the camera's forward axis and straight-down. ARKit's
    // gravity-aligned world has +Y up, so down is (0, -1, 0); the camera looks
    // along its -Z axis (third column of the world transform, negated).
    static func tiltDegrees(worldFromCamera: simd_float4x4) -> Float {
        let forward = simd_normalize(-simd_float3(
            worldFromCamera.columns.2.x,
            worldFromCamera.columns.2.y,
            worldFromCamera.columns.2.z
        ))
        let down = simd_float3(0, -1, 0)
        let cosA = simd_clamp(simd_dot(forward, down), -1, 1)
        return acos(cosA) * 180 / .pi
    }

    // Median of a centre-crop of the depth map, returned in centimetres.
    // ARKit's depthMap is Float32 metres; nil for an empty crop.
    static func medianDistanceCm(depthMap: CVPixelBuffer) -> Float? {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0 else { return nil }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(depthMap)

        let cropW = max(1, Int(Float(width) * cropFraction))
        let cropH = max(1, Int(Float(height) * cropFraction))
        let x0 = (width - cropW) / 2
        let y0 = (height - cropH) / 2

        var metres: [Float] = []
        metres.reserveCapacity(cropW * cropH)
        for row in y0..<(y0 + cropH) {
            let rowPtr = base.advanced(by: row * stride).assumingMemoryBound(to: Float.self)
            for col in x0..<(x0 + cropW) {
                let value = rowPtr[col]
                if value.isFinite, value > 0 { metres.append(value) }
            }
        }
        guard !metres.isEmpty else { return nil }
        metres.sort()
        let median = metres[metres.count / 2]
        return median * 100
    }

    // Fraction of pixels whose normalised confidence (ARConfidenceLevel 0…2
    // mapped to 0…1) meets the threshold, expressed as a percentage.
    static func lidarCoveragePercent(confidenceMap: CVPixelBuffer) -> Float {
        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)
        guard width > 0, height > 0 else { return 0 }

        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(confidenceMap) else { return 0 }
        let stride = CVPixelBufferGetBytesPerRow(confidenceMap)

        let maxLevel = Float(ARConfidenceLevel.high.rawValue)
        var total = 0
        var passing = 0
        for row in 0..<height {
            let rowPtr = base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self)
            for col in 0..<width {
                total += 1
                if Float(rowPtr[col]) / maxLevel >= confidenceThreshold { passing += 1 }
            }
        }
        guard total > 0 else { return 0 }
        return Float(passing) / Float(total) * 100
    }
}

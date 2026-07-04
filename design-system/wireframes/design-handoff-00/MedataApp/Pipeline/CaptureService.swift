import Foundation
import CoreGraphics

// MARK: - Cross-cutting types

/// Calibrated camera intrinsics — req §2.3.
struct CalibrationRecord: Hashable {
    let fx, fy, cx, cy: Double
    let width, height: Int
    let distortion: [Double]    // empty if device reports none
}

/// Req §6 — metric depth aligned with the colour frame.
struct DepthMap: Hashable {
    let widthPx: Int
    let heightPx: Int
    let metresPerPixel: [Float]   // row-major, in metres
    let confidence: [UInt8]       // 0 = low, 1 = med, 2 = high
}

/// Output of a capture session frame.
struct CapturedFrame: Hashable {
    let id: UUID = UUID()
    let imagePath: URL
    let calibration: CalibrationRecord
    let depth: DepthMap?
    let tiltDegrees: Double
    let distanceMetres: Double?
    let timestamp: Date
}

/// 6-DOF rigid transform — req §3.6.
struct PoseSE3: Hashable {
    let rotation: [Double]   // 3×3 row-major
    let translation: [Double]  // 3-vector, metres
}

// MARK: - Capture

enum CaptureErrorKind: Hashable {
    case tiltOutOfRange(actual: Double)
    case distanceOutOfRange(actual: Double)
    case trackingLost
    case noLidarNoCard
    case insufficientLight
    case unsupportedDevice
}

@MainActor
protocol CaptureService: AnyObject {
    /// Live tilt in degrees from vertical (nadir target).
    var tiltDegrees: AsyncStream<Double> { get }
    /// Live working distance in metres (LiDAR-backed where available).
    var distanceMetres: AsyncStream<Double> { get }
    /// True when the device exposes a rear LiDAR scanner.
    var hasLidar: Bool { get }

    func capture(target: CaptureTarget) async throws -> CapturedFrame
    func release()
}

enum CaptureTarget: Hashable {
    case nadir
    case oblique(degreesFromVertical: Double)   // 25 ± 5 per req §3.3
}

/// Stub — returns a fabricated frame so views can drive the flow.
@MainActor
final class MockCaptureService: CaptureService {
    let hasLidar: Bool = true
    var tiltDegrees: AsyncStream<Double> {
        AsyncStream { cont in cont.yield(2.1); cont.finish() }
    }
    var distanceMetres: AsyncStream<Double> {
        AsyncStream { cont in cont.yield(0.34); cont.finish() }
    }
    func capture(target: CaptureTarget) async throws -> CapturedFrame {
        CapturedFrame(
            imagePath: URL(fileURLWithPath: "/dev/null"),
            calibration: CalibrationRecord(fx: 1500, fy: 1500, cx: 960, cy: 540, width: 1920, height: 1080, distortion: []),
            depth: nil,
            tiltDegrees: 2.1,
            distanceMetres: 0.34,
            timestamp: .now
        )
    }
    func release() {}
}

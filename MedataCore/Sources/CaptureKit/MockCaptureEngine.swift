import Foundation
import PortableContracts

// In-memory CaptureEngine used by tests, HarnessCLI, and any non-iOS host that
// doesn't have ARKit. Frames are scripted; release() can be slowed via a
// configurable delay so the 200 ms ceiling in CaptureSession.stop() is testable.
public final class MockCaptureEngine: CaptureEngine, @unchecked Sendable {
    public var nadirFrame: RawFrame?
    public var obliqueFrame: RawFrame?
    public var startError: CaptureError?
    public var releaseDelayNs: UInt64 = 0

    public init(nadirFrame: RawFrame? = nil, obliqueFrame: RawFrame? = nil) {
        self.nadirFrame = nadirFrame
        self.obliqueFrame = obliqueFrame
    }

    public func start() async throws {
        if let err = startError { throw err }
    }

    public func captureFrame(target: CaptureTarget) async throws -> RawFrame {
        switch target {
        case .nadir:
            guard let f = nadirFrame else {
                throw CaptureError.captureFailed("no nadir frame queued")
            }
            return f
        case .oblique:
            guard let f = obliqueFrame else {
                throw CaptureError.captureFailed("no oblique frame queued")
            }
            return f
        }
    }

    public func release() async {
        if releaseDelayNs > 0 {
            try? await Task.sleep(nanoseconds: releaseDelayNs)
        }
    }
}

// Convenience builder used in tests and fixtures.
public extension RawFrame {
    static func fixture(
        timestampMonotonicNs: Int64 = 1_000_000_000,
        pixelFormat: PixelFormat = .bgra8,
        depth: DepthMap? = nil
    ) -> RawFrame {
        let intrinsics = CameraIntrinsics(
            fx: 1500, fy: 1500, cx: 2016, cy: 1512,
            distortion: [], imageWidth: 4032, imageHeight: 3024
        )
        return RawFrame(
            imageBytes: Data(repeating: 0, count: 16),
            pixelFormat: pixelFormat,
            colourSpace: .sRGB,
            orientation: 1,
            imageWidth: 4032, imageHeight: 3024,
            timestampMonotonicNs: timestampMonotonicNs,
            intrinsics: intrinsics,
            gravity: Vec3(0, -1, 0),
            worldFromCamera: .identity,
            depth: depth
        )
    }
}

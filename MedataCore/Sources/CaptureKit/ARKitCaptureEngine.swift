#if canImport(ARKit) && os(iOS)
import ARKit
import CoreMotion
import Foundation
import PortableContracts
import simd

// Real ARKit + Core Motion engine per Req 1, 2, 3, 6 and design §3.1. Lives behind
// `#if canImport(ARKit) && os(iOS)`; the macOS HarnessCLI uses MockCaptureEngine.
//
// Responsibilities:
//   • Refuse start() on devices without rear LiDAR (Req 1.3) in RELEASE builds.
//     DEBUG builds run without `.sceneDepth` so developers can exercise the
//     two-view + ID-1 card path (Req 4.3, §7.4) on non-LiDAR hardware.
//     See docs/ios-device-setup.md for device support details.
//   • Run an ARKit world-tracking session with sceneDepth (LiDAR) enabled (Req 6)
//     when the device supports it.
//   • Convert iOS-private simd_* types to portable Vec3/Mat4 BEFORE constructing
//     RawFrame, so no other module sees simd_* (design §6.0 boundary rule).
//   • Map ARConfidenceLevel.{low,medium,high} → UInt8 {0,127,255} per §6.0.
public final class ARKitCaptureEngine: NSObject, CaptureEngine, @unchecked Sendable, ARSessionDelegate {
    private let session = ARSession()
    private let motion = CMMotionManager()
    private var latestFrameContinuation: CheckedContinuation<ARFrame, Error>?
    private let stateQueue = DispatchQueue(label: "medata.captureengine.state")

    public override init() {
        super.init()
        session.delegate = self
    }

    public func start() async throws {
        let supportsLiDAR = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        #if !DEBUG
        guard supportsLiDAR else {
            throw CaptureError.lidarUnavailable
        }
        #endif
        let config = ARWorldTrackingConfiguration()
        if supportsLiDAR {
            config.frameSemantics.insert(.sceneDepth)
        }
        config.worldAlignment = .gravity
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 60.0
            motion.startDeviceMotionUpdates()
        }
    }

    public func captureFrame(target: CaptureTarget) async throws -> RawFrame {
        let arFrame = try await nextARFrame()
        guard arFrame.camera.trackingState.isUsable else {
            throw CaptureError.worldTrackingDegraded
        }
        return try buildRawFrame(arFrame: arFrame)
    }

    public func release() async {
        session.pause()
        motion.stopDeviceMotionUpdates()
    }

    // MARK: – ARSessionDelegate

    public func session(_ session: ARSession, didUpdate frame: ARFrame) {
        stateQueue.async { [weak self] in
            guard let self, let cont = self.latestFrameContinuation else { return }
            self.latestFrameContinuation = nil
            cont.resume(returning: frame)
        }
    }

    public func session(_ session: ARSession, didFailWithError error: Error) {
        stateQueue.async { [weak self] in
            guard let self, let cont = self.latestFrameContinuation else { return }
            self.latestFrameContinuation = nil
            cont.resume(throwing: CaptureError.captureFailed(error.localizedDescription))
        }
    }

    private func nextARFrame() async throws -> ARFrame {
        try await withCheckedThrowingContinuation { cont in
            stateQueue.async { [weak self] in
                guard let self else {
                    cont.resume(throwing: CaptureError.captureFailed("engine deallocated"))
                    return
                }
                self.latestFrameContinuation = cont
            }
        }
    }

    private func buildRawFrame(arFrame: ARFrame) throws -> RawFrame {
        let cam = arFrame.camera
        let pixelBuffer = arFrame.capturedImage
        let imageWidth = CVPixelBufferGetWidth(pixelBuffer)
        let imageHeight = CVPixelBufferGetHeight(pixelBuffer)

        let intrinsics = CameraIntrinsics(
            fx: cam.intrinsics[0, 0], fy: cam.intrinsics[1, 1],
            cx: cam.intrinsics[2, 0], cy: cam.intrinsics[2, 1],
            distortion: [],
            imageWidth: imageWidth, imageHeight: imageHeight
        )

        let gravity = Vec3(simd_float3(0, -1, 0))  // ARKit gravity-aligned: world +Y up.

        let depth: DepthMap? = arFrame.sceneDepth.map { sceneDepth in
            buildDepthMap(scene: sceneDepth, depthFromColour: matrix_identity_float4x4)
        }

        return RawFrame(
            imageBytes: copyPixelBufferBytes(pixelBuffer),
            pixelFormat: detectPixelFormat(pixelBuffer),
            colourSpace: .sRGB,
            orientation: 1,
            imageWidth: imageWidth, imageHeight: imageHeight,
            timestampMonotonicNs: Int64(arFrame.timestamp * 1_000_000_000),
            intrinsics: intrinsics,
            gravity: gravity,
            worldFromCamera: Mat4(cam.transform),
            depth: depth
        )
    }

    private func buildDepthMap(scene: ARDepthData, depthFromColour: simd_float4x4) -> DepthMap {
        let depthMap = scene.depthMap
        let confidence = scene.confidenceMap
        let w = CVPixelBufferGetWidth(depthMap)
        let h = CVPixelBufferGetHeight(depthMap)

        // ARKit emits depth in metres (Float32). Convert to mm before building the
        // portable bytes (per §6.0 unit convention).
        var depthBytes = Data()
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        if let base = CVPixelBufferGetBaseAddress(depthMap) {
            let stride = CVPixelBufferGetBytesPerRow(depthMap)
            depthBytes.reserveCapacity(w * h * 4)
            for row in 0..<h {
                let rowPtr = base.advanced(by: row * stride).assumingMemoryBound(to: Float.self)
                for col in 0..<w {
                    var mm = rowPtr[col] * 1000
                    withUnsafeBytes(of: &mm) { depthBytes.append(contentsOf: $0) }
                }
            }
        }

        var confBytes = Data(repeating: 0, count: w * h)
        if let confidence {
            CVPixelBufferLockBaseAddress(confidence, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(confidence, .readOnly) }
            if let base = CVPixelBufferGetBaseAddress(confidence) {
                let stride = CVPixelBufferGetBytesPerRow(confidence)
                for row in 0..<h {
                    let rowPtr = base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self)
                    for col in 0..<w {
                        let level = LidarConfidenceLevel(rawValue: Int(rowPtr[col])) ?? .low
                        confBytes[row * w + col] = level.normalisedByte
                    }
                }
            }
        }

        return DepthMap(
            depthBytesMm: depthBytes,
            confidenceBytes: confBytes,
            width: w, height: h,
            rowStrideBytes: w * 4,
            depthIntrinsics: CameraIntrinsics(
                fx: 0, fy: 0, cx: 0, cy: 0, distortion: [],
                imageWidth: w, imageHeight: h
            ),
            depthFromColour: Mat4(depthFromColour)
        )
    }

    private func detectPixelFormat(_ buffer: CVPixelBuffer) -> PixelFormat {
        switch CVPixelBufferGetPixelFormatType(buffer) {
        case kCVPixelFormatType_32BGRA: return .bgra8
        case kCVPixelFormatType_32RGBA: return .rgba8
        default: return .bgra8
        }
    }

    private func copyPixelBufferBytes(_ buffer: CVPixelBuffer) -> Data {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return Data() }
        let length = CVPixelBufferGetBytesPerRow(buffer) * CVPixelBufferGetHeight(buffer)
        return Data(bytes: base, count: length)
    }
}

private extension ARCamera.TrackingState {
    var isUsable: Bool {
        switch self {
        case .normal: return true
        default: return false
        }
    }
}
#endif

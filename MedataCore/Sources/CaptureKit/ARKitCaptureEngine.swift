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
//   • Run an ARKit world-tracking session with `.sceneDepth` (LiDAR) enabled
//     when the device supports it (Req 6). On non-LiDAR devices the session
//     starts without depth and the pipeline falls through to the two-view +
//     ID-1 card path (Req 4.3, §7.4), with `noLidarConfidence` set per §7.4.
//     The hardware-floor refusal (Req 1.3) is no longer enforced at this
//     boundary so non-LiDAR developer / test devices run the full app in both
//     Debug and Release. See docs/ios-device-setup.md for device support.
//   • Convert iOS-private simd_* types to portable Vec3/Mat4 BEFORE constructing
//     RawFrame, so no other module sees simd_* (design §6.0 boundary rule).
//   • Map ARConfidenceLevel.{low,medium,high} → UInt8 {0,127,255} per §6.0.
public final class ARKitCaptureEngine: NSObject, CaptureEngine, @unchecked Sendable, ARSessionDelegate {
    public enum InterruptionEvent: Sendable, Equatable {
        case began
        case ended
    }

    private let session = ARSession()
    private let motion = CMMotionManager()
    private var latestFrameContinuation: CheckedContinuation<ARFrame, Error>?
    private var frameContinuations: [UUID: AsyncStream<ARFrame>.Continuation] = [:]
    private var interruptionContinuations: [UUID: AsyncStream<InterruptionEvent>.Continuation] = [:]
    private let stateQueue = DispatchQueue(label: "medata.captureengine.state")

    public override init() {
        super.init()
        session.delegate = self
    }

    /// The underlying ARSession. Exposed so an iOS-shell preview view can
    /// render the camera feed by assigning it to ARView. The engine remains
    /// the sole `ARSessionDelegate`; callers MUST NOT reassign
    /// `session.delegate`.
    public var arSession: ARSession { session }

    /// Live AR frames observed by the engine's ARSessionDelegate hook, fanned
    /// out for non-capture consumers (preview overlays, tilt indicator,
    /// LiDAR-coverage gauge). The stream is per-subscriber and back-pressured
    /// via `BufferingPolicy.bufferingNewest(1)` — slow consumers see the
    /// latest frame, not a backlog. Cancelling the iteration unsubscribes.
    public var frames: AsyncStream<ARFrame> {
        let id = UUID()
        let (stream, cont) = AsyncStream<ARFrame>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        stateQueue.async { [weak self] in
            self?.frameContinuations[id] = cont
        }
        cont.onTermination = { [weak self] _ in
            self?.stateQueue.async { [weak self] in
                self?.frameContinuations.removeValue(forKey: id)
            }
        }
        return stream
    }

    /// AR-session interruption events (phone call, screen lock, etc.) surfaced
    /// from `ARSessionObserver.sessionWasInterrupted/Ended`. Per-subscriber,
    /// back-pressured via `BufferingPolicy.bufferingNewest(1)`.
    public var interruptions: AsyncStream<InterruptionEvent> {
        let id = UUID()
        let (stream, cont) = AsyncStream<InterruptionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        stateQueue.async { [weak self] in
            self?.interruptionContinuations[id] = cont
        }
        cont.onTermination = { [weak self] _ in
            self?.stateQueue.async { [weak self] in
                self?.interruptionContinuations.removeValue(forKey: id)
            }
        }
        return stream
    }

    public func start() async throws {
        let supportsLiDAR = ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        let config = ARWorldTrackingConfiguration()
        if supportsLiDAR {
            config.frameSemantics.insert(.sceneDepth)
        }
        config.worldAlignment = .gravity
        // Only re-run the session if it hasn't been configured yet (e.g., by ARPreviewView).
        // If already configured, ensure frame semantics are updated.
        if session.configuration == nil {
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
        } else if case let current as ARWorldTrackingConfiguration = session.configuration,
                  !current.frameSemantics.contains(.sceneDepth) && supportsLiDAR {
            // Update frame semantics if LiDAR support was added after initial config
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
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
            guard let self else { return }
            for cont in self.frameContinuations.values {
                cont.yield(frame)
            }
            if let cont = self.latestFrameContinuation {
                self.latestFrameContinuation = nil
                cont.resume(returning: frame)
            }
        }
    }

    public func session(_ session: ARSession, didFailWithError error: Error) {
        stateQueue.async { [weak self] in
            guard let self, let cont = self.latestFrameContinuation else { return }
            self.latestFrameContinuation = nil
            cont.resume(throwing: CaptureError.captureFailed(error.localizedDescription))
        }
    }

    public func sessionWasInterrupted(_ session: ARSession) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            for cont in self.interruptionContinuations.values {
                cont.yield(.began)
            }
        }
    }

    public func sessionInterruptionEnded(_ session: ARSession) {
        stateQueue.async { [weak self] in
            guard let self else { return }
            for cont in self.interruptionContinuations.values {
                cont.yield(.ended)
            }
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

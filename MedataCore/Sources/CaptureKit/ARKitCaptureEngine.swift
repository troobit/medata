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

    // The authoritative ARSession. Starts as a placeholder created off-screen;
    // once the preview ARView exists, `bindPreviewSession` swaps in the view's
    // session so there is exactly one session (one camera capture source). Only
    // ever mutated/read on the main actor (see `bindPreviewSession`, `start`,
    // `release`). The placeholder is never run — `applyRunStateIfNeeded` only
    // runs config after a real session is bound.
    private var session = ARSession()
    private var runRequested = false
    private var isBound = false
    // `internal` so `@testable import CaptureKit` can assert that
    // `bindPreviewSession` ran the config without depending on
    // `ARSession.configuration` (which is unreliable in the iOS Simulator).
    internal var isRunning = false

    private let motion = CMMotionManager()
    private var latestFrameContinuation: CheckedContinuation<ARFrame, Error>?
    private var frameContinuations: [UUID: AsyncStream<ARFrame>.Continuation] = [:]
    private var interruptionContinuations: [UUID: AsyncStream<InterruptionEvent>.Continuation] = [:]
    private let stateQueue = DispatchQueue(label: "medata.captureengine.state")

    public override init() {
        super.init()
        session.delegate = self
    }

    /// The single authoritative ARSession. Exposed for the iOS-shell preview
    /// view to observe; the view does NOT assign it (ARView.session is get-only)
    /// — instead the view hands the engine its session via `bindPreviewSession`.
    /// The engine remains the sole `ARSessionDelegate`; callers MUST NOT reassign
    /// `session.delegate`.
    public var arSession: ARSession { session }

    /// Adopt the preview `ARView`'s session as the one authoritative session.
    ///
    /// `ARView.session` is get-only, so the engine cannot inject its own session
    /// into the view. Instead the engine takes ownership of the view's session:
    /// it becomes that session's sole delegate and runs the world-tracking
    /// config on it (Decision 11 — one ARSession, owned by the engine). This
    /// replaces the earlier design that ran a SECOND, separate ARSession which
    /// contended with the view's for the camera, producing repeated
    /// capture-source failures and session-interruption churn.
    ///
    /// Idempotent: binding the same session again only re-asserts the delegate
    /// (RealityKit may reattach itself on `updateUIView`) and never re-runs the
    /// config, so live tracking is not reset.
    @MainActor
    public func bindPreviewSession(_ external: ARSession) {
        if external !== session {
            session.delegate = nil
            session.pause()
            session = external
            isRunning = false
        }
        session.delegate = self
        isBound = true
        // Binding a real session IS the run trigger — `CaptureFlowModel.start()`
        // runs fire-and-forget and may not have flipped `runRequested` yet.
        // Deferring leaves ARView rendering a bound-but-unconfigured session,
        // which produces FigCaptureSourceRemote -12784 / Fig -12710 errors
        // during the gap (see specs/bugfixes/arview-session-config-race/).
        // The placeholder session is still protected by the `isBound` guard
        // in `applyRunStateIfNeeded`.
        runRequested = true
        applyRunStateIfNeeded()
    }

    @MainActor
    private func applyRunStateIfNeeded() {
        guard isBound, runRequested, !isRunning else { return }
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        config.worldAlignment = .gravity
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        isRunning = true
    }

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
        // Record intent and run the config only if the preview session is bound;
        // otherwise the run is deferred to `bindPreviewSession`. This avoids
        // starting the placeholder session (a second camera source) before the
        // ARView's session is available. The model's start-task is fire-and-forget
        // and only awaited at capture time, which can only happen after the
        // preview (and therefore the bound, running session) exists.
        await MainActor.run {
            self.runRequested = true
            self.applyRunStateIfNeeded()
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
        await MainActor.run {
            self.runRequested = false
            self.isRunning = false
            self.session.pause()
        }
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

        let converted = try PixelBufferAdapter.convert(pixelBuffer)

        return RawFrame(
            imageBytes: converted.bytes,
            pixelFormat: converted.format,
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

import ARKit
import CaptureKit
import RealityKit
import SwiftUI

// Renders the live camera feed for the capture flow. `ARKitCaptureEngine` owns
// the one `ARSession` and is its sole delegate (Decision 11); RealityKit has
// historically re-attached itself as the session delegate at both makeUIView
// and updateUIView, so we re-assert the engine at both lifecycle points. The
// re-assertion is a cheap, idempotent property write.
//
// Note: `ARView.session` is get-only, so the engine's session cannot be
// injected into the ARView directly. The engine remains the authoritative
// session owner; `reassertDelegate()` keeps the engine wired as delegate.
struct ARPreviewView: UIViewRepresentable {
    let engine: ARKitCaptureEngine

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        ensureSessionConfigured()
        reassertDelegate()
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        reassertDelegate()
    }

    // Ensure the ARSession is configured and running so the ARView can render.
    // This runs synchronously to guarantee the camera is ready before the view
    // attempts to display it. The engine owns the session lifecycle; this seam
    // only ensures it's prepared for display.
    private func ensureSessionConfigured() {
        let session = engine.arSession
        if session.configuration == nil {
            let config = ARWorldTrackingConfiguration()
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                config.frameSemantics.insert(.sceneDepth)
            }
            config.worldAlignment = .gravity
            session.run(config, options: [.resetTracking, .removeExistingAnchors])
        }
    }

    // Testable seam shared by makeUIView and updateUIView (the SwiftUI
    // `Context` has no public initialiser, so tests drive this directly).
    func reassertDelegate() {
        engine.arSession.delegate = engine
    }
}

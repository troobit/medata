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
        reassertDelegate()
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        reassertDelegate()
    }

    // Testable seam shared by makeUIView and updateUIView (the SwiftUI
    // `Context` has no public initialiser, so tests drive this directly).
    func reassertDelegate() {
        engine.arSession.delegate = engine
    }
}

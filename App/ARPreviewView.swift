import ARKit
import CaptureKit
import RealityKit
import SwiftUI

// Renders the live camera feed for the capture flow. `ARView.session` is
// get-only, so the engine cannot be handed its own session to render; instead
// the engine ADOPTS the ARView's session as the one authoritative `ARSession`
// (Decision 11). This guarantees a single camera capture source — running a
// second, separate ARSession alongside the ARView's contends for the camera
// and produces capture-source failures and interruption churn.
//
// We bind at both makeUIView and updateUIView because RealityKit may reattach
// itself as the session delegate; `bindPreviewSession` is idempotent and only
// re-asserts the engine as delegate when the session is unchanged.
//
// `automaticallyConfigureSession: false` lets the engine own the configuration
// (world tracking + scene depth) rather than ARView overriding it.
struct ARPreviewView: UIViewRepresentable {
    let engine: ARKitCaptureEngine

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        bind(to: arView.session)
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        bind(to: uiView.session)
    }

    // Testable seam shared by makeUIView and updateUIView (the SwiftUI
    // `Context` has no public initialiser, so tests drive this directly).
    func bind(to session: ARSession) {
        engine.bindPreviewSession(session)
    }
}

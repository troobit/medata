import ARKit
import CaptureKit
import Testing
@testable import MeData

@Suite("ARPreviewView session-binding guard")
@MainActor
struct ARPreviewViewTests {

    // makeUIView and updateUIView both route through bind(to:); the SwiftUI
    // Context type cannot be constructed in a test, so we exercise the shared
    // seam directly. Binding must adopt the view's session as the engine's
    // authoritative session and leave the engine as its sole delegate
    // (design.md — RealityKit reassigns the delegate at either lifecycle point).

    @Test("bind adopts the view's session and makes the engine its delegate")
    func bindAdoptsSession() {
        let engine = ARKitCaptureEngine()
        let preview = ARPreviewView(engine: engine)
        let viewSession = ARSession()
        preview.bind(to: viewSession)
        #expect(engine.arSession === viewSession)
        #expect(viewSession.delegate === engine)
    }

    @Test("re-binding the same session restores the engine after a foreign delegate steals it")
    func restoresAfterForeignDelegate() {
        let engine = ARKitCaptureEngine()
        let preview = ARPreviewView(engine: engine)
        let viewSession = ARSession()
        preview.bind(to: viewSession)
        let thief = ForeignDelegate()
        viewSession.delegate = thief
        #expect(viewSession.delegate === thief)
        preview.bind(to: viewSession)
        #expect(viewSession.delegate === engine)
    }
}

private final class ForeignDelegate: NSObject, ARSessionDelegate {}

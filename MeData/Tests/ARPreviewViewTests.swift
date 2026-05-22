import ARKit
import CaptureKit
import Testing
@testable import MeData

@Suite("ARPreviewView delegate-reassertion guard")
@MainActor
struct ARPreviewViewTests {

    // makeUIView and updateUIView both route through reassertDelegate(); the
    // SwiftUI Context type cannot be constructed in a test, so we exercise the
    // shared seam directly. Both lifecycle points must leave the engine as the
    // session's sole delegate (design.md — RealityKit reassigns at either).

    @Test("reassertDelegate leaves the engine as the session delegate")
    func reassertsDelegate() {
        let engine = ARKitCaptureEngine()
        let preview = ARPreviewView(engine: engine)
        preview.reassertDelegate()
        #expect(engine.arSession.delegate === engine)
    }

    @Test("reassertDelegate restores the engine after a foreign delegate steals it")
    func restoresAfterForeignDelegate() {
        let engine = ARKitCaptureEngine()
        let preview = ARPreviewView(engine: engine)
        let thief = ForeignDelegate()
        engine.arSession.delegate = thief
        #expect(engine.arSession.delegate === thief)
        preview.reassertDelegate()
        #expect(engine.arSession.delegate === engine)
    }
}

private final class ForeignDelegate: NSObject, ARSessionDelegate {}

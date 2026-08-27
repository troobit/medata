#if FIELD_LOOP
import RealityKit
import SwiftUI
import UIKit

// The live `ARView`, if one is on screen. `ARPreviewView` publishes it under
// `#if FIELD_LOOP`; weak, so a dismissed capture cover drops it without any
// teardown hook. This is the only way the screenshot path can reach the camera
// feed: the AR preview is created inside a `UIViewRepresentable` and no other
// layer of the app holds it.
@MainActor
enum FieldARViewRegistry {
    static weak var current: ARView?
}

// A screenshot of the screen as it was when the affordance was tapped
// (ml-feedback-loop Req 1.4), including the live camera feed on the capture
// screen.
//
// Two render paths, because one does not cover both cases:
//
//  - Generic screens: `drawHierarchy(afterScreenUpdates: false)` on the
//    retained main window. `afterScreenUpdates: false` deliberately — a commit
//    pass here would render the sheet that is about to present.
//
//  - The capture screen: RealityKit renders through a Metal layer, which
//    `drawHierarchy` fills with black. So the AR content is taken from
//    `ARView.snapshot` (which includes the camera feed) and the chrome is drawn
//    over it by `CALayer.render(in:)`. `render(in:)` walks the layer tree and
//    ignores Metal-backed content entirely — the very limitation that makes it
//    useless as a general screenshot leaves exactly the transparent hole the
//    AR frame belongs in.
//
// Every failure is a reason string on the note, never an error: Req 1.6 puts
// the whole note path outside anything that can fail a capture.
@MainActor
enum FieldScreenshot {
    struct Shot {
        let image: UIImage?
        let failureReason: String?
    }

    static func capture(window: UIWindow?) async -> Shot {
        guard let window else {
            return Shot(image: nil, failureReason: "no_main_window")
        }
        guard window.bounds.width > 0, window.bounds.height > 0 else {
            return Shot(image: nil, failureReason: "zero_bounds")
        }
        if let arView = FieldARViewRegistry.current, arView.window === window {
            return await captureComposited(window: window, arView: arView)
        }
        return captureFlat(window: window)
    }

    private static func captureFlat(window: UIWindow) -> Shot {
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return Shot(image: image, failureReason: nil)
    }

    private static func captureComposited(window: UIWindow, arView: ARView) async -> Shot {
        guard let arImage = await arSnapshot(arView) else {
            // The camera frame is what makes a capture-screen note worth
            // having, but chrome alone still beats nothing.
            let flat = captureFlat(window: window)
            return Shot(image: flat.image, failureReason: "ar_snapshot_failed")
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { context in
            // The AR frame is camera-resolution and the window is in points:
            // fill the window rect rather than aligning pixel grids, matching
            // what the preview itself shows.
            arImage.draw(in: arView.convert(arView.bounds, to: window))
            window.layer.render(in: context.cgContext)
        }
        return Shot(image: image, failureReason: nil)
    }

    private static func arSnapshot(_ arView: ARView) async -> UIImage? {
        await withCheckedContinuation { continuation in
            arView.snapshot(saveToHDR: false) { image in
                continuation.resume(returning: image)
            }
        }
    }
}
#endif

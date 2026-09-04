import SwiftUI

// The persistent tilt guide for the nadir (0°) and oblique (25°) capture
// stages — a two-axis ("bubble" / attitude-level) readout. The numeric
// `LiveIndicatorBadge` auto-hides 5s after framing is in range
// (LiveIndicatorModel.scheduleHide), so its angle target disappears mid-
// adjustment; this guide stays on screen the whole time the user is aiming.
//
// It plots the live tilt as a dot in a 2-D field: distance from centre = tilt
// angle, direction = on-screen azimuth (fed by LiveIndicatorModel.liveTiltVector
// / LiveSampleMath.tiltVector). This shows WHICH way to rotate near the target.
//   • Nadir (0°)  — bring the dot to the centre bullseye (in-range disc = 12°).
//   • Oblique (25°) — bring the dot onto the target ring (in-range band 10–40°),
//     in ANY direction (free ring — matches the azimuth-free shutter gate).
//
// Per-stage target/tolerance and the in-range test live in `TiltGuideState`
// below, kept pure so they stay testable without a SwiftUI host.

// MARK: - Pure state surface (testable without a SwiftUI host)

enum TiltGuideState {
    // Target axis per stage: 0° straight-down for nadir, 25° for the oblique
    // (CaptureFlowModel tiltInRange / obliqueTiltOk).
    static func target(awaitingOblique: Bool) -> Float {
        awaitingOblique ? 25 : 0
    }

    // In-range tolerance. Oblique mirrors the live shutter gate exactly
    // (|Δθ − 25°| ≤ 15°, closeout-trail Decision 1). Nadir has no shutter gate,
    // so its band is advisory — the comfort window where σ_tilt stays high.
    static func toleranceDegrees(awaitingOblique: Bool) -> Float {
        awaitingOblique ? 15 : 12
    }

    static func isAligned(tilt: Float, target: Float, tolerance: Float) -> Bool {
        abs(tilt - target) <= tolerance
    }
}

// The `TiltBubbleGuide` view (200×200 centre attitude level) was replaced by
// `MedataBubbleLevel` (76×76 top-right) in the handoff-00 chrome rebuild —
// geometry/placement only (Decision 8). `TiltGuideState` above is the shared
// maths both used and is kept here.

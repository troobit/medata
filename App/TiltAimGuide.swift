import SwiftUI

// Persistent graphical tilt guide for the nadir (0°) and oblique (25°) capture
// stages. The numeric `LiveIndicatorBadge` auto-hides 5s after the framing is in
// range (LiveIndicatorModel.scheduleHide), so the angle target disappears mid-
// adjustment — the exact complaint this guide answers. This guide stays on
// screen the whole time the user is aiming: a vertical gauge with the target
// band fixed at centre, a puck tracking the live tilt, and a snap to
// `medataAccent` once the tilt enters the stage tolerance.
//
// Colour note: in-range uses `medataAccent`, the same accent the badge already
// uses for in-range distance / coverage — NOT the green/red in/out scheme
// Decision 19 removed from the tilt readout.

// MARK: - Pure state surface (testable without a SwiftUI host)

enum TiltAimGuideState {
    // Tilt this far from the target pins the puck to the gauge's end. Wide
    // enough that neither stage's working range clips against the ends.
    static let halfSpanDegrees: Float = 30

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

    // Signed offset from target mapped to −1…1. Positive = over-tilted (puck
    // above centre); negative = under-tilted (puck below centre).
    static func offsetFraction(tilt: Float, target: Float) -> Float {
        max(-1, min(1, (tilt - target) / halfSpanDegrees))
    }

    static func isAligned(tilt: Float, target: Float, tolerance: Float) -> Bool {
        abs(tilt - target) <= tolerance
    }

    // Direction the user must move to reach the band: +1 tilt up (increase),
    // −1 tilt down (decrease toward target), 0 already aligned.
    static func correction(tilt: Float, target: Float, tolerance: Float) -> Int {
        if abs(tilt - target) <= tolerance { return 0 }
        return tilt > target ? -1 : 1
    }
}

// MARK: - View

struct TiltAimGuide: View {
    let tiltDegrees: Float
    let awaitingOblique: Bool

    // UX rule (High): respect reduce-motion — snap the puck to its new position
    // instead of sliding it when the user has asked the system to limit motion.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let trackHeight: CGFloat = 200
    private let trackWidth: CGFloat = 8
    private let puckSize: CGFloat = 24

    private var target: Float { TiltAimGuideState.target(awaitingOblique: awaitingOblique) }
    private var tolerance: Float { TiltAimGuideState.toleranceDegrees(awaitingOblique: awaitingOblique) }
    private var aligned: Bool {
        TiltAimGuideState.isAligned(tilt: tiltDegrees, target: target, tolerance: tolerance)
    }
    private var correction: Int {
        TiltAimGuideState.correction(tilt: tiltDegrees, target: target, tolerance: tolerance)
    }

    // Largest puck travel from centre that keeps it fully inside the track.
    private var maxTravel: CGFloat { (trackHeight - puckSize) / 2 }
    // Positive offset = over-tilted = puck above centre (negative SwiftUI y).
    private var puckOffsetY: CGFloat {
        -CGFloat(TiltAimGuideState.offsetFraction(tilt: tiltDegrees, target: target)) * maxTravel
    }
    // Half-height of the in-range band, in points.
    private var bandHalfHeight: CGFloat {
        CGFloat(tolerance / TiltAimGuideState.halfSpanDegrees) * maxTravel
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(awaitingOblique ? "Oblique" : "Nadir")
                .font(.caption2.weight(.semibold))
            Text("target \(Int(target))°")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Color.captureChromeText.opacity(0.7))

            ZStack {
                Capsule()
                    .fill(Color.captureChromeText.opacity(0.18))
                    .frame(width: trackWidth, height: trackHeight)
                Capsule()
                    .fill(Color.medataAccent.opacity(0.3))
                    .frame(width: trackWidth, height: bandHalfHeight * 2)
                Capsule()
                    .fill(Color.captureChromeText.opacity(0.6))
                    .frame(width: trackWidth + 10, height: 2)
                puck
            }
            .frame(height: trackHeight)

            Text("\(Int(tiltDegrees.rounded()))°")
                .font(.caption2.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(Color.captureChromeText)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("tiltGuide")
        .accessibilityLabel(awaitingOblique ? "Oblique tilt guide" : "Nadir tilt guide")
        .accessibilityValue(
            aligned
                ? "Aligned at \(Int(tiltDegrees.rounded())) degrees"
                : "\(Int(tiltDegrees.rounded())) degrees, target \(Int(target)) degrees"
        )
    }

    private var puck: some View {
        Circle()
            .fill(aligned ? Color.medataAccent : Color.captureChromeText)
            .frame(width: puckSize, height: puckSize)
            .overlay {
                Image(systemName: aligned ? "checkmark" : (correction > 0 ? "chevron.up" : "chevron.down"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.captureBackground)
            }
            .offset(y: puckOffsetY)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: puckOffsetY)
            .accessibilityIdentifier("tiltGuide.puck")
    }
}

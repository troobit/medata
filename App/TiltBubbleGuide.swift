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

// MARK: - View

struct TiltBubbleGuide: View {
    let tiltVector: SIMD2<Float>
    let awaitingOblique: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let fieldSize: CGFloat = 200
    private let puckSize: CGFloat = 24
    // Angle mapped to the field edge. Wider than the gauge's 30° half-span so the
    // oblique 10–40° band fits inside with margin.
    private let maxAngleDegrees: Float = 45

    private var maxRadius: CGFloat { (fieldSize - puckSize) / 2 }
    private var pointsPerDegree: CGFloat { maxRadius / CGFloat(maxAngleDegrees) }

    private var target: Float { TiltGuideState.target(awaitingOblique: awaitingOblique) }
    private var tolerance: Float { TiltGuideState.toleranceDegrees(awaitingOblique: awaitingOblique) }
    private var tiltMagnitude: Float { (tiltVector.x * tiltVector.x + tiltVector.y * tiltVector.y).squareRoot() }
    private var aligned: Bool {
        TiltGuideState.isAligned(tilt: tiltMagnitude, target: target, tolerance: tolerance)
    }

    private func radius(forDegrees deg: Float) -> CGFloat {
        min(maxRadius, CGFloat(max(0, deg)) * pointsPerDegree)
    }

    // Dot position. Length clamped to the field; screen-y follows the tilt
    // direction (tilting the phone "away" drives the dot the matching way).
    private var puckOffset: CGSize {
        let mag = tiltMagnitude
        guard mag > 1e-4 else { return .zero }
        let clamped = min(mag, maxAngleDegrees)
        let scale = CGFloat(clamped) * pointsPerDegree / CGFloat(mag)
        return CGSize(width: CGFloat(tiltVector.x) * scale, height: CGFloat(tiltVector.y) * scale)
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(awaitingOblique ? "Oblique" : "Nadir")
                .font(.caption2.weight(.semibold))
            Text("target \(Int(target))°")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Color.captureChromeText.opacity(0.7))

            ZStack {
                // Field boundary.
                Circle()
                    .stroke(Color.captureChromeText.opacity(0.18), lineWidth: 2)
                    .frame(width: fieldSize, height: fieldSize)

                inRangeTarget
                crosshair
                puck
            }
            .frame(width: fieldSize, height: fieldSize)

            Text("\(Int(tiltMagnitude.rounded()))°")
                .font(.caption2.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(Color.captureChromeText)
        .padding(12)
        .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("tiltGuide")
        .accessibilityLabel(awaitingOblique ? "Oblique tilt guide" : "Nadir tilt guide")
        .accessibilityValue(
            aligned
                ? "Aligned at \(Int(tiltMagnitude.rounded())) degrees"
                : "\(Int(tiltMagnitude.rounded())) degrees, target \(Int(target)) degrees"
        )
    }

    // Nadir → a centre disc (radius = tolerance). Oblique → a ring band centred
    // on the 25° target, thick enough to span the 10–40° in-range window.
    @ViewBuilder
    private var inRangeTarget: some View {
        if target == 0 {
            Circle()
                .fill(Color.medataAccent.opacity(0.3))
                .frame(width: radius(forDegrees: tolerance) * 2, height: radius(forDegrees: tolerance) * 2)
        } else {
            let bandWidth = radius(forDegrees: target + tolerance) - radius(forDegrees: target - tolerance)
            Circle()
                .stroke(Color.medataAccent.opacity(0.3), lineWidth: bandWidth)
                .frame(width: radius(forDegrees: target) * 2, height: radius(forDegrees: target) * 2)
            Circle()
                .stroke(Color.medataAccent.opacity(0.7), lineWidth: 1.5)
                .frame(width: radius(forDegrees: target) * 2, height: radius(forDegrees: target) * 2)
        }
    }

    private var crosshair: some View {
        ZStack {
            Capsule().fill(Color.captureChromeText.opacity(0.5)).frame(width: 14, height: 2)
            Capsule().fill(Color.captureChromeText.opacity(0.5)).frame(width: 2, height: 14)
        }
    }

    private var puck: some View {
        Circle()
            .fill(aligned ? Color.medataAccent : Color.captureChromeText)
            .frame(width: puckSize, height: puckSize)
            .overlay {
                if aligned {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.captureBackground)
                }
            }
            .offset(puckOffset)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: puckOffset)
            .accessibilityIdentifier("tiltGuide.puck")
    }
}

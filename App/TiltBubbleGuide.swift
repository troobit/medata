import SwiftUI

// Two-axis ("bubble" / attitude-level) tilt guide — a third design to compare
// against the 1-D `.gauge` and `.dial` on device (CaptureFlowView.tiltGuideStyle).
//
// The gauge collapses tilt to a single magnitude, so near the target it can't
// show WHICH way to rotate. This guide plots the live tilt as a dot in a 2-D
// field: distance from centre = tilt angle, direction = on-screen azimuth (fed
// by LiveIndicatorModel.liveTiltVector / LiveSampleMath.tiltVector).
//   • Nadir (0°)  — bring the dot to the centre bullseye (in-range disc = 12°).
//   • Oblique (25°) — bring the dot onto the target ring (in-range band 10–40°),
//     in ANY direction (free ring — matches the azimuth-free shutter gate).
//
// In-range logic and per-stage target/tolerance are reused verbatim from
// `TiltAimGuideState`; only the rendering differs from the gauge.
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

    private var target: Float { TiltAimGuideState.target(awaitingOblique: awaitingOblique) }
    private var tolerance: Float { TiltAimGuideState.toleranceDegrees(awaitingOblique: awaitingOblique) }
    private var tiltMagnitude: Float { (tiltVector.x * tiltVector.x + tiltVector.y * tiltVector.y).squareRoot() }
    private var aligned: Bool {
        TiltAimGuideState.isAligned(tilt: tiltMagnitude, target: target, tolerance: tolerance)
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

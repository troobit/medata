import SwiftUI

// 76×76 top-right bubble level (Req 2.1 / 2.3, Decision 8). Same inputs and
// maths as the retired `TiltBubbleGuide` (tiltVector, stage-relative target
// 0°/25°, tolerance via `TiltGuideState`) — this is geometry/placement only.
// The bubble drifts continuously with device tilt, is tinted green within ±5°
// of the stage target and amber beyond, and always pairs colour with the
// puck's position (Req 14.4). It gates nothing (Decision 8).
struct MedataBubbleLevel: View {
    let tiltVector: SIMD2<Float>
    let awaitingOblique: Bool

    private let fieldSize: CGFloat = 76
    private let puckSize: CGFloat = 12
    private let maxAngleDegrees: Float = 45
    // Req 2.3 colour threshold: green within ±5° of the stage target.
    private let colourToleranceDegrees: Float = 5

    private var maxRadius: CGFloat { (fieldSize - puckSize) / 2 }
    private var pointsPerDegree: CGFloat { maxRadius / CGFloat(maxAngleDegrees) }

    private var target: Float { TiltGuideState.target(awaitingOblique: awaitingOblique) }
    private var tiltMagnitude: Float {
        (tiltVector.x * tiltVector.x + tiltVector.y * tiltVector.y).squareRoot()
    }
    // Green when the live tilt is within ±5° of the stage target angle.
    private var withinTarget: Bool {
        abs(tiltMagnitude - target) <= colourToleranceDegrees
    }
    private var puckColour: Color {
        withinTarget ? Color.medataAccent : Color(uiColor: .systemOrange)
    }

    private func radius(forDegrees deg: Float) -> CGFloat {
        min(maxRadius, CGFloat(max(0, deg)) * pointsPerDegree)
    }

    // Puck position: distance from centre encodes tilt magnitude, direction
    // follows the on-screen azimuth (the non-colour cue, Req 14.4).
    private var puckOffset: CGSize {
        let mag = tiltMagnitude
        guard mag > 1e-4 else { return .zero }
        let clamped = min(mag, maxAngleDegrees)
        let scale = CGFloat(clamped) * pointsPerDegree / CGFloat(mag)
        return CGSize(width: CGFloat(tiltVector.x) * scale, height: CGFloat(tiltVector.y) * scale)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.captureChromeBG)
            Circle()
                .stroke(Color.captureChromeText.opacity(0.18), lineWidth: 1.5)
            targetGuide
            crosshair
            Circle()
                .fill(puckColour)
                .frame(width: puckSize, height: puckSize)
                .offset(puckOffset)
        }
        .frame(width: fieldSize, height: fieldSize)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("bubbleLevel")
        .accessibilityLabel(awaitingOblique ? "Oblique tilt level" : "Nadir tilt level")
        .accessibilityValue("\(Int(tiltMagnitude.rounded())) degrees, target \(Int(target)) degrees")
    }

    // Nadir → a centre disc; oblique → a ring at the 25° target radius.
    @ViewBuilder
    private var targetGuide: some View {
        if target == 0 {
            Circle()
                .fill(Color.medataAccent.opacity(0.25))
                .frame(
                    width: radius(forDegrees: colourToleranceDegrees) * 2,
                    height: radius(forDegrees: colourToleranceDegrees) * 2
                )
        } else {
            Circle()
                .stroke(Color.medataAccent.opacity(0.5), lineWidth: 1.5)
                .frame(width: radius(forDegrees: target) * 2, height: radius(forDegrees: target) * 2)
        }
    }

    private var crosshair: some View {
        ZStack {
            Capsule().fill(Color.captureChromeText.opacity(0.4)).frame(width: 8, height: 1.5)
            Capsule().fill(Color.captureChromeText.opacity(0.4)).frame(width: 1.5, height: 8)
        }
    }
}

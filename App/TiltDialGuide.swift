import SwiftUI

// Attempt 2 — an alternative to the vertical-gauge `TiltAimGuide`. Same job
// (a persistent aiming guide for the nadir 0° / oblique 25° stages, never
// auto-hiding) and the same pure logic (`TiltAimGuideState`), but a different
// visual form: a quarter-circle protractor with a needle that rotates with the
// device tilt and a highlighted target wedge. The "rotate the needle into the
// band" metaphor reads more literally as an angle than a sliding puck, and it
// stays correct for both stages because the band is placed at the stage target,
// not at a fixed level.
//
// Switch between this and the vertical gauge with `TiltGuideStyle` in
// CaptureFlowView. Colours match the gauge: in-range snaps to `medataAccent`
// (the badge's in-range accent — not the green/red scheme Decision 19 removed),
// and the needle carries a checkmark / chevron so meaning is never colour-only.

struct TiltDialGuide: View {
    let tiltDegrees: Float
    let awaitingOblique: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // The dial shows tilt over 0…90°; readout still reports the true value.
    private let dialMaxDegrees: Float = 90
    private let radius: CGFloat = 96
    private let trackWidth: CGFloat = 8
    private let hubSize: CGFloat = 30
    // Padding around the arc so the stroke and needle aren't clipped.
    private let margin: CGFloat = 14

    private var target: Float { TiltAimGuideState.target(awaitingOblique: awaitingOblique) }
    private var tolerance: Float { TiltAimGuideState.toleranceDegrees(awaitingOblique: awaitingOblique) }
    private var aligned: Bool {
        TiltAimGuideState.isAligned(tilt: tiltDegrees, target: target, tolerance: tolerance)
    }
    private var correction: Int {
        TiltAimGuideState.correction(tilt: tiltDegrees, target: target, tolerance: tolerance)
    }

    // Tilt clamped into the drawable arc; the readout below shows the real angle.
    private var displayTilt: Float { max(0, min(dialMaxDegrees, tiltDegrees)) }

    // Hub sits at the bottom-leading corner; the arc sweeps up-and-right through
    // the first quadrant. Container is sized to hold the full radius plus margin.
    private var side: CGFloat { radius + margin * 2 }
    private var hub: CGPoint { CGPoint(x: margin, y: side - margin) }

    // Device tilt θ → screen angle: 0° points straight up (−90° in screen
    // space, y-down), increasing tilt rotates clockwise toward 0° (pointing
    // right) at 90°.
    private func screenAngle(_ tilt: Float) -> Angle { .degrees(Double(-90 + tilt)) }

    private func pointOnArc(_ tilt: Float, radius r: CGFloat) -> CGPoint {
        let a = screenAngle(tilt).radians
        return CGPoint(x: hub.x + r * CGFloat(cos(a)), y: hub.y + r * CGFloat(sin(a)))
    }

    private func arcPath(from lo: Float, to hi: Float, radius r: CGFloat) -> Path {
        var p = Path()
        p.addArc(
            center: hub,
            radius: r,
            startAngle: screenAngle(lo),
            endAngle: screenAngle(hi),
            clockwise: false
        )
        return p
    }

    var body: some View {
        VStack(spacing: 8) {
            Text(awaitingOblique ? "Oblique" : "Nadir")
                .font(.caption2.weight(.semibold))
            Text("target \(Int(target))°")
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Color.captureChromeText.opacity(0.7))

            dial

            Text("\(Int(tiltDegrees.rounded()))°")
                .font(.caption2.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(Color.captureChromeText)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("tiltDial")
        .accessibilityLabel(awaitingOblique ? "Oblique tilt guide" : "Nadir tilt guide")
        .accessibilityValue(
            aligned
                ? "Aligned at \(Int(tiltDegrees.rounded())) degrees"
                : "\(Int(tiltDegrees.rounded())) degrees, target \(Int(target)) degrees"
        )
    }

    private var dial: some View {
        ZStack {
            // Full-sweep track.
            arcPath(from: 0, to: dialMaxDegrees, radius: radius)
                .stroke(Color.captureChromeText.opacity(0.18),
                        style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
            // Target band (target ± tolerance), clamped to the drawable range.
            arcPath(from: max(0, target - tolerance),
                    to: min(dialMaxDegrees, target + tolerance),
                    radius: radius)
                .stroke(Color.medataAccent.opacity(0.85),
                        style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
            // Needle from hub to the live angle.
            Path { p in
                p.move(to: hub)
                p.addLine(to: pointOnArc(displayTilt, radius: radius - trackWidth / 2))
            }
            .stroke(aligned ? Color.medataAccent : Color.captureChromeText,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: displayTilt)

            hubBadge
        }
        .frame(width: side, height: side)
    }

    private var hubBadge: some View {
        Circle()
            .fill(aligned ? Color.medataAccent : Color.captureChromeText)
            .frame(width: hubSize, height: hubSize)
            .overlay {
                Image(systemName: aligned ? "checkmark" : (correction > 0 ? "chevron.up" : "chevron.down"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.captureBackground)
            }
            .position(hub)
            .accessibilityIdentifier("tiltDial.hub")
    }
}

import SwiftUI

// Always-visible telemetry capsule above the shutter (Req 2.1 / 2.4). Shows
// live tilt in degrees, subject distance in cm, and a LiDAR dot that pairs
// colour with shape (Req 14.4):
//   • depth available  → green filled ● (`circle.fill`)
//   • no depth (non-LiDAR guidance mode) → grey hollow ○ (`circle`)
// On non-LiDAR devices the distance field shows the static target band
// `30–40 cm` as guidance (copy inventory §2). Replaces the auto-hiding
// `LiveIndicatorBadge`; the pure `LiveIndicatorBadgeState` type it superseded
// lives on (CaptureFlowModel.tiltInRange still calls isSigmaTiltSufficient).
struct TelemetryCapsule: View {
    @Bindable var model: LiveIndicatorModel
    let supportsLiDAR: Bool

    // Depth is available when the device has LiDAR and the working-distance
    // gate has a live reading to show.
    private var hasDepth: Bool { supportsLiDAR && model.liveDistanceCm != nil }

    private var tiltText: String {
        String(format: "%.1f°", model.liveTiltDegrees)
    }

    private var distanceText: String {
        // Non-LiDAR: distance is guidance, so show the static target band.
        guard supportsLiDAR else { return "30–40 cm" }
        guard let cm = model.liveDistanceCm else { return "— cm" }
        return "\(Int(cm.rounded())) cm"
    }

    var body: some View {
        HStack(spacing: 8) {
            field(label: "tilt", value: tiltText)
            separator
            field(label: "dist", value: distanceText)
            separator
            HStack(spacing: 4) {
                Text("LiDAR")
                Image(systemName: hasDepth ? "circle.fill" : "circle")
                    .font(.system(size: 9))
                    .foregroundStyle(hasDepth ? Color.medataAccent : Color.captureChromeText.opacity(0.5))
            }
        }
        .font(.caption.weight(.medium).monospacedDigit())
        .foregroundStyle(Color.captureChromeText)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.captureChromeBG, in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("telemetryCapsule")
    }

    private func field(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(Color.captureChromeText.opacity(0.6))
            Text(value)
        }
    }

    private var separator: some View {
        Text("·").foregroundStyle(Color.captureChromeText.opacity(0.4))
    }
}

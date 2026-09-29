import SwiftUI

/// Soft-failure overlay — the bubble turns amber, ghost copy says what's
/// wrong, and a "skip to 2-view" escape hatch is offered (req §3.7, §4.5).
struct CaptureErrorView: View {
    let kind: CaptureErrorKind

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ViewfinderBackdrop().opacity(0.6)
                Circle()
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(DS.warning)
                    .frame(width: 240, height: 240)
                    .overlay {
                        VStack {
                            Text(headline.uppercased())
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(DS.warning)
                            Text("— hold flatter").font(.caption2).foregroundStyle(.white.opacity(0.85))
                        }
                    }
                VStack {
                    Label("too tilted", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(DS.warning, in: Capsule())
                        .padding(.top, 60)
                    Spacer()
                }
            }
            VStack(alignment: .leading, spacing: DS.spacingS) {
                Text("Hold the phone level").font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: DS.spacingM) {
                    Button("Skip to 2-view") { /* up to caller */ }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                    Button("Cancel") { /* up to caller */ }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, DS.spacingS)
            }
            .padding(DS.spacingL)
            .background(DS.paper)
        }
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headline: String {
        switch kind {
        case .tiltOutOfRange:        return "Tilt 14°"
        case .distanceOutOfRange:    return "Move closer"
        case .trackingLost:          return "Tracking lost"
        case .noLidarNoCard:         return "Add a card"
        case .insufficientLight:     return "More light"
        case .unsupportedDevice:     return "Unsupported"
        }
    }

    private var detail: String {
        switch kind {
        case .tiltOutOfRange:
            return "Top-down view needs to be within ±5° of vertical. Centre the bubble."
        case .distanceOutOfRange:
            return "Hold the phone 30–40 cm from the food."
        case .trackingLost:
            return "We lost our place between views. Retake the second photo."
        case .noLidarNoCard:
            return "Without LiDAR depth we need a reference card in shot to set scale."
        case .insufficientLight:
            return "It's too dark to read the plate edge reliably."
        case .unsupportedDevice:
            return "Medata requires an iPhone with a rear LiDAR scanner."
        }
    }
}

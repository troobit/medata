import Pipeline
import SwiftUI

// Capture-path fork sheet (§3), opened by long-pressing the mode button
// (`fork-sheet.md`). Offers `Quick (1 photo)` (recommended, requires LiDAR) and
// `Two-view`. Each path card is the selector: tapping writes
// `SettingsKeys.captureMode` and dismisses. On non-LiDAR devices the quick path
// is disabled (`LiDAR unavailable`) and two-view is preselected (Req 3.3).
//
// The reference-card toggle seeds from `SettingsKeys.alwaysIncludeCard` (§12.1)
// and writes a per-capture override on the model only — it is not persisted
// (Req 3.2).
struct LidarForkSheetView: View {
    @Bindable var model: CaptureFlowModel

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.captureMode) private var captureModeRaw: String = ""
    @AppStorage(SettingsKeys.alwaysIncludeCard) private var alwaysIncludeCard: Bool = false

    private var supportsLiDAR: Bool { model.supportsLiDAR }

    private var selectedMode: CaptureMode {
        if let m = CaptureMode(rawValue: captureModeRaw) { return m }
        return supportsLiDAR ? .single : .double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            lidarBanner

            pathCard(
                title: "Quick (1 photo)",
                subtitle: "~1 s · LiDAR",
                action: "1 photo",
                badge: "Recommended",
                mode: .single,
                disabled: !supportsLiDAR,
                disabledNote: "LiDAR unavailable"
            )

            pathCard(
                title: "Two-view",
                subtitle: "~2 s · top-down + 25°",
                action: "2 photos",
                badge: nil,
                mode: .double,
                disabled: false,
                disabledNote: nil
            )

            cardSection

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { model.includeCardThisCapture = alwaysIncludeCard }
        .accessibilityIdentifier("lidarForkSheet")
    }

    private var lidarBanner: some View {
        Label(
            supportsLiDAR ? "LiDAR available" : "LiDAR unavailable",
            systemImage: supportsLiDAR ? "checkmark.circle.fill" : "xmark.circle"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(supportsLiDAR ? Color.medataAccent : Color.textSecondary)
    }

    private func pathCard(
        title: String,
        subtitle: String,
        action: String,
        badge: String?,
        mode: CaptureMode,
        disabled: Bool,
        disabledNote: String?
    ) -> some View {
        let selected = selectedMode == mode
        return Button {
            captureModeRaw = mode.rawValue
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.headline)
                    if let badge {
                        Text(badge)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.medataAccent, in: Capsule())
                            .foregroundStyle(Color.black)
                    }
                    Spacer()
                    Text(action)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.medataAccent)
                }
                Text(disabled ? (disabledNote ?? subtitle) : subtitle)
                    .font(.footnote)
                    .foregroundStyle(Color.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color.medataAccent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .opacity(disabled ? 0.5 : 1)
        .disabled(disabled)
        .accessibilityIdentifier("fork.\(mode.rawValue)")
    }

    private var cardSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reference card").font(.headline)
            Text("Improves scale confidence")
                .font(.footnote)
                .foregroundStyle(Color.textSecondary)
            Toggle("Include card", isOn: $model.includeCardThisCapture)
                .tint(.medataAccent)
                .accessibilityIdentifier("fork.includeCard")
        }
    }
}

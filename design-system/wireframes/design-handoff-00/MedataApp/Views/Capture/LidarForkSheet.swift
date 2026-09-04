import SwiftUI

/// Bottom sheet shown when the user taps "info" — explains LiDAR fast path
/// vs canonical two-view, with a reference-card opt-in (req §3.5, §5).
struct LidarForkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var includeCard = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: DS.spacingM) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LiDAR available").font(.subheadline.weight(.semibold))
                        Text("Single photo is enough — distance and shape come from depth.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.success)
                }
                .padding(DS.spacingM)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.successSoft, in: RoundedRectangle(cornerRadius: DS.radiusM))

                pathCard(
                    title: "Quick (1 photo)",
                    subtitle: "~1 s · uses LiDAR depth",
                    badge: "Recommended",
                    primary: true
                ) { dismiss() }

                pathCard(
                    title: "Two-view (canonical)",
                    subtitle: "~1.8 s · top-down + 25° angle. Use when LiDAR can't see the whole plate.",
                    badge: nil,
                    primary: false
                ) { dismiss() }

                VStack(alignment: .leading, spacing: DS.spacingS) {
                    Text("Add a reference card?").font(.subheadline.weight(.semibold))
                    Text("Any ID-1 card (driving licence, bank card) included in shot improves scale confidence.")
                        .font(.caption).foregroundStyle(.secondary)
                    Toggle("Include card this time", isOn: $includeCard)
                        .font(.subheadline)
                }
                .padding(DS.spacingM)
                .background(DS.paperElev, in: RoundedRectangle(cornerRadius: DS.radiusM))

                Spacer(minLength: 0)
            }
            .padding(DS.spacingL)
            .navigationTitle("Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func pathCard(title: String, subtitle: String, badge: String?, primary: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: DS.spacingS) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(DS.success.opacity(0.18), in: Capsule())
                        .foregroundStyle(DS.success)
                }
            }
            Button(action: action) {
                Text(primary ? "Take 1 photo" : "Take 2 photos")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(primary ? AnyButtonStyle(BorderedProminentButtonStyle()) : AnyButtonStyle(BorderedButtonStyle()))
            .controlSize(.large)
        }
        .padding(DS.spacingM)
        .background(DS.paperElev, in: RoundedRectangle(cornerRadius: DS.radiusM))
    }
}

/// Type-erased button style helper so we can return either prominent or plain
/// from the same branch.
struct AnyButtonStyle: ButtonStyle {
    private let _make: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        self._make = { cfg in AnyView(style.makeBody(configuration: cfg)) }
    }
    func makeBody(configuration: Configuration) -> some View { _make(configuration) }
}

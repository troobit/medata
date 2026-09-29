import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.spacingM) {
                Text("Medata estimates the carbohydrate content of a meal from one or two photographs taken on your iPhone. It runs entirely on your device — no photo or measurement leaves the phone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                SectionHeader(text: "Data sources")
                sourceCard(
                    title: "CoFID",
                    body: "McCance & Widdowson's The Composition of Foods Integrated Dataset. Crown Copyright. Released under Open Government Licence v3."
                )
                sourceCard(
                    title: "IFCDB (overlay)",
                    body: "Irish Food Composition Database, optional regional overlay."
                )

                SectionHeader(text: "Method")
                Text("Estimates use shape-from-silhouette and LiDAR depth combined with per-class densities and bulk-correction factors calibrated against an internal test set. See the research spec for the full pipeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                SectionHeader(text: "Legal")
                row("Privacy policy")
                row("Open-source licences")
                row("Not a medical device")
            }
            .padding(DS.spacingL)
        }
        .navigationTitle("About Medata")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
        }
    }

    private func sourceCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(body).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.spacingM)
        .background(DS.paperElev, in: RoundedRectangle(cornerRadius: DS.radiusM))
    }

    private func row(_ title: String) -> some View {
        HStack { Text(title); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
            .padding(.vertical, 8)
            .overlay(Divider(), alignment: .bottom)
    }
}

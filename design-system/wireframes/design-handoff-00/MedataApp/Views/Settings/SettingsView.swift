import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var keepPhotosDays = 30
    @State private var ifcdbOverlay = true
    @State private var alwaysIncludeCard = false
    @State private var defaultPath: CapturePath = .singleViewLidar
    @State private var showingAbout = false

    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Text("Account")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.tertiary)
                .listRowBackground(DS.paperElev.opacity(0.4))
            }

            Section("Photo & data retention") {
                Picker("Keep photos for", selection: $keepPhotosDays) {
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("1 year").tag(365)
                    Text("Indefinitely").tag(-1)
                }
                Button("Delete all photos", role: .destructive) {}
            }

            Section("Food database") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CoFID 2024").font(.subheadline)
                        Text("McCance & Widdowson · OGL v3")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Label("active", systemImage: "checkmark.seal.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(DS.success)
                }
                Toggle(isOn: $ifcdbOverlay) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IFCDB 2023 overlay").font(.subheadline)
                        Text("Irish Food Composition Database")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Section("Capture") {
                Picker("Default path", selection: $defaultPath) {
                    Text("Single-view (LiDAR)").tag(CapturePath.singleViewLidar)
                    Text("Two-view").tag(CapturePath.twoViewSfS)
                }
                Toggle("Always include reference card", isOn: $alwaysIncludeCard)
            }

            Section("About") {
                HStack { Text("Version"); Spacer(); Text("0.2 · research").foregroundStyle(.secondary) }
                Button {
                    showingAbout = true
                } label: {
                    HStack { Text("Attribution & licence"); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
                }
                .foregroundStyle(.primary)
                Button {} label: {
                    HStack { Text("Export all data"); Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $showingAbout) {
            NavigationStack { AboutView() }
        }
    }
}

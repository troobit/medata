import Pipeline
import SwiftUI

// Wraps the exported archive URL so it can drive `.sheet(item:)`.
private struct ArchiveFile: Identifiable {
    let id = UUID()
    let url: URL
}

// Settings rewritten per Decisions 37 and 39. The retention picker and the
// IFCDB toggle are gone; photo lifecycle is delegated to the user's Photos
// library and macros are sourced from the bundled CoFID + AFCD pair with no
// user override.
struct SettingsView: View {
    let store: any PersistenceStore

    @State private var archiveFile: ArchiveFile?
    @State private var isExporting = false
    @State private var exportError: String?

    var body: some View {
        Form {
            Section("About macronutrient sources") {
                Text("Carbohydrate, energy, protein, fat and fibre values are derived from the bundled CoFID 2024 and AFCD 2024 databases.")
                    .font(.footnote)
                Text("CoFID — McCance & Widdowson, Food Standards Agency, Crown Copyright, Open Government Licence v3.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("AFCD — Australian Food Composition Database, Food Standards Australia New Zealand, CC-BY-4.0.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                // nutrition5k-calibration Req 1.5: CC BY 4.0 requires indicating
                // that the shipped values are adapted (derived β factors).
                Text("Nutrition5k — Google Research, CC BY 4.0. Values adapted: portion-volume calibration factors are derived from the dataset.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Photos") {
                Text("Captured meal photos are saved to your Photos library and managed there. Removing a photo from Photos will remove the preview from the meal record, but the carbohydrate estimate is kept.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("Data") {
                Button {
                    exportArchive()
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Label("Export archive", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isExporting)
                if let exportError {
                    Text(exportError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(item: $archiveFile) { file in
            ShareSheet(activityItems: [file.url])
        }
    }

    private func exportArchive() {
        isExporting = true
        exportError = nil
        Task {
            defer { isExporting = false }
            do {
                let path = try await store.exportArchive()
                archiveFile = ArchiveFile(url: URL(fileURLWithPath: path))
            } catch {
                exportError = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}

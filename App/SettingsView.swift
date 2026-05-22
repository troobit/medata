import Pipeline
import SwiftUI

// Keys kept in a single namespace to avoid stringly-typed UserDefaults access.
enum SettingsKeys {
    static let retentionDays = "medata.retentionDays"
    static let ifcdbOverlayEnabled = "medata.ifcdbOverlayEnabled"
}

// Sentinel value for "keep forever" (Req 17.4).
private let indefinite = -1

// Wraps the exported archive URL so it can drive `.sheet(item:)`.
private struct ArchiveFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct SettingsView: View {
    // Retention period: 30, 90, 365 days, or -1 for indefinite (Req 17.4).
    @AppStorage(SettingsKeys.retentionDays) private var retentionDays: Int = 90
    // IFCDB regional overlay toggle (FoodDatabase ATTACH on next launch).
    @AppStorage(SettingsKeys.ifcdbOverlayEnabled) private var ifcdbOverlayEnabled: Bool = false

    let store: any PersistenceStore

    @State private var archiveFile: ArchiveFile?
    @State private var isExporting = false
    @State private var exportError: String?

    private let retentionOptions: [(label: String, days: Int)] = [
        ("30 days", 30),
        ("90 days", 90),
        ("365 days", 365),
        ("Indefinite", indefinite)
    ]

    var body: some View {
        Form {
            Section("Meal History Retention") {
                Picker("Keep meals for", selection: $retentionDays) {
                    ForEach(retentionOptions, id: \.days) { option in
                        Text(option.label).tag(option.days)
                    }
                }
            }
            Section("Database") {
                Toggle("Enable Irish food composition overlay (IFCDB)", isOn: $ifcdbOverlayEnabled)
                Text("When enabled the IFCDB regional values replace the CoFID defaults for matching foods. Takes effect after relaunch.")
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

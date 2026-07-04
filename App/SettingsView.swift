import Pipeline
import SwiftUI

// Wraps the exported archive URL so it can drive `.sheet(item:)`.
private struct ArchiveFile: Identifiable {
    let id = UUID()
    let url: URL
}

// The Settings screen — design-handoff-00 §12, design-system/pages/settings.md.
// A disabled Account row, the bundled food-database editions (CoFID + AFCD, not
// IFCDB — Decision 4), capture defaults (default path + always-include-card),
// data export, and an About link. No photo-retention controls (Req 12.3).
// Attribution now lives in About (§13), not inline here. A DEBUG-only row seeds
// demo glucose so Trends is verifiable before an importer ships (Decision 13).
struct SettingsView: View {
    let store: any PersistenceStore

    @AppStorage(SettingsKeys.captureMode) private var captureMode: CaptureMode = .double
    @AppStorage(SettingsKeys.alwaysIncludeCard) private var alwaysIncludeCard = false

    @State private var archiveFile: ArchiveFile?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showsGlucoseImport = false
    @State private var isSeeding = false

    var body: some View {
        Form {
            Section {
                Button("Account") {}
                    .disabled(true)
                    .accessibilityIdentifier("settings.account")
            }

            Section("Food database") {
                Text("CoFID")
                Text("AFCD")
            }
            Section("Glucose data") {
                Button {
                    showsGlucoseImport = true
                } label: {
                    Label("Import LibreLink screenshots", systemImage: "waveform.path.ecg")
                }
                Text("Extracts glucose readings from FreeStyle LibreLink graph screenshots and stores them with your meals, entirely on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Capture") {
                Picker("Default path", selection: $captureMode) {
                    Text("1-view").tag(CaptureMode.single)
                    Text("2-view").tag(CaptureMode.double)
                }
                Toggle("Always include card", isOn: $alwaysIncludeCard)
            }

            Section {
                Button {
                    exportArchive()
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isExporting)
                .accessibilityIdentifier("settings.export")
                if let exportError {
                    Text(exportError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                NavigationLink("About") { AboutView() }
                    .accessibilityIdentifier("settings.about")
            }

            #if DEBUG
            Section {
                Button {
                    seedDemoGlucose()
                } label: {
                    if isSeeding {
                        ProgressView()
                    } else {
                        Text("Seed demo glucose")
                    }
                }
                .disabled(isSeeding)
                .accessibilityIdentifier("settings.seedGlucose")
            }
            #endif
        }
        .navigationTitle("Settings")
        .sheet(item: $archiveFile) { file in
            ShareSheet(activityItems: [file.url])
        }
        .sheet(isPresented: $showsGlucoseImport) {
            GlucoseImportView(store: store)
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

    #if DEBUG
    private func seedDemoGlucose() {
        guard let grdb = store as? GRDBPersistenceStore else { return }
        isSeeding = true
        Task {
            defer { isSeeding = false }
            try? await grdb.seedDemoBslEvents()
        }
    }
    #endif
}

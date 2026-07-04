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
    // Fresh-install default forks on device capability (Req 16.2 / Decision 9):
    // 1-view on LiDAR devices, 2-view otherwise. Passed from AppRoot so the
    // Picker resolves an unset key the same way `CaptureFlowView.effectiveMode`
    // and `defaultCaptureModeReader` do, instead of hard-defaulting to `.double`.
    let hasLiDAR: Bool

    @Environment(\.dismiss) private var dismiss
    // Empty string means the capture-mode key is unset — `captureModeBinding`
    // then resolves the effective default from `hasLiDAR`. Writing persists the
    // raw value back under the same `SettingsKeys.captureMode` key.
    @AppStorage(SettingsKeys.captureMode) private var captureModeRaw: String = ""
    @AppStorage(SettingsKeys.alwaysIncludeCard) private var alwaysIncludeCard = false

    private var captureModeBinding: Binding<CaptureMode> {
        Binding(
            get: { CaptureMode(rawValue: captureModeRaw) ?? (hasLiDAR ? .single : .double) },
            set: { captureModeRaw = $0.rawValue }
        )
    }

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
                // Explainer footnote removed under the developer-phase copy rule
                // (Req 14.5 / Decision 21).
            }

            Section("Capture") {
                Picker("Default path", selection: captureModeBinding) {
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
                        MedataLoadingSymbol(mode: .loop, size: 22)
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
                        MedataLoadingSymbol(mode: .loop, size: 22)
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CloseCoverButton { dismiss() }
            }
        }
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

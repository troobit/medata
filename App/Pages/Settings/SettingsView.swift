import Pipeline
import SwiftUI

// Wraps the exported archive URL so it can drive `.sheet(item:)`.
private struct ArchiveFile: Identifiable {
    let id = UUID()
    let url: URL
}

// The Settings screen — design-handoff-00 §12, design-system/pages/settings.md,
// restructured by specs/ui/settings-information-architecture.
//
// The top level is rows, not controls: a disabled Account row, one
// `NavigationLink` per area (Glucose, Capture, Insulin — and Developer in the
// field builds), the two estimation surfaces, the archive export, and About.
// Every editable control lives on the screen its row opens, following the
// About pattern (`App/Pages/About/AboutView.swift`).
//
// The bundled food-composition editions are NOT listed here: they are
// attributed under About › Data sources, and a second copy in Settings was
// duplication with nothing to do (backlog 31). No photo-retention controls
// (Req 12.3).
struct SettingsView: View {
    let store: any PersistenceStore
    // The recurring dose schedule (specs/data/dose-schedule Req 1.3, 1.4, 3.2,
    // 3.3). Owned by AppRoot so the outstanding set survives this cover being
    // presented and dismissed. Edited on the Insulin screen.
    let doseSchedule: DoseScheduleModel
    // Fresh-install default forks on device capability (Req 16.2 / Decision 9):
    // 1-view on LiDAR devices, 2-view otherwise. Passed from AppRoot so the
    // Capture screen's Picker resolves an unset key the same way
    // `CaptureFlowView.effectiveMode` and `defaultCaptureModeReader` do.
    let hasLiDAR: Bool
    // Live glucose-source connections (cgm-connect Req 6), owned by MedataApp
    // and threaded through AppRoot.
    let glucoseConnections: GlucoseConnectionsModel
    // Current segmenter lineage tag (snaq-parity): scopes the benchmark
    // report and labels the log. AppRoot passes `captureModel.segmenterSource`.
    let captureLineage: String
    // Benchmark capture launch (snaq-parity lane B). Settings cannot present
    // the Capture cover itself — Capture and Settings are mutually-exclusive
    // covers on AppRoot — so this closure hands the meal id up to AppRoot,
    // which tags `CaptureFlowModel.benchmarkMealID` and sequences
    // dismiss-Settings → present-Capture through its deep-link machinery.
    let onBenchmarkCapture: (UUID) -> Void
    // The outstanding-dose gear lands here: when set, Settings pushes the
    // Insulin screen on appear, which opens itself at the dose schedule.
    var scrollToDoseSchedule: Bool = false

    @Environment(\.dismiss) private var dismiss

    @State private var archiveFile: ArchiveFile?
    @State private var isExporting = false
    @State private var exportError: String?
    // The dose-schedule deep link, pushed once. Without the one-shot guard the
    // push would repeat every time this view reappears — including the moment
    // the developer taps back out of it.
    @State private var opensInsulin = false
    @State private var didOpenInsulin = false

    var body: some View {
        Form {
            Section {
                Button("Account") {}
                    .disabled(true)
                    .accessibilityIdentifier("settings.account")
            }

            Section {
                NavigationLink("Glucose") {
                    GlucoseSettingsView(store: store, glucoseConnections: glucoseConnections)
                }
                .accessibilityIdentifier("settings.glucose")
                NavigationLink("Capture") {
                    CaptureSettingsView(hasLiDAR: hasLiDAR)
                }
                .accessibilityIdentifier("settings.capture")
                NavigationLink("Insulin") {
                    InsulinSettingsView(doseSchedule: doseSchedule)
                }
                .accessibilityIdentifier("settings.insulin")
            }

            Section {
                // Outside any developer guard deliberately: Req 2.3 requires the
                // estimation log (and the benchmark that reads it) to operate in
                // Release builds.
                NavigationLink("Estimation log") {
                    EstimationLogView(store: store, lineage: captureLineage)
                }
                .accessibilityIdentifier("settings.estimationLog")
                NavigationLink("Benchmark") {
                    BenchmarkView(
                        store: store,
                        lineage: captureLineage,
                        onCapture: onBenchmarkCapture
                    )
                }
                .accessibilityIdentifier("settings.benchmark")
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
                NavigationLink("About") { AboutView() }
                    .accessibilityIdentifier("settings.about")
            }

            #if FIELD_LOOP
            // The row and its whole screen compile only in the field profiles
            // (Debug and Release); ProductRelease has no Developer row.
            Section {
                NavigationLink("Developer") {
                    DeveloperSettingsView(store: store)
                }
                .accessibilityIdentifier("settings.developer")
            }
            #endif
        }
        // Deliberately untitled (snaqui Req 4); inline mode so no large-title
        // band is reserved.
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $opensInsulin) {
            InsulinSettingsView(doseSchedule: doseSchedule, scrollToDoseSchedule: true)
        }
        .onAppear {
            guard scrollToDoseSchedule, !didOpenInsulin else { return }
            didOpenInsulin = true
            opensInsulin = true
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                CloseCoverButton { dismiss() }
            }
        }
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

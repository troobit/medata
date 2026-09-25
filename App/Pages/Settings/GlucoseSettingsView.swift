import GlucoseWidgetShared
import Pipeline
import SwiftUI

// Glucose preferences, reached from Settings (specs/ui/settings-information-
// architecture). Sources, the LibreLink screenshot importer, and the blood-hold
// window that decides how long a finger-prick outranks a newer sensor reading
// (specs/data/fingerprick-glucose Req 3.2).
struct GlucoseSettingsView: View {
    let store: any PersistenceStore
    let glucoseConnections: GlucoseConnectionsModel

    // Seconds on disk, minutes in the control. App-private and deliberately not
    // App Group state: what crosses to the widget is the resolved absolute
    // `holdsUntil`, never this (Decision 8).
    @AppStorage(SettingsKeys.glucoseHoldWindowSeconds)
    private var glucoseHoldWindowSeconds: Double = GlucoseHoldWindow.defaultSeconds

    @State private var showsGlucoseImport = false
    @State private var showsGlucoseSources = false

    var body: some View {
        Form {
            Section {
                Button {
                    showsGlucoseSources = true
                } label: {
                    Label("Glucose sources", systemImage: "sensor.tag.radiowaves.forward")
                }
                .accessibilityIdentifier("settings.glucoseSources")
                Button {
                    showsGlucoseImport = true
                } label: {
                    Label("Import LibreLink screenshots", systemImage: "waveform.path.ecg")
                }
            }

            Section {
                Stepper(value: $glucoseHoldWindowSeconds,
                        in: GlucoseHoldWindow.rangeSeconds,
                        step: 300) {
                    LabeledContent(
                        "Blood hold", value: Self.minutesLabel(glucoseHoldWindowSeconds))
                }
                .accessibilityIdentifier("settings.glucoseHoldWindow")
                // The one thing a longer window silently changes: the staleness
                // ladder measures a reading's age from its own instant and knows
                // nothing of the hold (Decision 3), so past this point a held
                // reading renders as stale while still holding. Stated as the
                // number it is, and only where the two diverge — a fact about
                // the render, not a warning about the setting.
                if glucoseHoldWindowSeconds > GlucoseTimeline.staleAge {
                    LabeledContent(
                        "Renders stale after",
                        value: Self.minutesLabel(GlucoseTimeline.staleAge))
                }
            }
        }
        .navigationTitle("Glucose")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsGlucoseImport) {
            GlucoseImportView(store: store)
        }
        .sheet(isPresented: $showsGlucoseSources) {
            GlucoseConnectionsView(model: glucoseConnections)
        }
    }

    // Seconds on disk, minutes on screen — the key is named in seconds so the
    // reader hands a `TimeInterval` straight to the derivation with no unit
    // conversion in between, and this is the one place that converts.
    private static func minutesLabel(_ seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded())) min"
    }
}

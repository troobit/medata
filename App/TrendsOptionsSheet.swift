import SwiftUI

// The Trends graph-options sheet — design-handoff-00 §10.8, design-system/pages/
// trends.md. Per-metric toggles with one-line source captions, a target-band
// toggle, a disabled Protein · Fat row, and the glucose y-scale control
// (Auto, or Fixed with an 8–25 mmol/L max stepper). All options persist via the
// same @AppStorage keys the chart reads, so this sheet and TrendsView stay in
// sync.
struct TrendsOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(SettingsKeys.trendsShowCarbs) private var showCarbs = true
    @AppStorage(SettingsKeys.trendsShowGlucose) private var showGlucose = true
    @AppStorage(SettingsKeys.trendsShowTargetBand) private var showTargetBand = true
    @AppStorage(SettingsKeys.trendsScaleFixed) private var scaleFixed = false
    @AppStorage(SettingsKeys.trendsFixedMax) private var fixedMax = 14

    var body: some View {
        NavigationStack {
            Form {
                Section("Metrics") {
                    toggleRow("Carbs", caption: "bars · meals", isOn: $showCarbs)
                    toggleRow("Glucose", caption: "line · glucose import", isOn: $showGlucose)
                    disabledRow("Protein · Fat", caption: "soon")
                }
                Section {
                    Toggle(isOn: $showTargetBand) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Target band")
                            Text("3.9–10.0 mmol/L")
                                .font(.caption)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
                Section("Scale") {
                    Picker("Scale", selection: $scaleFixed) {
                        Text("Auto").tag(false)
                        Text("Fixed").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if scaleFixed {
                        Stepper("Max \(fixedMax) mmol/L", value: $fixedMax, in: 8...25)
                            .accessibilityIdentifier("trends.options.max")
                    }
                }
            }
            .navigationTitle("Options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func toggleRow(_ title: String, caption: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    private func disabledRow(_ title: String, caption: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .foregroundStyle(Color.textSecondary.opacity(0.6))
    }
}

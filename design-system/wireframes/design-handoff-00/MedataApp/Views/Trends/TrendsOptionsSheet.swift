import SwiftUI

/// User-tunable graph options for TrendsView — which metrics to draw and
/// how the glucose y-axis is scaled.
struct TrendsGraphOptions {
    var showCarbs = true
    var showGlucose = true
    var showTargetBand = true

    enum ScaleMode: String, CaseIterable, Identifiable {
        case auto = "Auto", fixed = "Fixed"
        var id: String { rawValue }
    }
    var scaleMode: ScaleMode = .auto
    var fixedMaxMmolPerL: Double = 12
}

struct TrendsOptionsSheet: View {
    @Binding var options: TrendsGraphOptions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Metrics") {
                    Toggle(isOn: $options.showCarbs) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Carbs")
                            Text("bars · from meal captures")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $options.showGlucose) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Blood glucose")
                            Text("line · from CGM / meter import")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Toggle(isOn: $options.showTargetBand) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Target range band")
                            Text("3.9 – 10.0 mmol/L")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!options.showGlucose)

                    // Future macros — placeholder, intentionally disabled.
                    Toggle(isOn: .constant(false)) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Protein · Fat").foregroundStyle(Color(.tertiaryLabel))
                            Text("coming later")
                                .font(.caption2).foregroundStyle(Color(.tertiaryLabel))
                        }
                    }
                    .disabled(true)
                }

                Section("Scale") {
                    Picker("Glucose y-axis", selection: $options.scaleMode) {
                        ForEach(TrendsGraphOptions.ScaleMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)

                    if options.scaleMode == .fixed {
                        Stepper(value: $options.fixedMaxMmolPerL, in: 8...25, step: 1) {
                            HStack {
                                Text("Fixed max")
                                Spacer()
                                Text("\(Int(options.fixedMaxMmolPerL)) mmol/L")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Graph options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

import SwiftUI

// Keys kept in a single namespace to avoid stringly-typed UserDefaults access.
enum SettingsKeys {
    static let retentionDays = "medata.retentionDays"
    static let ifcdbOverlayEnabled = "medata.ifcdbOverlayEnabled"
}

// Sentinel value for "keep forever" (Req 17.4).
private let indefinite = -1

struct SettingsView: View {
    // Retention period: 30, 90, 365 days, or -1 for indefinite (Req 17.4).
    @AppStorage(SettingsKeys.retentionDays) private var retentionDays: Int = 90
    // IFCDB regional overlay toggle (FoodDatabase ATTACH on next launch).
    @AppStorage(SettingsKeys.ifcdbOverlayEnabled) private var ifcdbOverlayEnabled: Bool = false

    private let retentionOptions: [(label: String, days: Int)] = [
        ("30 days",     30),
        ("90 days",     90),
        ("365 days",    365),
        ("Indefinite",  indefinite)
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
        }
        .navigationTitle("Settings")
    }
}

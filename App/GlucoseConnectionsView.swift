import GlucoseIngestion
import SwiftUI

// Glucose-source connections screen (specs/data/cgm-connect Req 6), presented
// as a sheet from the "Glucose data" section in Settings — same pattern as
// the screenshot-import sheet. One section per source showing its connection
// state, last-reading time, and — for LibreLinkUp — the last successful
// fetch and the in-session discrepancy count (Decision 9). Functional copy
// only (Req 6.3, Decision 6); mmol/L is the only unit anywhere (Req 6.4).
struct GlucoseConnectionsView: View {
    let model: GlucoseConnectionsModel

    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        NavigationStack {
            Form {
                healthKitSection
                libreLinkUpSection
            }
            .navigationTitle("Glucose sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var healthKitSection: some View {
        Section("Apple Health") {
            stateRows(for: model.healthKitID)
            if model.userHasConnected(model.healthKitID) {
                Button("Disconnect", role: .destructive) {
                    model.disconnect(model.healthKitID)
                }
                .accessibilityIdentifier("glucose.healthkit.disconnect")
            } else {
                // Presents the OS Health-access sheet via the source (Req 2.1).
                Button("Connect Apple Health") {
                    model.connectHealthKit()
                }
                .accessibilityIdentifier("glucose.healthkit.connect")
            }
        }
    }

    private var libreLinkUpSection: some View {
        Section("LibreLinkUp") {
            stateRows(for: model.libreLinkUpID)
            if model.userHasConnected(model.libreLinkUpID) {
                if let fetchedAt = model.libreLinkUpLastSuccessAt {
                    LabeledContent("Last fetch", value: Self.timeString(fetchedAt))
                }
                if let count = model.discrepancyCounts[model.libreLinkUpID], count > 0 {
                    // Readings that arrived differing by more than
                    // 0.3 mmol/L from a stored value this session (Req 5.4).
                    LabeledContent("Discrepancies this session", value: "\(count)")
                }
                Button("Disconnect", role: .destructive) {
                    model.disconnect(model.libreLinkUpID)
                }
                .accessibilityIdentifier("glucose.librelinkup.disconnect")
            } else {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("glucose.librelinkup.email")
                SecureField("Password", text: $password)
                    .accessibilityIdentifier("glucose.librelinkup.password")
                Button("Connect LibreLinkUp") {
                    model.connectLibreLinkUp(email: email, password: password)
                    password = ""
                }
                .disabled(email.isEmpty || password.isEmpty)
                .accessibilityIdentifier("glucose.librelinkup.connect")
            }
        }
    }

    // State per Req 6.1: Not connected / Connected (+ last-reading time) /
    // Failed with the reason. LibreLinkUp's last-success time renders from
    // the persisted value above, so the failed case stays a single line.
    @ViewBuilder
    private func stateRows(for sourceID: String) -> some View {
        switch model.states[sourceID] ?? .notConnected {
        case .notConnected:
            LabeledContent("State", value: "Not connected")
        case .connected(let lastReadingAt):
            LabeledContent("State", value: "Connected")
            if let lastReadingAt {
                LabeledContent("Last reading", value: Self.timeString(lastReadingAt))
            }
        case .failed(let reason, _):
            LabeledContent("State", value: "Failed")
            Text(reason)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    // Same en_IE medium/short format as the Records rows.
    private static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

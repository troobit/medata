import GlucoseIngestion
import SwiftUI

// Glucose-source connections screen (specs/data/cgm-connect Req 6), presented
// as a sheet from the "Glucose data" section in Settings — same pattern as
// the screenshot-import sheet. One section per source showing its connection
// state, last-reading time, the in-session discrepancy count (Req 5.4,
// Decision 9) and — for LibreLinkUp — the last successful fetch. Functional
// copy only (Req 6.3, Decision 6); mmol/L is the only unit anywhere (Req 6.4).
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
            if model.connectedSourceIDs.contains(model.healthKitID) {
                Button("Disconnect", role: .destructive) {
                    model.disconnect(model.healthKitID)
                }
                .disabled(model.busySourceIDs.contains(model.healthKitID))
                .accessibilityIdentifier("glucose.healthkit.disconnect")
            } else {
                // Presents the OS Health-access sheet via the source (Req 2.1).
                Button("Connect Apple Health") {
                    model.connectHealthKit()
                }
                .disabled(model.busySourceIDs.contains(model.healthKitID))
                .accessibilityIdentifier("glucose.healthkit.connect")
            }
        }
    }

    @ViewBuilder
    private var libreLinkUpSection: some View {
        let connected = model.connectedSourceIDs.contains(model.libreLinkUpID)
        let busy = model.busySourceIDs.contains(model.libreLinkUpID)
        Section("LibreLinkUp") {
            stateRows(for: model.libreLinkUpID)
            if connected, let fetchedAt = model.libreLinkUpLastSuccessAt {
                LabeledContent("Last fetch", value: Self.timeString(fetchedAt))
            }
            // The form also shows while connected-but-failed, so wrong
            // credentials can be corrected in place (a re-connect stores the
            // new credentials and retries).
            if !connected || libreLinkUpFailed {
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
                .disabled(email.isEmpty || password.isEmpty || busy)
                .accessibilityIdentifier("glucose.librelinkup.connect")
            }
            if connected {
                Button("Disconnect", role: .destructive) {
                    model.disconnect(model.libreLinkUpID)
                }
                .disabled(busy)
                .accessibilityIdentifier("glucose.librelinkup.disconnect")
            }
        }
    }

    private var libreLinkUpFailed: Bool {
        if case .failed = model.states[model.libreLinkUpID] { return true }
        return false
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
        if let count = model.discrepancyCounts[sourceID], count > 0 {
            // Readings that arrived differing by more than 0.3 mmol/L from a
            // stored value this session (Req 5.4) — shown for every source.
            LabeledContent("Discrepancies this session", value: "\(count)")
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

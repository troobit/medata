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
                heartbeatSection
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

    // BLE heartbeat wake (specs/data/cgm-direct Req 5.1, 5.6). Disabled by
    // default behind the developer-phase enable (Req 6.1); enabling starts
    // the foreground pairing scan and triggers the Bluetooth permission
    // prompt. Functional copy only (Req 5.4).
    @ViewBuilder
    private var heartbeatSection: some View {
        Section("Sensor heartbeat") {
            if let heartbeat = model.heartbeat, model.heartbeatEnabled {
                // `stale` is defined by the absence of a beat, so the state
                // row derives it inside a periodic timeline — truthful
                // whenever it is on screen, no timer in the source (Req 5.2).
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    LabeledContent(
                        "State",
                        value: Self.heartbeatStateText(
                            heartbeat.state, lastBeatAt: heartbeat.lastBeatAt, now: context.date))
                }
                .accessibilityIdentifier("glucose.heartbeat.state")
                if case .unavailable(let reason) = heartbeat.state {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if let lastBeatAt = heartbeat.lastBeatAt {
                    // Persisted, so the row survives a relaunch (Req 5.7).
                    LabeledContent("Last heartbeat", value: Self.timeString(lastBeatAt))
                        .accessibilityIdentifier("glucose.heartbeat.lastBeat")
                }
                if case .pairing(.some(let sensorName)) = heartbeat.state {
                    Button("Confirm \(sensorName)") {
                        model.confirmHeartbeatPairing()
                    }
                    .accessibilityIdentifier("glucose.heartbeat.confirm")
                }
                // BLE cannot tell "out of range for a while" from "sensor
                // replaced", so the re-pair action rides every settled state,
                // not just repairNeeded — the user knows they swapped
                // (Req 2.4a, design "Swap detection is manual").
                switch heartbeat.state {
                case .connected, .stale, .repairNeeded:
                    Button("Re-pair sensor") {
                        model.enableHeartbeat()
                    }
                    .accessibilityIdentifier("glucose.heartbeat.repair")
                case .idle, .unavailable, .pairing:
                    EmptyView()
                }
                Button("Disable", role: .destructive) {
                    model.disableHeartbeat()
                }
                .accessibilityIdentifier("glucose.heartbeat.disable")
            } else {
                LabeledContent("State", value: "Off")
                Button("Enable heartbeat") {
                    model.enableHeartbeat()
                }
                .accessibilityIdentifier("glucose.heartbeat.enable")
            }
        }
    }

    // Req 5.6: each functional state a user diagnosing "is the wake working"
    // must tell apart. The unavailable row's next-step copy renders beneath.
    private static func heartbeatStateText(
        _ state: HeartbeatConnectionState, lastBeatAt: Date?, now: Date
    ) -> String {
        switch state {
        case .idle:
            return "Starting"
        case .unavailable:
            return "Unavailable"
        case .pairing(nil):
            return "Scanning for the sensor"
        case .pairing(.some):
            return "Sensor found"
        case .connected, .stale:
            let stale = Libre3Heartbeat.isStale(
                now: now, lastBeatAt: lastBeatAt,
                staleWindow: Libre3Heartbeat.Constants.staleWindow)
            return stale ? "Stale" : "Connected"
        case .repairNeeded:
            return "Re-pair sensor"
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
        if let count = model.discrepancyCounts[sourceID], count > 0 {
            // Readings that arrived differing by more than 0.3 mmol/L from a
            // stored value this session (Req 5.4) — shown for every source.
            LabeledContent("Discrepancies this session", value: "\(count)")
        }
    }

    // Same en_IE medium/short format as the Records rows (shared cached
    // formatter, specs/ui/shared-meal-components Req 4.2).
    private static func timeString(_ date: Date) -> String {
        MedataFormat.dateTimeString(date)
    }
}

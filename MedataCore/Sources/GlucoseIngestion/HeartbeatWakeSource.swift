import Foundation

// BLE heartbeat wake source (specs/data/cgm-direct Req 1). A wake source is
// deliberately NOT a GlucoseSource (Decision 1): in Phase A the sensor's BLE
// payload is not decrypted, so a heartbeat carries no glucose value — it is a
// "a reading exists now" signal that triggers the existing LibreLinkUp cloud
// fetch, and the type system keeps a value-less signal from masquerading as a
// reading. A wake source never writes, modifies, or deletes any event
// (Req 1.2).
//
// @MainActor protocol, not Sendable + async: the only conformer is a
// main-actor class (Decision 10 — CBCentralManagerDelegate is an @objc
// protocol an actor cannot conform to) and its consumer is the
// already-@MainActor GlucoseConnectionsModel.
@MainActor
public protocol HeartbeatWakeSource: AnyObject {
    var id: String { get }
    // The conformer is @Observable, so reads of these from SwiftUI track.
    var state: HeartbeatConnectionState { get }
    var lastBeatAt: Date? { get }
    // Foreground wildcard scan (iOS delivers wildcard scans in the foreground
    // only — Req 2.1, Decision 8); a discovered candidate surfaces in
    // `state` as .pairing(sensorName:) awaiting confirmation.
    func startPairing()
    // Persist the confirmed peripheral's identifier and connect (Req 2.1).
    func confirmPairing()
    // Reconnect to the persisted sensor — the launch path. On a restoration
    // relaunch the OS already holds the connection; resume re-arms the notify
    // subscription (Req 2.7).
    func resume()
    // Cancel connection and scanning; persisted identifier kept (Req 5.3).
    func stop()
}

// Connection state as surfaced in Settings (Req 5.6): each functional state a
// user diagnosing "is the wake working" must tell apart, with a next step.
// `stale` alone is defined by the ABSENCE of an event, so it is derived at
// display time via `Libre3Heartbeat.isStale`, not set by the source (design
// "State ownership").
public enum HeartbeatConnectionState: Sendable, Equatable {
    case idle                         // constructed, not started
    case unavailable(String)          // Bluetooth off / permission denied, with next-step copy
    case pairing(sensorName: String?) // scanning; non-nil when a candidate awaits confirmation
    case connected
    case stale                        // > staleWindow since last beat (Req 5.2, display-derived)
    case repairNeeded                 // persisted sensor gone; foreground re-pair (Req 2.4a)
}

// The pure decision logic and the BLE identifiers, kept free of CoreBluetooth
// types so they compile and unit-test on the macOS host (Decision 6) while the
// Libre3HeartbeatSource central itself is os(iOS)-only. Mirrors the
// LibreLinkUpGlucoseSource.nextPollInterval split: the timing thresholds are
// the bug-prone part; the delegate glue is device-verified.
public enum Libre3Heartbeat {

    // All BLE identifiers are easily-updated constants, as Abbott changes
    // them (Req 2.1).
    public enum Constants {
        public static let namePrefix = "ABBOTT"
        // The one-minute reading characteristic — the notify source
        // (feasibility note "Evidence: heartbeat is real"). Kept as a String;
        // the CBUUID is made at the use site so this type stays
        // CoreBluetooth-free.
        public static let notifyCharacteristicUUID = "0898177A-EF89-11E9-81B4-2A2AE2DBCCE4"
        public static let restoreIdentifier = "com.medata.libre3.heartbeat"
        // Req 2.5: debounce floor, xdripswift's proven
        // minimumTimeBetweenTwoHeartBeats.
        public static let minInterval: TimeInterval = 30
        // Req 5.2: one missed minute-tick plus margin, the proven
        // disconnect-warning threshold.
        public static let staleWindow: TimeInterval = 70
        // Req 3.3: wait for Abbott's app to upload the just-produced reading
        // before the fetch runs, so the fetch returns the newest value.
        public static let preFetchDelay: TimeInterval = 1
    }

    // Req 2.5: a burst of BLE callbacks (didConnect immediately followed by a
    // notify, or several notifies) yields at most one trigger per interval.
    // The boundary belongs to firing — "no less than 30 seconds" — and a nil
    // lastBeatAt (first beat since enable) always fires.
    public static func shouldFire(now: Date, lastBeatAt: Date?, minInterval: TimeInterval) -> Bool {
        guard let lastBeatAt else { return true }
        return now.timeIntervalSince(lastBeatAt) >= minInterval
    }

    // Req 5.2: stale means no beat for LONGER than the window — strictly
    // greater, so exactly staleWindow old is still fresh. nil is stale:
    // lastBeatAt persists across relaunches (Req 5.7), so nil genuinely means
    // no beat since the heartbeat was enabled, and the first beat on connect
    // replaces it within a minute.
    public static func isStale(now: Date, lastBeatAt: Date?, staleWindow: TimeInterval) -> Bool {
        guard let lastBeatAt else { return true }
        return now.timeIntervalSince(lastBeatAt) > staleWindow
    }

    // Req 2.1: the pairing scan surfaces peripherals whose advertised name
    // begins with the Abbott prefix. Case-sensitive — the sensor advertises
    // the prefix in capitals; casing drift means it is not the sensor.
    public static func matchesSensor(advertisedName: String?, prefix: String) -> Bool {
        advertisedName?.hasPrefix(prefix) ?? false
    }
}

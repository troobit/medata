// Libre 3/3+ BLE heartbeat central (specs/data/cgm-direct Phase A, Decision 10).
//
// A SECOND central riding the sensor link Abbott's app owns (Req 2.2): it
// holds no authenticated pairing, adds no radio traffic, and observes
// connection and notify events only. Every beat is value-less — the payload
// stays encrypted in Phase A — and the only effect of a beat is the
// `onHeartbeat` closure the model supplied at construction (Req 1.2), which
// triggers the rate-gated LibreLinkUp cloud fetch.
//
// The whole class is os(iOS): CoreBluetooth state restoration — the relaunch
// mechanism the wake depends on — does not exist on macOS, and
// `canImport(CoreBluetooth)` excludes nothing there (Decision 6). The
// delegate flow is device-verified only, like HealthKitGlucoseSource's
// observer path; the timing decisions live in the cross-platform
// `Libre3Heartbeat` statics, unit-tested on the macOS host.
#if os(iOS)
import CoreBluetooth
import Foundation
import Observation

// Main-actor NSObject, not an actor: CBCentralManagerDelegate is an @objc
// protocol an actor cannot conform to, and `queue: nil` delivers delegate
// callbacks on the main queue, so main-actor isolation matches delivery
// exactly (the @preconcurrency conformances assert it at runtime). FIFO
// delegate ordering keeps the debounce's read-modify-write of `lastBeatAt`
// correct; at one event a minute, main-thread cost is nil (Decision 10).
@Observable @MainActor
public final class Libre3HeartbeatSource: NSObject, HeartbeatWakeSource,
    @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate {

    public let id = "libre3-heartbeat"

    public private(set) var state: HeartbeatConnectionState = .idle
    // Req 5.7: persisted app-private so the Settings row survives a relaunch —
    // after a background restoration relaunch, a healthy connection must not
    // display an empty last-beat.
    public private(set) var lastBeatAt: Date?

    // Non-secret persisted state, same key family as the other sources.
    private static let lastBeatDefaultsKey = "glucose.source.libre3-heartbeat.lastBeatAt"
    private static let identifierDefaultsKey = "glucose.source.libre3-heartbeat.peripheralIdentifier"
    private static let sensorNameDefaultsKey = "glucose.source.libre3-heartbeat.sensorName"

    // Attached AT CONSTRUCTION (Decision 10): Apple delivers willRestoreState
    // as the first delegate call when relaunching the app into the background,
    // so there must be no attach-later window in which a restored event could
    // fire against a detached trigger (Req 2.7).
    private let onHeartbeat: @MainActor () -> Void

    @ObservationIgnored private var central: CBCentralManager!
    @ObservationIgnored private var peripheral: CBPeripheral?
    @ObservationIgnored private var pairingCandidate: CBPeripheral?
    // retrieve/connect (and scans) are legal only at .poweredOn, so resume()
    // and startPairing() record intent and centralManagerDidUpdateState acts
    // on it when power arrives — the standard CoreBluetooth launch sequence.
    @ObservationIgnored private var wantsConnection = false
    @ObservationIgnored private var wantsPairing = false

    public init(onHeartbeat: @escaping @MainActor () -> Void) {
        self.onHeartbeat = onHeartbeat
        let stored = UserDefaults.standard.double(forKey: Self.lastBeatDefaultsKey)
        self.lastBeatAt = stored > 0 ? Date(timeIntervalSince1970: stored) : nil
        super.init()
        // The restore identifier is what lets iOS relaunch the app into the
        // background and hand back the already-connected peripheral (Req 2.7).
        // Constructing the central triggers the Bluetooth permission prompt,
        // which is why the model constructs this source only when the
        // developer-phase flag is set (Req 6.1).
        self.central = CBCentralManager(
            delegate: self, queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: Libre3Heartbeat.Constants.restoreIdentifier]
        )
    }

    // MARK: - HeartbeatWakeSource

    // Foreground wildcard scan (Req 2.1, Decision 8): iOS does not deliver
    // wildcard scans in the background, and re-pairing after a sensor swap is
    // deliberately a foreground action (Req 2.4a).
    public func startPairing() {
        pairingCandidate = nil
        wantsPairing = true
        wantsConnection = false
        state = .pairing(sensorName: nil)
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil)
        }
    }

    // Persist the confirmed sensor and connect (Req 2.1). Subsequent connects
    // retrieve by this identifier with no scan.
    public func confirmPairing() {
        guard let candidate = pairingCandidate else { return }
        central.stopScan()
        wantsPairing = false
        wantsConnection = true
        UserDefaults.standard.set(candidate.identifier.uuidString, forKey: Self.identifierDefaultsKey)
        UserDefaults.standard.set(candidate.name, forKey: Self.sensorNameDefaultsKey)
        // A previous sensor's connection is displaced by the new pairing.
        if let old = peripheral, old.identifier != candidate.identifier {
            central.cancelPeripheralConnection(old)
        }
        connect(candidate)
    }

    // The launch path: reconnect to the persisted sensor. On a restoration
    // relaunch the OS already holds the connection — willRestoreState has
    // recovered the peripheral by the time power reports on, and the connect
    // resolves as a re-arm rather than a new link.
    public func resume() {
        wantsConnection = true
        if central.state == .poweredOn {
            connectToPersistedPeripheral()
        }
    }

    // Cancel connection and scanning. The persisted identifier is kept
    // (Req 5.3) — disable is additive-off, re-enable finds the sensor again.
    public func stop() {
        wantsConnection = false
        wantsPairing = false
        pairingCandidate = nil
        central.stopScan()
        if let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        state = .idle
    }

    // MARK: - The beat (Req 2.5, 5.7)

    // On didConnect AND didUpdateValueFor: on a shared persistent link
    // didConnect fires once, so the per-minute beat comes from the notify
    // subscription; the debounce collapses the connect+notify burst.
    private func beat() {
        let now = Date()
        guard Libre3Heartbeat.shouldFire(
            now: now, lastBeatAt: lastBeatAt,
            minInterval: Libre3Heartbeat.Constants.minInterval)
        else { return }
        lastBeatAt = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: Self.lastBeatDefaultsKey)
        onHeartbeat()
    }

    // MARK: - Connect plumbing

    private func connect(_ target: CBPeripheral) {
        peripheral = target
        target.delegate = self
        // A pending connect to a known peripheral has no timeout: it survives
        // suspension and relaunch and completes from the background when the
        // sensor comes into range — this is the wake mechanism (Req 2.4).
        central.connect(target, options: nil)
    }

    private func connectToPersistedPeripheral() {
        guard let stored = UserDefaults.standard.string(forKey: Self.identifierDefaultsKey),
              let identifier = UUID(uuidString: stored)
        else {
            // Enabled but never paired — nothing to resume; pairing is the
            // foreground action that fixes this.
            state = .repairNeeded
            return
        }
        guard let found = central.retrievePeripherals(withIdentifiers: [identifier]).first else {
            // The system no longer knows the identifier: the sensor was
            // replaced (or the pairing record is gone). No background
            // rediscovery — surface the re-pair state; the cloud path is
            // unaffected meanwhile (Req 2.4a, Decision 8).
            state = .repairNeeded
            return
        }
        if found.state == .connected {
            // Restoration handed back a live link — re-arm the notify
            // subscription; didConnect will not fire again (Req 2.7).
            peripheral = found
            found.delegate = self
            state = .connected
            found.discoverServices(nil)
        } else {
            connect(found)
        }
    }

    // Both connect and restore end in notify arming: without the subscription
    // there is no per-minute beat, because on a shared persistent link
    // didConnect fires once (design "Notify arming").
    private func armNotify(on peripheral: CBPeripheral) {
        peripheral.discoverServices(nil)
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            // Recover from the unavailable display state; a pending intent
            // below re-establishes the real one (didConnect → .connected).
            if case .unavailable = state { state = .idle }
            if wantsPairing {
                state = .pairing(sensorName: pairingCandidate?.name)
                central.scanForPeripherals(withServices: nil)
            } else if wantsConnection {
                connectToPersistedPeripheral()
            }
        case .poweredOff:
            state = .unavailable("Bluetooth is off — turn it on in Control Centre or Settings")
        case .unauthorized:
            state = .unavailable("Allow Bluetooth access in Settings")
        case .unsupported:
            state = .unavailable("Bluetooth is not available on this device")
        case .resetting:
            state = .unavailable("Bluetooth is restarting")
        case .unknown:
            break
        @unknown default:
            break
        }
    }

    // Apple delivers this as the FIRST delegate call on a background
    // restoration relaunch. The trigger closure is already attached (it came
    // with init), so recovering the peripheral and re-arming the notify
    // subscription is all that is left (Req 2.7).
    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        wantsConnection = true
        guard let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let first = restored.first
        else { return }
        peripheral = first
        first.delegate = self
        if first.state == .connected {
            state = .connected
            armNotify(on: first)
        }
        // A restored pending connect completes on its own; if the link was
        // lost, the poweredOn branch re-issues the connect.
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // First ABBOTT* peripheral is surfaced for one-tap confirmation
        // (Req 2.1); the scan stops so the candidate cannot be displaced
        // while the user reads its name.
        guard pairingCandidate == nil,
              Libre3Heartbeat.matchesSensor(
                  advertisedName: peripheral.name,
                  prefix: Libre3Heartbeat.Constants.namePrefix)
        else { return }
        pairingCandidate = peripheral
        state = .pairing(sensorName: peripheral.name)
        central.stopScan()
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        state = .connected
        beat()
        armNotify(on: peripheral)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        reconnectAfterDrop(peripheral)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        reconnectAfterDrop(peripheral)
    }

    // Transient drop (out of range, Abbott's app momentarily holding the
    // link): re-issue the connect — the OS holds it pending and completes it
    // on reconnection, including from the background. No state change here:
    // `stale` is derived at display time from the lapse of `lastBeatAt`
    // (Req 2.4, 5.2), and a sensor swap surfaces as `repairNeeded` only when
    // the identifier itself is gone (Req 2.4a) — BLE cannot tell "out of
    // range for a while" from "replaced", so the stale row carries the
    // re-pair action instead.
    private func reconnectAfterDrop(_ dropped: CBPeripheral) {
        guard wantsConnection || peripheral === dropped else { return }
        central.connect(dropped, options: nil)
    }

    // MARK: - CBPeripheralDelegate (notify arming)

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        let notifyUUID = CBUUID(string: Libre3Heartbeat.Constants.notifyCharacteristicUUID)
        for characteristic in service.characteristics ?? [] where characteristic.uuid == notifyUUID {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        // The one-minute reading characteristic ticked — the payload stays
        // encrypted and untouched; the event IS the signal (Req 1.1).
        beat()
    }
}
#endif

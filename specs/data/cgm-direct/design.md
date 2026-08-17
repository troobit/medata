# Design: CGM Direct

## Overview

Phase A adds a second BLE central that connects to the worn Libre 3/3+ sensor alongside Abbott's app
and, on each ~1-minute connection/notify event, triggers the existing `LibreLinkUpGlucoseSource`
cloud fetch. It carries no glucose value; it is a background **wake** that replaces an unbounded OS
wake deferral (the 2026-08-05 event, `cgm-connect` Decision 12) with a bounded worst-case staleness
of roughly one gate interval plus one beat (~6 minutes). Phase B (on-device decrypt) stays
research-only — this design implements Phase A and records Phase B's gates so Phase A forecloses
nothing.

## Architecture

### Placement and firewall

The wake-source protocol and pure decision logic live in the `GlucoseIngestion` module (Req 1.4,
9.1); the CoreBluetooth central and its app wiring are `#if os(iOS)` (CoreBluetooth `canImport`s on
macOS, so `canImport` guards exclude nothing). No new SwiftPM target, no new package-graph edge, so
`EstimationFirewallTests` keeps passing unchanged. The firewall test guards module *placement* (it
walks SwiftPM edges, not framework imports); keeping BLE code out of estimation targets remains a
placement discipline, which the module split enforces.

### Sensor lifecycle: confirm once, retrieve thereafter

Background wildcard scanning does not exist on iOS — `scanForPeripherals(withServices: nil)` is
foreground-only, and a nil-service scan cannot be state-restored. The design therefore never relies
on scanning in the background (Req 2.1, 2.4a, Decision 8):

1. **Pair (foreground, once per sensor):** enable → wildcard scan → first peripheral whose name
   matches `ABBOTT*` is shown for one-tap confirmation → its `identifier` (and name) persisted.
2. **Every subsequent connect:** `retrievePeripherals(withIdentifiers:)` → `connect(_:)`. A pending
   connect to a known peripheral survives suspension and relaunch, and completes from the background
   when the sensor comes into range — this is the wake mechanism.
3. **Transient drop** (`didDisconnectPeripheral`, `didFailToConnect`): re-issue `connect` to the same
   peripheral; state goes stale after 70 s (Req 2.4).
4. **Sensor swap:** the persisted peripheral never reconnects; the row shows a re-pair state and
   re-pairing repeats step 1 in the foreground. One app-open per fortnightly swap is the accepted
   contract; cloud polling is unaffected meanwhile (Req 2.4a).

### The two wake paths share one precondition — and one budget

| Wake path | Trigger | Guard before fetch | Fetch call |
|---|---|---|---|
| BGAppRefreshTask (existing) | iOS scheduler, best-effort ≥15 min | `await startTask?.value`; connected-check; rate gate | `performBackgroundFetch()` |
| BLE heartbeat (new) | Sensor connect/notify, ~1 min | gate peek; background assertion; `await startTask?.value`; connected-check; ~1 s delay | `catchUp()` |

Req 3.4 (the heartbeat as the adaptive-urgency trigger) reduces to Req 3.1 while the uniform
5-minute baseline (`cgm-connect` Decision 13) keeps that machinery dormant — no code addresses it
separately.

`catchUp()` and `performBackgroundFetch()` have **identical side effects on a closed gate** (both end
in `fetchAndIngest`, which checks the gate itself); they differ only in the returned `Bool`, whose
success-on-closed-gate contract exists for `setTaskCompleted(success:)` and is meaningless off
BGTaskScheduler. The heartbeat therefore calls `catchUp()` and discards nothing (Decision 5).

**Rate-gate double-spend is already impossible** (worth stating so nobody "fixes" it): there is no
suspension point between `LibreLinkUpRateGate.isOpen()` and `recordFetch()` inside the actor-isolated
`fetchAndIngest`, so a second beat entering during the first's network await finds the gate closed.

### Background execution contract (the ~10 s window)

A CoreBluetooth event wake grants roughly 10 seconds of runtime. The heartbeat closure is built to
fit or fail losslessly:

- **Gate peek first.** `LibreLinkUpRateGate.isOpen()` is one UserDefaults read; roughly four of five
  beats find the gate closed and return before taking an assertion, spawning work, or touching an
  actor. The beat still updates `lastBeatAt` — the heartbeat's meaning stays "a reading exists now".
- **Assertion around the work.** When the gate is open, the closure wraps the remainder in
  `UIApplication.beginBackgroundTask`, expiration handler cancelling the work Task (the existing
  `CancellableWorkBox` pattern from the BGTask handler). Cancellation surfaces through the URLSession
  await as a failed fetch; nothing is acked, the source's cursor holds.
- **Abandonment is lossless.** A fetch killed mid-flight is retried by the next open-gate beat; the
  graph endpoint returns history and keep-first dedup absorbs the overlap. On a cold relaunch the
  app's own init cost (GRDB, Core ML loads) may consume the window — accepted; the next beat retries.

### OS-driven launches do not spend the ungated fetch — Req 3.7, Decision 7

`LibreLinkUpGlucoseSource.connect()` runs one gate-ignoring immediate fetch, justified as "one
request on a user action". A state-restoration relaunch is not a user action, and its instant fetch
would race Abbott's ~1 s upload, ingest the *previous* reading, and close the gate against the
properly-delayed heartbeat fetch — defeating Req 3.3 on the marquee path and adding recurring
ungated requests (Req 3.2). Fix: `connect(sink:runValidationFetch:)` — the model passes `false`
when `UIApplication.shared.applicationState == .background` during `start()`; connect then attaches
the sink and starts polling, leaving the first fetch to the heartbeat path. Foreground launches and
credential entry keep today's behaviour.

### Parity audit — extending the "source in GlucoseConnectionsModel" pattern

| Existing per-source touch point (`GlucoseConnectionsModel`) | Heartbeat needs equivalent? | Note |
|---|---|---|
| `connectedSourceIDs` launch-reconnect flag | **Yes** | `glucose.source.libre3-heartbeat.enabled` — deliberately `.enabled`, not `.connected`: it is not a reading source and never enters `connectedSourceIDs` |
| `start()` reconnect on launch | **Yes** | but at `init` time, synchronously — see construction rule below |
| `disconnect(_:)` | **Partial** | disable = `cancelPeripheralConnection` + stop + clear flag; persisted identifier kept; no keychain/cursor (Req 5.3) |
| `busySourceIDs` intent guard | **No** | enable/disable is local BLE start/stop, no awaited network step |
| `catchUpConnectedSources()` on foreground | **No** | the heartbeat has no catch-up; the LLU fetch already catches up on foreground |
| BGTask registration | **No** | CoreBluetooth state restoration is the relaunch mechanism, not BGTaskScheduler |
| coordinator state stream / discrepancy tally | **No** | never ingests; does not register with the coordinator (Req 1.2) |
| Settings row + state display | **Yes** | new section in `GlucoseConnectionsView` (Req 5.1, 5.2, 5.6, 5.7) |

## Components and Interfaces

### `HeartbeatWakeSource` (protocol, new) — Req 1.1, 1.2

```swift
@MainActor
public protocol HeartbeatWakeSource: AnyObject {
    var id: String { get }                      // "libre3-heartbeat"
    var state: HeartbeatConnectionState { get } // observable (the conformer is @Observable)
    var lastBeatAt: Date? { get }
    func startPairing()                         // foreground wildcard scan → pendingSensorName
    func confirmPairing()                       // persist identifier, connect (Req 2.1)
    func resume()                               // reconnect to the persisted sensor (launch path)
    func stop()                                 // cancel connection + scanning, detach nothing else
}

public enum HeartbeatConnectionState: Sendable, Equatable {
    case idle                        // constructed, not started
    case unavailable(String)         // Bluetooth off / permission denied (Req 5.6)
    case pairing(sensorName: String?) // scanning; non-nil when a candidate awaits confirmation
    case connected
    case stale                       // > staleWindow since last beat (Req 5.2)
    case repairNeeded                // persisted sensor gone; foreground re-pair (Req 2.4a)
}
```

Deliberately **not** `GlucoseSource` (Decision 1): no samples, no sink, its own state enum — a
value-less signal cannot masquerade as a reading in the type system. `@MainActor` protocol, not
`Sendable`+async: the conformer is a main-actor class (Decision 10) and its consumer is the
already-`@MainActor` model.

### `Libre3HeartbeatSource` (class, new) — Decision 10

```swift
@Observable @MainActor
final class Libre3HeartbeatSource: NSObject, HeartbeatWakeSource,
                                   CBCentralManagerDelegate, CBPeripheralDelegate {
    init(onHeartbeat: @escaping @MainActor () -> Void)  // closure attached AT CONSTRUCTION
}
```

- **Isolation:** `@MainActor final class NSObject` with `CBCentralManager(delegate: self, queue: nil,
  options: [CBCentralManagerOptionRestoreIdentifierKey: Constants.restoreIdentifier])`. `queue: nil`
  delivers delegate callbacks on the main queue, matching the isolation; an actor cannot conform to
  the `@objc` delegate protocol, and actor Task enqueueing is not FIFO, which would break the
  debounce's read-modify-write of `lastBeatAt`. Event rate is 1/min — main-thread cost is nil.
- **Construction rule (Req 2.7 vs 6.1):** the model constructs this source in its `init` (called
  from `MedataApp.init`, synchronously, before launch completes) **iff** the enabled flag is set — a
  plain UserDefaults read. Restoration (`willRestoreState`) therefore always finds a central whose
  trigger closure is already attached; a disabled heartbeat constructs no central, triggers no
  Bluetooth permission prompt, and gives iOS nothing to relaunch (Req 6.1). The closure is a
  constructor argument precisely so there is no attach-later window.
- **Notify arming (the beat's plumbing):** on `didConnect` → `peripheral.discoverServices(nil)` →
  `discoverCharacteristics` → `setNotifyValue(true)` on the characteristic matching
  `Constants.notifyCharacteristicUUID` (`CBPeripheralDelegate` flow). Every connect and restore ends
  by re-running this arming; without the subscription there is no per-minute beat, because on a
  shared persistent link `didConnect` fires once.
- **Power-state ordering:** `retrievePeripherals`/`connect` are legal only at `.poweredOn`, so
  `resume()` records intent and the actual retrieve+connect is issued from
  `centralManagerDidUpdateState` when it reports `.poweredOn` — the standard CoreBluetooth launch
  sequence; `runStart()`'s timing relative to power-up therefore does not matter.
- **Trigger (Req 2.5):** on `didConnect` **and** `didUpdateValueFor`: if
  `Self.shouldFire(now:lastBeatAt:minInterval:)` (≥30 s debounce), record + persist `lastBeatAt`
  (Req 5.7) and invoke `onHeartbeat` with `[weak self]`-safe wiring (the model holds the source
  strongly; the closure must not hold the model strongly back).
- **Coexistence (Req 2.2):** iOS reference-counts one physical link per peripheral — Abbott's app
  holds the authenticated session; this central rides the same link and adds no radio traffic. The
  notify subscription is load-bearing: with a persistent shared link, `didConnect` fires once, so
  the per-minute beat comes from `didUpdateValueFor`.
- **Restore:** `centralManager(_:willRestoreState:)` recovers the peripheral from
  `CBCentralManagerRestoredStatePeripheralsKey` and re-arms the notify subscription; a pending
  connect needs no scan to restore.
- **Unavailability:** `centralManagerDidUpdateState` ≠ `.poweredOn` → `.unavailable` with functional
  copy ("Bluetooth is off" / "Allow Bluetooth access in Settings"), distinct from disabled (Req 5.6).

Pure, testable statics (no CoreBluetooth types in signatures; compiled on the macOS test host):

```swift
static func shouldFire(now: Date, lastBeatAt: Date?, minInterval: TimeInterval) -> Bool
static func matchesSensor(advertisedName: String?, prefix: String) -> Bool
static func isStale(now: Date, lastBeatAt: Date?, staleWindow: TimeInterval) -> Bool
enum Constants {
    static let namePrefix = "ABBOTT"
    static let notifyCharacteristicUUID = "0898177A-EF89-11E9-81B4-2A2AE2DBCCE4"  // String; CBUUID made at use site
    static let restoreIdentifier = "com.medata.libre3.heartbeat"
    static let minInterval: TimeInterval = 30      // Req 2.5
    static let staleWindow: TimeInterval = 70      // Req 5.2
    static let preFetchDelay: TimeInterval = 1     // Req 3.3
}
```

**State ownership:** `idle`, `unavailable`, `pairing`, `connected`, and `repairNeeded` are
event-driven and set by the source from delegate callbacks. `stale` alone is defined by the
*absence* of an event, so it is derived at display time: the Settings row renders inside
`TimelineView(.periodic(every: 10))`, showing Stale when `isStale(now:…)` says the observable
`lastBeatAt` has lapsed — no timer in the source, and the state is truthful whenever it is on
screen (the only place it is read). `lastBeatAt` persists to app-private UserDefaults
(`glucose.source.libre3-heartbeat.lastBeatAt`) so a relaunch shows the real last beat (Req 5.7).

**Swap detection is manual, by design:** BLE cannot distinguish "sensor out of range for a while"
from "sensor replaced" — both look like a pending connect that has not completed. `repairNeeded` is
set automatically only when `retrievePeripherals(withIdentifiers:)` comes back empty (identifier no
longer known to the system). Otherwise the stale row always carries the "Re-pair sensor" action
(the user knows they swapped; the affordance is the surface Req 2.4a requires), which re-runs the
`startPairing()` confirm flow.

### `GlucoseConnectionsModel` additions (wiring) — Req 3.6, 3.7, Decision 5

```swift
// init, synchronously (construction rule above):
if Self.heartbeatEnabledFlag() {
    heartbeat = Libre3HeartbeatSource(onHeartbeat: { [weak self] in self?.heartbeatFired() })
}

func enableHeartbeat()    // construct if needed, set flag, startPairing()
func confirmHeartbeatPairing()
func disableHeartbeat()   // heartbeat?.stop() (cancels connection), clear flag; identifier kept

private func heartbeatFired() {
    guard LibreLinkUpRateGate.isOpen() else { return }        // budget peek: most beats end here
    let assertion = UIApplication.shared.beginBackgroundTask(…) // + CancellableWorkBox expiration
    Task {
        defer { /* end assertion */ }
        await startTask?.value                                 // Req 3.6: lose the cold-launch race
        guard connectedSourceIDs.contains(libreLinkUpID) else { return }
        try? await Task.sleep(for: .seconds(Libre3HeartbeatSource.Constants.preFetchDelay))
        await libreLinkUp.catchUp()                            // re-checks gate inside (Req 3.1, 3.2)
    }
}
```

`runStart()` additionally calls `heartbeat?.resume()` when the flag is set, and passes
`runValidationFetch: false` to `libreLinkUp.connect` when the process launched into the background
(Req 3.7). The `resume()` on a restoration launch is a no-op for the connection itself (the OS
restored it) but re-asserts the notify subscription.

### Capability declarations — Req 6.3

`MeData/Info.plist`: add `bluetooth-central` to the existing `UIBackgroundModes` array (currently
`["fetch"]`) and an `NSBluetoothAlwaysUsageDescription` string (functional copy). No entitlement
change (Req 2.3, Decision 4).

### Settings UI — Req 5.1, 5.2, 5.4, 5.6

One new section in `GlucoseConnectionsView`'s `Form`, matching the existing LibreLinkUp section's
patterns (`LabeledContent` state rows, `en_IE` `timeString`, accessibility identifiers
`glucose.heartbeat.*`): state row (Pairing / Connected / Stale / Re-pair sensor / Bluetooth off),
"Last heartbeat" row, Enable/Confirm/Disable buttons. Functional copy only. The whole section sits
behind the developer-phase switch (Req 6.1), disabled by default.

### Widget interaction — ship and measure (Decision 9)

Phase A makes the app ingest in the background at gate cadence; each strictly-newer snapshot
requests a widget timeline reload against WidgetKit's ~40–70/day budget (up to ~288 requests/day
worst case). Accepted for now and **measured** in the on-device verification task rather than
throttled — `GlucoseWidgetPublisher` stays untouched in this spec. If budget exhaustion is observed,
throttling becomes a follow-up against `specs/ui/glucose-lock-widget`. Side effect worth recording
there later: a background-ingesting app largely supersedes the widget's self-fetch rationale
(glucose-lock-widget Decision 16).

## Operational prerequisite — a user-controlled uploader (Req 10)

Phase A observes an already-active session; it does not own the sensor. So it needs *some* uploader
running against the sensor, but which uploader is the **user's** choice, and a regional App Store
restriction on Abbott's LibreLink is routed around, never accepted as a block (Req 10). The table
maps each missing link to the truthful state it produces — the recoverable gap the user then closes
by taking a route below:

| Chain link | Provided by the chosen uploader | If absent | Visible as |
|---|---|---|---|
| Sensor activation | LibreLink (region-matched) or Juggluco | sensor emits nothing | no `ABBOTT*` peripheral at pairing |
| Authenticated session | the uploader's live connection | notify stream absent → no beats | heartbeat `stale` |
| LibreView upload | the uploader | cloud has no fresh values | LLU fetch stale/empty per cgm-connect Req 3.4 |

No code handles these specially — each lands in an existing truthful state (Req 10.3). Routes to
obtain an uploader, in preference order (`docs/libre-app-region-setup.md`): **(a) region-switch** —
install the LibreLink matching the sensor's country of purchase by changing the iPhone App Store
region (the sensor is country-locked; the app is free, so Payment Method: None); **(b) Juggluco
bridge** — an Android device activates + uploads to LibreView with no Abbott iOS app on the iPhone
(heartbeat coexistence against an Android-held session is unverified — stream-2 research, Req 10.4);
**(c) Phase B** — MeData activates and decrypts on-device, the only route with no external uploader
at all, gated per Req 7. The Ypsomed cloud stays a Non-Goal.

## Error Handling

| Condition | Behaviour | Requirement |
|---|---|---|
| Transient drop / `didFailToConnect` | re-issue `connect` to persisted peripheral; `stale` after 70 s; no reading touched | 2.4, 5.2 |
| Sensor swapped | pending connect never completes → `repairNeeded`; foreground re-pair; cloud path unaffected | 2.4a, 5.6 |
| Heartbeat while gate closed | closure returns at the gate peek; beat still recorded; not a failure | 3.1, 3.2 |
| Cold-launch race | `await startTask?.value`, connected-check; no-op if LLU not connected | 3.6 |
| Background window expires mid-fetch | assertion expiration cancels work; nothing acked; next open-gate beat retries; dedup absorbs overlap | 3.1, 4.2 |
| Bluetooth off / permission denied | `.unavailable(reason)` with next-step copy; enabling later re-runs | 5.6 |
| Heartbeat enabled, LibreLinkUp not connected | beats recorded and shown, fetch no-ops | 3.6 |

No new failure modes reach the estimation path — offline, the wake finds the vendor unreachable per
`cgm-connect` behaviour (Req 9.3).

## Testing Strategy

App/UI gate is the project rule: build + look right on device. The CoreBluetooth delegate,
background modes, restoration, and assertion discipline are **device-verified only** (like
`HealthKitGlucoseSource`'s observer path) — a mocked central would test the mock's scripted
ordering, not iOS's (Decision 6). Unit-tested (MedataCore, macOS host, example tables):

- `shouldFire` — <30 s suppressed, ≥30 s fires, first beat (`nil`) fires.
- `isStale` — boundary at exactly `staleWindow`; `lastBeatAt == nil`.
- `matchesSensor` — `ABBOTT*` matches; other prefixes and `nil` do not.
- `EstimationFirewallTests` asserted still green after the change lands.

Device verification includes a **measured close-out** (verify task): ≥24 h with the app never
foregrounded, heartbeat on, comparing `bsl` row count and max inter-reading gap against a
heartbeat-off baseline day, plus battery delta and widget-refresh behaviour — "looks right on
device" cannot see a wake that didn't happen.

No property-based testing: the pure logic is boundary checks, not invariants/round-trips. Phase B's
decrypt (AES-128-CCM round-trip against vectors) would be the PBT candidate when it is built.

## Phase B — research continuity (gates, not build)

- `docs/agent-notes/libre3-direct-ble.md` remains the normative, date-stamped gate of record
  (Req 8), now carrying a dated re-check log (first entry 2026-08-17: verdict unchanged; frontier
  moved — Juggluco confirmed as the Android reference after the maheini repo archived "decryption
  successfully cracked", and a 39C3/CCC 2025 project is attempting the iOS port).
- Phase A attributes readings to `librelinkup` (value provenance is the cloud); the distinct
  `libre3-ble` identifier (Req 4.3) stays reserved for Phase B.
- The task list carries a standing re-verification work stream (DiaBLE #22, LibreCRKit, 39C3
  project, Libre 3+ coexistence on-device, Ypsomed follower API), run on a cadence and logged
  whether or not the verdict moves (Req 8.2), concurrent with the Phase A build stream.

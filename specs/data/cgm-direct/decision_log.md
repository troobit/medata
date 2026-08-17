# Decision Log: CGM Direct

## Decision 1: The heartbeat is a wake source, not a reading GlucoseSource

**Date**: 2026-08-17
**Status**: accepted

### Context

Phase A connects a second BLE central to the sensor. In Phase A the BLE payload is **not**
decrypted — the connection/notify event carries no usable glucose value; the value is still fetched
from the LibreLinkUp cloud. The existing `GlucoseSource` protocol
(`MedataCore/Sources/GlucoseIngestion/GlucoseSource.swift`) is defined around producing
`GlucoseSample` batches and delivering them to the sink.

### Decision

Model the heartbeat as a distinct wake-source type that emits a value-less heartbeat signal and
triggers the existing `LibreLinkUpGlucoseSource` fetch entry point. It does not conform to
`GlucoseSource` and never writes to the event log itself.

### Rationale

A `GlucoseSource` that returned no samples, or synthesised a value it did not measure, would be a
lie in the type system and would risk writing an unattributable reading. Separating "a reading
exists now" (the heartbeat) from "here is the reading" (the cloud fetch) keeps provenance truthful:
the stored row stays attributed to `librelinkup` because the cloud is still where the value came
from (Req 4.1).

### Alternatives Considered

- **Make the heartbeat a GlucoseSource that fetches internally**: Fold the cloud fetch into a new
  source - Rejected: duplicates `LibreLinkUpGlucoseSource`'s fetch/dedup/rate-gate logic and would
  double-count against the shared vendor budget.
- **Synthesise a sample from the notify payload**: Emit a placeholder reading on heartbeat -
  Rejected: the payload is encrypted in Phase A; any value would be fabricated.

### Consequences

**Positive:**
- Truthful provenance; no new stored source id in Phase A; the shared budget stays one budget.
- The wake mechanism is reusable for another vendor's transmitter later.

**Negative:**
- A second abstraction beside `GlucoseSource` to hold; the wiring between wake and reading source
  must be explicit.

---

## Decision 2: Phase A respects the vendor rate budget — no per-minute cloud freshness claim

**Date**: 2026-08-17
**Status**: accepted

### Context

The heartbeat fires ~every minute. The naive read is "fetch the cloud every minute → 1-minute
freshness". But the LibreLinkUp cloud carries a shared ~5-minute rate budget (`cgm-connect`
Decision 13); ~3-minute-and-faster polling is the rate with known account-ban evidence. An early
framing of this feature claimed "~1-minute freshness", which is not safely achievable from the
cloud.

### Decision

Phase A's heartbeat-triggered fetch remains subject to the existing shared `LibreLinkUpRateGate`.
The honest Phase A value is (a) a reliable background wake that does not depend on iOS running a
deferred `BGAppRefreshTask`, and (b) a reading-aligned, budget-bounded fetch. No code, copy, or log
may claim per-minute cloud freshness. True per-minute network-free freshness is a Phase B property
only, because on-device decrypt has no cloud and no ban budget.

### Rationale

The 2026-08-05 field failure (`cgm-connect` Decision 12) was fundamentally a *missed wake*: the
reading existed in the cloud but iOS had deferred the refresh task, running it only when the phone
was unlocked. A BLE connection event is a reliable background wake and fixes that root cause without
increasing request rate. Increasing request rate to chase 1-minute cloud values would trade a
staleness problem for a ban problem — strictly worse, since a banned account loses all readings.

### Alternatives Considered

- **Bypass the rate gate on heartbeat for 1-minute polling**: Highest freshness - Rejected: this is
  the banned rate; a ban ends all ingestion, the opposite of the goal.
- **Raise the shared budget**: Poll faster but sub-1-minute - Rejected: still moves toward the ban
  rate for a gain Phase B delivers for free once unblocked.

### Consequences

**Positive:**
- No new ban exposure; the biggest real win (reliable background wake) is preserved.
- Sets an honest expectation that the network-free freshness goal is Phase B.

**Negative:**
- Phase A does not, by itself, guarantee sub-5-minute freshness; the urgent-fetch benefit depends on
  the adaptive-urgency machinery (`cgm-connect` Decision 12) being re-armed.

---

## Decision 3: MeData-can-activate for Phase B, gated behind a test sensor and Phase A default

**Date**: 2026-08-17
**Status**: accepted

### Context

Phase B (on-device decrypt) needs the sensor's blePIN. On Android (Juggluco) the blePIN is obtained
by the app **activating the sensor itself** as owner (feasibility note "Why Android can and iOS
can't"). Doing that displaces the official Abbott app's ownership of that sensor, and with it
Abbott's realtime hypo alarms.

### Decision

Phase B may NFC-activate the sensor as owner to obtain the blePIN, accepting loss of Abbott's alarms
on that sensor. This is gated: it is a deliberate, user-confirmed act (Req 7.4); it SHALL NOT run on
the user's live sensor until the full decrypt path is proven end-to-end on a separate test sensor;
and Phase A (coexisting heartbeat + cloud value, Abbott app and alarms intact) remains the everyday
path until then.

### Rationale

Activation-as-owner is the only known route past Blocker 1 (blePIN) on iOS, so foreclosing it would
foreclose Phase B. But displacing Abbott's alarms is a genuine safety cost, so it is bounded by a
test-sensor-first gate and kept off the everyday path. This gives the research route a door without
putting the user's live hypo alarms at risk before the path actually works.

### Alternatives Considered

- **Must-coexist only (never activate)**: Keep Abbott's alarms always - Rejected: it leaves
  Phase B permanently blocked on the blePIN.
- **Activate the live sensor now**: Fastest path to attempt decrypt - Rejected: sacrifices working
  alarms for an iOS path that is not yet proven (feasibility note Blocker 3).

### Consequences

**Positive:**
- Phase B has a viable route; the safety cost is bounded and reversible (use a test sensor).

**Negative:**
- When Phase B is eventually exercised on the live sensor, Abbott's official alarms are lost on it;
  the user accepts this tradeoff knowingly.

---

## Decision 4: Standard `bluetooth-central` background mode; restricted BLE entitlements not needed

**Date**: 2026-08-17
**Status**: accepted

### Context

Req 2.3 needs the BLE central to keep waking the app while suspended. `docs/agent-notes/glucose-ingestion.md`
recorded that "Bluetooth background entitlements (`com.apple.developer.bluetooth-central-background`
and the screen-off scanning pair) … Not self-service; special approval" — read literally, that would
make Phase A blocked on an Apple entitlement grant. That conflates two different iOS mechanisms.

### Decision

Phase A uses only the self-service `bluetooth-central` value in `UIBackgroundModes` plus an
`NSBluetoothAlwaysUsageDescription` string (Req 6.3). It does NOT request any restricted Bluetooth
entitlement.

### Rationale

The `bluetooth-central` background mode is a plain Info.plist declaration, no signed entitlement, and
per Apple's CoreBluetooth background-execution documentation it is exactly what wakes an app on
`CBCentralManagerDelegate`/`CBPeripheralDelegate` events (connection established or torn down,
characteristic value updates) and enables state restoration — the entire Phase A wake mechanism.
The restricted entitlements are different things: `com.apple.developer.bluetooth-central-background`
is the **watchOS** gate for background BLE on a watch extension, and screen-off scanning has its own
separate restricted entitlement. Neither applies to connection-event wakes on an iPhone.
xdripswift's shipping Libre 3 heartbeat runs on the standard mode; this design matches it. One
platform limit does bind, and is handled by Decision 8: background *scanning* requires explicit
service UUIDs — a wildcard scan is foreground-only.

Standing assumption: should a restricted entitlement ever become necessary, it will be applied
for — cert/profile changes for developer-mode builds, App Store permission requests as required —
and approval is assumed granted. Restricted entitlements are paperwork steps in this spec, never
blockers; this decision picks the standard mode because Phase A does not need more, not because
more is unreachable.

### Alternatives Considered

- **Request `com.apple.developer.bluetooth-central-background`**: Belt-and-braces - Rejected: it is
  the watchOS gate, for a scanning pattern this feature does not use; requesting an unused
  restricted capability adds an application step for zero function.
- **No background mode (foreground-only heartbeat)**: Simplest - Rejected: it defeats the whole point.
  The wake's value is precisely that it fires while the app is suspended (the 2026-08-05 deferred-BGTask
  root cause).

### Consequences

**Positive:**
- Phase A ships with a plist edit and no entitlement dependency; `docs/agent-notes/glucose-ingestion.md`
  is corrected so the false blocker is not re-raised.

**Negative:**
- If a future need for screen-off *scanning* appears (e.g. Phase B rediscovery of an unpaired
  sensor), the separate restricted entitlement must be applied for first — assumed granted per the
  standing assumption above, so a lead-time step, not a blocker.

---

## Decision 5: The heartbeat triggers `catchUp()`, owned by `GlucoseConnectionsModel`, sharing the BGTask guard

**Date**: 2026-08-17
**Status**: accepted

### Context

A heartbeat must cause a LibreLinkUp fetch. Two fetch entry points exist: `catchUp()` (plain,
rate-gated) and `performBackgroundFetch()` (rate-gated but reports a closed gate as success, for
BGTaskScheduler's benefit). The fetch must also wait ~1 s for Abbott's upload (Req 3.3) and must not
run before the app's source-reconnect (`startTask`) has attached the sink — the same cold-launch race
the existing BGTask handler already guards.

### Decision

`GlucoseConnectionsModel` owns the `Libre3HeartbeatSource` and supplies its `onHeartbeat` closure. The
closure: `await startTask?.value` → guard LibreLinkUp connected → sleep ~1 s → `libreLinkUp.catchUp()`.
The ~1 s delay and the connected/reconnect guard live in the model's closure, not inside the BLE
source, so the source stays a pure value-less wake.

### Rationale

`catchUp()` and `performBackgroundFetch()` have **identical side effects on a closed gate** — both
end in `fetchAndIngest`, which checks the gate itself; they differ only in the returned `Bool`.
`performBackgroundFetch()`'s success-on-closed-gate return contract exists solely for
`setTaskCompleted(success:)` (so iOS keeps scheduling BGTasks) and is meaningless off
BGTaskScheduler, so `catchUp()` is the honest verb — there is no behavioural difference to choose
by, only a contract that does not apply. Most beats spending nothing against the ~5-minute budget
is the intended design, not a failure. Reusing
`startTask` and the connected-guard means the two wake paths (BGTask, heartbeat) share one
precondition (Req 3.6) rather than drifting apart. Placing the wiring in the model keeps the BLE
source free of any `GlucoseSource`/LibreLinkUp coupling.

### Alternatives Considered

- **Heartbeat calls `performBackgroundFetch()`**: Symmetry with BGTask - Rejected: its closed-gate =
  success contract is meaningless off BGTaskScheduler and would obscure that most beats are intended
  no-ops.
- **Put the 1 s delay + fetch inside `Libre3HeartbeatSource`**: Fewer moving parts - Rejected: it would
  couple the BLE source to `LibreLinkUpGlucoseSource` and the App Group rate gate, breaking the
  "wake source knows nothing about readings" separation (Decision 1).

### Consequences

**Positive:**
- One shared wake precondition; the BLE source is reusable for another vendor's transmitter with no
  LibreLinkUp knowledge.

**Negative:**
- The heartbeat's real effect is spread across two files (source fires; model decides) — intentional,
  but the wiring must be read as a pair.

---

## Decision 6: BLE delegate is device-verified only; debounce/stale/match logic is pure and unit-tested

**Date**: 2026-08-17
**Status**: accepted

### Context

The `GlucoseIngestion` module compiles and unit-tests on the macOS `make test` host, which has no BLE
hardware and does not run the app-target UI. CoreBluetooth exists on macOS but exercising a real
central needs a sensor. The project test gate is "build + look right on device" for app/UI work, with
MedataCore math kept green.

### Decision

Split the source like `HealthKitGlucoseSource`: the `CBCentralManager` delegate, background mode, and
state restoration are `#if os(iOS)` (note: `canImport(CoreBluetooth)` excludes nothing — CoreBluetooth
exists on macOS) and verified only by the on-device build. The debounce (`shouldFire`), stale-window (`isStale`), and name-match (`matchesSensor`)
decisions are pure `static` functions with no CoreBluetooth types in their signatures, unit-tested by
example tables — mirroring `LibreLinkUpGlucoseSource.nextPollInterval`.

### Rationale

The bug-prone parts are the timing thresholds (30 s debounce via `shouldFire`, 70 s stale via `isStale`)
and the name match (`matchesSensor`), and those are pure and testable without hardware. The CoreBluetooth glue is thin and only meaningfully verified
against a real sensor anyway, so a mock central would test the mock, not the behaviour. This keeps the
firewall test (`EstimationFirewallTests`) passing unchanged — the CoreBluetooth import adds no new
package-graph edge into any estimation target.

### Alternatives Considered

- **Protocol-abstract the central and inject a fake**: Full unit coverage - Rejected: it tests the
  fake's scripted callbacks, not iOS's real connect/notify/restore ordering, at the cost of an
  abstraction layer; the device build is the real check (project test gate).
- **Add a new XCTest target that scans real BLE in CI**: Highest fidelity - Rejected: no BLE on the
  test host; against the "less is more" test-gate rule.

### Consequences

**Positive:**
- Timing logic is regression-guarded; no hardware in `make test`; firewall stays green.

**Negative:**
- The delegate/restoration path has no automated test — it rides the device-build gate, like HealthKit.

---

## Decision 7: OS-driven background launches do not run the gate-ignoring validation fetch

**Date**: 2026-08-17
**Status**: accepted

### Context

`LibreLinkUpGlucoseSource.connect()` runs one immediate fetch with `ignoringRateGate: true`,
justified in cgm-connect as "one request on a user action, not a rate". Phase A's design review
traced the restoration cold-launch sequence and found that this fetch fires instantly on every
OS-driven relaunch: it races Abbott's ~1 s cloud upload (ingesting the previous reading), calls
`recordFetch()` (closing the shared gate), and thereby turns the properly-delayed heartbeat fetch
into a no-op — on exactly the terminated-app-near-a-hypo path the feature exists to fix. It also
converts cold launches, which iOS may now trigger about once a minute via BLE, into recurring
ungated vendor requests: new ban exposure against Req 3.2's "no new ban exposure".

### Decision

`connect(sink:)` gains a `runValidationFetch` parameter (Req 3.7). `GlucoseConnectionsModel` passes
`false` when the process was launched into the background (`applicationState == .background` during
`start()`); connect then attaches the sink and starts polling, and the first fetch comes from the
rate-gated, ~1 s-delayed heartbeat path. User-initiated paths (credential entry, foreground opens)
keep today's immediate ungated fetch.

### Rationale

The ungated fetch's own justification ("a user action") does not hold for an OS-driven relaunch, and
keeping it would breach two acceptance criteria at once (Req 3.2, 3.3) on the feature's marquee path.
The change is confined to launch wiring — the fetch cycle, rate gate, and cgm-connect's user-facing
credential-validation behaviour are untouched, keeping the Non-Goals promise that Phase A does not
modify the cloud fetch itself.

### Alternatives Considered

- **Keep today's behaviour**: No cgm-connect signature change - Rejected: recurring
  ungated requests on OS events plus a guaranteed-stale first reading on restoration wakes.
- **Apply the 1 s delay to the launch fetch but keep it ungated**: Fixes staleness only - Rejected:
  the ban-exposure half remains; two fetches per wake where one suffices.

### Consequences

**Positive:**
- Req 3.2 and 3.3 hold on the restoration path; one budget-spend per wake, correctly delayed.

**Negative:**
- A background relaunch surfaces no immediate connection state; the state appears after the first
  gated fetch — invisible in practice, since no UI is on screen during a background launch.

---

## Decision 8: Sensor swap is a foreground re-pair; no background scanning of any kind

**Date**: 2026-08-17
**Status**: accepted

### Context

iOS delivers wildcard scans (`serviceUUIDs: nil`) only in the foreground, and a wildcard scan cannot
be state-restored. After a sensor swap (~fortnightly), the persisted peripheral identifier is dead
and background rediscovery would require scanning a specific advertised service UUID. The Libre 3
data service is reported as `FDE3`, but that value is unverified on Libre 3 Plus hardware from this
project's own evidence (feasibility note re-check 2026-08-17).

### Decision

Discovery and re-pairing are foreground-only: enable → wildcard scan → user confirms the `ABBOTT*`
sensor → persist its identifier; all subsequent connects use `retrievePeripherals(withIdentifiers:)`
with no scan. After a swap the heartbeat shows a re-pair state until the user opens the app once
(Req 2.1, 2.4a). No `FDE3` background scan is attempted.

### Rationale

The retrieve-by-identifier path needs no scan at all, works from the background and across
relaunches, and is restorable — it covers every day except swap day. A background service scan would
buy self-healing on one day a fortnight at the cost of building on an unverified UUID; the cloud
path keeps readings flowing during the gap regardless, so the failure mode is a missing wake
optimisation, not missing data. One deliberate app-open per sensor swap is an honest, simple
contract for a single-user developer phase.

### Alternatives Considered

- **Background scan on `FDE3` as well**: Self-heals after swap - Rejected: UUID unverified on 3+;
  adds a scanning duty cycle; the gain is one saved app-open per fortnight.
- **Re-run wildcard scan opportunistically whenever foregrounded**: Automatic re-pair without a
  confirm step - Rejected: silently latching onto the first `ABBOTT*` peripheral drops Req 2.1's
  user confirmation and misbehaves around other Libre wearers.

### Consequences

**Positive:**
- No unverified constants on the wake path; deterministic pairing; Req 2.1's confirmation is real.

**Negative:**
- The heartbeat is down from swap until the next app-open; recorded as the accepted contract
  (Req 2.4a). If `FDE3` is later verified on 3+ hardware, a background scan can be added by a
  follow-up decision.

---

## Decision 9: Widget reload budget under Phase A — ship and measure, no publisher throttle yet

**Date**: 2026-08-17
**Status**: accepted

### Context

Phase A makes the app ingest in the background at gate cadence. `GlucoseWidgetPublisher` requests a
widget timeline reload on every strictly-newer snapshot; background reloads spend WidgetKit's
~40–70/day budget, and gate-cadence ingestion could request up to ~288/day. Exhausting the budget
early could leave the Lock Screen widget staler later in the day — inverting the feature's purpose.

### Decision

Ship Phase A without touching `GlucoseWidgetPublisher`; add widget-refresh observation to the
on-device verification task and throttle only if budget exhaustion is actually observed. User
approved 2026-08-17 ("Ship and measure").

### Rationale

The reload budget's real-world behaviour under this pattern is unknown, WidgetKit reloads are
requests rather than guarantees, and a throttle designed against an unmeasured budget would be
guesswork touching a shipped surface (`specs/ui/glucose-lock-widget`) outside this spec's scope.
Related observation for that spec, recorded here so it is not lost: a background-ingesting app
largely supersedes the widget's self-fetch rationale (glucose-lock-widget Decision 16); whether to
retire the self-fetch or keep it as redundancy is that spec's follow-up.

### Alternatives Considered

- **Throttle the publisher now**: Protects the budget preemptively - Rejected: unmeasured problem,
  cross-spec change, and a wrong threshold could suppress wanted refreshes.
- **Back off the heartbeat instead**: Fewer ingests, fewer reloads - Rejected: sacrifices the
  feature's core gain to protect a display optimisation.

### Consequences

**Positive:**
- No cross-spec churn; the verification task produces real budget data to decide with.

**Negative:**
- Until measured, days with volatile glucose could exhaust the widget budget early; the widget's
  staleness ladder still marks old data, so the failure is visible, not silent.

---

## Decision 10: Main-actor `NSObject` central, constructed at app init iff enabled, closure attached at construction

**Date**: 2026-08-17
**Status**: accepted

### Context

Three constraints collide. (1) `CBCentralManagerDelegate` is an `@objc` protocol refining
`NSObjectProtocol` — a Swift actor can neither subclass `NSObject` nor conform to it, so "actor or
NSObject" is not a choice. (2) Apple delivers `willRestoreState` as the **first** delegate call when
relaunching the app into the background, so the central must exist, with its trigger wired, during
app launch — an async `start(onHeartbeat:)` attach-later design leaves a window where a restored
event fires against a detached trigger (Req 2.7). (3) Constructing a `CBCentralManager` triggers the
Bluetooth permission prompt, and Req 6.1 requires the app to function fully with the heartbeat
disabled.

### Decision

`Libre3HeartbeatSource` is an `@Observable @MainActor final class` subclassing `NSObject`, its
`CBCentralManager` created with `queue: nil` (main-queue delegate delivery) and the restore
identifier. The `onHeartbeat` closure is a **constructor argument** — there is no attach step.
`GlucoseConnectionsModel.init` (which runs synchronously in `MedataApp.init`, before launch
completes) constructs the source iff the persisted enabled flag is set; disabled means no central,
no prompt, and nothing for iOS to relaunch.

### Rationale

Main-actor isolation with main-queue delegate delivery makes the ObjC→Swift hop safe by
construction, keeps delegate ordering FIFO (an actor's Task enqueueing is not FIFO, which would
break the debounce's read-modify-write), and allows the synchronous
`UIApplication.beginBackgroundTask` call inside the callback path. The event rate is one per minute
— main-thread cost is immaterial. Construct-iff-enabled is the single rule that satisfies Req 2.7
and Req 6.1 simultaneously and gives the disable path its teeth (Req 5.3): clearing the flag means
the next launch constructs nothing.

### Alternatives Considered

- **Actor with an NSObject delegate shim forwarding into it**: "Modern" isolation - Rejected:
  loses FIFO ordering across the hop, cannot take the main-actor background assertion synchronously,
  and adds a forwarding layer for zero contention (state is one `Date?`, one peripheral, one closure).
- **Construct the central lazily on first enable, attach the closure via `start()`**: Defers the
  permission prompt identically - Rejected: on a restoration relaunch the central would not exist at
  launch (restoration broken outright), and an attach-later API reintroduces the detached-trigger
  window Req 2.7 forbids.

### Consequences

**Positive:**
- Restoration always finds a wired central; no Bluetooth prompt until the user enables; delegate
  ordering and the debounce are trivially correct.

**Negative:**
- The heartbeat source is a main-actor class among actor sources — a deliberate asymmetry, documented
  in the type. The source itself stays in `GlucoseIngestion` (Req 1.4, 9.1); only the
  `UIApplication.beginBackgroundTask` assertion lives app-side, in the model's trigger closure,
  because UIKit is unavailable to the package target.

---

## Decision 11: A regional App Store restriction is routed around, not accepted — the uploader is user-controlled

**Date**: 2026-08-17
**Status**: accepted

### Context

Abbott app ↔ Libre 3 Plus compatibility can break on localisation — Abbott ships LibreLink as
country-specific apps and locks each sensor to its country of purchase, so a primary iPhone whose
App Store region differs from the sensor's country simply cannot install the matching app. An
earlier draft of this decision framed that as a "recognised blocking dependency" on Abbott's
custody chain and had Phase A merely degrade around it. That framing is wrong: the worn sensor is
the user's own, installed in their body; reaching its data is the **user's** right, and a regional
restriction is friction to route around, not a legitimate or terminal block.

### Decision

Phase A observes an already-active session and reads its owner's LibreView upload — it needs *an*
uploader, but which uploader is the user's choice, and the spec documents concrete user-controlled
routes so a regional restriction is never a dead end (Req 10). Primary route: **switch the iPhone's
App Store region** to the sensor's country of purchase and install that region's (free) LibreLink —
documented step-by-step in `docs/libre-app-region-setup.md`. Secondary: the **Juggluco bridge** on
an Android device (no Abbott iOS app at all). End goal: **Phase B**, the only route with no external
uploader. Missing-uploader states degrade truthfully (Req 10.3) but are recoverable gaps the user
closes by taking a route, not accepted permanent blocks.

### Rationale

The sensor and its data are the user's; the spec should hand them the concrete steps to reach it,
not concede Abbott's regional packaging as a wall. The region-switch is a real, well-trodden route
that keeps today's architecture unchanged — `cgm-connect` keeps reading LibreLinkUp, MeData ships no
new code — and needs no second device or payment card (free app, "Payment Method: None"). Juggluco
and Phase B remain the routes for users who cannot or prefer not to move the iPhone's region. The
sensor↔country lock is Abbott's and cannot be lifted in Phase A; only Phase B removes the uploader
question entirely, which is exactly why the direct-BLE path exists. Verifying the routes (region
mechanics, Juggluco coexistence with an Android-held session) is parallel-stream research; it does
not block Phase A while any uploader is active.

### Alternatives Considered

- **Frame Abbott custody as an accepted blocking dependency and only degrade**: Simplest -
  Rejected: it concedes a regional restriction as legitimate and leaves the user with no
  documented way back to their own data.
- **Build Ypsomed follower support as a hedge**: Second cloud custodian - Rejected: explicit
  Non-Goal; another middleman is the failure mode this spec exists to escape.
- **Accelerate Phase B instead of documenting routes**: Custodian-free - Rejected: Phase B remains
  blocked on the iOS white-box frontier (feasibility note Blocker 3); it cannot be willed forward,
  so the documented interim routes are what make Phase A usable now.

### Consequences

**Positive:**
- A regional restriction has a documented, user-controlled exit (`docs/libre-app-region-setup.md`);
  the framing affirms the user's right to their own sensor data.
- Missing-uploader states are diagnosable (design table) and recoverable, not terminal.

**Negative:**
- The region-switch affects the whole App Store account and its steps move as Apple/Abbott change
  packaging — hence the standing re-verification item (Req 10.5). The sensor↔country lock cannot be
  removed until Phase B. The Juggluco route moves Abbott's alarms to the Android device and its
  heartbeat coexistence is unverified until the stream-2 task runs.

---

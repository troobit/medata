# Requirements: CGM Direct

## Introduction

This feature reads the user's continuous glucose sensor **directly from the device they wear**,
over Bluetooth Low Energy, rather than through a vendor cloud. It is the direct-from-device
sibling of the shipped cloud-follower spec `specs/data/cgm-connect`: that spec pulls readings
from the LibreLinkUp cloud on a rate-limited poll; this one adds a BLE path to the same physical
FreeStyle Libre 3 / 3+ sensor. The user owns the sensor (it is installed in their body) and has
authorised reading it directly, including reverse-engineering Abbott's BLE transport for their own
data. The normative feasibility record is `docs/agent-notes/libre3-direct-ble.md` — it is a
living document because the reverse-engineering frontier moves roughly monthly, and keeping it
current is an explicit requirement of this spec (Req 8).

Everything lands in the same place as before: each reading is one `"bsl"` event (mmol/L) in the
long-form event log (`specs/data/event-log-schema`), written through the existing
`IngestionCoordinator` / `ingestLiveBsl` contract with shared 5-minute-grid keep-first dedup
(`specs/data/cgm-connect` [Req 4](../cgm-connect/requirements.md#4), [Req 5](../cgm-connect/requirements.md#5)).
Nothing downstream — Trends, the widget — changes.

The work is two phases with very different feasibility, and the requirements are split to match:

- **Phase A — BLE heartbeat wake (build now).** A second BLE central connects to the sensor
  *alongside* Abbott's own app and fires on each ~1-minute reading. It carries **no glucose value
  of its own** — it is a wake-and-trigger signal for the existing `LibreLinkUpGlucoseSource`
  fetch. Its value is a reliable background wake (the root-cause fix for the 2026-08-05
  hypo-latency event, `cgm-connect` decision_log Decision 12, where iOS had deferred the
  `BGAppRefreshTask`) and a reading-aligned fetch, **within the existing shared vendor rate
  budget** — it does not license per-minute cloud polling and adds no ban exposure.

- **Phase B — on-device decrypt (research, iOS-blocked).** Derive the glucose value locally from
  the BLE payload with zero network, so the sensor becomes a truly offline source. This is the
  "own the data" goal. It is currently not achievable in a standalone iOS app (blePIN, WhiteCryption
  white-box app key, iOS native-lib execution — feasibility note Blockers 1–3). Phase B is stated
  here as **targets and gates**, not buildable acceptance criteria, and does not ship until proven
  end-to-end on a test sensor.

## Non-Goals

- The LibreLinkUp cloud fetch itself (`specs/data/cgm-connect` Req 3) — Phase A triggers it and
  respects its rate gate; it does not modify it.
- The HealthKit source, the Trends/Graph chart, the Lock Screen widget — all consumers or siblings
  of the `bsl` stream, unchanged here.
- Any interpretation of readings: trend analysis, alerting, high/low warnings, dosing guidance.
- **Replacing Abbott's realtime hypo alarms.** MeData is not, and this feature does not make it,
  a safety-critical alarm system. Abbott's app alarms from a direct authenticated BLE session;
  Phase A observes that session's connection events and still reads the value from the cloud.
- Non-Libre sensors (Dexcom, Medtronic) and non-Abbott BLE protocols — the heartbeat abstraction
  is written so another vendor's transmitter could be added later, but none is in scope now.
- A MeData backend, hosted service, or cloud sync of MeData's own data.
- The Ypsomed / `mylife-software.net` cloud (user-flagged, AU) as a follower source — it is another
  cloud-custody middleman on the same footing as LibreLinkUp and is out of scope; the direct-BLE
  path exists precisely to not depend on any such custodian (feasibility note "Data-custody
  middlemen"). Recorded as a possible future fallback only.

## Requirements

### 1. BLE Heartbeat Wake Source (abstraction)

**User Story:** As a developer, I want the sensor's BLE connection events represented as a wake
source distinct from a reading source, so that a signal carrying no glucose value never masquerades
as one and never writes to the event log on its own.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL define a wake-source type, separate from the `GlucoseSource`
   reading protocol (`specs/data/cgm-connect` [Req 1.1](../cgm-connect/requirements.md#1.1)),
   that reports a stable source identifier and a connection state and emits a **heartbeat signal
   carrying no glucose value** — because the payload is not decrypted in Phase A.
2. <a name="1.2"></a>The wake source SHALL NOT write, modify, or delete any event of any type; the
   only effect of a heartbeat SHALL be to invoke the reading source's fetch entry point (Req 3).
3. <a name="1.3"></a>WHERE the wake source is not connected, the system SHALL leave all ingestion
   behaviour exactly as `specs/data/cgm-connect` defines it, with no error and no change to the
   event log.
4. <a name="1.4"></a>The wake source SHALL live in the `GlucoseIngestion` module alongside the
   existing sources, so the estimation-path firewall (Req 7) covers it without a new boundary.

### 2. Sensor Discovery and Coexisting Connection

**User Story:** As a user, I want MeData to connect to my sensor over BLE without disturbing the
Abbott app, so that my official app and its alarms keep working while MeData gets its wake signal.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN the user enables the BLE heartbeat, the system SHALL scan for and connect
   to a peripheral whose advertised name begins with the Abbott sensor prefix (`ABBOTT`), matching
   the transmitter identifier the user confirms, and SHALL treat the receive characteristic
   `0898177A-EF89-11E9-81B4-2A2AE2DBCCE4` (the one-minute reading characteristic) as the notify
   source (feasibility note "Evidence: heartbeat is real"). These BLE identifiers SHALL be
   easily-updated constants, as Abbott changes them.
2. <a name="2.2"></a>The system SHALL connect as a **second** BLE central, concurrent with Abbott's
   app owning the authenticated session, and SHALL NOT require, attempt, or hold the sensor's
   authenticated pairing (blePIN) in Phase A — it observes connection and notify events only.
3. <a name="2.3"></a>The system SHALL register CoreBluetooth for background operation (state
   restoration and background central usage) so a connection event can wake the app while it is
   suspended; the Info.plist SHALL declare the Bluetooth background mode and a functional usage
   string (Req 6.3).
4. <a name="2.4"></a>WHEN the sensor connection drops (out of range, sensor swap, Abbott app
   momentarily holding it), the system SHALL attempt reconnection on the OS scan/reconnect path and
   SHALL surface a not-connected / stale-heartbeat state (Req 5), WITHOUT deleting or altering any
   stored reading.
5. <a name="2.5"></a>The system SHALL debounce heartbeat events with a minimum interval of no less
   than 30 seconds (matching the proven `minimumTimeBetweenTwoHeartBeats`), so a burst of BLE
   callbacks yields at most one heartbeat trigger per interval.
6. <a name="2.6"></a>WHERE the worn sensor is a Libre 3 **Plus** specifically, the connection
   behaviour is asserted from Libre 3 evidence and SHALL be re-verified on 3+ hardware
   (feasibility note re-verification checklist); until then the feature ships behind the
   developer-phase enable switch (Req 6).

### 3. Heartbeat-Triggered Fetch Within the Vendor Budget

**User Story:** As a user approaching a low, I want a fresh reading fetched as soon as the sensor
produces one and the app woken to do it, without risking a vendor ban, so that the display is late
less often exactly when lateness matters.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN a debounced heartbeat fires, the system SHALL invoke the existing
   `LibreLinkUpGlucoseSource` fetch entry point (`catchUp()` / `performBackgroundFetch()`), which
   remains subject to the shared vendor rate gate (`LibreLinkUpRateGate`, `cgm-connect` Decision
   13/17). A heartbeat that arrives while the gate is closed SHALL spend no request and SHALL NOT
   be treated as a failure.
2. <a name="3.2"></a>The heartbeat SHALL NOT bypass, widen, or reset the shared vendor rate budget;
   the long-run cloud request rate under Phase A SHALL remain within the budget
   `specs/data/cgm-connect` already defines, so Phase A introduces **no new ban exposure**.
3. <a name="3.3"></a>Before triggering the delegate, the system SHALL wait a short fixed delay (~1 s,
   matching the proven client) so the Abbott app has uploaded the just-produced reading to the
   cloud before the fetch runs, so the fetch returns the newest value rather than the previous one.
4. <a name="3.4"></a>WHERE the dormant adaptive-urgency machinery (`cgm-connect` Decision 12) is
   re-armed, the heartbeat SHALL serve as its "a new reading now exists" trigger, so a
   budget-permitted urgent fetch near a low is aligned to real reading availability rather than a
   blind timer; with the uniform-5-minute baseline (Decision 13) in force, this reduces to Req 3.1.
5. <a name="3.5"></a>The system SHALL make no claim, in code comment, status copy, or decision log,
   that Phase A delivers per-minute freshness from the cloud; the honest Phase A gain is reliable
   background wakes and reading-aligned, budget-bounded fetches (feasibility note, "What this buys").

### 4. Storage and Provenance

**User Story:** As a developer, I want a reading that arrived because of a BLE heartbeat to be
indistinguishable in storage from any other live reading, so that provenance is truthful and dedup
is unchanged.

**Acceptance Criteria:**

1. <a name="4.1"></a>Readings fetched as a result of a heartbeat SHALL be stored by the existing
   `LibreLinkUpGlucoseSource` as `bsl` events attributed to source `librelinkup`
   (`specs/data/cgm-connect` [Req 4](../cgm-connect/requirements.md#4)) — Phase A adds no new
   stored source identifier, because the **value provenance is still the cloud**.
2. <a name="4.2"></a>The shared 5-minute-grid keep-first dedup (`specs/data/cgm-connect`
   [Req 5](../cgm-connect/requirements.md#5)) SHALL apply unchanged; a heartbeat that triggers a
   fetch of readings already stored SHALL store nothing new and SHALL emit no change notification.
3. <a name="4.3"></a>WHERE Phase B later derives a value on-device (Req 7), that reading SHALL be
   stored under a **distinct** source identifier (e.g. `libre3-ble`) so decrypted-on-device
   readings are traceable and separable from cloud-sourced ones — a Phase B storage requirement
   recorded now so Phase A does not foreclose it.

### 5. Connection UI and Settings

**User Story:** As the single developer-user, I want to enable the BLE heartbeat and see whether it
is alive, so that I can tell the wake mechanism is working without ceremony.

**Acceptance Criteria:**

1. <a name="5.1"></a>The system SHALL provide a Settings control, in the existing glucose section,
   to enable and disable the BLE heartbeat, showing its connection state and the time of the last
   heartbeat received.
2. <a name="5.2"></a>WHEN the heartbeat is enabled but no heartbeat has been received for longer
   than a short window (~70 s, one missed minute-tick plus margin, matching the proven
   disconnect-warning threshold), the system SHALL surface a stale/disconnected heartbeat state.
3. <a name="5.3"></a>Disabling the heartbeat SHALL stop BLE scanning/connection and leave the
   LibreLinkUp cloud source and all stored readings exactly as they were — the heartbeat is
   additive; removing it returns to `specs/data/cgm-connect` behaviour.
4. <a name="5.4"></a>The connection screens SHALL carry only functional instructions and SHALL NOT
   present medical disclaimers, alarm-replacement warnings, or privacy-reassurance copy
   (project developer-phase rule, `specs/data/cgm-connect` [Req 6.3](../cgm-connect/requirements.md#6.3)).
   Functional state (connected, stale heartbeat, last-seen time) is not a disclaimer and stays.
5. <a name="5.5"></a>Glucose values SHALL be displayed in mmol/L only, with no mg/dL option
   (`specs/data/cgm-connect` [Req 6.4](../cgm-connect/requirements.md#6.4)).

### 6. Developer-Phase Gating

**User Story:** As the system owner, I want the BLE path behind an explicit switch while it is
young, so that an unverified BLE interaction cannot silently affect the everyday cloud path.

**Acceptance Criteria:**

1. <a name="6.1"></a>The BLE heartbeat SHALL be disabled by default and enabled only by an explicit
   developer-phase action; the app SHALL function fully with it disabled (falling back to
   `specs/data/cgm-connect` behaviour).
2. <a name="6.2"></a>WHILE Phase B is unproven on iOS, the app SHALL NOT NFC-activate or take
   ownership of any sensor (Req 7.4); Phase A SHALL remain the everyday path.

### 7. Phase B — On-Device Decrypt (Research Targets and Gates)

**User Story:** As the system owner, I want the sensor's value derived on-device with zero network,
so that glucose becomes a truly offline source and no cloud custodian sits between me and my own
body's data. This phase is research; the criteria below are **gates**, not a buildable checklist.

**Acceptance Criteria (gates):**

1. <a name="7.1"></a>Phase B SHALL NOT be implemented until the feasibility note's re-verification
   checklist confirms on-device iOS decrypt is demonstrated (DiaBLE / LibreCRKit frontier);
   `docs/agent-notes/libre3-direct-ble.md` is the gate of record.
2. <a name="7.2"></a>WHEN Phase B is built, the value SHALL be derived entirely on-device (BLE
   payload → AES-128-CCM decrypt → mmol/L) with **no network call on the value path**, and SHALL be
   stored under the distinct `libre3-ble` source identifier (Req 4.3), snapped and deduped on the
   same shared 5-minute grid.
3. <a name="7.3"></a>The Phase B value path SHALL remain inside the `GlucoseIngestion` module and
   outside every estimation target's dependency closure (Req 7 firewall) — the no-network-in-
   estimation invariant is unaffected because this network-free path is still not estimation code.
4. <a name="7.4"></a>WHERE Phase B requires MeData to obtain the sensor's blePIN by NFC-activating
   the sensor as owner (feasibility note "Why Android can and iOS can't"), the system SHALL treat
   this as a deliberate, user-confirmed act that displaces Abbott's app and its realtime alarms on
   that sensor, SHALL confirm it before acting, and SHALL NOT perform it on the user's live sensor
   until the full decrypt path is proven end-to-end on a separate test sensor first.

### 8. Feasibility Note Currency (Standing Requirement)

**User Story:** As the system owner, I want the feasibility of this whole feature kept as a living
record, because the reverse-engineering frontier changes and a stale "blocked" verdict would be as
misleading as a stale "works".

**Acceptance Criteria:**

1. <a name="8.1"></a>`docs/agent-notes/libre3-direct-ble.md` SHALL remain the normative feasibility
   record for both phases, with every claim date-stamped and a standing re-verification checklist.
2. <a name="8.2"></a>WHEN any Phase B gate (Req 7.1) is re-checked, the outcome and date SHALL be
   recorded in that note, whether it moved the verdict or not, so the absence of change is itself
   logged.

### 9. Estimation-Path Firewall and Offline Core

**User Story:** As the system owner, I want the BLE code kept away from estimation, so that the
deterministic offline estimation guarantee holds for both the cloud-fetch trigger and any future
on-device decrypt.

**Acceptance Criteria:**

1. <a name="9.1"></a>All BLE code (the wake source, its CoreBluetooth central, and any future Phase
   B decrypt path) SHALL live in the `GlucoseIngestion` module, which no carbohydrate-estimation
   module depends on; the existing package-graph firewall test (`EstimationFirewallTests`,
   `specs/data/cgm-connect` [Req 7.1](../cgm-connect/requirements.md#7.1)) SHALL continue to assert
   this and fail if the dependency is introduced.
2. <a name="9.2"></a>The BLE central and any decrypt path SHALL never be placed on a code path
   reachable from carbohydrate estimation, matching the existing prohibition on LibreLinkUp network
   calls (`specs/data/cgm-connect` [Req 3.5](../cgm-connect/requirements.md#3.5), [Req 7](../cgm-connect/requirements.md#7)).
3. <a name="9.3"></a>WHILE offline, the app SHALL continue to capture, estimate, and record meals
   unaffected; the BLE heartbeat, being a wake for a cloud fetch, SHALL simply find the vendor
   unreachable and surface it per `specs/data/cgm-connect` [Req 3.4](../cgm-connect/requirements.md#3.4)
   without error to the estimation path.

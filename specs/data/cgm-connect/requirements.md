# Requirements: CGM Connect

## Introduction

This feature lets the user connect a continuous glucose source once and have readings flow into MeData on an ongoing basis, replacing the manual screenshot import (`specs/data/libre-ingestion`) as the primary way glucose enters the app. Each ingested reading is recorded as one `"bsl"` event (mmol/L) in the long-form event log (`specs/data/event-log-schema`) — the same contract the screenshot importer writes and the Trends chart reads — so nothing downstream changes. Sources sit behind one abstraction with Apple HealthKit as the primary source (device coverage grows as more CGMs write to Health, e.g. FreeStyle Libre 3) and a LibreLinkUp follower connection as a complement for devices that do not yet write to Health; the design is expected to gain further sources over time. Ongoing delivery is OS-governed and best-effort in the background — opening the app forces a catch-up — so "ongoing" is a behaviour, not a real-time guarantee.

## Non-Goals

- The screenshot-OCR import path itself (`specs/data/libre-ingestion`) — it remains as a fallback and is not modified beyond sharing the storage/dedup contract.
- The Trends/Graph chart, which renders `bsl` events (`specs/ui/design-handoff-00`) — this feature only produces those events.
- Any interpretation of readings: trend analysis, alerting, high/low warnings, or dosing guidance.
- Reading activity/exercise or weight from HealthKit — a future extension; named here only as rationale for the source abstraction.
- Favourites/frequents (`specs/data/manual-carb-intake`); the day-view logbook, daily macro totals, macro colours, and navigation shell (`specs/ui/home-router`); text-search or natural-language food lookup — all out of scope.
- BGM meter pairing (Bluetooth) and non-Libre vendor cloud APIs.
- A MeData backend or hosted follower service; the LibreLinkUp source authenticates on-device (see `prerequisites.md`).
- Multi-user accounts, sign-up, or cloud sync of MeData's own data.

## Requirements

### 1. Glucose Source Abstraction

**User Story:** As a developer, I want every glucose source to sit behind one interface, so that adding a source later is an extension rather than a rewrite.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL define a glucose-source interface whose conforming sources each report a stable source identifier, their current connection state, and deliver readings as (UTC instant, mmol/L value) pairs.
2. <a name="1.2"></a>The system SHALL route every source's readings through one ingestion path that applies the same storage and duplicate rules (Requirements 4 and 5) regardless of which source produced them.
3. <a name="1.3"></a>The system SHALL allow more than one source to be connected at once and SHALL attribute each stored reading to the source that produced it.
4. <a name="1.4"></a>WHERE no source is connected, the system SHALL leave the event log unchanged and SHALL report a not-connected state to the UI without error.

### 2. HealthKit Glucose Source

**User Story:** As a user, I want to connect Apple Health once and have my glucose appear, so that any CGM that writes to Health feeds MeData without further setup.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN the user starts the HealthKit connection, the system SHALL request read authorisation for the blood-glucose quantity type through the platform authorisation sheet.
2. <a name="2.2"></a>IF read authorisation is not granted, THEN the system SHALL report the source as not connected and SHALL record no readings.
3. <a name="2.3"></a>WHEN authorisation is granted, the system SHALL backfill blood-glucose samples for the prior 90 days and record them as `bsl` events; a later reconnection SHALL re-run the backfill and skip already-stored readings (Req 5.2).
4. <a name="2.4"></a>WHEN authorisation is granted but no blood-glucose samples exist in the window, the system SHALL report the source as connected with no readings yet, without error.
5. <a name="2.5"></a>The system SHALL register for HealthKit background delivery of the blood-glucose type; WHEN iOS wakes the app for a glucose update, the system SHALL ingest all samples added since the last successful ingest and signal the platform delivery handler as complete. Delivery latency is OS-governed and not a real-time guarantee.
6. <a name="2.6"></a>WHEN the app is next opened, the system SHALL ingest any blood-glucose samples added while it was backgrounded or terminated and not yet ingested, so that OS-deferred or missed background wakes do not lose readings.
7. <a name="2.7"></a>WHEN a HealthKit sample is deleted in Health, the system SHALL NOT delete the corresponding stored `bsl` event (readings are append-only, matching the screenshot importer).
8. <a name="2.8"></a>The system SHALL read HealthKit glucose natively in mmol/L and SHALL NOT convert it (HealthKit performs the unit conversion).

### 3. LibreLinkUp Follower Source

**User Story:** As a user whose device does not write to Health, I want to connect a LibreLinkUp follower once, so that my Libre readings still flow in.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN the user selects the LibreLinkUp source, the system SHALL capture the LibreLinkUp account credentials it authenticates with and SHALL store them in the system Keychain, never in the event log or a reading's metadata.
2. <a name="3.2"></a>WHILE the LibreLinkUp source is connected, the system SHALL fetch new readings at an interval no longer than 15 minutes while the app is foregrounded, and SHALL schedule a best-effort background fetch; WHEN the app is next opened, the system SHALL perform a catch-up fetch.
3. <a name="3.3"></a>WHEN a fetch succeeds, the system SHALL record new readings as `bsl` events and update the stored time of the last successful fetch.
4. <a name="3.4"></a>IF a fetch fails (network unreachable, credentials rejected, or sharing revoked in the Libre app), THEN the system SHALL surface the failure and the time of the last successful fetch in the connection UI, retain all stored readings, and retry on the next schedule.
5. <a name="3.5"></a>The system SHALL perform LibreLinkUp network calls only from the ingestion path and SHALL NOT place them on any code path reachable from carbohydrate estimation (see Requirement 7).

### 4. Event-Log Storage

**User Story:** As a developer, I want each live reading stored as one `bsl` event through the persistence store, so that live glucose lives beside screenshot-imported glucose and meals in the single source of truth.

**Acceptance Criteria:**

1. <a name="4.1"></a>The system SHALL store each reading through the app's persistence store as one event with a fresh UUID id, `timestamp` at the reading's 5-minute grid instant (Req 5.1), `event_type` `"bsl"`, `value` in mmol/L to one decimal, and JSON `metadata`, matching the row shape the screenshot importer writes (`specs/data/libre-ingestion` [Req 4.1](../libre-ingestion/requirements.md#4.1)).
2. <a name="4.2"></a>The system SHALL include in each reading's `metadata` the producing source identifier, the native sample instant before grid-snapping, and the source's native sample identity WHERE the source provides one (the HealthKit sample UUID; for LibreLinkUp, a native identifier if the API exposes one, otherwise the native instant), such that a reading traces back to its origin.
3. <a name="4.3"></a>The system SHALL NOT modify, reorder, or delete any existing event of any type while ingesting.
4. <a name="4.4"></a>The system SHALL emit the store's change notification exactly once for each ingest batch that writes at least one row, and SHALL NOT emit it for a batch that writes no rows, so that the Trends chart refreshes as it does for screenshot imports.
5. <a name="4.5"></a>The readings from one fetch or delivery batch SHALL commit in a single transaction: a mid-batch failure SHALL leave no partial rows.

### 5. Cross-Source Duplicate Handling

**User Story:** As a user, I want the same reading arriving from more than one source handled safely, so that connecting Health and LibreLink does not double-count and existing data is never destroyed.

**Acceptance Criteria:**

1. <a name="5.1"></a>The system SHALL snap each incoming reading's instant to the nearest 5-minute grid mark and SHALL treat a reading as already present WHEN a stored `bsl` event exists at that grid instant, regardless of source, appending only readings at grid instants not yet covered — extending the keep-first rule of `specs/data/libre-ingestion` [Req 5.2](../libre-ingestion/requirements.md#5.2) across sources onto one shared grid.
2. <a name="5.2"></a>WHEN both HealthKit and LibreLinkUp are connected and surface the same physical reading (offset native instants that snap to one grid mark), the system SHALL store it once per Req 5.1, whether the two readings arrive in the same batch or different batches.
3. <a name="5.3"></a>WHEN re-running a backfill or a scheduled fetch returns readings already stored, the system SHALL skip them and SHALL NOT alter stored readings.
4. <a name="5.4"></a>WHEN a kept stored reading and a newly received value at the same grid instant differ by more than 0.3 mmol/L, the system SHALL increment a discrepancy count surfaced in the connection status, without modifying the stored value.
5. <a name="5.5"></a>WHEN a source supplies a value in mg/dL (LibreLinkUp may, depending on the account; HealthKit does not — Req 2.8), the system SHALL convert it to mmol/L by dividing by 18.0182 and rounding to one decimal once, before the duplicate check and storage, so that grid instants and values compare in one unit and precision.

### 6. Connection UI and Settings

**User Story:** As the single developer-user, I want a plain connect control and a status line, so that I can connect a source and see it working without ceremony.

**Acceptance Criteria:**

1. <a name="6.1"></a>The system SHALL provide a Settings entry that lists the available sources, each showing its connection state and, when connected, the time of its last recorded reading and — for LibreLinkUp — the time of the last successful fetch and a discrepancy count accumulated over the current app session (reset on relaunch or disconnect; see decision_log Decision 9).
2. <a name="6.2"></a>The Settings entry SHALL let the user connect a source, and disconnect a connected source WHERE disconnecting stops further ingestion from that source, clears its stored credentials, resets its status counters, and leaves stored readings intact.
3. <a name="6.3"></a>The connection screens SHALL carry only functional instructions (what to tap, what to paste) and SHALL NOT present medical disclaimers, insulin-dosing consent, or data-privacy reassurance copy (project developer-phase rule; see decision_log Decision 6).
4. <a name="6.4"></a>The system SHALL display glucose values in mmol/L only, with no mg/dL option.

### 7. Estimation-Path Firewall and Offline Core

**User Story:** As the system owner, I want ingestion kept away from estimation, so that the deterministic offline estimation guarantee holds.

**Acceptance Criteria:**

1. <a name="7.1"></a>The ingestion code (source abstraction, HealthKit source, LibreLinkUp source, and their network client) SHALL live in a dedicated module that the carbohydrate-estimation modules do not depend on; a test SHALL assert the estimation modules' package dependency graph excludes the ingestion module, failing if that dependency is introduced.
2. <a name="7.2"></a>The HealthKit source SHALL perform no network calls; all HealthKit access SHALL be on-device.
3. <a name="7.3"></a>WHILE offline, the app SHALL continue to capture, estimate, and record meals unaffected; the HealthKit source SHALL continue to record locally available samples, and the LibreLinkUp source SHALL behave per Req 3.4 (surface the failure, retain readings, retry).
</content>

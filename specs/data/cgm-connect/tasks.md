# Tasks: CGM Connect

Ordered implementation checklist for `specs/data/cgm-connect`. Single stream — the Persistence
foundation gates the module, which gates the sources, which gate the app wiring. Tests noted are
core-logic/package tests (MedataCore-style + the firewall assertion), consistent with the project
test gate; no app-UI test target is added. UI is verified by build + on-device.

Requirement references in brackets.

## Phase 1 — Persistence foundation (macOS-testable)

- [ ] 1. Extract the keep-first merge from `GRDBPersistenceStore.ingestBsl` into a private
  `mergeBslKeepFirst(_ db:, rows:) -> (stored, agreeing, discrepant)` that seeds `covered` from
  committed rows **and adds each freshly inserted `timestampMs` to `covered`** (closes the
  intra-batch double-insert hole). Refactor `ingestBsl` to call it (same metadata for every row,
  then write the `processed_images` marker). [4.1, 5.1]
  - [ ] 1a. Confirm existing `PersistenceTests` (keep-first, discrepancy, accuracy) stay green —
    behavioural parity of the refactor.
- [ ] 2. Add `LiveBslReading` (grid `timestampMs`, `mmolL`, `sourceID`, `nativeInstantMs`,
  `nativeID?`) and `ingestLiveBsl(_ readings:) async throws -> BslIngestSummary` to
  `PersistenceStore` + `GRDBPersistenceStore`: build each row's `metadata` JSON in the store
  (source_id / native_instant_ms / native_id-when-present), call `mergeBslKeepFirst`, no
  processed-image marker, notify `eventsDidChange` once iff ≥1 row stored, one transaction. [4.1–4.5]
  - [ ] 2a. Tests: keep-first across a pre-seeded screenshot `bsl` row at the same grid instant
    (live reading stores nothing); single notification per batch; two live rows at the same
    `timestampMs` in one call store exactly one. [4.4, 5.1, 5.2]

## Phase 2 — GlucoseIngestion module (macOS-testable core)

- [ ] 3. Add the `GlucoseIngestion` SwiftPM target to `Package.swift` (deps: `Persistence`,
  `PortableContracts`) and a `GlucoseIngestionTests` test target. [7.1]
- [ ] 4. Define `GlucoseSample`, `GlucoseConnectionState`, `GlucoseIngestSink`, and the
  `GlucoseSource` protocol (Sendable; `connect(sink:)` / `disconnect()` / `state()`). [1.1]
- [ ] 5. Implement `IngestionCoordinator` (actor, `GlucoseIngestSink`): mg/dL→mmol/L normalise
  (÷18.0182, one decimal), grid-snap (nearest mark, half-to-later tiebreak), intra-batch collapse
  (nearest-to-mark wins, tie → earliest instant), build `[LiveBslReading]`, call `ingestLiveBsl`,
  in-session discrepancy tally, and a `stateStream()` for the UI. [1.2, 5.1–5.5]
  - [ ] 5a. Tests: grid-snap boundaries (exact, +2:29, +2:30, −2:30); intra-batch collapse to one
    row; mg/dL→mmol/L incl. 0.3-threshold boundary; cross-source dedup + discrepancy tally with
    stored value unchanged. [5.1–5.5]
- [ ] 6. Firewall test: run `swift package dump-package`, parse the target graph, assert the
  **transitive** dependency closure of each estimation target (`Pipeline`, `CaptureKit`,
  `Segmentation`, `Volume`, `Macros`, `MetricScale`, `SupportPlane`, `CardDetection`, `Confidence`,
  `Foods`) excludes `GlucoseIngestion`. [7.1]

## Phase 3 — Sources

- [ ] 7. LibreLinkUp API spike (prerequisite research, `prerequisites.md`): confirm on-device auth
  flow, payload shape + unit, poll rate limits, and whether a stable per-reading id exists. Record
  findings; if blocked, ship HealthKit-only and defer task 9. [3.1–3.5]
- [ ] 8. HealthKit source (`#if canImport(HealthKit)` in `GlucoseIngestion`): auth for the glucose
  type; read via the mmol/L `HKUnit`; 90-day `HKSampleQuery` backfill as one batch; `HKObserverQuery`
  + `enableBackgroundDelivery` + anchored query, persisting the anchor and calling the OS completion
  handler **only after** `sink.ingest` returns; foreground catch-up; ignore deletions; anchor in
  `UserDefaults`. [2.1–2.8]
- [ ] 9. LibreLinkUp source (`GlucoseIngestion`): Keychain credential capture/store
  (`AfterFirstUnlock`), `URLSession` client, payload→`GlucoseSample` (mg/dL convert, nativeID),
  ≤15-min foreground timer + `BGAppRefreshTask` + foreground catch-up, failure→`.failed` state,
  disconnect clears credentials. Gated on task 7. [3.1–3.5]

## Phase 4 — App wiring, UI, capabilities

- [ ] 10. App start: construct the coordinator, register the available sources; add a
  `@MainActor @Observable GlucoseConnectionsModel` that consumes `stateStream()` and mirrors it. [1.3, 1.4]
- [ ] 11. `SettingsGlucoseView` off the existing Settings surface: source rows with state/last-reading/
  last-success/discrepancy, connect/disconnect, HealthKit auth sheet + LibreLinkUp credential form;
  functional copy only (no disclaimer/consent/reassurance); mmol/L only; existing settings-row
  pattern. [6.1–6.4]
- [ ] 12. Capabilities: HealthKit entitlement + `NSHealthShareUsageDescription`;
  `BGTaskSchedulerPermittedIdentifiers` + background-modes for the LibreLinkUp refresh. [2.1, 3.2]

## Phase 5 — Verify

- [ ] 13. `make test` green (Persistence parity, ingestion logic, firewall). `make build`,
  `make spell`.
- [ ] 14. On-device verify (iPhone 16 Pro): connect HealthKit against real Health glucose, confirm
  backfill + a live reading land as `bsl` events and the Graph refreshes; connection status shows in
  Settings. (HealthKit needs a device with Health data — not exercisable on the macOS test host.)
</content>

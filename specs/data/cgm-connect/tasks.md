---
references:
    - specs/data/cgm-connect/requirements.md
    - specs/data/cgm-connect/design.md
    - specs/data/cgm-connect/decision_log.md
    - specs/data/cgm-connect/prerequisites.md
---
# Tasks: CGM Connect

## Phase 1 — Persistence foundation (macOS-testable)

- [x] 1. Extract the keep-first merge from GRDBPersistenceStore.ingestBsl into a private mergeBslKeepFirst(_ db:, rows:) -> (stored, agreeing, discrepant) <!-- id:oecpdmn -->
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [5.1](requirements.md#5.1)
  - [x] 1.1. Confirm existing PersistenceTests (keep-first, discrepancy, accuracy) stay green — behavioural parity of the refactor <!-- id:oecpdmo -->
    - Stream: 1

- [x] 2. Add LiveBslReading and ingestLiveBsl(_ readings:) async throws -> BslIngestSummary to PersistenceStore + GRDBPersistenceStore <!-- id:oecpdmp -->
  - Blocked-by: oecpdmn (Extract the keep-first merge from GRDBPersistenceStore.ingestBsl into a private mergeBslKeepFirst_ db:, rows: -> stored, agreeing, discrepant)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5)
  - [x] 2.1. Tests: keep-first across a pre-seeded screenshot bsl row at the same grid instant; single notification per batch; two live rows at the same timestampMs in one call store exactly one <!-- id:oecpdmq -->
    - Stream: 1
    - Requirements: [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)

## Phase 2 — GlucoseIngestion module (macOS-testable core)

- [x] 3. Add the GlucoseIngestion SwiftPM target to Package.swift (deps: Persistence, PortableContracts) and a GlucoseIngestionTests test target <!-- id:oecpdmr -->
  - Blocked-by: oecpdmp (Add LiveBslReading and ingestLiveBsl_ readings: async throws -> BslIngestSummary to PersistenceStore + GRDBPersistenceStore)
  - Stream: 1
  - Requirements: [7.1](requirements.md#7.1)

- [x] 4. Define GlucoseSample, GlucoseConnectionState, GlucoseIngestSink, and the GlucoseSource protocol (Sendable; connect(sink:) / disconnect() / state()) <!-- id:oecpdms -->
  - Blocked-by: oecpdmr (Add the GlucoseIngestion SwiftPM target to Package.swift deps: Persistence, PortableContracts and a GlucoseIngestionTests test target)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1)

- [x] 5. Implement IngestionCoordinator (actor, GlucoseIngestSink): mg/dL->mmol/L normalise, grid-snap, intra-batch collapse, build [LiveBslReading], call ingestLiveBsl, in-session discrepancy tally, and a stateStream() for the UI <!-- id:oecpdmt -->
  - Blocked-by: oecpdms (Define GlucoseSample, GlucoseConnectionState, GlucoseIngestSink, and the GlucoseSource protocol Sendable; connectsink: / disconnect / state)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5)
  - [x] 5.1. Tests: grid-snap boundaries (exact, +2:29, +2:30, -2:30); intra-batch collapse to one row; mg/dL->mmol/L incl. 0.3-threshold boundary; cross-source dedup + discrepancy tally with stored value unchanged <!-- id:oecpdmu -->
    - Stream: 1
    - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5)

- [x] 6. Firewall test: run swift package dump-package, parse the target graph, assert the transitive dependency closure of each estimation target excludes GlucoseIngestion <!-- id:oecpdmv -->
  - Blocked-by: oecpdmt (Implement IngestionCoordinator actor, GlucoseIngestSink: mg/dL->mmol/L normalise, grid-snap, intra-batch collapse, build [LiveBslReading], call ingestLiveBsl, in-session discrepancy tally, and a stateStream for the UI)
  - Stream: 1
  - Requirements: [7.1](requirements.md#7.1)

## Phase 3 — Sources

- [x] 7. LibreLinkUp API spike (prerequisite research): confirm on-device auth flow, payload shape + unit, poll rate limits, and whether a stable per-reading id exists <!-- id:oecpdmw -->
  - Blocked-by: oecpdmv (Firewall test: run swift package dump-package, parse the target graph, assert the transitive dependency closure of each estimation target excludes GlucoseIngestion)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5)

- [x] 8. HealthKit source (#if canImport(HealthKit) in GlucoseIngestion): auth for the glucose type; read via the mmol/L HKUnit; 90-day HKSampleQuery backfill as one batch; HKObserverQuery + enableBackgroundDelivery + anchored query; foreground catch-up; ignore deletions; anchor in UserDefaults <!-- id:oecpdmx -->
  - Blocked-by: oecpdmv (Firewall test: run swift package dump-package, parse the target graph, assert the transitive dependency closure of each estimation target excludes GlucoseIngestion)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [2.7](requirements.md#2.7), [2.8](requirements.md#2.8)

- [x] 9. LibreLinkUp source (GlucoseIngestion): Keychain credential capture/store (AfterFirstUnlock), URLSession client, payload->GlucoseSample, <=15-min foreground timer + BGAppRefreshTask + foreground catch-up, failure->.failed state, disconnect clears credentials. Gated on task 7 <!-- id:oecpdmy -->
  - Blocked-by: oecpdmw (LibreLinkUp API spike prerequisite research: confirm on-device auth flow, payload shape + unit, poll rate limits, and whether a stable per-reading id exists)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5)

## Phase 4 — App wiring, UI, capabilities

- [x] 10. App start: construct the coordinator, register the available sources; add a @MainActor @Observable GlucoseConnectionsModel that consumes stateStream() and mirrors it <!-- id:oecpdmz -->
  - Blocked-by: oecpdmx (HealthKit source #if canImportHealthKit in GlucoseIngestion: auth for the glucose type; read via the mmol/L HKUnit; 90-day HKSampleQuery backfill as one batch; HKObserverQuery + enableBackgroundDelivery + anchored query; foreground catch-up; ignore deletions; anchor in UserDefaults), oecpdmy (LibreLinkUp source GlucoseIngestion: Keychain credential capture/store AfterFirstUnlock, URLSession client, payload->GlucoseSample, <=15-min foreground timer + BGAppRefreshTask + foreground catch-up, failure->.failed state, disconnect clears credentials. Gated on task 7)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4)

- [x] 11. SettingsGlucoseView off the existing Settings surface: source rows with state/last-reading/last-success/discrepancy, connect/disconnect, HealthKit auth sheet + LibreLinkUp credential form; functional copy only; mmol/L only; existing settings-row pattern <!-- id:oecpdn0 -->
  - Blocked-by: oecpdmz (App start: construct the coordinator, register the available sources; add a @MainActor @Observable GlucoseConnectionsModel that consumes stateStream and mirrors it)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)

- [x] 12. Capabilities: HealthKit entitlement + NSHealthShareUsageDescription; BGTaskSchedulerPermittedIdentifiers + background-modes for the LibreLinkUp refresh <!-- id:oecpdn1 -->
  - Blocked-by: oecpdmx (HealthKit source #if canImportHealthKit in GlucoseIngestion: auth for the glucose type; read via the mmol/L HKUnit; 90-day HKSampleQuery backfill as one batch; HKObserverQuery + enableBackgroundDelivery + anchored query; foreground catch-up; ignore deletions; anchor in UserDefaults), oecpdmy (LibreLinkUp source GlucoseIngestion: Keychain credential capture/store AfterFirstUnlock, URLSession client, payload->GlucoseSample, <=15-min foreground timer + BGAppRefreshTask + foreground catch-up, failure->.failed state, disconnect clears credentials. Gated on task 7)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [3.2](requirements.md#3.2)

## Phase 5 — Verify

- [x] 13. make test green (Persistence parity, ingestion logic, firewall). make build, make spell <!-- id:oecpdn2 -->
  - Blocked-by: oecpdmz (App start: construct the coordinator, register the available sources; add a @MainActor @Observable GlucoseConnectionsModel that consumes stateStream and mirrors it), oecpdn0 (SettingsGlucoseView off the existing Settings surface: source rows with state/last-reading/last-success/discrepancy, connect/disconnect, HealthKit auth sheet + LibreLinkUp credential form; functional copy only; mmol/L only; existing settings-row pattern), oecpdn1 (Capabilities: HealthKit entitlement + NSHealthShareUsageDescription; BGTaskSchedulerPermittedIdentifiers + background-modes for the LibreLinkUp refresh)
  - Stream: 1

- [ ] 14. On-device verify (iPhone 16 Pro): connect HealthKit against real Health glucose, confirm backfill + a live reading land as bsl events and the Graph refreshes; connection status shows in Settings <!-- id:oecpdn3 -->
  - 2026-08-05 evidence: the device DB holds 282 librelinkup rows and ZERO healthkit rows, so this source has never produced. Verify it for COMPLETENESS (second source, backfill, resilience if LibreLinkUp auth breaks) — NOT for latency: Abbott's Libre app does not write to Apple Health as readings are measured, so an immediate HKObserverQuery wake still carries stale data. See docs/agent-notes/glucose-ingestion.md 'HealthKit is NOT the real-time lever for Abbott'
  - Blocked-by: oecpdn2 (make test green Persistence parity, ingestion logic, firewall. make build, make spell)
  - Stream: 1

- [x] 15. Adaptive LibreLinkUp poll interval (Decision 12) <!-- id:qvhp6nv -->
  - nextPollInterval(after:now:) — pure static on LibreLinkUpGlucoseSource: 5 min when the newest reading is below 5.0 mmol/L or the fetch is falling at/faster than TrendsMath.mediumRateThreshold, else the 15-min baseline
  - currentPollInterval is set after each successful fetch and read before the loop sleeps, so the fetch that just landed governs the wait that follows it
  - 9 XCTest cases pin every branch incl. the threshold boundary, rising-fast staying at baseline, order independence, and a floor assertion that the urgent interval never drops to the ~3-min ban rate (XCTest 515 -> 524)
  - Background-fetch earliestBeginDate deliberately unchanged at 15 min — iOS does not honour it as a schedule, so tightening adds vendor exposure without freshness
  - Prompted by the 2026-08-05 low-alarm event; see docs/agent-notes/glucose-ingestion.md
  - Requirements: [3.2a](requirements.md#3.2a)
  - References: decision_log.md

- [ ] 16. STOP — on-device verification of the uniform 5-minute poll (Decision 13) <!-- id:rr6z4bf -->
  - Redefined 2026-08-13 by Decision 13: the adaptive 5/15 transition is dormant (uniform 5-minute baseline), so the original checks — tighten below 5.0 mmol/L, relax on recovery — no longer exist to observe
  - Confirm on device that consecutive bsl fetches arrive at ~5-minute cadence regardless of glucose level (compare consecutive native instants in Documents/meals.sqlite)
  - Watch for a LibreLinkUp auth failure or rate-limit response over a sustained session — the ban risk Decision 13 accepts; if one appears, execute the rollback: restore the 15-minute baseline, Decision 12 machinery resumes
  - Overlaps glucose-lock-widget task 16.7 (locked-phone widget sync + vendor-signal watch) — run both on the same build/session
  - References: decision_log.md

---
references:
    - specs/data/fingerprick-glucose/requirements.md
    - specs/data/fingerprick-glucose/design.md
    - specs/data/fingerprick-glucose/decision_log.md
    - specs/data/fingerprick-glucose/prerequisites.md
---
# fingerprick Glucose — Implementation Tasks

## Shared contract and precedence (MedataCore)

- [ ] 1. Add GlucoseProvenance and carry it on GlucoseReading and GlucoseSnapshot <!-- id:3sphmgc -->
  - public enum GlucoseProvenance: String, Codable, Sendable { case sensor, blood } in GlucoseWidgetShared — Foundation-only, no new dependency edge.
  - GlucoseReading.provenance defaulted .sensor in the initialiser so every existing construction site compiles unchanged: GlucoseSnapshotSource.current, App/TrendsModel.swift, App/RecordsModel.swift, MeData/MeDataWidgets/GlucoseWidget.swift.
  - GlucoseSnapshot to schemaVersion 2 with provenance: GlucoseProvenance? and holdsUntil: Date?, both carried through make(...). A v1 blob already reads as .neverRecorded on the version check, so there is no migration and no backfill.
  - Types and interfaces only — no preceding test.
  - Stream: 1
  - Requirements: [2.5](requirements.md#2.5), [3.5](requirements.md#3.5), [7.1](requirements.md#7.1)
  - References: MedataCore/Sources/GlucoseWidgetShared/GlucoseDerivation.swift, MedataCore/Sources/GlucoseWidgetShared/GlucoseSnapshot.swift

- [ ] 2. Write GlucoseDerivation precedence and trend-exclusion tests (Red) <!-- id:3sphmgd -->
  - Blood inside the window is displayed over a strictly newer sensor reading; blood outside it is not; the later of two in-window blood readings wins; a reading back-dated beyond the window never displays — assert it falls out of the same comparison rather than a separate branch.
  - holdsUntil equals the blood instant + holdWindow while a blood reading is displayed and is nil otherwise; provenance names the displayed reading.
  - Trend: a blood reading offset from a flat sensor trace leaves the rate unchanged; the sensor-only count and span rules are unchanged; blood-only input yields no trend at all.
  - Empty input stays .neverRecorded and sensor-only input is identical to today's behaviour.
  - Blocked-by: 3sphmgc (Add GlucoseProvenance and carry it on GlucoseReading and GlucoseSnapshot)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.9](requirements.md#3.9), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)
  - References: MedataCore/Tests/GlucoseWidgetSharedTests/

- [ ] 3. Implement precedence and the sensor-only trend in GlucoseDerivation (Green) <!-- id:3sphmge -->
  - snapshot(from:now:holdWindow:) — the latest blood reading whose timestamp is within holdWindow of now, else the latest reading of any provenance; status is the band of whichever was displayed.
  - Trend runs over readings.filter { $0.provenance == .sensor } — filtered before the regression, not after, so a modality offset can never be reported as a rate.
  - No default for holdWindow: the widget extension passes 0 because it holds no blood readings, the app passes the setting. GlucoseSnapshotSource.snapshot keeps forwarding for app-side callers.
  - Blocked-by: 3sphmgd (Write GlucoseDerivation precedence and trend-exclusion tests Red)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.9](requirements.md#3.9), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)
  - References: MedataCore/Sources/GlucoseWidgetShared/GlucoseDerivation.swift

- [ ] 4. Write GlucoseSnapshotStore.merged and replacingDeleted write tests (Red) <!-- id:3sphmgf -->
  - Case 1: a sensor candidate while stored.holdsUntil > now keeps stored's value, readingDate and provenance and adopts only the candidate's trend.
  - Case 2: a candidate carrying the same readingDate and provenance is admitted only when its trend differs — without it the arrow freezes for the whole window, foreground included.
  - Case 3: the Decision 19 rule unchanged, including a candidate carrying no reading always writing.
  - The invariant across an arbitrary write sequence: the displayed readingDate never decreases except through a deletion write.
  - write(_:replacingDeleted:): a rollback to an older reading is admitted when stored.readingDate is among the removed instants, and refused when it is not — the refusal is what protects a newer extension fetch the app never saw.
  - Blocked-by: 3sphmgc (Add GlucoseProvenance and carry it on GlucoseReading and GlucoseSnapshot)
  - Stream: 1
  - Requirements: [3.7](requirements.md#3.7), [3.8](requirements.md#3.8), [6.2](requirements.md#6.2)
  - References: MedataCore/Tests/GlucoseWidgetSharedTests/

- [ ] 5. Implement merged and the deletion-authorised write (Green) <!-- id:3sphmgg -->
  - Replaces supersedesStored; write(_:replacingDeleted:to:) defaults the array to empty so existing callers are unchanged.
  - Policy stays inside the store rather than in either writer, per glucose-lock-widget Decision 19 — any future writer inherits the rule by construction.
  - Blocked-by: 3sphmgf (Write GlucoseSnapshotStore.merged and replacingDeleted write tests Red)
  - Stream: 1
  - Requirements: [3.7](requirements.md#3.7), [3.8](requirements.md#3.8), [6.2](requirements.md#6.2)
  - References: MedataCore/Sources/GlucoseWidgetShared/GlucoseSnapshot.swift

## Storage and ingestion (MedataCore)

- [ ] 6. Write recordBloodBsl store tests (Red) <!-- id:3sphmgh -->
  - A 13:02:37 instant stores as 13:02:37 — not snapped to a 5-minute mark.
  - Metadata carries provenance blood and source_id, and native_id only when non-nil: key absent, never null, mirroring liveBslMetadataJSON.
  - Re-delivering the same (source_id, native_id) writes no second row and emits no eventsDidChange; two hand entries at the same instant with no native id both persist.
  - A blood row at the instant of an existing sensor row leaves that row present and separately retrievable by id, and the path issues no UPDATE and no DELETE.
  - An out-of-range value is rejected at the store the way saveInsulinDose rejects units, so a deep-linked or future caller cannot bypass the pad's bound.
  - Blocked-by: 3sphmgc (Add GlucoseProvenance and carry it on GlucoseReading and GlucoseSnapshot)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [4.1](requirements.md#4.1), [4.4](requirements.md#4.4)
  - References: MedataCore/Tests/PersistenceTests/LiveBslIngestTests.swift

- [ ] 7. Implement BloodBslReading and recordBloodBsl (Green) <!-- id:3sphmgi -->
  - BloodBslReading (instant, mmolL, sourceID, nativeID?) on PersistenceStore; the GRDB implementation is one INSERT in one transaction returning the new UUID, matching saveInsulinDose's shape.
  - Dedup is a json_extract(metadata, '$.native_id') lookup gated on source_id — a scan over the candidate range rather than an indexed key lookup (Decision 10).
  - changeBroadcaster.notify() exactly once, and only when a row was actually written.
  - Blocked-by: 3sphmgh (Write recordBloodBsl store tests Red)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [4.1](requirements.md#4.1), [4.4](requirements.md#4.4)
  - References: MedataCore/Sources/Persistence/PersistenceStore.swift, MedataCore/Sources/Persistence/GRDBPersistenceStore.swift

- [ ] 8. Write IngestionCoordinator provenance-routing tests (Red) <!-- id:3sphmgj -->
  - A mixed batch splits: sensor samples reach ingestLiveBsl grid-snapped with the keep-first bucket collapse intact, blood samples reach recordBloodBsl at exact instants and never enter the bucketing.
  - A blood-only batch performs no grid work; the returned BslIngestSummary accounts for both halves; lastReadingMs and the .connected transition still advance.
  - A batch with provenance unset behaves exactly as today — the structural half of Req 7.2.
  - Blocked-by: 3sphmgi (Implement BloodBslReading and recordBloodBsl Green)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [7.2](requirements.md#7.2)
  - References: MedataCore/Tests/GlucoseIngestionTests/IngestionCoordinatorTests.swift

- [ ] 9. Implement GlucoseSample.provenance and the coordinator partition (Green) <!-- id:3sphmgk -->
  - GlucoseSample.provenance defaulted .sensor so LibreLinkUp, screenshot import and the heartbeat source are untouched; the coordinator partitions and routes, sources stay unaware of the split.
  - Durable-ack ordering unchanged: a throw from either path propagates so the source does not advance its cursor.
  - Blocked-by: 3sphmgj (Write IngestionCoordinator provenance-routing tests Red)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.3](requirements.md#1.3), [7.2](requirements.md#7.2)
  - References: MedataCore/Sources/GlucoseIngestion/GlucoseSource.swift, MedataCore/Sources/GlucoseIngestion/IngestionCoordinator.swift

- [ ] 10. Write HealthKit writer-registry tests (Red) <!-- id:3sphmgl -->
  - An unclassified bundle id yields .sensor — the fail-safe direction, since mistaking a sensor for blood grants it a hold it has not earned.
  - A bundle id classified blood yields .blood; observing a writer records bundle id, display name and HKDevice name/manufacturer when present; re-observing neither duplicates the entry nor overwrites an existing classification.
  - The registry reads and writes an injected UserDefaults defaulting to .standard, so it is testable from a suite-backed instance while HealthKitGlucoseSource stays device-only. This refines design.md, which names UserDefaults.standard directly.
  - Blocked-by: 3sphmgc (Add GlucoseProvenance and carry it on GlucoseReading and GlucoseSnapshot)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.5](requirements.md#1.5)
  - References: MedataCore/Tests/GlucoseIngestionTests/

- [ ] 11. Implement the writer registry and classify HealthKit samples (Green) <!-- id:3sphmgm -->
  - Writers live under glucose.healthkit.writers in UserDefaults.standard; HealthKitGlucoseSource.glucoseSample records the observed writer and maps sample.sourceRevision.source.bundleIdentifier through the registry to provenance. nativeID stays sample.uuid.uuidString.
  - Keys on the bundle identifier, not HKDevice, which any writer may leave nil.
  - No Contour bundle id is hard-coded: the literal is read off a real sample on device (prerequisites.md) and set through Settings in task 23.
  - Blocked-by: 3sphmgl (Write HealthKit writer-registry tests Red), 3sphmgk (Implement GlucoseSample.provenance and the coordinator partition Green)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.5](requirements.md#1.5)
  - References: MedataCore/Sources/GlucoseIngestion/HealthKitGlucoseSource.swift

## App and widget surfaces

- [ ] 12. Write GlucoseSnapshotSource provenance-decode and hold-window tests (Red) <!-- id:3sphmgn -->
  - A row written by recordBloodBsl surfaces as .blood; a row written by ingestLiveBsl, which carries no provenance key, surfaces as .sensor — Req 7.1 satisfied by absence, with nothing rewritten. An unrecognised provenance string also falls back to .sensor.
  - End to end over a real store: a blood row inside the window is the snapshot's displayed reading while a newer sensor row exists, and stops being it once the window elapses.
  - Blocked-by: 3sphmge (Implement precedence and the sensor-only trend in GlucoseDerivation Green), 3sphmgi (Implement BloodBslReading and recordBloodBsl Green)
  - Stream: 1
  - Requirements: [3.7](requirements.md#3.7), [7.1](requirements.md#7.1)
  - References: MedataCore/Tests/PersistenceTests/

- [ ] 13. Implement the provenance decode, hold-window setting, and app-side pass-through (Green) <!-- id:3sphmgo -->
  - SettingsKeys.glucoseHoldWindowSeconds (medata.glucose.holdWindowSeconds), default 900 — app-private, deliberately NOT App Group state (Decision 8).
  - GlucoseSnapshotSource.current(store:now:holdWindow:) decodes metadata.provenance onto each GlucoseReading and forwards the window.
  - HomeGlucoseModel and GlucoseWidgetPublisher both read the setting and pass it, so home and the published snapshot resolve the same reading (Req 3.7).
  - Blocked-by: 3sphmgn (Write GlucoseSnapshotSource provenance-decode and hold-window tests Red)
  - Stream: 1
  - Requirements: [3.2](requirements.md#3.2), [3.7](requirements.md#3.7), [7.1](requirements.md#7.1)
  - References: MedataCore/Sources/Persistence/GlucoseSnapshotSource.swift, App/SettingsKeys.swift, App/HomeGlucoseModel.swift, App/GlucoseWidgetPublisher.swift

- [ ] 14. Write GlucoseTimeline provenance-render and staleness tests (Red) <!-- id:3sphmgp -->
  - A blood-provenance snapshot renders naming blood; a sensor one renders exactly as today.
  - The ladder still measures age from readingDate, so a blood reading held for the full default window reaches the 15-minute boundary exactly — holdsUntil must not shift the ladder.
  - Blocked-by: 3sphmgc (Add GlucoseProvenance and carry it on GlucoseReading and GlucoseSnapshot)
  - Stream: 1
  - Requirements: [3.5](requirements.md#3.5), [3.6](requirements.md#3.6)
  - References: MedataCore/Tests/GlucoseWidgetSharedTests/

- [ ] 15. Name provenance on the lock-screen widget and keep its own fetch sensor-labelled (Green) <!-- id:3sphmgq -->
  - GlucoseRender / GlucoseTimeline.render carry provenance through to the view, and GlucoseWidget.swift names it beside the value.
  - The extension's own vendor fetch builds GlucoseReading with the literal .sensor and passes holdWindow 0; its write now goes through merged, so a sensor fetch landing during a hold contributes trend only.
  - Design gap: design.md's Surfaces table has no row for the lock-screen widget's render although Req 3.5 covers it — add one when this lands.
  - Blocked-by: 3sphmgp (Write GlucoseTimeline provenance-render and staleness tests Red), 3sphmgg (Implement merged and the deletion-authorised write Green)
  - Stream: 1
  - Requirements: [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7), [3.8](requirements.md#3.8)
  - References: MedataCore/Sources/GlucoseWidgetShared/GlucoseTimeline.swift, MeData/MeDataWidgets/GlucoseWidget.swift

- [ ] 16. Build the glucose entry sheet and its model <!-- id:3sphmgr -->
  - New App/GlucoseEntryModel.swift and App/GlucoseEntrySheet.swift, both needing the four-place project.pbxproj registration (docs/agent-notes/ui-capture-flow.md).
  - Autofocused numeric pad with implicit tenths: digits shift in from the right and the value is formatted live so the decimal point is visible rather than remembered. Every value in 1.0-30.0 takes at most three digits plus Save.
  - Back-dating reuses the compact DatePicker(selection:in:...Date()) row from App/InsulinDoseSheet.swift and is not on the path to Save.
  - Save calls recordBloodBsl with source id manual and no native id, then dismisses. Hand entries never deduplicate, so a double tap is two rows (Decision 10).
  - No preceding test: app-target UI, whose gate is build plus device inspection (CLAUDE.md). MeData/Tests is a documentation contract, not an executable suite.
  - Blocked-by: 3sphmgi (Implement BloodBslReading and recordBloodBsl Green)
  - Stream: 2
  - Requirements: [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6)
  - References: App/GlucoseEntrySheet.swift, App/GlucoseEntryModel.swift, App/InsulinDoseSheet.swift, MeData/MeData.xcodeproj/project.pbxproj

- [ ] 17. Make the home latest-reading display raise the sheet and name provenance <!-- id:3sphmgs -->
  - The reading becomes a Button presenting the entry sheet — supersedes home-router Decision 15's read-only framing. No new route row, and the tap target carries no label.
  - Renders snapshot.provenance beside the value.
  - App/UI: no preceding test, same gate as task 16.
  - Blocked-by: 3sphmgr (Build the glucose entry sheet and its model), 3sphmgo (Implement the provenance decode, hold-window setting, and app-side pass-through Green)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [3.5](requirements.md#3.5), [3.7](requirements.md#3.7)
  - References: App/HomeView.swift, App/HomeGlucoseModel.swift

- [ ] 18. Add the medata://glucose/add deep link <!-- id:3sphmgt -->
  - A .glucoseSheet case joins DeepLinkTarget and handleDeepLink's (glucose, /add) match, reusing the pendingDeepLink dismiss-and-resume sequencing the insulin sheet already uses so it works from any app state, including with another sheet or full-screen cover up.
  - Wiring only — no preceding test.
  - Blocked-by: 3sphmgr (Build the glucose entry sheet and its model)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1)
  - References: App/AppRoot.swift

- [ ] 19. Add the glucose launcher widget <!-- id:3sphmgu -->
  - A fourth Widget mirroring InsulinDoseWidget: LauncherProvider, LauncherView, widgetURL medata://glucose/add, kind ie.medata.widget.glucose.add — distinct from the data-driven ie.medata.widget.glucose — and the same supportedFamilies. Add it to MeDataWidgetBundle.
  - Wiring only — no preceding test.
  - Blocked-by: 3sphmgt (Add the medata://glucose/add deep link)
  - Stream: 2
  - Requirements: [2.2](requirements.md#2.2)
  - References: MeData/MeDataWidgets/MeDataWidgets.swift

- [ ] 20. Draw blood readings as a distinct marker series on the Graph <!-- id:3sphmgv -->
  - TrendsModel.reload decodes provenance when building the glucose series; TrendsView keeps the existing LineMark over sensor readings alone, so the trace is drawn unbroken across a blood instant, and adds blood readings as a separate PointMark series.
  - App/UI: no preceding test.
  - Blocked-by: 3sphmgi (Implement BloodBslReading and recordBloodBsl Green)
  - Stream: 1
  - Requirements: [4.2](requirements.md#4.2)
  - References: App/TrendsModel.swift, App/TrendsView.swift

- [ ] 21. Label provenance on the Records glucose row <!-- id:3sphmgw -->
  - loadGlucose carries provenance onto GlucoseRow, keeping Event.id (records-deletion Decision 13); the row labels it.
  - Ordering, the swipe gesture and the bulk actions are untouched — Req 6.1 needs no change.
  - App/UI: no preceding test.
  - Blocked-by: 3sphmgi (Implement BloodBslReading and recordBloodBsl Green)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3), [6.1](requirements.md#6.1)
  - References: App/RecordsModel.swift, App/RecordsView.swift

- [ ] 22. Route deleted bsl instants to the snapshot write <!-- id:3sphmgx -->
  - RecordsModel.delete and deleteBulk collect the removed bsl timestamps — including the date-range and delete-all purges from specs/ui/records-deletion — and hand them to the publisher, which passes them as replacingDeleted:. Deletions of other event types pass nothing and behave as today.
  - Needs a route from RecordsModel, constructed in RecordsView, to the publisher owned by App.swift; pick one seam and use it for all three deletion paths.
  - App wiring over a store policy already covered by task 4's tests.
  - Blocked-by: 3sphmgg (Implement merged and the deletion-authorised write Green)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)
  - References: App/RecordsModel.swift, App/GlucoseWidgetPublisher.swift, App/App.swift, App/RecordsView.swift

- [ ] 23. Add the Apple Health writer-classification list and the hold-window control to Settings <!-- id:3sphmgy -->
  - GlucoseConnectionsView gains an Apple Health writers section listing every observed writer — bundle id, display name, and device name/manufacturer when known — each with a blood/sensor picker, taking effect on subsequently arriving samples only.
  - SettingsView gains the hold-window control bound to SettingsKeys.glucoseHoldWindowSeconds; above 15 minutes a held reading can render as stale (Decision 3), which the control should make evident without disclaimer copy.
  - This surface is what makes the Contour classification settable without a rebuild.
  - App/UI: no preceding test.
  - Blocked-by: 3sphmgm (Implement the writer registry and classify HealthKit samples Green), 3sphmgo (Implement the provenance decode, hold-window setting, and app-side pass-through Green)
  - Stream: 1
  - Requirements: [1.5](requirements.md#1.5), [3.2](requirements.md#3.2)
  - References: App/GlucoseConnectionsView.swift, App/GlucoseConnectionsModel.swift, App/SettingsView.swift

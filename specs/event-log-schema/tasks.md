---
references:
    - specs/event-log-schema/requirements.md
    - specs/event-log-schema/design.md
    - specs/event-log-schema/decision_log.md
---
# Tasks: Event Log Schema

- [x] 1. Update PersistenceStore protocol surface and consumers <!-- id:z0ukrwj -->
  - Add EventType namespace with constant `meal = "meal"` in MedataCore/Sources/Persistence/PersistenceStore.swift.
  - Add Event struct (id, timestamp, eventType, value, metadata).
  - Add events(in:type:) and corrections(for:) protocol methods.
  - Rename mealsDidChange to eventsDidChange.
  - Update App/MealHistoryModel.swift — one-line rename to subscribe to eventsDidChange.
  - Update test stub PersistenceStore conformers in PipelineTests/EstimationFailureTests, PersistenceTests/RetentionSchedulerTests, HarnessCLITests/PipelinePerformanceTests, MeData/Tests/MealHistoryModelTests — add stubs for the two new methods (fatalError("unused") where the test does not exercise them) and rename the stream.
  - No GRDB implementation yet — follows in later tasks.
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5)

- [x] 2. Write tests for MealRecord.metadataJSON() / from(metadata:) <!-- id:z0ukrwk -->
  - New file MedataCore/Tests/PersistenceTests/MealRecordMetadataTests.swift.
  - Round-trip via metadataJSON() then from(metadata:) preserves every MealRecord field.
  - Inner `record` JSON string extracted from metadataJSON() output is byte-identical to original.pb.jsonString().
  - Malformed outer JSON throws PersistenceError.corruptRecord.
  - Missing `record` or `palette_version` key throws corruptRecord.
  - Blocked-by: z0ukrwj (Update PersistenceStore protocol surface and consumers)
  - Stream: 1
  - Requirements: [3.2](requirements.md#3.2)

- [x] 3. Implement MealRecord.metadataJSON() / from(metadata:) <!-- id:z0ukrwl -->
  - Add to MedataCore/Sources/Persistence/MealRecord.swift.
  - metadataJSON(): builds ["record": pb.jsonString(), "palette_version": paletteVersion] and encodes via JSONSerialization with no options.
  - from(metadata:): parses outer JSON, extracts the two keys, calls the existing MealRecord.from(jsonString:paletteVersion:segmenterSource:photoAssetID:) decoder.
  - Blocked-by: z0ukrwk (Write tests for MealRecord.metadataJSON() / from(metadata:))
  - Stream: 1
  - Requirements: [3.2](requirements.md#3.2)

- [x] 4. Write tests for events schema, save round-trip, and allMeals ordering <!-- id:z0ukrwm -->
  - Rewrite MedataCore/Tests/PersistenceTests/PersistenceTests.swift against the new schema.
  - PRAGMA shows `events` table with id/timestamp/event_type/value/metadata columns plus events_timestamp index.
  - `meals` and `meal_classes` are NOT in sqlite_master.
  - meta.schema_version is "3".
  - save then reload via meal(id:) round-trips all fields.
  - value and timestamp columns equal totalCarbsG and createdAt-ms.
  - allMeals returns rows in (timestamp DESC, id ASC) order.
  - Blocked-by: z0ukrwl (Implement MealRecord.metadataJSON() / from(metadata:))
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1)

- [x] 5. Rewrite createSchema, save, and allMeals against events table <!-- id:z0ukrwn -->
  - MedataCore/Sources/Persistence/GRDBPersistenceStore.swift.
  - createSchema creates only events, meal_artefacts, corrections, meta. No meals or meal_classes.
  - schema_version bumps to "3".
  - save() inserts one row into events (id, timestamp, event_type, value, metadata) with event_type=EventType.meal, value=totalCarbsG, metadata=record.metadataJSON().
  - meal_classes write is removed.
  - allMeals selects FROM events WHERE event_type=? ORDER BY timestamp DESC, id ASC, decoding each row via MealRecord.from(metadata:).
  - No unit conversion anywhere (Req 2.3).
  - Blocked-by: z0ukrwm (Write tests for events schema, save round-trip, and allMeals ordering)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [4.1](requirements.md#4.1)

- [x] 6. Write tests for meal(id:) event_type filter and wrong-type mealNotFound <!-- id:z0ukrwo -->
  - Extend PersistenceTests.swift.
  - Hand-insert a synthetic row with event_type="other" via raw SQL.
  - Assert meal(id:) throws PersistenceError.mealNotFound for it.
  - Existing meal-not-found test for missing ids continues to pass.
  - Blocked-by: z0ukrwn (Rewrite createSchema, save, and allMeals against events table)
  - Stream: 1
  - Requirements: [4.2](requirements.md#4.2)

- [x] 7. Rewrite meal(id:) against events table <!-- id:z0ukrwp -->
  - GRDBPersistenceStore.meal(id:): SELECT value, metadata FROM events WHERE id=? AND event_type=?, parameterized with EventType.meal.
  - Decode via MealRecord.from(metadata:).
  - Missing row or wrong-type row both throw PersistenceError.mealNotFound.
  - Blocked-by: z0ukrwo (Write tests for meal(id:) event_type filter and wrong-type mealNotFound)
  - Stream: 1
  - Requirements: [4.2](requirements.md#4.2)

- [x] 8. Write tests for deleteMeal cascade, wrong-type no-op, and deleteArtefacts path-from-id <!-- id:z0ukrwq -->
  - Save a meal with associated meal_artefacts and corrections rows and a meals/{id} directory; assert deleteMeal removes all three plus the directory.
  - Hand-insert a non-meal event row with the same UUID; assert deleteMeal leaves it in place (no rows deleted with wrong event_type).
  - deleteArtefacts(olderThan:) selects events filtered by event_type=meal and timestamp<cutoff and removes meals/{id} for each — no artefacts_dir column read.
  - Blocked-by: z0ukrwn (Rewrite createSchema, save, and allMeals against events table)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3)

- [x] 9. Rewrite deleteMeal and deleteArtefacts(olderThan:) <!-- id:z0ukrwr -->
  - GRDBPersistenceStore.deleteMeal: DELETE FROM events WHERE id=? AND event_type=?; DELETE FROM meal_artefacts WHERE meal_id=?; DELETE FROM corrections WHERE meal_id=?; remove meals/{id} directory (best-effort, swallow filesystem errors).
  - Notify eventsDidChange.
  - deleteArtefacts(olderThan:): SELECT id FROM events WHERE event_type=? AND timestamp<? and remove meals/{id} for each.
  - Blocked-by: z0ukrwp (Rewrite meal(id:) against events table), against, against, against, against, against, against, against, against, against, against, against, against, against, against, against, against, z0ukrwq (Write tests for deleteMeal cascade, wrong-type no-op, and deleteArtefacts path-from-id)
  - Stream: 1
  - Requirements: [4.3](requirements.md#4.3)

- [x] 10. Write tests for updatePhotoAssetID byte-identity and eventsDidChange tick <!-- id:z0ukrws -->
  - Save a meal; capture metadata bytes via raw SELECT; call updatePhotoAssetID with a new id; capture metadata bytes again; extract the inner record string from both.
  - Decode both record strings via PbMealRecord; assert ONLY photoAssetID differs; every other PbMealRecord field is equal.
  - Subsequent meal(id:) returns the new photoAssetID.
  - A subscriber to eventsDidChange receives a tick after updatePhotoAssetID — behavior change vs today (silent).
  - Blocked-by: z0ukrwn (Rewrite createSchema, save, and allMeals against events table)
  - Stream: 1
  - Requirements: [4.5](requirements.md#4.5)

- [x] 11. Rewrite updatePhotoAssetID and add broadcaster notify <!-- id:z0ukrwt -->
  - GRDBPersistenceStore.updatePhotoAssetID: SELECT metadata FROM events WHERE id=? AND event_type=?; parse outer JSON; decode the inner record string via PbMealRecord(jsonString:).
  - Set pb.photoAssetID = new value; re-emit pb.jsonString() and the outer metadata JSON.
  - UPDATE events SET metadata=? WHERE id=?; notify eventsDidChange.
  - Wrong-type id throws PersistenceError.mealNotFound.
  - Blocked-by: z0ukrwr (Rewrite deleteMeal and deleteArtefacts(olderThan:)), z0ukrws (Write tests for updatePhotoAssetID byte-identity and eventsDidChange tick)
  - Stream: 1
  - Requirements: [4.5](requirements.md#4.5)

- [x] 12. Write tests for events(in:type:) bounds, sort, type filter, and fail-fast on corrupt metadata <!-- id:z0ukrwu -->
  - Save three events at times t-1h, t, t+1h; events(in: (t-1h)...(t+1h), type: nil) returns all three in (timestamp ASC, id ASC) order — both endpoints inclusive.
  - events(in: (t-30m)...(t+30m), type: nil) returns only the middle one.
  - Hand-insert a synthetic non-meal event via raw SQL; events(in:..., type: "meal") excludes it; events(in:..., type: nil) includes it.
  - Hand-insert a row with malformed metadata JSON; events(in:..., type: nil) throws PersistenceError.corruptRecord (fail-fast, not skip).
  - Blocked-by: z0ukrwn (Rewrite createSchema, save, and allMeals against events table)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4), [1.5](requirements.md#1.5)

- [x] 13. Implement events(in:type:) <!-- id:z0ukrwv -->
  - GRDBPersistenceStore.events(in:type:): SELECT id, timestamp, event_type, value, metadata FROM events WHERE timestamp BETWEEN ? AND ? AND (?=NULL OR event_type=?) ORDER BY timestamp ASC, id ASC.
  - The type predicate switches on a sentinel when type==nil.
  - Map each row to Event.
  - UUID parse failure or row decode failure throws corruptRecord and aborts the call.
  - Blocked-by: z0ukrwt (Rewrite updatePhotoAssetID and add broadcaster notify), z0ukrwu (Write tests for events(in:type:) bounds, sort, type filter, and fail-fast on corrupt metadata), corrupt, corrupt, corrupt, corrupt, corrupt, corrupt, corrupt, corrupt, corrupt, corrupt, corrupt, corrupt, corrupt, corrupt, corrupt, corrupt
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5)

- [x] 14. Write tests for corrections(for:) ordering and appendCorrection no-notify <!-- id:z0ukrww -->
  - Save a meal and append two corrections at distinct createdAtMs; corrections(for: meal.id) returns both PbUserCorrection values in ascending created_at order.
  - After the appends, meal(id:).macros.totalCarbsG and the events.value column both equal the original uncorrected estimate (Req 4.4).
  - Subscriber to eventsDidChange receives NO tick after appendCorrection — distinguishes the side table from the event log.
  - Blocked-by: z0ukrwn (Rewrite createSchema, save, and allMeals against events table)
  - Stream: 1
  - Requirements: [4.4](requirements.md#4.4), [4.5](requirements.md#4.5)

- [x] 15. Implement corrections(for:) <!-- id:z0ukrwx -->
  - GRDBPersistenceStore.corrections(for:): SELECT correction_json FROM corrections WHERE meal_id=? ORDER BY created_at ASC.
  - Decode each blob via PbUserCorrection(jsonString:).
  - Empty array when none.
  - The existing PK (meal_id, created_at) covers this query — no new index.
  - Blocked-by: z0ukrwv (Implement events(in:type:)), z0ukrww (Write tests for corrections(for:) ordering and appendCorrection no-notify)
  - Stream: 1
  - Requirements: [4.4](requirements.md#4.4)

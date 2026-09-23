# Design: Event Log Schema

References: [requirements.md](requirements.md), [decision_log.md](decision_log.md).

## Overview

Replace the meal-centric SQLite schema (`meals` + `meal_classes`) with a single `events` table where each row is one discrete physiological/behavioural event. Meal rows become `event_type = "meal"` events with `value = total_carbs_g` and the verbatim `MealRecord` JSON in `metadata`. `meal_artefacts` and `corrections` remain unchanged as side tables linked by event id.

## Architecture

### Schema diff

Removed: `meals`, `meal_classes` (Decision 2).
Added: `events`.
Unchanged: `meal_artefacts`, `corrections`, `meta`.

There is no production data (Decision 5). The legacy tables are simply not created by the new code. A pre-existing dev `meals.sqlite` that still contains them is left untouched — `createSchema` only adds `events` and the legacy tables become orphan storage. Developers wipe simulator/device storage to reclaim the space; no destructive DDL runs on the production path. `exportArchive` copies the whole SQLite file, so an export taken from such a dev DB will include the stale legacy rows — acceptable in pre-release. Schema version bumps `"2"` → `"3"`.

### Integration points

All persistence changes are confined to `MedataCore/Sources/Persistence/`:

- `GRDBPersistenceStore.swift` — `createSchema`, `save`, `meal(id:)`, `allMeals`, `deleteMeal`, `updatePhotoAssetID`, `deleteArtefacts(olderThan:)` rewritten against `events`.
- `PersistenceStore.swift` — additive: `events(in:type:)`, `corrections(for:)`. Rename: `mealsDidChange` → `eventsDidChange`. New `EventType` namespace.
- `MealRecord.swift` — metadata-shape encode/decode helpers (`metadataJSON()` / `from(metadata:)`).

UI consumer:

- `App/MealHistoryModel.swift` — one-line update: `store.mealsDidChange` → `store.eventsDidChange`.

### Pattern extension audit

Every call site that depends on the meal-table shape:

| Call site | Operation today | Change |
|---|---|---|
| `GRDBPersistenceStore.save` | INSERT into `meals` + `meal_classes` | INSERT into `events` only. `meal_classes` no longer written. |
| `GRDBPersistenceStore.meal(id:)` | SELECT from `meals` | SELECT `value, metadata` FROM `events` WHERE id=? AND event_type='meal'. Wrong-type id treated as `mealNotFound`. |
| `GRDBPersistenceStore.allMeals` | SELECT FROM `meals` ORDER BY created_at DESC | SELECT FROM `events` WHERE event_type='meal' ORDER BY timestamp DESC, id ASC. |
| `GRDBPersistenceStore.deleteMeal` | DELETEs across `meals`, `meal_classes`, `meal_artefacts`, `corrections` | DELETEs across `events` (filtered to `event_type='meal'`), `meal_artefacts`, `corrections`. Manual cascade in code — there is no SQL FK or `ON DELETE CASCADE`. |
| `GRDBPersistenceStore.updatePhotoAssetID` | Updates `photo_asset_id` column AND `record_json` BLOB | Reads `metadata`, decodes inner `PbMealRecord`, mutates `photoAssetID`, re-emits `metadata`. See "byte-identity" below. Now also calls `eventsDidChange.notify()` (behavior change — flagged in tests). |
| `GRDBPersistenceStore.deleteArtefacts(olderThan:)` | SELECT `artefacts_dir` FROM `meals` WHERE created_at<? | SELECT `id` FROM `events` WHERE event_type='meal' AND timestamp<?; path is `meals/{id}`. |
| `GRDBPersistenceStore.exportArchive` | Copies SQLite + `meals/` directory | No change. Schema-agnostic. |
| `GRDBPersistenceStore.appendCorrection` | INSERT into `corrections` | No change. Today's semantics preserved: caller is trusted; no validation that the `meal_id` references an existing meal event. |
| `GRDBPersistenceStore.sweepIfDue` | Delegates to `deleteArtefacts(olderThan:)` | No change. |
| `RetentionScheduler` | Calls `deleteArtefacts(olderThan:)` | No change. |
| `PaletteMigrator` | Operates on in-memory `MealRecord`; the re-derived record passes through `save()` | No change. `paletteVersion` is on `MealRecord` as a Swift field; `metadataJSON()` writes it to `metadata.palette_version`. |
| `MealHistoryModel` | Subscribes to `store.mealsDidChange` | One-line rename to `eventsDidChange`. |
| Test stub `PersistenceStore` conformers — `RetentionSchedulerTests`, `EstimationFailureTests` (Pipeline), `PipelinePerformanceTests` (HarnessCLI), `MealHistoryModelTests` (MeData) | Implement the current protocol | Each updated for the rename + the two new methods. Stubs that don't exercise the new methods may `fatalError("unused")`. |
| Test files exercising SQL directly — `PersistenceTests.swift`, `MealHistoryStoreTests.swift` | Assert on `meals` / `meal_classes` rows | Rewritten to assert on `events`. |

## Components and Interfaces

### PersistenceStore protocol

```swift
public enum EventType {
    public static let meal = "meal"
}

public protocol PersistenceStore: Sendable {
    func save(_ record: MealRecord, artefacts: [MealArtefact]) async throws
    func appendCorrection(mealId: UUID, correction: PbUserCorrection) async throws
    func meal(id: UUID) async throws -> MealRecord
    func allMeals() async throws -> [MealRecord]
    func deleteMeal(id: UUID) async throws
    func updatePhotoAssetID(mealId: UUID, photoAssetID: String) async throws
    func deleteArtefacts(olderThan date: Date) async throws
    func exportArchive() async throws -> String
    func sweepIfDue() async throws

    // Req 1.4, 1.5. Closed interval; both bounds inclusive.
    func events(in range: ClosedRange<Date>, type: String?) async throws -> [Event]
    // Req 4.4. Empty array when none; meal event's `value` is unaffected.
    func corrections(for mealId: UUID) async throws -> [PbUserCorrection]

    // Req 4.5.
    var eventsDidChange: AsyncStream<Void> { get }
}
```

`events(in:type:)` returns rows whose `timestamp` falls within `[range.lowerBound, range.upperBound]` (both inclusive), ordered `(timestamp ASC, id ASC)`. Ascending order matches the chronological intent of Req 1.4. The deterministic secondary sort handles equal-timestamp ties. `type == nil` returns all event types; otherwise filters to `event_type = type`. A row whose `metadata` cannot be parsed throws `PersistenceError.corruptRecord` for the whole call (fail-fast, matching `meal(id:)` today). The `type` parameter is retained even though only `"meal"` is implementable in this phase — it is the API affordance that Req 1.3 promises and is exercised in tests with a hand-inserted non-meal row.

`corrections(for:)` returns `(SELECT … FROM corrections WHERE meal_id=? ORDER BY created_at ASC)`. The existing PK `(meal_id, created_at)` covers this query — no new index needed. The meal event's `value` is unchanged; overlay composition is the caller's job.

### Event

```swift
public struct Event: Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let eventType: String
    public let value: Double?
    public let metadata: String   // raw JSON; consumer decides how to decode
}
```

Generic surface. `value` is `Double?` so future event types without a canonical scalar can be added without schema change (Req 1.3). Meal events always populate `value`. No production consumer of `events(in:type:)` is wired up in this phase — the method exists to satisfy Req 1.4 / 1.5 and is exercised only by tests; the Meals tab continues to read via `allMeals()`.

### MealRecord ↔ event metadata

```swift
extension MealRecord {
    func metadataJSON() throws -> String
    static func from(metadata: String) throws -> MealRecord
}
```

**`metadataJSON()` contract.** Produces a JSON object literal with exactly two keys:

- `record` — a JSON string whose value is `self.pb.jsonString()` (i.e. the protobuf-JSON of `PbMealRecord`, byte-identical to `SwiftProtobuf` output).
- `palette_version` — a JSON string equal to `self.paletteVersion`.

Encoded via `JSONSerialization` with no options (no sorted keys, no pretty-printing). Outer-key order is not contractual; only the inner `record` string is held to byte-identical reproduction. `photoAssetID` and `segmenterSource` are inside `record` (they are `PbMealRecord` fields); the design does not duplicate them at the outer level.

**`from(metadata:)` contract.** Parses the outer JSON to `[String: Any]`, extracts the two keys, then calls `MealRecord.from(jsonString: record, paletteVersion: palette_version)`. The existing four-argument decoder is kept and called from this new entry point; old callers (none in production after this change) are removed. A missing or wrong-typed key throws `PersistenceError.corruptRecord`.

**`research D31` invariant.** (`research D31` = Decision 31 in `specs/estimation/pipeline/decision_log.md`, per the DECISIONS.md citation key.) The `record` string round-trips through `JSONSerialization` only as a JSON string value, not as a parsed-and-re-emitted object — string values are preserved character-for-character through any conforming JSON encoder. So the inner protobuf-JSON survives byte-identical, which is the `research D31` guarantee that any future Android consumer of the export archive relies on. The byte-identical test asserts on the `record` field after extraction, not on the whole metadata blob.

**`updatePhotoAssetID` byte-identity.** The method:

1. Reads the row's `metadata`.
2. Extracts the `record` string, decodes via `PbMealRecord(jsonString:)`.
3. Mutates only `photoAssetID`.
4. Re-emits via `pb.jsonString()` — byte-identical to what would have been produced for a fresh save with the new asset id.
5. Re-emits the outer metadata JSON with the new `record` string and the unchanged `palette_version`.
6. UPDATE `events SET metadata=? WHERE id=?`.
7. Notifies `eventsDidChange` — a behavior change vs today's silent update. This is intentional so the Meals tab refreshes when the photo binding is stamped, which is the only reasonable UX (the row otherwise refreshes only on save/delete).

Byte-identity of unchanged sibling fields inside `record` is preserved because the round-trip is through `PbMealRecord` which is the canonical encoder. No textual diff/patch is attempted on the JSON string.

### Change broadcaster

`ChangeBroadcaster` is unchanged in mechanics; the public stream is renamed `eventsDidChange` and fires after any successful event-row write or delete: `save`, `deleteMeal`, and (newly) `updatePhotoAssetID`. `appendCorrection` **does notify `eventsDidChange`** as of design-handoff-00 ([Decision 18](../../ui/design-handoff-00/decision_log.md#decision-18-appendcorrection-now-emits-eventsdidchange)) — the Data screen and Meal overview compose corrected totals and must refresh when a correction lands; without this notification they have no way to learn of the change. The original design (corrections live in their side table; Meals tab does not redraw on a correction) is superseded by this requirement.

## Data Models

### `events` table

```sql
CREATE TABLE IF NOT EXISTS events (
    id          TEXT    PRIMARY KEY,        -- UUID string
    timestamp   INTEGER NOT NULL,           -- absolute instant, ms since epoch UTC
    event_type  TEXT    NOT NULL,           -- EventType.meal in this phase
    value       REAL,                       -- canonical scalar; NULL allowed for future types
    metadata    TEXT    NOT NULL            -- JSON object
);
CREATE INDEX IF NOT EXISTS events_timestamp ON events(timestamp);
```

**Column type notes.** `metadata` is `TEXT` (not `BLOB` as the legacy `record_json` was). SQLite treats them identically for storage and JSON-function purposes, but `TEXT` signals "this is human-readable JSON" to anyone reading the schema. No tooling depends on the type-affinity difference.

**Index choice.** `events_timestamp` exists because range queries (`events(in:type:)`) are the dominant new access pattern after `allMeals()`. Cost is one B-tree per row; at the projected scale (Decision 1: hundreds to low tens of thousands of rows) this is trivial. No index on `event_type` — only one value exists in this phase, and a covering composite `(event_type, timestamp)` is the right answer when a second type lands.

**Invariants.**

- `id` is the meal's UUID for meal events (Req 3.3) — the same value used by `meal_artefacts.meal_id` and `corrections.meal_id`.
- `timestamp` is UTC milliseconds since epoch.
- `value` for `event_type=EventType.meal` equals the uncorrected `total_carbs_g` (Req 3.1, 4.4). For meal events, `value` is informational — the inner `record` inside `metadata` is the source of truth for `total_carbs_g`. They are written together from the same in-memory `MealRecord`; a mismatch would only arise from external tampering and is not detected (Decision 1: no validation in this phase).

### `metadata` shape for `event_type=EventType.meal`

```json
{
  "record": "<protobuf-JSON of PbMealRecord, byte-identical to SwiftProtobuf output>",
  "palette_version": "v1"
}
```

Round-trip acceptance: reconstructing `MealRecord` from `(value, metadata)` produces a value equal to the original (Decision 6, Req 3.2).

### Side tables (unchanged)

`meal_artefacts` and `corrections` keep their current schema. Their `meal_id` is a foreign-key-by-convention to `events.id` for rows where `event_type=EventType.meal`. There is no SQL FK constraint and no SQL `ON DELETE CASCADE` — `deleteMeal` issues the cascade DELETEs in code, as today.

## Testing Strategy

Tests live in `MedataCore/Tests/PersistenceTests/`. The existing `PersistenceTests.swift` and `MealHistoryStoreTests.swift` are rewritten against the new schema. Stub `PersistenceStore` conformers in `RetentionSchedulerTests`, `EstimationFailureTests` (Pipeline), `PipelinePerformanceTests` (HarnessCLI), and `MealHistoryModelTests` (MeData) gain the two new methods and the renamed stream (`fatalError("unused")` for methods the test does not exercise).

| Behavior | Test |
|---|---|
| `events` table created on first launch; `meals` / `meal_classes` not created | `PRAGMA` check. |
| Save → reload by id round-trips a `MealRecord` losslessly | Compare every public field; assert inner `record` string equals the original `record.jsonString()` byte-for-byte. |
| Save populates `value` with `total_carbs_g` and `timestamp` with createdAt-ms | Direct `SELECT value, timestamp FROM events`. |
| `events(in:type:)` is inclusive on both bounds, sorted `(timestamp ASC, id ASC)` | Save three meals at t-1h / t / t+1h; query `[t-1h, t+1h]` returns three in order; query `[t-30m, t+30m]` returns one. |
| `events(in:type:)` filters by `event_type` when non-nil | Hand-insert a synthetic non-meal row via raw SQL; assert it appears only when `type == nil`. |
| `events(in:type:)` fail-fast on a corrupt `metadata` row | Hand-insert a row with malformed JSON; expect `PersistenceError.corruptRecord`. |
| `allMeals()` returns newest-first | Existing test reused (ordering becomes `timestamp DESC, id ASC`). |
| `meal(id:)` and `deleteMeal(id:)` filter on `event_type=meal`; non-meal id surfaces as `mealNotFound` | Hand-insert a non-meal row; assert `meal(id:)` throws `mealNotFound` and `deleteMeal(id:)` leaves the row in place. |
| `deleteMeal` cascades to `meal_artefacts` and `corrections` (Req 4.3) | Insert artefact + correction rows; delete; assert both side tables empty for that id. |
| `updatePhotoAssetID` rewrites `metadata` and emits `eventsDidChange` | Reload sees the new value; subscriber receives one tick. |
| `corrections(for:)` returns the append log ordered by `created_at` ASC; meal event `value` unchanged | Append two corrections at distinct timestamps; assert order; assert event `value` unchanged. |
| `eventsDidChange` yields after `save`, `delete`, `updatePhotoAssetID`, and `appendCorrection` (design-handoff-00 [Decision 18](../../ui/design-handoff-00/decision_log.md#decision-18-appendcorrection-now-emits-eventsdidchange)) | Subscribe before each operation; assert tick presence. |
| `deleteArtefacts(olderThan:)` resolves paths from event id, not from a stored column | Save meal with artefact dir present on disk; advance clock; sweep; assert dir gone. |
| Protobuf-JSON byte-identical inside `metadata.record` | Encode → store → reload `metadata` → extract `record` field → equal to `original.pb.jsonString()` exact bytes. |

Property-based testing is not added in this phase. The two universal invariants worth PBT are range-query closure under `[start, end]` and round-trip equality; both are expressible as small example-based tests with the existing XCTest fixtures, and Decision 1 deferred the broader generative-test machinery alongside other premature infrastructure.

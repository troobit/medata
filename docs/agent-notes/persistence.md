# Persistence Module

## Architecture

`Persistence` depends only on `PortableContracts` + `GRDB` + `ZIPFoundation`.

`MealRecord` uses **Pb sub-types** for all composite fields (PbCameraIntrinsics, PbSupportPlane, PbMetricScale, PbVolumeResult, PbMacroResult, PbConfidenceResult, PbBetaCalibrationStatus, PbUserCorrection, PbRawFrameMetadata). This avoids importing the upstream native-type modules (Volume, Macros, Confidence, etc.) into Persistence.

Native Swift types used: `UUID` (id), `Date` (createdAt), `CapturePath` (PortableContracts enum), `String` (databaseEdition, paletteVersion).

`paletteVersion` is a **SQL-only** denormalized column; it is NOT in `PbMealRecord` and must be passed separately when round-tripping through the database.

## Serialization (Decision 31)

`record_json` column = protobuf-JSON of `PbMealRecord` via `SwiftProtobuf.jsonString()` / `init(jsonString:)`. This guarantees byte-identical encoding between iOS Swift and a future Android Kotlin consumer.

`paletteVersion` is stored in the SQL column and injected back via `MealRecord.from(jsonString:paletteVersion:)`.

## Schema (design §4.1)

Five tables: `meals`, `meal_classes`, `meal_artefacts`, `corrections`, `meta`. Created with `CREATE TABLE IF NOT EXISTS` for idempotent startup. Corrections are immutable (never UPDATE, always INSERT, PRIMARY KEY = meal_id + created_at).

## PaletteMigrator

Formula: `m_c' = V_c · ρ_new · β_new / (ρ_old · β_old)` where:
- V_c = volumeCm3 from the stored PbPerClassMacros entry
- ρ_old, β_old = looked up from PaletteFoodDatabase for the old class + old edition
- ρ_new, β_new = looked up from PaletteFoodDatabase for the new class + new edition
- Unmappable classes are retained under their old class id

`BundlePaletteMigrator` looks up mapping URLs by key `"\(fromPalette)→\(toPalette)"`.

## Archive Export

Uses ZIPFoundation. Checkpoints the WAL before copying (`db.checkpoint(.truncate)`). Resolves symlinks in both base and item paths before computing relative entry paths — macOS returns `/var/…` for `temporaryDirectory` but file enumeration may yield `/private/var/…`.

## RetentionScheduler

Two sweep modes:
- `sweep(relativeTo:)` — unconditional, used by BGProcessingTask and tests
- `sweepIfDue()` — delegated to `GRDBPersistenceStore` which checks `last_sweep_at_ms` in the meta table (only sweeps if 24h have passed)

BGProcessingTask guard: `#if os(iOS)` (not `canImport(BackgroundTasks)` which would match macOS 12+).

## Insulin events (regression-suggestion-integration)

`EventType.insulin` rows follow **medreg's convention** (`~/repos/medreg/docs/insulin-event-convention.md`; parser source of truth `medreg/src/medreg/insulin.py`): `value` = units (REAL, non-negative), `timestamp` = administration time UTC ms, `metadata` = JSON object with exactly `kind` ("bolus"|"basal"), `insulin_type` (free text), `schema_version` (integer 1), plus `note` only when provided — the key is **absent, never null**, when nil. Do not add metadata keys beyond the convention.

`saveInsulinDose` rejects units < 0 or > 60 (`PersistenceError.insulinUnitsOutOfRange`); 0 and 60 are accepted at the store — the UI enforces its own floor of 1 U. `deleteInsulinEvent(id:)` is gated on `event_type = insulin` so a meal/bsl row sharing the id survives; insulin has no side tables. Both notify `eventsDidChange` once (delete notifies unconditionally, matching `deleteMeal`).

Cross-repo check (2026-07-05): a store-written fixture loads in medreg via `medreg.ingest.load_events` with matching units/kind/timestamp/insulin_type/note. medreg is read-only over the export archive; no adapter needed.

## GRDB version note

`DatabaseQueue.read {}` is async in GRDB 6 — always `try await`. `Database.CheckpointMode` uses `.truncate` (not `.truncating`). The Archive throwing initializer is `try Archive(url:accessMode:)`.

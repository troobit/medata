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

Five tables: `meals`, `meal_classes`, `meal_artefacts`, `corrections`, `meta`. Created with `CREATE TABLE IF NOT EXISTS` for idempotent startup. Corrections are immutable for `appendCorrection` callers (INSERT, PRIMARY KEY = meal_id + created_at); the meal-review path instead uses `upsertCorrection` — one row per meal, `created_at` fixed at review-session start, ON CONFLICT DO UPDATE — so same-millisecond mutations cannot raise a constraint violation.

## Correction records (ui/meal-review)

`correction_records` (schema v7; `CREATE IF NOT EXISTS` retrofits onto v6 DBs): one row per detected food per capture, PRIMARY KEY (meal_id, predicted_class), `record_json` = protobuf-JSON of `PbCorrectionRecord`. Four denormalised bool columns (`class_corrected`, `rejected`, `absent`, `amount_corrected`) mirror fields inside the blob for queryability. `PbCorrectionRecord` field 22 `was_reverted` (meal-review Decision 20) marks per-dimension reversals so a corrected-then-uncorrected food is separable from a confirmed prediction; blob-only, no column.

**Never pruned.** Exempt from `deleteMeal`/`deleteRecords` cascades, from `deleteAllData()` (the Debug reset), and from every sweep — the corpus is the deliverable (meal-review Req 9.9/9.10). Do not add it to any delete path.

- Creation: `createCorrectionRecords` — INSERT ... DO NOTHING; re-presenting the surface must not reset `created_at` or overwrite the predicted side. Never tick `eventsDidChange` on creation.
- Mutation: `updateCorrectionRecord(_:upsertingCorrection:)` — INSERT ... ON CONFLICT (meal_id, predicted_class) DO UPDATE touching only the corrected columns (`updated_at`, the four flags, `record_json`); `created_at` and `outcome_id` keep their first-write values on conflict. The insert arm **self-heals** a row whose creation failed (that error is swallowed per Req 8.5) — the earlier bare UPDATE matched zero rows forever in that case while the reconciling corrections write beside it succeeded. When the reconciling `PbUserCorrection` is passed it is upserted into `corrections` in the SAME transaction and `eventsDidChange` ticks once.
- Batch mutation: `updateCorrectionRecords(_:upsertingCorrection:)` — the whole-meal-scale path; every row plus the reconciling upsert in ONE transaction (a force-quit mid-scale must not diverge corpus from Records). All records must share one meal_id; the single-record method delegates to it.
- Reads: `correctionRecords(for:)`, `allCorrectionRecords()`, `recentCorrectedClassIds(forPredictedClass:limit:)` (recency shortlist; decodes blobs, bounded scan LIMIT 100).

`deleteArtefacts(olderThan:)` skips meals whose correction_records row carries an actual correction (any of the four flags — not mere row existence), and now also deletes the `meal_artefacts` rows alongside the directories.

## Candidate evidence (alternative-class-candidates)

`PbMealRecord` fields 16/17 — `map<string, CandidateSet> candidate_evidence`
keyed by detected class name, and `bool candidate_evidence_produced`. Surfaced on
`MealRecord` as `candidateEvidence: [String: PbCandidateSet]` and
`candidateEvidenceProduced: Bool`, both defaulted so every existing constructor
compiles unchanged. `CandidateSet` is **parallel arrays** (`class_names` +
`mean_permille`), not one message per candidate: the record persists as
protobuf-JSON, where object framing costs ~50 B a candidate and would carry the
worst case over the 1 KB budget (Decision 10). Measured worst case (5 sets × 5
16-character names) is **920 B** of added JSON, asserted in
`CandidateEvidenceRecordTests`.

Three gotchas:

- **The marker is not derivable from the map.** Empty-because-nothing-qualified
  and never-produced are different facts, and Req 8.1's denominator is the
  population where the pass ran (Decision 4). `Pipeline` sets it from
  `nadirSeg.candidateEvidence != nil` — that the pass RAN, not that fills landed.
- **The member-wise copy sites are the hazard.** The pb bridge in both directions
  and `withPhotoAssetID` reconstruct field by field; one omission drops evidence
  while every other value still looks right. Pinned by test, not by review.
- **Equal array lengths are a writer invariant the reader checks.** `init(pb:)`
  filters out any set whose arrays disagree — it reads as no evidence for that
  class, never as a corrupt record. This pass must not be able to fail a load.

`PaletteMigrator` needs no code for Req 5: `reDerive` builds a fresh record, so
evidence drops and the marker defaults false by construction. `PaletteMigratorTests`
asserts the migrated record is byte-identical (modulo the fresh UUID and
timestamp) to one migrated from a record that never carried evidence.

Downgrade is not a supported path: SwiftProtobuf JSON decoding throws on unknown
fields, so a build predating 16/17 cannot read a record carrying them. Noted, not
designed around.

## PaletteMigrator

Formula: `m_c' = V_c · ρ_new · β_new / (ρ_old · β_old)` where:
- V_c = volumeCm3 from the stored PbPerClassMacros entry
- ρ_old, β_old = looked up from PaletteFoodDatabase for the old class + old edition
- ρ_new, β_new = looked up from PaletteFoodDatabase for the new class + new edition
- Unmappable classes are retained under their old class id
- `perClassVolumesPreBetaCm3` (VolumeResult field 5, meal-review Decision 17) is re-keyed through the migration with values unchanged — pre-β volume is geometric, class-independent. Empty on records written before the field existed.

`BundlePaletteMigrator` looks up mapping URLs by key `"\(fromPalette)→\(toPalette)"`. It cannot import `Macros`/`Foods` (dependency boundary), so its §6.12 arithmetic stays independent of `Macros.reDerive` — meal-review Decision 19.

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

## Intake events (manual-carb-intake)

`EventType.intake` rows mirror the insulin convention: `value` = carbs in grams, `timestamp` = the user-set time UTC ms, `metadata` = JSON object with `subtype` (only "carb" for now), `schema_version` (integer 1, `IntakeEntry.metadataSchemaVersion`), `source` ("manual"|"quickadd"), plus `preset_id` (quickadd provenance stamp — not enforced against `source`) and `protein_g`/`fat_g`/`fibre_g` — all optional keys **absent, never null**, when nil.

`saveIntakeEntry`/`updateIntakeEntry` reject carbs outside 1...999 (`PersistenceError.intakeCarbsOutOfRange`). Update and delete are gated on `event_type = intake` so a meal/insulin/bsl row sharing the id survives; intake has no side tables. Each write notifies `eventsDidChange` once (unconditionally, matching insulin).

Quick-add presets live in the `quick_presets` table (schema v5; `CREATE IF NOT EXISTS` retrofits it onto v4 DBs — no DDL on legacy tables): `id` TEXT PK, `name`, `carbs_g` NOT NULL, optional `protein_g`/`fat_g`/`fibre_g`, `sort_order`. The three authored defaults ("A pint" 17 g, "Bagel" 45 g, "Chips" 40 g) are seeded **at most once per DB**, gated on the `quick_presets_seeded` meta flag — deleting all presets does NOT reseed on relaunch. `saveQuickPreset` is INSERT OR REPLACE (insert and update in one); preset writes do not notify `eventsDidChange`.

## Activity events (activity-events)

`EventType.activity` rows mirror the insulin convention: `value` = **duration in minutes** and is SQL NULL when the duration was not given (nil is unrecorded, never 0 — Req 1.5), `timestamp` = the activity **start** UTC ms, `metadata` = JSON object with `schema_version` (integer 1, `ActivityEvent.metadataSchemaVersion`), `kind`, `provenance` ("manual"|"healthkit"), plus `note` only when provided — **absent, never null**, when nil.

`character` (aerobic/anaerobic/mixed) is **never stored**. It is a computed property on `ActivityKind` with an exhaustive `switch` and no `default`, so adding a kind without classifying it fails the build. Writing it would create two sources of truth for the field a later regression joins on.

`activities(before:within:)` is the lookback a dosing model calls instead of reimplementing the query: half-open at the bottom, closed at the top — `(instant - interval, instant]` — newest first. `ActivityEvent.defaultLookback` is the 36 hours of Decision 3; the parameter is deliberately NOT defaulted so each call site's window is visible. Rows that fail to decode (unknown `kind`, non-JSON metadata) are **dropped, not thrown** — unlike `events(in:type:)`, which fails fast. An empty result is an ordinary answer.

`saveActivity` has no range validation (there is no bound to enforce on a duration). `deleteActivityEvent(id:)` is gated on `event_type = activity`; activity has no side tables. Both notify `eventsDidChange` once.

Nothing in `MedataCore` or `App` consumes the lookback within the activity-events spec: the covariate is RECORDED and no insulin adjustment is applied (Decision 5). insulin-dosing Req 12.4 is the intended first consumer.

## Record deletion (records-deletion)

`deleteBslEvent(id:)` mirrors the insulin/intake single-row gates
(`event_type = bsl`, notify once) — glucose rows are deletable since
records-deletion Decision 3, superseding home-router Req 3.5. Wrinkle: a
reading deleted inside the live LibreLinkUp polling window re-ingests on the
next poll (keep-first merge probes incoming timestamps); accepted, no UI
messaging.

`deleteRecords(mealIDs:eventIDs:)` is the batched bulk/date-range path: ONE
write transaction (chunked `IN` deletes at 500 ids/statement — the
32,766-bound-variable cap precedent; per-meal `events`/`meal_artefacts`/
`corrections` cascade identical to `deleteMeal`), best-effort artefact-dir
removal after commit, ONE `eventsDidChange` notification. Never loop the
single-row deletes for bulk work — each notifies and every observer reloads
per tick.

## Estimation outcomes (snaq-parity)

`estimation_outcomes` (schema v6; `CREATE IF NOT EXISTS` retrofits it onto v5
DBs like quick_presets onto v4): one row per estimation attempt — success or
refusal. Columns: `id` TEXT PK, `timestamp` (UTC **ms**, last_sweep_at_ms
precedent), `outcome` ('success'|'refused'), `failure` (JSON
{domain, case, payload}, NULL on success), `measurements` (JSON
`EstimationAttemptRecord` snapshot, schema-versioned via its `v` field),
`meal_id` (success only), `model_version` (segmenter lineage tag),
`benchmark_meal_id` (set when launched from a benchmark meal). Indexes
`outcomes_timestamp` and `outcomes_benchmark(benchmark_meal_id, model_version)`.

Persistence stores `failure`/`measurements` **opaquely** — it sits below
Pipeline in the dependency graph and cannot see the typed record; the
`EstimationOutcome(record:benchmarkMealID:)` bridge lives in Pipeline
(PipelineDiagnostics.swift). `saveEstimationOutcome` applies split eviction
bounds INSIDE the insert's write transaction: non-benchmark rows keep the
newest 500; benchmark rows keep the newest 10 per (benchmark_meal_id,
model_version). "Newest" orders by (timestamp, id) — the id tie-break keeps
eviction deterministic when attempts share a millisecond. Only the population
the insert belongs to is evicted. `estimationOutcomes(limit:)` returns newest
first. Outcome writes never touch `eventsDidChange` (quick_presets convention).

## Benchmark meals (snaq-parity)

`benchmark_meals` (also schema v6 — Decision 7 defines v6 as BOTH snaq-parity
tables; `CREATE IF NOT EXISTS` retrofits it onto dev DBs stamped '6' before it
landed): `id` TEXT PK, `name`, `created_at` (UTC ms), `items` (JSON
`[{class_id, grams}]` — snake_case pinned by `BenchmarkMealItem` CodingKeys),
`truth_carbs_g`, `db_edition`, `fidelity` ('weighed'|'package').

`saveBenchmarkMeal(_:carbsPer100g:)` takes an **injected lookup**
`(String) -> Double?` because Persistence sits below Foods and cannot call
`FoodDatabase.entry(for:)` itself — the caller backs it with the same lookup
`Macros.compute` uses. Truth is derived AT SAVE (`grams × carbs/100` summed;
no volume, no β) and the caller-supplied `truthCarbsG` is **ignored**. Grams
outside 1...5000 → `benchmarkGramsOutOfRange`; a nil lookup →
`benchmarkClassUnresolvable` (never a silent 0 g truth). Insert-or-update by
id, but the upsert is rejected with `benchmarkMealImmutable` once any
`estimation_outcomes` row references the meal (checked inside the write
transaction) — corrections create a new meal. No `eventsDidChange`.

The report maths lives in the separate `Benchmark` SwiftPM target (depends on
Persistence only): `BenchmarkReport.compute(meals:outcomes:lineage:)` (pure;
latest-completed-attempt scoring with (timestamp, id) tie-break; SNAQ anchor
block; N ≥ 20 + staple-floor headline validity) and
`BenchmarkReport.promotionVerdict(old:new:seed:)` (paired bootstrap, seeded
`SplitMix64`, two-tier revert per design lane B). The estimate for a completed
meal is decoded from the outcome row's `measurements` JSON — the sum of
`decomposition[].carbsG` — so Benchmark never imports Pipeline.

## Bsl ingestion (libre-ingestion + cgm-connect)

Both `ingestBsl` (screenshot import) and `ingestLiveBsl` (live sources, cgm-connect Phase 1) share one private keep-first merge, `mergeBslKeepFirst`, which takes per-row `(timestampMs, value, metadataJSON)` tuples and adds each freshly inserted `timestampMs` to its covered set as it goes. That covered-set update is a deliberate behavioural change to `ingestBsl` too: two same-timestamp readings in one screenshot batch previously both inserted; now the second is classified `skippedExisting` (cgm-connect design "finding #5").

`ingestLiveBsl` differences from `ingestBsl`: no `processed_images` marker, per-row metadata built by the store itself (`{"source_id":…,"native_instant_ms":…,"native_id":…}`, `native_id` key absent — never null — when nil, matching the insulin convention), callers pass typed `LiveBslReading` values and never construct event JSON. Both notify `eventsDidChange` once per batch iff at least one row stored.

`mergeBslKeepFirst` seeds its covered set with a `BETWEEN min AND max` range query over the batch's timestamps (fix landed in cgm-connect Phase 2; previously `timestamp IN (…)` — one bound variable per reading against SQLite's 32,766 cap, which a >32k-row backfill would exceed). Extra committed rows inside the range are harmless: the map is only probed at incoming timestamps. `ingestLiveBsl` also guards the empty batch — it returns a zero `BslIngestSummary` without opening a write transaction.

## GRDB version note

`DatabaseQueue.read {}` is async in GRDB 6 — always `try await`. `Database.CheckpointMode` uses `.truncate` (not `.truncating`). The Archive throwing initializer is `try Archive(url:accessMode:)`.

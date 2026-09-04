# Decision Log: Event Log Schema

## Decision 1: Trim scope to data architecture only (no lakehouse patterns, no validation)

**Date**: 2026-06-09
**Status**: accepted

### Context

The original feature request asked for a Long-Form Event Log plus a set of data-engineering patterns (horizontal/vertical partitioner, dataset materializer, compactor, metadata-enhancer block-skipping statistics, schema-compatibility enforcer, stateful sessionizer, late-data detector, audit-write-audit-publish). MeData is a single-user, on-device iOS app storing meals in one SQLite file (GRDB), at a realistic scale of hundreds to low tens of thousands of rows. No regression, decay, or time-series code exists; CGM/decay work is already deferred to a future phase.

### Decision

Limit this feature to two things: (1) the Long-Form Event Log table and paradigm, and (2) introducing it directly as the meal store. Ingestion validation is also excluded. All listed lakehouse patterns are deferred. (See Decision 5: there is no production data, so no migration is in scope.)

### Rationale

The lakehouse patterns target distributed, petabyte-scale analytical warehouses where small-file overhead, I/O footprint, and data skipping dominate. At single-user SQLite scale, a B-tree index on the timestamp already provides time-window skipping; there are no small files to compact; the query planner already does predicate pushdown; and JSON parsing of hundreds of rows is sub-millisecond. Building this machinery now adds ongoing complexity to solve problems that do not exist yet. The user confirmed the trim, then further excluded ingestion validation as premature for this stage.

### Alternatives Considered

- **Implement all patterns as written**: Rejected — premature optimization; carries ongoing maintenance cost for no measurable benefit at this scale.
- **Minimal spike only (no spec)**: Rejected — the change touches the persistence boundary and existing read paths, which warrants a full spec.

### Consequences

**Positive:**
- Smallest change that establishes the extensible event-log baseline.
- No speculative infrastructure to maintain.

**Negative:**
- Future regression work will need its own spec for any of the deferred patterns it genuinely requires.

---

## Decision 2: Event log is the single meal store

**Date**: 2026-06-09
**Status**: accepted

### Context

Meals can be stored either in the legacy `meals`/`meal_classes` tables, in the event log, or in both (dual-write). The goal is a single, unambiguous source of truth.

### Decision

The event log is the sole meal store. Read and write paths target it. The legacy `meals` and `meal_classes` tables are not part of the new schema. `meal_artefacts` and `corrections` remain as side tables, linked by the meal event's id.

### Rationale

The stated goal is high-integrity data. Dual-write maintains two stores that can drift, which is itself an integrity risk. A single source of truth is the integrity-correct end state. Because there is no production data (Decision 5), the legacy tables can simply not be created — no retention or fallback window is needed.

### Alternatives Considered

- **Additive / dual-write, legacy tables remain source of truth**: Rejected — two sources of truth risk drift.
- **Keep `meal_classes` as an indexed table for per-class queries**: Rejected — per-class data lives in `metadata` (Decision 3); no current consumer needs indexed per-class rows.

### Consequences

**Positive:**
- One source of truth, no drift, no dual maintenance.

**Negative:**
- Per-class queries read from `metadata` rather than an indexed table (accepted in Decision 3).

---

## Decision 3: One event per meal; primary scalar in `value`, breakdown in `metadata`

**Date**: 2026-06-09
**Status**: accepted

### Context

A meal currently carries a per-class, per-macro breakdown. In a long-form log this could decompose to one row per meal, per food class, or per macro metric. The fixed `value` column also needs defined semantics.

### Decision

Store one event per meal (`event_type = "meal"`). The `value` column holds the canonical scalar for the event type — total carbohydrate in grams for a meal. All multi-dimensional data (per-class and per-macro breakdown, volume, sigma, calibration) lives in the `metadata` JSON. Future metrics (heart rate, CGM, insulin, LiDAR-derived volume) become their own `event_type` rows.

### Rationale

One row per meal keeps the meal atomic and minimises row count, while `metadata` preserves the full breakdown. A canonical scalar in `value` keeps the common time-series query fast without parsing JSON. New metrics are added as new event types, satisfying the extensibility goal without per-macro row explosion.

### Alternatives Considered

- **One event per food class**: Rejected — more rows and a correlation id, with no current consumer needing per-class rows.
- **One event per macro metric**: Rejected — heaviest row count, "pure" normalisation with no current benefit.
- **`value` nullable, all data in metadata**: Rejected — common queries would have to parse JSON.

### Consequences

**Positive:**
- Atomic meals, minimal rows, fast canonical queries.

**Negative:**
- Per-class queries must read from `metadata` until/unless a finer event type is introduced later.

---

## Decision 4: Metric units only; glucose in mmol/L

**Date**: 2026-06-09
**Status**: accepted

### Context

The `value` column stores physiological measurements that must be unambiguous for the life of the app.

### Decision

Store all physiological values in metric units only: glucose in mmol/L, mass in grams, volume in cubic centimetres. No imperial units, and no unit or locale conversion. Internationalisation is out of scope, permanently.

### Rationale

A single fixed unit per metric removes ambiguity from stored data and from any future regression that reads it. mg/dL is explicitly disallowed for glucose. Conversion and localization add complexity with no benefit for this single-user app.

### Consequences

**Positive:**
- Stored values are unambiguous; no conversion bugs.

**Negative:**
- None for the target use; a future export to an imperial-expecting consumer would convert at the boundary, not in storage.

---

## Decision 5: No migration or backfill — no production data exists

**Date**: 2026-06-10
**Status**: accepted

### Context

An earlier draft of this spec included a migration that would backfill existing meals into the event log and retain the legacy tables read-only as a fallback. The app is pre-release (Phase 1 dev-stub) and holds no production data.

### Decision

Drop migration and backfill from scope entirely. Introduce the event log directly as the meal store. The legacy `meals`/`meal_classes` tables are simply not created.

### Rationale

There is nothing to migrate. A backfill of an empty store is a no-op, and the safety machinery a real migration would need (idempotency keys, corrupt-row handling, pre-migration DB snapshot, WAL checkpoint, one-release rollback window) would all be guarding against risks that cannot occur with no data. Removing it is the simplest correct outcome.

### Alternatives Considered

- **Keep a no-op migration for symmetry / future-proofing**: Rejected — it guards risks that do not exist and adds code and review surface for no benefit.

### Consequences

**Positive:**
- Removes the entire migration-safety surface (the bulk of the design-critic and peer-review findings became moot).
- Smaller, simpler spec and implementation.

**Negative:**
- If real data is ever introduced before this ships, a migration would need to be reintroduced. Acceptable given the current pre-release state.

---

## Decision 6: `metadata` stores the verbatim record plus SQL-only fields

**Date**: 2026-06-10
**Status**: accepted

### Context

An early requirement listed the specific fields the meal event's `metadata` must preserve. Review against the protobuf schema found the list was wrong: per-class `protein/fat/fibre/energy` and per-class `density` do not exist in the proto in that shape, and `palette_version` exists only as a SQL column, not in the record.

### Decision

`metadata` stores the verbatim meal record (the protobuf-JSON currently held in `record_json`) plus the fields that exist only as SQL columns today (`palette_version`, and the `photo_asset_id` / `segmenter_source` overrides). The acceptance check is round-trip equality: the original `MealRecord` reconstructs from `metadata` with no loss.

### Rationale

A hand-maintained field list was already factually wrong and would drift from the schema. Storing the record verbatim plus the known SQL-only columns is both simpler and verifiably lossless, and round-trip equality is a concrete, testable acceptance criterion.

### Alternatives Considered

- **Enumerate preserved fields**: Rejected — the enumeration was already incorrect against the proto and would require maintenance as the record evolves.

### Consequences

**Positive:**
- Verifiably lossless; no field list to maintain.

**Negative:**
- `metadata` carries the full record even for fields a query rarely needs; negligible at this scale.

---

## Decision 7: Rename `mealsDidChange` to `eventsDidChange`; notify on `updatePhotoAssetID`

**Date**: 2026-06-13
**Status**: accepted

### Context

The change-notification stream fires after every event-row write. With the schema moving from a meals table to a generic events table, the existing `mealsDidChange` name no longer describes what the broadcaster does. Separately, `updatePhotoAssetID` silently rewrites the row today; with the event log it is the only path that stamps the photo binding onto an already-persisted meal, and the Meals tab does not refresh otherwise.

### Decision

Rename `mealsDidChange` to `eventsDidChange`. Make `updatePhotoAssetID` call the broadcaster.

### Rationale

The rename is a single-call surface and one consumer (`MealHistoryModel`). Renaming now avoids name-rot when other event types arrive. Adding the notification on `updatePhotoAssetID` aligns the broadcaster's contract — fires on every event-row write — and gives the UI a deterministic refresh point.

### Alternatives Considered

- **Keep `mealsDidChange`**: Rejected — name-rot once non-meal events ship; cost of the rename is one consumer line.
- **Leave `updatePhotoAssetID` silent**: Rejected — Meals tab does not redraw on photo stamp; the row appears un-photographed until the next unrelated change.

### Consequences

**Positive:**
- Stream name matches its semantics; UI redraws on the photo stamp.

**Negative:**
- Test stub conformers across the codebase update — small mechanical churn.

---

## Decision 8: Public `events(in:type:)` and `corrections(for:)` on `PersistenceStore`

**Date**: 2026-06-13
**Status**: accepted

### Context

Requirements 1.4 / 1.5 (chronological order + range query) and 4.4 (corrections overlay) could be satisfied internally without changing the protocol surface. The alternative is to expose them as protocol methods so the requirements have a concrete read API.

### Decision

Add two methods to `PersistenceStore`: `events(in:type:)` and `corrections(for:)`.

### Rationale

The requirements describe behaviours of the store that consumers should be able to invoke. Exposing them at the protocol gives a directly testable surface and a small, future-friendly affordance for a regression/overlay consumer that does not exist yet in this phase. The cost is two method signatures and matching stubs in test conformers — small. The `type` parameter on `events(in:type:)` is retained even though only `"meal"` is implementable in this phase, because it is the Req 1.3 affordance and is exercised in tests with a hand-inserted non-meal row.

### Alternatives Considered

- **Keep internal**: Rejected — the requirements are read-side; not exposing them leaves the contract untestable at the API boundary.
- **Add only `events(in:type:)`, leave corrections internal**: Rejected — Req 4.4 explicitly mentions overlay reads; symmetry beats asymmetry for the cost.

### Consequences

**Positive:**
- Requirements 1.4 / 1.5 / 4.4 are testable at the public surface.

**Negative:**
- Two extra methods on stub conformers (`fatalError("unused")` is acceptable where the test does not exercise them).

---

## Decision 9: `EventType.meal` constant; no SQL `CHECK` on `event_type`

**Date**: 2026-06-13
**Status**: accepted

### Context

`event_type` is a free-text `TEXT` column. With only one value (`"meal"`) today, an unconstrained column lets a typo or copy-paste error silently insert a row that no read path returns (every meal-shaped read filters on `event_type='meal'`).

### Decision

Centralize the vocabulary at the API boundary with a Swift constant: `EventType.meal = "meal"`. No SQL `CHECK` constraint and no full enum (yet).

### Rationale

A constant catches the typo at the call site, which is where every event is constructed. A `CHECK` constraint would block future event types from being added without a schema change, contradicting Req 1.3. A full Swift enum is overkill while only one variant exists — it is trivially upgradable later. Decision 1 already deferred SQL-level validation machinery.

### Alternatives Considered

- **SQL `CHECK (event_type IN ('meal'))`**: Rejected — would have to be dropped or rewritten for every new event type; contradicts Req 1.3's "no schema change" promise.
- **No central registry, callers use the literal**: Rejected — vulnerable to silent-typo bugs; no compile-time hint.
- **Full Swift `enum EventType: String`**: Rejected — single-variant enum has no advantage over a constant and adds rawValue/init churn.

### Consequences

**Positive:**
- Typo-resistant at the API boundary; future types extend the same namespace.

**Negative:**
- An external SQL writer could still insert an unknown `event_type`; acceptable since the only external writer is the test that exercises the `type` filter.

---

## Decision 10: Wrong-`event_type` id → `mealNotFound`; pre-existing dev DBs left untouched

**Date**: 2026-06-13
**Status**: accepted

### Context

`meal(id:)` and `deleteMeal(id:)` are meal-specific operations on an events table that will, eventually, hold other event types. Separately, dev devices may carry a pre-existing `meals.sqlite` from before this change; the legacy `meals` / `meal_classes` tables would still be present on disk.

### Decision

Both `meal(id:)` and `deleteMeal(id:)` filter on `event_type=EventType.meal`. An id that exists with a different `event_type` is reported as `PersistenceError.mealNotFound`. `createSchema` only creates the `events` table; pre-existing legacy tables are not dropped. The design states the developer workaround (wipe simulator/device storage) for those who care about the orphan storage.

### Rationale

Filtering keeps the meal-named API honest about its scope — `deleteMeal` does not delete arbitrary events. `mealNotFound` for a wrong-type id is the closest existing error and avoids inventing a new error case for a path that can only arise from external tampering. For dev DBs, destructive DDL on the production code path guards a risk that does not exist (Decision 5: no production data) and adds a code path with no production value; the wipe instruction is the simplest correct outcome.

### Alternatives Considered

- **`meal(id:)` / `deleteMeal(id:)` operate on any event row by id**: Rejected — the names lie about what they do once other event types exist.
- **New `PersistenceError.wrongEventType(_:got:)`**: Rejected — only meal API code paths would observe it; an indistinguishable `mealNotFound` is sufficient.
- **`createSchema` drops legacy tables when `schema_version < 3`**: Rejected — destructive DDL on every dev install for no production benefit.

### Consequences

**Positive:**
- Meal API is honest; no destructive DDL ships.

**Negative:**
- Dev DBs accumulate stale legacy tables that `exportArchive` includes verbatim; acceptable in pre-release.

---

## Decision 11: Cite the cross-spec byte-identity decision with the `research D31` key

**Date**: 2026-06-28
**Status**: accepted

### Context

`design.md` justified the protobuf-JSON byte-identity guarantee by referring to "Decision 31". This spec's own decision log only runs 1–10, so a bare "Decision 31" reads as a dangling reference to a decision that does not exist here. The decision being cited actually lives in `specs/estimation/pipeline/decision_log.md` (Decision 31: Portable type contracts strip iOS-only types from public surfaces), which is the source of the byte-identical portable-contract guarantee an Android consumer relies on.

### Decision

Reference the cross-spec decision using the established citation key `research D31` (= Decision 31 in `specs/estimation/pipeline/decision_log.md`), and state the expansion inline at first use. Local decisions keep their bare `Decision N` form.

### Rationale

`specs/DECISIONS.md` already defines `research DN` as the citation key for the estimation/pipeline log (PROCESS §3 legacy-name note), and `specs/DECISIONS.md` itself cites `research D31`. Using the same key here makes the reference resolvable and disambiguates it from this spec's local Decision numbering, with no change to design intent.

### Alternatives Considered

- **Leave the bare "Decision 31"**: Rejected — it collides with this spec's local 1–10 numbering and resolves to nothing in the local log.
- **Renumber/copy the pipeline decision into this log**: Rejected — duplicates a decision owned by another spec; PROCESS §9 says the owning per-spec log is authoritative.

### Consequences

**Positive:**
- The byte-identity reference resolves unambiguously to its owning spec.
- Consistent with the repo-wide `research DN` convention.

**Negative:**
- A reader must follow the key to the estimation/pipeline log to read the full decision; acceptable and standard for cross-spec citations.

---

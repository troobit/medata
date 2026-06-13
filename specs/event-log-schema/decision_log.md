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

# Decision Log: Manual Carb/Macro Intake

## Decision 1: Full spec workflow (not smolspec)

**Date**: 2026-07-07
**Status**: accepted

### Context

The user asked to "facilitate carb/macro data intake without the estimation/photo pipeline" with new input screens, a modal, quick-add presets, user-definable quicksets, and edit/delete of records. A scope assessment estimated ~450–700 LOC of new Swift across multiple new files, a new ledger event type, and edit/delete semantics touching the existing read-only meal model.

### Decision

Use the full spec workflow (requirements → design → tasks with approval gates).

### Rationale

Every full-spec threshold is met: >80 LOC, >3 files, multiple subsystems (UI + data layer), a new data-layer event type, and real design forks. The user also explicitly requested a full spec.

### Alternatives Considered

- **Smolspec**: Lightweight path — Rejected because the change exceeds every smolspec bound (LOC, file count, cross-cutting data-model impact).

### Consequences

**Positive:**
- Design forks (quick-add value source, event type, edit/delete scope) get resolved before implementation.

**Negative:**
- More upfront process than a direct build.

---

## Decision 2: Carbs required, macros optional, shown only in entry detail

**Date**: 2026-07-07
**Status**: accepted

### Context

The feature is framed as "carb/macro" intake. Capturing four fields (carbs, protein, fat, fibre) per entry conflicts with the low-friction goal; capturing carbs only drops the "macro" half of the framing.

### Decision

Each entry requires a carbohydrate value; protein, fat, and fibre are optional, hidden behind a disclosure so the default path is a single carb field.

### Rationale

Keeps the common case one number (matching the insulin single-value flow) while still allowing fuller nutrition when the user has it. Balances the "carb/macro" framing against the "minimise interaction" objective.

### Alternatives Considered

- **Carbs only**: Fastest — Rejected because it drops macros entirely, contradicting the feature's stated scope.
- **Carbs + all macros always**: Richest data — Rejected because four fields per entry works against one-tap logging.

### Consequences

**Positive:**
- Fast path stays a single field; macros available on demand.

**Negative:**
- The record model and UI must handle absent (not zero) macro values.

### Impact

Design-critic flagged that nothing in the app consumes protein/fat/fibre (graph + totals are carbs + glucose), making captured macros write-only. Resolved by giving macros a consumer: an entry's captured macros are displayed in its own detail/edit view (Req 2.4). No aggregate/graph macro view is in scope.

---

## Decision 3: Quick-add values are fixed and user-set (not food-DB backed)

**Date**: 2026-07-07
**Status**: accepted

### Context

Quick-add items such as "a pint", "bagel", and "chips" are portion/colloquial items. The bundled CoFID/AFCD food databases are keyed by segmentation class-id and do not contain these portion items, so a live lookup would frequently miss.

### Decision

Each quick-add preset stores a fixed carbohydrate (and optional macro) value defined when the preset is created. No food-database lookup.

### Rationale

Fixed values are reliable, predictable, and match how the user thinks about these items ("a pint = N g"). The food DB's class-keyed structure is a poor fit for portion presets.

### Alternatives Considered

- **Food-database lookup**: Cleaner provenance — Rejected because the DBs lack portion items like "a pint" and are keyed by segmentation class.
- **DB where matched, else fixed**: Flexible — Rejected as premature; adds a matching/fallback rule to design and test without a demonstrated need.

### Consequences

**Positive:**
- Simple, deterministic preset values; no dependency on food-DB coverage.

**Negative:**
- Preset carb values are the user's responsibility; no automatic nutrition sourcing.

---

## Decision 4: Edit/delete scoped to manual carb entries only

**Date**: 2026-07-07
**Status**: accepted (supersedes the initial "any ledger record" choice)

### Context

The user first chose low-friction edit/delete over "any ledger record". Design-critic review then surfaced two blocking problems: (1) editing a photo meal's carb value directly contradicts the append-only correction model (event-log-schema Req 4.4 keeps the meal event's `value` immutable; a corrections UI already exists), and (2) there is no unified records list today — meals are in the Data screen, insulin in Trends — and the unified `records` surface is owned by the future home-router spec, not this one. So "any record" would rework a settled data model and build a records surface this spec does not own.

### Decision

This spec makes only manually-added carb entries (keyed-in and quick-add) editable and deletable, via a list of recent manual entries reachable from the intake surface. Universal edit/delete over photo meals, insulin, and glucose is deferred to the records/home-router spec.

### Rationale

Manual carb records have no correction model, so they are freely mutable with no conflict. Confining edit/delete to them resolves the Req 4.4 contradiction, keeps this spec self-owned (no dependency on the unbuilt unified records surface), and still delivers the low-friction fix/remove the user asked for on the records this feature creates.

### Alternatives Considered

- **Any ledger record**: Uniform edit/delete — Rejected after review: contradicts the immutable-meal/correction model and depends on a records surface owned by another spec.
- **Manual + insulin**: Also covers doses (no correction model) — Rejected to keep this spec's scope to the carb-intake records it creates; insulin edit belongs with the records surface.

### Consequences

**Positive:**
- No conflict with the correction model; spec stays self-contained and focused.
- Delivers fix/remove on exactly the records this feature introduces.

**Negative:**
- Editing meals/insulin/glucose still requires the future records/home-router spec; until then those remain edited via their current flows (meal corrections, etc.).

---

## Decision 5: Home router is a separate parallel spec; this spec owns the intake route only

**Date**: 2026-07-07
**Status**: accepted

### Context

Asked where the entry point should live, the user rejected the current design (Graph as launch root, design-handoff-00 Decision 20/21). They want a new home page acting as the primary router to `intake` / `dose` / `records`, with Graph reduced to visualisation only. They noted this "may need to be tied to a parallel ui/ spec."

### Decision

The new home page, Graph demotion, and dose/records routing become a separate `specs/ui/` spec. This `manual-carb-intake` spec covers the intake content only and assumes the home router provides an `intake` route.

### Rationale

Keeps each spec focused and lets intake proceed in parallel with the navigation-shell redesign. Matches the user's own steer.

### Alternatives Considered

- **Include the home router here**: One spec — Rejected as too broad; it would couple intake delivery to a navigation-shell redesign affecting dose, records, and Graph.
- **Defer the home page**: Keep Graph as root — Rejected because it leaves the entry point where the user said it should not be.

### Consequences

**Positive:**
- Focused specs; intake is not blocked on the shell redesign.

**Negative:**
- A cross-spec seam: the intake surface needs a temporary entry point until the home-router spec lands.
- Reverses design-handoff-00 Decision 20 (Graph as launch root); the home-router spec must record that supersession.

### Impact

A new `specs/ui/` home-router spec must be created (flagged in `nextup.md`). The `no-disclaimer-copy` memory note ("Graph is the launch root") becomes stale once the home router lands.

---

## Decision 6: "Quickset" interpreted as a flat collection of presets

**Date**: 2026-07-07
**Status**: accepted (resolved 2026-07-10 at the design gate)

### Context

The user wrote "have a quickset of options and create and add our own quicksets." This reads two ways: (a) a quickset is one preset, and the user creates many presets; or (b) a quickset is a named *group* of presets (e.g. a "pub" set, a "breakfast" set).

Requirements landed with interpretation (a) (Req 3.1–3.3, Req 4.1–4.4 all describe a single collection of individually named presets, no grouping field anywhere) but this decision was left `proposed` pending confirmation. At the design gate, no new information favours (b): the home-router spec that landed in parallel treats Records as one flat, ungrouped timeline (home-router Decision 3, rejecting sectioned/filtered views for the same reason), and the project's stated bias for this spec is minimalist UI and less code.

### Decision

Quick-add presets are a single flat, user-editable collection. Named/nested groups are a non-goal for this spec.

### Rationale

A flat collection is the simplest thing that satisfies the one-tap goal and avoids grouping UI (create-group, rename-group, move-preset-between-groups) that works against "minimise interaction." It matches the requirements as written and the sibling home-router spec's own flat-timeline choice. Grouping is additive later — a `groupName` field could be added to the preset row without breaking the flat rendering — so nothing here forecloses it.

### Alternatives Considered

- **Named preset groups**: Organise presets into sets — Rejected as premature complexity; adds grouping UI (group CRUD, assignment) without a demonstrated need, and requirements as written describe single presets, not groups.

### Consequences

**Positive:**
- Simplest preset model and UI; matches requirements as written.
- A `groupName` column could be added later without reshaping the flat list.

**Negative:**
- If the user later wants named sets (e.g. "pub" vs "breakfast"), that is new scope, not covered here.

---

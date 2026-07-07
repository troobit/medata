# Decision Log: Home Router

## Decision 1: Full spec workflow (not smolspec)

**Date**: 2026-07-07
**Status**: accepted

### Context

The feature introduces a new launch root, re-roots the navigation shell (reversing design-handoff-00 Decision 20), moves every entry point off the Graph toolbar, and adds a records surface that spans all three event types. A scope assessment estimated well over 80 LOC across 6+ files (new home view, records view, `AppRoot`, `TrendsView`, route enums, a unifying record model), with breaking navigation changes and cross-cutting data-layer concerns.

### Decision

Use the full spec workflow (requirements → design → tasks with approval gates).

### Rationale

Every full-spec threshold is met: >80 LOC, >3 files, multiple subsystems (shell + data layer), breaking navigation change, and reversal of two accepted decisions. The user approved the full-spec path at scope assessment.

### Alternatives Considered

- **Smolspec**: Lightweight path — Rejected because the change exceeds every smolspec bound (LOC, file count, breaking navigation change, cross-cutting data model).

### Consequences

**Positive:**
- The shell inversion and records-model forks get resolved before implementation.

**Negative:**
- More upfront process than a direct build.

---

## Decision 2: Home page is a pure router, no summary data

**Date**: 2026-07-07
**Status**: accepted

### Context

The new home page could be either a plain navigation hub or a hub that also surfaces at-a-glance data (today's carb total, latest glucose). More on the home page means more to build and maintain.

### Decision

The home page is a pure router: controls to Capture, Intake, Dose, Records, Graph, and Settings, and nothing else. No summary data.

### Rationale

The smallest thing that satisfies "a home page that routes to everything." A summary duplicates what Graph and Records already show and can be added later if wanted. User chose the pure-router option at the requirements gate.

### Alternatives Considered

- **Router + summary**: Home also shows today's carbs / latest glucose — Rejected as premature; duplicates Graph/Records and adds surface without a demonstrated need.

### Consequences

**Positive:**
- Minimal home page; fastest to build.

**Negative:**
- The user must open Graph or Records to see any data — the home page shows none.

---

## Decision 3: Records is a merged chronological timeline

**Date**: 2026-07-07
**Status**: accepted

### Context

The records surface must show three event types (meals, insulin, glucose) that today live on three different screens. It could interleave them in one list or split them into per-type sections/filters.

### Decision

Records is one chronological timeline, most-recent-first, with all three types interleaved and each row tagged by type.

### Rationale

A single timeline is the closest match to "one place that lists everything" and avoids the sectioning/filter UI, which works against a quick review-and-remove flow. User chose the merged-timeline option.

### Alternatives Considered

- **Sectioned/filterable by type**: Meals / Insulin / Glucose tabs or a segmented filter — Rejected as more UI than the review-and-delete task needs; grouping can be added later.

### Consequences

**Positive:**
- One list, one mental model; simplest records UI.

**Negative:**
- Three decode paths (meal protobuf, insulin JSON metadata, glucose value) must render into one row model; no per-type filtering.

---

## Decision 4: Records is delete-only; in-place editing deferred

**Date**: 2026-07-07
**Status**: accepted (supersedes the requirements-gate "editable" selections)

### Context

At the requirements gate the user initially selected editable+delete for meals (via the corrections flow) and for insulin (reopening the dose sheet). The user then interrupted to revise: records should be delete-only for both meals and insulin — "if they're wrong we can re-add them" — with editing deferred to a future feature if UX testers find it necessary. Less code is preferred for now.

### Decision

The Records surface deletes meals and insulin doses; it does not edit any record in place. Editing is out of scope for this spec.

### Rationale

Delete-and-re-add covers the correction need for the low-friction manual records with far less code than an edit UI, and it sidesteps the immutable-meal/append-only-correction conflict entirely (delete already exists and cascades; editing a meal's carb value would have required routing through the corrections model). Editing can be added later once UX testing shows it is needed. Direct user steer.

### Alternatives Considered

- **Editable + delete (meals via corrections flow, insulin via dose sheet)**: Uniform edit/delete — Rejected by the user as more code than warranted now; editing deferred.
- **Full in-place meal value edit**: Simplest UX — Rejected because it breaks the append-only correction model (event-log-schema Req 4.4).

### Consequences

**Positive:**
- Much less code; no edit UI, no corrections-flow coupling, no immutable-meal conflict.
- `deleteMeal`/`deleteInsulinEvent` already exist and cascade correctly.

**Negative:**
- Fixing a mistimed or mis-valued record means delete then re-add. Editing must arrive as a later feature if UX testing demands it.

---

## Decision 5: Glucose is read-only on the Records surface

**Date**: 2026-07-07
**Status**: accepted

### Context

Glucose readings are import-sourced from LibreLink screenshots via a keep-first merge; there is no glucose edit/delete UI today. The records surface could make glucose deletable (or editable) for uniformity with meals and insulin.

### Decision

Glucose rows appear on the Records timeline but are read-only — neither editable nor deletable.

### Rationale

A deleted glucose reading would be reintroduced by the next import (keep-first merge), so a delete affordance would appear not to work. Glucose has an authoritative external source; meals and insulin are user-entered and freely re-addable. Keeping glucose read-only matches its provenance and avoids a confusing no-op.

### Alternatives Considered

- **Editable + delete**: Most uniform — Rejected; lets manual edits diverge from the import source and a delete is undone on re-import.
- **Hide glucose from Records entirely**: Simplest — Rejected; the user wants one place that lists everything recorded, and glucose is part of the record.

### Consequences

**Positive:**
- No misleading no-op affordance; glucose stays consistent with its import source.

**Negative:**
- The Records surface has an asymmetry — two of three types are deletable, one is not.

---

## Decision 6: The Records surface replaces the meal-only Data screen

**Date**: 2026-07-07
**Status**: accepted

### Context

Today the Data screen (`DataView`) lists meals only, presented as a full-screen cover from the Graph toolbar. The new Records surface lists meals plus insulin and glucose. Keeping both would leave two meal lists.

### Decision

The Records surface supersedes the meal-only Data screen; the home page routes to Records, not to a separate Data screen.

### Rationale

Two overlapping meal lists is redundant. Records is a superset of what Data showed, so folding Data into Records keeps a single records place and one fewer route.

### Alternatives Considered

- **Keep Data and add Records alongside**: Least disruptive — Rejected; two meal lists confuse and duplicate.

### Consequences

**Positive:**
- One records place; one fewer home route to reason about.

**Negative:**
- `DataView`'s meal-specific presentation is absorbed into the unified timeline; any meal-only affordances must be preserved on the meal row/detail.

---

## Decision 7: Reverses design-handoff-00 Decision 20 (Graph as launch root)

**Date**: 2026-07-07
**Status**: accepted

### Context

design-handoff-00 Decision 20 made Graph the launch root with Capture/Data/Settings/Insulin entry points on its toolbar. This spec introduces a home page as the root and moves those entry points onto it, directly reversing that decision. The project `no-disclaimer-copy` memory also records "Graph is the launch root," which becomes stale.

### Decision

Record that this spec supersedes design-handoff-00 Decision 20. Graph is no longer the launch root; the home page is.

### Rationale

The user directed the change; capturing the supersession keeps the decision history traceable and prevents re-litigation. The AR-session-only-while-Capture lifecycle from Decision 20 is preserved, now anchored at the home root.

### Alternatives Considered

- **Leave Graph as root**: No shell change — Rejected; the user explicitly wants a home router with Graph as visualisation only.

### Consequences

**Positive:**
- Traceable supersession; the shell history stays coherent.

**Negative:**
- Third re-root of the app in the design-handoff-00 history; the `no-disclaimer-copy` memory note ("Graph is the launch root") must be updated once this lands.

---

## Decision 8: Records is all-time and unwindowed; delete is immediate via standard swipe-reveal

**Date**: 2026-07-07
**Status**: accepted

### Context

Design-critic review raised two records-surface concerns. (1) Volume: glucose is bulk-imported from LibreLink (dozens of readings/day), so an unbounded merged timeline could bury the meals/insulin the user came to delete. (2) Safety: a meal delete is irreversible and cascades the meal's corrections and stored photo artefacts, yet an inline swipe offers no confirmation. Both were put to the user as explicit choices.

### Decision

The Records timeline lists all records for all time with no windowing, pagination, or filtering. Deletion uses the standard iOS swipe-to-delete interaction (swipe reveals a Delete button); tapping it deletes immediately with no additional confirmation dialog.

### Rationale

The user chose the simplest build for both: accept the glucose volume rather than add windowing/pagination code, and rely on the swipe-reveal's inherent two-step (swipe, then tap Delete) rather than an extra confirmation. This matches the feature's low-friction, "less code for now, re-add if wrong" philosophy. If real-world glucose volume or accidental deletes prove painful in UX testing, windowing and/or confirmation can be added later.

### Alternatives Considered

- **Windowed timeline (day-grouped, recent-first, load-more)**: Bounds glucose volume — Rejected by the user in favour of the simpler all-time list.
- **Exclude glucose from Records**: Removes the volume problem — Rejected; the user wants one place listing everything, and glucose already appears read-only.
- **Explicit confirmation dialog on delete**: Safer against accidental loss — Rejected as unnecessary friction over the standard swipe-reveal.

### Consequences

**Positive:**
- No windowing/pagination or confirmation-dialog code; simplest records surface.

**Negative:**
- The timeline degrades as imported glucose accumulates; meals/insulin can be sparse among glucose rows.
- An accidental swipe-then-tap destroys a meal plus its corrections and photos with no undo.

---

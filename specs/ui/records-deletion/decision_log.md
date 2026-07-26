# Decision Log: Records Deletion

## Decision 1: Edit-mode multi-select over a custom selection UI

**Date**: 2026-07-26
**Status**: accepted

### Context

The user asked for deletion "closer to the top": individual swipe/long-press
delete with confirmation or standard practice, plus bulk and date-range
deletion with Select All and unselect. Several interaction shapes could carry
this: a custom checkbox column, a long-press-driven selection mode, or the
platform's `EditMode` multi-select.

### Decision

Use the standard iOS edit-mode pattern: an Edit button in the navigation bar,
`List(selection:)` checkmarks, a bottom bar with Select All / Deselect All
and a confirmed destructive Delete (n). Swipe-to-delete stays the individual
path on every row type, with the revealed Delete button as its confirmation.
Date-range purge is a toolbar-menu action opening a small sheet.

### Rationale

The Mail/Photos edit-mode pattern is what iOS users already know, it
composes with the existing `List` + `.onDelete` for free, and it needs no
bespoke selection state machine. Swipe delete without an extra dialogue is
the HIG-standard two-step (reveal, then tap); dialogues are reserved for the
non-reversible bulk shapes where a mis-tap destroys many rows.

### Alternatives Considered

- **Long-press to enter selection mode (Photos-style)**: familiar but hides
  the entry point; the user explicitly wants deletion visible near the top,
  which the Edit button provides — rejected as the primary entry (long-press
  can be added later as a shortcut).
- **Per-row confirmation dialogue on swipe delete**: maximally cautious —
  rejected: contradicts standard practice, doubles the interaction cost of
  the common case, and the user endorsed "standard UI practice".
- **Settings-level "erase all data" only**: simplest — rejected: does not
  cover individual or date-range deletion and hides purge far from the data.

### Consequences

**Positive:**
- Zero novel interaction vocabulary; discoverable in one tap.
- Selection, checkmarks, and edit transitions come from SwiftUI for free.

**Negative:**
- Edit mode + `NavigationLink` rows need care on iPhone (selection is
  edit-mode-only); verified on device.
- Bottom bar occupies space during edit mode.

---

## Decision 2: One batched store delete with a single change notification

**Date**: 2026-07-26
**Status**: accepted

### Context

Bulk and date-range deletes can span thousands of rows (LibreLinkUp glucose
backfills). Every existing delete method notifies `eventsDidChange` per call,
and every observer (Records, Trends, History) reloads on each tick. A loop of
per-id deletes would trigger thousands of reloads and thousands of write
transactions.

### Decision

Add `deleteRecords(mealIDs:eventIDs:)` to the store: one write transaction,
chunked `IN` deletes for event rows, per-meal side-table cascades, one
`eventsDidChange` notification when anything was deleted. Individual glucose
deletion gets its own `deleteBslEvent(id:)` mirroring the insulin/intake
single-row gates.

### Rationale

The store already owns transactional semantics and the notification
convention; batching there keeps observers dumb and the UI responsive. The
existing `mergeBslKeepFirst` fix (cgm-connect Phase 2) documents SQLite's
32,766 bound-variable cap — chunking the `IN` lists is the established
answer.

### Alternatives Considered

- **Loop per-id deletes in the model**: no store change — rejected: one
  notification and one transaction per row; a 10k-row purge would freeze the
  UI in reload storms.
- **A `deleteEvents(in: DateRange)` SQL-side range delete**: elegant for the
  range case — rejected: duplicates the range logic the model already has
  (rows are fully loaded, unwindowed by design), cannot serve
  selection-based bulk delete, and needs its own meal-cascade handling
  anyway.

### Consequences

**Positive:**
- One transaction, one notification, regardless of purge size.
- Meal cascades stay in one place, identical to `deleteMeal`.

**Negative:**
- Two new protocol requirements ripple into five test mocks (one-line no-ops)
  and the App-target FakeStore documentation contract.

---

## Decision 3: Glucose rows become deletable, superseding home-router Req 3.5

**Date**: 2026-07-26
**Status**: accepted

### Context

Home-router Req 3.5 made glucose rows read-only because import-sourced
readings "re-appear on the next import". The user now explicitly requires all
data to be purgeable in bulk, individually, and by date range — glucose
included.

### Decision

Enable glucose deletion everywhere (swipe, multi-select, range purge) via a
new `deleteBslEvent(id:)` gated on `event_type = bsl`. Req 3.5's rationale is
recorded as a known wrinkle, not a blocker: a reading deleted inside the live
polling window may re-ingest on the next poll.

### Rationale

Consistency across row types beats protecting the user from a re-ingest
edge case that only affects the most recent polling window. The dominant use
case is clearing history (developer/test data), where re-ingest does not
apply.

### Alternatives Considered

- **Keep glucose read-only, offer only a Settings-level bsl wipe**:
  preserves Req 3.5 — rejected: inconsistent affordances in one list and no
  date-range control.
- **Tombstone deleted readings so re-ingest skips them**: technically clean —
  rejected: new table and merge complexity for an edge the user does not
  care about; revisit only if re-appearing readings become a real annoyance.

### Consequences

**Positive:**
- One deletion model for every row type.

**Negative:**
- A just-deleted recent reading can reappear after the next live poll
  (undocumented in UI per the developer-phase copy rule; noted in
  `docs/agent-notes/persistence.md`).

---

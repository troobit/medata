# Records Deletion — Individual, Bulk, and Date-Range

## Overview
Deletion on the Records surface is one-at-a-time, inconsistent per row type
(glucose rows are delete-disabled), and the discoverable meal path is buried
in the meal overview's toolbar menu. This change makes the list the primary
deletion surface with the standard iOS patterns: swipe-to-delete on every row
type, edit-mode multi-select with Select All and a confirmed bulk delete, and
a confirmed date-range purge. Full findings in
`specs/ui/records-deletion/UI-IMPROVEMENTS.md` (2026-07-26 review).

## Requirements
- Every record row type (meal, insulin, glucose, intake) MUST support
  individual swipe-to-delete from the Records list. Swipe delete follows
  standard practice — the revealed Delete button is the confirmation; no
  extra dialogue.
- The Records list MUST offer an edit mode entered from a navigation-bar
  button: rows gain selection checkmarks, a bottom bar offers Select All /
  Deselect All (toggling by whether everything is selected) and a
  destructive "Delete (n)" action.
- Bulk deletion MUST present a confirmation dialogue naming the count before
  deleting, MUST delete in a single store transaction with ONE
  `eventsDidChange` notification, and on completion MUST clear the selection
  and exit edit mode.
- A "Delete by Date…" action MUST be reachable from the Records navigation
  bar, presenting From/To date pickers (defaulting to the earliest record and
  now), a live count of records in range, and a confirmed destructive delete
  routed through the same batched store path.
- A "Delete All Records…" action MUST sit beside "Delete by Date…" — a
  one-tap full-history purge behind a total-count-naming confirmation,
  through the same batched path. Clearing debug-era records must not require
  picker work: stale records would otherwise feed the meal-glucose
  regression suggestions (regression-suggestion-integration).
- Glucose deletion MUST be supported by a new `deleteBslEvent(id:)` store
  method gated on `event_type = bsl` (mirroring the insulin/intake gates).
  This supersedes home-router Req 3.5 (glucose read-only).
- The batched path MUST handle meal rows' cascades (events row, side tables,
  artefact directory) identically to `deleteMeal`, and MUST chunk SQL `IN`
  lists to stay under SQLite's bound-variable cap.
- No new reassurance/disclaimer copy (developer-phase copy rule). The
  confirmation dialogues carry only the action and count.

## Implementation Approach
- **`Persistence/PersistenceStore.swift` + `GRDBPersistenceStore.swift`** —
  add `deleteBslEvent(id: UUID)` (single-row, gated, notify once) and
  `deleteRecords(mealIDs: [UUID], eventIDs: [UUID])` (one write transaction:
  chunked `DELETE FROM events WHERE id IN (…)` for event rows regardless of
  type, per-meal side-table deletes for meal ids; artefact directories
  removed best-effort after commit; ONE notify when anything was deleted).
  The five MedataCore test mocks gain one-line no-op conformances
  (`MeData/Tests/MealHistoryModelTests.swift`'s FakeStore updated as a
  documentation contract).
- **`App/RecordsModel.swift`** — `delete(_:)` gains the glucose case;
  new `deleteBulk(_ rows: [RecordRow])` splitting meal ids from event ids
  into one `deleteRecords` call; `rows(in range: ClosedRange<Date>)` filter
  for the range sheet's live count and its delete.
- **`App/RecordsView.swift`** — `List(selection:)` over `RecordRow.id`
  (String), `@State editMode` + custom Edit/Done toolbar button, bottom bar
  in edit mode (Select All toggle + Delete (n) + confirmation dialogue),
  toolbar Menu with "Delete by Date…", and a colocated `DateRangePurgeSheet`
  (From/To `DatePicker`s, live count, confirmed delete). Glucose rows lose
  `.deleteDisabled(true)`. No new files, so no `project.pbxproj` edits.
- **Out of Scope:** the MealOverviewView menu path (stays as a secondary
  route) *(route since deleted by `specs/ui/home-router` Decision 16,
  2026-08-26: `MealOverviewView` is removed and its delete menu lives on
  ResultView, the one meal-detail surface)*; day-section headers; long-press
  context menus; any Trends/History changes (they follow via
  `eventsDidChange`).

## Risks and Assumptions
- **Risk:** `List(selection:)` plus `NavigationLink` rows — selection is
  edit-mode-only on iPhone, links keep working in browse mode (standard Mail
  pattern); verified on device.
- **Risk:** deleting a glucose reading inside the live LibreLinkUp polling
  window re-ingests on the next poll (keep-first merge probes incoming
  timestamps). Accepted: the use case is history purge, not single-reading
  suppression; no UI messaging (developer-phase copy rule).
- **Assumption:** the app-target build + on-device look is the test gate
  (CLAUDE.md); MedataCore gains no new pure-maths surface worth unit tests
  beyond the store methods, which follow existing tested patterns.

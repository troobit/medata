---
references:
    - specs/ui/records-deletion/smolspec.md
    - specs/ui/records-deletion/decision_log.md
---
# Records Deletion — Implementation Tasks

- [x] 1. Store: deleteBslEvent + batched deleteRecords
  - Add `deleteBslEvent(id: UUID)` to PersistenceStore + GRDBPersistenceStore: DELETE gated on `event_type = bsl`, notify `eventsDidChange` once (insulin/intake convention).
  - Add `deleteRecords(mealIDs: [UUID], eventIDs: [UUID])`: one write transaction; chunked `DELETE FROM events WHERE id IN (…)` (≤500 ids per statement) for event rows; per-meal `events`/`meal_artefacts`/`corrections` deletes; best-effort artefact-directory removal after commit; ONE notify when anything was deleted.
  - Update the five MedataCore test mocks with no-op conformances; update MeData/Tests FakeStore as a documentation contract.
  - Stream: 1
  - References: specs/ui/records-deletion/smolspec.md, MedataCore/Sources/Persistence/PersistenceStore.swift, MedataCore/Sources/Persistence/GRDBPersistenceStore.swift

- [x] 2. Model: glucose delete + bulk delete + range filter
  - `RecordsModel.delete(_:)` glucose case calls `deleteBslEvent`.
  - New `deleteBulk(_ rows: [RecordRow])` splitting meal ids from event ids into one `deleteRecords` call.
  - New `rows(in range: ClosedRange<Date>) -> [RecordRow]` for the range sheet's live count and delete.
  - Stream: 1
  - References: App/RecordsModel.swift

- [x] 3. View: edit-mode multi-select, Select All, date-range sheet
  - `List(selection:)` over `RecordRow.id`; Edit/Done toolbar button; bottom bar in edit mode with Select All / Deselect All toggle and destructive "Delete (n)" behind a confirmation dialogue naming the count; clear selection + exit edit mode after delete.
  - Toolbar Menu with "Delete by Date…" presenting the colocated DateRangePurgeSheet: From/To DatePickers (default earliest record → now), live in-range count, confirmed destructive delete via `deleteBulk`.
  - Remove `.deleteDisabled(true)` from glucose rows.
  - Stream: 1
  - References: App/RecordsView.swift

- [ ] 4. Verify: build, device look, docs
  - `make test` (both totals) + `make spell`; app builds for the device; on-device check of swipe, edit-mode bulk delete, and range purge.
  - Update `docs/agent-notes/persistence.md` (new store methods, re-ingest wrinkle) and `docs/agent-notes/ui-capture-flow.md`-adjacent records note if one exists.
  - Stream: 1
  - References: specs/ui/records-deletion/smolspec.md

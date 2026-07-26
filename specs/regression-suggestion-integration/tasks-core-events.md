---
references:
    - specs/regression-suggestion-integration/prd.md
---
# Insulin dose inflow (medreg integration) — Core events

## Event type and persistence

- [x] 1. Define EventType.insulin and InsulinDose value type (id, timestamp, units, kind bolus|basal, insulinType, note?) — PRD Core 1

- [x] 2. Save API writing one events row per medreg convention: value=units (REAL, non-negative), timestamp UTC ms, metadata {kind, insulin_type, schema_version:1, note?} with note absent when nil — PRD Core 2, 3

- [x] 3. Delete API for a single insulin event by id; save and delete both notify eventsDidChange; delete cannot touch meal/bsl rows or side tables — PRD Core 3

- [x] 4. Store-layer validation: reject units < 0 or > 60; 0 and 60 accepted at store — PRD Core 4

## Tests and verification

- [x] 5. PersistenceTests: round-trip raw-row/metadata-shape assertions, events(in:type:) filter incl. insulin, eventsDidChange ticks, bounds rejection — PRD Core acceptance

- [x] 6. Verify a store-written fixture SQLite loads in medreg (~/repos/medreg: make setup; load_events → frames.insulin matches units/kind/timestamp); record result in task notes, no committed cross-repo test — PRD Core 2 acceptance
  - Verified 2026-07-05: fixture meals.sqlite written by GRDBPersistenceStore.saveInsulinDose via a throwaway test (deleted after use); two doses — 6.5 U bolus/NovoRapid @ 1751000000000 ms (no note) and 18 U basal/Lantus @ 1751050000000 ms (with note)
  - Command: /Users/r/repos/medreg/.venv/bin/python -c 'from medreg.ingest import load_events; load_events(<fixture path>)' with assertions on frames.insulin
  - Result: PASS — both doses loaded; units/kind/timestamp/insulin_type/note/event_id all matched; note key absent (None) for the bolus dose
  - No changes committed to medreg; no cross-repo test added to medata

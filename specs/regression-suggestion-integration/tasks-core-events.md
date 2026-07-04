---
references:
    - prd.md
---
# Insulin dose inflow (medreg integration) — Core events

## Event type and persistence

- [ ] 1. Define EventType.insulin and InsulinDose value type (id, timestamp, units, kind bolus|basal, insulinType, note?) — PRD Core 1

- [ ] 2. Save API writing one events row per medreg convention: value=units (REAL, non-negative), timestamp UTC ms, metadata {kind, insulin_type, schema_version:1, note?} with note absent when nil — PRD Core 2, 3

- [ ] 3. Delete API for a single insulin event by id; save and delete both notify eventsDidChange; delete cannot touch meal/bsl rows or side tables — PRD Core 3

- [ ] 4. Store-layer validation: reject units < 0 or > 60; 0 and 60 accepted at store — PRD Core 4

## Tests and verification

- [ ] 5. PersistenceTests: round-trip raw-row/metadata-shape assertions, events(in:type:) filter incl. insulin, eventsDidChange ticks, bounds rejection — PRD Core acceptance

- [ ] 6. Verify a store-written fixture SQLite loads in medreg (~/repos/medreg: make setup; load_events → frames.insulin matches units/kind/timestamp); record result in task notes, no committed cross-repo test — PRD Core 2 acceptance

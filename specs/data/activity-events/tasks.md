---
references:
    - specs/data/activity-events/requirements.md
    - specs/data/activity-events/design.md
    - specs/data/activity-events/decision_log.md
---
# Activity Events

## Core

- [x] 1. Add `EventType.activity` and the activity value types to Persistence <!-- id:av1ktp0 -->
  - `EventType.activity = "activity"` alongside meal/bsl/insulin/intake, with the same comment convention naming this spec
  - `ActivityKind` (swim, waterpolo, cycle, run, walk, gym, other), `ActivityCharacter`, `ActivityProvenance`, `ActivityEvent` — shapes exactly as design.md section 1
  - `character` is a computed property over `kind`, never a stored field; the switch must be exhaustive over `allCases` so a new kind fails the build rather than defaulting
  - `durationMinutes` is `Double?` — nil is unrecorded, never 0
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3)

- [x] 2. Add the store surface — save, delete, and the lookback query <!-- id:av2mqr4 -->
  - `saveActivity`, `deleteActivityEvent`, `activities(before:within:)` on `PersistenceStore` and `GRDBPersistenceStore`, following `saveInsulinDose`/`deleteInsulinEvent` byte for byte in row handling
  - `value` carries duration minutes and is absent when nil; metadata JSON is schema_version/kind/provenance/note with note omitted when nil
  - `character` is NOT written to metadata — derivable from kind, and two sources of truth for the regression key is the defect this avoids
  - Lookback returns `(instant - interval, instant]` newest first; undecodable rows are dropped, matching TrendsModel's existing handling
  - Blocked-by: av1ktp0 (Add `EventType.activity` and the activity value types to Persistence)
  - Requirements: [1.3](requirements.md#1.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)

- [x] 3. MedataCore tests for encoding and lookback boundaries <!-- id:av3wsn8 -->
  - Round-trip save → `events(in:type:)` → decode; nil duration omits `value` and decodes back to nil not 0; nil note omitted from metadata
  - Lookback boundary: an event exactly at `instant - interval` is excluded, one exactly at `instant` is included
  - `character` mapping exhaustive over `ActivityKind.allCases`
  - MVP test gate: MedataCore only. Do NOT add app-target test scaffolding — `MeData/Tests` and `MeData/UITests` are documentation contracts, not an executable suite
  - Blocked-by: av2mqr4 (Add the store surface — save, delete, and the lookback query)
  - Requirements: [1.5](requirements.md#1.5), [2.2](requirements.md#2.2), [5.1](requirements.md#5.1)

## Entry

- [x] 4. `ActivityModel` and `ActivitySheet` <!-- id:av4hjd2 -->
  - Medium-detent `.sheet` modelled on `InsulinDoseSheet`/`InsulinDoseModel`, not a full-screen cover
  - Kind chips preselected to the most recently used kind via a new `SettingsKeys` entry, so a repeat activity is open → Save
  - Optional duration stepper, blank by default, blank saves nil and never blocks Save
  - Timestamp defaults to now with a control to move it — the one deliberate divergence from the dose sheet, because activity is logged after the fact
  - No intensity control, no effort rating, no calorie field
  - No reassurance, disclaimer, warning or coaching copy anywhere in the sheet
  - Register both new files in `project.pbxproj` (four sections — see the checklist in `docs/agent-notes/ui-capture-flow.md`)
  - Blocked-by: av2mqr4 (Add the store surface — save, delete, and the lookback query)
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [2.4](requirements.md#2.4), [4.4](requirements.md#4.4)

- [x] 5. Deep link `medata://activity/add` <!-- id:av5rfk6 -->
  - Added to the existing `CFBundleURLTypes` array in the partial `MeData/Info.plist` — it cannot be an `INFOPLIST_KEY_` build setting
  - Handled in `AppRoot.handleDeepLink`, inheriting the existing `pendingDeepLink` resume so arrival during a dismissing presentation is not silently dropped
  - Blocked-by: av4hjd2 (`ActivityModel` and `ActivitySheet`)
  - Requirements: [3.5](requirements.md#3.5)

## Display

- [x] 6. Graph day/week/month rendering <!-- id:av6zcx1 -->
  - Day: span mark from start to start+duration where a duration exists, point mark where it does not; own band below the insulin band, keyed off the same `glucoseAxisMax` fraction so it stays clear of the glucose plot under Auto and Fixed y-scales
  - Week/Month: per-day count x-aligned with the carbohydrate buckets via `TrendsMath.dailyBuckets`
  - New `Colors.swift` tokens distinct from both insulin series and the glucose trace
  - Must not obscure the glucose trace, carbohydrate bars or insulin band; no current-time RuleMark is to be added anywhere
  - Blocked-by: av2mqr4 (Add the store surface — save, delete, and the lookback query)
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2)

- [x] 7. Records row and swipe-to-delete <!-- id:av7bnv5 -->
  - Row carries kind label and duration; deletion by the same swipe the insulin rows use
  - Needs the `List`-inside-`ScrollView` treatment with a pinned height — without the height pin it collapses to zero
  - Blocked-by: av2mqr4 (Add the store surface — save, delete, and the lookback query)
  - Requirements: [3.6](requirements.md#3.6), [4.3](requirements.md#4.3)

## Gates

- [ ] 8. STOP — on-device entry pass on the iPhone 16 Pro <!-- id:av8qlm3 -->
  - Human verification, cannot be automated. Log a real activity from the deep link and from the Graph; confirm the two-tap repeat path, that a blank duration saves, and that the day view renders the span without obscuring the trace
  - Match `event=launch buildStamp=…` before trusting any device output
  - `make test` green (BOTH totals — XCTest and swift-testing), `make spell` clean
  - Blocked-by: av5rfk6 (Deep link `medata://activity/add`), av6zcx1 (Graph day/week/month rendering), av7bnv5 (Records row and swipe-to-delete)
  - Requirements: [3.1](requirements.md#3.1), [4.1](requirements.md#4.1)

- [x] 9. Regenerate the specs index <!-- id:av9tgh7 -->
  - `/specs-overview` so `specs/OVERVIEW.md` carries this spec
  - Blocked-by: av8qlm3 (STOP — on-device entry pass on the iPhone 16 Pro)

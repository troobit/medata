# PRD: Insulin dose inflow (medreg integration)

## Product summary

MeData records meals (carb estimates) and blood glucose (`bsl` events) in a single
SQLite `events` table. The sibling repository `~/repos/medreg` is a read-only
regression tool that fits insulin-dosing parameters from an exported copy of that
table. medreg already ingests three event types — `meal`, `bsl`, and `insulin` —
but MeData does not yet write `insulin` rows, so the regressions have nothing to
fit against.

This PRD adds insulin dosing as a first-class data inflow in MeData. The governing
constraint is speed of entry: if logging a dose is not fast and easy, the end user
will not do it and the regression data is worthless. Entry must therefore be a
two-tap happy path (open the dose sheet, save the 10 U bolus default), reachable
from the Graph root and from a lock-screen widget. Doses render on the Graph
alongside glucose and carbs. No confidence scores, no gating, no medical-safety
messaging — this is a developer-phase build used with clinicians, and medical
concerns are explicitly out of scope.

Target repository: `medata` (this repo). No changes to medreg — its
`docs/insulin-event-convention.md` is the contract MeData conforms to, and the
existing `exportArchive()` ZIP is the transport medreg already consumes.

## Goals

- Insulin doses are stored as `"insulin"` events conforming byte-for-byte to
  medreg's convention, so an exported archive loads in medreg with no adapter.
- Logging a dose takes two taps in the common case (default 10 U bolus, now).
- Doses are visible on the Graph in day, week, and month ranges without
  obscuring the glucose trace.
- Lock-screen widgets open the app directly into the dose-entry sheet and,
  via a second widget, directly into the Capture camera.
- The Graph chart carries no obstructive full-height current-time bar.

## Non-goals

- No dose suggestion, insulin-on-board, or regression maths in the app — medreg
  owns all modelling, off-device, against exported data.
  - Superseded in part, after this PRD shipped, by
    [`specs/data/insulin-dosing/decision_log.md`](../data/insulin-dosing/decision_log.md)
    Decision 1, "Reverse the 'no dose suggestion in the app' non-goal, narrowly":
    suggestion arithmetic and insulin-on-board now run on-device; parameter
    fitting does not, and `~/repos/medreg` remains the only place dosing
    parameters are estimated from history.
- No confidence scores, gating, warnings, reassurance, or disclaimer copy
  (developer-phase copy rule, CLAUDE.md).
- No changes to the medreg repository.
- No network calls, no HealthKit, no sync — the existing export archive remains
  the only outflow.
- No interactive dose adjustment on the lock screen — the widget is a launcher,
  not a form.
- No changes to the Data screen; dose management lives on the Graph day view.
- No i18n and no imperial units — insulin in units (U), glucose in mmol/L.

## Core events

Scope: `MedataCore/Sources/Persistence/` (PersistenceStore protocol,
GRDBPersistenceStore, TrendsMath if maths is needed) and
`MedataCore/Tests/PersistenceTests/`.

1. The core MUST define `EventType.insulin = "insulin"` alongside the existing
   `meal` and `bsl` constants, and an `InsulinDose` value type carrying id,
   timestamp, units (Double), kind (bolus | basal), insulin type (String), and
   an optional note.
   - Acceptance: `events(in:type: EventType.insulin)` returns saved doses and
     excludes meal/bsl rows; the existing type filter tests extend to the new type.
2. The core MUST persist a dose as one `events` row exactly per the medreg
   convention (`~/repos/medreg/docs/insulin-event-convention.md`, schema v3
   unchanged): `id` = UUID string, `timestamp` = administration time in UTC
   milliseconds, `event_type` = `"insulin"`, `value` = dose in units (REAL,
   non-negative), `metadata` = a JSON object with required keys `kind`
   (`"bolus"` or `"basal"`), `insulin_type` (free-text product string), and
   `schema_version` (integer `1`), plus optional `note`.
   - Acceptance: a round-trip test saves a dose and asserts the raw row's
     column values and metadata keys/types match the convention, including that
     `note` is absent (not null) when not provided.
   - Acceptance: a fixture SQLite file written by the store loads in medreg —
     `cd ~/repos/medreg && make setup` then `python -c` driving
     `medreg.ingest.load_events(path)` yields the dose in `frames.insulin` with
     matching units, kind, and timestamp. Run once during implementation and
     record the result in the task notes; this is a verification step, not a
     committed cross-repo test.
3. The core MUST provide a save API for insulin doses and a delete API for a
   single insulin event by id, both notifying `eventsDidChange`.
   - Acceptance: subscriber receives one tick per save and per delete; deleting
     an insulin event touches no side tables and cannot delete a meal or bsl row.
4. The core MUST reject saving a dose with units < 0 or > 60.
   - Acceptance: out-of-range saves throw; 0 and 60 are accepted at the store
     layer (the UI enforces its own floor).

## App UI

Scope: `App/` (new dose-entry sheet, TrendsView/TrendsModel, AppRoot, Settings)
plus registering new files and the URL scheme in `MeData/MeData.xcodeproj`.
Depends on Core events.

1. The app MUST present a dose-entry sheet from a dedicated, prominent control
   on the Graph toolbar (SF Symbol `syringe` or similar), presented as a sheet —
   not a full-screen cover — so it feels lighter than Capture/Data/Settings.
   - Acceptance: from a cold look at the Graph, one tap opens the sheet; the
     control has an accessibility identifier (`graph.insulin` pattern).
2. The sheet MUST open pre-filled with 10 units of bolus, timestamped now, with
   a single prominent save action, so the common case is exactly two taps.
   - Acceptance: open → save writes a 10 U bolus event at the current time and
     dismisses the sheet; the Graph refreshes via `eventsDidChange` without
     manual reload.
3. The sheet MUST show the dose as a large numeral flanked by large `+` and `−`
   controls. A tap steps 1 U. Press-and-hold repeats at roughly 4 steps/second,
   and after about 2 seconds of continuous hold accelerates (e.g. to 10
   steps/second) so reaching any value from 1–60 takes only a few seconds.
   - Acceptance: hold `+` from 10 and the value visibly accelerates after ~2 s,
     stopping hard at 60; hold `−` stops at 1; the save control is disabled only
     if the value could ever read 0 (floor is 1 U).
4. The sheet MUST offer a bolus/basal toggle (bolus default) and SHOULD offer a
   compact time adjustment for back-dating a forgotten dose; neither may add a
   tap to the happy path.
   - Acceptance: switching kind preserves the chosen units; a back-dated save
     stores the adjusted timestamp in UTC ms.
5. The app MUST fill `insulin_type` automatically from per-kind defaults stored
   in Settings (bolus default `"NovoRapid"`, basal default `"Lantus"`), editable
   as free text in a new Settings section; the sheet itself never asks for it.
   - Acceptance: doses saved after editing the Settings value carry the new
     string; the sheet contains no product-name field.
6. The Graph day view MUST render each dose as a discrete marker at its
   administration time with the unit count legible (the established CGM-app
   pattern: small glyphs with unit labels in a dedicated band along the bottom
   of the chart, clear of the glucose trace), with bolus and basal visually
   distinct. Week and month views MUST show per-day insulin (total units per
   day) in the same band.
   - Acceptance: a logged dose appears on all three ranges; markers never
     overlap the glucose line's plot band; colours are distinguishable from the
     glucose and carb series.
7. The chart MUST NOT draw a full-height vertical current-time bar or line in
   any range. Any current-time affordance, if kept at all, is at most a subtle
   tick at the axis edge.
   - Acceptance: visual check on device across day/week/month shows no vertical
     rule at the current time. Note: as of writing, no `RuleMark` or
     current-time mark exists in `App/TrendsView.swift` (lineage f090898) — if
     none is found, verify on the deployed build that the reported obstruction
     is not produced elsewhere in the chart and record what was (or was not)
     found; do not add one.
8. The Graph day view MUST list the day's doses (time, units, kind) in a
   section alongside the existing Meals list, with swipe-to-delete so a
   fat-fingered entry can be removed immediately.
   - Acceptance: deleting a row removes the event and the chart marker in the
     same refresh.
9. The Graph SHOULD gain an "Insulin" metric chip (toggle, matching the
   Carbs/Glucose chips) and an insulin stat card (total units for the selected
   range).
   - Acceptance: toggling the chip hides/shows the dose markers; the stat card
     shows summed units.
10. The app MUST register a custom URL scheme and handle two deep links:
    `medata://insulin/add` presents the dose-entry sheet, and
    `medata://capture` opens the Capture cover — each from any state,
    dismissing other covers if needed.
    - Acceptance: `xcrun simctl openurl` (or on-device tap) with each URL lands
      on the dose sheet / the Capture screen within one screen transition.

## Lock screen widget

Scope: a new WidgetKit extension target in `MeData/MeData.xcodeproj` (new
directory, e.g. `MeDataWidgets/`). Depends on App UI (the deep link) and edits
the same `project.pbxproj` — MUST run after App UI, never in parallel with it.

1. The project MUST gain a widget extension providing TWO widget kinds, each
   with lock-screen accessory families (`accessoryCircular` and
   `accessoryRectangular`): a dose widget whose tap opens the app via the
   dose-entry deep link (`medata://insulin/add`), and a capture widget whose
   tap opens the Capture camera (`medata://capture`). Lock-screen accessory
   widgets carry a single tap target each, which is why these are separate
   kinds the user places side by side.
   - Acceptance: the extension builds and embeds in the app product; both
     widgets appear in the lock-screen widget gallery; tapping each opens its
     screen (dose sheet / Capture).
2. Both widgets MUST be static launchers: a glyph plus a short label (syringe
   "Log dose"; camera "Capture"), no data display, no App Group, no timeline
   beyond a single static entry.
   - Acceptance: widget code contains no persistence imports and no shared
     container; `Timeline` policy is `.never`.
3. Both widgets SHOULD also offer a `systemSmall` home-screen family with the
   same behaviour.
   - Acceptance: the same deep links fire from the home-screen widgets.

## Execution notes

- Quality gates, via the repo-root Makefile: `make build` and `make test`
  (report BOTH totals — XCTest and swift-testing), `make spell` before
  committing any docs/strings. The iOS app builds with `make build-app`;
  on-device check with `make deploy-device DEVICE_UDID=6AD781BA-89FF-5A82-A2A1-B5EC9469F465 DEVICE_NAME=you`
  (Makefile defaults still point at the old phone).
- Test gate is MVP-minimal (CLAUDE.md): new unit tests belong ONLY in
  `MedataCore/Tests/PersistenceTests/` for the Core events context. App and
  widget work is verified by build + on-device look; do NOT create UI-test or
  app-test targets, and never claim to have run files under `MeData/Tests/`.
- Ordering: Core events → App UI → Lock screen widget. App UI consumes the new
  store API; the widget consumes the deep link; App UI and the widget both edit
  `project.pbxproj`, so they must not run concurrently.
- New `App/*.swift` files must be registered in
  `MeData/MeData.xcodeproj/project.pbxproj` (files are referenced in place as
  `../App/*.swift` — follow the existing `ShutterButton.swift` entries; see
  `docs/agent-notes/ui-capture-flow.md`).
- The insulin event contract is medreg's
  `~/repos/medreg/docs/insulin-event-convention.md`; medreg's parsing source of
  truth is `~/repos/medreg/src/medreg/insulin.py`. Consumers ignore unknown
  metadata keys; do not add keys beyond the convention.
- Metric only (units of insulin,
  mmol/L); no reassurance/disclaimer copy anywhere in the new UI.
- Estimation path is untouched; nothing here may call the network or an LLM.

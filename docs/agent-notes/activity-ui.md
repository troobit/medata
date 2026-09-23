# Activity UI (App/)

`specs/data/activity-events` — the App side. Activity is the fifth event type
in the `events` table; the core API (`EventType.activity`, `ActivityEvent`,
`saveActivity`, `deleteActivityEvent`, `activities(before:within:)`) lives in
MedataCore Persistence, see `persistence.md`. This note covers entry, display
and the deep link only.

## Architecture

- **`ActivityModel`** (`@Observable @MainActor`) owns the entire entry state —
  kind, optional duration, timestamp, save — and both sheet layouts are pure
  views over it. `durationMinutes` is `Double?`: nil is UNRECORDED and is
  never written as 0 (Req 1.5), so every display path must render nothing
  rather than "0 min". Save writes `provenance: .manual` and, only on
  success, stores the kind's raw value under `SettingsKeys.activityLastKind`
  so the next open preselects it (Req 3.3, the two-tap repeat path).
- **`ActivitySheet`** is a plain medium-detent `.sheet`, the same weight as
  `InsulinDoseSheet`, presented from `AppRoot` (not from the Graph — the
  Graph stayed visualisation-only, home-router Req 2.3). It is raised by the
  home **Activity** control and by `medata://activity/add`.
- **`ActivityKind.displayLabel` / `.symbolName`** are an App-side extension in
  `ActivityModel.swift`. The enum's raw values are STORAGE keys (Req 1.4) and
  must never be shown to the user or parsed back from a label.
- **TrendsModel** loads `activity` rows in the same `reload()` the
  `eventsDidChange` subscription drives and decodes `kind` out of the metadata
  JSON (undecodable rows are dropped, as insulin rows are). Day markers carry
  `end` where a duration exists; Week/Month markers carry a per-day **count**
  from `TrendsMath.dailyBuckets`.
- **RecordsModel** has its own copy of the same decoder — deliberately
  duplicated per model (home-router Decision 13), not shared.

## Gotchas / non-obvious behaviour

- **Week/Month aggregate a COUNT, never a minutes total.** An unrecorded
  duration is absent, so summing minutes across a week silently under-reports
  every day whose activities carried no duration. `TrendsBucket.count` is the
  honest aggregate; the sample values are a constant 1 and mean nothing.
- **There is no room for the activity band *below* the insulin band**, which
  is what `design.md` §4 asks for. The chart floor is 0 and insulin sits at
  `glucoseAxisMax * 0.04` — about 10 pt off the axis on the 260 pt chart — so
  a lane beneath it has ~5 pt of clear space and the glyphs collide. The
  marker-lane attempt sits at `0.16` instead: above insulin and its unit
  annotations, still far below the glucose plot band (3.9+ mmol/L), which is
  the separation the design was actually protecting (Req 4.1).
- **`CFBundleURLTypes` registers SCHEMES, not links.** `medata://activity/add`
  needed NO new array element in `MeData/Info.plist` — it arrives through the
  existing `medata` entry and is told apart by host and path in
  `AppRoot.handleDeepLink`. The task file expected an array edit; only the
  comment changed.
- **Two entry sheets means every deep link must dismiss the other one.**
  `AppRoot` now owns `showInsulinSheet` AND `showActivitySheet`; presenting a
  sheet while another is animating out is silently dropped, so each link parks
  its target in `pendingDeepLink` and the dismissing surface's `onDismiss`
  resumes it. Adding a third sheet means touching all four resume switches.
- **The Graph's Day Activity list is a `List` inside the ScrollView with a
  pinned height** (`rowCount × doseRowHeight`), copied from the Insulin
  section — without the pin it collapses to zero. That list is read-only;
  deletion lives on Records, by the same swipe the insulin rows use.
- Both files need no `project.pbxproj` entry: `App/` became a synchronised
  group on 2026-08-28 (docs/agent-notes/ui-capture-flow.md).

## Design attempts on the device

Four tags, two pairs, per the tagging convention in
`device-build-and-test.md`. Each is one commit and claims nothing beyond
"this is what that attempt was":

| Tag | What it tries | What it trades |
|---|---|---|
| `activity-sheet-attempt-1` | Scrolling chip row + ±5-minute stepper — the dose sheet's idiom verbatim | Kinds run off the right edge; 45 min is nine taps |
| `activity-sheet-attempt-2` | 4×2 icon-tile grid + one-tap duration presets | No arbitrary duration; more vertical space on kinds |
| `activity-graph-attempt-1` | A marker lane at 16% of the y-max: rounded rule for a duration, dot without one | Says when and how long, nothing else; overlapping activities draw on top of each other |
| `activity-graph-attempt-2` | The active period as a shaded full-height column behind the plot | Loses the per-day count on Week/Month; a busy day tints most of the chart |

The graph pair differs in the sheet layout as well (attempt-2 of the sheet
landed first), and the sheet pair differs in whether the graph/records work is
present. Neither confound touches the surface being compared.

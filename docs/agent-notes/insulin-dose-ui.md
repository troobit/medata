# Insulin dose UI (App/)

PRD `specs/regression-suggestion-integration/` (App UI context). Insulin doses
flow in through a dose-entry sheet on the Graph and render as a bottom band on
the chart. The core API (EventType.insulin, `InsulinDose`, `saveInsulinDose`,
`deleteInsulinEvent`) is in MedataCore Persistence — see `persistence.md`.

## Architecture

- **`InsulinDoseModel`** (`@Observable @MainActor`) owns the stepper state and
  save. Hold-to-repeat timing is the pure seam
  `repeatSteps(afterHold:)`: 0 repeats until 0.4 s, then ~4 steps/s, then
  ~10 steps/s after 2 s of hold. `beginHold` fires the tap step immediately
  and a 50 ms polling Task applies whatever the schedule says is due — the
  view never owns timing. UI floor is 1 U, hard stop 60 U (the store accepts
  0–60; the floor keeps a save from ever reading 0).
- **`LogSheet`** (the Decision 16 merge, see below) consolidates the three
  entry sheets: insulin, activity and carbohydrate entry are modes of one
  sheet whose title is the mode menu, with `EntryChrome` holding the shared
  time row, save button and chips. `InsulinDoseSheet.swift` now hosts only
  the insulin mode's content; chrome (title, detent, dismissal) belongs to
  `LogSheet`, presented from `AppRoot`. The sheet stays a plain `.sheet`
  (medium detent) — deliberately lighter than the Capture/Data/Settings
  full-screen covers. The +/− controls use
  `onLongPressGesture(minimumDuration: .infinity, …, onPressingChanged:)` so
  tap and hold share one press-down/press-up code path. No product-name
  field: `insulin_type` fills at save time from per-kind Settings defaults
  (`SettingsKeys.insulinTypeBolus/Basal`, defaults NovoRapid/Lantus; empty or
  whitespace falls back to the default).
- **`DoseSuggestionModel`** computes the suggestion from the merged `Dosing`
  target and writes real `dose_suggestions` rows via `saveDoseSuggestion` /
  `linkDose` (no in-memory ledger survives the merge). The history surfaces
  (`MealOverviewView`, `ResultView`) read a meal's recorded suggestion back
  via `doseSuggestion(forSourceEventID:)` and render it as the read-only
  `suggested 12 U · 5 g/U (· given 14 U)` line
  (`specs/data/insulin-dosing/requirements.md` Req 6.10).
- **TrendsModel** loads insulin via `events(in:type: EventType.insulin)` in
  the same `reload()` the `eventsDidChange` subscription drives, decoding
  `kind` from the metadata JSON (rows that fail to decode are dropped).
  Week/Month markers reuse `TrendsMath.dailyBuckets` (empty days filtered),
  x-aligned with the carb bars' buckets.
- **Deep links** (CFBundleURLTypes in `MeData/Info.plist`, handled in
  `AppRoot.onOpenURL`): `medata://insulin/add` presents the dose sheet;
  `medata://capture` opens the Capture cover. Both land from any state — the
  lock-screen widgets (next context) are single-tap launchers to these URLs.

## Gotchas / non-obvious behaviour

- **The chart's x-domain must stay pinned.**
  `.chartXScale(domain: model.interval.start...end)` was added because the
  default domain collapses to the data extent: a single meal in the Day range
  rendered as one enormous centred BarMark (automatic width = plot width ÷
  mark count) at its timestamp ≈ "now" — this was the reported "obstructive
  current-time bar". There is NO current-time RuleMark anywhere and none
  should be added (PRD App 7). Day-range carb bars also use
  `width: .fixed(6)`.
- **Swipe-to-delete needs a List**, so the Day-view Insulin list is a
  `List` embedded in the Graph's ScrollView: `.scrollDisabled(true)`,
  `.scrollContentBackground(.hidden)`, height pinned to
  `rowCount × defaultMinListRowHeight`. Without the height pin it collapses
  to zero inside the ScrollView.
- **Deep link vs presentations**: presenting while another presentation is
  animating out is silently dropped, so `AppRoot.handleDeepLink` records a
  `pendingDeepLink` target and resumes it on dismissal completion — the
  cover's `onDismiss` (a cover was up), or TrendsView's
  `onInsulinSheetDismiss` closure (the dose sheet was up when
  `medata://capture` arrived). TrendsView likewise drops its options sheet
  when the insulin binding turns true.
- **CFBundleURLTypes cannot be an `INFOPLIST_KEY_` build setting** — it lives
  in the partial `MeData/Info.plist` (already merged with the generated plist
  for the build stamp).
- Insulin band y = `glucoseAxisMax * 0.04` keeps glyphs just above the axis
  under both Auto and Fixed y-scales, clear of the glucose plot band
  (3.9+ mmol/L). Colours: bolus teal circle, basal purple square, Week/Month
  aggregate teal diamond (`Colors.swift` seriesInsulinBolus/Basal).
- New files `InsulinDoseModel.swift` / `InsulinDoseSheet.swift` are
  registered in `project.pbxproj` (four sections — see the checklist in
  `ui-capture-flow.md`).

## The three dose-suggestion attempts (decided — Decision 16 synthesis)

The verdict is taken: `specs/data/insulin-dosing/decision_log.md` Decision 16,
"The attempt verdict — attempt 3's consolidation as the base, attempt 2's
reach ported onto it". No single attempt won; the synthesis is **merged on
`research`** and the tags below remain as archive per the attempt convention
(`device-build-and-test.md`, "Comparing UI attempts on the phone") — reachable
history, not unmerged work.

What merged: attempt 3's App layer as the base (`LogSheet` in three modes,
`EntryChrome`, its `DoseSuggestionModel`, its seven `SettingsKeys`), with
attempt 2's reach ported on top — `DoseReadoutLine` (`MiddleDotLine` /
`MealTotalSecondLine`), the readout on the review line and the manual entry
line, the dose sheet's provenance caption consumed by the first press, and a
seed that is actually consumed. Attempt 3's documented ledger stub was
replaced with the real `saveDoseSuggestion` / `linkDose` wiring. Attempt 1 was
rejected outright — the seed it armed on Record was never consumed
(`takeSeed()` had no caller), which under the everywhere-readable bar is "the
gap, not the restraint" (Decision 16).

What the losers traded away (Decision 15's contract): nothing, in all three
cases. Attempt 1's seven-character review segment "survives verbatim inside
attempt 2's `MealTotalSecondLine` shed order"; attempt 2's readout components
and provenance caption ported whole; attempt 3's `LogSheet`/`EntryChrome`
landed unchanged. What remains device-judged sits inside task 16's on-device
STOP: chiefly design-direction §10's open question — bare `12 U` versus
`12 U at 5 g/U` on the review line. The merged build ships the data-forward
branch, so without an explicit device verdict at task 16 that choice "becomes
the winner by inertia" (Decision 16).

The descriptions below record what each attempt was.

| | Branch | Tag (replay 2) | Sha |
|---|---|---|---|
| 1 | `insulin-dosing-ui-1-on-research` | `insulin-dosing-ui-attempt-1-on-research-3` | `ff9d29f` |
| 2 | `insulin-dosing-ui-2-on-research` | `insulin-dosing-ui-attempt-2-on-research-3` | `e0373bd` |
| 3 | `insulin-dosing-ui-3-on-research` | `insulin-dosing-ui-attempt-3-on-research-3` | `26af5f9` |

All three were replayed on `006606f`, then carried the demo-meal commit
`a1618ee`, and all three build clean. Every earlier tag —
`insulin-dosing-ui-attempt-{1,2,3}` and its `-on-research` / `-on-research-2`
replays — stays where it is; those trees no longer build against current
`research`.

All three share the same spine: a `DoseSuggestionModel` in `App/` reading the
merged `Dosing` target, a readout on the meal-review second line and on the
manual intake path, and ratio/increment rows in Settings. What they disagree
about is how far the suggestion reaches past that line.

**Attempt 1 — the readout, and nothing else.** Eight files. The suggestion is
seven characters appended to a line that already exists: `≈ 214 g on plate ·
12 U`, one font, one colour, `ViewThatFits` shedding `on plate`, then the `≈`,
then the mass, never the dose. Nothing else on any screen changes. It arms a
seed on Record but **never consumes one** — `takeSeed()` has no caller — so the
dose sheet still opens at the standing 10 U and the number is retyped by hand.
Decision 16 judged that the gap, not the restraint.

**Attempt 2 — the readout, plus the surfaces it implies.** Seventeen files as
written; the replay dropped its private activity implementation (see below), so
what is left is `DoseReadoutLine` as a reusable view, the same readout on all
three entry paths, and the dose sheet's provenance caption — `from 60 g at
5 g/U`, restating the carbohydrate figure precisely because the sheet is the one
surface where the source number is off screen. The caption is consumed by the
first press on `+`/`−`, not by the first change of value: `step` clamps at 1 and
60, so an observer on `units` would silently fail to fire at either bound. This
is the only attempt that seeds the sheet AND says where the seed came from.

**Attempt 3 — one `LogSheet` in three modes.** Fourteen files. It reads the
suggestion as evidence that the app was about to grow a third near-identical
entry sheet, and consolidates instead: insulin, activity and carbohydrate entry
become modes of one sheet whose TITLE is the mode menu, with `EntryChrome`
holding the shared time row, save button and chips. Zero added height, every
entry point still names its own mode, so the menu is a way out of a wrong turn
rather than a step on the way in. It is the largest bet — it changes surfaces
the dose suggestion has no business changing — and its own header admits the
carbohydrate mode fits the grammar least well.

### What the replays dropped

Attempts 2 and 3 were written before `activity-events` merged, so both carried
their own activity types, model and sheet. Research now ships a different
implementation of exactly that. Both replays take research's — attempt 2's
`App/ActivityTypes.swift` is deleted outright and its Graph/Colors/TrendsModel
changes reverted; attempt 3 keeps its consolidation claim by having `LogSheet`
absorb research's `ActivitySheet` (deleted) and rebinding its `ActivityContent`
to research's `ActivityModel`. Neither replay is a transcription, and neither
attempt should be read as still proposing an activity design.

Attempt 2 also wrote its suggestion rows through an in-memory
`InMemoryDoseLedger`; the merge replaced that with the real
`saveDoseSuggestion`/`linkDose` calls (Decision 16), so rows land in
`dose_suggestions` from the first merged build.

### Judging the merged tree (task 16)

Task 8 in `specs/data/insulin-dosing/tasks.md` closed with the Decision 16
verdict; tasks 9–15 unblocked against the merged layer. What survives as an
on-device judgement is task 16's STOP — the synthesis tree is a shape no phone
had displayed at merge time, and it includes design-direction §10's `12 U`
versus `12 U at 5 g/U` choice on the review line.

The two DEBUG affordances from `a1618ee` remain the way to get the surface on
screen: **Settings → Seed demo meal** writes one fixed 56.0 g record, and
**Records → that meal → ⋯ → Review** opens the review surface on it without a
capture. The path to judge in full is seed → Review → Record → open the dose
sheet: the readout on the review line, the seeded opening value and its
provenance caption, and the consolidated `LogSheet`. The manual path — Intake
→ carb entry — needs no seed at all. Mechanism and its Release exclusion:
`device-build-and-test.md`, "Getting the surface on screen without a capture".

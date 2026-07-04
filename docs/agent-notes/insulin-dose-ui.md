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
- **`InsulinDoseSheet`** is a plain `.sheet` (medium detent) presented by
  TrendsView — deliberately lighter than the Capture/Data/Settings
  full-screen covers. The +/− controls use
  `onLongPressGesture(minimumDuration: .infinity, …, onPressingChanged:)` so
  tap and hold share one press-down/press-up code path. No product-name
  field: `insulin_type` fills at save time from per-kind Settings defaults
  (`SettingsKeys.insulinTypeBolus/Basal`, defaults NovoRapid/Lantus; empty or
  whitespace falls back to the default).
- **TrendsModel** loads insulin via `events(in:type: EventType.insulin)` in
  the same `reload()` the `eventsDidChange` subscription drives, decoding
  `kind` from the metadata JSON (rows that fail to decode are dropped).
  Week/Month markers reuse `TrendsMath.dailyBuckets` (empty days filtered),
  x-aligned with the carb bars' buckets.
- **Deep link**: `medata://insulin/add` (CFBundleURLTypes in
  `MeData/Info.plist`) is handled in `AppRoot.onOpenURL`. AppRoot owns the
  sheet binding so it can present from any state.

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
- **Deep link vs covers**: presenting a sheet while a fullScreenCover is
  animating out is silently dropped, so `AppRoot.handleDeepLink` sets
  `pendingInsulinSheet` and presents from the cover's `onDismiss`. TrendsView
  likewise drops its options sheet when the insulin binding turns true.
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

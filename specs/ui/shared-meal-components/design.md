# Design: Shared Meal Components

## Shape

Three new shared files under `App/` (each registered in `project.pbxproj` in the four places
— `docs/agent-notes/ui-capture-flow.md` checklist), plus adoption edits in the consuming
views. Extraction only: every body is lifted from the surface that currently renders it best
and parameterised, not redesigned.

| New file | Contents | Consumed by |
|---|---|---|
| `App/ServingRows.swift` | `PlateFraction` (moved from `ResultView.swift`), `PlateFractionControl`, `ServingAmountButton`, `GramEditor`, `StepButton`, `ServingStepLogic` (`step(_:direction:)` + `clampedRowGrams`) | `MealReviewView`, `ResultView` |
| `App/MealReadouts.swift` | `MealPalette`, `CarbAmountText` (numeral + `g carbs` pair), `CorrectedMarker`, `RecordedSuggestion.line`, `MealPhotoLoader` (relocated from the retired `MealHistoryModel.swift`) — containers stay per-surface (Decision 3) | `MealReviewView`, `ResultView`, `RecordsView` (marker) *(Redefined in place by Decision 4 — `specs/ui/home-router` Decision 16 deletes `MealOverviewView`. Superseded wording: "`MealOverviewView`, `MealReviewView`, `ResultView`, `RecordsView` (marker)")* |
| `App/SharedFormatting.swift` | `MedataFormat.timeString(_:)` / `.dateTimeString(_:)` over cached `en_IE` formatters; `MedataFormat.prettify(_:)`; `TimelineRow` layout (glyph 20 pt frame, headline/caption stack, trailing content) | `RecordsView` rows, `IntakeView.entryRow`, `GlucoseConnectionsView`, `EstimationLogView`, `TrendsView` *(Redefined in place by Decision 4 — `specs/ui/home-router` Decision 16 deletes `MealOverviewView`. Superseded wording: "`RecordsView` rows, `IntakeView.entryRow`, `MealOverviewView`, `GlucoseConnectionsView`, `EstimationLogView`, `TrendsView`")* |

The carb-amount form (Req 2) does not need a fourth file: `LogSheet.CarbEntryContent`
(arriving with the insulin-dosing Decision 16 synthesis) becomes the single body, and
`QuickPresetEditSheet` consumes the same `CarbAmountFields` view extracted inside that file.

## State seams

- **Serving rows.** The component is stateless over `(classId, grams, serving)` plus
  callbacks `onStep(direction)`, `onCommitGrams(Double)`. `MealReviewView` maps callbacks to
  `model.setAmount`; `ResultView` maps them to its `pendingGrams` dictionary and
  `PbUserCorrection` append. The shared `@State` trio (editing class id, edit text, focus)
  moves into the component; the keyboard `Done` toolbar stays per-surface because toolbar
  placement is owned by the screen.
- **Carb total.** `CarbTotalBlock(palette:numeralSize:secondaryLine:)` where `palette` picks
  `captureChromeText`-family or `textPrimary`-family styles (under
  `specs/ui/unified-dark-theme` both resolve on black; the parameter preserves the token
  provenance per surface). The `secondaryLine` slot takes the existing mass line or the
  `MealTotalSecondLine` dose readout, which is how Req 3.3's "only through the shared line"
  is structural.
- **Timeline rows.** `TimelineRow(glyph:tint:)` with `@ViewBuilder` headline/detail/trailing
  slots; the five Records row structs keep their names and data decoding, and shrink to
  slot-fillers.

## Ordering against the other in-flight work

1. The insulin-dosing Decision 16 synthesis merge lands first (it brings `EntryChrome`,
   `LogSheet`, `DoseReadoutLine`).
2. Then this extraction, so the dose segment and mass line are written into the shared
   `CarbTotalBlock` once, not stitched into three views and then extracted.
3. `specs/data/manual-carb-intake` tasks 12–18 (save-as-quick-add) build on the extracted
   components — the two menu items land on surfaces already consuming shared chrome.

## Removals

- `App/MealHistoryModel.swift` + its four pbxproj entries (Req 6.2). The
  documentation-contract tests referencing it (`MeData/Tests/MealHistoryModelTests.swift`)
  are removed with it — they document a component that no longer exists; no committed target
  compiles them (`docs/agent-notes/ui-capture-flow.md` convention).
- The per-view `DateFormatter` helpers, `prettify` copies, `correctedMarker` copies,
  duplicated serving-editor blocks, and `QuickPresetEditSheet`'s private field bodies, each
  replaced by the shared implementation at its call site.

## What is deliberately NOT extracted

- `TrendsModel` decoders and anything else in the Graph's perf-sensitive file (home-router
  Decision 13; `specs/bugfixes/graph-month-selection-hang/`).
- The corrections-overlay observation loop (three sites) — an async `for await` loop whose
  lifetime is owned by each view's `.task`; sharing it means sharing task lifetime, which is
  behaviour, not rendering. Recorded as Decision 2.
- `ConfidenceLevel` / `CalibrationBannerState` / `ResultFormat` stay declared in
  `ResultView.swift` — cross-file reads are ugly but inert, and moving them is churn with no
  coordination story. Candidates for a later pass if a fourth consumer appears.

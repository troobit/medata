# Shared meal components and the unified dark theme (App/)

Two specs landed together on 2026-08-25: `specs/ui/shared-meal-components`
(the extraction) and `specs/ui/unified-dark-theme` (one dark presentation).
Read this before touching any meal surface.

## The dark theme is one plist key

`MeData/Info.plist` sets `UIUserInterfaceStyle = Dark` — the WHOLE mechanism.
No view carries `.preferredColorScheme`, and none should gain one. Under dark
resolution `.systemGroupedBackground` (`surfacePrimary`) is `#000000`,
identical to `captureBackground`, and `.secondarySystemGroupedBackground`
(`surfaceElevated`) is `#1C1C1E`, so the OLED capture family and the grouped
family converge without any view changing tokens. Keep the grouped tokens
semantic (never hard-code the dark values) — a future light theme is a
one-line revert, and that revertibility is why the indirection survives.
Do not add appearance-variant assets or `colorScheme` reads; either would
silently pin to one branch.

## The shared files

| File | Holds | Gotchas |
|---|---|---|
| `App/ServingRows.swift` | `PlateFraction` (moved out of `ResultView`), `ServingAmountButton`, `ServingGramEditor`, `ServingStepButton`, `PlateFractionButton`, `ServingStepLogic` (step arithmetic, 4-digit/5000 g keypad clamp) | Stateless over callbacks: review routes to `MealReviewModel.setAmount`, result to its `pendingGrams` dict + `PbUserCorrection`. Accessibility ids are parameterised by full row prefix (`result.row.<id>` / `review.row.<id>`) and must stay byte-identical. Step targets converged on 44 pt deliberately (Req 1.4). |
| `App/MealReadouts.swift` | `MealPalette`, `CarbAmountText`, `CorrectedMarker`, `RecordedSuggestion.line`, `MealPhotoLoader` (relocated from the retired `MealHistoryModel.swift`) | The CONTAINER layouts stay per-surface (Decision 3) — do not try to unify the three total blocks into one view; the shared unit is the content. |
| `App/SharedFormatting.swift` | `MedataFormat.dateTimeString` / `.clockString` (cached `en_IE` formatters), `MedataFormat.prettify`, `TimelineRow` (glyph 20 pt / headline / timestamp / footer / trailing) | The five Records rows and `IntakeView.entryRow` are slot-fillers over `TimelineRow`; a new record type should be too. `EstimationLogView`'s machine-format `fileStamp` is deliberately NOT here (en_US_POSIX filename format, not user copy). |
| `App/CarbEntrySheet.swift` | Also hosts `CarbAmountField` + `MacroDisclosure`, shared with `QuickPresetEditSheet` | The preset sheet passes `sourceMealID` through an edit untouched (Req 8.9) — it reconstructs the `QuickPreset`, so a new field must be added to that pass-through or edits silently drop it. |

`MealHistoryModel` is gone (was test-only dead code); `DisplayMeal` now lives
in `App/MealRouting.swift` beside `quickPresetDraft` and the route plumbing.

## What stays duplicated, on purpose

The corrections-observation loop (`MealOverviewView` / `ResultView` /
`RecordsModel`) and `TrendsModel`'s decoders — shared-meal-components
Decision 2 and home-router Decision 13 (perf-hang file). Do not extract them.

## Dose readout wiring (insulin-dosing Decision 16 synthesis)

`DoseSuggestionModel` (AppRoot-owned, environment-injected, optional in every
consumer so history routes render without it) computes via the pure `Dosing`
target, writes a real `dose_suggestions` row on every refresh (INSERT OR
REPLACE on a per-subject stable id), and arms a 45-minute `DoseSeed` carrying
the row id. `AppRoot.presentInsulinSheet` consumes the seed; on insulin save
the two-parameter `onInsulinSaved` links the dose back via `linkDose`. Live
readouts: `MealTotalSecondLine` (review), the CarbEntryContent secondary line;
history surfaces render `RecordedSuggestion.line` from the stored row — never
a recomputation (Req 6.11). The remaining device judgement is insulin-dosing
task 18's STOP, including design-direction §10's bare `12 U` vs
`12 U at 5 g/U`.

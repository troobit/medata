# UI Design Handoff 00 — Design

**Version:** 0.3 (post second critic pass)
**Date:** 2026-07-04
**Requirements:** `requirements.md` v0.4

## Overview

Reskin-in-place adoption of handoff 00 (Decision 11): the TabView shell is removed, the existing `CaptureFlowModel` state machine stays, and screens are rebuilt in `App/` against design-system pages. The scaffold at `tmp/design/design_handoff_medata/MedataApp/` is layout reference only. Two scoped MedataCore/pipeline additions support the UI: persisted mask artefacts (Decision 15) and `bsl`/palette-colour/notification plumbing (Decisions 13, 16, 18).

## Architecture

### Shell change (Req 1)

`CaptureFlowView` already owns a `NavigationStack(path: $model.navigationPath)` — the shell change removes the TabView around it:

| Site | Today | After |
|---|---|---|
| `App/AppRoot.swift` | `TabView`, `@AppStorage("selectedTab")` | Hosts `CaptureFlowView` + one `.fullScreenCover(item: $activeSheet)` (Decision 19 — full screens, not sheets) where `enum ActiveSheet: Identifiable { case data, trends, settings }` — a single optional, so surfaces are mutually exclusive by construction. Each surface carries an explicit close control (xmark, accessibility `Close`) since full-screen covers have no drag-to-dismiss. Buttons in the capture chrome set it via closures passed into `CaptureFlowView` |
| `App/AppTab.swift` | Tab enum | **Deleted** (with it, the `-uitestResetSelectedTab` launch override in `App.swift`) |
| `CaptureFlowModel.tabSelectionChanged(to:)` | Stops/starts AR per tab | Renamed: `sheetDidPresent()` (stop session ≤200 ms; `.estimating` lets pipeline finish) / `sheetDidDismiss()` (`evaluatePermissions()` → re-arm). Same bodies. Satisfies Req 1.5; single-item sheet state means dismiss-then-present is sequential, so the AR session never double-toggles |
| `scenePhaseChanged` | — | Unchanged |
| `ShutterButtonMetrics.bottomClearanceFromTabBar` | 24 pt above tab bar | Renamed `bottomClearance`, from safe-area bottom |
| `defaultCaptureModeReader()` | Hard default `.double` | WHEN `SettingsKeys.captureMode` is unwritten: `hasLiDAR ? .single : .double` (Req 16.2). Existing installs that wrote the key keep their choice |

### Navigation routes (all four stacks)

`navigationDestination(for: MealRecord.self)` is **removed**; each stack keys one route enum:

| Stack | Route enum | Cases |
|---|---|---|
| Capture (root) | `CaptureRoute` | `.review(MealRecord)` → SegmentationReviewView · `.result(MealRecord)` → ResultView(.justCaptured) · `.correction(MealRecord)` → ManualCorrectionView |
| Data sheet | `MealRoute` | `.overview(MealRecord)` → MealOverviewView · `.result(MealRecord)` → ResultView(.historyDetail) · `.correction(MealRecord)` |
| Trends sheet | `MealRoute` (shared) | Day-list rows push `.overview` (Req 10.6) |
| Settings sheet | none | `AboutView` via plain `NavigationLink` |

`runEstimation` success appends `CaptureRoute.review(record)`; the review's `Carbs` action appends `.result(record)`. `Done` in `.justCaptured` calls `model.dismissResult()` (clears path, `.ready`); `Done` in `.historyDetail` pops **one level** (Overview → Full result → Done lands back on Overview; Req 1.3's return-to-Capture applies to the capture stack only). Req 6.7 note: `.historyDetail` currently hides the action row — showing `Adjust`/`Done` there is a deliberate semantic change.

Correction `Save` pops one level, back to whichever screen pushed it. Result always shows the **original** estimate in the hero; after a correction it gains the `corrected` marker (Req 7.3) via the same `eventsDidChange` re-read Overview uses — corrected totals surface in Data and Overview, not the hero. Fresh-capture ⋯ `Delete`: `ResultView` has no store reference, so the menu action calls a new `model.deleteAndDismiss(record)` (`store.deleteMeal` then `dismissResult()`; the `.showingResult` guard holds); in the Data/Trends stacks, delete stays on Overview only (§9.3).

### TabView-era parity audit

| Call site | Needs equivalent | Replacement |
|---|---|---|
| `AppRoot.onChange(of: selectedTab)` | yes | `.onChange(of: activeSheet)` → `sheetDidPresent/Dismiss` |
| `@AppStorage("selectedTab")` + `applyLaunchOverrides` reset | no | Deleted with AppTab |
| `model.tabSelectionChanged` internals | yes | Same body, new names |
| `LiveIndicatorBadge` view + auto-hide | no | Telemetry capsule (always visible; σ_tilt% dropped — manifest deviation). **Kept:** `LiveIndicatorBadgeState.isSigmaTiltSufficient` — `CaptureFlowModel.tiltInRange` (line ~696) calls it; the pure state type moves into the telemetry capsule's file |
| Blocked-shutter feedback (`shutterBlockedTapped()` → badge `reveal()`) | yes | Haptic `.warning` (existing) + a transient status chip above the shutter naming the failing gate (`too far` / `hold steady` / `wait` — §4 chip component reused). Req 2.6's feedback contract preserved with a new surface |
| `TiltBubbleGuide` (200×200 centre) | yes | `MedataBubbleLevel` (76×76 top-right) — same inputs (`tiltVector`, target 0°/25°, tolerance), same maths; geometry/placement only (Decision 8) |
| `CaptureTopBar` (close + torch) | partially | Rebuilt: mode capsule + Trends/Data buttons. Torch dropped (Decision 14, accepted) |
| `MealRow` (photo-led card) | no | `DataRow` (anonymous, Req 8.2); `meals-tab.md` page superseded |
| Transient surfaces: status hints (`Initialising…`/`Tracking lost`/`Capturing…`), `NadirThumbnailView`, `obliqueTiltMessage` | yes | Preserved and restyled per `capture.md` page (Req 2.1's transient-surface clause); copy per inventory |
| `.permissionDenied` → `PermissionDeniedView` (no chrome) | yes | Branch restructured: top bar (Trends/Data) + bottom row (Settings) stay rendered; shutter and mode disabled; refusal copy centred (Req 1.6) |

### Screen inventory and integration points

| Screen (Req) | File | New/Mod | Integration point |
|---|---|---|---|
| Capture chrome (§2) | `CaptureFlowView.swift` + new `TelemetryCapsule.swift`, `MedataBubbleLevel.swift` | M/N | `model.currentSnapshot` / `indicators.liveTiltVector`; mode capsule from `mode` + `model.awaitingObliqueView` |
| Fork sheet (§3) | new `LidarForkSheetView.swift` | N | Long-press on mode control; path buttons write `SettingsKeys.captureMode`; card toggle seeds from `SettingsKeys.alwaysIncludeCard`, per-capture override in model only. Observable effect of the toggle: card-placement guidance shown during two-view capture (detection itself stays automatic in the pipeline) |
| Error overlay (§4) | new `CaptureErrorOverlay.swift` (replaces `RefusalSheet` presentation) | N | Same `ActiveRefusal` + `retry()`/`dismissRefusal()`; `2-view` action = new model command `switchToTwoViewAndRetry()` — clears `inFlightMode`, writes `.double` to `SettingsKeys.captureMode` (persists, same semantics as tapping the toggle), restarts capture. Plain `retry()` would re-run the frozen single-mode attempt |
| Estimating (§1.3) | `CaptureFlowView` `.estimating` branch | M | `MedataLoadingSymbol(mode: .loop)` over frozen frames (closes `ldsym06`) |
| Segmentation review (§5) | new `SegmentationReviewView.swift` + `MaskOverlayLoader.swift` | N | Pushed via `CaptureRoute.review`; masks per Decision 15 (below); class swatches from the palette colour table |
| Result (§6) | `ResultView.swift` | M | Adds summary card, per-class rows (name/mass/volume/carbs from per-class macros), macro placeholders, `Adjust`/`Done` + ⋯ menu per 6.6/6.7. Keeps calibration banner, very-low surface, placeholder chip, `ConfidencePill` |
| Correction (§7) | new `ManualCorrectionView.swift` | N | `store.appendCorrection` (now notifies — Decision 18); `was N g` from `corrections(for:)` |
| Data (§8) | `MealsTabView.swift` → `DataView.swift` (+`DataRow`) | M | `MealHistoryModel` **extended**: `reload()` composes corrections (one `corrections(for:)` pass per meal — N small at MVP scale) into a display struct (record + corrected total + corrected flag), so `eventsDidChange` after `appendCorrection` (Decision 18) genuinely invalidates rows. Value-identical `MealRecord` refetches alone would not — SwiftUI would diff no change |
| Meal overview (§9) | new `MealOverviewView.swift` | N | Photo via extracted `PHAsset` loader; masks via `MaskOverlayLoader`; corrections re-read on `eventsDidChange` while visible; delete via confirmation |
| Trends (§10) | new `TrendsView.swift`, `TrendsModel.swift`, `TrendsOptionsSheet.swift` | N | Meals `store.allMeals()`; glucose `store.events(in:type: EventType.bsl)`; `import Charts` (target 26.5, no guards) |
| Settings (§12) | `SettingsView.swift`, `SettingsKeys.swift` | M | Account (disabled), capture defaults, About link, export unchanged (whole-file copy ⇒ `bsl` rows included); DEBUG seed row |
| About (§13) | new `AboutView.swift` | N | Attribution moves out of Settings |

### Mask artefacts (Decision 15; Reqs 5.1, 6.8, 9.1, 9.2)

The pipeline persists no artefacts today, and the store API has no byte transport: `MealArtefact` is a descriptor only and `save()` inserts rows without writing files (`artefactsBaseURL` is private to the store). Two store methods are added (both `PersistenceStore` protocol + GRDB impl):

```swift
func writeArtefact(mealId: UUID, artefact: MealArtefact, data: Data) async throws
// writes meals/{id}/{filename} then inserts the meal_artefacts row; file-first so a
// crash between the two leaves an orphan file, never a dangling row
func artefactData(mealId: UUID, kind: String) async throws -> Data?
// nil when no such artefact/file — the §6.8 fallback signal; never throws for absence
```

- **Write:** at Stage L, after `save`, encode the label raster as an **8-bit greyscale PNG of raw label indices** (no colour profile; ~20–50 KB) and `writeArtefact(kind: "mask")`. Estimation maths untouched; encode/write failure logs and never fails the meal save.
- **Colour table:** `ClassPalette` maps id→name only. Add a deterministic id→colour table alongside it in MedataCore (fixed hue wheel indexed by class id, palette-versioned) — single source for overlay tinting, §9.2 swatches, and the design pages. Colours are applied at **read time only**; the stored PNG carries indices, not colours.
- **Read:** `MaskOverlayLoader` (App) takes the store, calls `artefactData(mealId:kind:)`, reads the raw bitmap bytes via `CGDataProvider` (not a colour-managed `UIImage` decode, which can remap index values), tints per the table. Nil anywhere → photo-only fallback (Req 6.8). Pre-existing meals fall back — no backfill. No filesystem paths cross the store boundary.
- **Delete:** existing `deleteMeal` artefact cascade covers it; `deleteArtefacts(olderThan:)` purges masks too (fallback handles it).

### Trends chart (Req 10.2–10.5)

Single y-scale workaround kept, with a dynamic carb axis: `carbAxisMax = max(80, ceil(maxCarbs/20)*20)` (Req 10.2, no clipping). Mapping/relabelling are pure functions in `TrendsModel`.

`TrendsMath` (pure, MedataCore): TIR is time-weighted with exact crossings — linearly interpolate between consecutive readings, count the sub-durations where the interpolated value lies in [3.9, 10.0] (crossing points computed, not all-or-nothing); intervals with gap > 60 min are excluded from numerator *and* denominator; nil when nothing qualifies (Req 10.5 `—`). Plus day/week/month bucketing.

Options persist via `@AppStorage` keys in `SettingsKeys`.

## Data Models

MedataCore changes (all additive; none touch estimation maths):

```swift
public enum EventType {
    public static let meal = "meal"
    public static let bsl = "bsl"     // blood glucose, value = mmol/L
}
```

- Palette colour table (see Mask artefacts).
- `appendCorrection` now emits `eventsDidChange` (Decision 18) — documented behaviour change; it is the only way Data/Overview learn a correction landed without polling.
- `#if DEBUG` `seedDemoBslEvents()` on `GRDBPersistenceStore` (Decision 13): 24 h synthetic readings, 15-min spacing, from a DEBUG-only Settings row. Verification path until an importer ships.

## Error Handling

Presentation changes only. `EstimationFailure` → §4 overlay (chip + hint from copy inventory; `localisedMessage` verbatim rule superseded — row 12). `PersistenceError.corruptRecord` from `events(in:type:)` → Trends empty state + log, never a crash. Mask-artefact write failure → logged, meal save unaffected. LiDAR dot pairs colour with shape: filled `●` (depth) vs hollow `○` (none) (Req 14.4).

## Design-system deliverables

- **Pages** (Req 15.3): `capture.md` (incl. transient surfaces + Trends/Data button placement), `capture-error.md`, `fork-sheet.md`, `segmentation-review.md`, `result.md`, `correction.md`, `data.md`, `meal-overview.md`, `trends.md`, `settings.md`, `about.md`. `photo-tab.md`/`meals-tab.md` marked superseded.
- **MASTER.md amendments** (Decision 12): tab-bar invariant deleted; tokens `seriesGlucose` (systemOrange), `bandTarget` (medataAccent 10 %); scaffold palette not adopted.
- **Archive + manifest** (Reqs 15.1/15.2): bundle → `design-system/wireframes/design-handoff-00/`; `MANIFEST.md` deviations: three-tier chip, retention/IFCDB, σ_tilt%, torch, per-class σ, Save→Done, Trends row target, tab-bar invariant, copy → §14.
- **Copy inventory** (Req 14.2): `copy-inventory.md` — verbatim contract.
- **Supersession note** (Req 16.1): added to `specs/ui/iphone-experience/requirements.md` in the same commit series.

## Testing Strategy

Build + on-device look-right; no new test scaffolding. Exception (existing MedataCore suite, not scaffolding): `TrendsMath` tests — TIR crossing interpolation, gap exclusion, nil denominator; axis mapping round-trip. Palette colour table gets one determinism test (same id → same colour across runs).

| Verify | Build | How |
|---|---|---|
| Chrome, sheets, Data, Settings, About, Trends (seeded bsl) | `make deploy-device` (Debug) | Visual pass per pages; match `buildStamp` first |
| Capture → estimating → review → result, error overlay, fork sheet, mask overlay on fresh meal | `make deploy-release-stub` | Debug stub can't arm the shutter |
| Reduce Motion, empty states, denied-Photos fallback, pre-existing-meal fallback (no mask artefact) | either | iOS Settings toggles; fresh install; pre-redesign meal in store |

`make spell` on all new strings/pages; `make test` (report both totals) stays green.

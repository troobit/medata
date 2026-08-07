# PRD: SNAQ-inspired UI uplift — portion adjustment and page declutter

> **Superseded in part (2026-07-26)**: the global "Ate N of M" portion stepper this PRD added to ResultView is superseded by `specs/serving-adjust/`, which replaces the PORTION card and `PortionStepper` pair with per-food serving steppers on the Per food rows. The correction-persistence mechanism (`appendCorrection`), corrected Graph carb bars, and page-declutter work remain in force.

## Product summary

MeData estimates the carbohydrate content of everything on the plate, but the user does not always eat the whole plate: with five baked potatoes captured, they may eat two. SNAQ's serving-portion adjustment (observed in the collaborator screenshots, see `docs/agent-notes/snaq-flow-and-gap-analysis.md`) lets the user state how much of the estimate they actually consumed, and that single control is the highest-impact gap between "what the camera saw" and "what went into the body" — the number the glucose graph actually needs.

This PRD adds a portion-adjustment control to the estimation result surfaces, persisted through the existing append-only correction mechanism so the original estimate is never lost, and fixes the downstream gap where the Graph's carb bars ignore corrections entirely (`App/TrendsModel.swift` reads `record.macros.totalCarbsG` raw). It also declutters the page chrome: navigation titles are removed from the full-screen pages (the title duplicates context the user already has and costs a nav-bar band of vertical space), and the Graph's metric-chip row must stop truncating with an ellipsis in portrait.

Target repository: `medata` (this repository). All work is SwiftUI in `App/`; the estimation pipeline, Core ML model, and food databases are untouched.

## Goals

- The user can state, on the result screen, how much of the estimated plate they ate (a fraction such as 2 of 5, or more than one plate) and have the scaled carb value become the recorded amount.
- The scaled (corrected) carb total is what Records rows, the Meal overview, and the Graph's carb bars all display — one consistent "eaten" number everywhere downstream.
- The original estimate is always preserved and visible; a portion adjustment is reversible and re-adjustable.
- Full-screen pages stop spending a nav-bar band on a redundant title; the freed vertical space goes to content.
- Nothing on the Graph or result screens truncates with an ellipsis in portrait on the primary device (iPhone 16 Pro).

## Non-goals

- No changes to the estimation pipeline, segmenter, volume/mass maths, or food databases — portion scaling is post-estimation display/persistence arithmetic only.
- No new event types, tables, or schema changes: portion adjustment persists through the existing `PbUserCorrection` / `appendCorrection` mechanism.
- No macro (protein/fat) work, no favourites/frequents, no text-search food lookup — those are catalogued in the SNAQ gap analysis for other tracks.
- Modal sheets keep their titles (`CarbEntrySheet`, `QuickPresetEditSheet`, `InsulinDoseSheet`, `TrendsOptionsSheet`, `GlucoseImportView`, `GlucoseConnectionsView`, `AboutView`): a sheet title distinguishes create/edit modes and none of them exhibits the truncation problem. Only full-screen pages lose their titles.
- No landscape-specific layout work; portrait on the primary device is the bar.
- No new test scaffolding: the MVP gate is build + looks-right-on-device. Keep `make test` (MedataCore) green; do not add app-target tests or test targets.

## iOS app

Covers the SwiftUI surfaces in `App/` (result and history screens, Graph, Records, Intake, Settings) and the display models behind them (`TrendsModel`, `RecordsModel`, `MealHistoryModel`). Single context: both changes touch the same screens.

1. The result screen (`App/ResultView.swift`, both `justCaptured` and `historyDetail` presentations) MUST offer a portion control that lets the user state how much of the estimated plate they ate, defaulting to the full plate.
   - Acceptance: the control expresses "N of M" fractions (the 2-of-5-potatoes case must be exactly representable, not approximated to a nearest quarter) and multiples above one plate (at least ×2, e.g. ate two captured-identical plates).
   - Acceptance: while adjusting, the displayed carb total updates live to the scaled value (scaled = original × portion factor, rounded to 1 g per the existing `ResultFormat.carbsGrams` convention); the full-plate estimate remains visible on the screen (e.g. as a secondary "full plate: N g" line) so the original is never hidden.
   - Acceptance: with the control at its default, behaviour and persisted data are unchanged from today — no correction is written for a full-plate meal.
2. Confirming a portion adjustment MUST persist the scaled totals through the existing correction mechanism, never by overwriting the estimate.
   - Acceptance: an applied portion appends one `PbUserCorrection` via `store.appendCorrection` carrying the scaled total, the per-class carb values scaled by the same factor, and a note recording the portion (e.g. "portion 2/5"); the original `MealRecord` is byte-identical afterwards.
   - Acceptance: re-opening the meal from history seeds the portion control from the recorded portion, and re-adjusting (including back to full plate) appends a further correction — the history of adjustments is preserved (corrections are append-only).
3. The Graph's carb bars MUST reflect the corrected (eaten) totals, not the raw estimate.
   - Acceptance: after a portion adjustment (or any manual correction), the Graph's day-view carb bar for that meal shows the corrected value; week/month aggregates use the same corrected totals (`App/TrendsModel.swift` currently reads `record.macros.totalCarbsG` directly — this is the gap being closed).
   - Acceptance: Records rows and the Meal overview show the same scaled total with the existing `corrected` marker (already wired via `displayTotalCarbsG` — must keep working).
4. Full-screen pages MUST NOT render a navigation title, and the freed vertical space MUST go to content.
   - Acceptance: Graph (`TrendsView`), Records (`RecordsView`), Intake (`IntakeView`), Settings (`SettingsView`), Meal overview (`MealOverviewView`), Adjust (`ManualCorrectionView`), and Foods (`SegmentationReviewView`) show no title text in the navigation bar; their close/options toolbar controls remain functional.
   - Acceptance: on each of these pages the first content element sits higher than before the change (no empty band where the title was) — verified visually on device/simulator.
5. The Graph and result screens MUST NOT truncate any control or label with an ellipsis in portrait on the primary device.
   - Acceptance: the Graph metric-chip row (`Carbs / Glucose / Insulin / Protein · Fat`, `TrendsView.metricChips`) renders all chips fully legible in portrait — wrapping, resizing, or scrolling are all acceptable; truncation is not.
   - Acceptance: the result screen's banners, pills, and the new portion control render without ellipsis truncation in portrait at default Dynamic Type.
6. All new and changed UI SHOULD follow the existing design system (`Colors.swift` palette, capture-chrome treatment on result surfaces, the label-wrapped Button pattern from `docs/agent-notes/ui-capture-flow.md`).
   - Acceptance: new buttons place sizing/`contentShape` inside the Button label (the dead-pill trap); result-surface additions use the capture palette; `make spell` passes; no reassurance/disclaimer copy.

## Execution notes

- Quality gates: `make build`, `make test` (report BOTH totals — XCTest and swift-testing), `make spell`, all from the repo-root Makefile. The app itself builds via `MeData/MeData.xcodeproj`; note the caveat in `docs/agent-notes/ui-capture-flow.md` — the project's local-package reference only resolves in a checkout directory literally named `medata`, so an app-target build from a worktree needs the path pointed locally (never commit that change).
- Read `docs/agent-notes/ui-capture-flow.md` before touching `App/` (Button dead-surface trap, pbxproj four-place registration for any NEW file under `App/`, one-ARSession rule).
- Load the `frontend-design` skill when reshaping these screens — the user asked for a design uplift, not just a mechanical change.
- Requirement 3 (corrected totals in the Graph) is independent of requirements 1–2 and can land first; requirement 2 depends on 1. Requirements 4–5 (chrome) are independent of 1–3 but touch the same files — implement in one branch, not parallel worktrees.
- Do NOT add app-target tests: `MeData/Tests/` and `MeData/UITests/` are documentation contracts, not an executable suite. Portion-scaling arithmetic that wants a unit test belongs in MedataCore only if it naturally lives there; otherwise verify by build + on-device look.
- STOP — the final looks-right pass on the iPhone 16 Pro (portion control ergonomics, no truncation in portrait, reclaimed space) is the user's call; the executor verifies to the simulator-build level.

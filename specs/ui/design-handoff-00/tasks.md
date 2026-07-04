---
references:
    - requirements.md
    - design.md
    - decision_log.md
    - copy-inventory.md
---
# UI Design Handoff 00 — Tasks

## Core (MedataCore + pipeline)

- [ ] 1. Write failing TrendsMath tests (TIR, bucketing, axis mapping) <!-- id:xi3gpmz -->
  - TIR: exact crossing interpolation into [3.9, 10.0]; gaps > 60 min excluded from numerator AND denominator; nil when nothing qualifies
  - Day/week/month bucketing; carb-axis mapping round-trip with dynamic max = max(80, ceil(maxCarbs/20)*20)
  - New test file in the existing MedataCore suite (design Testing Strategy) — must fail before task 2
  - Stream: 1
  - Requirements: [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [10.5](requirements.md#10.5)

- [ ] 2. Implement TrendsMath (pure, MedataCore) to pass tests <!-- id:xi3gpn0 -->
  - Pure functions only — no UI imports; lives in MedataCore so the existing suite covers it
  - Blocked-by: xi3gpmz (Write failing TrendsMath tests (TIR, bucketing, axis mapping)), failing, failing, failing, failing, failing, failing
  - Stream: 1
  - Requirements: [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [10.5](requirements.md#10.5)

- [ ] 3. Write failing palette colour-table test (determinism) <!-- id:xi3gpn1 -->
  - Same class id → same colour across runs; table is palette-versioned alongside ClassPalette (design: Mask artefacts)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [9.2](requirements.md#9.2)

- [ ] 4. Implement id→colour table beside ClassPalette <!-- id:xi3gpn2 -->
  - Fixed hue wheel indexed by class id; single source for overlays, swatches, design pages; colours applied at read time only (Decision 15)
  - Blocked-by: xi3gpn1 (Write failing palette colour-table test (determinism)), failing, palette, failing, palette, failing, palette, failing, palette, failing, palette, failing, palette
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [9.2](requirements.md#9.2)

- [ ] 5. Add EventType.bsl and DEBUG-only seedDemoBslEvents() <!-- id:xi3gpn3 -->
  - EventType.bsl = "bsl", value mmol/L (imgdatacollector row shape); types/config — TDD exempt
  - #if DEBUG extension on GRDBPersistenceStore: 24 h synthetic readings, 15-min spacing (Decision 13); no public event-write API (importer spec owns that)
  - Stream: 1
  - Requirements: [11.1](requirements.md#11.1)

- [ ] 6. Write failing store artefact-transport tests <!-- id:xi3gpn4 -->
  - writeArtefact(mealId:artefact:data:) writes meals/{id}/{filename} THEN inserts meal_artefacts row (file-first crash ordering)
  - artefactData(mealId:kind:) returns bytes; nil (not throw) when artefact/file absent; deleteMeal cascade removes the file
  - Stream: 1
  - Requirements: [6.8](requirements.md#6.8)

- [ ] 7. Implement writeArtefact/artefactData on PersistenceStore + GRDB impl <!-- id:xi3gpn5 -->
  - Protocol + GRDBPersistenceStore; no filesystem paths cross the store boundary (design: Mask artefacts)
  - Blocked-by: xi3gpn4 (Write failing store artefact-transport tests)
  - Stream: 1
  - Requirements: [6.8](requirements.md#6.8)

- [ ] 8. Write failing test: appendCorrection emits eventsDidChange <!-- id:xi3gpn6 -->
  - Asserts one eventsDidChange tick after a successful correction insert (Decision 18)
  - Stream: 1
  - Requirements: [7.3](requirements.md#7.3)

- [ ] 9. Emit eventsDidChange from appendCorrection <!-- id:xi3gpn7 -->
  - GRDBPersistenceStore one-line change; update the stale 'does not emit' note in specs/data/event-log-schema/design.md is task 26, not here
  - Blocked-by: xi3gpn6 (Write failing test: appendCorrection emits eventsDidChange)
  - Stream: 1
  - Requirements: [7.3](requirements.md#7.3)

- [ ] 10. Write failing test: Stage L persists mask artefact <!-- id:xi3gpn8 -->
  - After estimate: meal_artefacts has kind "mask" row + decodable 8-bit greyscale PNG of label indices; encode/write failure logs and does NOT fail the meal save
  - Blocked-by: xi3gpn5 (Implement writeArtefact/artefactData on PersistenceStore + GRDB impl)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [6.8](requirements.md#6.8)

- [ ] 11. Implement Stage L mask-artefact write in Pipeline <!-- id:xi3gpn9 -->
  - Storage only — estimation maths untouched (Decision 15 boundary; police in review)
  - No colour in the PNG; indices only, no colour profile
  - Blocked-by: xi3gpn8 (Write failing test: Stage L persists mask artefact)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [6.8](requirements.md#6.8)

## Shell and routes

- [x] 12. Shell swap: remove TabView, ActiveSheet enum, stubs + pbxproj registration <!-- id:xi3gpna -->
  - AppRoot hosts CaptureFlowView + .sheet(item: $activeSheet) (single optional enum → sheets mutually exclusive); delete AppTab.swift and the -uitestResetSelectedTab override in App.swift
  - Rename tabSelectionChanged → sheetDidPresent()/sheetDidDismiss() (same bodies); ShutterButtonMetrics.bottomClearance from safe-area bottom
  - defaultCaptureModeReader: unset key → hasLiDAR ? .single : .double; written keys untouched
  - Create compilable stub files for ALL new App/ views (TelemetryCapsule, MedataBubbleLevel, CaptureErrorOverlay, LidarForkSheetView, SegmentationReviewView, MaskOverlayLoader, ManualCorrectionView, DataView, MealOverviewView, TrendsView, TrendsModel, TrendsOptionsSheet, AboutView) and register each individually in project.pbxproj (ShutterButton pattern, docs/agent-notes/device-build-and-test.md) — later tasks fill stubs, no further pbxproj edits
  - Wiring/config — TDD exempt (applies to all App-target tasks; no executable app-target suite)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.5](requirements.md#1.5), [16.2](requirements.md#16.2)

- [x] 13. Route enums and model commands <!-- id:xi3gpnb -->
  - CaptureRoute(review/result/correction) on capture stack; MealRoute(overview/result/correction) shared by Data+Trends sheet stacks; REMOVE navigationDestination(for: MealRecord.self)
  - runEstimation appends .review(record); Done(.justCaptured) → model.dismissResult(); Done(.historyDetail) pops one level; correction Save pops one level
  - New model commands: deleteAndDismiss(record) (store.deleteMeal then dismissResult; .showingResult guard holds) and switchToTwoViewAndRetry() (clear inFlightMode, persist .double, restart) — plain retry() would re-run the frozen single-mode attempt
  - Blocked-by: xi3gpna (Shell swap: remove TabView, ActiveSheet enum, stubs + pbxproj registration)
  - Stream: 2
  - Requirements: [1.3](requirements.md#1.3), [4.1](requirements.md#4.1), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7)

## Capture screens

- [x] 14. Rebuild capture chrome + write design-system/pages/capture.md <!-- id:xi3gpnc -->
  - TelemetryCapsule (always visible; tilt°, dist cm or 30–40 cm band non-LiDAR, LiDAR dot ● filled/○ hollow + green/grey per Req 14.4); keep LiveIndicatorBadgeState.isSigmaTiltSufficient (CaptureFlowModel.tiltInRange calls it), delete badge view
  - MedataBubbleLevel 76×76 top-right: TiltBubbleGuide maths (tiltVector, target 0°/25°, tolerance), non-gating, colour+position (Decision 8)
  - Top bar: mode capsule (1-VIEW · LiDAR / 2-VIEW · NADIR / 2-VIEW · OBLIQUE) + Trends/Data buttons; bottom row mode/shutter/settings; torch REMOVED (Decision 14)
  - Transient surfaces restyled, copy per inventory: Initialising / hold steady / Capturing / Target 25° / Nadir thumbnail
  - Blocked-shutter feedback: existing haptic + transient failing-gate chip above shutter (badge reveal is gone)
  - .permissionDenied restructured: top bar + settings button stay rendered, shutter/mode disabled, refusal copy centred (Req 1.6)
  - .estimating: MedataLoadingSymbol(.loop) over frozen frames (closes ldsym06); accessibility label Estimating
  - capture.md pins Trends/Data button placement (carry-forward item); all strings verbatim from copy-inventory.md
  - Blocked-by: xi3gpnb (Route enums and model commands)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [1.6](requirements.md#1.6), [14.4](requirements.md#14.4)

- [x] 15. CaptureErrorOverlay + capture-error.md (replaces RefusalSheet presentation) <!-- id:xi3gpnd -->
  - Full-screen overlay: amber ghost outline, ≤3-word chip, one-clause hint, Retry / 2-view / Cancel; same ActiveRefusal model + retry()/dismissRefusal(); 2-view action = switchToTwoViewAndRetry()
  - Retry resumes at failed stage with AR live (folds old refusal 10.2/10.3); chips/hints verbatim from copy inventory
  - Blocked-by: xi3gpnb (Route enums and model commands)
  - Stream: 2
  - Requirements: [1.4](requirements.md#1.4), [4.1](requirements.md#4.1), [4.2](requirements.md#4.2)

- [x] 16. LidarForkSheetView + fork-sheet.md <!-- id:xi3gpne -->
  - Long-press on mode control; Quick (1 photo) recommended / Two-view; path buttons write SettingsKeys.captureMode
  - Card toggle seeds from SettingsKeys.alwaysIncludeCard; per-capture override in model only (not persisted); observable effect = card guidance during two-view
  - No LiDAR: quick disabled (LiDAR unavailable), two-view preselected
  - Blocked-by: xi3gpnb (Route enums and model commands)
  - Stream: 2
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3)

- [ ] 17. SegmentationReviewView + MaskOverlayLoader + segmentation-review.md <!-- id:xi3gpnf -->
  - MaskOverlayLoader takes the store, artefactData(mealId:kind:"mask"), reads raw bitmap via CGDataProvider (NOT colour-managed UIImage decode), tints per colour table; nil anywhere → photo-only (Req 6.8)
  - Class list with mask-colour swatches, no per-class confidence (Decision 16); unknown/liquid banners icon+text; primary action Carbs → appends .result(record)
  - Blocked-by: xi3gpn2 (Implement id→colour table beside ClassPalette), xi3gpn5 (Implement writeArtefact/artefactData on PersistenceStore + GRDB impl), xi3gpnb (Route enums and model commands)
  - Stream: 2
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [6.8](requirements.md#6.8)

- [ ] 18. Rework ResultView + result.md <!-- id:xi3gpng -->
  - Adds summary card (thumbnail per 6.8 fallback, N foods, mass, CoFID + AFCD), per-class rows (name/mass/volume/carbs — no σ), dashed Protein/Fat placeholders
  - Actions: Adjust / Done; ⋯ menu Retake+Delete fresh, Delete only from history (Decision 17); .historyDetail now SHOWS the action row (deliberate change)
  - Hero always shows original estimate; corrected marker via eventsDidChange re-read; keeps calibration banner, very-low surface, placeholder chip, four-tier ConfidencePill (Decision 5)
  - Blocked-by: xi3gpnb (Route enums and model commands)
  - Stream: 2
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7), [6.8](requirements.md#6.8)

- [ ] 19. ManualCorrectionView + correction.md <!-- id:xi3gpnh -->
  - Total stepper + per-food edits + Note; store.appendCorrection; was N g from corrections(for:); Save pops one level
  - Copy: Original kept · correction saved alongside (minimised, no exemption)
  - Blocked-by: xi3gpn7 (Emit eventsDidChange from appendCorrection), xi3gpnb (Route enums and model commands)
  - Stream: 2
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3)

## Sheet screens

- [ ] 20. DataView + DataRow + MealHistoryModel correction composition + data.md <!-- id:xi3gpni -->
  - MealHistoryModel.reload() composes corrections into display struct (record + corrected total + corrected flag) — value-identical MealRecord refetch alone would not invalidate SwiftUI rows (critic R2)
  - Day grouping (Today/Yesterday/date), anonymous rows: thumbnail (6.8 fallback), time, carbs, four-tier pill; row → MealRoute.overview; empty state No meals yet
  - Blocked-by: xi3gpn7 (Emit eventsDidChange from appendCorrection), xi3gpnb (Route enums and model commands)
  - Stream: 3
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [7.3](requirements.md#7.3)

- [ ] 21. MealOverviewView + meal-overview.md <!-- id:xi3gpnj -->
  - Photo via extracted PHAsset loader (shared with ResultView); masks via MaskOverlayLoader; metadata line {path} · {time}; corrections re-read on eventsDidChange while visible
  - Per-class rows with colour swatches (no σ); Adjust / Full result; delete via ⋯ with confirmation (Delete meal?)
  - Blocked-by: xi3gpn2 (Implement id→colour table beside ClassPalette), xi3gpn5 (Implement writeArtefact/artefactData on PersistenceStore + GRDB impl), xi3gpnb (Route enums and model commands)
  - Stream: 3
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3)

- [ ] 22. TrendsView + TrendsModel + TrendsOptionsSheet + trends.md <!-- id:xi3gpnk -->
  - import Charts (target 26.5, no guards); day dual-series (glucose line mmol/L leading axis, carb bars trailing axis in grams, 3.9–10.0 band via bandTarget token), week/month aggregates; dynamic carbAxisMax — no clipping
  - Glucose from store.events(in:type: EventType.bsl); TIR/bucketing from TrendsMath; no glucose data + — states; day meal list → MealRoute.overview; footer safety copy verbatim
  - Options sheet: metric toggles + captions, band toggle, disabled Protein · Fat, scale Auto/Fixed (8–25 stepper); options persist via @AppStorage SettingsKeys
  - Blocked-by: xi3gpn0 (Implement TrendsMath (pure, MedataCore) to pass tests), xi3gpn3 (Add EventType.bsl and DEBUG-only seedDemoBslEvents()), xi3gpnb (Route enums and model commands)
  - Stream: 3
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [10.4](requirements.md#10.4), [10.5](requirements.md#10.5), [10.6](requirements.md#10.6), [10.7](requirements.md#10.7), [10.8](requirements.md#10.8), [10.9](requirements.md#10.9), [11.1](requirements.md#11.1), [11.2](requirements.md#11.2)

- [ ] 23. SettingsView rework + AboutView + settings.md + about.md <!-- id:xi3gpnl -->
  - Disabled Account row; food database CoFID + AFCD (not IFCDB, Decision 4); capture defaults (Default path 1-view/2-view writing captureMode, Always include card → new SettingsKeys.alwaysIncludeCard); Export; NO retention (Req 12.3)
  - DEBUG-only Seed demo glucose row → seedDemoBslEvents()
  - AboutView: CoFID (Crown Copyright OGL v3) + AFCD attribution, method paragraph (⚖ 13.1), Not a medical device, on-device privacy line; attribution moves out of Settings inline section
  - Blocked-by: xi3gpn3 (Add EventType.bsl and DEBUG-only seedDemoBslEvents()), xi3gpna (Shell swap: remove TabView, ActiveSheet enum, stubs + pbxproj registration)
  - Stream: 3
  - Requirements: [12.1](requirements.md#12.1), [12.2](requirements.md#12.2), [12.3](requirements.md#12.3), [12.4](requirements.md#12.4), [13.1](requirements.md#13.1)

## Docs and archive

- [ ] 24. Archive handoff bundle + MANIFEST.md + intake-note update <!-- id:xi3gpnm -->
  - tmp/design/design_handoff_medata/ → design-system/wireframes/design-handoff-00/ verbatim, inert (no target membership)
  - MANIFEST.md: id 00, date, source, deviations each linking a decision (three-tier chip D5, retention/IFCDB D4, σ_tilt% row 2, torch D14, per-class σ D16, Save→Done D17, Trends row target 10.6, tab-bar invariant D12, copy → §14); no SHA field (Decision 10)
  - docs/agent-notes/wireframe-intake.md landing-zone section → bulk-folder scheme
  - Stream: 4
  - Requirements: [15.1](requirements.md#15.1), [15.2](requirements.md#15.2)

- [ ] 25. MASTER.md amendments + supersede photo-tab/meals-tab pages <!-- id:xi3gpnn -->
  - Delete tab-bar layout invariant; add seriesGlucose (systemOrange) + bandTarget (medataAccent 10%) tokens (Decision 12); scaffold palette NOT adopted
  - photo-tab.md / meals-tab.md: superseded markers pointing at capture.md / data.md
  - Stream: 4
  - Requirements: [15.3](requirements.md#15.3)

- [ ] 26. Supersession note in iphone-experience + event-log-schema note update <!-- id:xi3gpno -->
  - Status paragraph in specs/ui/iphone-experience/requirements.md pointing at the §16 table (Req 16.1, same commit series)
  - specs/data/event-log-schema/design.md: appendCorrection now notifies (Decision 18)
  - Stream: 4
  - Requirements: [16.1](requirements.md#16.1)

## Integration

- [ ] 27. Integration gate: build + test + spell + copy audit <!-- id:xi3gpnp -->
  - Clean xcodebuild of MeData.xcodeproj (all stubs filled, pbxproj resolves); make test green — report BOTH totals (XCTest + swift-testing); make spell clean
  - Copy audit: every user-facing string in App/ matches copy-inventory.md verbatim (Req 14.2 compliance definition); Irish/British spelling (14.3)
  - Device verification is human-gated — see prerequisites.md
  - Blocked-by: xi3gpn9 (Implement Stage L mask-artefact write in Pipeline), xi3gpnc (Rebuild capture chrome + write design-system/pages/capture.md), xi3gpnd (CaptureErrorOverlay + capture-error.md (replaces RefusalSheet presentation)), xi3gpne (LidarForkSheetView + fork-sheet.md), xi3gpnf (SegmentationReviewView + MaskOverlayLoader + segmentation-review.md), xi3gpng (Rework ResultView + result.md), xi3gpnh (ManualCorrectionView + correction.md), xi3gpni (DataView + DataRow + MealHistoryModel correction composition + data.md), xi3gpnj (MealOverviewView + meal-overview.md), xi3gpnk (TrendsView + TrendsModel + TrendsOptionsSheet + trends.md), xi3gpnl (SettingsView rework + AboutView + settings.md + about.md), xi3gpnm (Archive handoff bundle + MANIFEST.md + intake-note update), xi3gpnn (MASTER.md amendments + supersede photo-tab/meals-tab pages), xi3gpno (Supersession note in iphone-experience + event-log-schema note update)
  - Stream: 1
  - Requirements: [14.1](requirements.md#14.1), [14.2](requirements.md#14.2), [14.3](requirements.md#14.3)

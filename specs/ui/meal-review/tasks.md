---
references:
    - specs/ui/meal-review/requirements.md
    - specs/ui/meal-review/design.md
    - specs/ui/meal-review/decision_log.md
    - specs/ui/meal-review/prerequisites.md
---
# Meal Review

## Contracts and derivation (MedataCore)

- [ ] 1. Persist the pre-beta per-class volumes on PbVolumeResult <!-- id:fffbfgr -->
  - VolumeResult.proto: map<string, float> per_class_volumes_pre_beta_cm3 = 5 (fields 1-4 are in use); regenerate VolumeResult.pb.swift
  - VolumeEstimate.perClassVolumesPreBetaCm3 (VolumeTypes.swift:84) is already produced by both estimators (HeightFieldEstimator.swift:190,197; VoxelCarveEstimator.swift:244) and reaches PipelineDiagnostics:128 — it is simply dropped before the meal record is written. Carry it through to the persisted record
  - PaletteMigrator must copy the map through a v1 to v2 migration (Decision 17)
  - Beta is multiplied in during volume estimation, not the macro stage — the persisted volume_cm3 stays post-beta and unchanged
  - Stream: 1
  - Requirements: [3.5](requirements.md#3.5), [8.2](requirements.md#8.2)

- [ ] 2. PbUserCorrection gains corrected_class_ids <!-- id:fffbfgs -->
  - map<string, string> corrected_class_ids = 5 — predicted class id to corrected class id; regenerate
  - Additive with an empty default, so existing readers stay valid — this engages estimation/pipeline Req 14.4 (correction schema shared verbatim with the future clinical track)
  - Without it, every history surface renders record.macros.perClass keys and a rice to couscous relabel displays Rice for the life of the record
  - Stream: 1
  - Requirements: [8.7](requirements.md#8.7)

- [ ] 3. CorrectionRecord, FoodDerivation and MassSource contracts <!-- id:fffbfgt -->
  - New proto per design.md Data Models; Pb prefix per the PortableContracts convention
  - outcome_id joins the record to its estimation_outcomes row and through it to a capture bundle where one survives; where none does the record stays valid for macro re-derivation on its own (Req 8.3) — re-running segmentation under a later model is explicitly not a retention obligation
  - Four independent booleans, not one state enum — corrections compose, and a whole-meal scale writes a mass to every row
  - shortlist_rank is 1-based with 0 meaning no relabel (proto3 scalars default to 0, so a -1 sentinel would make no-relabel indistinguishable from picked-the-first-entry)
  - Density and carbs-per-100g are carried, derived arithmetically from the stored figures (rho = mass_g / volume_cm3, kappa = 100 * carbs_g / mass_g, guarding zero) — never re-looked-up from the database
  - beta_status, density_source and coefficient_source are carried: beta_used == 1.0 is otherwise indistinguishable from an uncalibrated class
  - Fields are double to match Macros.compute and pendingTotalCarbsG, so the corpus value equals the displayed one
  - Stream: 1
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [8.3](requirements.md#8.3), [9.11](requirements.md#9.11), [9.12](requirements.md#9.12)

- [ ] 4. Extract the shared macro re-derivation into MedataCore/Sources/Macros <!-- id:fffbfgu -->
  - Three call sites now need it: PaletteMigrator.swift:83-86 already computes volumeCm3 * rhoNew * betaNew / (rhoOld * betaOld), Pipeline has its own, and the review path is the third. Decision 8's Impact clause requires sharing rather than reimplementing
  - Takes a pre-beta volume and a target class; applies BetaCorrection.entries[class], density and coefficient through Macros.compute, which stamps betaUsed and betaStatus from the DB row (Macros.swift:132-133) — that is what carries Req 3.7's calibration indication for free
  - Pass liquidClassIds: and liquidOverEstimate: so a liquid's over-read flag is not silently dropped
  - Fallback for records written before task 1: stored.volumeCm3 / stored.betaUsed, refused where betaUsed is zero or non-finite — reject, absent and amount adjustment stay available in that case
  - Always derive from predicted, never from a previous corrected value, or repeated relabels compound Float32 drift
  - Blocked-by: fffbfgr (Persist the pre-beta per-class volumes on PbVolumeResult)
  - Stream: 1
  - Requirements: [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.7](requirements.md#3.7)

## Correction store (MedataCore)

- [ ] 5. correction_records table with create, update and read <!-- id:fffbfgv -->
  - Schema per design.md: PRIMARY KEY (meal_id, predicted_class) — the natural key, so the millisecond-collision defect in corrections' PRIMARY KEY (meal_id, created_at) cannot arise, and a held stepper updates one row rather than appending per repeat
  - Creation is INSERT ... ON CONFLICT DO NOTHING; mutation is UPDATE against the corrected columns only. Never INSERT OR REPLACE — the surface can re-appear for the same meal and a blanket upsert would reset created_at and overwrite a predicted side that never changes
  - The four boolean columns are denormalised copies of fields inside record_json so the corpus is queryable and browsable without decoding every blob
  - Index on meal_id, plus an index on predicted_class for the recency shortlist (task 12)
  - Blocked-by: fffbfgt (CorrectionRecord, FoodDerivation and MassSource contracts)
  - Stream: 1
  - Requirements: [9.1](requirements.md#9.1), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4)

- [ ] 6. No-eviction guarantees and the cascade break <!-- id:fffbfgw -->
  - correction_records gains no delete in deleteMeal (GRDBPersistenceStore.swift:177) or deleteRecords (:542). corrections keeps its cascade — it is the meal's current display value and a deleted meal has no display value
  - Exempt from deleteAllData() (:1209, reached from SettingsView.swift:243) — it enumerates its tables by hand and correction_records must not be added to that list. The corpus is not test data
  - No count bound, no age sweep, no pruning anywhere. This is the one store deliberately exempt from the bounding estimation_outcomes (:940-1010) applies
  - Growth: ~800 B per JSON record, three meals a day at four foods is ~44k rows and ~35 MB over a decade. If that ever matters the lever is encoding, not eviction
  - Blocked-by: fffbfgv (correction_records table with create, update and read)
  - Stream: 1
  - Requirements: [9.9](requirements.md#9.9), [9.10](requirements.md#9.10)

- [ ] 7. Artefact-retention exemption on deleteArtefacts(olderThan:) <!-- id:fffbfgx -->
  - The exemption belongs on deleteArtefacts(olderThan:) (:660, public on PersistenceStore.swift:328), not sweepIfDue() (:733) which has no production caller today
  - Skip meals holding a row with an actual correction — class_corrected OR rejected OR absent OR amount_corrected — not merely holding a row, which every meal does; that would make the function an unconditional no-op rather than a retention policy
  - Also delete the meal_artefacts rows alongside the directory, which it does not do today
  - The masks are the storage question, not the records: a 1920x1440 8-bit indexed mask.png (MaskArtefactWriter.swift:11-13,31-34) at three captures a day dwarfs the ~35 MB of records, which is why the sweep stays a policy worth keeping
  - Blocked-by: fffbfgv (correction_records table with create, update and read)
  - Stream: 1
  - Requirements: [8.4](requirements.md#8.4)

- [ ] 8. upsertCorrection(mealId:) — the reconciling write <!-- id:fffbfgy -->
  - One row per meal, created_at fixed at review-session start, ON CONFLICT (meal_id, created_at) DO UPDATE
  - appendCorrection (:122-137) is left untouched for existing callers: it is a plain INSERT into PRIMARY KEY (meal_id, created_at) at millisecond granularity, so a held stepper or a scale tap rewriting every row raises a constraint violation — and because both stores share one transaction that would roll back the correction_records write too, silently, in the one store the spec exists to make lossless
  - Every reader already takes the latest row (MealHistoryModel.swift:84, TrendsModel.swift:109, RecordsModel.swift:111, ResultView.swift:1026, MealOverviewView.swift:226), so one row satisfies them all
  - Row creation writes correction_records only, never corrections — otherwise isCorrected = !corrections.isEmpty becomes true for every meal and the corrected marker appears on all of them
  - Blocked-by: fffbfgs (PbUserCorrection gains corrected_class_ids)
  - Stream: 1
  - Requirements: [8.6](requirements.md#8.6), [8.7](requirements.md#8.7)

- [ ] 9. MedataCore tests: beta re-derivation, cascade, row identity <!-- id:fffbfgz -->
  - Three tests only, per design.md Testing Strategy and the CLAUDE.md gate — no new app-target scaffolding
  - Beta re-derivation equality: relabel(rice to couscous) on a stored PerClassMacros equals Macros.compute([couscous: preBeta * beta_couscous], ...). A deterministic equality, not a property test — it catches a factor inversion
  - Cascade: deleteMeal removes the meal and its artefacts and leaves correction_records intact. This is the regression test for the defect the spec exists to fix
  - Row identity: repeated corrections to one food leave exactly one row, predicted byte-identical to its first write. Includes the re-presentation case — creating rows twice for one meal must not reset created_at or clear a correction already made
  - Blocked-by: fffbfgu (Extract the shared macro re-derivation into MedataCore/Sources/Macros), fffbfgv (correction_records table with create, update and read), fffbfgw (No-eviction guarantees and the cascade break)
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.10](requirements.md#9.10)

## Review surface (App)

- [ ] 10. MaskOverlayDecoder.contours(from:) beside the colourise path <!-- id:fffbfh0 -->
  - Extraction raster: label map downsampled to <=512 long edge, nearest-neighbour (class identity must not be interpolated) — ~0.19 M cells against 2.76 M at full resolution
  - Minimum area 0.25% of image; Douglas-Peucker simplification at eps 1.5 px at extraction scale
  - nonisolated decode off the MainActor, cached by mealId — the current decode is MainActor-isolated with no cache and re-runs on every appearance via .task(id:), blocking the push transition
  - Emit contours only for class ids present in macros.perClass (Req 2.8), but retain presentClassIds on both paths: unknown_food and unsupported_liquid are never in perClass and are the sole input to the Req 1.5 banners (SegmentationReviewView.swift:22,30-31)
  - MealOverviewView.swift:79-80 keeps the fill path; neither path is removed. Lives in App/MaskOverlayLoader.swift, no new file — avoids the four-place project.pbxproj registration (docs/agent-notes/ui-capture-flow.md)
  - Stream: 2
  - Requirements: [1.5](requirements.md#1.5), [2.1](requirements.md#2.1), [2.8](requirements.md#2.8)

- [ ] 11. MealReviewModel <!-- id:fffbfh1 -->
  - @Observable @MainActor; ReviewFood holds an immutable predicted, an optional corrected, independent CorrectionFlags and a massSource. classId stays the identity key after a relabel, so relabelling two foods to the same target does not merge their rows and predicted.class_index remains a valid mask join
  - Mutators are async because the store is (PersistenceStore.swift:365); each upserts its CorrectionRecord and the reconciling PbUserCorrection in one transaction before returning, and each is idempotent per (classId, resulting state)
  - Written on every mutation, not at record(). An earlier draft deferred to the primary action; a session killed mid-review would then leave the corpus holding a relabel while Records showed the uncorrected total permanently. record() only dismisses
  - Persistence failure is logged and swallowed, never surfaced (Req 8.5), per the MaskArtefactWriter precedent
  - Reversal is per correction dimension, not per row: reversing a relabel leaves a co-existing user-set mass in place, and was_reverted is set so a rejected-then-un-rejected food stays distinguishable from a confirmed correct prediction
  - dismissAlternatives() sets picker_opened_unchanged; any subsequent change to that food clears it. discard() sets capture_abandoned across every row of the meal — a per-meal fact held per-row because no meal-scoped row survives deletion
  - Blocked-by: fffbfgu (Extract the shared macro re-derivation into MedataCore/Sources/Macros), fffbfgv (correction_records table with create, update and read), fffbfgy (upsertCorrectionmealId: — the reconciling write)
  - Stream: 2
  - Requirements: [3.11](requirements.md#3.11), [4.1](requirements.md#4.1), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [8.5](requirements.md#8.5), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4), [9.5](requirements.md#9.5)

- [ ] 12. Relabel shortlist, eligible list and the absent action <!-- id:fffbfh2 -->
  - Shortlist ordered by recency, read back from correction_records: rows with predicted_class = this class, ordered updated_at desc, distinct corrected class. No new store is needed — this is why task 5 adds the predicted_class index
  - shortlist_source is written as "recency" on every record made under this spec, so rows stay distinguishable from ones made later under score ordering (Decision 18). Without it shortlist_rank means two different things
  - At most five alternatives before further interaction; no score, percentage or confidence tier displayed for any of them
  - The eligible list is 25 solid classes or 8 liquid ones, with a plain in-memory text filter over food names — no index, no ranking, no query beyond the palette table
  - Filtered to foods the bundled database gives both a density and a coefficient, so an ineligible food is unreachable at relabel time; no solid-to-liquid relabel in either direction
  - The absent action is prominent, not tucked under a search: nearly every real food is outside a 25-class palette, so not-in-the-database is the common case rather than the exception
  - Blocked-by: fffbfh1 (MealReviewModel)
  - Stream: 2
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.8](requirements.md#3.8), [3.9](requirements.md#3.9), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [9.7](requirements.md#9.7)

- [ ] 13. MealReviewView <!-- id:fffbfh3 -->
  - Layout order: photo + outlines ~40% fixed, then total + confidence pill + corrected marker, primary action, and the scale control — all above the scroll boundary. Accessory signals (calibration, liquid over-estimate, unknown region) collapse to one expandable line below it, then the food rows
  - The very-low-confidence surface owns the fold when sigma < 0.20 and suspends the Req 6.6 guarantee: a retake decision precedes any adjustment. This is the one case prerequisites.md cannot treat as a pure layout check
  - Each outline carries a numbered badge at its largest contour's centroid matching its row — the non-colour identity channel, and the means by which adjacent foods stay distinguishable under Differentiate Without Colour. Stroke colour alone satisfies neither
  - A relabelled food's badge row shows predicted to corrected; a rejected food keeps its outline at reduced stroke weight with the badge struck through and its predicted name on the row
  - Selection dims outside the selected class via an even-odd Path; Path.contains(_:eoFill:) gives hit-testing. Canvas is the fallback if <=25 stroked Shape views measure worse on device — it needs the same accessibilityChildren shadow layer either way
  - accessibilityChildren over a shadow ZStack plus ContentShapeKinds.accessibility so the focus ring follows the contour, not a bounding box; where a class's largest contour is under 44 pt its row is the hit target
  - placeholderChip (ResultView.swift:862-870) is not carried: it fires whenever segmenterSource == dev_stub, so it would be permanently present in every Debug build, and the segmenter source is already recorded per correction
  - Rows adopt IntakeView's grouped-row metrics restated against the capture palette; colour from App/Colors.swift tokens only — the Color(uiColor: .systemOrange) sites inherited from SegmentationReviewView.swift:104 resolve to confidenceModerate, the same colour
  - No reassurance, disclaimer or data-preservation copy (design-handoff-00 Req 14.5)
  - Blocked-by: fffbfh0 (MaskOverlayDecoder.contoursfrom: beside the colourise path), fffbfh1 (MealReviewModel)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.4](requirements.md#1.4), [1.6](requirements.md#1.6), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [2.7](requirements.md#2.7), [3.10](requirements.md#3.10), [4.2](requirements.md#4.2), [6.6](requirements.md#6.6), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.5](requirements.md#7.5), [7.8](requirements.md#7.8), [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3), [10.4](requirements.md#10.4), [10.5](requirements.md#10.5), [10.6](requirements.md#10.6), [10.7](requirements.md#10.7)

- [ ] 14. Whole-meal scale and per-food amount wiring <!-- id:fffbfh4 -->
  - PlateFraction is reused (ResultView.swift:193-203); stops are fractions of the estimate at or below one, covering leftovers in one interaction. Correcting upward goes through the per-food serving and gram controls, which are not capped at the measured volume
  - The scale applies to each row's currently derived amount — post-relabel, pre-user-amount — and does not compound. ResultView.applyFraction (:739) scales row.originalGrams, which becomes wrong once relabelling exists: scaling the rice mass after the user said couscous discards the re-derivation
  - A row already carrying a user-set mass is scaled from that mass, and its mass_source becomes MEAL_SCALE
  - A relabel after an amount edit keeps the mass and re-derives carbohydrate only, skipping beta and density: a user-set mass is an assertion, a volume-derived one an inference. Without this rule Req 3.6 and Req 6.9 give different masses for the same sequence
  - mass_source distinguishes I ate three quarters of the plate from the segmenter over-traced this potato — opposite signals that one ratio cannot carry. The ratio itself is not stored; it is corrected.mass_g / predicted.mass_g, both already in the record
  - Amount changes take effect on the total with no separate confirmation; row order is fixed at init and never re-sorts
  - Gram entry is reachable alongside the serving and scale controls without dismissing either; per-food serving stepping and the tap-to-reveal gram editor are serving-adjust items 1 and 3, unchanged
  - Blocked-by: fffbfh1 (MealReviewModel)
  - Stream: 2
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.7](requirements.md#6.7), [6.8](requirements.md#6.8), [6.9](requirements.md#6.9), [6.10](requirements.md#6.10), [7.6](requirements.md#7.6), [7.7](requirements.md#7.7), [9.6](requirements.md#9.6)

- [ ] 15. Capture-stack rewire and ResultView collapse <!-- id:fffbfh5 -->
  - CaptureRoute loses .review; runEstimation pushes .result directly (CaptureFlowModel.swift:841), so no interaction sits between estimation completing and the surface appearing
  - SegmentationReviewView is deleted; ResultView.mode collapses to historyDetail. ResultView itself is not deleted — it remains the Records/Graph read path
  - veryLowSurface is gated to the review path and removed from historyDetail. showsVeryLowSurface (:298) checks only sigma and keepAsIsDismissed, so its retake button at :930 is not mode-gated today; it is already inert in history (onRetake defaults to {}), so this makes a dead affordance explicit rather than changing behaviour
  - logPill (:694) and the adjustmentPending arming (:356) go from the review path — corrections apply live and there is no confirm step between the primary action and the meal being recorded
  - Retake and delete both discard the recorded meal and set capture_abandoned; CaptureFlowView.swift:83-87 resyncs showingResult on back-gesture pop, so re-presentation must not create rows twice
  - Blocked-by: fffbfh3 (MealReviewView)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [7.4](requirements.md#7.4)

- [ ] 16. Corrected food names on every display surface <!-- id:fffbfh6 -->
  - Read PbUserCorrection.corrected_class_ids at ResultView.swift:316-330, MealOverviewView.swift:226, MealHistoryModel.swift:81, RecordsModel.swift:105-121 and TrendsModel.swift:108
  - MealOverviewView composes its own display and is one of only two surfaces that names foods
  - The meal total keeps the stored-total-plus-per-class-delta rule (ResultView.swift:363-367) so historic records do not jump when the database edition changes: Macros.compute is called per corrected food and its totalCarbsG used only as that food's contribution, never as the meal total
  - Corrected-meal marking itself is design-handoff-00 Req 7.3, unchanged
  - Blocked-by: fffbfgy (upsertCorrectionmealId: — the reconciling write)
  - Stream: 2
  - Requirements: [8.6](requirements.md#8.6), [8.7](requirements.md#8.7)

- [ ] 17. Corrections browse and JSONL export in EstimationLogView <!-- id:fffbfh7 -->
  - A corrections section reading correction_records, and a JSONL export beside the existing share-sheet path
  - exportArchive() shipping raw SQLite does not satisfy interpretable as a training example without the app
  - No capture imagery in the export; segmenter_source present per row so stub-derived corrections can be excluded from a training export
  - A row must read without the app, without the food database at the edition that produced it, and without the mask
  - Blocked-by: fffbfgw (No-eviction guarantees and the cascade break)
  - Stream: 2
  - Requirements: [9.8](requirements.md#9.8), [9.11](requirements.md#9.11), [9.13](requirements.md#9.13)

## Supersession and documentation

- [ ] 18. Remove superseded requirement text from design-handoff-00 <!-- id:fffbfh8 -->
  - Requirements 5.1, 5.3 and 7.1 are removed, not annotated in place — the superseded text is edited out of the document that holds it
  - Req 5.2's banners are carried to meal-review Req 1.5 and must not be lost in the removal
  - Req 7.1 was already partly stale: serving-adjust item 5 retired ManualCorrectionView and the free-text note. This is cleanup of that debt plus the relabel addition
  - copy-inventory.md: remove the segmentation-review relabel row, which records the relabel instruction as dropped
  - Add a design-handoff-00 decision-log entry recording the supersession and pointing at specs/ui/meal-review/
  - design-handoff-00 Decision 7 remains in force: correction stays post-hoc, with no user-visible segmentation phase before the estimate completes
  - Stream: 3

- [ ] 19. Remove superseded text from serving-adjust and the design system <!-- id:fffbfh9 -->
  - serving-adjust prd.md: remove §iOS app item 2 (the global portion stepper) and item 4 (the confirm pill and the edit-by-exception rule), and the non-goal "no new correction mechanism, event types, or schema changes"
  - Items 1, 3 and 5 remain in force and are cited, not restated, by meal-review Req 6.1 — do not touch them
  - design-system/pages/segmentation-review.md: remove the "Do NOT offer a relabel / per-class exclusion interaction" anti-pattern
  - Add a serving-adjust decision-log entry recording what was superseded and why
  - Stream: 3

- [ ] 20. New design-system/pages/meal-review.md; retire segmentation-review.md <!-- id:fffbfha -->
  - The page is the written target this surface is iterated against (PROCESS §5) — layout zones, outline and badge treatment, row metrics restated on the capture palette, the above-the-fold rule and its sigma < 0.20 exception
  - segmentation-review.md gains a superseded marker pointing here, matching the photo-tab.md / meals-tab.md precedent
  - result.md is scoped to historyDetail only; its .justCaptured content moves here
  - Blocked-by: fffbfh3 (MealReviewView)
  - Stream: 3
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2)

- [ ] 21. Agent notes, OVERVIEW and nextup <!-- id:fffbfhb -->
  - docs/agent-notes/ui-capture-flow.md: the two-screen split is replaced by one surface; correction_records is the one store exempt from every sweep including the Debug reset; the four-place project.pbxproj registration still applies to any new file
  - specs/OVERVIEW.md: add the Meal Review row (domain ui, mode full) and regenerate rather than hand-merging
  - nextup.md: record the state at hand-off
  - Stream: 3

## Integration

- [ ] 22. Integration gate: build, test, spell <!-- id:fffbfhc -->
  - make build clean; make test green — report BOTH totals (XCTest and swift-testing); make spell clean before committing docs or strings
  - No new app-target test scaffolding: MeData/Tests and MeData/UITests are documentation contracts, not an executable suite
  - Device verification is human-gated — prerequisites.md carries the layout, interaction-cost, legibility, accessibility, durability and corpus checks
  - Confirm the correction records survive a force-quit mid-review and a meal deletion before calling the store done
  - Blocked-by: fffbfgz (MedataCore tests: beta re-derivation, cascade, row identity), fffbfh5 (Capture-stack rewire and ResultView collapse), fffbfh6 (Corrected food names on every display surface), fffbfh7 (Corrections browse and JSONL export in EstimationLogView), fffbfha (New design-system/pages/meal-review.md; retire segmentation-review.md), fffbfhb (Agent notes, OVERVIEW and nextup)
  - Stream: 1

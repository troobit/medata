---
references:
    - requirements.md
    - design.md
    - decision_log.md
---
# nutrition5k-calibration

## Contract

- [x] 1. Write failing tests for the redefined ClassPalette v1 predicates and liquid classes <!-- id:i3we68u -->
  - Extend the existing ClassPalette tests (MedataCore/Tests/SegmentationTests).
  - Assert liquidClasses == [water, coffee, tea, milk, fruit_juice, soup, beer, wine] appended after the 24 solid classes; sentinel indices (background/unknown_food/unsupported_liquid) follow the liquids; totalClasses == foodClasses.count + liquidClasses.count + 3.
  - isFoodClass unchanged — true only for solid indices 0..<foodClasses.count; new isLiquidClass true exactly for the liquid index range (Decisions 23/24 predicate contract: liquid handling is strictly opt-in through isLiquidClass).
  - version stays "v1" — no v2 (Decision 23).
  - Stream: 1
  - Requirements: [7.2](requirements.md#7.2)
  - References: MedataCore/Sources/Segmentation/ClassPalette.swift

- [x] 2. Redefine ClassPalette v1 in place and land the proto contract extensions <!-- id:i3we68v -->
  - ClassPalette.swift: add liquidClasses stored field + init + totalClasses + isLiquidClass; keep version "v1".
  - Proto extensions (design §Data Models): MealFixture.proto — ground_truth_protein_g = 20, ground_truth_fat_g = 21, source_dataset = 22, estimator_path = 23 (closed vocabulary "single_dominant" | "mixture"; any other value malformed); PerClassMacros.proto — protein_g, fat_g, device_verified, is_liquid; MacroResult.proto — result-level liquid_over_estimate flag; ClassPalette.proto — repeated string liquid_classes.
  - Regenerate .pb.swift via MedataCore/Sources/PortableContracts/Schemas/generate.sh (needs protoc + protoc-gen-swift); update the PbClassPalette bridge.
  - This is the single contract task every stream depends on (design §Parallel execution) — land it first.
  - Blocked-by: i3we68u (Write failing tests for the redefined ClassPalette v1 predicates and liquid classes)
  - Stream: 1
  - Requirements: [3.5](requirements.md#3.5), [3.7](requirements.md#3.7), [7.2](requirements.md#7.2), [10.2](requirements.md#10.2)
  - References: MedataCore/Sources/Segmentation/ClassPalette.swift, MedataCore/Sources/PortableContracts/Schemas/MealFixture.proto, MedataCore/Sources/PortableContracts/Schemas/PerClassMacros.proto, MedataCore/Sources/PortableContracts/Schemas/MacroResult.proto, MedataCore/Sources/PortableContracts/Schemas/ClassPalette.proto

## Stream A — N5k ingestion (Python)

- [x] 3. Write failing tests for the N5k ingredient mapping artifact and loader <!-- id:i3we68w -->
  - pytest under tools/nutrition5k/tests/ (new; mirror the tools/segmenter/tests layout).
  - Cases: unmapped ingredient excluded, never reassigned (2.3); ambiguous pairs (white/brown rice, boiled/mashed potato, white/wholemeal bread) recorded status=ambiguous and excluded from both sides (2.4); loader fails loudly on palette_class_list mismatch and on n5k_metadata_version mismatch (2.5); the eight carb-priority staples present where N5k ingredients exist (2.2); class ids preserve FOOD_DATA channel order (2.1).
  - Artifact schema: {palette_class_list, n5k_metadata_version, mappings: [{n5k_ingredient_id, class_id|null, status: mapped|unmapped|ambiguous}]} — keyed to palette content, not the "v1" label (Decision 23).
  - Blocked-by: i3we68v (Redefine ClassPalette v1 in place and land the proto contract extensions)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5)
  - References: tools/segmenter/tests, data/metadata/ingredients_metadata.csv

- [x] 4. Build mapping_n5k_to_palette.json and its loader <!-- id:i3we68x -->
  - tools/nutrition5k/mapping_n5k_to_palette.json + loader (tools/nutrition5k/mapping.py).
  - Map as many of the 24 solid classes as ingredients_metadata.csv allows — the 8 staples are the floor, not the cap (design §Mapping artifact: broad coverage is what feeds the mixture path, since a plate qualifies only when ALL significant ingredients map).
  - Liquid-mapped ingredients (soup, milk, juice…) map to liquid class ids so routing can detect them; they never enter the β fit (4.7).
  - Blocked-by: i3we68w (Write failing tests for the N5k ingredient mapping artifact and loader)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5)
  - References: tools/food_db/generate.py

- [x] 5. Write failing tests for ingest.py core: depth conversion, fixture emission, skip/record <!-- id:i3we68y -->
  - pytest with a tiny synthetic N5k dir fixture (a few dishes + malformed variants).
  - Depth: raw→mm = raw/10.0 as Float32 LE round-trips exactly on the integer grid (property test); sentinel 0 and at-cap pixels written as 0 so the estimator's zt>0 guard excludes them (3.2); two reference-depth checks strictly below the 0.4 m cap abort ingestion outside the documented tolerance band (3.1 — a 10x unit error must fail loudly).
  - CLI: missing dir/artifact exits non-zero naming the expected path + missing artifact (1.2); rgb/depth resolution mismatch vs the pinned model → skip + run-summary record (3.4 — the check is dimensional, not geometric); malformed depth/RGB/mass → skip + record + continue (3.8).
  - Emission: capture_path_canonical="single_view_lidar", pinned nominal RealSense D435 intrinsics (identical for every plate, recorded in lineage — N5k publishes none), gravity straight down, ground_truth_class_mass_g mapped, per-dish carb/protein/fat GT, source_dataset stamp (3.3/3.5/3.6).
  - Pre-checkpoint default: every plate stamped estimator_path=mixture with sentinel SHA "no_segmenter" and no probabilities (3.7).
  - Release identifier: SHA-256 manifest of metadata + split files + download date, carried into the run summary (1.4).
  - Blocked-by: i3we68v (Redefine ClassPalette v1 in place and land the proto contract extensions)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.8](requirements.md#3.8)
  - References: tools/segmenter/make_fixtures.py

- [x] 6. Implement tools/nutrition5k/ingest.py (pre-checkpoint mode) and extend build_fixture_bytes <!-- id:i3we68z -->
  - tools/nutrition5k/ingest.py mirrors tools/segmenter/make_fixtures.py; extend its build_fixture_bytes for the new proto fields rather than duplicating it.
  - --n5k-dir defaults to the data/ layout documented in prerequisites.md (data/n5k/realsense_overhead/dish_<id>/{rgb.png, depth_raw.png}, data/metadata/, data/dish_ids/splits/).
  - Never write N5k imagery/metadata into the repo (1.1) — data/ is gitignored.
  - Emit a run-summary JSON: ingested count, skip reasons, release identifier, ingredient-metadata version.
  - Blocked-by: i3we68x (Build mapping_n5k_to_palette.json and its loader), i3we68y (Write failing tests for ingest.py core: depth conversion, fixture emission, skip/record)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6), [3.8](requirements.md#3.8)
  - References: tools/segmenter/make_fixtures.py, specs/estimation/nutrition5k-calibration/prerequisites.md

- [x] 7. Write failing tests for checkpoint-mode plate routing <!-- id:i3we690 -->
  - Liquid check first: a plate whose liquid-mapped mass fraction ≥ 0.05 is always stamped mixture, never single_dominant (4.7 routing half).
  - τ_route = 0.90: the dominant mapped ingredient's mass fraction of TOTAL plate mass (unmapped included, so an unmapped-heavy plate cannot be stamped single-dominant) → single_dominant stamp; segmenter probs + real checkpoint SHA embedded via export.load_checkpoint / reference_input for make_fixtures.py parity.
  - Plates with unmapped mass fraction > 0.10 recorded as excluded from the mixture fit (design §Unmapped-volume bias).
  - Exactly one fixture per plate; thresholds from design §Provisional gate values, documented in the run summary.
  - Blocked-by: i3we68z (Implement tools/nutrition5k/ingest.py (pre-checkpoint mode) and extend build_fixture_bytes)
  - Stream: 2
  - Requirements: [3.7](requirements.md#3.7), [4.7](requirements.md#4.7)
  - References: tools/segmenter/export.py

- [x] 8. Implement checkpoint-mode routing in ingest.py <!-- id:i3we691 -->
  - --checkpoint flag; without it behaviour is unchanged (all-mixture).
  - Document regeneration semantics: when the model-production Bucket C checkpoint lands, re-run ingestion to regenerate the FULL fixture set; calibrate re-fits both paths and CalibrationMerge applies the 5.2 supersession.
  - Blocked-by: i3we690 (Write failing tests for checkpoint-mode plate routing)
  - Stream: 2
  - Requirements: [3.7](requirements.md#3.7), [4.1](requirements.md#4.1), [4.7](requirements.md#4.7)
  - References: tools/segmenter/export.py

## Stream B — Calibrators and harness (Swift)

- [x] 9. Write failing property tests for TotalHullVolume <!-- id:i3we692 -->
  - Swift Testing, alongside the existing harness tests (MedataCore/Tests/HarnessCLITests).
  - Synthetic depth grid over a known plane: integrated volume matches the analytic value within tolerance; silhouette = height above plane > ε (documented); sentinel/at-cap (0) depth pixels excluded (3.2); off-axis pixel-area correction applied — reuse the VolumeTypes geometry (readDepthMm, ray-plane height).
  - Stream: 3
  - Requirements: [3.2](requirements.md#3.2), [4.1](requirements.md#4.1)
  - References: MedataCore/Sources/Volume/VolumeTypes.swift, MedataCore/Tests/HarnessCLITests

- [x] 10. Implement HarnessCore/TotalHullVolume.swift <!-- id:i3we693 -->
  - New file HarnessCore/TotalHullVolume.swift (#if HARNESS_ENABLED) — NOT MedataCore/Sources/Volume; this keeps stream B's files disjoint from stream C's estimator edits (design §MixtureBetaCalibrator).
  - Depth-threshold silhouette instead of an argmax mask; same geometry helpers as HeightFieldEstimator.
  - Blocked-by: i3we692 (Write failing property tests for TotalHullVolume)
  - Stream: 3
  - Requirements: [4.1](requirements.md#4.1)
  - References: MedataCore/Sources/Volume/VolumeTypes.swift

- [x] 11. Write failing tests for the plate-region support-plane mask <!-- id:i3we694 -->
  - Synthetic frame: plate disc raised above a table plane. Flood fill on 4-neighbour depth continuity (|Δz| below a documented threshold) seeded at the frame centre stops at the plate-rim discontinuity; passing the resulting mask to FixtureRunner.fitPlaneFromDepth lands the RANSAC plane on the plate top, not the table (the current all-ones mask finds the table when the plate does not fill the frame — design §Support plane).
  - Poor plate-plane fit (high residualMm) → plate skipped and recorded (3.4/3.8 path).
  - Stream: 3
  - Requirements: [3.6](requirements.md#3.6)
  - References: HarnessCore/FixtureRunner.swift

- [x] 12. Implement plate-region plane masking in FixtureRunner <!-- id:i3we695 -->
  - HarnessCore/FixtureRunner.swift: derive the plate-region mask from depth before fitPlaneFromDepth for N5k fixtures; record supportPlane.residualMm per plate.
  - Whether the plate reliably fills the N5k overhead frame is confirmed empirically in the Integration task; until confirmed the plate-region restriction is required, not assumed (Decision 15 amendment).
  - Blocked-by: i3we694 (Write failing tests for the plate-region support-plane mask)
  - Stream: 3
  - Requirements: [3.4](requirements.md#3.4), [3.6](requirements.md#3.6), [3.8](requirements.md#3.8)
  - References: HarnessCore/FixtureRunner.swift

- [x] 13. Write failing property tests for the MixtureBetaCalibrator BVLS solver <!-- id:i3we696 -->
  - Property tests (Swift Testing, synthetic generators): plates from known β and ρ with V_p = Σ m/(ρβ) + bounded noise → solver recovers β within tolerance.
  - Bounds x_c = 1/β_c ∈ [1/1.5, 1/0.05] enforced INSIDE the solve; a bound-resting class is marked clamped (5.6) — a post-hoc clamp would re-leak excess volume into co-occurring classes (Decision 11 refinement).
  - A deliberately collinear class → large SE, identifiablePerClass=false; an under-sampled class is held at β=1 and moved to the RHS as a fixed offset, not misattributed (4.6).
  - Stacking guard: plate with V_p < κ·Σ m/ρ (κ=0.6) excluded and listed (4.3); liquid-bearing plate (liquid-mapped mass ≥ 0.05) excluded entirely and counted (4.7).
  - effectiveSamplePerClass uses τ_eff=0.15 per-plate mass fraction (4.5); conditionNumber emitted (5.5).
  - Stream: 3
  - Requirements: [4.3](requirements.md#4.3), [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [5.6](requirements.md#5.6), [6.4](requirements.md#6.4)
  - References: specs/estimation/nutrition5k-calibration/design.md

- [x] 14. Implement HarnessCore/MixtureBetaCalibrator.swift <!-- id:i3we697 -->
  - New file HarnessCore/MixtureBetaCalibrator.swift: hand-rolled Lawson-Hanson active-set BVLS (Decision 14 — Swift, offline harness only, roughly 100 lines).
  - Interface per design: PlateObservation{fixtureID, totalHullVolumeCm3, massByClassG}; Result{betaPerClass, standardErrorPerClass, effectiveSamplePerClass, identifiablePerClass, conditionNumber, excludedPlates, fixedOffsetClasses}.
  - Per-class SE = residual variance × diag((AᵀA)⁻¹) over the free set; per-class conditioning (not just the global condition number) drives identifiablePerClass.
  - ρ-coupling note for the dispersion report: a ρ error in one class biases co-occurring classes' β (5.3).
  - Blocked-by: i3we696 (Write failing property tests for the MixtureBetaCalibrator BVLS solver)
  - Stream: 3
  - Requirements: [4.1](requirements.md#4.1), [4.3](requirements.md#4.3), [4.6](requirements.md#4.6), [5.3](requirements.md#5.3)
  - References: HarnessCore/BetaCalibrator.swift

- [x] 15. Write failing tests for BetaCalibrator PerClassFit outputs and CalibrationMerge arbitration <!-- id:i3we698 -->
  - BetaCalibrator: closed-form fit value and clamp unchanged; new PerClassFit outputs — per-class log-residual standard error + effective-sample count (the current CalibrationResult discards the spread the 5.4 SE gate needs).
  - CalibrationMerge arbitration (5.2/5.4): single-dominant β wins when it clears effective-sample ≥ 30 AND relative SE ≤ 0.15; a strong mixture fit is KEPT when single-dominant is merely under-sampled (no perverse discard); enough plates but large SE → stays pooled, not calibrated; provenance n5k_single_dominant | n5k_mixture | none recorded; clamped flag propagated.
  - Blocked-by: i3we697 (Implement HarnessCore/MixtureBetaCalibrator.swift)
  - Stream: 3
  - Requirements: [5.2](requirements.md#5.2), [5.4](requirements.md#5.4)
  - References: HarnessCore/BetaCalibrator.swift

- [x] 16. Extend BetaCalibrator and implement CalibrationMerge with BetaProvenance <!-- id:i3we699 -->
  - Extend HarnessCore/BetaCalibrator.swift (new outputs only — no change to fit value or clamp); new HarnessCore/CalibrationMerge.swift + BetaProvenance enum (n5k_single_dominant, n5k_mixture, gravimetric, none).
  - Decision 16: provenance is a dimension separate from BetaCalibrationStatus, which stays a three-value enum so existing consumers' switches don't break.
  - Blocked-by: i3we698 (Write failing tests for BetaCalibrator PerClassFit outputs and CalibrationMerge arbitration)
  - Stream: 3
  - Requirements: [5.2](requirements.md#5.2), [5.4](requirements.md#5.4)
  - References: HarnessCore/BetaCalibrator.swift

- [x] 17. Write failing tests for FixtureLoader per-path guards <!-- id:i3we69a -->
  - Guard matrix (design §Testing, Decision 17): a mixture fixture with sentinel SHA "no_segmenter" loads on the mixture path; a mixture fixture carrying segmentation probabilities is rejected; a single_dominant fixture with a wrong, missing, empty, or sentinel SHA is rejected; an unknown estimator_path value is malformed; a missing/empty SHA is never coerced to the sentinel.
  - estimator_path is the AUTHORITATIVE path selector — the sentinel string alone must not select the path, or any fixture could bypass the hash guard by writing the magic value.
  - Blocked-by: i3we68v (Redefine ClassPalette v1 in place and land the proto contract extensions)
  - Stream: 3
  - Requirements: [3.7](requirements.md#3.7)
  - References: HarnessCore/FixtureLoader.swift

- [x] 18. Implement FixtureLoader per-path guards <!-- id:i3we69b -->
  - HarnessCore/FixtureLoader.swift: per-path guards keyed off the estimator_path proto field; the existing checkpoint-SHA hash guard is unchanged on the single-dominant path.
  - Blocked-by: i3we69a (Write failing tests for FixtureLoader per-path guards)
  - Stream: 3
  - Requirements: [3.7](requirements.md#3.7)
  - References: HarnessCore/FixtureLoader.swift

- [x] 19. Write failing tests for AccuracyHarness k-fold eval and report content <!-- id:i3we69c -->
  - Synthetic mini-split fixtures.
  - k-fold CV over the calibration set with ONE recorded seed for selection + folds (4.4/6.1) — no staple stranded below the 30-effective-sample floor by splitting; the bake itself fits on ALL qualifying plates (design §Split reconciliation).
  - Mapped-classes-only GT basis for carbs AND protein/fat (6.2/6.6); per-staple + overall MAPE/MAE for BOTH β=1.0 and β_c (6.3); per-class dispersion — mixture classes report regression SE (6.4); MAPE<20% target stated as a reported result, not a gate (6.5).
  - Cross-macro consistency: carb agrees but protein/fat MAPE > 1.5× the class carb MAPE → flag as likely mapping/composition-source error (6.7).
  - Official-split whole-dish section (6.8): MAE + MAE÷mean-actual over evaluated dishes; evaluated-dish count vs split total (enumerating skips); mapped-carb coverage fraction; the oracle caveat text (figures "reported alongside, not claimed comparable with" the paper's Table 3 image-only baseline); unmapped AND liquid-mapped ingredients contribute zero estimate but full GT carbs.
  - Pool arithmetic report (4.5): ~3.5k RGB-D − depth_test_ids.txt − ingestion skips − liquid exclusions, effective samples broken out per estimator path; insufficient/unidentifiable are documented accepted outcomes.
  - Blocked-by: i3we693 (Implement HarnessCore/TotalHullVolume.swift), i3we699 (Extend BetaCalibrator and implement CalibrationMerge with BetaProvenance)
  - Stream: 3
  - Requirements: [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [6.7](requirements.md#6.7), [6.8](requirements.md#6.8)
  - References: HarnessCore/AccuracyHarness.swift

- [x] 20. Extend AccuracyHarness and the calibration report <!-- id:i3we69d -->
  - Extend HarnessCore/AccuracyHarness.swift.
  - Multi-class eval plates: attribute the measured hull volume across mapped classes by ground-truth mass proportions (oracle composition — a recorded caveat); each share × ρ_c × β_c × carb-fraction.
  - Mixture held-out eval runs on the same hull-volume basis it was fit on; the masking-transfer gap stays a recorded caveat pre-checkpoint (5.1) — Req 3.7 forbids masks on mixture fixtures.
  - Blocked-by: i3we69c (Write failing tests for AccuracyHarness k-fold eval and report content)
  - Stream: 3
  - Requirements: [5.1](requirements.md#5.1), [6.1](requirements.md#6.1), [6.3](requirements.md#6.3), [6.6](requirements.md#6.6), [6.8](requirements.md#6.8)
  - References: HarnessCore/AccuracyHarness.swift

- [x] 21. Write failing tests for HarnessCLI calibrate wiring and the calibrate JSON artifact <!-- id:i3we69e -->
  - Depth-test-split exclusion (data/dish_ids/splits/depth_test_ids.txt — the RGB-D split, NOT the rgb_* files) applied before any selection (4.4).
  - τ_purity=0.90 volume-purity gate applied post-estimate on single_dominant fixtures: purity = above-plane volume of pixels whose segmenter argmax equals the mass-dominant class ÷ total above-plane food-region volume (sentinel/at-cap excluded); failures DROPPED and recorded, never re-routed (4.2 / 5.2 at-most-one-estimator invariant).
  - JSON artifact — the sole stream B↔C interface (design §DB bake handoff contract): per class {beta, status, provenance, standard_error, effective_sample, clamped} + a lineage block {release identifier, metadata version, mapping-artifact version, τ_route/τ_purity/τ_eff/κ thresholds, seed, per-class effective samples, conditioning diagnostics, pinned intrinsics model, licence CC BY 4.0} (5.5).
  - Blocked-by: i3we699 (Extend BetaCalibrator and implement CalibrationMerge with BetaProvenance), i3we69b (Implement FixtureLoader per-path guards)
  - Stream: 3
  - Requirements: [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.5](requirements.md#5.5)
  - References: HarnessCLI/main.swift

- [x] 22. Implement HarnessCLI calibrate / calibrate-and-eval wiring and JSON emission <!-- id:i3we69f -->
  - HarnessCLI/main.swift calibrate + calibrate-and-eval: route fixtures per estimator_path — single_dominant through the existing BetaCalibrator on the HeightFieldEstimator masking path (5.1); mixture through TotalHullVolume + MixtureBetaCalibrator; CalibrationMerge decides per-class β; write the JSON artifact.
  - Extend the existing CalibrationJSON writer rather than adding a parallel output path.
  - Blocked-by: i3we69d (Extend AccuracyHarness and the calibration report), i3we69e (Write failing tests for HarnessCLI calibrate wiring and the calibrate JSON artifact)
  - Stream: 3
  - Requirements: [1.4](requirements.md#1.4), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.5](requirements.md#5.5)
  - References: HarnessCLI/main.swift

## Stream C — Palette lock, liquids, DB bake

- [x] 23. Write failing tests for liquid DB rows, provenance columns, and new tables <!-- id:i3we69g -->
  - tools/food_db/tests: 8 coarse liquid FOOD_DATA rows (water, coffee, tea, milk, fruit_juice, soup, beer, wine) each with carb, density, and per-row source (7.1); beta_provenance TEXT NOT NULL DEFAULT 'none' + device_verified INTEGER NOT NULL DEFAULT 0 columns (5.4 / banner plumbing); liquid_servings(class_id, region, vessel, serving_ml, source) PK(class_id, region, vessel) with a CLOSED region/vessel vocabulary — a lookup miss is a hard error, not a silent zero (7.4/7.7); liquid_subclasses(class_id, sub_class, carbs_mono_100, density, source) PK(class_id, sub_class) with beer → lager/stout rows (7.5, Decision 24); the len(FOOD_DATA)==24 count guard moves to 24 solid + 8 liquid.
  - Blocked-by: i3we68v (Redefine ClassPalette v1 in place and land the proto contract extensions)
  - Stream: 4
  - Requirements: [5.4](requirements.md#5.4), [7.1](requirements.md#7.1), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)
  - References: tools/food_db/generate.py, tools/food_db/tests

- [x] 24. Implement generate.py schema additions and liquid data <!-- id:i3we69h -->
  - tools/food_db/generate.py: CoFID-primary liquid values, AFCD/USDA-sourced values in AFCD_DATA per the existing CoFID-wins merge; canonical serving volumes region-keyed (e.g. UK pint 568 mL) with provenance — a separate table, never a foods column (region-dependent, 7.7).
  - No basis column: N5k masses are as-served by construction; the convention is recorded in a generate.py comment (design §DB bake — the density spot-check IS the assert, tested in the bake task).
  - Blocked-by: i3we69g (Write failing tests for liquid DB rows, provenance columns, and new tables)
  - Stream: 4
  - Requirements: [7.1](requirements.md#7.1), [7.4](requirements.md#7.4), [7.7](requirements.md#7.7)
  - References: tools/food_db/generate.py

- [x] 25. Write failing tests for the palette-lock content check and FoodSeg103 remap <!-- id:i3we69i -->
  - verify_palette_lock parses the ordered class list from ClassPalette.swift (foodClasses then liquidClasses, declaration order, sentinels excluded — extend the existing regex-read pattern) and asserts exact equality with FOOD_DATA ids/order; a stale pre-liquid list must fail on CONTENT with the "v1" label unchanged (5.7/7.2, Decision 23).
  - build_class_mapping.py: parse_palette's 24-class assert moves to the new total; wine/coffee/tea/milk/juice/soup/beer FoodSeg103 categories route to the coarse liquid classes instead of unsupported_liquid (7.2).
  - Blocked-by: i3we69h (Implement generate.py schema additions and liquid data)
  - Stream: 4
  - Requirements: [5.7](requirements.md#5.7), [7.2](requirements.md#7.2)
  - References: tools/food_db/generate.py, tools/segmenter/build_class_mapping.py

- [x] 26. Implement the palette-lock content check, remap update, and artifact regeneration <!-- id:i3we69j -->
  - Regenerate every palette-locked artifact in the same change: both sqlite DBs and tools/segmenter/class_mapping_foodseg103_v1.json (Decision 23 consequence — the content lock enforces this discipline; no CI hook per PROCESS §8, fail-loud loaders instead).
  - Blocked-by: i3we69i (Write failing tests for the palette-lock content check and FoodSeg103 remap)
  - Stream: 4
  - Requirements: [5.7](requirements.md#5.7), [7.2](requirements.md#7.2)
  - References: tools/segmenter/build_class_mapping.py, tools/segmenter/class_mapping_foodseg103_v1.json

- [x] 27. Write failing tests for bake consumption of the calibrate JSON <!-- id:i3we69k -->
  - Hand-written calibrate-JSON fixture (do NOT depend on stream B landing first — the JSON contract in design §DB bake is the interface).
  - β/status/provenance/SE/effective-sample written per row with device_verified defaulting 0 (5.4); a clamped class → calibration-quality warning, never silent acceptance (5.6); supersession: prior DB holds a mixture β, JSON holds a qualifying single-dominant β → supersession recorded in lineage meta (5.2 — generate.py reads the prior DB; the JSON carries no prior-bake state); density-basis spot-check: N5k-implied density (mass ÷ measured volume) vs DB ρ outside tolerance on rice/pasta ABORTS the bake (5.3 — the spot-check IS the assert); lineage meta rows incl. the pinned intrinsics model and licence CC BY 4.0 (1.5/5.5); palette lock runs and aborts on version mismatch (5.7).
  - Blocked-by: i3we69h (Implement generate.py schema additions and liquid data)
  - Stream: 4
  - Requirements: [1.5](requirements.md#1.5), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7)
  - References: tools/food_db/generate.py

- [x] 28. Implement the bake path in generate.py <!-- id:i3we69l -->
  - generate.py consumes the JSON artifact via a flag (e.g. --calibration-json); without the flag the current uncalibrated defaults are unchanged.
  - Blocked-by: i3we69k (Write failing tests for bake consumption of the calibrate JSON)
  - Stream: 4
  - Requirements: [1.5](requirements.md#1.5), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7)
  - References: tools/food_db/generate.py

- [x] 29. Write failing property tests for liquid surface-to-plane volume <!-- id:i3we69m -->
  - Swift Testing property test: flat and tilted synthetic liquid surfaces integrate surface-to-plane to their analytic volume within tolerance (7.3).
  - A recognised liquid class integrates via isLiquidClass; unsupported_liquid stays skipped; carb = volume × density × carb-fraction; the estimate raises the liquid over-estimate flag — the integration includes the vessel base/walls, a known upward bias (Decision 19).
  - Blocked-by: i3we68v (Redefine ClassPalette v1 in place and land the proto contract extensions)
  - Stream: 4
  - Requirements: [7.3](requirements.md#7.3)
  - References: MedataCore/Sources/Volume/HeightFieldEstimator.swift

- [x] 30. Implement HeightFieldEstimator liquid integration <!-- id:i3we69n -->
  - MedataCore/Sources/Volume/HeightFieldEstimator.swift: replace the blanket liquid skip (if labelC == liquidId { continue }) — recognised liquid classes integrate to the support plane; unsupported_liquid still skipped.
  - Blocked-by: i3we69m (Write failing property tests for liquid surface-to-plane volume)
  - Stream: 4
  - Requirements: [7.3](requirements.md#7.3)
  - References: MedataCore/Sources/Volume/HeightFieldEstimator.swift

- [x] 31. Write failing tests for LiquidResolver <!-- id:i3we69o -->
  - The vessel canonical mapping is a pure function (vessel_label, sub_class, region) → liquid_servings.serving_ml × DB carb density: parameterised table test over each vessel/sub-class/region, generic coarse-row fallback when the sub-class is uncertain (7.5 — no assumed lager<stout ordering; densities from the DB), closed-vocabulary miss raises an error (7.4).
  - Precedence (7.6): recognised standard vessel → canonical-volume estimate; else recognised liquid class with usable surface depth → depth-integrated estimate; else exclude + flag — never an unbacked carb number.
  - BOTH estimate paths raise liquidOverEstimate (Decision 19). Region comes from a Settings value defaulting to UK.
  - Blocked-by: i3we68v (Redefine ClassPalette v1 in place and land the proto contract extensions), i3we69h (Implement generate.py schema additions and liquid data)
  - Stream: 4
  - Requirements: [7.4](requirements.md#7.4), [7.5](requirements.md#7.5), [7.6](requirements.md#7.6)
  - References: specs/estimation/nutrition5k-calibration/design.md

- [x] 32. Implement MedataCore/Sources/Volume/LiquidResolver.swift <!-- id:i3we69p -->
  - New MedataCore/Sources/Volume/LiquidResolver.swift; sits after segmentation where liquid classes are detected; returns a carb value + over-estimate flag or an exclusion + flag; sets the result-level liquidOverEstimate.
  - Vessel/sub-class recognition stays the deferred model-production dependency (7.7) — the resolver is fully unit-testable from label inputs.
  - Blocked-by: i3we69o (Write failing tests for LiquidResolver)
  - Stream: 4
  - Requirements: [7.4](requirements.md#7.4), [7.5](requirements.md#7.5), [7.6](requirements.md#7.6), [8.2](requirements.md#8.2)
  - References: MedataCore/Sources/Volume/HeightFieldEstimator.swift

## Stream D — App plumbing and banner

- [x] 33. Write failing tests for DB-read and macros plumbing <!-- id:i3we69q -->
  - FoodsTests: GRDBFoodDatabase.rowToEntry reads beta_provenance + device_verified into FoodEntry.
  - MacrosTests: Macros.compute populates PerClassMacros.proteinG/fatG from the same β-corrected per-class mass × the DB protein/fat fraction (10.1 — no separate fit); copies deviceVerified and isLiquid onto each PerClassMacros (banner inputs, 8.1); carbs stay primary, protein/fat additive (10.2); no UI surfacing (10.3).
  - Blocked-by: i3we68v (Redefine ClassPalette v1 in place and land the proto contract extensions), i3we69h (Implement generate.py schema additions and liquid data)
  - Stream: 5
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2)
  - References: MedataCore/Sources/Foods/GRDBFoodDatabase.swift, MedataCore/Sources/Macros/Macros.swift

- [x] 34. Implement FoodEntry/rowToEntry and Macros.compute plumbing <!-- id:i3we69r -->
  - MedataCore/Sources/Foods/GRDBFoodDatabase.swift + MedataCore/Sources/Macros/Macros.swift; thread liquidOverEstimate through the estimate result (MacroResult) so ResultView needs no new lookups (design §Banner plumbing).
  - Blocked-by: i3we69q (Write failing tests for DB-read and macros plumbing)
  - Stream: 5
  - Requirements: [10.1](requirements.md#10.1), [10.2](requirements.md#10.2), [10.3](requirements.md#10.3)
  - References: MedataCore/Sources/Foods/GRDBFoodDatabase.swift, MedataCore/Sources/Macros/Macros.swift

- [x] 35. Extend the showsUncalibratedBanner tests to the three-state matrix <!-- id:i3we69s -->
  - Extend the existing ResultFormat.showsUncalibratedBanner test with the flag-injection matrix (8.1): any pooled/unity solid class → full banner; all calibrated + any not device-verified → softened; all calibrated + all device-verified (injected — otherwise unreachable in this spec) → suppressed; liquid classes never enter the evaluation; a standalone drink (no contributing solid class) shows NO calibration banner with the liquid flag standing alone (a stated rule, not vacuous suppression); the liquid flag renders additively with each of the three states (8.2).
  - Blocked-by: i3we69r (Implement FoodEntry/rowToEntry and Macros.compute plumbing)
  - Stream: 5
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: App/ResultView.swift

- [x] 36. Implement the three-state banner and additive liquid flag in ResultView <!-- id:i3we69t -->
  - App/ResultView.swift: showsUncalibratedBanner's boolean becomes the three-state calibration-confidence signal plus the independent additive liquid flag; softened copy "population-calibrated — not yet verified on this device"; reuse the existing banner styling — presentation stays model-production-owned (8.3).
  - British English; run bash tools/check_spelling.sh.
  - Blocked-by: i3we69s (Extend the showsUncalibratedBanner tests to the three-state matrix)
  - Stream: 5
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3)
  - References: App/ResultView.swift

- [x] 37. Add the Nutrition5k attribution row to SettingsView <!-- id:i3we69u -->
  - App/SettingsView.swift "About macronutrient sources": add a Nutrition5k row matching the existing CoFID/OGL line — Google Research, CC BY 4.0, values adapted (derived β factors) (1.5).
  - UI string wiring — TDD-exempt; run bash tools/check_spelling.sh.
  - Stream: 5
  - Requirements: [1.5](requirements.md#1.5)
  - References: App/SettingsView.swift

## Stream E — Spec alignment (docs)

- [x] 38. Update cross-spec documentation <!-- id:i3we69v -->
  - specs/estimation/pipeline dataset-overlap section (§20.2): add Nutrition5k and its β_c calibration use (9.1).
  - specs/estimation/model-production: record the final-v1 palette class-list lock (the enumerated list incl. liquid classes) as a Stage 3 training prerequisite (9.4, Decisions 22–23).
  - tools/segmenter/README.md: document the N5k partial layout + acquisition steps per prerequisites.md (1.3).
  - Verify the population-transfer + nominal-intrinsics risk (9.3) and the liquid-reversal cross-reference (9.2) are recorded — both already live in this spec's design/decision log; add pointers where missing.
  - Run bash tools/check_spelling.sh.
  - Stream: 6
  - Requirements: [1.3](requirements.md#1.3), [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4)
  - References: specs/estimation/pipeline, specs/estimation/model-production, tools/segmenter/README.md

## Integration

- [x] 39. Run the pre-checkpoint end-to-end calibration and bake <!-- id:i3we69w -->
  - Agent-executable pre-checkpoint run (prerequisites.md): re-fetch any missing bucket files from gs://nutrition5k_dataset; tools/nutrition5k/ingest.py over data/ (all-mixture, sentinel SHA) → HarnessCLI calibrate-and-eval → calibrate JSON + accuracy report → generate.py bake → both sqlite DBs.
  - Confirm empirically whether the plate fills the N5k overhead frame (Decision 15 open check) and that the two reference-depth checks pass on real captures; verify the 4.5 pool-arithmetic/feasibility report is produced (insufficient classes are documented outcomes, not failures).
  - Commit the calibrate JSON, report, and baked DBs — never N5k imagery/metadata (1.1).
  - Gates: swift build && swift test green; pytest green; bash tools/check_spelling.sh.
  - The post-checkpoint single-dominant re-fit + supersession re-run stays a documented manual step gated on model-production Bucket C — deliberately NOT a task here.
  - Blocked-by: i3we68z (Implement tools/nutrition5k/ingest.py (pre-checkpoint mode) and extend build_fixture_bytes), i3we69f (Implement HarnessCLI calibrate / calibrate-and-eval wiring and JSON emission), i3we69j (Implement the palette-lock content check, remap update, and artifact regeneration), i3we69l (Implement the bake path in generate.py)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.4](requirements.md#1.4), [4.5](requirements.md#4.5)
  - References: specs/estimation/nutrition5k-calibration/prerequisites.md

## Closeout — worktree consolidation

- [x] 40. Commit the in-flight nutrition5k worktree changes once gates pass <!-- id:i3we69x -->
  - In .worktrees/nutrition5k-calibration: run swift test (report both XCTest and swift-testing totals), pytest for tools/nutrition5k tools/food_db tools/segmenter, and bash tools/check_spelling.sh.
  - If green, commit the in-flight WIP (~560 lines across 21 files: HarnessCLI/HarnessCore calibrator work, MealFixture.proto + regenerated .pb.swift, tools, tests, agent notes, spec docs including this closeout phase and Decision 29).
  - Success: git status clean in the worktree; all gates green.
  - References: specs/estimation/nutrition5k-calibration/decision_log.md

- [x] 41. Merge nutrition5k-calibration into research <!-- id:i3we69y -->
  - Retarget note (2026-07-04): uplift-process-fixes was fast-forwarded into research (both at bb314a5); the consolidation target is now the research branch, which is checked out in the main worktree and tracks origin/research.
  - From the main worktree (/Users/r/repos/medata) on branch research: git merge nutrition5k-calibration.
  - Expected mechanical conflicts: .gitignore and tools/check_spelling.sh (keep both sides' intent); CHANGELOG.md union-merges automatically.
  - From this point the merged copy of this tasks file (specs/estimation/nutrition5k-calibration/tasks.md in the main worktree) is the live ledger — tick the remaining tasks there.
  - Success: merge committed; make test green (report both XCTest and swift-testing totals).
  - Blocked-by: i3we69x (Commit the in-flight nutrition5k worktree changes once gates pass)

- [x] 42. Merge resumable-segmenter-training into research <!-- id:i3we69z -->
  - git merge resumable-segmenter-training. Expected semantic conflicts in tools/segmenter/export.py and tools/segmenter/train.py: resolution must keep BOTH behaviours — the n5k palette/liquids changes AND the crash-safe --resume sidecar.
  - Do not hand-merge specs/OVERVIEW.md — it is regenerated in the next task (PROCESS.md §9).
  - Success: merge committed; make test green; pytest for tools/segmenter green.
  - Blocked-by: i3we69y (Merge nutrition5k-calibration into research)
  - References: specs/estimation/resumable-segmenter-training/smolspec.md

- [x] 43. Regenerate specs/OVERVIEW.md and spell-check <!-- id:i3we6a0 -->
  - Run /specs-overview to regenerate the index (never hand-merge, PROCESS.md §9); bash tools/check_spelling.sh; commit.
  - Success: OVERVIEW.md lists both merged specs; spelling lint clean.
  - Blocked-by: i3we69z (Merge resumable-segmenter-training into research)

- [ ] 44. Delete both worktrees and their branches <!-- id:i3we6a1 -->
  - git worktree remove .worktrees/nutrition5k-calibration and .worktrees/resumable-segmenter-training; then git branch -d nutrition5k-calibration resumable-segmenter-training (lowercase -d so git itself verifies both are fully merged before deletion).
  - Success: git worktree list shows only the main worktree; both branches gone.
  - Blocked-by: i3we6a0 (Regenerate specs/OVERVIEW.md and spell-check)

- [ ] 45. Push research to origin <!-- id:i3we6a2 -->
  - git push origin research — explicitly authorised by the user in nextup.md (push is otherwise denied in .claude/settings.local.json). If the harness denies the push, report it as blocked for the user to run rather than failing.
  - Also safe afterwards: git branch -d uplift-process-fixes (fully merged, redundant).
  - Success: origin/research equals local HEAD.
  - Blocked-by: i3we6a1 (Delete both worktrees and their branches)

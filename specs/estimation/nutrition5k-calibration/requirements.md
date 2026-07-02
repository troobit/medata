# Requirements: nutrition5k-calibration

## Introduction

This feature uses the Google Nutrition5k dataset (5,006 plates — the README figure; the CVPR paper cites 5,066 — with per-ingredient gravimetric mass, protein, fat, and carbohydrate, of which roughly 3,500 dishes carry overhead RealSense RGB-D) as a population ground-truth source to derive per-class β_c bulk-correction factors, replacing the uncalibrated β = 1.0 default that biases carb estimates upward. N5k overhead RGB-D is bridged into the existing `MealFixture` format and run through the existing `HarnessCLI calibrate` loop using the same volume estimator the device uses, so the fitted β transfers to inference; the resulting β_c values are baked into the food database with full lineage. Because β corrects volume to mass, the correction benefits all macros, so N5k's protein and fat are used to validate the calibration, to cross-check the class mapping, and as additional pipeline outputs (carbs remain primary; UI display of protein/fat is deferred). The feature also reverses the v1 out-of-scope decision for standalone liquids, adding liquid classes and carb/density values from UK/AU/US food databases, while leaving end-to-end liquid carb validation to a later spec.

## Non-Goals

- Training or fine-tuning the segmenter — N5k has no per-pixel masks (Decision 3); segmentation accuracy stays owned by model-production/FoodSeg103.
- Bundling a trained `segmenter.mlpackage` or resolving `segmenterModelMissing` — owned by model-production Bucket C; a trained checkpoint is still required.
- YCbCr→BGRA full-range pixel conversion — owned by rawframe-rgb-conversion.
- ANE residency / on-device inference-latency tuning — owned by model-production.
- On-device carb-accuracy measurement — this spec measures MAPE/MAE only on the offline N5k eval split.
- Individual (per-user) β fine-tuning — N5k provides population calibration only.
- End-to-end validation of liquid carb output — N5k has no standalone-liquid mass/volume ground truth; liquid carb numbers are emitted from database values but are not validated in this spec (Decision 7).
- Modelling container geometry (taper, base, wall thickness) for liquids — liquid volume is integrated from the visible surface to the support plane.
- Surfacing protein/fat (or fat-protein units) in the UI — excluded from this spec and recorded as a required future spec under the `ui/` domain (Decision 13); this spec emits the values but does not display them.

## Requirements

### 1. Local N5k dataset acquisition and layout

**User Story:** As a developer, I want N5k to live in a documented local gitignored location with a pinned release, so that calibration is reproducible and the large dataset is never committed.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL read N5k inputs from a local directory that is excluded from version control, and SHALL NOT add any N5k imagery, depth, or metadata to the repository.  
2. <a name="1.2"></a>WHEN the configured N5k directory is absent or missing required files, the ingestion tool SHALL exit with a non-zero status and a message naming the expected path and the missing artifact.  
3. <a name="1.3"></a>The repository SHALL document the expected N5k directory layout and acquisition steps — the partial layout this spec consumes (`imagery/realsense_overhead/dish_<id>/{rgb.png, depth_raw.png}`, the metadata CSVs, and the official split files), not the full archive — in the spec's prerequisites and the ML training docs, and that documented layout SHALL define "required files" for [1.2](#1.2).  
4. <a name="1.4"></a>The ingestion run SHALL record the N5k release identifier — defined operationally as a SHA-256 manifest of the fetched metadata and split files plus the download date, since the source bucket is unversioned — the ingredient-metadata version, and the count of plates actually ingested (the RGB-D subset differs from the headline dish count), and downstream artifacts SHALL carry that identifier.  
5. <a name="1.5"></a>The application SHALL attribute the Nutrition5k dataset (CC BY 4.0) on the About/Legal screen alongside the existing food-database attributions, indicating that the shipped values are adapted (derived β factors) as CC BY 4.0 requires, and the calibration lineage SHALL record the dataset licence.  

### 2. N5k ingredient-to-palette class mapping

**User Story:** As a developer, I want N5k ingredient IDs mapped to MeData's canonical food classes, so that calibration attributes mass to the correct class.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL provide a mapping from N5k ingredient IDs to MeData food-class IDs that preserves the channel order defined by `tools/food_db/generate.py` FOOD_DATA, expressed against the current `ClassPalette` rather than a fixed class count.  
2. <a name="2.2"></a>The mapping SHALL cover the eight carb-priority staples (white_rice, brown_rice, pasta, bread_white, bread_wholemeal, potato_boiled, potato_mashed, chips_fries) where corresponding N5k ingredients exist.  
3. <a name="2.3"></a>WHEN an N5k ingredient has no corresponding MeData class, the mapping SHALL exclude it from calibration rather than assign it to an unrelated class.  
4. <a name="2.4"></a>WHERE N5k's ingredient taxonomy does not distinguish a MeData class pair (e.g. white vs brown rice, boiled vs mashed potato, white vs wholemeal bread), the mapping SHALL record the ambiguity and SHALL NOT silently assign an ambiguous ingredient to one side of the pair.  
5. <a name="2.5"></a>The mapping SHALL be a versioned artifact tied to both the palette content — the ordered class list, not only `ClassPalette.version`, since the redefined v1 keeps its label (Decision 23) — and the N5k ingredient-metadata version, and SHALL fail loudly if either does not match what it was built against.  

### 3. N5k RGB-D to MealFixture bridge

**User Story:** As a developer, I want N5k overhead RGB-D converted into `.fixture` files, so that the existing harness can consume N5k as `single_view_lidar` captures.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL convert N5k raw depth — 16-bit integers in units of 10⁻⁴ m (10,000 units = 1 m), so millimetres = units ÷ 10 — to MeData `DepthMap.depthBytesMm` (Float32 little-endian, millimetres), and SHALL verify the conversion against at least two reference depths of independently documented ground truth (e.g. the fixed rig camera-to-plate distance and a known plate-height feature), both strictly below the 0.4 m saturation cap (where clamping cannot mask a scale error), aborting ingestion when the converted values fall outside a documented tolerance band.  
2. <a name="3.2"></a>The system SHALL exclude N5k invalid-return (sentinel 0) and at-cap (saturated maximum) depth pixels from the silhouette and the volume integral, rather than treating them as valid surfaces.  
3. <a name="3.3"></a>The system SHALL emit each ingested N5k plate as a `MealFixture` with `capture_path_canonical = "single_view_lidar"`, the converted nadir depth, the nadir RGB image, and `nadir_intrinsics` from a documented, pinned camera model recorded in lineage — N5k publishes no per-capture RealSense calibration (verified against the dataset bucket and repository), so the intrinsics SHALL come from a stated nominal source (e.g. the RealSense D435 factory model at the captured resolution), and the resulting systematic volume-scale risk SHALL be folded into the population-transfer caveat ([9.3](#9.3)).  
4. <a name="3.4"></a>WHEN a plate's depth/RGB registration is unusable — the images cannot be aligned under the pinned camera model of [3.3](#3.3) — the tool SHALL skip that plate and record it. Intrinsics are the single documented pinned model for every plate ([3.3](#3.3)); the tool SHALL NOT substitute ad-hoc per-plate intrinsics.  
5. <a name="3.5"></a>Each emitted fixture SHALL set `ground_truth_class_mass_g` from N5k per-ingredient mass (mapped per [2](#2)) and SHALL carry N5k per-dish carbohydrate, protein, and fat totals as ground truth (extending the fixture schema where it currently records only carbohydrate).  
6. <a name="3.6"></a>Each emitted fixture SHALL set the gravity vector and support-plane inputs so that volume is integrated above the surface the food rests on (the plate top), not the surrounding table.  
7. <a name="3.7"></a>Each fixture SHALL carry an estimator-path field (`single_dominant` | `mixture`) that authoritatively selects the load path. Single-dominant fixtures SHALL carry the `segmenter_checkpoint_sha256` of the checkpoint that produced their segmentation probabilities, and the single-dominant load path SHALL reject a fixture whose SHA is missing, empty, or the sentinel. Mixture fixtures, whose volume derives from the depth silhouette alone, SHALL carry the literal sentinel `"no_segmenter"`, SHALL NOT carry segmentation probabilities, and SHALL be accepted only on the mixture-only load path (Decision 17). A missing or empty SHA SHALL be treated as malformed — rejected by the loader, and skipped at ingestion per [3.8](#3.8) — never coerced to the sentinel.  
8. <a name="3.8"></a>WHEN a plate's depth, RGB, or mass metadata is malformed or missing, the tool SHALL skip that plate, record it in the run summary, and continue.  

### 4. Calibration data usage and feasibility gate

**User Story:** As a developer, I want calibration to use as much of N5k as possible — both clean single-item plates and multi-ingredient plates — and to know up front how many samples each class gets, so that β is attributed cleanly, the dataset is not wasted, and the feature's value is verified before committing.

**Acceptance Criteria:**

1. <a name="4.1"></a>The system SHALL use both single-dominant-staple plates and multi-ingredient plates whose significant ingredients all map to known classes, rather than restricting calibration to single-dominant plates.  
2. <a name="4.2"></a>For a single-dominant plate, the system SHALL attribute the depth-derived food region (sentinel/at-cap pixels excluded per [3.2](#3.2)) to the one dominant class, using a documented above-plane-volume purity threshold so low-mass high-volume contaminants do not enter the attributed region.  
3. <a name="4.3"></a>For a multi-ingredient plate, the system SHALL attribute the plate's total above-plane hull volume across its per-ingredient masses so each mapped class contributes to its β fit, under a documented additive-volume assumption (items do not overlap or stack). The system SHALL exclude plates whose measured hull is implausibly small relative to the sum of expected per-ingredient volumes at β ≈ 1 (a computable stacking/occlusion guard), and SHALL document residual sauce/stacking error as an accepted systematic bias.  
4. <a name="4.4"></a>Plate selection and any calibration/evaluation split SHALL be driven by a fixed, recorded random seed so that results are reproducible run-to-run, and calibration SHALL exclude every dish in N5k's official depth test split (`dish_ids/splits/depth_test_ids.txt` — the split whose dishes carry RGB-D, distinct from the `rgb_*` split files) so the paper-comparable report ([6.8](#6.8)) is computed on data the fit never saw.  
5. <a name="4.5"></a>Before baking, the run SHALL report, per class, an effective-sample measure (plates where the class exceeds a documented mass-fraction, not the raw count of plates it merely appears on) and the fit's identifiability for that class, assessed against the ingested calibration pool — dishes carrying overhead RGB-D (roughly 3,500 of the ~5,000), minus the official depth test split ([4.4](#4.4)) and ingestion-skipped plates ([3.4](#3.4)/[3.8](#3.8)) — with the pool size stated in the report and effective-sample counts broken out per estimator path (single-dominant vs mixture, since only single-dominant β carries the [5.1](#5.1) masking guarantee), and SHALL treat "insufficient" or "not individually identifiable" as documented, accepted outcomes rather than failures.  
6. <a name="4.6"></a>WHEN a class is under-sampled or not individually identifiable, the system SHALL leave it on the existing pooled/unity fallback (not fabricate or duplicate samples), and its volume contribution SHALL be subtracted as a fixed offset in the joint solve so it is not misattributed to identifiable classes.  
7. <a name="4.7"></a>Standalone-liquid classes ([7](#7)) SHALL be excluded from the N5k β fit — their carb and density values are database-sourced ([7.1](#7.1)) and N5k provides no liquid ground truth (Decision 9). A plate carrying a significant liquid-mapped ingredient (e.g. soup) SHALL be excluded from the mixture fit entirely, not merely have the liquid dropped from the sum: the vessel-plus-liquid volume stays in the plate's measured hull and would be misattributed to co-occurring solid classes' β, and vessel geometry breaks the additive-volume assumption ([4.3](#4.3)). These exclusions SHALL be counted in the [4.5](#4.5) pool report.  

### 5. β_c calibration run and database bake

**User Story:** As a developer, I want N5k-derived β_c baked into the food database with lineage, so that estimates use corrected volumes and the calibrated database is auditable.

**Acceptance Criteria:**

1. <a name="5.1"></a>The volume used to fit a single-dominant-plate β SHALL be produced by the same `HeightFieldEstimator` and masking path the device pipeline uses at inference, so that β corrects inference-time volume rather than a calibration-only silhouette bias. β derived from the mixture fit ([4.3](#4.3)) is fit against total mass-attributed volume and does NOT carry this masking guarantee; it SHALL be recorded with a distinct provenance and the residual masking-transfer gap noted.  
2. <a name="5.2"></a>Each plate SHALL contribute to at most one estimator — the single-dominant loop or the mixture fit, never both; a plate that fails the [4.2](#4.2) purity gate after routing contributes to neither and SHALL be recorded — and each class SHALL receive one β from one estimator, with the choice recorded, so no plate or class is double-counted. WHEN a calibration run executes with a segmenter checkpoint available, classes whose single-dominant fit passes the [5.4](#5.4) effective-sample, identifiability, and standard-error gates SHALL be re-fit on that path, and the qualifying single-dominant β SHALL supersede a previously baked mixture β for that class (higher-guarantee provenance wins; a single-dominant fit that fails the gates leaves the mixture β in place), with the supersession recorded in lineage.  
3. <a name="5.3"></a>The β fit SHALL use the same per-class density ρ that the pipeline uses at inference, and the bake SHALL assert that N5k masses (cooked/as-served) and the database ρ and carb-fraction share a cooked/as-served basis. The bake SHALL note that in the mixture fit a ρ error in one class couples into co-occurring classes' β, and reflect this in the dispersion report ([6.4](#6.4)).  
4. <a name="5.4"></a>The bake SHALL set `beta_status = "calibrated"` for a class only when it meets the effective-sample minimum AND is individually identifiable with a fit standard error within a documented bound — not on raw plate count — leaving all other classes at pooled/unity. It SHALL record per row whether the β provenance is N5k single-dominant, N5k mixture, or hand-measured gravimetric.  
5. <a name="5.5"></a>The bake SHALL record calibration lineage: N5k release/metadata version, mapping-artifact version, purity/mass-fraction thresholds, selection seed, per-class effective-sample counts, and the mixture fit's conditioning/identifiability diagnostics.  
6. <a name="5.6"></a>WHEN a fitted β is clamped to the calibrator's bounds, the bake SHALL emit a calibration-quality warning for that class rather than silently accept the clamped value.  
7. <a name="5.7"></a>The bake SHALL run the existing palette-lock verification and SHALL abort if `ClassPalette.version` does not match the palette version the database is built against.  

### 6. Carb-accuracy reporting on the N5k eval split

**User Story:** As a developer, I want carb-accuracy reported against a β=1.0 baseline on a held-out N5k split, so that I can see whether population β_c actually improves estimates.

**Acceptance Criteria:**

1. <a name="6.1"></a>The system SHALL compute MAPE and MAE over an evaluation set disjoint from the calibration set, using a split policy that does not further drop a staple below the 30-effective-sample calibration minimum ([4.5](#4.5)) (e.g. cross-validation over the calibration set rather than a single holdout); WHERE the official-test-split exclusion ([4.4](#4.4)) alone pushes a staple under the minimum, that class stays on pooled/unity per [4.6](#4.6) and is reported per [4.5](#4.5).  
2. <a name="6.2"></a>The evaluation ground truth SHALL be the carbohydrate of mapped classes only, so that carbs from unmapped/excluded ingredients do not inflate the error.  
3. <a name="6.3"></a>The report SHALL include, per carb-priority staple and overall, MAPE and MAE for both the β=1.0 baseline and the β_c-calibrated run, so the improvement (or regression) is explicit.  
4. <a name="6.4"></a>The report SHALL include per-class β dispersion alongside each calibrated β — for mixture-fit classes this SHALL be the regression standard error, which surfaces collinear/unidentifiable classes as large dispersion.  
5. <a name="6.5"></a>The report SHALL state the MAPE < 20% target and whether each carb-priority staple meets it, as a reported result and not a pass/fail gate on the bake.  
6. <a name="6.6"></a>The report SHALL include protein and fat MAPE and MAE against N5k ground truth, for both the β=1.0 baseline and the β_c run, on the same mapped-classes-only basis as carbs ([6.2](#6.2)).  
7. <a name="6.7"></a>The run SHALL perform a cross-macro consistency check: WHEN a class's carbohydrate estimate agrees with N5k but its protein or fat diverges beyond a documented tolerance, the run SHALL flag the class as a likely mapping or composition-source error rather than silently baking it.  
8. <a name="6.8"></a>The report SHALL additionally state, on N5k's official depth test split (held out of calibration per [4.4](#4.4)), whole-dish carbohydrate MAE and MAE÷mean-actual — the basis and normalisation of the Nutrition5k paper's Table 3 RGB-D direct-regression baseline (carb MAE 23.8% of mean) — where unmapped ingredients contribute zero to the estimate but their full carbohydrate to the whole-dish ground truth, for both the β=1.0 baseline and the β_c run. The MAE÷mean-actual denominator SHALL be computed over the evaluated dishes, and the report SHALL state the evaluated-dish count against the split's total (enumerating dishes skipped per [3.4](#3.4)/[3.8](#3.8)), the mapped-carb coverage fraction of the evaluated split, and the caveat that the pipeline consumes ground-truth class identity via the ingredient mapping, so these figures are reported alongside — not claimed directly comparable with — the paper's baseline (which predicts from RGB-D with no ground-truth ingredient identity). The whole-dish figures conflate mapping coverage with calibration quality (a β=1.0 over-read can partially cancel unmapped ground-truth carbs), so the β_c-vs-baseline judgement lives in [6.3](#6.3). MAPE on the mapped-classes-only basis ([6.2](#6.2)) remains the internal figure of [6.1](#6.1)–[6.5](#6.5).  

### 7. Standalone-liquid classes and carb values

**User Story:** As a user, I want a carb estimate for a standalone drink, so that liquids are no longer silently excluded.

**Acceptance Criteria:**

1. <a name="7.1"></a>The palette and food database SHALL define a documented set of standalone-liquid classes, each with a carbohydrate value and density sourced from CoFID (UK), AFCD (Australia), or USDA (US), with the source recorded per row.  
2. <a name="7.2"></a>Adding liquid classes SHALL redefine the v1 palette in place — no version bump; the app has never shipped and nothing was trained against the prior layout (Decision 23) — and the database bake SHALL pass palette-lock against the redefined palette, where the lock SHALL check palette content (the ordered class list), not only the version label, and SHALL update the FoodSeg103 remap so the corresponding categories no longer collapse to `unsupported_liquid`. The final palette class list SHALL be locked before the FoodSeg103 training run begins — the trained checkpoint's output-channel count must match the shipped palette, and training on the pre-liquid layout would force a retrain (Decision 22; recorded as a model-production prerequisite).  
3. <a name="7.3"></a>The system SHALL provide a volume estimate for a liquid class by integrating the liquid surface depth to the support plane, covered by a unit test against a known synthetic surface, and SHALL produce a carbohydrate value from volume, density, and carb fraction. This estimate SHALL raise the over-estimate flag — the integration includes the vessel base and walls, a known upward bias (Decision 19).  
4. <a name="7.4"></a>GIVEN a recognised standard vessel with a canonical, DB-sourced serving volume, the system SHALL estimate carbohydrate as canonical volume × the class's carb density (a pure mapping unit-testable from a vessel-label + sub-class fixture input, independent of the recognition step). This path assumes the vessel is full to its canonical serving line, and SHALL raise an over-estimate flag so a fill-assumption estimate is not presented as measured.  
5. <a name="7.5"></a>WHERE a drink is visually sub-classifiable, the system SHALL apply the sub-class carb density on a best-effort basis and fall back to the generic liquid class when the sub-class is uncertain; the distinct densities SHALL come from the food database ([7.1](#7.1)), not from an assumed ordering between sub-classes.  
6. <a name="7.6"></a>The pipeline SHALL resolve a detected liquid by a single precedence rule: recognised standard vessel → canonical-volume estimate ([7.4](#7.4)); else recognised liquid class with usable surface depth → depth-integrated estimate ([7.3](#7.3)); else exclude the liquid and flag it (existing behaviour), never emitting an unbacked carb number.  
7. <a name="7.7"></a>The requirements SHALL record that (a) recognising the liquid class, vessel, and sub-class at inference depends on segmenter/classifier retraining owned by model-production, so [7.4](#7.4)/[7.5](#7.5)/[7.6](#7.6) recognition triggers are a deferred dependency — and FoodSeg103 carries no sub-class supervision (e.g. no lager vs stout labels), so the segmenter is trained on the coarse liquid class and sub-classification remains the runtime best-effort of [7.5](#7.5) — and (b) liquid carb output is unvalidated in this spec because N5k provides no standalone-liquid ground truth, overhead depth on transparent liquids is unreliable, and the vessel path assumes a full serving. The specific canonical serving volumes (which differ by region, e.g. UK vs US pint) and per-class carb densities SHALL be defined in the database with provenance, not hard-coded in behaviour.  

### 8. Suppress the uncalibrated banner for N5k-calibrated classes

**User Story:** As a user, I want the over-estimate warning to disappear for classes that are now calibrated, so that the warning reflects reality.

**Acceptance Criteria:**

1. <a name="8.1"></a>The ResultView SHALL derive a calibration-confidence banner with exactly one of three states, evaluated over the result's contributing solid-food classes only (liquid classes carry no β and SHALL NOT enter this evaluation): (a) **suppressed** — every class has `beta_status = "calibrated"` (which per [5.4](#5.4) requires individual identifiability, not merely a sample count) AND every class is device-verified (a per-class flag, default false, flipped only by the future device-spot-check spec); (b) **softened** ("population-calibrated — not yet verified on this device") — every class is calibrated but any is not device-verified; (c) **full uncalibrated banner** — any class remains pooled or unity (Decision 18). WHERE no solid-food class contributes to the result (a standalone-drink capture), no calibration banner is shown and the liquid over-estimate flag ([8.2](#8.2)) stands alone — this empty-set case is a stated rule, not the suppressed state reached by vacuous truth. For any result with at least one solid-food class, the suppressed state is unreachable within this spec (no class can be device-verified yet) and SHALL be verified by flag injection in tests.  
2. <a name="8.2"></a>Independently of the calibration banner, WHEN the result includes a liquid estimate from either path — fill-assumption standard serving ([7.4](#7.4)) or depth-integrated ([7.3](#7.3)), both of which over-read (Decision 19) — the ResultView SHALL display the liquid over-estimate flag additively alongside whatever calibration-banner state [8.1](#8.1) selected; the liquid flag SHALL NOT replace, upgrade, or suppress that state.  
3. <a name="8.3"></a>These conditions SHALL be the only modifications this spec makes to the model-production-owned banner; the banner's presentation otherwise stays owned by model-production.  

### 9. Spec alignment

**User Story:** As a maintainer, I want existing specs updated to reference N5k, so that the dataset overlap, the transfer assumptions, and the liquid-decision reversal are recorded where readers expect them.

**Acceptance Criteria:**

1. <a name="9.1"></a>The estimation/pipeline dataset-overlap section (§20.2) SHALL list Nutrition5k as an overlapping public dataset and note its use for β_c calibration.  
2. <a name="9.2"></a>The reversal of the v1 standalone-liquid out-of-scope decision SHALL be recorded in this feature's decision log and cross-referenced from the liquid requirement.  
3. <a name="9.3"></a>The spec SHALL document the population-transfer assumption that β fitted on N5k overhead RealSense captures is applied to device LiDAR captures — including the systematic volume-scale component introduced by nominal (unpublished per-capture) N5k intrinsics ([3.3](#3.3)) — and SHALL note this as a known risk to confirm with a later device spot-check.  
4. <a name="9.4"></a>model-production's stage ordering SHALL be updated to record the palette class-list lock ([7.2](#7.2), Decisions 22–23) as a prerequisite of its training stage, so the sequencing constraint is enforced where the training run is executed, not only asserted here.  

### 10. Protein and fat pipeline outputs

**User Story:** As a developer, I want the pipeline to emit protein and fat alongside carbohydrate, so that N5k's macro signal is used and downstream (later UI, fat-protein units) has the values available.

**Acceptance Criteria:**

1. <a name="10.1"></a>The pipeline SHALL produce per-meal protein and fat estimates from the same β-corrected per-class mass used for the carbohydrate estimate (mass × the class's database protein/fat fraction), so protein and fat benefit from N5k calibration with no separate fit.  
2. <a name="10.2"></a>Adding protein and fat SHALL extend the pipeline estimate result; carbohydrate remains the primary output, and protein/fat are additive rather than replacing it.  
3. <a name="10.3"></a>This spec SHALL NOT surface protein or fat in the UI; their presentation is deferred to a future `ui/`-domain spec recorded in the decision log (Decision 13).  

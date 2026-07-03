# Decision Log: nutrition5k-calibration

## Decision 1: Use Nutrition5k as a population gravimetric-calibration source

**Date**: 2026-07-01
**Status**: accepted

### Context

The MeData MVP ships every food class at β = 1.0 (`uncalibrated_unity`), carrying the systematic upward volume bias of visual-hull geometry. The pipeline spec requires ≥ 30 weighed meals per class before a class can be marked `calibrated` (estimation/pipeline §11.7). Hand-acquiring that gravimetric set is the project's primary human-gated blocker.

### Decision

Use the Google Nutrition5k (N5k) dataset — 5,006 plates with overhead RealSense RGB-D and per-ingredient mass labels — as a population ground-truth source to derive per-class β_c factors, run through the existing `HarnessCLI calibrate` loop.

### Rationale

N5k supplies gravimetric mass (the exact input `BetaCalibrator` needs) at a volume no manual campaign can match, and its overhead RGB-D matches MeData's `single_view_lidar` capture path. Population calibration anchors the estimate before any individual fine-tuning.

### Alternatives Considered

- **Hand-acquired gravimetric set**: The original plan — Rejected as the blocker we are trying to remove; slow, low-volume.
- **Keep β = 1.0 for MVP**: Status quo — Rejected because the upward bias is a clinical-safety concern for carb counting.

### Consequences

**Positive:**
- Unblocks β_c for staples without a physical capture campaign.
- Reuses the existing calibrate loop and DB bake path; little new estimation code.

**Negative:**
- N5k population β may not match an individual's plating; individual fine-tuning still deferred.

*Figures annotated 2026-07-02: only ~3.5k of the 5,006 dishes carry overhead RGB-D — see Decision 20.*

---

## Decision 2: This spec owns only N5k-specific work; cross-cutting infra is referenced

**Date**: 2026-07-01
**Status**: accepted

### Context

The initiating plan bundled several infrastructure items (YCbCr→BGRA conversion, bundling a trained `.mlpackage`, ANE residency, ResultView banner) that already have owners.

### Decision

This spec owns N5k ingestion, the fixture bridge, the β_c calibration run + DB bake, carb-accuracy reporting, and the liquid rework. The following are referenced as dependencies, not re-owned: YCbCr conversion (specs/rawframe-rgb-conversion), bundling a trained segmenter / `segmenterModelMissing` and ANE residency (specs/estimation/model-production Bucket C), and the uncalibrated banner (model-production task 10 — this spec adds only a suppression follow-on).

### Rationale

Double-owning code already covered by other specs makes this spec unable to close and risks divergent requirements. A trained checkpoint is still required regardless of N5k.

### Alternatives Considered

- **Absorb all infra into this spec**: One umbrella spec - Rejected; broad, double-owns code, never closes.

### Consequences

**Positive:** Bounded, closeable scope.
**Negative:** Real MVP carb numbers still gated on the referenced model-production Bucket C work.

---

## Decision 3: Drop N5k segmentation-training supplementation (no per-pixel masks)

**Date**: 2026-07-01
**Status**: accepted

### Context

The plan proposed supplementing FoodSeg103 with N5k overhead RGB to raise segmentation mIoU.

### Decision

Drop this thread. N5k provides RGB-D and per-ingredient mass but **no per-pixel semantic segmentation masks** (verified against the dataset documentation). Segmentation-mIoU work stays owned by model-production/FoodSeg103.

### Rationale

Dense per-pixel masks are required to train or evaluate semantic segmentation. N5k has none, so it cannot raise mIoU. Its value is gravimetric mass + depth, which feeds calibration and geometry validation only.

### Alternatives Considered

- **Pseudo-label N5k with a model, then train on it**: Generate masks via inference - Rejected; adds a noisy-label sub-project and depends on a trained model existing first.

### Consequences

**Positive:** Avoids a low-confidence sub-project.
**Negative:** N5k contributes nothing to segmentation accuracy; mIoU still depends on FoodSeg103.

**Future work (2026-07-01, per Ronan):** Pseudo-labelling is worth spinning out as its own side project, not discarded. Once a trained segmenter exists (post model-production Bucket C), run it over N5k's 5,006 overhead RGB images to generate masks, then self-train using those pseudo-masks plus N5k per-ingredient mass as added supervision (a semi-supervised / weak-supervision loop; N5k's real plated food could lift top-down mIoU where FoodSeg103 is thin, and mask+mass pairing enables joint volume+mass training). It is a *later* improvement loop, not a dependency of this spec, because: it needs the trained model first (circular for calibration); it needs confidence filtering / agreement checks / human spot-review to avoid confirmation bias; and N5k's fine-grained ingredients don't cleanly cover the 24-class palette. Candidate future spec of its own.

*Figures annotated 2026-07-02: the pseudo-labelling pool is the ~3.5k RGB-D dishes (plus ~20k video frames without depth), not 5,006 overhead images — see Decision 20.*

---

## Decision 4: Derive the per-class calibration silhouette from depth on single-dominant-class plates

**Date**: 2026-07-01
**Status**: accepted

### Context

`BetaCalibrator` needs per-class predicted volume, which requires a per-class mask over the plate. N5k supplies no masks (Decision 3).

**Status note:** Amended by Decision 11 — single-dominant plates are the mask-free baseline, not the only usable subset.

### Decision

For calibration, select N5k plates dominated by a single carb-priority staple, derive the food silhouette from the overhead depth (height-above-support-plane), label that silhouette with the single dominant class, and compare its hull volume against that ingredient's known mass.

### Rationale

Depth alone separates food from the table without a semantic mask. On a single-dominant-class plate the silhouette is unambiguously that one class, and N5k's per-ingredient mass gives m_c directly, yielding β_c = m_c / (V_c · ρ).

### Alternatives Considered

- **Run the MeData segmenter on N5k to get masks**: Circular — depends on the trained model (Bucket C) and N5k's classes may not map cleanly - Rejected for calibration.

### Consequences

**Positive:** Calibration works with no masks; clean per-class attribution.
**Negative:** Restricts the usable N5k subset to single-dominant plates; per-staple sample counts (≥ 30?) must be confirmed in design.

---

## Decision 5: Full per-type liquid carb estimation, sourced from UK/AU/US food databases

**Date**: 2026-07-01
**Status**: accepted

### Context

The plan reworks the v1 `unsupported_liquid` out-of-scope decision (estimation/pipeline §8.7), which currently zeroes liquid voxels and surfaces a "standalone liquids not estimated in v1" message. The user wants real carb numbers for liquids, sourced from food databases.

### Decision

Reverse §8.7 for a defined set of common standalone liquids. Add liquid food classes with carb and density values sourced from CoFID (UK), AFCD (Australia), and USDA (US). Estimate liquid volume from the depth surface integrated to the support plane, then carb = volume · density · carb-fraction. The segmenter retraining needed to distinguish the new liquid classes is referenced as a model-production/Bucket C dependency (FoodSeg103 already contains wine/coffee/juice/milk/tea/soup categories that currently collapse to `unsupported_liquid`).

### Rationale

CoFID and AFCD are already DB sources and carry carb content for common liquids; USDA covers gaps. Per-type carb output requires per-type classes, which requires the segmenter to distinguish them — that retraining rides on the existing Bucket C training run rather than being re-owned here.

### Alternatives Considered

- **Volume infra only, no liquid classes**: Estimate liquid volume but emit no carbs - Rejected; the user wants carb numbers.
- **Single generic liquid class with an averaged carb density**: No retraining - Rejected; juice/milk/water carb content differs too much for one value.
- **Defer liquids entirely**: Keep v1 out-of-scope - Rejected; the user explicitly wants the rework now.

### Consequences

**Positive:** Real carb numbers for common liquids; reuses existing DB sources.
**Negative:** Bumps the palette to v2 (re-bake DB, update FoodSeg103 remap and carb-priority lists) and depends on segmenter retraining. Overhead depth sees only the liquid surface, so surface-to-plane integration includes container walls — a geometry caveat to resolve in design.

---

## Decision 6: MAPE < 20% is a reported target, not a spec-completion gate

**Date**: 2026-07-01
**Status**: accepted

### Context

The plan introduces MAPE < 20% as a clinical-safety accuracy bar. A real on-device MAPE needs the trained model (Bucket C), which this spec does not own.

### Decision

Treat MAPE < 20% as a target measured and reported via `calibrate-and-eval` on a disjoint N5k eval split. Do not gate spec completion on it.

### Rationale

The offline N5k holdout MAPE is measurable now and is the right signal for whether the population β_c helps, but the authoritative carb-accuracy number is on-device and depends on Bucket C. Gating this spec on a number it cannot fully control would block closure.

### Alternatives Considered

- **Hard offline gate on N5k holdout**: Require MAPE < 20% on the eval split to pass - Rejected by the user in favour of report-only.

### Consequences

**Positive:** Spec can close on deliverables it controls; MAPE still measured and visible.
**Negative:** No automated pass/fail on carb accuracy within this spec.

---

## Decision 7: Fit β with the same volume estimator and masking the device uses

**Date**: 2026-07-01
**Status**: accepted

### Context

The review noted that β is fit so β·V ≈ m/ρ. If calibration V comes from a depth-threshold silhouette but inference V comes from the segmenter mask, β absorbs the calibration-masking bias, not the inference-masking bias, and does not transfer.

### Decision

Calibration volume SHALL be produced by the same `HeightFieldEstimator` and masking path the device pipeline uses at inference (Req 5.1).

### Rationale

β is only valid if the volume it corrects is computed the same way at fit time and inference time. This is the validity linchpin of the whole calibration.

### Consequences

**Positive:** β corrects the real inference-time bias.
**Negative:** Requires the N5k fixtures to carry segmentation probabilities from a checkpoint, tying calibration to the model-production checkpoint rather than depth alone.

---

## Decision 8: Report a paired β=1.0 baseline in the eval

**Date**: 2026-07-01
**Status**: accepted

### Context

A MAPE figure for the calibrated run in isolation cannot show whether calibration helped or hurt.

### Decision

The eval SHALL report MAPE/MAE for both the β=1.0 baseline and the β_c run on the same split, per staple and overall (Req 6.3), plus per-class β dispersion (Req 6.4).

### Rationale

The only question that matters is whether β_c beats β=1.0. Given carb counts drive insulin dosing, a calibrated value presented as trustworthy needs a measured improvement and a dispersion signal.

### Consequences

**Positive:** Improvement is explicit and auditable; clinical-safety dispersion visible.
**Negative:** Slightly more reporting work in the harness.

---

## Decision 9: Liquid scope = classes + DB values + volume geometry now; carb validation deferred

**Date**: 2026-07-01
**Status**: accepted

### Context

The user chose full per-type liquid carb estimation sourced from UK/AU/US databases. The review established that N5k has no standalone-liquid mass or volume ground truth, that overhead RealSense depth on transparent liquids is unreliable, and that routing a pixel to a liquid class needs the disowned segmenter retraining — so liquid carb output cannot be validated end-to-end in this spec.

### Decision

This spec delivers the liquid classes, their CoFID/AFCD/USDA carb+density values, the palette bump and remap, and a unit-tested surface-to-plane volume geometry (Req 7). End-to-end liquid carb validation is an explicit Non-Goal, deferred to a later spec once the segmenter distinguishes liquid classes.

### Rationale

Honours the user's intent (real DB-sourced liquid carbs) for the parts that are deliverable and testable now, while not claiming an accuracy that nothing in scope can verify.

### Alternatives Considered

- **Full validated liquid carb estimation now**: Rejected; no liquid ground truth exists in N5k and depth on clear liquids is unreliable.
- **Drop liquids**: Rejected; the user wants the rework.

### Consequences

**Positive:** Liquid classes and carb values land; geometry is unit-tested.
**Negative:** Liquid carb numbers are unvalidated until the model-production retraining and a future liquid-validation spec.

---

## Decision 10: Validate per-staple plate counts before baking; keep the calibrator's split intact

**Date**: 2026-07-01
**Status**: accepted

### Context

Single-dominant-staple plates are a scarce subset of N5k, and the 30-sample floor competes with a disjoint eval split, risking silent fallback to unity.

### Decision

The run SHALL report per-staple qualifying plate counts as a feasibility gate before baking (Req 4.4), treat "insufficient" as an accepted documented outcome, and use a split policy that does not strand a staple below 30 (Req 6.1). Selection and split SHALL be seeded (Req 4.3).

### Rationale

The feature's value depends on staples actually clearing the floor; that must be visible and reproducible, not discovered after a silent no-op bake.

### Consequences

**Positive:** Feasibility is explicit and reproducible.
**Negative:** Some staples may remain uncalibrated if N5k lacks enough clean plates — known and accepted.

*Cross-references annotated 2026-07-02: renumbering by the amendment round moved the feasibility gate to Req 4.5 and the seeded-split requirement to Req 4.4.*

---

## Decision 11: Maximise N5k usage via mixture decomposition, not just single-dominant plates

**Date**: 2026-07-01
**Status**: accepted (amends Decision 4)

### Context

Decision 4's single-dominant-plate approach is mask-free and clean, but single-item plates are a small fraction of N5k's 5,006, so most of the dataset — and its per-ingredient mass labels — would go unused. Ronan asked how to maximise the dataset's usefulness given the food items are not separated.

### Decision

Use multi-ingredient plates as well as single-dominant ones. A plate's total above-plane hull volume relates to its per-ingredient masses as V ≈ Σᵢ (mᵢ/ρᵢ)·(1/βᵢ), which is linear in 1/βᵢ. Stacking many plates with varying ingredient mixes into a system and solving (non-negative least squares) recovers βᵢ for every class from all fully-mapped plates. Single-dominant plates are the special case. The single-class path keeps the existing `BetaCalibrator`; the mixture path extends it (Req 4.1, 4.3, 5.2), preserving the 30-sample threshold, pooled/unity fallback, and clamps.

### Rationale

Item separation is impossible without masks (Decision 3), but the mixture fit does not need separation — only per-ingredient mass (N5k has it) and total hull volume (depth gives it). This turns almost the whole dataset into calibration signal and directly raises per-class sample counts, easing the feasibility risk in Decision 10.

### Alternatives Considered

- **Depth-based instance separation then per-item attribution**: Watershed/connected components on the height field - Rejected as the sole path; it can separate physical piles but cannot name them without the segmenter, so class identity is still unavailable.
- **Single-dominant only (Decision 4)**: Kept as the baseline - insufficient alone; wastes most of N5k.

### Consequences

**Positive:** Far more usable plates; higher per-class sample counts; better identifiability across classes.
**Negative:** Introduces a second calibration method beyond the existing `BetaCalibrator` (amends the "reuse only" stance). Relies on the additive-volume assumption (items side by side, not stacked or sauce-covered); overlapping/stacked plates violate it and must be excluded or down-weighted. Identifiability needs enough plate diversity per class.

**Refinements (2026-07-01, post-critic):** The mixture fit changes the meaning of "sample", so the safety chain (count → `calibrated` → banner suppression) is tightened: (1) `calibrated` gates on effective-sample count + individual identifiability (fit standard error), not raw plate count (Req 4.5, 5.4); (2) mixture β does NOT carry Req 5.1's same-masking guarantee that single-dominant β does — it gets distinct provenance and the masking-transfer gap is recorded (Req 5.1/5.4); (3) each plate feeds exactly one estimator, no double-counting (Req 5.2); (4) under-sampled/unidentifiable classes are subtracted as fixed offsets in the joint solve so their volume is not misattributed (Req 4.6); (5) the stacking/occlusion guard is a computable hull-vs-expected-volume check, not an uncomputable "detect sauce" (Req 4.3); (6) ρ error couples across co-occurring classes in the mixture fit, reflected in dispersion (Req 5.3/6.4).

**Refinements (2026-07-02, post-critic/validator):** Plates carrying a significant liquid-mapped ingredient (e.g. soup) are excluded from the mixture fit entirely (Req 4.7) — dropping only the liquid from the sum would leave the vessel-plus-liquid volume in the measured hull and misattribute it to co-occurring solids' β, and vessel geometry breaks the additive-volume assumption. Exclusions are counted in the Req 4.5 pool report.

**Refinement (2026-07-02, design amendment):** The solver is **bounded-variable least squares (BVLS, active-set)** rather than plain NNLS: the β bounds `[0.05, 1.5]` are enforced *inside* the solve because a post-hoc clamp would re-leak a clamped class's excess volume into co-occurring classes and break the joint attribution. Same algorithm family (non-negativity is the lower bound's special case), still implemented in Swift per Decision 14; a bound-resting class is marked `clamped` for the Req 5.6 warning.

---

## Decision 12: Standard-serving carb fallback for recognised liquid vessels

**Date**: 2026-07-01
**Status**: accepted

### Context

Overhead RealSense depth on a liquid surface is unreliable, and even where it works, surface-to-plane integration measures the container, not the liquid (Decision 5, review NEW-8). Ronan noted that a photo of a pint could just assume an average lager or stout by colour and give a close estimate.

### Decision

For liquids served in a recognised standard vessel (e.g. a pint at 568 mL, a can at 330/440 mL), estimate carbohydrate from the canonical serving volume × the class's carb density, bypassing depth-based volume entirely (Req 7.4). Where a drink is visually sub-classifiable (lager vs stout by colour), the classes carry distinct carb densities so the estimate reflects the sub-class (Req 7.5).

### Rationale

A standard serving has a known volume, so recognising the drink and its vessel gives a close carb estimate without the unreliable liquid-depth measurement. Colour cheaply separates high-carb lager from lower-carb stout. All volumes stay metric (mL).

### Alternatives Considered

- **Always measure liquid volume from depth**: Rejected as the sole method; unreliable on transparent liquids and biased by container geometry.

### Consequences

**Positive:** Robust, close carb estimates for common drinks without depth; sidesteps the container-volume problem.
**Negative:** Recognising the vessel and colour sub-class at inference is a model/classifier capability owned by model-production (Bucket C dependency), so this path is not exercisable until the model supports it. Assumes the standard vessel is full to its canonical serving line.

**Refinements (2026-07-01, post-critic):** (1) The full-fill assumption moves into the requirement text and the serving estimate raises an over-estimate flag — a partial pour must not be presented as measured, and this estimate does NOT clear the banner (Req 7.4, 8.2). (2) The carb value is a pure mapping (vessel label + sub-class → canonical volume × DB density), unit-testable independent of the deferred recognition step (Req 7.4). (3) Colour sub-classification is best-effort with fallback to the generic class; densities come from the DB with no assumed lager<stout ordering (the "stout is lower-carb" premise is false for sweet/milk stouts) (Req 7.5). (4) Canonical serving volumes are region-dependent (UK vs US pint) and live in the DB with provenance, not hard-coded (Req 7.7). (5) A single precedence rule orders the vessel / depth / exclude paths (Req 7.6).

---

## Decision 13: Use N5k protein and fat; emit as pipeline outputs; defer UI to a future ui/ spec

**Date**: 2026-07-01
**Status**: accepted

### Context

N5k provides per-ingredient protein and fat as well as carbohydrate and mass. The carb-only framing would discard that signal. Ronan directed that these macros are useful and should not be excluded, chose to emit them as pipeline outputs, and directed that UI display be excluded and recorded as a required future spec under the ui/ domain.

### Decision

Use N5k protein and fat three ways: (1) carry them as fixture ground truth (Req 3.5); (2) report protein/fat MAPE/MAE (β=1.0 vs β_c) and run a cross-macro consistency check that flags a class whose carb matches N5k but whose protein/fat diverges (Req 6.6, 6.7); (3) emit per-meal protein and fat from the β-corrected mass × the DB fraction as additive pipeline outputs, carbs remaining primary (Req 10). Surfacing protein/fat (and fat-protein units) in the UI is excluded and recorded here as a required future spec under the ui/ domain.

### Rationale

β corrects volume→mass, so the correction is macro-agnostic — protein and fat come free from the same corrected mass. They give an independent check on the calibration and the class mapping (a carb match with a fat mismatch signals a bad mapping or composition source), and they are clinically relevant to T1D (fat/protein delay and extend the glucose response — the basis of fat-protein units). Emitting them is cheap because mass is already computed; UI is a separate product concern owned by the ui/ domain.

### Alternatives Considered

- **Carbs only (exclude protein/fat)**: Original framing - Rejected; wastes N5k ground truth and the free calibration QA it provides.
- **Validation/QA only, no pipeline outputs**: Report but don't emit - Rejected by Ronan in favour of emitting outputs.
- **Full feature incl. UI display in this spec**: Rejected; UI is owned by the ui/ domain and would broaden this spec (per Decision 2 discipline). Deferred to a required future ui/ spec.

### Consequences

**Positive:** No N5k signal wasted; independent mapping/calibration check; protein/fat available for a later UI/fat-protein-units feature.
**Negative:** Extends the fixture schema (protein/fat ground-truth fields) and the pipeline estimate result type (a touch-point on estimation/pipeline); a follow-on ui/ spec is now owed to actually show the values.

### Impact

Fixture schema (protein/fat ground truth), calibration harness reporting, food-DB fractions (already present), the pipeline estimate result type, and a newly-owed future ui/ spec.

---

## Decision 14: Fit the mixture β in Swift (offline harness), not Python

**Date**: 2026-07-01
**Status**: accepted

### Context

The multi-ingredient β fit (Decision 11) needs a non-negative least-squares solve of `V ≈ Σ (mᵢ/ρᵢ)·(1/βᵢ)` plus per-class standard errors and conditioning diagnostics. numpy/scipy make this trivial; Swift has no built-in NNLS. The concern raised was whether a Swift solver would compromise future Android integration.

### Decision

Implement `MixtureBetaCalibrator` in Swift in `HarnessCore` (hand-rolled Lawson-Hanson NNLS + covariance/condition-number diagnostics), next to the existing `BetaCalibrator`.

### Rationale

`HarnessCore` is offline calibration tooling gated on `#if HARNESS_ENABLED`; it never ships on-device. The Android-integration concern is about *on-device inference*, which consumes only the baked DB values (β, β_status), not the fitting code. So the calibrator's language is invisible to any device runtime. Keeping the fit in Swift keeps the whole calibration in one language and test suite and reuses the Swift volume geometry directly (the total-hull-volume computation must be Swift anyway to match the estimator), which is the smaller-code path.

### Alternatives Considered

- **Python/scipy offline**: robust `scipy.optimize.nnls` + numpy - Rejected; adds a Swift→JSON→Python seam, splits calibration across two languages/test suites, for a solver that is ~100 lines of well-understood active-set code.

### Consequences

**Positive:** One calibration pipeline; reuses the Swift volume path; zero Android-integration impact (offline-only).
**Negative:** Must hand-roll and test NNLS + standard-error/condition diagnostics in Swift rather than calling a library.

---

## Decision 15: Establish the N5k support plane from the overhead depth; do not use side-angle views

**Date**: 2026-07-01
**Status**: accepted

### Context

Req 3.6 requires volume to integrate above the plate top, not the surrounding table. An initial framing treated this as an overhead-depth ambiguity needing a plate-thickness offset or a rim heuristic. Ronan corrected that N5k is not overhead-only — it also ships side-angle RGB video (4 rotating angles, no depth), and the overhead RealSense measures the plate surface directly.

### Decision

Fit the support plane at runtime from the overhead RealSense depth. No proto field and no plate-thickness offset. **Amended after review:** the existing `FixtureRunner.fitPlaneFromDepth` passes an all-ones mask, so its RANSAC finds the largest plane in the frame — which is the table, not the plate, if the plate doesn't fill the frame. The plane fit for N5k is therefore **restricted to the plate region** (a plate mask derived from the depth, bounded by the rim discontinuity), so it lands on the plate top. **Empirically confirmed 2026-07-03 (integration run):** the plate does not fill the frame in any of 60 randomly sampled real captures — every frame carries a clear table border ~40–60 mm deeper than the plate centre, with a median 53% of border pixels above the 0.4 m saturation cap (zeroed at ingestion, which hard-stops the flood fill). The plate-region restriction is therefore load-bearing, not precautionary. The N5k side-angle RGB videos are not consumed in this spec; they are recorded as an available resource for the deferred pseudo-label loop (Decision 3 future work) and a possible future two-view cross-check. Plates with a high plate-plane fit residual are skipped and recorded.

### Rationale

A downward depth camera images the plate-top surface directly, so RANSAC over the depth lands on the plate, not a table — the plate-thickness bias the offset was meant to correct does not arise. Reusing the existing plane fit avoids a new proto field and a fragile heuristic. Bringing the side-angle RGB in would push toward the two-view SfS path, which the requirements did not adopt (they commit to `single_view_lidar`), so it stays out of scope here.

### Alternatives Considered

- **Explicit support plane in the fixture proto**: ingestion fits and writes the plane - Rejected; unnecessary once the runtime depth fit lands on the plate, and it adds a proto field + FixtureRunner branch.
- **Accept the table plane + document plate-thickness bias**: Rejected; based on the incorrect overhead-ambiguity premise — the plate is directly measured, so no offset is warranted.
- **Use the side-angle RGB for two-view geometry**: Rejected for this spec; the requirements commit to the single-view LiDAR path, and the angled frames carry no depth.

### Consequences

**Positive:** No schema change; reuses tested plane-fit code; correct plate-top reference from direct measurement.
**Negative:** Relies on the overhead depth being clean around the plate; poor-fit plates are dropped, reducing usable sample count. Plate-plane fit residual on N5k must be validated during ingestion.

---

## Decision 16: Record β provenance as a dimension separate from β_status

**Date**: 2026-07-01
**Status**: accepted

### Context

Req 5.4 requires each baked β to record whether its provenance is N5k single-dominant, N5k mixture, or hand-measured gravimetric, and tightens the `calibrated` gate to require individual identifiability, not raw plate count. The existing `BetaCalibrationStatus` is a three-value enum (calibrated/pooled/unity) consumed by `GRDBFoodDatabase`, `PerClassMacros`, and the ResultView banner.

### Decision

Keep `BetaCalibrationStatus` unchanged and add an orthogonal `BetaProvenance` enum (`n5k_single_dominant`, `n5k_mixture`, `gravimetric`, `none`) plus a `beta_provenance` DB column. The `calibrated` status is set only when a class meets the effective-sample minimum AND is individually identifiable AND its fit SE is within bound.

### Rationale

Overloading the status enum with provenance values would break every existing consumer's exhaustive switch and conflate "how good is this β" with "where did it come from". A separate dimension lets the safety chain (identifiability → `calibrated` → banner suppression) stay on the existing enum while provenance is recorded for audit and dispersion reporting.

### Alternatives Considered

- **Extend `BetaCalibrationStatus` with provenance cases**: Rejected; breaks consumers and conflates two concepts.
- **Store provenance only in the lineage meta, not per row**: Rejected; Req 5.4 requires it per row for audit.

### Consequences

**Positive:** No break to existing status consumers; per-row auditability; clean split of quality vs origin.
**Negative:** One more DB column and result field to thread through the bake and reporting.

---

## Decision 17: Decouple the mixture path from the segmenter checkpoint

**Date**: 2026-07-01
**Status**: accepted (amends Req 3.7)

### Context

Req 3.7 requires every N5k fixture to carry the segmenter checkpoint SHA so `FixtureLoader`'s hash guard accepts it, which gates the whole bake on model-production Bucket C. But the mixture path's volume is a depth silhouette that needs no segmenter — so the bulk of N5k (multi-ingredient plates, most of the 5,006) would be blocked purely by a fixture-format artifact, not a real dependency.

### Decision

Gate per-path, not uniformly. Mixture fixtures carry a sentinel `segmenter_checkpoint_sha256 = "no_segmenter"` and `FixtureLoader` accepts them on a mixture-only load path; single-dominant fixtures still carry the real checkpoint SHA and the hash guard still applies to them. Mixture β can be fitted and baked before the checkpoint exists. Req 3.7 is amended to "every single-dominant fixture carries the checkpoint SHA."

### Rationale

The mixture math has no genuine checkpoint dependency; gating it only served fixture-format uniformity. Decoupling ships most of N5k's calibration value before Bucket C, easing the feasibility risk in Decision 10, while single-dominant β keeps its Req 5.1 masking guarantee (which does need the real checkpoint).

### Alternatives Considered

- **Keep uniform gating**: all fixtures carry the real SHA - Rejected by Ronan; blocks the bulk of the dataset's value behind an artifact, not a dependency.

### Consequences

**Positive:** Mixture β (most of N5k) bakeable pre-checkpoint; feature delivers value before Bucket C.
**Negative:** Two fixture variants + a mixture-only `FixtureLoader` path; a sentinel SHA is a special case to test. Mixture β still carries the recorded masking-transfer gap (Decision 11).

**Refinements (2026-07-02, post-critic/validator):** (1) The sentinel alone cannot select the load path — that would let any fixture bypass the hash guard by writing the magic string. Req 3.7 now requires an authoritative estimator-path field (`single_dominant` | `mixture`); the single-dominant path rejects missing/empty/sentinel SHAs, the mixture path rejects fixtures carrying segmentation probabilities, and a missing SHA is malformed (skip), never coerced to the sentinel. (2) Decoupling made the bake two-phase, so supersession is now explicit (Req 5.2): when the checkpoint lands, single-dominant-eligible classes are re-fit and single-dominant β supersedes a baked mixture β (higher-guarantee provenance wins), recorded in lineage. (3) *Design amendment (2026-07-02):* routing is two-stage — a mass-based `τ_route` stamps the path at ingestion, the volume-based `τ_purity` (Req 4.2) is applied by the harness, and a stamped single-dominant plate that fails it is **dropped, not re-routed** (the mixture path must reject probability-carrying fixtures); Req 5.2 is amended from "exactly one" to "at most one, never both" to make the drop case explicit. *Context figure ("most of the 5,006") superseded by Decision 20 — the ingestible pool is the ~3.5k RGB-D subset.*

---

## Decision 18: Softened banner tier for population-calibrated, device-unverified classes

**Date**: 2026-07-01
**Status**: accepted (amends Req 8.1)

### Context

Req 8.1 clears the over-estimate banner when every contributing class is `calibrated`. But β is fit on N5k overhead RealSense depth and applied to iPhone LiDAR, and the device spot-check that would confirm transfer is deferred (Req 9.3). A mixture-provenance β additionally lacks the masking-transfer guarantee. Clearing the insulin-relevant warning on a β never validated on-device is a clinical-safety concern.

### Decision

Introduce a third banner tier. A fully-`calibrated` result whose classes are not yet device-verified shows a softened "population-calibrated — not yet verified on this device" banner instead of no banner. A `deviceVerified` flag (default false, flipped by the future device-spot-check spec) gates full suppression. Req 8.1 is amended to require device-verification, not just `calibrated`, for full banner clearance.

### Rationale

Carb counts drive insulin dosing; a population β from a different depth sensor is a real but unverified improvement. A softened banner communicates "better than uncalibrated, not yet device-proven" honestly rather than presenting the number as fully trusted.

### Alternatives Considered

- **Follow Req 8.1 as written**: calibrated clears the banner regardless - Rejected by Ronan; suppresses the warning on an on-device-unvalidated β.

### Consequences

**Positive:** No over-trust of cross-sensor β; honest signal to the T1D user.
**Negative:** Adds a banner state and a `deviceVerified` lineage flag; until the deferred device spot-check lands, all N5k-calibrated classes show the softened banner (nothing fully clears it). Requires a Req 8.1 amendment.

**Refinements (2026-07-02, post-critic/validator):** (1) `deviceVerified` is **per-class** (stored alongside `beta_status`/`beta_provenance`, consistent with Decision 16's per-row audit stance), not a single bake-level flag — the future spot-check spec will realistically verify classes incrementally. (2) The banner is restructured as one three-state calibration-confidence signal (suppressed / softened / full) evaluated over solid-food classes only; liquids are outside the β-status domain and are handled solely by the separate additive liquid flag (see Decision 19 refinement). (3) The suppressed tier is unreachable within this spec (default-false flag, no in-scope flipper) — Req 8.1 marks it verifiable by flag injection so it doesn't sit as an untestable SHALL.

---

## Decision 19: Both liquid estimate paths raise the over-estimate flag

**Date**: 2026-07-01
**Status**: accepted (amends Req 8.2)

### Context

Req 8.2 forces the banner for the fill-assumption vessel path but says a bypass-depth serving estimate SHALL NOT clear the banner — leaving the depth-integrated path (Req 7.3) able to clear it. But integrating the liquid surface to the support plane includes the vessel base and walls (Decision 5 caveat), so the depth path also over-reads. The path with an unmodelled over-read would ship without a warning.

### Decision

Both liquid estimate paths — canonical-vessel fill-assumption (Req 7.4) and depth-integrated (Req 7.3) — raise the over-estimate flag and show the banner. Req 8.2 is amended so any liquid estimate that over-reads keeps the banner.

### Rationale

Both liquid paths produce a known upward-biased volume; treating them consistently avoids presenting the depth path as more trustworthy than it is. Consistent with the clinical-safety stance in Decision 18.

### Alternatives Considered

- **Follow Req 8.2 as written**: only the vessel path flags - Rejected by Ronan; the depth path's container-wall over-read is unmodelled and would ship unwarned.

### Consequences

**Positive:** Consistent, honest treatment of both over-reading liquid paths.
**Negative:** No liquid estimate can clear the banner in this spec; a future liquid-geometry spec that models the vessel could relax this. Requires a Req 8.2 amendment.

**Refinements (2026-07-02, post-critic/validator):** (1) The flag obligation is now stated in Req 7.3's own text, not only in Req 8.2's aside — the depth-path implementer reads 7.3. (2) The liquid over-estimate flag is a **separate, additive signal**: it renders alongside whatever calibration-banner state Req 8.1 selected and never replaces, upgrades, or suppresses it. This resolves the previously undefined composition when a fully calibrated solids result carries a drink.

---

## Decision 20: Correct the spec's Nutrition5k factual basis against primary sources

**Date**: 2026-07-02
**Status**: accepted (amends Introduction, Req 1.4, 3.1, 4.5; adds Req 1.5)

### Context

A dataset-verification pass (`docs/agent-notes/dataset-strategy.md`, checked against the N5k README and the CVPR 2021 paper) found the spec's stated dataset facts wrong or unpinned in four places: the intro claimed all 5,006 plates carry overhead RGB-D when only ~3.5k dishes do; the paper and README disagree on the dish count (5,066 vs 5,006); the raw depth encoding (16-bit integer, 10⁻⁴ m units) was not stated, leaving a silent 10× scale bug open in the mm conversion; and the licence (CC BY 4.0, attribution required) was recorded nowhere.

### Decision

Pin the spec to the verified facts: intro states both dish figures and the ~3.5k RGB-D coverage; Req 4.5 assesses per-class feasibility against the RGB-D subset; Req 3.1 states the source encoding and requires a known-distance conversion check; Req 1.4 records the ingested plate count; new Req 1.5 requires CC BY 4.0 attribution on the About/Legal screen and licence in lineage.

### Rationale

The ≥30-samples-per-class feasibility gate (Req 4.5) is meaningless if computed against a dish count 43% larger than the ingestible pool. The depth-unit constraint is the difference between a correct volume and one wrong by 10×, and the conversion check makes that failure loud. Attribution is a licence obligation, and the existing About/Legal pattern (CoFID/AFCD under OGL v3) already gives it a home.

### Alternatives Considered

- **Fix facts at design time only**: leave requirements as written, correct in design.md - Rejected; the wrong dish pool sits inside an acceptance criterion (4.5), so the requirement itself was untestable as written.
- **Treat attribution as out of scope (data never ships)**: only derived β values reach the device - Rejected; CC BY 4.0 attribution is cheap, unambiguous, and follows the established food-database attribution pattern.

### Consequences

**Positive:**
- Feasibility, depth conversion, and licence obligations are now testable against reality.
- The 10× depth-scale failure mode is caught by a required check, not code review.

**Negative:**
- Per-class calibration feasibility is tighter than the spec previously implied (~3.5k usable plates, not ~5k); more classes may stay on pooled/unity fallback.

**Refinements (2026-07-02, post-critic/validator):** (1) The known-distance conversion check originally anchored at ≈ 0.4 m — exactly the depth clamp, where a scale error can hide in saturated values; Req 3.1 now requires two references strictly below the cap with a documented tolerance band, aborting ingestion on failure. (2) The "release identifier" is defined operationally (SHA-256 manifest of fetched metadata + split files, plus download date) because the GCS bucket is unversioned. (3) Bucket + repo verification (2026-07-02) found N5k publishes **no camera intrinsics**; Req 3.3 is repointed from "N5k's published RealSense calibration" (which does not exist) to a documented pinned nominal camera model, with the systematic scale risk folded into Req 9.3. (4) Stale dish-pool figures in Decisions 1, 3, and 17 are annotated as superseded by this decision. (5) Attribution (Req 1.5) also indicates modification, as CC BY 4.0 requires for adapted material.

---

## Decision 21: Keep fixed-seed cross-validation; add an official-test-split report

**Date**: 2026-07-02
**Status**: accepted (amends Req 4.4; adds Req 6.8)

### Context

N5k ships official train/test splits in `dish_ids/splits/`, which the spec's own fixed-seed cross-validation (Req 4.4/6.1) ignored. Official splits make results directly comparable with the paper's published baselines (RGB-D direct-regression carb MAE 23.8% of mean), but adopting them outright risks dropping thin staples below the 30-sample calibration minimum that motivated cross-validation in the first place.

### Decision

Calibration keeps the fixed-seed cross-validation policy but excludes every dish in the official test split from calibration; the accuracy report additionally states carb MAPE/MAE on that official test split for both β=1.0 and β_c runs.

### Rationale

This keeps the sample-floor protection intact while making the headline numbers comparable with published baselines at the cost of one extra report row. Holding the official test split out of calibration is what makes that report honest — evaluating on dishes the fit saw would overstate the improvement.

### Alternatives Considered

- **Adopt official splits outright**: calibrate on official train, evaluate on official test - Rejected; risks under-sampling thin staples below the 30-sample floor with no cross-validation fallback.
- **Keep own fixed-seed CV only**: no official-split usage - Rejected; forfeits comparability with published N5k baselines for no gain.

### Consequences

**Positive:**
- Results are directly comparable with the CVPR paper's baselines.
- Sample-floor protection for thin staples is unchanged.

**Negative:**
- The calibration pool shrinks by the official test split's dishes, further tightening per-class feasibility (compounding Decision 20's coverage correction).

**Refinements (2026-07-02, post-critic/validator):** (1) "Official test split" is pinned to `dish_ids/splits/depth_test_ids.txt` (verified against the bucket: `depth_*` and `rgb_*` variants exist; the depth split is the RGB-D one — picking `rgb_test_ids.txt` would hold out mostly depth-less dishes and destroy the comparison this decision exists for). (2) The original consequence claim "sample-floor protection for thin staples is unchanged" was wrong: the CV mechanism is unchanged, but the fixed exclusion alone can push a staple under 30 — Req 6.1 now scopes its floor guarantee to the CV policy, and such a class stays on pooled/unity per Req 4.6. (3) "Directly comparable" overclaimed on three axes (mapped-only vs whole-dish ground truth, MAPE vs MAE÷mean, oracle class identity vs image-only). Req 6.8 now reports whole-dish MAE and MAE÷mean (the paper's Table 3 basis and normalisation), states the evaluated-dish count, carries the oracle-knowledge caveat, and says "reported alongside", not "directly comparable"; mapped-only MAPE stays the internal figure. (4) Req 4.5's feasibility denominator is reconciled to the doubly-shrunk pool (RGB-D minus test split minus ingestion skips), reported per estimator path; the ≥30 floor has **not** been re-verified against that pool — the Req 4.5 feasibility report is where that arithmetic lands.

---

## Decision 22: Palette v2 is a hard prerequisite for the FoodSeg103 training run

**Date**: 2026-07-02
**Status**: accepted (amends Req 7.2; adds a model-production prerequisite)

### Context

The liquid classes (Req 7.1–7.2) bump `ClassPalette.version` and change the segmenter's output-channel count. The FoodSeg103 GPU training run (model-production Stage 3) has not started — the dataset is not yet downloaded — but nothing recorded the ordering between the two specs. Training on palette v1 and then adopting v2 would force a full retrain; FoodSeg103 also carries no sub-class supervision (no lager/stout labels), so the trained classes must be the coarse liquid classes.

### Decision

Lock palette v2 before the FoodSeg103 training run begins, recorded as a hard prerequisite in both this spec and model-production's stage ordering. The segmenter trains on the coarse liquid classes; sub-classification stays the runtime best-effort of Req 7.5.

### Rationale

The sequencing costs nothing today (training has not started) and avoids a guaranteed retrain — the only scenario where the soft alternative wins is one where training starts before palette v2 can be defined, which is not the current state. Pinning the coarse-class training scope now prevents the palette from accreting sub-classes FoodSeg103 cannot supervise.

### Alternatives Considered

- **Soft note only**: record the retrain risk but let training start on v1 if ready first - Rejected; accepts a likely full retrain to hedge a sequencing constraint that currently costs nothing.
- **Separate model revision for liquids**: train v1 for MVP, plan a v2 retrain after - Rejected; liquid recognition is already a deferred dependency (Req 7.7), but deliberately planning a second GPU run wastes the one training slot the project has for no MVP gain.

### Consequences

**Positive:**
- No retrain; the one gated GPU run produces a checkpoint whose channel count matches the shipped palette.
- Training scope (coarse liquid classes) is pinned before dataset remap work starts.

**Negative:**
- model-production's Stage 3 gains a dependency on this spec's palette definition — the liquid class set must be finalised before training can start.

**Refinements (2026-07-02, post-critic/validator):** (1) "Locked" means a versioned, enumerated liquid-class artifact (the palette v2 class list at a pinned `ClassPalette.version`), so the prerequisite is verifiable rather than asserted — this spec now blocks model-production Stage 3, and churn in the class set is the cost. (2) The model-production side of the lock is enforced by a spec-alignment criterion (Req 9.4: model-production's stage ordering must record the prerequisite), not only by this log entry. (3) *Decision 23 (2026-07-02) removes the v2 label: the liquid classes land in a redefined palette v1, so the artifact locked before training is the enumerated final v1 class list. The sequencing constraint itself is unchanged.*

---

## Decision 23: Liquid classes land in a redefined palette v1 — no v2

**Date**: 2026-07-02
**Status**: accepted (amends Req 2.5, 7.2, 9.4; refines Decision 22 and all palette-v2 references)

### Context

Reqs 7.2/9.4, the design, and the prerequisites introduced "palette v2" — bump `ClassPalette.version` when the liquid classes land. Ronan's review feedback: the app has never worked or shipped, so incrementing versions is meaningless churn; use the new palette as v1, replacing the old, if that is viable for asap deployment. Viability was checked against the code: `ClassPalette.v1Standard` (24 solid classes + 3 sentinels) is consumed only by in-repo artifacts regenerated by build tooling (`generate.py`'s sqlite DBs, `build_class_mapping.py`'s remap); no trained checkpoint exists (model-production Bucket C has not run), and no DB or app has shipped. Nothing external is keyed to the 24-class layout.

### Decision

Redefine v1 in place: append the coarse liquid classes to `v1Standard`, keep `version: "v1"`, and regenerate every palette-locked artifact in the same change. Because the label no longer changes when the palette does, the bake's palette lock gains a content check — the ordered class list parsed from `ClassPalette.swift` must match FOOD_DATA — and the N5k mapping artifact ties to palette content, not the label (Req 2.5).

### Rationale

Version identity exists to protect shipped or trained consumers from silent divergence. With zero such consumers, a v2 label is pure churn: two palettes to reason about and a migration that migrates nothing. The content check closes the one real hole the redefinition opens — a stale pre-liquid artifact passing a label-only lock.

### Alternatives Considered

- **Bump to v2 as specced**: version the palette change - Rejected by Ronan; version increments don't make sense before the app has ever worked.
- **Content-hash the version string** (e.g. `v1-<hash>`): make the label track content automatically - Rejected; the list-equality check in the bake gives the same protection without changing the version's meaning or touching every version consumer.

### Consequences

**Positive:**
- One palette to reason about; no stale-v2 migration surface.
- The lock is strengthened from label to content, which also covers future in-place palette edits.

**Negative:**
- "v1" means something different before and after this spec — history readers must use the class list, not the label.
- Every palette-locked artifact must be regenerated in the same change (enforced by the content lock, but still a discipline).

---

## Decision 24: Coarse liquid palette channels; beer sub-classes live in the DB

**Date**: 2026-07-02
**Status**: accepted (operationalizes Decision 22; refines the Decision 5 class list)

### Context

The earlier liquid class-list answer named `beer_lager`/`beer_stout` among the liquid classes. Decision 22 pins the trained classes to coarse liquid classes because FoodSeg103 carries no sub-class supervision — and palette channels are exactly the segmenter's output channels, so lager/stout channels would be untrainable dead channels that inflate the checkpoint and contradict Decision 22's rationale.

### Decision

The palette gains 8 coarse liquid channels (`water`, `coffee`, `tea`, `milk`, `fruit_juice`, `soup`, `beer`, `wine`). `beer_lager`/`beer_stout` become rows in a new `liquid_subclasses` DB table; `LiquidResolver` applies the sub-class carb density best-effort (Req 7.5) and falls back to the coarse `beer` row when the sub-class is uncertain.

### Rationale

Keeps Decision 22's training scope (palette = trainable classes, exactly), satisfies Req 7.5's requirement that distinct densities come from the food database, and preserves the chosen sub-class values — at the DB level rather than as segmentation channels.

### Alternatives Considered

- **Sub-classes as palette channels**: as originally listed - Rejected; untrainable dead channels violate Decision 22 and cost checkpoint width for nothing.
- **Drop sub-classes entirely**: coarse classes only - Rejected; Req 7.5 requires distinct DB densities where a drink is visually sub-classifiable.

### Consequences

**Positive:**
- Palette channels correspond one-to-one with trainable classes; sub-classes extend in the DB without palette churn.

**Negative:**
- `LiquidResolver` does a two-level lookup (sub-class row, else coarse row); the sub-class recognition source remains a deferred model-production dependency (Req 7.7).

---

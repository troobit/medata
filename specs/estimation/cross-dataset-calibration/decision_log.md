# Decision Log: cross-dataset-calibration

## Decision 1: Full spec workflow

**Date**: 2026-07-04
**Status**: accepted

### Context

Broadening β calibration beyond Nutrition5k touches per-dataset ingestion, cross-dataset merge/provenance, the food-DB bake, and lineage, with a cross-cutting capture-skew concern. The sizing question was smolspec vs full spec.

### Decision

Use the full spec workflow (requirements → design → tasks).

### Rationale

Multiple subsystems, cross-cutting skew handling, and genuinely open requirements (which datasets, how to reconcile β across them) all exceed the smolspec bar (<80 LOC, 1–3 files, no cross-cutting concerns).

### Consequences

**Positive:** Requirements and design gates force the skew and reproducibility questions to be settled before code.
**Negative:** More process for a feature whose realistic data yield is modest (see Decision 4).

---

## Decision 2: MetaFood3D as the one materially useful new dataset

**Date**: 2026-07-04
**Status**: accepted

### Context

A web-researched landscape (2026-07-04) scored public food datasets against what β needs: ground-truth gramme mass + a usable volume signal (depth/multi-view/3D/fiducial) + ~30 samples/class. Most candidates fail at least one requirement.

### Decision

Adopt MetaFood3D (arXiv 2409.01966) as the primary new calibration source.

### Rationale

MetaFood3D is the only non-baseline public dataset carrying real single-food 3D volume + per-object mass with meaningful overlap of our carb staples (rice, pasta, bread, potato). Nutrition5k is already our baseline; NutritionVerse-Real has mass but no volume signal; NutritionVerse-3D (105 models) is too small; FPB/SimpleFood45 are tiny or regional; segmentation-only sets (FoodSeg103, UECFOOD, UNIMIB, Food-101, Recipe1M) carry no mass and cannot calibrate β at all.

### Alternatives Considered

- **Nutrition5k only**: Already used; adds nothing new — Rejected, it is the baseline this feature improves on.
- **NutritionVerse-3D / SimpleFood45 / FPB**: Too small per class, or no clean volume signal — Rejected as primary sources.

### Consequences

**Positive:** Provides the single-food volume↔mass samples Nutrition5k's mixed plates cannot.
**Negative:** Even MetaFood3D leaves some staples below the 30-sample bar (Decision 4).

---

## Decision 3: MetaFood3D only for v1; ECUSTFD deferred

**Date**: 2026-07-04
**Status**: accepted

### Context

ECUSTFD carries real 2-view + coin-scale volume + mass but covers only apple/banana/egg/tomato — none of the carb staples this feature targets.

### Decision

Scope this spec to MetaFood3D ingestion only; defer ECUSTFD to a possible fast-follow.

### Rationale

ECUSTFD adds no carb-staple coverage, which is the priority. Keeping v1 to one dataset keeps the ingestion abstraction clean; ECUSTFD can follow once the multi-dataset abstraction is proven.

### Consequences

**Positive:** Tighter scope, one ingestion path to get right first.
**Negative:** apple/banana/egg/tomato gain nothing this increment.

---

## Decision 4: Fit β from our volume estimator, not MetaFood3D's mesh ground truth

**Date**: 2026-07-04
**Status**: accepted

### Context

MetaFood3D ships both real mesh volume (ground truth) and imagery. β corrects the bias of *our* volume estimator relative to true mass. Asked which volume to fit against, the user did not pick an option but noted: "provided this maximises use of public data."

### Decision

Fit β from the volume our own estimator produces on MetaFood3D, applied to an overhead depth view rendered from each object's mesh. Do not use the mesh ground-truth volume as the estimator input.

### Rationale

β must correct the bias the device actually has; the device never sees a perfect mesh, so using mesh volume as the estimator input would produce a β that does not transfer to real captures. Rendering the estimator input from the mesh also maximises usable data (the user's steering): every object with a valid mesh yields one usable single-food sample, rather than dropping objects that lack a clean native overhead frame.

### Alternatives Considered

- **Mesh ground-truth volume as estimator input**: simpler ingestion, but measures density/composition error only, not our volume bias; β would not transfer to device — Rejected as methodologically invalid.

### Consequences

**Positive:** β transfers the *geometric* component of the estimator's bias to on-device estimates; maximal object yield.
**Negative:** Ingestion must render a consistent overhead depth view per object — more work than reading a mass column. Rendered depth is noise-free while real captures are not, so β does not correct sensor-noise-induced bias (see Decision 8). As one multiplicative scalar fit against mass, β also absorbs mesh-scale error (Req 1.5), density mismatch (Decision 7), and render-pose error (Req 2.4) indiscriminately — the reason those are pinned by hard checks.

---

## Decision 5: Pool cross-dataset samples with provenance and a skew guard

**Date**: 2026-07-04
**Status**: accepted

### Context

When a class has qualifying samples from both Nutrition5k and MetaFood3D, the baked β can be produced three ways: pool samples, fit per-dataset and pick the most confident, or prefer the baseline and only accept the other source when it agrees.

### Decision

Pool per-class samples across datasets into a single fit, record contributing datasets and per-source counts in provenance, and add a capture-skew guard: compute per-dataset β, and when they disagree beyond an uncertainty-aware bound flag the class inconsistent and fall back to pooled/unity rather than bake the blended value.

### Rationale

Pooling maximises effective sample count, the binding constraint against the 30-sample bar. Provenance keeps the bake auditable. The skew guard addresses the one real risk of pooling — different capture rigs/sensors introducing systematic volume bias that a naive pooled fit would absorb.

### Alternatives Considered

- **Fit per-dataset, pick highest-confidence**: avoids skew but requires each dataset to clear the sample bar alone, so fewer classes calibrate — Rejected; defeats the coverage aim.
- **Prefer Nutrition5k, flag disagreement**: most conservative, but discards MetaFood3D's samples whenever it could most help — Rejected; too conservative.

### Consequences

**Positive:** Best chance of clearing the sample bar; skew is caught rather than silently baked.
**Negative:** Requires a defensible skew test and per-dataset fits in addition to the pooled fit; the guard is inert for single-source classes (Decision 9).

---

## Decision 6: MetaFood3D calibration is not gated on the segmenter checkpoint

**Date**: 2026-07-04
**Status**: accepted

### Context

Nutrition5k's single-dominant β path was gated on the trained checkpoint (model-production Bucket C) because a segmenter is needed to confirm a mixed plate is dominated by one class and to attribute mass. The passed-in context assumed this gating carried over.

### Decision

Treat each MetaFood3D object as a single-class observation requiring no segmenter, so MetaFood3D calibration runs pre-checkpoint.

### Rationale

MetaFood3D objects are single-food by construction, so mass attribution is trivial (100% the mapped class) and no segmentation is needed. This is precisely why MetaFood3D helps where Nutrition5k could not: it sidesteps both mixed-plate collinearity and the checkpoint gate, letting carb staples calibrate now.

### Consequences

**Positive:** Calibration coverage improves before the model exists — decouples this work from the human/GPU-gated training run.
**Negative:** The MetaFood3D and Nutrition5k volume paths must be shown to agree closely enough that pooling them is sound (handled by the Decision 5 skew guard).

---

## Decision 7: Bake a mass-fit β; keep a volume-fit β as a diagnostic

**Date**: 2026-07-04
**Status**: accepted

### Context

The regression target was unstated. β can be fit against per-object **mass** (as Nutrition5k does, since its mixed plates yield mass but no per-object volume) or against MetaFood3D's true **mesh volume**. A design-critic + peer-review pass showed the two estimate different quantities: mass-fit β = E[mass/(V_est·ρ)] conflates geometry with density mismatch; volume-fit β = E[V_true/V_est] is pure geometry. Samples estimating different quantities cannot be pooled, and Nutrition5k can only do mass-fit.

### Decision

Bake a **mass-fit** β for MetaFood3D against per-object mass using the DB density ρ_DB (Req 2.2), so it is poolable with Nutrition5k and self-consistent at inference. Additionally compute a **volume-fit** β from MetaFood3D's mesh volume as a non-baked diagnostic (Req 2.3) to isolate geometric bias.

### Rationale

Poolability with Nutrition5k requires a common estimand, and Nutrition5k's mass-only data forces mass-fit. Using ρ_DB at both fit and inference keeps `V·β·ρ_DB` self-consistent, so density mismatch does not corrupt the DB. The volume-fit diagnostic recovers the pure-geometry signal that the mass-fit conflates, giving a cross-check the baked value cannot provide.

### Alternatives Considered

- **Volume target only**: clean geometric β, but Nutrition5k cannot produce it and it is not poolable — Rejected; abandons the pooling mechanism.

### Consequences

**Positive:** Poolable, self-consistent bake plus a geometry-isolating diagnostic.
**Negative:** Baked β is not purely geometric — it carries the density draw of MetaFood3D's sampled foods relative to ρ_DB.

---

## Decision 8: β corrects geometric bias only; device-noise modelling deferred

**Date**: 2026-07-04
**Status**: accepted

### Context

The β render is noise-free, but real Nutrition5k (RealSense) and device (iPhone LiDAR) depth carry noise, edge rectification, off-axis convexity, and dropout that produce systematic, food-shape-dependent volume biases. β fit on clean renders captures the geometric bias but not these sensor-induced ones. Options: inject a device-matched LiDAR noise/dropout model into the render, or accept geometry-only β and document it.

### Decision

Accept that β corrects **geometric bias only**; record the noise-free-render limitation in lineage (Req 2.5) and rely on the held-out accuracy anchor (Req 10.2) to catch gross errors. Simulating device-LiDAR noise is deferred (Non-Goal).

### Rationale

A credible LiDAR noise model realistically needs real device captures of known objects — which edges toward the human-capture path this whole effort avoids. Given the project's honesty-over-coverage posture, documenting the limitation plus an out-of-sample anchor is the proportionate choice; noise modelling can be a later refinement if the anchor shows it matters.

### Consequences

**Positive:** Simple, honest, no dependence on unavailable device-capture data.
**Negative:** Residual sensor-induced bias is uncorrected; β may under- or over-correct on real captures relative to the render fit.

---

## Decision 9: Bake single-source β on statistical gates, not an accuracy gate

**Date**: 2026-07-04
**Status**: accepted

### Context

The carb staples this feature targets are calibrated from MetaFood3D **alone** (Nutrition5k cannot calibrate them pre-checkpoint), so the cross-dataset skew guard (Decision 5) cannot fire on them — they are single-source and unguarded. The choice was whether to hard-gate their bake on the held-out accuracy anchor (fail → keep unity) or bake on the statistical gates with a provenance flag. The trade-off was explained at introductory level: fewer-but-accuracy-checked vs more-but-some-unvalidated.

### Decision

Bake a single-source β when it clears the weighted effective-sample and relative-SE gates, carry the `single_source_uncorroborated` flag (Req 6.2, 8.3), and do NOT block the bake on the held-out accuracy anchor. The anchor is still computed and reported (Req 10.2).

### Rationale

User decision after an explicit walk-through of the risk: maximise the number of staples that receive a correction, accepting that some baked β are not out-of-sample validated. Provenance flags and the reported anchor keep the risk visible and auditable.

### Alternatives Considered

- **Accuracy-gated bake**: only bake if the held-out anchor passes, else unity — Rejected by the user in favour of broader coverage.
- **Gate with pooled/plausibility fallback on failure**: middle path — Not chosen.

### Consequences

**Positive:** More staples receive a β; the feature delivers visible coverage.
**Negative:** The highest-value β can ship without out-of-sample accuracy validation; a confidently-wrong β could shift a carb estimate the wrong way. Mitigated by the provenance flag and reported anchor, not prevented.

---

## Decision 10: Review-driven requirement hardening

**Date**: 2026-07-04
**Status**: accepted

### Context

A design-critic and peer-review-validator pass on the first requirements draft found that β behaves as a scalar "sponge" absorbing every multiplicative error in the MetaFood3D path, and that several ACs were untestable or mis-targeted.

### Decision

Harden the requirements: pin the render camera configuration and record it in lineage (Req 2.4, 9.1); retarget the ingestion unit check to a hard mesh-scale abort (Req 1.5); make the pooled effective-sample count information-weighted rather than a raw sum (Req 4.2); replace the fixed-0.25 skew tolerance with an uncertainty-aware equivalence check (Req 5.2); add a held-out MetaFood3D accuracy anchor and broccoli cross-check (Req 10.2); and exclude ambiguous cooking-method categories from split classes (Req 1.3).

### Rationale

Each change closes a path by which a dataset artefact (scale, pose, density, sampling noise) would be silently absorbed into β and mis-transfer to the device. Stating the render config and mesh-scale check as hard, recorded constraints is what makes β reproducible and auditable at all.

### Consequences

**Positive:** β becomes reproducible from lineage; artefact-driven mis-calibration is caught by hard checks rather than absorbed.
**Negative:** More ingestion and reporting machinery; the exact statistics (weighting formula, equivalence bound) are pushed to the design phase.

---

## Decision 11: MetaFood3D routes as single-class mixture rows; no separate pooling layer

**Date**: 2026-07-04
**Status**: accepted

### Context

The harness routes fixtures by `estimator_path` ∈ {mixture, single_dominant, legacy}. MetaFood3D objects are single-food. The design could add a new estimator path and a bespoke cross-dataset pooling/weighting layer (as the requirements anticipated), or reuse an existing path.

### Decision

Stamp MetaFood3D fixtures `estimator_path="mixture"` with the `no_segmenter` sentinel and no probability tensor, so each object is a degenerate single-class mixture row that joins the N5k rows in one shared `MixtureBetaCalibrator` BVLS solve. No new router path and no separate pooling/weighting layer.

### Rationale

A single-food object *is* a one-class mixture; the mixture path already needs only depth + per-class ground-truth mass, with no segmenter and no checkpoint (satisfying Req 3 directly). "Pooling" then reduces to adding rows to the shared design matrix — a single-non-zero row breaks the collinearity that made N5k staples unidentifiable and carries full information. The least-squares standard error already down-weights collinear rows, so the information-weighting of Req 4.2 falls out of the existing conditioning rather than a bespoke Kish/inverse-variance layer.

### Alternatives Considered

- **New `estimator_path` + explicit pooling/weighting layer**: matches the requirements' literal framing but changes the router and re-implements weighting the BVLS already does — Rejected as redundant.

### Consequences

**Positive:** Zero changes to the router, loader, calibrator, or volume path; the smallest surface that delivers the feature.
**Negative:** Relies on `MixtureBetaCalibrator`'s effective-sample crediting single-non-zero rows at full weight — verified by a unit test, not new code. Per-dataset β for the skew guard needs two extra single-dataset solves.

---

## Decision 12: CPU ray-cast render (trimesh), not GPU offscreen

**Date**: 2026-07-04
**Status**: accepted

### Context

The render turns each MetaFood3D mesh into an overhead depth map for the volume estimator. Options: CPU perspective ray-casting (trimesh) or GPU offscreen rasterisation (pyrender/Open3D via EGL/OSMesa).

### Decision

Render on CPU with trimesh — one perspective ray per pixel at the pinned intrinsics, first-hit distance → depth.

### Rationale

Determinism and offline operation are hard invariants, and β must be reproducible from lineage. CPU ray-casting is bit-deterministic and needs no GL context, GPU, or headless-driver setup. Roughly 700 one-off renders make per-render speed irrelevant, so the GPU's only advantage does not apply.

### Alternatives Considered

- **GPU offscreen (pyrender/Open3D)**: faster per render, but adds a GL-context dependency and risks cross-machine/driver non-determinism that would break reproducibility — Rejected.

### Consequences

**Positive:** Deterministic, headless-clean, minimal build footprint (trimesh, optional embree).
**Negative:** Slower per render (immaterial at this volume).

---

## Decision 13: Inject the authored support plane for MetaFood3D; do not RANSAC-refit it

**Date**: 2026-07-04
**Status**: accepted

### Context

The volume path fits the support plane with `fitPlateRegionPlane` — a centre-seeded flood fill on 4-neighbour depth continuity (|Δz|<5 mm) then RANSAC. For a nadir render of a steep-sided food (tall rice, stacked sandwich) the >5 mm edge cliff stops the fill reaching the synthetic plane, so RANSAC fits the food surface instead — a silent, shape-dependent volume error. For MetaFood3D the plane is authored exactly at render time.

### Decision

The MetaFood3D calibrate branch injects the authored `SupportPlane` (known normal + distance) directly into `TotalHullVolume`, bypassing the RANSAC refit. N5k keeps its existing refit path.

### Rationale

Re-discovering a plane we authored, via a fit that fails on steep foods, adds risk for no benefit. Injecting it is exact and removes the failure mode.

### Alternatives Considered

- **Reuse `fitPlateRegionPlane` for MetaFood3D**: no new branch, but silently wrong on steep foods and pointless when the plane is known — Rejected.
- **Seed the flood fill off-food**: brittle (depends on food position/size) — Rejected.

### Consequences

**Positive:** Exact plane, no steep-food failure, no new plane algorithm.
**Negative:** Per-dataset plane-fit asymmetry (N5k RANSAC vs MetaFood3D exact). Consistent with the noise-free-render stance (Decision 8) — MetaFood3D β is already a clean geometric fit — and any resulting disagreement is surfaced by the skew guard (Decision 5) and the volume-fit diagnostic (Decision 7).

---

## Decision 14: Metric-scale check via unit-sanity + weight-plausibility, not a dimension reference

**Date**: 2026-07-04
**Status**: accepted

### Context

Req 1.5 called for a hard mesh-scale abort against a "known-dimension reference." Verification found MetaFood3D ships **no per-object linear dimension** — only a gramme weight (plus nutrition). Its meshes are natively metric (fiducial-calibrated), so the real residual risk is a one-off unit/import error, not per-object drift.

### Decision

Replace the dimension check with two hard gates: (a) a global unit-sanity gate on the snapshot's bounding-box size distribution (catches a mm/m import or loader-scale error once); (b) a per-object plausibility that mesh bbox volume under a density band brackets the shipped gramme weight.

### Rationale

The check must use ground truth the dataset actually provides. Gramme weight is the only per-object physical reference, and a global unit gate catches the dominant real failure (a scale error absorbed into β) without a dimension field that does not exist.

### Consequences

**Positive:** Implementable against the real data; still a hard abort on the failure that would silently corrupt β.
**Negative:** Weaker than a direct dimension check per object; a scale error that happens to keep bbox-volume×density inside the weight band would pass.

---
</content>

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

## Decision 15: MetaFood3D mapping targets the palette v2 content list; v1 references superseded

**Date**: 2026-08-09
**Status**: accepted

### Context

This spec was planned 2026-07-04 against `ClassPalette.v1Standard` (35 channels), and its requirements and tasks state that target explicitly (Req 1.3 "35-channel palette v1", Non-Goals "the 35-channel palette and its ordering are fixed", tasks 1–2 "target ClassPalette.v1Standard ordering (load-bearing)"). On 2026-07-25 the myfoodrepo-bridge work shipped palette **v2**: `cereal` appended after the existing 24 solids (index 24), liquids shifted to 25–32, sentinels to 33/34/35, 36 channels; the bundled model is the 36-channel `ab812dc3aa9d`, and `tools/food_db/generate.py` now locks the DB bake against `v2Standard` (`PALETTE_VERSION = "v2"`, `_PALETTE_MARKER = "v2Standard"`). This spec's documents predate v2 and never mention it, so the target had to be re-verified before any mapping code was written.

### Decision

Target the **palette v2 content list** (`ClassPalette.v2Standard`: 25 solid + 8 liquid class names, sentinels excluded) for `mapping_metafood3d_to_palette.json` and all stream-1 tooling. The v1 references in requirements.md (Non-Goals, Req 1.3) and tasks.md (tasks 1–2) are marked superseded in place by this decision.

### Rationale

Evidence gathered 2026-08-09 shows β is keyed by **class name**, not channel index, end-to-end, so the "load-bearing ordering" concern does not bind the MetaFood3D data path — but the palette *content* lock must reference the palette that actually ships:

- The fixture contract carries GT masses as `map<string, float>` (`ground_truth_class_mass_g`, MealFixture.proto field 17); mixture fixtures — the shape MetaFood3D uses (Decision 11) — carry **no probability tensor**, which is the only place channel ordering is load-bearing.
- `MixtureBetaCalibrator` consumes `massByClassG: [String: …]` and `densityByClass: [String: Float]`; `CalibrationArtifact.classes` is name-keyed; `generate.py::_apply_calibration` bakes via `UPDATE foods SET beta … WHERE class_id = ?` with class-name strings. No index survives into the bake.
- `generate.py` locks the DB against `v2Standard` content; a calibrate artifact naming a class absent from the v2 DB fails its unknown-class check. A v1-locked mapping artifact could never map `cereal`, and its fail-loud content lock would validate against a superseded palette while the shipped model and DB moved on — exactly the drift the lock exists to catch.
- v2 is a pure append (all v1 names retained, first 8 carb-staple solids index-stable), so pooling with Nutrition5k fixtures (whose committed mapping artifact still carries the 32-name v1 content list) is unaffected: pooled rows join on class names, which are identical across v1/v2. The N5k artifact's own lock is per-tool and out of scope here.

### Alternatives Considered

- **Target v1Standard as planned**: literal spec compliance — Rejected: locks new tooling to a superseded palette, forecloses mapping MetaFood3D cereal-type categories into the live `cereal` class, and makes the artifact's palette-content lock validate against a declaration retained only for persisted-meal migration.
- **Key the mapping by v2 channel indices**: makes ordering explicit — Rejected: nothing in the mixture calibrate path consumes indices; index keying adds a brittle coupling the name-keyed fixture/artifact/DB contract deliberately avoids.
- **Support both palettes behind a flag**: maximal flexibility — Rejected: there is exactly one live bake target (v2); a dual-target mapping doubles the lock surface for no consumer.

### Consequences

**Positive:**
- The mapping artifact's fail-loud content lock guards the palette that actually ships (36-channel model, v2-locked DB bake).
- MetaFood3D cereal-type categories can be mapped rather than force-excluded.
- No migration machinery: name keying means zero changes to fixtures, calibrator, merge, or bake for this retarget.

**Negative:**
- The spec's Req 1.3 / Non-Goals / task text needed superseding annotations, and stream-2 readers must not take the "v1" task wording literally.
- The metafood3d and nutrition5k mapping artifacts temporarily reference different palette content lists (33 vs 32 names) until the N5k artifact is regenerated — acceptable because each lock is per-tool, but mildly confusing to auditors.

### Impact

Stream 1 only (`tools/metafood3d/`): `build_mapping.py` parses `v2Standard` (marker-scoped, mirroring `generate.py`), the artifact records the v2 content list, and tests assert mapped categories target valid v2 class names. No Swift change; stream 2's palette use in the mixture path is limited to `palette.liquidClasses` names, identical in v1/v2.

---

## Decision 16: MetaFood3D-only mixture β stamps the food-support reference

**Date**: 2026-08-09
**Status**: accepted

### Context

The calibrate artifact stamps each class's `support_plane_reference`, and `generate.py` applies a β only when that stamp matches the runtime's `foodSupport` basis (support-plane-reference Req 5.4). `CalibrationArtifact.reference(for:)` stamped every mixture-provenance β `plateRegion` — correct for Nutrition5k mixture rows, whose volumes come from the flood-filled plate-region fit (Decision 17 of that spec). MetaFood3D rows enter the same mixture solve (Decision 11), so the task 23 end-to-end test surfaced that a MetaFood3D-only carb staple clearing the effective-sample and relative-SE gates was reference-skipped at bake — no MetaFood3D β could ever reach the shipped DB, contradicting Req 8.3 ("SHALL be baked ... including MetaFood3D-only carb staples").

### Decision

`CalibrationArtifact.reference(for:singleDominant:contributingDatasets:)` stamps a mixture-provenance β `foodSupport` when its recorded contributing datasets are non-empty and exclusively `metafood3d`; any Nutrition5k contribution, or an empty contributor record (the pre-cross-dataset two-argument merge), keeps the fail-closed `plateRegion` stamp.

### Rationale

A MetaFood3D β is fitted on volumes integrated above the authored plane the object rests on (Decision 13) — exact by construction, residual 0. That plane IS the object's support surface, so the volume basis is the same one the device's `foodSupport` fitter measures above at inference; `plateRegion` describes a flood-fill fit that never ran for these rows. Stamping the true basis is what lets Req 8.3 hold end-to-end while the Req 5.4 basis gate keeps genuine N5k mixture β (and mixed-basis pools) out of the bake.

### Alternatives Considered

- **Keep `plateRegion` for all mixture β**: no code change, maximally fail-closed — Rejected: makes Req 8.3 unsatisfiable; every MetaFood3D-only class is silently reference-skipped at bake forever.
- **Relax the `generate.py` reference gate for MetaFood3D classes**: bake-side special case — Rejected: the artifact would keep recording a reference that is factually wrong for these β, and the bake would need dataset knowledge the artifact already encodes better per class.
- **Record the reference per observation and propagate the exact basis into the merge**: most precise — Rejected: the merge only sees per-dataset thresholded effective samples today; a per-observation reference plumb-through is a larger change with the same outcome for every case that exists (MF3D rows are the only injected-plane rows).

### Consequences

**Positive:**
- Req 8.3 holds end-to-end: a MetaFood3D-only staple clearing the statistical gates bakes, carrying `single_source_uncorroborated` provenance.
- The stamp now states the basis the β was actually fitted on; N5k mixture β and mixed-basis pooled β keep failing closed.
- The pre-cross-dataset two-argument merge (empty contributor records) is bit-identical, preserving the Req 7.1 golden.

**Negative:**
- The discriminator is the dataset name string, mirroring the CLI's injected-plane branch keying — a second dataset with authored planes would need to extend it.
- A class whose N5k rows all sit below τ_eff (so `nutrition5k` never enters its contributor record) would stamp `foodSupport` despite marginal plate-region rows having entered the pooled solve; the influence is bounded by the sub-τ_eff mass shares.

### Impact

`HarnessCore/CalibrationArtifact.swift` (`reference(for:)` + the `ClassEntry` construction), pinned by `CalibrationReferenceGuardTests` and exercised end-to-end by `EndToEndCalibrateBakeTests`. No change to `generate.py`, the merge, or any on-device code.

---

## Decision 17: Canonical run-summary contract with an emitter-generated fixture; per-dataset licence provenance

**Date**: 2026-08-09
**Status**: accepted

### Context

An adversarial review of the merged implementation found that `tools/metafood3d/ingest.py` and the Swift decoder (`CalibrateRun.loadIngestSummary`) had drifted on the `run_summary.json` key names: the emitter wrote `snapshot_identifier`, `render_config.width`/`height` and omitted `mapping_version`/`seating_rule`, while the decoder read `snapshot`, `mapping_version`, `render_config.image_width`/`image_height`/`seating_rule` and defaulted every missing key to `""`. Only `plane_depth_mm` matched, so a real ingest → calibrate run would pass every gate and bake per-dataset lineage of empty strings — a silent Req 9.1 violation, masked by the end-to-end test hand-writing the Swift-side keys. Separately, `HarnessCLI` hardcoded `lineage.licence = "CC BY 4.0"` even when MetaFood3D (CC BY-NC 4.0, non-commercial) contributed, understating the pool's licence obligations in the artifact and the baked `calibration_licence` meta row.

### Decision

Canonicalise the contract on the Swift decoder's names — `snapshot`, `mapping_version`, `licence`, `render_config.{plane_depth_mm, intrinsics_model, image_width, image_height, seating_rule}` — and enforce it from both sides: the Python emitter writes exactly these keys; a committed contract fixture (`tools/metafood3d/tests/fixtures/run_summary_contract.json`) is generated by the real emitter (`make_contract_fixture.py`), diffed against the emitter by pytest, and fed byte-for-byte to the built HarnessCLI by the end-to-end test; and the Swift loader exits 1 (never defaults to `""`) when a non-Nutrition5k summary misses any required lineage key. For licences: each contributing dataset's licence is recorded in its `lineage.per_dataset` entry (MetaFood3D's read from its run summary, required; Nutrition5k's the known CC BY 4.0), and the top-level `lineage.licence` becomes the STRICTEST contributing licence, with unrecognised licence strings ranking strictest of all.

### Rationale

The decoder's names win because they are the richer, self-describing set (`image_width` vs a bare `width`), they were already documented as the contract in `docs/agent-notes/n5k-calibration-harness.md`, and they include the two keys Req 9.1's reproducibility actually needs (`mapping_version`, `seating_rule`) that the emitter never wrote. A schema agreed on only in prose drifted once; a fixture produced by one side and consumed by the other side's real binary cannot drift silently — a key change goes red in pytest (emitter vs fixture) or in the Swift end-to-end run (decoder exits 1 on the fixture). The top-level licence must stay (the bake hard-requires it, nutrition5k-calibration Req 1.5) and a single value for a mixed pool is only honest if it is the most restrictive one: a CC BY-NC contribution makes the whole calibrated output non-commercial in effect, and per-dataset entries preserve the attribution detail the single value cannot.

### Alternatives Considered

- **Canonicalise on the Python emitter's names** (`snapshot_identifier`, `width`/`height`): equal drift-proofing once fixed — Rejected: still omits `mapping_version` and `seating_rule`, so the Swift side (and the agent-note contract) would need semantic additions anyway; the decoder-side names were the documented contract.
- **Generate the e2e summary via a subprocess into ingest.py at test time**: no committed artefact to go stale — Rejected: `ingest.py` imports numpy at module scope, and the Swift test suite must not depend on the host python having the tool venv; a committed fixture keeps the Swift gate hermetic while pytest owns freshness.
- **Drop the top-level `lineage.licence` in favour of per-dataset only**: no aggregation rule to defend — Rejected: `generate.py` hard-aborts on a missing top-level licence (Req 1.5 of the N5k spec) and downstream consumers read one `calibration_licence` meta row; removing it widens this fix into a bake-contract change.
- **Top-level licence as a joined list of all contributing licences**: lossless — Rejected: consumers of the single meta row would need parsing rules; the strictest-wins scalar answers the only question the field exists for (what obligations bind the output), and the per-dataset block keeps the detail.

### Consequences

**Positive:**
- A real MetaFood3D ingest → calibrate run now either bakes complete Req 9.1 lineage or fails loudly at summary load — the silent empty-lineage path is closed.
- The emitter and decoder share one committed artefact; either side changing keys turns a gate red in its own language's suite.
- The artifact and the baked DB state the licence that actually binds them; a CC BY-NC contribution can no longer masquerade as CC BY.

**Negative:**
- An intentional contract change now touches three places (emitter, fixture regeneration, decoder) plus the agent note — deliberate friction.
- The licence strictness ranking is a small curated table; a new dataset with an unlisted licence ranks strictest until the table is extended (fail-strict, but potentially over-restrictive).
- N5k summaries keep their looser optional decoding for backwards compatibility, so the loud-failure guarantee applies only to non-N5k datasets.

### Impact

`tools/metafood3d/ingest.py` + `render.py` (canonical keys, `mapping_version`, `seating_rule`), `tools/metafood3d/tests/` (contract fixture + regeneration script + diff tests), `HarnessCore/CalibrationArtifact.swift` (`loadIngestSummary` contract check, `DatasetLineage.licence`, `strictestLicence`), `HarnessCLI/main.swift` (licence wiring), `EndToEndCalibrateBakeTests` (consumes the committed fixture), and the two agent notes' contract tables. No on-device code.

---

## Decision 18: MetaFood3D (CC BY-NC 4.0) may contribute to research calibration; commercial ship requires an NC-free re-bake or a commercial licence

**Date**: 2026-08-10
**Status**: accepted

### Context

MetaFood3D is licensed CC BY-NC 4.0 (non-commercial), unlike Nutrition5k's CC BY 4.0, and the question of whether NC-derived βs may ship commercially had been left open. As of this date nothing NC has shipped: the dataset is request-gated and no snapshot has been obtained, no MetaFood3D fixtures exist in the repo, and both bundled databases record `calibration_licence = CC BY 4.0` with Nutrition5k-only lineage. MetaFood3D touches nothing outside the calibration pool — segmenter training and estimation-quality make no reference to it. The Decision 17 provenance machinery (per-fixture `source_dataset=metafood3d@<snapshot>` stamps, baked `calibration_contributing_datasets_per_class`, strictest-licence top-level `calibration_licence`) makes any future NC contribution visible per class in the shipped artefact.

### Decision

MetaFood3D data may contribute freely to research and MVP-phase calibration. Before any commercial release, either (a) re-run calibrate with all MetaFood3D fixtures excluded from the pool and re-bake, verifying `calibration_licence = CC BY 4.0` in the output meta rows, or (b) obtain a commercial licence from the dataset authors. The gate is auditable: a commercial build's databases must not list `metafood3d` in `calibration_contributing_datasets_per_class` unless option (b) was taken.

### Rationale

Removal is mechanical by construction — the calibrate pool is just the set of fixture directories passed in, so an NC-free bake is a re-run without the MetaFood3D fixtures, and the baked provenance meta rows prove the result is NC-free without trusting process discipline. Deferring the commercial question therefore carries no entanglement risk, while blocking MetaFood3D now would forfeit its sample-size boost for exactly the classes where Nutrition5k is thinnest (lentils n=1, pasta n=1, brown_rice n=2 in the current bake) during the phase where accuracy iteration matters most.

### Alternatives Considered

- **Bar MetaFood3D from the pool entirely until the commercial question is settled**: zero licence exposure — Rejected: forfeits the accuracy gains for thin-sample classes during the research phase, and the provenance machinery already makes later removal clean, so pre-emptive exclusion buys nothing.
- **Treat βs as uncopyrightable facts not bound by CC BY-NC**: scalar regression coefficients are arguably not "adapted material" — Rejected as the load-bearing position: the question is legally unsettled, and the repo's fail-strict posture (strictest licence wins) is the defensible default. It remains available as a fallback argument, not the plan.
- **Ship commercially with NC βs and rely on the NC clause applying only to redistribution of the dataset itself**: Rejected: CC BY-NC restricts use of the licensed material in commercial contexts, not just redistribution; this reading invites exactly the dispute the provenance machinery exists to avoid.

### Consequences

**Positive:**
- Research calibration can use MetaFood3D immediately when the snapshot lands, with no licensing pre-work.
- The commercialisation path is a re-run plus a meta-row check, not an untangling exercise.
- The decision is enforceable from the artefact alone (`calibration_licence`, `calibration_contributing_datasets_per_class`), independent of who runs the bake.

**Negative:**
- A commercial re-bake reverts thin-sample classes to the weaker Nutrition5k-only βs unless another CC BY source has been found by then — the cost of removal is accuracy, not mechanics.
- The gated request form may impose terms beyond CC BY-NC 4.0; those terms must be reviewed at submission time and could tighten this decision.
- Two β sets (research vs commercial) must not be confused; the meta rows are the guard, but release tooling must actually check them.

### Impact

Governs the calibration pool composition for any commercial release; no code changes. Release-time check: `calibration_licence` and `calibration_contributing_datasets_per_class` meta rows in `cofid_db.sqlite`/`afcd_db.sqlite`. Resolves the "MetaFood3D licence" open decision. Dataset access is request-gated (form + password) — a property of the source, recorded in the root README's data-sources section; when a snapshot lands, the mapping regenerates via `build_mapping.py --categories-file`.

---

## Decision 19: Rigid native-archive layout for MetaFood3D ingest; category-qualified object identity

**Date**: 2026-08-10
**Status**: accepted

### Context

The real MetaFood3D snapshot arrived (access obtained 2026-08-10) and contradicted two assumptions the pre-contact ingest carried. First, the planned layout (`meshes/<category>/<object_id>.<ext>`, flat files under category directories) does not exist in the shipped archives: the native shape is `3D_Mesh/<Category>/<object>/` with one textured mesh per object *directory*, categories named like `Almond(bowl)`, and inconsistent file-stem capitalisation. Second, ingest keyed object identity on the mesh file stem alone — and object directory names repeat across categories in the real data (`almond_3` exists under both `Almond(bowl)` and `Almonds`), so stem keying would silently collide fixtures, metadata rows, and truth entries. The nutrition workbook (`complete_dataset_nutrition_v2.xlsx`, 637 objects / 108 categories, matching the site's claims) is the metadata source; its `Object_name` column holds the category and `Food_Type` the object — inverted from what the names suggest.

### Decision

Ingest requires exactly one rigid layout — the shipped mesh archive extracted verbatim plus one derived file: `<mf3d-dir>/3D_Mesh/<Category>/<object>/` containing exactly one mesh file (`.obj|.ply|.glb|.off`; texture and `.mtl` siblings ignored), and `<mf3d-dir>/metadata.csv` produced by the new stdlib-only `derive_metadata.py` from the v2 workbook. Any structural deviation — a stray file at category or object level, zero or multiple mesh files in an object directory, a missing or mis-headed metadata.csv — is a hard error whose message prints the expected tree and the exact commands to create it. Object identity is the directory pair; every emitted id (fixture filenames, skip lists, truth sidecar) is `<Category>__<object>` in raw on-disk names. `derive_metadata.py` is equally rigid: it accepts exactly the known nine-column v2 header and aborts showing found-versus-expected on any deviation.

### Rationale

A tolerant loader that adapts to layout variants accumulates guessing code for eventualities that may never occur, and each guess is a place the real data can be misread silently. A rigid contract inverts the cost: the code stays small and single-shaped, and when a future snapshot deviates, a human reads an error that names the deviation and reshapes the data (or deliberately extends the tool) — data problems surface as instructions to the user, not as parser behaviour. Choosing the native archive shape as the contract means the user's setup is `tar -xzf` plus one derivation command, with nothing to rearrange. Directory-pair identity is forced by the data: stems collide across categories, and directory names are the only stable, unique handle the snapshot provides.

### Alternatives Considered

- **Keep the planned flat layout and require the user to rearrange the archive to fit**: no code change — Rejected: flattening 637 object directories (with cross-category name collisions to manually resolve) is exactly the kind of error-prone busywork the tool should absorb; "easy to recreate the structure" must mean minutes, not scripting.
- **Tolerant discovery (rglob for meshes anywhere, fuzzy metadata matching)**: survives any layout — Rejected: silently wrong on the real data (stem collisions), and every tolerance is an undocumented contract nobody can audit; the Decision 17 lesson is that contracts drift unless one side pins them.
- **Read the nutrition workbook directly from ingest.py (no metadata.csv intermediary)**: one fewer step — Rejected: it drags xlsx parsing into the render-venv tool and couples ingest to workbook cosmetics; a committed-format CSV keeps the ingest contract inspectable with `head`, and the derivation step is where a unit-conversion note would live if a future snapshot ships non-gram weights.

### Consequences

**Positive:**
- Setup from downloads is two commands, both printed verbatim by the error messages when anything is missing.
- Cross-category name collisions are structurally impossible in fixture ids, skip lists, and the truth sidecar.
- The real workbook derives cleanly: 637 objects, 108 categories — the first on-data validation of the site's claimed counts.
- The `run_summary.json` contract (Decision 17) is untouched: summary keys, the committed contract fixture, and the Swift decoder are all unchanged.

**Negative:**
- A future snapshot that renames `3D_Mesh/` or reshapes the workbook header stops the pipeline until a human reconciles it — deliberate friction, the same trade Decision 17 made.
- Fixture ids carry raw directory names (parentheses, mixed case: `Almond(bowl)__almond_3`) — traceable to disk, but cosmetically uneven downstream.

### Impact

`tools/metafood3d/ingest.py` (layout verification, `discover_objects`, `MeshEntry`, keyed metadata), `tools/metafood3d/derive_metadata.py` (new), `tools/metafood3d/tests/` (`mf3d_testkit.write_dataset` new layout, `TestRigidLayout`, `test_mf3d_derive_metadata.py` new), agent note `docs/agent-notes/metafood3d-ingestion.md`. No Swift-side changes; the Decision 17 contract fixture is byte-identical.

---

## Decision 20: Mapping regenerated against the real enumeration; coverage is 11 classes, not the hoped-for carb staples

**Date**: 2026-08-10
**Status**: accepted

### Context

The blind-written curated rules (the artifact's universe since the spec closed) named categories that do not exist in the real dataset: the v2 nutrition workbook's enumeration (637 objects / 108 categories, written to `categories.txt` by `derive_metadata.py`) shares almost no spellings with them. More materially, the real taxonomy undercuts the spec's motivating premise. There is no cereal-type category (no oatmeal, porridge, or breakfast cereal — Decision 15's "cereal reachability" rationale is void on real data), no plain pasta (`Pasta_mixed_dishes` is composite), no lentils, and rice and bread appear only as method-ambiguous generics (`Rice`, `Yeast_bread`). The dataset skews heavily to composite dishes (burger, lasagna, sushi, tacos), battered/fried items, and desserts — 93 of 108 categories are unmappable under the conservative-identity policy.

### Decision

Rewrite `MAPPED_RULES`/`AMBIGUOUS_RULES` against the real enumeration and commit the artifact built in enumerated mode: `categories_source` records the enumeration's SHA-256, all 108 categories are recorded, and the stale-rule abort is now armed. The curation maps 13 categories to 11 classes (80 objects): apple 7, banana 7, beef 4 (Steak), broccoli 9, carrot 12, chicken 10 (breast + thighs), chips_fries 6 (French_Fry), egg 5, pork 5 (Pork_Chop), potato_mashed 4, tomato 11 (Tomato + Tomato_slice). `Rice` (8 objects) and `Yeast_bread` (9) are recorded ambiguous. Conservative exclusions include bacon/sausages (cured), chicken wings/whole chicken (skin/bone-heavy), fried egg/omelet (added fat), baked potato (a stated method neither potato class covers), and sweet potato (different species). `derive_metadata.py` now also writes `categories.txt` so one derivation step feeds both consumers.

### Rationale

The curation policy is unchanged — conservative identity, ambiguity never guessed — only applied to real names instead of guessed ones. The honest outcome is that MetaFood3D's calibration value shifts from "boost the thin carb staples" to "add three classes the N5k pool lacks entirely (banana, chips_fries, potato_mashed) and corroborate eight it has." The thin classes that motivated the spec (lentils n=1, pasta n=1, brown_rice n=2) get nothing; recording that plainly now prevents the corpus run from being read as a fix for them.

### Alternatives Considered

- **Map aggressively (bacon→pork, baked_potato→potato_boiled, omelet→egg) to lift coverage**: more βs — Rejected: the curation policy exists because a β fitted against compositionally wrong ground truth bakes a silent bias; coverage bought with wrong identity is negative value.
- **Disambiguate `Rice`/`Yeast_bread` per object via the workbook's FNDDS food code**: 17 additional objects, including the rice classes we actually want — Deferred, not rejected: the mapping artifact is category-level by design (Req 1.3), and per-object disambiguation is a contract change to ingest. Worth its own decision if the corpus run shows the 11-class pool is worth extending; the FNDDS column is already preserved in the workbook.
- **Keep the committed artifact curated-only until meshes arrive**: no churn — Rejected: the enumeration is snapshot data we already hold; committing the enumerated artifact now arms the stale-rule abort and makes ingest one command when meshes land.

### Consequences

**Positive:**
- The committed artifact records the full real universe; unknown-category counts at ingest time now mean snapshot drift, not curation blindness.
- Three palette classes gain their first calibration source; eight gain a second (cross-dataset corroboration per the merge rules).
- The stale-rule abort is armed: a future snapshot renaming categories fails the build loudly.

**Negative:**
- The spec's motivating gap (pasta, lentils, rice βs) remains open — MetaFood3D does not close it, and another CC BY source would be needed for those classes.
- 15 % of the dataset's objects are usable (95 of 637 counting the ambiguous 17); the download is mostly unusable for calibration.
- Per-class samples are modest (4–12 objects); single-source classes (banana, chips_fries, potato_mashed) bake only if they clear the statistical gates alone.

### Impact

`tools/metafood3d/build_mapping.py` (rules rewritten, docstring), `tools/metafood3d/mapping_metafood3d_to_palette.json` (regenerated, enumerated mode), `tools/metafood3d/derive_metadata.py` (+`categories.txt`), tests (mapping coverage pins, ingest category names, derivation enumeration), agent note. No Swift-side changes; `mapping_version` lineage changes with the artifact hash, as designed.

---

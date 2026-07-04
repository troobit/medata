# Design: cross-dataset-calibration

## Overview

Ingest MetaFood3D single-food captures into the existing β calibration harness by rendering an overhead depth map per mesh and routing each object as a single-class **mixture** observation. Carb-staple classes gain clean single-food volume↔mass samples that Nutrition5k's mixed plates cannot supply, with no change to the fixture contract or the calibrator.

## Architecture

### Integration point: MetaFood3D enters as "mixture" fixtures

The harness routes fixtures by `estimator_path` (`FixtureLoader.swift`, authoritative over the SHA). A single-food object is a degenerate one-class mixture, so MetaFood3D fixtures are stamped `estimator_path="mixture"`, `segmenter_checkpoint_sha256="no_segmenter"`, **no probability tensor** — exactly the shape the mixture path already accepts. This satisfies Req 3 (single-class observation, no segmenter, not checkpoint-gated) with **zero router changes**: `CalibrateRun.route()` drops them into the same pool as N5k mixture rows, and they enter one shared `MixtureBetaCalibrator` BVLS solve.

**Consequence for pooling (Req 4).** "Pooling" is extra rows in the shared design matrix. A MetaFood3D row has one non-zero column (mass fraction 1.0), so it breaks the collinearity that kept N5k staples unidentifiable. Note the mechanics precisely: the calibrator's `effectiveSamplePerClass` is a **threshold count** — `+1` per plate where the class's mapped-mass share ≥ τ_eff (0.15) (`MixtureBetaCalibrator.swift:86-94`), *not* a precision weighting. Collinearity is not down-weighted in that count; it is down-weighted downstream in the **identifiability gate** — the relative-SE ≤ 0.15 bound and condition number from the Gram-matrix eigen-inverse. So the effective-sample (≥30) gate plus the relative-SE gate together are what stop a collinear pool from qualifying on raw count (Req 4.2). A single-class row correctly gets `+1` and, being orthogonal, tightens its class's SE — no bespoke weighting layer is built (Decision 11). The one code check: a unit test asserting a single-non-zero row increments the class count and lowers its SE.

### The render (the one genuinely new subsystem)

`tools/metafood3d/render.py` turns a mesh into the `nadir_depth` buffer the volume estimator consumes. CPU ray-cast via `trimesh` (Decision 12): a pinned nadir **perspective** camera casts one ray per pixel; the first-hit distance along each ray becomes depth in millimetres. Deterministic, no GL context — consistent with the offline / reproducible-from-lineage invariants.

Pinned render configuration (recorded in lineage, Req 2.4/9.1):

| Field | Value | Why |
|---|---|---|
| intrinsics | N5k pinned model (RealSense D435 RGB nominal, 640×480; `ingest.py:95-97`) | β must be fit under the same camera model N5k uses; the 1/cos³θ term is intrinsics-dependent |
| pose | nadir; gravity = (0,0,−1) | matches N5k nadir convention (`LiDARPlaneFitter` gravity orientation) |
| plate/plane depth | ~385 mm, inside N5k `CAMERA_TO_PLATE_BAND_MM` (250,400), below the 0.4 m cap (`ingest.py:82-90`) | seats MetaFood3D at the true N5k plate distance; the reference-depth check the ingest reuses then passes for the right reason |
| seating | stable resting pose under gravity, base on the plane; every food pixel closer than the plane | MetaFood3D meshes have no guaranteed up-axis. Food nearer than the plane ⇒ positive height-above-plane, so no pixel is silently dropped by `TotalHullVolume`'s `max(0,·)` gate |

Depth encoding matches the contract: Float32 LE mm, row-major, 0 = miss (`DepthMap.proto`).

**Mesh metric-scale check (Req 1.5).** MetaFood3D meshes are natively metric (fiducial-calibrated capture) and ship a per-object **gramme weight**, but no per-object linear dimension. So the check is two hard gates, aborting on failure: (a) a **global unit-sanity gate** — the snapshot's object bounding-box distribution must sit in a physically sane millimetre range, catching a one-off mm/m import or loader-scale error; (b) a **per-object weight plausibility** — the mesh bounding-box volume under a density band must bracket the shipped gramme weight. β is a scalar against mass, so an unchecked scale error is a pure multiplicative volume error that would bake silently.

### Support plane: injected, not refit (Decision 13)

For a nadir render, a **steep-sided food** (tall rice, stacked sandwich) presents a >5 mm depth cliff at its edge; `fitPlateRegionPlane`'s centre-seeded flood fill (4-neighbour, |Δz|<5 mm, `FixtureRunner.swift:139-243`) would never cross it to reach the synthetic plane, and RANSAC would fit the *food surface* — a silent, shape-dependent volume error. Since the MetaFood3D plane is authored exactly (known normal + distance), the MetaFood3D calibrate branch **injects that `SupportPlane` directly** into `TotalHullVolume`, bypassing the RANSAC refit. This removes the failure mode and is exact.

Trade-off, stated: N5k keeps its RANSAC-refit plane (real-rig noise) while MetaFood3D gets a perfect plane — a per-dataset plane-fit asymmetry. This is consistent with, and no worse than, the noise-free-render stance already accepted in Decision 8 (MetaFood3D β is a clean geometric fit; N5k carries rig artefacts). The skew guard (Req 5) and the volume-fit diagnostic are what surface any resulting disagreement.

### The three β computations

| Fit | Input | Output | Baked? |
|---|---|---|---|
| Mass-fit (combined) | N5k + MetaFood3D mixture rows, one BVLS solve, GT mass with ρ_DB | per-class β via `CalibrationMerge` | **Yes** (Req 2.2) |
| Per-dataset (skew + corroboration) | N5k-only and MetaFood3D-only solves | per-dataset β + SE + identifiability per class | No — feeds the skew guard (Req 5.1) |
| Volume-fit diagnostic | per object: β_geom = V_mesh_true / V_est, aggregated per class | geometric β per class | No — reported (Req 2.3) |

The volume-fit diagnostic isolates the estimator's geometric bias from the density mismatch the mass-fit conflates (Decision 7); a large gap between baked β and β_geom flags a density-draw problem. True mesh volumes come from a `metafood3d_truth.json` sidecar written by ingest.

### Skew guard and corroboration (Req 5, 6)

A class is **corroborated** only when ≥2 datasets each produce an *independently identifiable* standalone β (each clears effective-sample + relative-SE on its own solve) **and** those pass an equivalence test (Decision 10): TOST — the (1−2α) CI of (β_N5k − β_MF3D), using SE_Δ = √(SE_N5k² + SE_MF3D²), lies within ±δ·β̄ (δ default 0.20, α default 0.05, both in lineage). Not equivalent → flag `cross_dataset_inconsistent` → pooled/unity (Req 5.3).

Any class not corroborated — single dataset present, *or* present in two but independently identifiable in only one — is flagged `single_source_uncorroborated` (Req 6.2). It still bakes on the effective-sample + relative-SE gates and is not accuracy-gated (Decision 9). `CalibrationMerge` keeps its existing mixture rule; the additions are the corroboration flag plus two `ClassEntry` fields, not a new merge path.

### Reporting (Req 8, 10)

Extend `AccuracyHarness` (one element, owning Req 4.3, 8.2, 10.1, 10.2):

- **Per-class β delta + coverage (Req 8.2, 10.1):** for each class, effective-sample and status before (N5k-only) vs after (combined), and the β change attributable to MetaFood3D.
- **Carb accuracy delta (Req 10.1):** carb MAPE/MAE combined vs N5k-only on the N5k eval pool; per-class deltas reported **only** above a minimum eval-plate count; a staple absent from the eval pool is marked *no in-harness accuracy validation*.
- **Held-out anchor (Req 10.2):** fixed-seed split of MetaFood3D objects; predict mass = V_est·β·ρ_DB on held-out objects, report MAPE; broccoli cross-check where present. Reported, not a bake gate.
- **Per-dataset contribution (Req 4.3):** per class, each contributing dataset's sample count into the baked β.

### Parity audit — adding a dataset to the calibrate flow

| Touch point | Change | Rationale |
|---|---|---|
| `tools/metafood3d/{ingest,render,build_mapping}.py`, `mapping_metafood3d_to_palette.json` | **new** | mirror `tools/nutrition5k/`; ingest reuses `build_fixture_bytes`; emits mixture fixtures + `run_summary.json` + `metafood3d_truth.json` |
| `CalibrateRun.route()` | none | routes by `estimator_path` already |
| `CalibrateRun` MetaFood3D branch | inject authored `SupportPlane` into `TotalHullVolume` (Decision 13) | skip the RANSAC refit for the known plane |
| `MixtureBetaCalibrator`, `FixtureLoader`, `TotalHullVolume` | none | single-class rows + injected plane use existing inputs; add an effective-sample unit test |
| `CalibrationMerge` | set corroboration flag; call skew guard | Req 5, 6 |
| `CrossDatasetSkew` | **new** | per-dataset identifiability + TOST |
| `VolumeFitDiagnostic` | **new** | β_geom aggregation (reported) |
| `CalibrationArtifact` | +2 `ClassEntry` fields, +render-config, +per-dataset contribution & lineage | additive |
| `AccuracyHarness` | β-delta, carb-delta with eval-plate guard, held-out anchor | Req 4.3, 8.2, 10 |
| `HarnessCLI/main.swift` | merge multi-dataset `--ingest-summary`; `--heldout-frac` | Req 10 |
| `tools/food_db/generate.py` | persist the new per-class fields as meta JSON dicts | additive |

### Backwards compatibility (Req 7)

New `ClassEntry`/lineage keys are additive with defaults; the fixture contract is untouched. **N5k-only** (zero MetaFood3D rows) is the combined solve with no added columns, so at a fixed seed it reproduces the current baseline β — pinned by a golden test (Req 7.1).

In the **combined** bake, baseline β *can* move — this is the intended pooling: a staple crossing the 30-effective bar changes from a fixed-offset (β=1, subtracted from the RHS) to a solved column, perturbing co-occurring classes; MetaFood3D-only classes that never co-occur on N5k plates stay orthogonal and do not. The Req 10.1 per-class β-delta report is where this becomes visible. One regression risk to watch: broccoli is the only currently-calibrated class, so if the datasets disagree the skew guard (Req 5.3) can demote it to pooled/unity — the report must surface that.

## Components and Interfaces

```
# tools/metafood3d/render.py
render_overhead_depth(mesh, cfg: RenderConfig) -> np.ndarray  # HxW float32 mm, 0 = miss
  # trimesh perspective ray grid at cfg.intrinsics; first-hit z

# tools/metafood3d/ingest.py  (mirrors tools/nutrition5k/ingest.py; reuses build_fixture_bytes)
check_metric_scale(meshes, meta) -> None  # raises → abort: global unit-sanity + per-object weight plausibility
ingest(mf3d_dir, out_dir)                 # *.fixture (estimator_path="mixture", no probs, authored plane params),
                                          # run_summary.json (excluded/unmapped ids+counts),
                                          # metafood3d_truth.json {fixture_id: mesh_volume_mm3}
```

```swift
// HarnessCore/CrossDatasetSkew.swift  (new)
enum CrossDatasetSkew {
  static func equivalent(betaA: Double, seA: Double, betaB: Double, seB: Double,
                         delta: Double, alpha: Double) -> Bool          // TOST
}

// HarnessCore/CalibrationArtifact.swift  ClassEntry additions
struct ClassEntry { /* … existing … */
  var contributingDatasets: [String: Int]   // dataset → sample count feeding this β (Req 4.3)
  var singleSourceUncorroborated: Bool      // not corroborated by ≥2 identifiable, TOST-agreeing datasets
}
```

## Data Models

Additive calibrate-artifact / DB fields:

- `ClassEntry.contributing_datasets: {dataset: count}`, `ClassEntry.single_source_uncorroborated: Bool`.
- `lineage.render_config` — intrinsics id, plate/plane depth, resolution, seating rule, δ/α (Req 9.1).
- `lineage.per_dataset` — per-contributing-dataset snapshot + mapping-artifact version.
- `generate.py` persists meta JSON dicts: `calibration_contributing_datasets_per_class`, `calibration_single_source_classes`.

`RunSummary` gains per-dataset exclusion buckets (`*_excluded_by_dataset`) so N5k depth-test-split drops and MetaFood3D scale/unmapped drops stay attributable.

## Error Handling

| Condition | Handling |
|---|---|
| Global unit-sanity or per-object weight-plausibility check fails | abort ingest, record id + measured-vs-expected in run_summary (Req 1.5) |
| Render miss / degenerate mesh (no frame intersection) | skip object, record id |
| No stable resting pose | skip object, record id |
| Unmapped or ambiguous cooking-method category | exclude, count in run_summary (Req 1.3/1.4) |
| Skew test inconsistent | class → pooled/unity (Req 5.3) — expected, not an error |
| Class not corroborated | bake with `single_source_uncorroborated=true` (Req 8.3) — not an error |

## Testing Strategy

Harness-side tests only (`HARNESS_ENABLED` Swift + Python), consistent with the existing MedataCore/HarnessCLI suites; no app/UI tests.

- **Backwards-compat golden (Req 7.1):** N5k-only calibrate at fixed seed reproduces the current baseline β byte-for-byte through the pooling path.
- **Single-class fit (Req 2/3):** a synthetic single-class mixture fixture with an injected plane yields β ≈ GT_mass/(V_est·ρ_DB) within tolerance, no segmenter/checkpoint; and increments the class effective-sample and lowers its SE (the M1 check).
- **Metric-scale abort (Req 1.5):** a mesh whose bbox-volume-vs-weight leaves the density band aborts; a snapshot with a mm/m unit error trips the unit-sanity gate.
- **Injected plane (Decision 13):** a steep-sided synthetic food yields correct volume with the injected plane where the RANSAC refit would fit the food surface.
- **Skew/corroboration (Req 5.2, 6.2):** boundary β pairs map to the correct flag; a count==2 class identifiable in only one dataset is flagged `single_source_uncorroborated`.
- **Reporting (Req 8.2, 10.1):** per-class β-delta and eval-plate-count guard behave; a staple absent from the eval pool is marked unvalidated.
- **End-to-end (Req 7.2):** small synthetic MetaFood3D fixture set → `calibrate.json` → `generate.py` bake; palette↔DB lock holds; new per-class fields persist.

**Property-based (pytest + Hypothesis):**
- *Render determinism:* same mesh + config → byte-identical depth across runs.
- *Weight-plausibility:* a uniformly k-scaled mesh (weight unchanged) leaves the density band and is caught by the scale check.
</content>

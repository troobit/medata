# Nutrition5k calibration harness (stream B, HarnessCore)

Swift side of the nutrition5k-calibration spec (tasks 9–22). All files are
`#if HARNESS_ENABLED` and never ship on-device.

## Pieces and how they connect

- `TotalHullVolume` — total above-plane hull volume for the mixture path.
  Depth-threshold silhouette (height above plane > ε = 3 mm; sentinel/at-cap
  pixels are written as 0 by ingestion and excluded by the `zt > 0` guard).
  Geometry (ray-plane height, off-axis 1/cos³θ pixel area) intentionally
  mirrors `HeightFieldEstimator` — only the masking differs (the recorded
  Req 5.1 masking-transfer gap). Uses NEAREST depth sampling, not bilinear,
  so a sentinel excludes exactly its own pixel.
- `FixtureRunner.plateRegionMask` / `fitPlateRegionPlane` — flood fill on
  4-neighbour depth continuity (threshold 5 mm) seeded at the frame centre
  (spiral-searches up to 8 px for a valid seed); stops at the plate-rim
  discontinuity. The plane is fitted INSIDE that region via
  `LiDARPlaneFitter.CandidateRegion.insideMask` (a new additive mode — the
  default band-scan mode samples *outside* the food mask and would land on
  the table). RANSAC then picks the plate annulus as the dominant plane.
  **Scoped to the MIXTURE path since support-plane-reference task 16.**
  `FixtureRunner.run` no longer branches on `estimatorPath` at all — both the
  N5k single-dominant and legacy branches now go through
  `FixtureRunner.fitSupportPlane`, which calls the same
  `LiDARSupportPlaneFitter.fitFromDepth` the device runs (Req 5.1), with the
  food mask derived from `nadirSeg`'s argmax. The flood fill survives only for
  `CalibrateRun.mixtureObservation`, whose fixtures carry neither `probs_hwc`
  nor `argmax_hw` and so have no mask to derive (Decision 17). Planes fitted
  there record `SupportPlaneReference.plateRegion`, and β_c is fitted within one
  reference (Req 5.4) — see `CalibrateRun.applyReferenceGate`.
- `MixtureBetaCalibrator` — hand-rolled BVLS (Lawson–Hanson active set with
  bound interpolation) in Double, plus a cyclic-Jacobi symmetric eigensolver
  used both for the rank-deficiency-safe free-set LS solve and the SE /
  condition-number diagnostics. β bounds [0.05, 1.5] enforced inside the
  solve (x = 1/β ∈ [1/1.5, 20]). Collinear classes surface as enormous SE
  (eigenvalues floored at λmax·1e-12, NOT pseudo-inverse-dropped) →
  `identifiable = false`. Under-sampled classes (< 30 effective) are held at
  β = 1 and moved to the RHS (`fixedOffsetClasses`).
- `BetaCalibrator.calibrateWithFit` — unchanged §6.9 closed form; the
  `PerClassFit` mirrors the SPLIT-based fit (60/40) exactly — this is the
  SELF-EVALUATION entry point only. The baked β comes from
  `BetaCalibrator.bakeFit`, which holds nothing out (design §Split
  reconciliation: 30-plate floor, not ~50) — `main.swift` feeds `bakeFit`'s
  output to CalibrationMerge/the artifact and keeps the split result for the
  legacy eval. `logResidualSE` ≈ relative SE on β.
- `CalibrationMerge` — per-class arbitration (Req 5.2/5.4): single-dominant
  wins when effective ≥ 30 AND rel SE ≤ 0.15; else a qualifying mixture fit;
  else pooled/unity with provenance `none`. A class calibrated on raw count
  alone but failing the SE gate is demoted to the POOL β, not its unqualified
  fitted value. `BetaProvenance` is a separate dimension from
  `BetaCalibrationStatus` (Decision 16).
- `FixtureLoader` — per-path guards keyed off `estimator_path`
  (authoritative; the sentinel string alone never selects the path). Sentinel
  is `no_segmenter` (must match `tools/nutrition5k/ingest.py`). Legacy
  fixtures (empty path) keep the original hash guard.
- `AccuracyHarness.evaluateCalibration` — seeded k-fold CV (fold fits via
  MixtureBetaCalibrator), oracle mass-proportion attribution
  (est_c/GT_c = (V/M)·ρ_c·β_c — mixes co-occurring densities, so even a
  perfect β leaves a few % on mixed plates), official-split whole-dish
  section, cross-macro flag (1.5× carb MAPE with a 5-point absolute floor),
  pool arithmetic. GT macros per class come from the caller, NOT re-derived
  from the DB — that's what lets the cross-macro check see composition errors.
- `CalibrateRun.evalPlate` builds the eval plates: GT macros from the
  fixture's per-class N5k maps (proto fields 24–26, Decision 27); fixtures
  predating the maps fall back to GT mass × DB fraction (circular across
  macros — the 6.7 flag can never fire on the fallback).
- `CalibrateRun` + `CalibrationArtifact` — CLI wiring (depth-test-split
  exclusion FIRST, τ_purity = 0.90 volume gate: failures dropped, never
  re-routed) and the calibrate JSON artifact (the sole stream B↔C interface;
  `generate.py` consumes it). `betaPool` stays top-level for existing
  consumers.

- `CalibrateRun.loadIngestSummary` + `route(fixtures:depthTestSplit:unmappedExcluded:)`
  — the harness consumes the ingestion `run_summary.json` via HarnessCLI
  `--ingest-summary` (Req 4.1): fixtures carry mapped masses only, so the
  >10%-unmapped-mass mixture exclusion cannot be re-derived Swift-side.
  Without the flag those plates would enter the fit and bias co-occurring β
  downward. The calibrate artifact's `run_summary` block records the excluded
  dish ids; the pool report carries `unmapped_excluded_count`.

## First full pre-checkpoint run (2026-07-03, task 39)

**Its numbers are superseded by the 2026-08-05 rebase below** — kept because the
command recipe and the pool-arithmetic shape are still the reference.

- Committed artifacts:
  `specs/estimation/nutrition5k-calibration/artifacts/{calibrate.json,
  accuracy_report.json}` and the calibrated
  `MedataCore/Sources/Foods/Resources/{cofid_db,afcd_db}.sqlite`. Reproduce
  with `.build/release/HarnessCLI calibrate[-and-eval] --fixtures-dir
  tmp/n5k_fixtures --depth-test-split data/dish_ids/splits/depth_test_ids.txt
  --ingest-summary tmp/n5k_fixtures/run_summary.json --mapping-version
  <first 12 of sha256 of mapping_n5k_to_palette.json> --seed 42`, then
  `python3 tools/food_db/generate.py --calibration-json <calibrate.json>`.
- Pool arithmetic: 3,490 dish folders → 3,485 ingested (5 skipped: 1
  malformed depth, 4 depth out of band; both Req 3.1 reference-depth checks
  passed) → 507 official depth-test split, 2,688 unmapped-mass excluded,
  45 liquid, 56 stacking → **181 qualifying mixture plates**. The unmapped
  exclusion dominates: most N5k dishes carry ingredients outside the 24-class
  palette.
- Only **broccoli** calibrates (β = 0.516, eff 35, SE 0.058); carrot has eff
  48 but is unidentifiable (collinear co-occurrence); everything else is
  under 30 effective. All other classes stay at unity — the documented
  Req 4.5 outcome, not a failure. Carb MAPE 105.8 → 81.9 on the k-fold pool;
  no staple meets the 20% target (best-sampled staple is white_rice at 10
  effective).
- The post-checkpoint single-dominant re-fit + supersession re-run stays a
  manual step gated on model-production Bucket C.

## Rebase onto the promoted support plane (2026-08-05, support-plane-reference task 17)

Both committed artifacts were regenerated with the same flags and the same seed.
Ingestion re-ran from the raw corpus (`build/n5k_fixtures` / `tmp/n5k_fixtures`
is gitignored and had been reaped), pre-checkpoint as before.

**The promoted fitter never runs on this corpus.** Pre-checkpoint ingestion
stamps every plate `mixture` — `run_summary.json` reports
`estimator_paths: {mixture: 3485, single_dominant: 0}` — and mixture keeps the
plate-region flood fill permanently (Decision 17). So `FixtureRunner.fitSupportPlane`,
the branch task 16 promoted, is reached zero times here. N5k gains promoted-path
coverage only when Bucket C lands and ingestion re-runs with `--checkpoint`.
What the rebase actually buys is the `support_plane_reference` stamp: without it
the Req 5.3 fail-closed guard aborts the bake, so until it ran the corpus
contributed no β at all.

Numbers did move, and **not because of the support plane**: the stacking guard
divides mapped mass by `densityByClass` from the bundled DB, which was rebaked
between the two runs (`c855042` food DB v2, `bcbe9bd` cereal row). Two more
plates now fail `totalHullVolume < 0.6 × expectedMin`.

| | 2026-07-03 | 2026-08-05 |
|---|---|---|
| Qualifying mixture plates | 181 | 179 |
| Stacking excluded | 56 | 58 |
| broccoli β (eff, SE) | 0.516 (35, 0.058) | 0.495 (34, 0.055) |
| Carb MAPE baseline → calibrated | 105.8 → 81.9 | 66.7 → 67.5 |

Depth-test split (507), unmapped-mass excluded (2,688), liquid (45) and
plane-fit skips (8 of 290 mixture; 4 of 507 official-split) are all unchanged.

Two things worth carrying forward. **Calibration no longer beats baseline on
carbs** — 67.5 vs 66.7 MAPE, where it used to be 81.9 vs 105.8; the DB v2
composition tables moved the baseline far more than β moves the estimate, and
one class fitted at 0.495 is not enough to recover the difference. Protein and
fat still improve. And the bake bakes **nothing**: broccoli is the only
calibrated class, its per-class reference is `plateRegion`, and Req 5.4 skips
any class not fitted under `foodSupport`, so every β stays
`uncalibrated_unity` (Decision 10 holds). Re-running `generate.py` against the
new artifact is therefore behaviour-neutral; it only writes the calibration
lineage into `meta`, which the DB v2 rebake had dropped.

## Review fixes (2026-07-03)

- N5k runs REQUIRE `--depth-test-split` (exit 1 without it — Req 4.4 is a
  SHALL) and warn to stderr when `--ingest-summary` is missing (the Req 4.1
  unmapped exclusion cannot be applied without it).
- The lineage block also records `liquid_significant_fraction`,
  `unmapped_significant_fraction`, `relative_se_bound`,
  `effective_sample_min` — a bake is reproducible from lineage alone.
- FixtureLoader's mixture guard rejects `nadir/oblique_argmax` as well as
  probs (an argmax is segmenter output too, Req 3.7).
- Official-split dishes skipped from the whole-dish eval (non-mixture path,
  no depth, plane-fit failure) are enumerated to stderr (Req 6.8).

## Cross-dataset additions (cross-dataset-calibration stream 2, 2026-08)

Swift side of specs/estimation/cross-dataset-calibration (tasks 7–19, 22).
MetaFood3D objects enter as degenerate single-class MIXTURE rows (Decision
11): `estimator_path="mixture"`, sentinel SHA, no probability tensor — zero
router/loader/calibrator changes. Everything below is additive.

- `CrossDatasetSkew` — TOST equivalence (Decision 10): the (1−2α) CI of
  (β_A−β_B) with SE_Δ=√(SE_A²+SE_B²) must lie within ±δ·β̄ (δ=0.20, α=0.05
  defaults, both in lineage). Fails closed on degenerate inputs, and on wide
  SEs even when the point estimates agree — under-powered is "not
  corroborated", never "corroborated by default".
- `VolumeFitDiagnostic` — β_geom = V_mesh_true/V_est mean per class from the
  `metafood3d_truth.json` sidecar ({fixture_id: mesh_volume_mm3}). Reported,
  never baked.
- `CalibrateRun.mixtureObservation(fixture:injectedSupportPlane:)` — the
  MetaFood3D branch (Decision 13). The authored plane bypasses
  `fitPlateRegionPlane`: on a steep-sided nadir render the flood fill cannot
  cross the >5 mm edge cliff and RANSAC fits the FOOD surface (pinned by
  `InjectedPlaneTests`). `CalibrateRun.authoredSupportPlane(gravity:planeDepthMm:)`
  builds it (n̂ = normalised gravity, positive distance, residual 0).
- `CalibrationMerge.merge(singleDominant:mixture:perDataset:)` — per-dataset
  standalone solves feed corroboration + skew. A class is corroborated only
  when ≥2 datasets are each independently identifiable (own solve clears
  eff ≥ 30 AND identifiable) AND all pairs TOST-agree; otherwise calibrated
  classes carry `single_source_uncorroborated=true`. Skew-inconsistent (≥2
  identifiable, TOST-fail) demotes to the POOL β with
  `crossDatasetInconsistent=true` even when the pooled fit qualifies
  (Req 5.3). The two-argument `merge` forwards with `perDataset: []` and is
  the Req 7.1 identity — pinned bit-for-bit by `BackwardsCompatGoldenTests`.
- `CalibrationArtifact` — now Codable (round-trip tested). ClassEntry +=
  `contributing_datasets`/`single_source_uncorroborated`; lineage +=
  `render_config` (incl. the Req 2.5 noise-free-render note) + `per_dataset`;
  RunSummary += `*_excluded_by_dataset` count buckets. All additive with
  absent-tolerant decoding.
- `AccuracyHarness` extensions (`CrossDatasetReporting.swift`):
  `betaCoverageDelta` (before/after eff+status+β), `carbAccuracyDelta`
  (baseline-vs-combined β on the N5k eval pool; per-class only at ≥ 10 scored
  plates, thinner classes suppressed-with-count, staples absent from the pool
  listed as unvalidated), `heldOutSplit` (seeded shuffle of sorted ids) and
  `heldOutAnchor` (mass = V_est·β·ρ_DB MAPE; broccoli cross-check). All
  reported, none gate a bake (Decision 9).
- Per-class `support_plane_reference` stamping (Decision 16 of the
  cross-dataset spec): a mixture-provenance β whose contributing datasets
  are exclusively `metafood3d` stamps `foodSupport` — its volumes were
  integrated above the authored plane the object rests on, which is the
  device's basis — so it APPLIES at bake (Req 8.3). Any N5k contribution,
  or an empty contributor record (the two-argument merge), keeps the
  fail-closed `plateRegion` stamp, so the 2026-08-05 "bake bakes nothing"
  behaviour is unchanged for N5k-only runs.
- `EndToEndCalibrateBakeTests` (task 23) runs the REAL chain: synthetic
  MF3D fixture set on disk → the built `HarnessCLI` binary via Process →
  calibrate.json → `generate.py` bake (PATH `python3`; the Apple 3.9
  cannot evaluate the `str | None` annotations) → SQLite meta/row
  asserts. It locates the products directory via `dladdr` on
  `#dsohandle` — the swift-testing runner is a toolchain helper, so
  Bundle-based lookups fail. `generate.py` runs with cwd = temp dir so
  the relative OUTPUT_DIR keeps the committed DBs untouched.
- `HarnessCLI` — `--ingest-summary` is now REPEATABLE (one per dataset) and
  `--heldout-frac` selects the MetaFood3D anchor holdout. A run with
  MetaFood3D fixtures REQUIRES the MF3D summary to carry
  `render_config.plane_depth_mm` (exit 1 otherwise — the alternative is the
  silently-wrong RANSAC refit). MetaFood3D fixtures are recognised by the
  `source_dataset` stamp prefix before "@" (`CalibrateRun.dataset(of:)`).

**Contract stream 1's `tools/metafood3d/ingest.py` run_summary.json must
match** (all keys optional on N5k summaries, which decode unchanged):
`dataset` ("metafood3d"), `snapshot`, `mapping_version`,
`skipped: {reason: [ids]}`, `mixture_fit_excluded_unmapped`,
`liquid_excluded`, and `render_config: {plane_depth_mm, intrinsics_model,
image_width, image_height, seating_rule}`. The truth sidecar is a flat
`{fixture_id: mesh_volume_mm3}` JSON.

## Gotchas

- `CalibrateRun.applyPurityGate` drops inputs with no entry in
  `massDominantByFixture` (purity 0). Legacy inputs must be filtered out
  before the gate — `main.swift` does this.
- `MixtureBetaCalibrator.Result.conditionNumber` is NaN when nothing was
  solved; sanitise before JSON-encoding (JSONEncoder throws on NaN/∞).
- The gravity convention for `LiDARPlaneFitter`: the plane normal is oriented
  n̂·gravity > 0 and must be within 15° of the passed gravity vector. N5k
  nadir fixtures use gravity (0,0,−1), so the fitter returns n̂ = (0,0,−1)
  with positive `distanceMm`; the volume integrators only use |z| magnitudes,
  so the sign convention is safe.

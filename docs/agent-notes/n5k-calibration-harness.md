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

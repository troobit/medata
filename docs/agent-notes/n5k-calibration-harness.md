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
  `FixtureRunner.run` uses this path whenever `fixture.estimatorPath` is
  non-empty; legacy fixtures keep the all-ones-mask fit.
- `MixtureBetaCalibrator` — hand-rolled BVLS (Lawson–Hanson active set with
  bound interpolation) in Double, plus a cyclic-Jacobi symmetric eigensolver
  used both for the rank-deficiency-safe free-set LS solve and the SE /
  condition-number diagnostics. β bounds [0.05, 1.5] enforced inside the
  solve (x = 1/β ∈ [1/1.5, 20]). Collinear classes surface as enormous SE
  (eigenvalues floored at λmax·1e-12, NOT pseudo-inverse-dropped) →
  `identifiable = false`. Under-sampled classes (< 30 effective) are held at
  β = 1 and moved to the RHS (`fixedOffsetClasses`).
- `BetaCalibrator.calibrateWithFit` — unchanged §6.9 closed form; the new
  `PerClassFit` mirrors the SPLIT-based fit (60/40) exactly. For the
  no-holdout bake basis, pass all qualifying plates. `logResidualSE`
  ≈ relative SE on β.
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

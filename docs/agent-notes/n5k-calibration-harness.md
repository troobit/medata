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

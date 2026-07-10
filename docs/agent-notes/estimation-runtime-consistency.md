# Estimation runtime consistency guards

Two conservative, additive guards in the deterministic geometry/β chain
(PRD `specs/estimation/estimation-quality/prd.md`, "Estimation runtime
consistency"). Both are fully deterministic and offline — identical inputs
give identical output; no RNG was added.

## LiDAR plane-fit consensus polish

`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift`, step 3b of `fit(_:)`.

- **Variance source**: the RANSAC winner's ±5 mm inlier band is anchored to a
  3-point candidate plane. Points near the band edge flip membership under the
  millimetre-level depth differences between two captures of the same plate,
  so the winning triple (and therefore the LSQ plane) differs capture to
  capture. `plane.distanceMm` feeds the mm/px scale directly
  (`lidarMmPerPx = |d| / fMean` at Pipeline stage E) and the plane feeds every
  height-field sample, so plane jitter multiplies straight into cm³ → grams →
  carbs.
- **Guard**: after the existing LSQ refinement, re-select inliers against the
  REFINED plane (same 5 mm band) and re-refine, iterating until the consensus
  set stops changing (cap `consensusPolishMaxPasses = 3`). The fixed point is
  (largely) independent of which minimal sample won.
- **Conservative fallbacks**: a re-selection that goes below `minPoints`,
  fails `refine` (degenerate SVD), or lands outside the 15° gravity cone keeps
  the previous pass's plane — the polish can never fail a fit that previously
  succeeded.
- `debugLastInlierCount` now reports the POLISHED inlier count (feeds the
  `supportplane.end success=false` trace in `Pipeline.swift`).
- Existing accuracy/determinism tests in
  `MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterTests.swift` cover the
  polished path unchanged (clean fixtures reach the fixed point immediately).

## Fail-closed food-coverage gate

`MedataCore/Sources/Pipeline/FoodRegionCoverage.swift`
(`minimumFoodCoverageFraction`, `foodCoverageFraction`,
`enforceMinimumFoodCoverage`), called in `Pipeline.estimate` immediately after
Stage F (segmentation), before β/Volume, for BOTH capture paths.

- **Variance source**: β application on a near-empty mask — with only a
  handful of food-argmax pixels, the volume comes from a few noisy depth
  samples and β multiplies that noise straight into the carb number.
- **Threshold**: `minimumFoodCoverageFraction = 0.001` (0.1 % of frame pixels,
  ~2 765 px at 1920×1440). Real plates run 1–8 % of the frame (device masks
  are 92–99 % background), so genuine meals never trip it. Coverage counts
  pixels whose argmax is a food OR recognised liquid class (the estimators'
  integration predicates); background/unknown_food/unsupported_liquid do not
  count. Exactly-at-threshold accepts.
- **Refusal**: reuses the EXISTING `EstimationFailure.noFoodPixels` (§5 edge
  case 3 "zero food pixels" extends to "too few to estimate") — no new enum
  case, same user-facing message.
- Unit tests: `FoodCoverageGateTests` suite in
  `MedataCore/Tests/PipelineTests/FoodRegionCoverageTests.swift`
  (swift-testing).

Gotcha: the gate runs on the post-shutter argmax (`nadirSeg.argmax`), not the
pre-shutter `BinaryMask` — the pre-shutter empty-mask gate (Decision 2) in
`SupportPlaneFitter` still fires first when the pre-shutter mask is empty.

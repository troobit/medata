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
  polished path unchanged.

### What the corpus says about all of that (support-plane-reference Decision 54)

Three of the sentences above are claims about real captures, and
`SupportPlaneCorpusMeasurementTests.thePolishCapIsACapOnALoopThatFixedPointsFirst`
measures them against the two committed `.depthslice` fixtures. **Read this
before changing the cap or citing the guard.**

- **"Iterating until the consensus set stops changing" is not what happens.** The
  cap always binds. At 3, extraction is truncated on 4 of its 6 passes and
  reaches the fixed point on 1; **both** fallback fits are truncated. Swept to
  64, the depth the corpus needs is **17** in extraction and **11** in the
  fallback. The plane both paths ship is a truncated iterate, not the fixed
  point. (The earlier "clean fixtures reach the fixed point immediately" here
  was a statement about the synthetic test fixtures, and it does not transfer.)
- **The polish does not remove the seed dependence it was added for.** Eight
  seeds, plane at the food: 2.123 / 2.095 / 2.067 mm at 0, 3 and 64 passes on
  `1785135663727` — **2.9 %** for running the loop to convergence. It works on
  the other capture (0.096 → 0.001 mm), which was nearly seed-stable already.
  What removes it is `SupportRegion.ransacSuccessProbability`: 2.095 → 0.194 mm
  (Decision 51). The residual spread is the seeds disagreeing about which
  *candidate wins*, and the polish refines a plane rather than reordering a set.
- **The gravity-cone fallback is inverted in effect.** "A re-selection outside
  the cone keeps the previous pass's plane" is correct as written, and on
  `1785135663727`'s third pass the previous plane is the **ungated** refinement
  before the loop — itself outside the cone at 20.512°. The gate fires at 0
  applied iterations and the `break` is what preserves the plane the cone exists
  to exclude. See `support-plane-fit.md`; not repaired, because removing the
  candidate moves the answer.

Two more things the cap turns out to decide: the candidate **count**
(`1785135663727` yields 2 candidates at 0–1 passes and 3 from 2 up, so the
persisted `planeCandidateCount` is denominated here), and the **fallback**
plane, which moves 1.719 mm on `1785901032716` over 0…64 — past Req 5.1's 1 mm,
while the promoted plane moves 0.106 mm. `consensusPolishMaxPasses` is `[owed]`,
bracketed 1…unbounded, and interpolable.

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

---
references:
    - specs/estimation/depth-grown-food-region/smolspec.md
    - specs/estimation/depth-grown-food-region/decision_log.md
---
# Depth-Grown Food Region — Tasks

## Pipeline

- [x] 1. A seed region on a raised slab grows to the slab's cliff and no further, deterministically, with the cap and floor as passthrough guards (Req 1–3) <!-- id:7i9k8j5 -->
  - FoodRegionGrowth.grow in the Volume module: depth-grid multi-source breadth-first fill from the food-like colour pixels, |Δz| ≤ cliffMm, confidence ≥ tauConfidence, height above the plane ≥ floorMm (ray–plane helper lifted from HeightFieldEstimator), first arrival labels, mapped back to the colour grid; returns the grown ArgmaxMap, the added-pixel BinaryMask, before/after counts and a capTripped flag. Constants on a GrowthConfig: cliff 4 mm, floor 3 mm, cap 0.35, plus .disabled.
  - Verify: VolumeTests on synthetic depth — a two-speck seed on a 30 mm slab with a one-cell cliff grows to the whole slab and stops at it; a plate-height ramp below the floor is not entered; growth past the cap returns the input unchanged with capTripped true; two seed classes on one slab split by distance; a run is byte-identical across two calls; .disabled returns the input; make test green (both totals).

- [x] 2. The height-field integrator measures every grown pixel and leaves ungrown estimates byte-identical (Req 5) <!-- id:7i9k8j6 -->
  - HeightFieldEstimator.Inputs gains grownRegion: BinaryMask? (default nil); a pixel the mask marks skips the (1 − qBg) < tauSilhouette test and nothing else changes.
  - Verify: VolumeTests — a grown pixel whose probabilities say background integrates volume when marked and none when unmarked; every existing HeightFieldEstimator test passes unchanged; make test green (both totals).
  - Blocked-by: 7i9k8j5 (A seed region on a raised slab grows to the slab's cliff and no further, deterministically, with the cap and floor as passthrough guards Req 1–3)

- [x] 3. The single-view path grows the region, refits the plane and scale from it, integrates over it, and shows it, while the bundle keeps the segmenter's map (Req 4–6) <!-- id:7i9k8j7 -->
  - Pipeline.estimate .singleViewLidar: growth after enforceMinimumFoodCoverage; on change, fitSupportPlane again with the grown food mask, take its plane and recompute lidarMmPerPx/MetricScale on success, keep the first plane on refusal; integrate with the grown argmax and grownRegion; mask artefact writer gets the grown map; CaptureBundleRecorder keeps nadirSeg.argmax; PipelineDiagnostics.recordRegionGrowth(applied:capTripped:before:after:refitReference:) lands in the outcome measurements; Release log line event=region.grow applied= before= after= refit=.
  - Verify: a Pipeline-level test with a stub segmenter and synthetic depth shows the record's volume covering the slab, the bundle argmax equal to the segmenter's, and the outcome measurements carrying the growth fields; Debug build warning-free via make build-app; make test green (both totals).
  - Blocked-by: 7i9k8j5 (A seed region on a raised slab grows to the slab's cliff and no further, deterministically, with the cap and floor as passthrough guards Req 1–3), 7i9k8j6 (The height-field integrator measures every grown pixel and leaves ungrown estimates byte-identical Req 5)

## Harness

- [x] 4. Harness single-view replay grows the same region as the device and sweeps the constants from the command line (Req 7) <!-- id:7i9k8j8 -->
  - FixtureRunner.run applies FoodRegionGrowth before HeightFieldEstimator.integrate and repeats its fitter call with the grown mask; HarnessCLI accuracy takes --growth-cliff-mm, --growth-floor-mm, --growth-cap (0 disables) and reports per-capture before/after food-like fractions and capTripped.
  - Verify: HarnessCLITests — replay of a synthetic fixture matches the pipeline test's volume; --growth-cap 0 reproduces the pre-change number byte-for-byte; make test green (both totals).
  - Blocked-by: 7i9k8j7 (The single-view path grows the region, refits the plane and scale from it, integrates over it, and shows it, while the bundle keeps the segmenter's map Req 4–6)

- [x] 5. The shipped constants are the ones the corpus sweep admits under the Req 8 pass rule, recorded in Decision 1 <!-- id:7i9k8j9 -->
  - Run HarnessCLI accuracy over the corpus captures with depth (/Users/r/repos/medata-corpus/captures, single-view bundles) at cliff {3, 4, 6} mm × floor {2, 3, 5} mm with cap 0.35; table per setting: median added area on captures with ≥ 5 % ungrown food-like area, cap-trip count, and the grown fraction on 1790223818017-success.
  - Verify: the table and the chosen constants appended to Decision 1; GrowthConfig.standard carries them; make test green (both totals). Gates the merge of research into main, not the device pass (Decision 2).
  - Blocked-by: 7i9k8j8 (Harness single-view replay grows the same region as the device and sweeps the constants from the command line Req 7)

## Device

- [x] 6. STOP — Release build on device measures the sesame roll whole: outline covers the roll, plane refit lands foodSupport, carb figure plausible for a ~60 g roll; field note updated <!-- id:7i9k8ja -->
  - make deploy-release; capture the roll single-view; expect event=region.grow applied=true with after ≫ before, supportplane refit reference=foodSupport, review outline over the whole roll, and a bread row in the tens of grams of carbohydrate; pull the log and bundle.
  - Verify: log trail and outcome row cited in docs/agent-notes/field-truth-sessions.md under a 2026-09-24 entry; make spell.
  - Blocked-by: 7i9k8j7 (The single-view path grows the region, refits the plane and scale from it, integrates over it, and shows it, while the bundle keeps the segmenter's map Req 4–6)

## Seed-area gate

- [x] 7. Growth on the single-view path is skipped when the segmenter already covers more than 200 cm² of the first plane, and every outcome row says why (Req 9, Decision 5)
  - FoodRegionGrowth.foodAreaCm2 measures the food-like footprint on the first plane; FoodRegionGrowthConfig.seedAreaGateCm2 (standardSeedAreaGateCm2 = 200); GrownRegionPlaneRefit.refit(gateBySeedArea:) skips grow and refit when over it, single-view callers only (Pipeline via planeOnly == false, FixtureRunner single-view); the two-view plane-only growth is never gated.
  - Outcome rows carry regionGrowth.seedAreaCm2, seedAreaGateCm2 and gated; event=region.grow prints seedAreaCm2, gateCm2 and gated; HarnessCLI takes --growth-gate-cm2 and prints both on the growth line and in volumes rows.
  - Verify: the gate sweep (Nutrition5k 216 plates, the four weighed single-view plates) in Decision 5; GrownRegionPlaneRefitTests cover the footprint and the gate; make test green (both totals); make spell.

## Second growth guard

- [x] 8. A second guard against runaway growth (grown/seed ratio or grown-footprint cap, fall-back or clamp) is swept on Nutrition5k and the weighed set, and ships only if it beats the current state on both (Decision 6)
  - Swept on 2a6f2b8: ratio fall-back 2-16x, grown-footprint fall-back 100-400 cm2, clamp at 2-6x seed and 100/150/200 cm2, over the 216 scored Nutrition5k plates and the five 2026-09-29/10-03 weighed captures (mass at true class).
  - Outcome: nothing ships. No variant beats the current state on both sets; the toast (1790748465041) grown region is its two slices (205 cm2 against a 207 cm2 raised slab), and its +105 % is the plate under it plus density, not runaway growth. A ratio cap would also remove the 15.2x founding roll capture 1790223818017.
  - Verify: Decision 6 tables; field-truth-sessions 2026-10-03 replay table; make test green (both totals); make spell.

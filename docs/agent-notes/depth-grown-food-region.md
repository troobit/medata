# Depth-grown food region

Spec: `specs/estimation/depth-grown-food-region/` (smolspec + decision log).
Code: `MedataCore/Sources/Volume/FoodRegionGrowth.swift`; wiring in
`Pipeline.estimate` (single-view branch) and `HarnessCore/FixtureRunner.run`.

## What it does

Grows every food-like region of the regularised nadir label map into the
raised depth slab around it before volume, so a food the segmenter only
partly recognises (the 2026-09-24 sesame roll: 0.5 % of the frame labelled,
7 % raised) is measured whole. Single-view LiDAR only; the two-view carve is
untouched.

Order matters and is the whole design: **grow → refit → prune.**

1. `FoodRegionGrowth.grow` — multi-source BFS on the 256×192 depth grid from
   the cells under food-like colour pixels. A neighbour is admitted when
   |Δz| ≤ `cliffMm`, confidence ≥ `HeightFieldEstimator.tauConfidence`, and
   its height above the **support surface** ≥ `floorMm`. First arrival
   labels a cell. Over `frameFractionCap` of the frame → the input is
   returned with `capTripped`.
2. The pipeline refits the plane with the grown mask (`supportPlaneFitter.
   fitOutcome`), and adopts it (plus recomputes the LiDAR metric scale) only
   when step 3 leaves added pixels.
3. `FoodRegionGrowth.prune` — the same height test against the plane the
   volume will use.

Grown pixels bypass the integrator's probability silhouette test through
`HeightFieldEstimator.Inputs.grownRegion`; nothing else in the integrator
changes, so ungrown estimates are byte-identical.

## The support surface, and why continuity alone failed

The first plane is fitted before segmentation from the pre-shutter mask. On
an `edgeBand` fallback it is the **table**, and the fitter's ring median is
the plate top's height above it (+18…+26 mm on the corpus; 19.7 mm on the
roll). `Pipeline.supportOffsetMm` / `SingleViewPlaneFit.supportOffsetMm`
return that median on an `edgeBand` fit and 0 on `foodSupport`; growth
measures height above plane + offset.

The first draft admitted cells by depth continuity alone and pruned after the
refit. The corpus sweep killed it in one run: at cliff 3, 4 and 6 mm the fill
tripped the cap on 7 of 10 captures (the roll among them) and leaked 5–11 %
of the frame on the other 3. ARKit's smoothed depth has no cliff at a food's
edge — it is a slope of a few mm per cell. Do not reintroduce a
continuity-only rule; the cliff now only stops the fill crossing a real drop.

Known inert case: a first plane admitted as `foodSupport` on a flat food's own
top (speck seed on a flat-topped food). Nothing is raised above it, growth adds
nothing, and the estimate is today's.

## Constants (Decision 1 table, 2026-09-24)

`FoodRegionGrowthConfig.standard` = cliff 3 mm, floor 3 mm, cap 0.35.
Floor 2 mm let plate noise in (median added area on well-segmented plates
+40 %, one plate 2.5×); floor 3 mm reads +9 %; floor 5 mm dropped the roll's
refit back to `edgeBand`. Cliff made no difference to the median; 3 was
chosen over 6 for one unverifiable outlier. Sweep with
`HarnessCLI accuracy --growth-cliff-mm C --growth-floor-mm F --growth-cap X`
(cap 0 disables the pass and reproduces the ungrown numbers); it prints one
`growth fixture=… before= after= applied= capTripped= refit= plane=` line per
fixture on stderr. Only 10 single-view successes on `ab812dc3aa9d` load from
the corpus; `1786450130307-success.fixture` is truncated at exactly
170,000,000 bytes and must be excluded or the loader refuses the directory.

## Gotchas

- The bundle keeps the segmenter's (ungrown) argmax; replay re-grows. The
  mask artefact the review outline reads is the grown map.
- The colour-grid edge follows the bilinear depth contour, not the 7.5 × 7.5
  px cell blocks: a pixel is added when its own bilinear depth clears the
  floor and its cell or a 4-neighbour cell was filled (evening 2026-09-24,
  after the "speckles around edge of roll" field note). Counts in tests are
  therefore ranges, not cell multiples.
- `pipelineStageLog` is Debug-only; `event=region.grow` is on
  `supportPlaneLog` so it reaches the Release log.
- Outcome rows carry `regionGrowth {applied, capTripped, foodPixelsBefore,
  foodPixelsAfter, refitReference, refitRefused}`; the plane fields describe
  the plane the volume used (the refit when adopted).

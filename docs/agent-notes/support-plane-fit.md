# Support-plane fitting

Two fitters live in `MedataCore/Sources/SupportPlane/`, and they answer different
questions. Read this before changing either.

| File | Question it answers | Reference recorded |
|---|---|---|
| `LiDARPlaneFitter.swift` | largest gravity-aligned plane in four colour-grid bands around the food bbox | `edgeBand` — the table, in a plate scene |
| `SupportRegion.swift` | which gravity-aligned plane the food is actually resting on | `foodSupport` |

`SupportRegion` is the `specs/estimation/support-plane-reference/` feature.
`LiDARPlaneFitter` is not being deleted: it is the fallback, and Req 4.3 requires the
fallback plane to be byte-identical to what it produces today.

## Why the old fitter is wrong and still kept

Volume is integrated per-pixel above the support plane, so a plane 26.1 mm too low adds
26.1 mm to every food pixel. Two weighed captures: 80 g of bread read as 285.94 g
(3.57×), 208 g of rice as 440 g (2.1×). The over-read is proportionally largest on the
flattest food. `LiDARPlaneFitter` is not buggy — it faithfully implements what pipeline
Req 4.2 asked for, which is why the feature amends the specification rather than only
the code.

## SupportRegion, in the order the data flows

1. **`depthIntrinsics(from:depth:)`** — derives depth intrinsics from the COLOUR ones.
   Never read `depth.depthIntrinsics`: `ARKitCaptureEngine` writes it as all zeros, so
   reading it divides by zero and yields a NaN plane. The half-pixel terms
   (`cx_d = (cx_c + 0.5)·s − 0.5`) match `sampleDepthBilinear`. The dangerous mistake is
   not dropping those terms (0.433 depth px of shift, ~0.016° of tilt) — it is passing
   the colour intrinsics through UNSCALED, which leaves the plane looking healthy at
   nadir while every mm-denominated radius is 7.5× too small.
2. **`prepare`** — one pass over the native depth grid: back-projected points, validity
   (`z > 0` and confidence ≥ τ_conf 0.40), the downsampled food mask, and
   `mmPerPx = medianFoodDepth / fx_d`. Everything downstream is millimetre-denominated
   off that scale, which is what makes the fit transfer across depth-grid resolutions
   (Req 5.1) — the N5k identity grid included.
3. **`ringSamples`** — an exact Felzenszwalb distance transform from the food mask gives
   each depth pixel its distance to the food. Samples 8–25 mm out are the ring (split
   into three radial bands and, for the inner band, eight angular sectors about the
   food-mask centroid); samples out to 50 mm are the annulus, which is the bounded
   candidate set.
4. **`extractCandidates`** — up to three sequential CC-RANSAC passes over the annulus,
   each removing its polished inliers within 2× the inlier band.
5. **`admissibility` + `fitFoodSupportPlane`** — guards filter EVERY candidate, then the
   best admissible one wins on inner-band support fraction.

## Things that will bite you

- **The mask downsample is deliberately conservative.** A depth pixel is food if ANY
  covered colour pixel is food. Req 2.1 requires the fitted set to contain no food
  pixel, so ambiguity resolves towards exclusion, and the colour→depth boxes overlap
  where the ratio does not divide evenly. Do not "fix" that into a majority vote.
- **`ringMinSamples = 200` holds PER radial band, not overall.** Banding divides the
  samples and sectoring divides the inner band again. Food smaller than ~25 mm across at
  350 mm therefore falls back — that is priced in (Decision 20), not a bug.
- **Perfectly planar synthetic depth is degenerate.** An exactly-flat sample set has a
  rank-2 scatter matrix and `LiDARPlaneFitter.refine`'s σ_min/σ_max gate rejects it as
  `lidarFitDegenerate`. The test scenes add ±0.3 mm of deterministic noise for this
  reason; a new scene without noise will fail with a confusing refusal.
- **The CC labelling is amortised by an exact bound.** A component can never be larger
  than the raw inlier count, so a hypothesis whose raw count cannot beat the running best
  component size is never labelled. Remove that guard and the cost becomes
  `maxIterationsPerPass × maxCandidatePlanes` labellings — order 1e8 ops, on the path
  that already produced a 32 GB allocation failure.
- **RANSAC draws three `uniformInt` per iteration unconditionally**, before any
  rejection test. That is what keeps the generator sequence independent of how many
  hypotheses are rejected and of how many passes ran before, i.e. what makes Req 7.7
  determinism hold across the multi-pass loop.
- **`candidatePointCount` / `inlierCount` change meaning with the reference.** On a
  `.foodSupport` row they are native depth samples; on `.edgeBand` they are colour-grid
  points. The two differ ~56× on device and must never be compared across references.

## Guards, and what each is actually for

Several guards in earlier drafts could not fire; the surviving set is the third
iteration (Decisions 16, 19, 22). If you are tempted to add a bar, check its firing
window against the admissibility floor first — that is how the residual bar, the
whole-ring MAD bar and the inner-band MAD bar were each removed.

- `supportFraction` is the score AND a guard. `|median|` is not the score: it has a 50 %
  cliff, and just past it the table plane reads ~0 and looks textbook-perfect.
- `supportingSectors` is the straddle detector and the Req 2.3 dispersion bar. Without
  it, food near a plate's edge selects the TABLE and persists a ring median of ~0 — the
  value the spec otherwise treats as proof of correctness.
- The band-step guard reads **inner→mid only**. A well plane's own profile rises outward
  whenever the ring spans well and rim, so a guard firing on any outward rise rejects the
  exact candidate the rimmed-plate handling exists to rescue (Decision 21).
- `foodEnvelope` is p90 of the food's signed height in MILLIMETRES, not a count fraction.
  The fraction version rejected this feature's own acceptance capture: overhanging food
  sits below the plate plane, so ~11 % of the weighed bread's samples voted against the
  correct fit at a 5 % bar (Decision 22).

## Known-marginal constants (task 26)

Every constant is annotated `[derived]`, `[measured]`, `[inherited]` or `[owed]` in the
source. The `[owed]` ones are corpus measurements and Req 3.7 forbids shipping the sector
trio as asserted values.

**Run the measurement pass before touching any of them:**

```bash
swift test --filter SupportPlaneCorpusMeasurement
```

`SupportPlaneCorpusMeasurementTests` is the instrumented, guards-disabled pass over the
committed `.depthslice` fixtures. Adding a capture to it means cutting a slice with
`tools/fixture_slice.py` and appending the stem to its `captures` list. What it settled
(Decision 29):

- `ringInnerMm = 8` holds, and the **range envelope is ≈ 365 mm**. The 4 px smear measures
  7.45 mm and 7.36 mm at 338.9 mm and 336.9 mm. Because the smear is a fixed pixel count,
  `smear_mm = 4z/f_d` with `f_d ≈ 182 px` — beyond ~365 mm the constant must become
  `max(ringInnerMm, 4 × mmPerPx)` or the ring sits inside the smear.
- `ringMinSamples = 200` per band holds at 5.6–7.0× margin (`[1120, 1132, 1213]` and
  `[1294, 1347, 1392]`), and inner-band sectors carry 102–184 samples apiece.
- `supportVisibilityMin` **is firable**, and the earlier note here saying otherwise was
  wrong about which region it measures. The ratio is computed over the **annulus**
  (0–50 mm, which begins at the food boundary), not the contact ring (8–25 mm), so a
  support strip thinner than `ringInnerMm` is counted. Ceilings measure 1.710 and 1.426
  against achieved 0.880 and 1.032. The value still needs prerequisites capture 4.

Three traps for anyone measuring against this corpus:

- **Adding a slice is not the same as adding evidence.** A third slice is committed and
  deliberately excluded, in `rejectedCaptures` rather than `captures` (Decision 31):
  `1785054950406`, the 208 g mounded-rice bundle. It slices cleanly, fills all three bands,
  and its confident food sits 15.1 mm above its confident surroundings — everything looks
  right until you read the confidence map, where **43.2 % of its food mask is ARKit-low
  against 0.0 % on both admitted captures**, and the discarded samples are the near ones
  (247.9 mm against the surviving 277.8 mm). τ_conf removes the mound; the best candidate
  reports the food as 9.0 mm *below* its own plane. Admit it and the sector test flips to
  "the trio is separable" on a capture with no food in it. Check
  `lowConfidenceFoodShare` before adding any capture.

- **Neither committed capture is a clean correct fit.** On `1785135663727` the plate-top
  candidate's per-sector inner medians reach −32.6 mm over a contiguous arc — the ring
  escapes onto the table over ~135°. On `1785901032716` the highest-support candidate is
  the **table**, not the plate. Do not tune a bar until these pass; that fits the wrong side.
- **Per-sample noise is surface-dependent, not range-dependent, at this range.** 3.44 mm
  on one capture and 6.98 mm on the other, both at ~337 mm. `ringBandMm = 5` falls between
  them, so `ringSupportMin` is underivable until a matte-surface capture exists.

And one defect in the guard itself (Decision 30, proposed, not fixed): `ringStatistics`
counts a supporting sector on `|height| ≤ ringBandMm`, so the count is **blind to sign**.
A correct plane whose ring escaped downward (failing sectors −6.8…−32.6 mm) and a table
plane with part of its ring on the plate (failing sectors +16.6…+19.8 mm) both score 5 of
8. The whole-ring median kept the sign for exactly this reason (Req 3.1, Decision 22); the
per-sector version lost it.

## Tests

`MedataCore/Tests/SupportPlaneTests/SupportRegion*Tests.swift`, with the scene builders
in `SupportRegionScenes.swift`. Scenes are nadir captures authored as HEIGHT MAPS in mm
above the table, because that is how the physical cases are described; the camera looks
straight down, so a gravity-aligned plane has normal (0,0,1) and a point's signed height
above a plane at depth Z is `Z − depth`. The colour grid is an exact 4× multiple of the
depth grid so the mask round trip is lossless — pick a non-multiple and the food mask
dilates by a pixel and every knife-edge scene shifts under you.

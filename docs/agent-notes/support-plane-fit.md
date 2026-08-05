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

- `ringInnerMm = 8` holds, and the **range envelope is `ringInnerMm × f_d / 4`** — 364.1 mm
  and 366.4 mm, with the corpus standing at 93.1 % and 92.0 % of it. The 4 px smear measures
  7.45 mm and 7.36 mm at 338.9 mm and 336.9 mm. Because the smear is a fixed pixel count,
  `smear_mm = 4z/f_d`; beyond the envelope the ring's inner band sits inside the smear.

  **Do not "fix" this with `mmPerPx`.** Decision 29 instructed that the constant become
  `max(ringInnerMm, 4 × mmPerPx)`, and Decision 39 measured that and refused it. `mmPerPx`
  is `z/f_d` and carries range and grid resolution alike, but only range moves the smear — a
  coarser grid subsamples a map ARKit has already smoothed. At 128 px the smear-tracking
  radius reads 14.9 mm for a physical smear still near 7.4 mm, leaves three ring bands of
  3.37 mm against depth pixels of 3.73 mm (each narrower than one pixel), and drops
  `1785135663727`'s inner band to 166 against the 200 floor on the very grid where the plane
  transfers within 0.9 mm. `mmPerPx` repairs grid dependence (Decisions 37, 38); it cannot
  repair range dependence. The envelope closes by recording the capture range, which
  `prerequisites.md` now requires. Measured by `smearTrackingInnerRadiusCollapsesTheRing`
  and `smearEnvelopeIsARangeBoundTheCorpusNearlyReaches`.
- `ringMinSamples = 200` per band holds at 5.6–7.0× margin (`[1120, 1132, 1213]` and
  `[1294, 1347, 1392]`), and inner-band sectors carry 102–184 samples apiece.
- `supportVisibilityMin` **is firable**, and the earlier note here saying otherwise was
  wrong about which region it measures. The ratio is computed over the **annulus**
  (0–50 mm, which begins at the food boundary), not the contact ring (8–25 mm), so a
  support strip thinner than `ringInnerMm` is counted. Ceilings measure 1.710 and 1.426
  against achieved 0.880 and 1.032. The value still needs prerequisites capture 4.

And what Decision 32 retired — the only `[owed]` value this feature has removed rather
than deferred:

- `minCandidateSamples` was **two constants under one name**. `extractCandidates` used it
  to stop the sequential passes; `fitFoodSupportPlane` used it to refuse the whole fit on a
  starved annulus. The second has an exact answer: `ringStatistics` returns nil unless
  every band clears `ringMinSamples`, and that test reads the radial banding alone, so it
  is plane-independent and knowable before extraction. `ringBandsAreFeasible(samples:)`
  now asks it directly. The substitution is outcome-identical *by construction* — the ring
  is a strict subset of the annulus, so under 500 annulus samples some band is under 167
  — not by measurement, which is why it is safe on a two-capture corpus.
- What is left is the residue floor, one job, still `[owed]` — and since Decision 38 it is
  `minResidueAreaMm2 = 1691`, not `minResidueSamples = 500`. A sample count quarters under
  a 2× grid halving where the surface does not, which is why the corpus ran three
  extraction passes natively and two halved, making the persisted `planeCandidateCount` a
  property of the sensor's grid. Converted through `mmPerPx` (rounded **up**, so the bar is
  never weaker) the count is 3 → 3. The value did not move: 500 samples is 1732.6 and
  1691.5 mm² on the two captures, so 1691 is the largest whole mm² at or below both. The
  corpus still bounds it **above only**, now at 2013 mm² (per-pass residues
  `[36 280, 11 471, 2013]` and `[42 458, 9509, 3153]` mm²). Do not read that as a
  derivation — it is where a floor begins costing something, not where a pass stops being
  worth running. The residue *area* is what the grid leaves alone: the annulus agrees to
  0.3 % and 1.2 % across the halving, later passes to 5–23 %, the spread coming from
  inlier removal being resolved on the grid.
- `minAcceptedExtentMm = 44` is **bracketed at 22.3…47.8 mm**, not set. Above a 22.3 mm
  (12 px), 153-sample sliver it correctly rejects; at or below the 47.8 mm smallest extent
  reaching the later guards — and that candidate fails `supportFraction` anyway, so the
  ceiling is soft. The 3.8 mm margin is asserted, so a capture that narrows it fails the
  test. It was `minAcceptedExtentPx = 24` bracketed at 13…26 px, which was a **256×192**
  bracket; Decision 37 re-denominated it, and the value did not move (24 px is 44.68 and
  44.14 mm at the two captures' `mmPerPx`). See the grid note below.

And what Decision 35 settled — the two Req 5.1 figures, which are not constants:

- **The tolerance is 1 mm and the fixture is `1785135663727`.** Device and replay run one
  implementation, so identical bytes agree exactly; the quantity at risk is the depth grid.
  Decimate 2× and the plane moves 0.835 mm and 0.037 mm at the food-mask centroid ray
  (normals tilting 0.945° and 0.063°). Compare planes *there*, not by coefficient: volume is
  integrated per-pixel above the plane, so a millimetre there is a millimetre everywhere.
- **The transfer floors at the ring, not the plane.** 128×96 holds; 64×48 leaves the inner
  band at 37 and 32 samples against `ringMinSamples = 200` and `ringBandsAreFeasible`
  refuses. Since `mmPerPx = z / f_d`, coarsening `f_d` and raising `z` move the same
  *quantity* — but they are **not the same constraint**, and Decision 39 is where that
  distinction is measured. The 4 px smear reads 14.9 mm at 128×96, well past `ringInnerMm`,
  while the plane still transfers within a millimetre, because decimation subsamples an
  already-smoothed map and the physical smear never moved. The smear bounds how clean the
  ring *measure* is, not where the plane lands — and it is bounded by **range**, not by grid.
- **`planeCandidateCount` was grid-dependent where the plane is not — Decision 38 fixed
  that.** Three passes natively, two at half resolution, because the residue floor was a
  raw sample count and sample counts quarter under a halving. It is persisted (Req 6.1), so
  the field recorded the sensor's grid rather than the scene. `minResidueAreaMm2 = 1691`
  converts through the same `mmPerPx`, and the count is 3 → 3. The residue *area* is the
  invariant: the annulus agrees to 0.3 % and 1.2 % across the halving; later passes drift
  5–23 %, because inlier removal is resolved on the grid.
- **The extent bar was the only one denominated in pixels — Decision 37 fixed that.** Pixel
  extents halve with the grid (123→61, 76→38, 155→77, 44→22) and the last of those crossed
  the old 24 px bar: same scene, same plane, opposite verdict. `minAcceptedExtentMm = 44`
  converts through the `mmPerPx` the ring radii already use, so the same four surfaces now
  drift 1.698, 0.102, 1.839 and 0.000 mm across the halving — at most half a halved-grid
  pixel — and **zero** verdicts flip. `tools/nutrition5k/ingest.py` pins N5k at f = 617 px
  against the device's measured f_d = 182.033 px, so the same physical extent spans 3.389×
  more pixels there; a pixel bar would have been 3.4× stricter on device, and a millimetre
  bar is the same bar on both. Nothing had hit it because pre-checkpoint N5k ingestion
  carries no food mask; model-production Bucket C is when it would have.

And what Decision 36 measured — `fallbackPenalty`, which lives in `Confidence`, not
`SupportRegion`, and is a price rather than a bar:

- **It is denominated in millimetres of plane error.** σ_plane is exp(−r/5), so a penalty p
  charges −5·ln(p) mm. The shipped **0.9 charges 0.53 mm**. Req 4.6 ("no higher than a
  restricted fit of *equal* residual") is met by any value in (0, 1), so it never constrained
  the number.
- **The corpus measures 18.37 mm and the ceiling is 0.025** — a 35.5× over-report. Measured
  as the mean over food *samples*, not on the centroid ray Decision 35 uses: the edge-band
  and best-candidate planes are 7.18° apart, so the offset spans 7.96–28.61 mm across one
  food region. Corroborated by the 408 cm³ `SupportPlaneRegressionSliceTests` measures
  between the pre-feature and corrected volumes.
- **The residual channel works against the penalty.** The edge-band plane is a *good* fit to
  the wrong surface, so its residual is **lower** than the restricted fit's (1.95 vs 2.33 mm)
  and exp(−r/5) rewards it. 71 % of the penalty is spent cancelling that; the net confidence
  reduction on the same capture is **3.1 %**. This is Decision 12's argument for keeping the
  penalty separate from the residual, now with numbers — and the reason is the opposite of
  the intuitive one.
- **The bound is one-sided and the value waits on Bucket C.** A fallback on food resting
  directly on the surrounding surface is the *correct* plane, penalty 1, so one constant
  prices a mixture whose weight is Req 4.5's fallback rate. Two owed figures, one gate.
- **Do not price it from the persisted ring median.** Measured and rejected: the ratio of
  fallback ring median to offset at the food is **0.231** on one capture and **2.471** on the
  other — low where the offset is real, high where it is not, for the Decision 33 reason
  (the ring sits 8–25 mm out, where the plate has already ended in five of eight directions).

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

**Most of the guard table has never run** (Decision 34). `admissibility` short-circuits, so
the reason it returns is the FIRST guard to fire, not the only one — which matters when you
are measuring rather than estimating. Evaluate them independently
(`SupportPlaneCorpusMeasurementTests.allRejections`) and the picture is:

| Reason | Fires on the corpus? | Note |
|---|---|---|
| `extent`, `supportFraction`, `sectors` | yes | the only three under the shipped order |
| `ringMedian` | only when evaluated independently | 4 of 6 candidates |
| `ringUnavailable` | no | all bands clear `ringMinSamples` |
| `foodEnvelope` | no | every corpus envelope positive, 7.2–39.6 mm |
| `bandStep` | no | every inner→mid step is a FALL, −0.5…−6.5 mm |
| `visibility` | no | corpus floor 0.246 against a 0.15 bar |
| `escaped` | no | annulus medians −36.6…**+5.7** mm against a 30 mm bar |

So `foodEnvelopeMinMm`, `bandStepMaxMm`, `supportVisibilityMin` and `escapeBandMm` are worse
off than the other `[owed]` constants: nothing in the corpus says their guards do anything at
all. `foodEnvelopeMinMm` is bounded **above** at 25.8 mm — over that it rejects the candidate
the design intends to select — and not below. `escapeBandMm`'s one-sidedness is *correct*:
Req 3.3 rejects a plane lying below its surroundings, which reads a **positive** annulus
median; the −36.6 mm candidate is a plane above them, and `ringMedianMaxMm` is what rejects it.
`ringSupportMarginMin` is worse still — it compares the top two **admissible** candidates and
neither capture produces one, so it cannot run; the gaps real candidates open (0.312 and 0.117)
straddle the shipped 0.15.

And one defect in the guard itself (Decision 30, superseded by Decision 40; still not
fixed in code): `ringStatistics` counts a supporting sector on `|height| ≤ ringBandMm`, so
the count is **blind to sign**. A correct plane whose ring escaped downward (failing
sectors −6.8…−32.6 mm) and a table plane with part of its ring on the plate (failing
sectors +16.6…+19.8 mm) both score 5 of 8. The whole-ring median kept the sign for exactly
this reason (Req 3.1, Decision 22); the per-sector version lost it.

**The replacement rule is stated, and it costs no new millimetre constant (Decision 40).**
A **failing** sector — below `sectorSupportMin` — whose signed inner-band median exceeds
`+ringBandMm` is **crossed**: the support surface is still there and this plane is not on
it. Below `−ringBandMm` it has **escaped**, which is the plate ending (Decision 33) and
*not* grounds for rejection. Reject above `maxCrossedSectors` crossed sectors.

Two things to know before touching this. The bar is `ringBandMm` and it is **inherited,
not fitted** — the plate candidate's highest failing median is −6.794 mm and the table
candidate's lowest is +16.603 mm, so 5 sits ~11.7 mm clear on both sides of a 23.4 mm
window. That only holds because the rule is restricted to *failing* sectors: over **all**
sectors the window is +3.846…+5.974 mm, a tenth as wide, and `ringBandMm` surviving inside
it would be luck. If you are tempted to drop the `sectorSupportMin` gate as redundant, this
is why it is not.

And it is **deliberately not implemented**. `maxCrossedSectors` is bracketed 0…2 by the
corpus (0 crossed on the plate candidate, 3 on the table one) and owed to prerequisites
capture 6; shipping the rule means asserting that count, which Req 3.7 forbids for exactly
these constants. Implementing it later widens `RingStatistics` and the Req 6.4 persisted
fields. The measurement lives in `failingSectorSignSeparatesWhatTheCountCannot`, which runs
it over all six corpus candidates — one reads 6 crossed / 0 escaped, one 0 / 7, one is
genuinely mixed at 2 / 4, so the classification is not degenerate. Note the counter-case
the corpus cannot supply: on a **rimmed** plate a correct plane's ring can reach a rim
genuinely above it, which is captures 3 and 4, not capture 6.

## Tests

`MedataCore/Tests/SupportPlaneTests/SupportRegion*Tests.swift`, with the scene builders
in `SupportRegionScenes.swift`. Scenes are nadir captures authored as HEIGHT MAPS in mm
above the table, because that is how the physical cases are described; the camera looks
straight down, so a gravity-aligned plane has normal (0,0,1) and a point's signed height
above a plane at depth Z is `Z − depth`. The colour grid is an exact 4× multiple of the
depth grid so the mask round trip is lossless — pick a non-multiple and the food mask
dilates by a pixel and every knife-edge scene shifts under you.

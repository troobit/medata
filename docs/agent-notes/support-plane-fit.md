# Support-plane fitting

Two fitters live in `MedataCore/Sources/SupportPlane/`, and they answer different
questions. Read this before changing either.

| File | Question it answers | Reference recorded |
|---|---|---|
| `LiDARPlaneFitter.swift` | largest gravity-aligned plane in four colour-grid bands around the food bbox | `edgeBand` — the table, in a plate scene |
| `SupportRegion.swift` | which gravity-aligned plane the food is actually resting on | `foodSupport` |

`SupportRegion` is the `specs/estimation/support-plane-reference/` feature.
`LiDARPlaneFitter` is not being deleted: it is the fallback, and Req 4.3 requires the plane the
pipeline USES when the fallback fires to be identical to the one this fitter PRODUCES for that
capture. That is an internal consistency, not a freeze on this fitter's constants — both sides
of the identity move together when one of them moves (Decisions 54, 57). An earlier reading of
this line as "byte-identical to what it produces today" is superseded.

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

**Every owed constant has two brackets, not one (Decision 41).** The corpus is one. The
committed scene suites are the other, and they reference owed constants twenty-eight times.
All the references are symbolic — `SupportRegion.ringSupportMin`, never a literal — which
looks like insulation and is not: a test that fixes a synthetic scene and asserts the scene's
measured value against a constant flips as soon as the constant crosses it.
`committedScenesBoundTheOwedConstants` computes the intervals:

| Constant | Suite | Corpus |
|---|---|---|
| `ringSupportMin` | ≤ 0.676 | no ceiling at all |
| `minSupportingSectors` | 6…7 | ≤ 5 |
| `bandStepMaxMm` | 0.024…9.288 mm | no floor at all |
| `supportVisibilityMin` | ≤ 2.667 | ≥ 0.246 |
| `foodEnvelopeMinMm` | −6.758…8.233 mm | 7.154…21.041 mm (Decision 48) — **both are readings at `foodEnvelopePercentile`** (Decision 56) |
| `foodEnvelopePercentile` | floor **0.1** at the shipped bar | ceiling **0.92**, interpolable (Decision 56) |
| `escapeBandMm` | ≥ 14.868 mm | reaches +5.750 mm |
| `maxCrossedSectors` | 0…2 | **2…2** at full pass depth (Decision 48) |
| `maxCandidatePlanes` | ≥ 2 | ≥ 2, no ceiling — *at 2× removal* (Decisions 48, 50) |
| `inlierRemovalMultiple` | none — no scene runs extraction | 1…2.5× (Decision 50) |
| `ransacSuccessProbability` | none — no scene runs extraction | 0.9…unbounded, NOT interpolable (Decision 51) |
| `maxIterationsPerPass` | none — no scene runs extraction | 128…unbounded, never fires (Decision 51) |
| `consensusPolishMaxPasses` | none — no scene runs extraction or the fallback fit | 1…unbounded, **always** fires, interpolable (Decision 54) |
| `gravityAngleMaxRad` | none — no scene runs extraction or the fallback fit | 10°…unbounded, a **floor** not a knob (Decision 55) |
| `LiDARPlaneFitter.maxIterations` | **4…unbounded** — the regression slices, not the scenes (Decision 57) | 8…unbounded, a **floor** not a knob, exact at every value (Decision 57) |

**Every row of the sector part of that table is denominated in `ringSectorCount` *and*
`sectorSupportMin`, both of which are themselves `[owed]` (Decisions 44, 45).** Read
`maxCrossedSectors` 0…2 as "0…2 *at eight sectors with a support bar of 0.5*" — re-cut the same
rings at nine counts and you get eight distinct joint intervals; hold the count and drop the bar
to 0.1 and it is 0…0. See the two sector sections below before setting anything with "sector" in
its name, and fix the count and the bar **together**.

`foodEnvelopeMinMm` and `escapeBandMm` are bound **tighter by the suite than by the corpus**,
so a value defensible against every capture can still turn the suite red.
`minSupportingSectors` is worse than tight — the two brackets do not overlap. A real intended
candidate scores 5 of 8 sectors, and the silent-failure scene the guard exists to reject
scores 5 too, so the suite floors it at 6 and the corpus caps it at 5. Do not resolve that by
retuning `foodAcrossPlateEdge`: it is Decision 30's finding (the unsigned count cannot
separate the two cases), and it resolves when Decision 40's crossed-sector rule replaces the
count. The scene does **not** have to move with it — Decision 43 measured the rule against
these same eight scenes and it clears them all; see below.

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
- **That invariant is the algorithm's, not the corpus's range — Decision 62.** The two
  `captures` slices sit 2.0 mm apart in range (338.9 and 336.9 mm), so every transfer claim
  above was varied by decimation alone. The 2026-08-11 bread pair spans 272.9–399.9 mm and
  is committed as **`rangeCaptures`**, read by the grid-transfer measurements *only* —
  admitting it to `captures` would re-denominate every owed bracket in Decisions 40–57,
  which Decision 61 froze the frame to prevent. At 272.9 mm the plane moves **0.080 mm**
  across the halving and the residue area drifts 1.34 % and **0.72 %**, its later pass an
  order tighter than either corpus capture. `1786439141215`'s "zero residues when halved" is
  **not** a counter-example: `ringBandsAreFeasible` is false at 128 px (bands
  [164, 135, 132] vs 200), so extraction never runs. The invariant's **domain** is ring
  feasibility on both grids; the test used to trap there and now reports it.
- **The two `mmPerPx` bounds are 2.2× apart, and until Decision 62 nothing separated them.**
  The smear envelope bites at `4 × mmPerPx > ringInnerMm`, i.e. **2.0 mm/px** (≈364 mm); the
  ring sample floor is bracketed **3.726…4.405 mm/px** (≈678–802 mm), joint across four
  slices whose native food-sample counts span 6.9×. Read that as a consistency check, not a
  separation: the per-capture brackets are decimation-wide and overlap heavily, and the ring
  is a band around the food *boundary*, so perimeter is still in its sample count. It is
  decimation-limited — integer factors are the only resampler in hand.
  `1786439141215` sits *between* the two at 2.201 mm/px, which is exactly why its fit reads
  clean (support 0.616, ring median −0.011 mm) while its volume is 3× short.
- **`ringMinSamples = 200` is settled; the margin quoted beside it is not.** Decision 29's
  "5.6–7.0× margin" is a reading at the corpus's range *and* footprint: 5.95–6.38× on the
  inside-envelope capture, **2.64–3.00×** on the outside-envelope one. Any headroom figure
  in Decisions 29–57 taken from the two original slices carries the same unstated qualifier.
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
all. `foodEnvelopeMinMm` is bounded **above** at 21.0 mm — over that it rejects the candidate
the design intends to select — and **below at 7.154 mm** (Decision 48, correcting both figures:
25.8 mm is the *table's* envelope on `1785901032716`, and the corpus does contain a plane above
the support surface, whose envelope is positive rather than negative). `escapeBandMm`'s one-sidedness is *correct*:
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

**The suite brackets it at 0…2 as well, and that discharges the collision (Decision 43).**
`crossedSectorRuleIsBracketedByBothConstraintSets` reads the eight committed scenes through
the rule. Five scenes whose assertions require the sector guard to pass carry 0 crossed
sectors; the silent-failure scene carries 3 at +19.95…+19.98 mm. Joint interval 0…2, against
an **empty** 6…5 for `minSupportingSectors` on the same eight scenes. So the Decision 41
collision belongs to the unsigned count, not to the suite — nothing has to move. This is the
only `[owed]` constant whose two sources agree exactly.

Three things that fall out and are worth not re-deriving:

- Nothing in hand narrows 0…2. The test loops every committed scene and both corpus
  candidates at each of 0, 1 and 2 and the verdicts are identical, so the constant is owed
  in the strict sense and *any* choice among the three is asserting.
- `overhangingFood` is the first committed scene to exercise the rule's **escape** half, at
  −20.024 mm. Before this the escape reading fired only on the corpus.
- Neither rimmed-plate scene covers the counter-case above. Both read 8 of 8 supporting with
  no failing sector, because their rims sit outside the inner band the sector median is
  computed over. Do not try to fix that by moving `rimStartPx` — where a real rim sits
  relative to a real food boundary is what captures 3 and 4 are for.

Against Decision 42's 0.338 mm: the rule rejects the table candidate by 3 crossed sectors
against a ceiling of at most 2 — a one-sector margin at the loosest admissible value, three
at the tightest — where `ringMedianMaxMm` clears it by 6.8 % of an inherited bar.

## The sector count is the unit, not a peer (Decision 44)

`ringSectorCount = 8` had never been varied until `sectorCountIsTheUnitOfTheSectorTrio`
re-cut both corpus rings and all eight committed scenes at nine counts. Three things fall
out, and the first invalidates how the other sector brackets read.

| N | plate crossed | table crossed | joint `maxCrossedSectors` | min sector samples | `ringMinSamples` | halved grid |
|---|---|---|---|---|---|---|
| 4 | 0 | 2 | **0…0** | 248 | 100 | feasible |
| 6 | 0 | 3 | 0…1 | 137 | 150 | feasible |
| **8** | **0** | **3** | **0…2** | 102 | 200 | feasible |
| 10 | **1** | 5 | 1…2 | 80 | 250 | feasible |
| 11 | 1 | 6 | 1…2 | 73 | 275 | feasible |
| 12 | 1 | 7 | 1…3 | 66 | 300 | **refused** |
| 16–32 | 1 | 7–18 | 1…4 … 1…9 | 45–21 | 400–800 | refused |

- **The ceiling is Req 5.1's, and it is self-tightening.** `ringMinSamples` *is*
  `ringSectorCount × 25`, so finer arcs raise the floor the ring must clear. The native
  corpus would carry 44 sectors (thinnest band 1120); the 2× halved grid carries **11**
  (thinnest band 292). Above 11 the plane still transfers within a millimetre and the ring
  measure refuses — the same asymmetry Decision 39 refused to paper over with `mmPerPx`.
  So `ringMinSamples` is `[measured]` on an `[owed]` input, which no annotation showed.
- **No floor from the rule.** Decision 40's crossed-sector rule separates the plate-top
  candidate from the table candidate at **every** count 4…32. A coarse cut does not average
  the crossing away inside one sector. The 4…8 bracket's top comes from the *pass* side
  instead: the plane a correct fit must admit reads 0 crossed sectors at 4, 6 and 8 and 1
  from 10 up, because narrow arcs resolve the direction its own ring ran off the plate
  (Decision 33's margin, read a third way).
- **The trade runs backwards, and it undercuts Decision 43.** A *coarser* cut leaves *less*
  freedom in the constant it denominates — joint widths 1, 2, 3 at counts 4, 6, 8. At four
  sectors `maxCrossedSectors` is **determined at 0** by evidence already committed. So
  "0…2 and nothing in hand narrows it" is partly an artefact of the count, which happens to
  be the count where the freedom is widest. Do not read that as an argument for four: it
  asserts `ringSectorCount` to avoid asserting `maxCrossedSectors`, and whether a 90° arc
  resolves Decision 18's straddle is a property of scenes the corpus does not have.

**Practical rule: fix the count before the capture session, not from it.** Capture 6 reads
`maxCrossedSectors` in whatever unit the count fixed, so taking the captures first and
choosing the count afterwards measures nothing. **But not the count alone — see below.**

## The support bar is the population, and 0.5 is a cliff edge (Decision 45)

`sectorSupportMin = 0.5` had never been varied either.
`supportBarSelectsThePopulationTheRuleReads` re-classifies the same two corpus candidates and
the same eight committed scenes at eleven bars. The bar is not a peer of the other two: the
crossed-sector rule reads the sign of sectors that **fail** it, so it chooses the population
Decision 40's inheritance claim is a statement about.

The window below is Decision 40's, recomputed — how far `ringBandMm` may move before either
candidate changes its crossed count, lower edge the plate's highest failing median, upper
edge the table's lowest crossed median.

| `sectorSupportMin` | plate crossed | table crossed | `ringBandMm`'s room | joint `maxCrossedSectors` |
|---|---|---|---|---|
| 0.0 | 0 | **0** | — rule silent | empty |
| 0.1–0.3 | 0 | 2 | −32.564…+16.603 (**49.167 mm**) | 0…0, 0…0, 0…1 |
| 0.4 | 0 | 3 | −9.680…+16.603 (26.283 mm) | 0…2 |
| **0.5** | **0** | **3** | **−6.794…+16.603 (23.397 mm)** | **0…2** |
| 0.6–0.8 | 0 | 4 | +3.711…+5.974 (**2.263 mm**) | 0…2 |
| 0.9–1.0 | 0 | 4 | +3.846…+5.974 (2.128 mm) | 0…2 |

- **The ceiling is a cliff and the shipped value stands on it.** A **10.339×** collapse in one
  notch, 0.5 → 0.6, the largest step in the sweep by a wide margin. Decision 40 supplied the
  criterion without knowing it was one — 2.128 mm is "fitted", 23.397 mm is "inherited" — so
  the cliff picks the ceiling with no new threshold. The bar is bracketed **0…0.5**, and the
  shipped 0.5 is *on* the ceiling rather than inside the bracket. **Do not raise it**: one
  notch up and `ringBandMm` stops being inherited, which is the ground Decision 40 rejected
  the all-sector formulation on.
- **Both edges converge on the bar, from opposite sides.** Noisy sectors that sit *on* the
  correct plane start failing and read near zero, lifting the floor −32.564 → +3.846; sectors
  holding the table plane at a small positive offset fail and become crossed, dropping the
  ceiling +16.603 → +5.974. One constant squeezes the bar from both directions.
- **The floor is the rule's own.** At 0 nothing fails, the population is empty, and a rule with
  nothing to read admits the plane Decision 18 exists to reject. Only 0 is silent at eight
  sectors; at four the floor rises to 0.3.
- **Decision 40's all-sector contrast understates itself.** At 1.0 the reading reproduces
  +3.846…+5.974 exactly — but that is the room the bar has *at its current value*. Read without
  conditioning on where `ringBandMm` sits, the all-sector failing medians **interleave**: the
  table's lowest is +0.426, *below* the plate's highest +3.846, a separation of −3.419 mm. So
  the `sectorSupportMin` gate inside the rule is more load-bearing than Decision 40 recorded.

**This supersedes Decision 44's ordering.** The count's own pass-side bracket is a function of
the bar — counts with a clean pass side and a firing rule are 6, 8, 10, 11 at 0.1–0.2; **all
five** Req 5.1 permits at 0.3; 4, 6, 8, 10 at 0.4; and 4, 6, 8 from 0.5 up. The erosion above
eight sectors that gives 4…8 its top is a consequence of the bar being at 0.5. **Fix the count
and the bar together, before the sitting.**

One positive, and it is the strongest statement the feature has about the rule: over the whole
5 × 11 grid **no cell collides**. Wherever the rule fires, the suite and the corpus admit a
common `maxCrossedSectors`, so Decision 43's agreement is a property of the rule rather than of
the shipped pair.

## The ring radius moves the answer, not just the bracket (Decision 46 — and it was the annulus, Decision 49)

`ringOuterMm = 25` is the third free constant in the sector measure and the one that behaves
differently from the other two. **Read this before changing it, and before trusting any plane
figure in this feature to better than ~2 mm.**

`ringSectorCount` re-cuts a fixed ring. `sectorSupportMin` re-classifies a fixed set of sectors.
Both can only move a *verdict*. `ringOuterMm` moved the **annulus** — the candidate bound was
`2 × ringOuterMm` — so `extractCandidates` ran on a different sample set at every value and the
constant changed **which plane wins**.

**That coupling is gone (Decision 49).** The bound is `SupportRegion.annulusOuterMm = 50`, a
constant of its own at the same value, and it is what carries the movement: pin it and the radius
moves the selected plane **0.000 mm** at every value from 13 to 40 mm on both captures, exactly,
because `extractCandidates` reads the annulus and nothing else. Everything below is a measurement
of the **coupled** sweep — still true of that sweep, and no longer true of the shipped path.
`ringRadiusIsTheRadialUnitOfTheSectorRule` therefore passes the coupled bound explicitly, via
`coupledBoundMm`. Read the annulus section below before changing either constant.

Measured over seventeen radii, re-extracting at each (`ringRadiusIsTheRadialUnitOfTheSectorRule`):

- The **selected plane moves 18.719 mm** at the food on `1785901032716` and 4.162 mm on
  `1785135663727`. Req 5.1's transfer tolerance is **1 mm**. Decisions 44 and 45 both closed
  with "no value moves"; this one does.
- **Bracketed 22…32 mm.** Floor from Req 5.1's 2× grid halving — a narrower ring holds fewer
  samples per band and the halving quarters them, so below 22 mm `ringBandsAreFeasible` refuses
  (halved bands [78, 111, 48] at 13 mm against the 200 floor). This is the *mirror* of
  Decision 44's ceiling of 11 on the count: same halving, other axis.
- **Ceiling from the committed suite, not from geometry.** The scenes place their features at
  fixed pixel radii, so at 35 mm the ring reaches the rim `rimmedPlate` deliberately put outside
  it. Every sector of a scene that must *pass* reads crossed, the suite's floor on
  `maxCrossedSectors` jumps to 8 and its ceiling on `minSupportingSectors` falls to 0. **Widen
  the ring past 32 mm and the committed suite goes red** — that is the scenes moving with the
  constant, exactly as Decision 41 predicted.

~~**Do not interpolate inside the bracket.**~~ **Superseded (Decision 49).** The pass side
alternates at 1 mm steps under the *coupled* bound — 0 crossed sectors at 22, 23, 25, 26, 28, 29,
31 mm and **2** at 24, 27, 30, 32 mm — and reads 0 at every radius once the bound is pinned. The
alternation was the annulus re-selecting the candidates, so the bracket may be interpolated.

**The control that makes that claim safe** (`candidateSelectionIsSeedUnstableAtTheShippedRadius`).
The alternation could have been extraction noise re-rolled by a moving annulus. Held at the
shipped radius with only the RANSAC seed varied over eight draws:

| capture | distinct planes at the food | spread | supporting | crossed |
|---|---|---|---|---|
| `1785135663727` | 349.232 / 350.948 / 351.328 | **2.095 mm** | 5 | 0 |
| `1785901032716` | 356.280 | 0.001 mm | 5 | 3 |

Two things follow, and they pull in opposite directions.

- **The plane is a draw.** 2.095 mm of seed dependence on the capture carrying the corpus's one
  intended-correct fit — twice the figure Decision 35 measures the grid transfer at. This is
  **not** a Req 5.1 failure: the seed is `Fnv1a64.hash(depthBytesMm)`, so identical bytes draw
  identically and replay reproduces device exactly. But every plane-at-the-food figure this
  feature quotes — Decision 35's 0.835 mm, Decision 36's 18.370 mm — is one draw, and their
  error bars are wider than recorded. **Do not read a sub-2 mm difference in these numbers as
  signal.**
- **The verdict is not.** Across eight draws the supporting and crossed counts are single-valued,
  so the brackets in Decisions 40–45 are properties of the captures. Nothing had checked this
  before. It is also what separates the control from the sweep: the seed never moves the crossed
  count, the radius moves it four times in eleven millimetres.

**Consequences for the sitting.** Decision 45's joint (count, bar) pair is a **triple**, and the
radius is fixed **first**, because it selects the candidates the other two are read on.
`maxCrossedSectors` is denominated in all three — the joint bracket reads 0…0, 0…1, 0…2 and 2…2
over the sweep with *no ordering in the radius* — and at 22 and 24 mm the corpus and the suite
admit no common value at all. So Decision 45's collision-free 5 × 11 grid is a slice taken at the
shipped radius, not a property of the rule outright.

## The band count, the divisor nobody marked (Decision 47)

`ringBandCount = 3` was the only one of the seven constants the sector measure reads with **no
provenance marker** — its comment said "structural: inner / mid / outer". It had never been
varied. Decision 46 swept the *numerator* of the inner-band edge
(`ringInnerMm + (ringOuterMm − ringInnerMm) / ringBandCount`) and left the divisor alone.

`theBandCountIsTheRadialDivisorOfTheSectorRule` re-bands both corpus captures and all eight
committed scenes at nine counts, at the shipped radius. **Bracketed 2…3** — two values, the
tightest bracket in the feature, shipped value **on the ceiling**.

- **Floor of 2, reason one: a guard stops existing.** At one band there is no mid band, so
  `admissibility`'s `ring.bandMedianMm.count > 1` test is false and `bandStep` neither fires nor
  reports that it did not — while `bowl` and `rim in the mid band` assert that it does. If you
  ever change this constant, that `count > 1` is the line to look at first.
- **Floor of 2, reason two: the suite collapses.** At one band the inner band *is* the whole
  8…25 mm ring, so the rimmed-plate rims fall inside it, a must-pass scene reads 8 of 8 crossed,
  and both suite intervals go empty (`maxCrossedSectors` 8…2, `minSupportingSectors` 6…0).
- **Ceiling of 3: Req 5.1's halving, third constant off it.** `ringMinSamples` is floored *per
  band* and this constant is how many bands there are, so it bites hardest here — halved counts
  [322, 361, 323] / [313, 292, 299] at three bands, [237, 197, 215, 255] / [258, 264, 204, 280]
  at four. Decision 44 read the same halving as `ringSectorCount ≤ 11`, Decision 46 as
  `ringOuterMm ≥ 22 mm`.
- **It moves no plane.** 0.000 mm at the food on both captures at every count, against Decision
  46's 18.719 mm on the radius. The candidate set is fixed because the annulus is. This is the
  measurement behind Decision 46's claim that the movement belongs to the *annulus* — worth
  knowing before attributing plane movement to any other radial constant.

**Two constants are denominated in it.** `bandStepMaxMm`'s suite ceiling collapses — 13.470,
9.288, 6.755, 5.496, 0.211 mm at 2…6 bands — and the interval **inverts** from seven bands, where
the scene that must fire reads a smaller step than the scene that must pass. A rim spanning a
fixed radial distance stops being a step between *adjacent* bands once the bands are narrower
than the rim. The shipped 6 mm holds at 2, 3 and 4 bands, covering the whole Req 5.1 bracket, so
the pair is coupled but does not collide. And `maxCrossedSectors` reads **1…2 at two bands**
against 0…2 at three — so Decision 43's "nothing in hand narrows 0…2" is a three-band reading,
moved by Decision 43's own recorded blind spot (at two bands the inner band ends at 16.5 mm and a
rimmed-plate rim *does* reach it).

**Caveat, same shape as Decision 46's.** This bracket is a slice at `ringOuterMm = 25`, and both
its ends come from constraints the radius also moves. Unlike the other three sector constants,
though, committed evidence alone brackets it, so it is fixed **before** the capture sitting rather
than at it.

## The pass cap never fires, and the ranking picks the table (Decision 48)

`maxCandidatePlanes = 3` was the last comment in `SupportRegion` saying "structural:" where a
derivation belongs. `thePassCapIsWhatStopsExtractionOnTheCorpus` varies it 1…8.

**It never fires.** Both captures still stop at three passes with the cap at 8, and both stop
**starved** — replay the removal chain past the last pass and 384 and 46 samples remain, against
`minResidueSamples` floors of 488 and 500. `minResidueAreaMm2` is what ends extraction.

Two consequences for anyone touching either constant:

- **Set `minResidueAreaMm2` before `maxCandidatePlanes`.** `1785135663727` leaves 1330.7 mm² —
  78.7 % of the shipped floor — so a floor below 1331 mm² gives it a fourth pass and the cap
  starts truncating. Until then no ceiling here is readable.
- **Decision 38's 3 → 3 is unconditional.** Both counts were *at* the cap, so the native/halved
  agreement could have been the cap truncating both. Lift it and the grids still agree, which is
  the area-invariance reading that decision recorded.

**The floor of 2 is where sequential extraction earns its keep — and the ranking is what makes
it necessary.** The corpus candidates, by pass:

| capture | pass | plane at food | ring median | inner support | crossed | envelope |
|---|---|---|---|---|---|---|
| `1785135663727` | 1 | 351.328 mm | **−0.928** | **0.629** | 0 | 26.628 mm |
| | 2 | 371.282 mm | +6.366 | 0.317 | 6 | 39.601 mm |
| | 3 | 316.216 mm | −32.917 | 0.183 | 0 | 8.958 mm |
| `1785901032716` | 1 | 356.280 mm | +3.039 | **0.480** | 3 | 25.793 mm |
| | 2 | 344.883 mm | **−2.658** | 0.362 | 2 | 21.041 mm |
| | 3 | 335.147 mm | −12.844 | 0.304 | 0 | 7.154 mm |

On `1785901032716` the plane a correct fit must select is **pass 2**, and `fitFoodSupportPlane`'s
ranking picks **pass 1, the table**. Selection there depends entirely on a guard rejecting the
table — the same fact Decision 42 records as `ringMedianMaxMm`'s 0.338 mm.

**So the corpus determines `maxCrossedSectors` at 2.** Every earlier reading takes the bracket's
floor from the highest-*support* candidate on each capture; on this one that is the table. Read
off the plane that must be **admitted** — pass 2, carrying 2 crossed sectors — the floor is 2 and
the ceiling is still 2. Same caveat as Decisions 44–47: a slice at the shipped
`(ringOuterMm, ringSectorCount, sectorSupportMin, ringBandCount)`, all four bracketed.

**And `foodEnvelopeMinMm` has a floor after all.** Decision 34 read the guard's cases as
negative-envelope scenes the corpus lacks. `1785901032716`'s pass 3 sits 9.736 mm **above** the
plate with 6 escaped sectors and its envelope is **positive at 7.154 mm** — a plane above a
surface still has food above *it* wherever the food is taller than the gap. Bracketed
7.154…21.041 mm by the corpus; against Decision 41's suite ceiling of 8.233 mm the joint window
is **1.079 mm**, the narrowest in the feature.

## The candidate bound, and what carried the radius's movement (Decision 49)

`SupportRegion.annulusOuterMm = 50` was `annulusOuterMultiple = 2` — a multiple of `ringOuterMm`,
with no provenance marker, never swept. It could not be swept: with the bound written as a
multiple of the radius there is no radius at which the bound is held still and no bound at which
the radius is. Decisions 46, 47 and 48 all read *through* it.

Pin it and re-run Decision 46's own 13…40 mm radius sweep
(`theCandidateBoundIsAConstantOfItsOwn`):

| sweep | `1785135663727` | `1785901032716` |
|---|---|---|
| radius 13…40 mm, bound coupled (Decision 46) | 4.162 mm | 18.719 mm |
| radius 13…40 mm, bound pinned at 50 mm | **0.000 mm** | **0.000 mm** |
| bound 25…100 mm, ring pinned at 25 mm | 1.978 mm | **18.843 mm** |

The zero is exact, not a tolerance: `extractCandidates` takes the annulus and nothing else, so a
pinned bound hands every radius the same candidates — and the ranking, which *does* move with the
ring, picks the same one anyway. The re-denomination is Decisions 37 and 38's pattern: the value
does not move (`2 × 25` = 50), so every corpus candidate and committed scene is unchanged, and
what changes is that a measure parameter stops resizing the candidate set.

**Bracketed 50…75 mm, by the corpus alone.** `maxCrossedSectors` per bound, read as Decision 48
reads it:

| bound | 25 | 31.25 | 37.5 | 43.75 | **50** | 62.5 | 75 | 100 |
|---|---|---|---|---|---|---|---|---|
| corpus `maxCrossedSectors` | empty | 3…∞ | empty | empty | **2…2** | 2…4 | 2…4 | empty |

Below 50 mm the plane a correct fit must admit is itself crossed (and at 25 mm the bound has
collapsed onto the ring — two candidates, not three); at 100 mm the plate capture's intended
candidate reads 6 crossed as the annulus reaches past the plate. The shipped value is **on the
floor**, and it is the only value in the sweep at which Decision 48's determination at 2 holds.

**The committed suite cannot see this constant.** The scenes never run extraction, so the bound
reaches them only through `visibility` and `escaped` — two of the five guards Decision 34 found
never fire — and every scene keeps its verdict from 25 mm to 100 mm. First constant since
Decision 41 with no second source.

Two riders. `escapeBandMm`'s suite floor is an *annulus* median, so Decision 41's ≥ 14.868 mm is a
reading at the shipped bound: over the sweep the same scenes read 0.131…14.868 mm. And Req 7.6's
latency is denominated here — the annulus holds 10 469 and 12 551 samples at 50 mm against 19 427
and 25 659 at 100 mm.

**Keep the ring inside the bound.** Free while this was a multiple ≥ 1; an invariant now.

## The fallback rate, and the 0.3 mm holding the corpus together (Decision 42)

**Both committed captures fall back under the shipped constants.** That is a per-capture fact
in `SupportPlaneRegressionSliceTests`; in aggregate it is a fallback rate of **1.000**, which
is Req 4.5's own definition of the feature "delivering nothing".

The rate is a readout of the `[owed]` constants and of nothing else, measured by
`fallbackRateIsAFunctionOfTheOwedConstantsAlone`:

| Setting | Rate | Plane selected |
|---|---|---|
| shipped placeholders | 1.000 | none |
| `minSupportingSectors` ≤ 5, all else shipped | 0.500 | `1785135663727`'s plate top |
| every owed bar at its loosest | 0.000 | both captures, nearest Req 3.1's zero |

Three things follow, and the third is the one to remember.

- **Do not set Req 4.5's threshold from this corpus.** Any value is satisfied or violated by the
  placeholders alone; the captures never change. That is Req 3.7's circularity arriving at
  Req 4.5. The denominator problem (`prerequisites.md`) is the *second* blocker, not the first.
- **The geometry is sound.** At the loosest owed setting each capture selects the candidate whose
  inner band is nearest zero — −0.521 mm and −1.023 mm — so the remaining work really is
  constants. Note the honest limit: on `1785901032716` that plane is admitted only at support
  0.362 over 2 of 8 sectors, because its plate ends inside the ring in five of eight directions
  (Decision 33). The 0.000 is a bound, not a proposal.
- **`ringMedianMaxMm` is the only thing rejecting the wrong planes there, and it clears the
  closest by 0.338 mm.** The table candidate on `1785901032716` — Decision 40's crossed-sector
  case, three sectors at +16.6…+19.8 mm — reads 5.338 mm on its inner band against a 5 mm bar.
  That bar is `[inherited]` from `ringBandMm` and Decision 22 gave it the Req 3.2 signed-admission
  job, not this one. **Do not widen it**, and do not read the margin as comfort: it is the
  strongest argument for Decision 40's crossed-sector rule that does not need capture 6, because
  the rule separates the same two candidates by 11.7 mm on each side instead of by a third of a
  millimetre.

Practical consequence for task 27: deploy today and a device capture of this kind records
`.edgeBand`. The reference check fails for constant reasons, not implementation ones.

## Tests

`MedataCore/Tests/SupportPlaneTests/SupportRegion*Tests.swift`, with the scene builders
in `SupportRegionScenes.swift`. Scenes are nadir captures authored as HEIGHT MAPS in mm
above the table, because that is how the physical cases are described; the camera looks
straight down, so a gravity-aligned plane has normal (0,0,1) and a point's signed height
above a plane at depth Z is `Z − depth`. The colour grid is an exact 4× multiple of the
depth grid so the mask round trip is lossless — pick a non-multiple and the food mask
dilates by a pixel and every knife-edge scene shifts under you.

## The removal band, and what one pass hands the next (Decision 50)

`SupportRegion.inlierRemovalMultiple = 2` is the **fourth** constant that decides which planes
*compete*, and the only one that acts *between* passes. The other three each own a different part
of the candidate set:

| constant | what it decides |
|---|---|
| `annulusOuterMm` | the sample set extraction draws from |
| `maxCandidatePlanes` | how many times it may draw |
| `ringOuterMm` | how a set already chosen is re-ringed (bracket-only since Decision 49) |
| `inlierRemovalMultiple` | what each draw **leaves** for the next |

It was the last constant in the file carrying a claim in place of a provenance marker, and the
claim was **false**. "A 1× shell seeds near-duplicate planes on the next pass": read in the
removal's own units — the largest gap between two planes' signed heights over the annulus, against
one `inlierBandMm` — **0 of 33** adjacent pass pairs across eight multiples is a near-duplicate.
The closest at 1× diverges by **30.807 mm**; the closest anywhere by **23.973 mm**, nearly five
bands. CC-RANSAC is why: a pass keeps the largest *connected* component, so what a 1× shell leaves
behind is a thin ring around a surface already taken and it does not form one.

**It does not move the plane** — 0.000 mm at the food on both captures at every multiple, exactly.
Removal happens *after* a pass, so pass 1 is drawn from an annulus this constant never touched, and
the ranking picks pass 1 on both captures throughout. Bracket-only, like the count, the bar, the
band count and the radius.

**Bracketed 1…2.5×** (`theRemovalBandIsWhatOnePassHandsTheNext`), with the shipped 2× strictly
inside — the first owed constant in this feature that is not on an edge:

| multiple | 1× | 1.25× | 1.5× | **2×** | 2.5× | 3× | 4× | 6× |
|---|---|---|---|---|---|---|---|---|
| natural depth (plate / table capture) | 7 / 5 | 5 / 3 | 4 / 3 | **3 / 3** | 2 / 3 | 2 / 2 | 2 / 2 | 2 / 1 |
| intended ring median, `1785901032716` | −2.203 | −2.309 | −2.377 | **−2.658** | −3.011 | +3.039 | +3.039 | +3.039 |
| corpus `maxCrossedSectors` | 2…2 | 2…2 | 2…2 | **2…2** | 2…2 | 3…∞ | 3…∞ | 3…∞ |

The **ceiling** is where a shell wide enough to take the table takes the plate with it: at 3× the
nearest-to-zero candidate *is* the table, carrying 3 crossed sectors of its own. The **floor of 1**
is structural, not measured — below it a pass leaves samples it selected within `inlierBandMm` and
the next pass can re-find the same plane. Readings are monotone, so unlike Decision 46's radius the
bracket may be interpolated.

**Fix it before `minResidueAreaMm2` and `maxCandidatePlanes`.** Decision 48's "the cap never fires"
is a reading at 2×: below it extraction runs deeper than the cap allows and the cap truncates. 2×
is the smallest multiple at which it does not. Req 7.6's latency follows the same chain, since the
RANSAC bound is `maxIterationsPerPass` times the passes actually run.

**The committed suite cannot express a reading on it at all** — structurally, not by measurement.
Decision 49's bound at least reached the scenes through `visibility` and `escaped`; no scene runs
extraction, so there is nothing to read. The only owed constant of which that is true.

One positive: `maxCrossedSectors` reads **2…2 at every multiple the bracket admits**, so unlike the
candidate bound this constant does not denominate Decision 48's determination.

## The iteration budget, and the end of the clamp that binds (Decision 51)

`requiredIterations` is `min(maxIterationsPerPass, log(1 − p) / log(1 − w³))`. Two constants,
one mechanism, and until this decision the shipped code never reported which end was doing the
work. The cap carried a `[derived]` marker and a paragraph of argument; the target carried **no
provenance marker at all** — the last constant in `SupportRegion` of which that was true, after
Decision 47's band count and Decision 48's pass cap.

**The target always binds; the cap never fires.** Per pass, per capture:

| Capture | pass 1 | pass 2 | pass 3 | cap |
|---|---|---|---|---|
| `1785135663727` | 72 (w = 0.402) | 11 (w = 0.718) | 250 (w = 0.263) | 2048 |
| `1785901032716` | 12 (w = 0.698) | 41 (w = 0.477) | 5 (w = 0.872) | 2048 |

The largest draw the corpus ever needs is **250**, so the cap truncates nothing at or above 256.

**The cap's stated derivation is refuted by its own number.** It priced pass 1 at a ~6 % inlier
ratio. Measured it is **0.402 and 0.698**, six to twelve times that, and at those ratios the 0.99
target is met in 69 and 12 iterations. The budget is sufficient because the dominant plane is
*easy*, not because extraction is sequential.

**The target moves the answer** — only `annulusOuterMm` otherwise does. Swept 0.5…0.99999 the
selected plane at the food moves **3.704 mm** on `1785135663727`: 351.620, 349.473, 353.130,
351.328, 349.426, 349.426 mm. Those **wander rather than climb**, so like Decision 46's radius and
unlike Decision 50's removal band, **do not interpolate inside the bracket**.

**This is what Decision 46's ~2 mm caveat is denominated in.** Every plane figure Decisions 40–50
quote carries it. Re-run that decision's eight-seed control against each end of the clamp:

| Held at | 0.99 / 2048 | tightened |
|---|---|---|
| the **cap** (64 → 8192) | 2.095 mm | 2.095 mm — buys nothing |
| the **target** (0.99 → 0.99999) | 2.095 mm | **0.194 mm** — a 10.8× fall, under the Req 5.1 bar |

So the draw dependence is neither a property of the captures nor a price of the cap. It is this
constant, and it is **removable**.

**Brackets.** The cap is **128…unbounded** from below: at 64 the sector verdict on
`1785135663727` flips from 5 supporting / 0 crossed to 3 / 2 — the guard every bracket in
Decisions 40–50 is read from — and at 32 the plane moves 1.9 mm, while at 128 and above it is the
shipped plane to 0.000 mm. Its ceiling is open and stays open: above the largest required draw
there is nothing to distinguish, so Req 7.6's worst-case latency sets it, and the low-inlier-ratio
scene where it *would* fire is exactly the scene this corpus lacks. The target is
**0.9…unbounded**: `1785901032716` is draw-stable at 0.001 mm from 0.9 up and jumps to 2.376 mm at
0.5. Tightening it is paid for out of the cap's 8× headroom, so the two do not compete.

**It is the only owed constant the committed corpus alone can set.** Every other one waits on the
capture sitting or on model-production Bucket C. This one does not — but choosing a value inside
the bracket is still asserting, which Req 3.7 forbids.

## The inlier band, and where four `[inherited]` markers terminate (Decision 52)

Decision 51 closed the file's provenance audit with "every constant in `SupportRegion` now carries
a provenance marker". That was true and it was not sufficient, and the reason is worth keeping:
**an `[inherited]` marker is a pointer, and it is only as good as the constant it points at.**

Four markers in `SupportRegion` resolve, directly or in one hop, to `LiDARPlaneFitter.inlierBandMm`:

| Marker | Reads |
|---|---|
| `ringBandMm` | `[inherited] LiDARPlaneFitter.inlierBandMm = 5` |
| `ringMedianMaxMm` | `[inherited] ringBandMm` |
| `inlierRemovalMultiple` | a multiple **of** `inlierBandMm` |
| `supportVisibility` | a count **within** `inlierBandMm` |

In `LiDARPlaneFitter.swift` it was a bare `static let inlierBandMm: Float = 5` with no comment, in a
block headed "Tunable parameters per design §6.2". **One file outside the file being audited.** When
sweeping this feature's provenance, follow `[inherited]` out of the module — the audit's scope was
the defect.

**It is the fifth constant that decides which planes compete, and the most upstream.**
`annulusOuterMm` fixes the set extraction draws from, `maxCandidatePlanes` how many times it may
draw, `inlierRemovalMultiple` what each draw leaves, `ringOuterMm` re-rings a set already chosen.
This one decides **what an inlier is**, in three places at once: the RANSAC inlier test, the
consensus polish's re-selection, and the removal band the multiple is denominated in. So it moves
the plane further than anything else swept — **18.132 mm** and **19.389 mm** at the food over
1…12.5 mm, the first owed constant to move *both* captures past Req 5.1's 1 mm. Readings **wander**
rather than climb (support 0.312 at 3 mm, 0.281 at 4 mm), because extraction re-runs and the
candidate is re-selected: **do not interpolate**.

**The corpus interval is empty at the shipped bars.** Three constraints, all read on the plane a
correct fit must select (Decision 48's identification — nearest Req 3.1's zero, not the ranking's
winner):

| Constraint | Admits |
|---|---|
| `ringMedian` — a bar that *is* the band | ≥ 4 mm (fails at 3 mm and below on both captures) |
| `maxCrossedSectors` ≤ 2 | ≤ 5 mm on `1785901032716` |
| `ringSupportMin` ≥ 0.6 | ≥ 10 mm on `1785901032716` |

The last two are **disjoint**. The interval is non-empty only once `ringSupportMin` falls to
**0.362** or below, and there it is exactly the shipped 5 mm; below ~0.28 it widens to {4, 5} mm.
So the corpus determines the band *conditionally*, and hands `ringSupportMin` its **first ceiling**
in the same reading — Decision 29 recorded that it had none, and Decision 41's suite ceiling of
0.676 was the only bound in existence. The band, the support bar and the crossed count are **one
joint set**, the first three-way one in the feature.

**design.md's ε/h table is superseded on its load-bearing row.** It priced "plate above table" at
h = 26 mm — which is pipeline Decision 6's plane *error at the food*, not the step between the two
competing surfaces over the annulus. Measured from the shipped run:

| Capture | Competing surfaces | h | shipped ε/h |
|---|---|---|---|
| `1785901032716` | table +3.039 mm / plate −2.658 mm | **11.706 mm** | **0.427** |
| `1785135663727` | closest pair | 19.464 mm | 0.257 |

0.427 is outside Gallo et al.'s 0.25…0.35 and in the same band as the two rows that table already
marked outside. **So the straddler is real**: at the *shipped* band the plate candidate's largest
connected component holds **22.1 %** of its members within one band of the surface below it. That
settles design.md's one explicitly deferred question ("task 26 settles it by measurement; neither
reading may be assumed") for the first of its two readings.

**The 15° gravity cone is not an invariant of the candidate set.** `SupportRegion.extractCandidates`
gates gravity on the RANSAC hypothesis and on every consensus-polish iteration — but **not on the
first refinement between them**, and a polish that reaches its fixed point immediately leaves that
plane standing. The committed corpus contains a candidate at **20.512°** (25.422° at a 4 mm band).
It is rejected downstream on `extent` and `supportFraction`, so nothing observable changes today.
Two consequences: any argument stated in terms of the cone is about a bound the candidate set does
not respect, and **repairing the gate removes a candidate and therefore moves the answer** — which
is why it is recorded at the call site rather than fixed.

**The committed scenes bound no tolerance, anywhere.** `SPRScene.makeDepth` adds ±0.3 mm of
synthetic noise, an order of magnitude below the smallest band swept, so every scene sample sits on
its own surface and any tolerance from 1 to 12.5 mm classifies it identically: `maxCrossedSectors`
0…2 and `minSupportingSectors` 6…7 at *every* band, with no scene's `supportFraction` or
`ringMedian` verdict broken. This is the third distinct kind of suite silence — Decision 49's was
measured, Decision 50's was structural (no scene runs extraction), this one is a property of the
scenes' noise model. **The suite validates every guard's logic and no tolerance in any of them**;
do not read a tolerance bracket off it.

## The confidence bar, and why it is not a bracket at all (Decision 53)

There is one step further up the same file than Decision 52 took it.
`LiDARPlaneFitter.confidenceThreshold` — τ_conf — decides what a **sample** is: `SupportRegion.prepare`
drops any pixel below it before back-projection, so every sample the inlier test is ever applied to
has already passed it. It is the **sixth** constant that decides which planes compete and the most
upstream of the six.

**Its domain is three states, not a range. This is the thing to remember.** ARKit reports three
confidence *levels*, scaled to bytes `{0, 127, 255}`, and all three committed slices carry exactly
those values and nothing else. So over the whole of [0, 1] there are three behaviours:

| State | τ_conf | What survives |
|---|---|---|
| accept-all | ≤ 0 | LOW, MEDIUM, HIGH |
| MEDIUM+ | 0 < τ ≤ 127/255 = **0.498** | MEDIUM, HIGH — the shipped 0.40 is here, 0.098 clear of the boundary |
| HIGH-only | > 0.498 | HIGH — `HeightFieldEstimator.tauConfidence = 0.66` is here |

Twelve swept values collapse to three sample sets. **Do not treat this constant as tunable between
0.40 and 0.49** — there is nothing there. It is also the only owed constant whose domain the corpus
enumerates *exhaustively*; every other bracket in Decisions 29-52 is an interval with unread values
inside it, which is why they all carry an interpolation rider and this one cannot.

**The sweep needs no restatement of shipped code, and that trick is reusable.** Every other sweep in
`SupportPlaneCorpusMeasurementTests` reimplements a stage with the constant as an argument
(`ccRansac`, the pass chain, `sectorSigns`, `sectorIndex`) and pins the copy against the shipped
function. For τ_conf, rewrite the *confidence map* instead — each byte to 255 if it clears the swept
bar, else 0 — and the shipped 0.40 then admits exactly the set the swept bar admits. `prepare`,
`ringSamples`, `extractCandidates` and `admissibility` all run unmodified. The depth bytes are
untouched, so `Fnv1a64.hash(depthBytesMm)` is identical and the **RANSAC seed is held** across the
sweep (the draw is not — `uniformInt(n)` reads a residue size that moves).

**It moves the plane and the pass count.** 2.098 mm at the food on `1785135663727` (349.229 /
349.325 / 351.328), past Req 5.1's 1 mm; 0.038 mm on the other. Extraction runs three passes at
MEDIUM+ and **two** at HIGH-only on `1785135663727`, because a 12.7 % smaller annulus starves the
residue floor a pass early — so `minResidueAreaMm2`, `maxCandidatePlanes` and Req 7.6's latency are
denominated here too.

**Both of Decision 52's determinations are readings in the MEDIUM+ state:**

| State | `ringSupportMin` corpus ceiling | Inlier band the corpus admits |
|---|---|---|
| accept-all | 0.362 | 5 mm |
| MEDIUM+ (shipped) | 0.362 | 5 mm |
| HIGH-only | **0.497** | **6 mm** |

So Decision 52's three-way joint set is **four-way**, with τ_conf at its head. Accept-all reads the
same as shipped because the capture that binds both quantities, `1785901032716`, has only 36 LOW
pixels.

**The corpus cannot settle it, in either direction.** The shipped 0.40 exists because
`lidar-plane-fit-matte-table-confidence` had HIGH-only starving the fit to `noLidarPoints`. At
HIGH-only on this corpus **nothing starves** — every ring band clears `ringMinSamples`, extraction
still yields candidates, the fitter's own band scan still returns a plane — and the intended
candidate *improves* on both captures (support 0.629 → 0.690 and supporting sectors 5 → 6; support
0.362 → 0.379, supporting 2 → 3). The corpus mildly argues against the shipped state while being
unable to justify the alternative, because the matte-table scene is not in it. **A matte-surface
capture now bounds two constants** (this and `ringSupportMin`), and the capture session should record
the ARKit confidence *histogram* per surface — the level mix per surface material is the measurement.

The floor *is* measured: admitting LOW moves the plane 2.003 mm on `1785135663727` (22.7 % of its grid
is LOW) and pushes the intended inner-band median from −0.521 to −1.454 mm. Only that capture can say
so; the other's 36 LOW pixels (0.07 %) change nothing. One-capture footing, as with `fallbackPenalty`.

**τ_conf is two constants under one name, straddling the boundary.** The support plane's bar is 0.40
and the food height field's is `HeightFieldEstimator.tauConfidence = 0.66`, on the far side of MEDIUM.
So the plane is fitted to MEDIUM+HIGH samples while the volume above it is integrated over HIGH alone.
Deliberately not aligned — closing it changes which samples exist and moves the volume — and pinned at
both call sites. Practical consequence: **any "0 % low-confidence" claim has to name which bar it is
read at.** Decision 31's "43.2 % against 0.0 % on both admitted captures" is the plane's bar; at the
height field's the three shares are 60.3 %, 2.7 % and 1.9 %.

**Decision 31's exclusion of `1785054950406` stands on a different ground than it records.** Its
second ground (the surviving food's envelope is negative, so no mound to anchor) is circular: at
τ_conf = 0 the same slice reads **+58.353 mm**. The mound is in the data, and τ_conf removes it. Its
third ground reverses — the spurious separable count needs 4 supporting sectors, and the capture reads
2 at accept-all, 3 at shipped, 4 only at HIGH-only. What actually disqualifies it: admitting the LOW
samples the mound is made of takes the intended candidate's ring median from **−0.018 mm to
−4.589 mm**. Its mound and its usable support surface cannot both be present at one setting, so no
threshold recovers it and capture 2 still has to be taken.

**One positive.** `maxCrossedSectors` reads 2 at the shipped band in all three states — the only
member of the joint set that survives τ_conf directly.

## The polish cap always binds, and its depth is not what the loop buys (Decision 54)

`LiDARPlaneFitter.consensusPolishMaxPasses = 3` is the **seventh** constant that decides
which planes compete, the third that can *add* one, and the only one **both** fitters read —
`SupportRegion.extractCandidates` polishes every candidate with it, `LiDARPlaneFitter.fitOutcome`
polishes its single winner with the same number.

Unlike Decisions 47, 48 and 51's unmarked constants it *has* a derivation, written in the
source and in `estimation-runtime-consistency.md`: "the loop usually exits earlier because the
inlier set reaches a fixed point". **It is false on this corpus, on both legs.**

| At the shipped 3 | stopped by the cap | reached the fixed point | stopped by the gate |
|---|---|---|---|
| extraction (6 passes) | **4** | 1 | 1 |
| the fallback fit (2 captures) | **2** | 0 | 0 |

Swept to 64, the depth the corpus actually needs is **17** in extraction (pass 1 of
`1785135663727`) and **11** in the fallback. So the plane both paths ship is a truncated
iterate of the polish map, not its fixed point. This is the exact mirror of Decision 51's
`maxIterationsPerPass`, which never fires anywhere: two caps, two `[derived]` arguments,
opposite failures.

**The depth is not what removes the seed dependence the loop was added for.** Decision 46's
eight-seed control, re-run at three depths:

| Capture | no polish | shipped 3 | converged 64 |
|---|---|---|---|
| `1785135663727` | 2.123 mm | **2.095 mm** | 2.067 mm |
| `1785901032716` | 0.096 mm | 0.001 mm | 0.000 mm |

**2.9 %** on the capture carrying the corpus's only intended-correct fit, for running the loop
to convergence. It works completely on the other one — which was nearly seed-stable to begin
with. What *does* remove it is `ransacSuccessProbability` (2.095 → **0.194 mm**, Decision 51).
The reason is visible in the rolls: the surviving spread is three distinct planes with the
candidate count itself varying between 2 and 3, so the seeds disagree about **which candidate
wins**. The polish refines a plane; it does not reorder a set. Do not cite the polish as the
answer to plane jitter.

**It moves both legs, and the fallback further.** Over 0…64 the promoted plane moves 0.490 and
0.106 mm at the food — inside Req 5.1's 1 mm. The **fallback** plane moves 0.158 and
**1.719 mm** (357.506 unpolished → 359.096 shipped → 359.225 converged on `1785901032716`), so
the shipped cap sits 1.590 mm above the unpolished plane and 0.129 mm short of its own fixed
point. Req 4.3 holds at every value — one constant moves both legs — but the plane it names is
what Decision 36 prices `fallbackPenalty` against and what feeds `lidarMmPerPx = |d| / f` on
the legacy path. Decision 36's 18.37 mm survives (its capture's fallback moves 0.158 mm) and is
a reading here. **First owed constant measured on the fallback leg.**

**And it changes the candidate SET.** `1785135663727` yields **two** candidates at 0–1 passes
and **three** from 2 up: a shallower polish leaves a different plane, hence a different removal
shell, hence a residue that stops at `minResidueAreaMm2` a pass early. Persisted
`planeCandidateCount` (Req 6.1) is denominated here — its third denominator after Decision 38's
residue floor and Decision 53's confidence bar.

**Decision 52's unenforced gravity cone is worse than "absent" — it is inverted.**
`1785135663727`'s third pass records `gravity` at **0 applied iterations at every depth from 2
up**: the gate fires on the first re-selection and `break`s, which keeps the previous plane —
the **ungated** refinement before the loop, itself outside the cone. The documented
conservative fallback is precisely what preserves the plane the cone exists to exclude. The
tilt left standing moves with the cap: 26.573° at 2 passes, Decision 52's **20.512°** at the
shipped 3, 18.771° at 4–8, 18.609° from 16. At 0 and 1 passes nothing is outside the cone,
because that candidate does not exist yet. Still not repaired: removing it moves the answer.

**Bracketed 1…unbounded, interpolable, and the corpus points above the shipped value.** The
floor of 1 is the corpus's — at 0 the candidate set is short a plane and `maxCrossedSectors`
reads **2…3** against the 2…2 Decision 48 determined, so the polish is part of what makes that
determination tight; from 1 up it is 2…2 at every depth. There is no ceiling, and the
constant's own derivation is met only at 17. What stops that being a proposal is **Req 7.6**:
this is the innermost loop in extraction — a full re-selection over the residue, a
connected-component labelling and an SVD per iteration — and 17 quintuples it on the path that
produced the 32 GB allocation failure. Readings are monotone (each depth is one more iteration
of the same map), so unlike Decisions 46, 51 and 52 the bracket **may** be interpolated. The
committed suite is silent for Decision 50's structural reason: no scene runs extraction, and
none runs the fallback fit either.

## The gravity cone bounds nothing, and tightening it makes that worse (Decision 55)

`LiDARPlaneFitter.gravityAngleMaxRad = 15°` is read at **four** gates — more than any other
constant here — and enforced at two. `SupportRegion.ccRansac` and `LiDARPlaneFitter.ransac`
test every hypothesis against it and reject; `extractCandidates` and `fitOutcome` test every
consensus re-selection and **`break`**, which keeps the plane the *previous* iteration
produced. The refinement between the two stages is not gated at all.

Decisions 52 and 54 described that mechanism. This one swept the bar, and the mechanism turns
out not to be a property of the shipped value:

| cone | 1° | 2° | 3° | 5° | 8° | 10–20° | 25° | 30–45° | 90° |
|---|---|---|---|---|---|---|---|---|---|
| candidates outside their own cone | **4/4** | 5/6 | 1/5 | 3/6 | **0/6** | 1/6 | 0/6 | 0/6 | 0/6 |
| worst tilt standing | 3.643° | **18.955°** | 9.167° | 10.519° | 7.892° | 20.512° | 24.223° | 25.500° | 79.809° |

- **At a 1° cone every candidate is outside 1°**, each recorded as `gravity` at 0 applied
  iterations. The gate admits only hypotheses within 1° and the set it produces is entirely
  outside it. In units of the bar the violation is **9.5×** at 2° and 1.37× at the shipped 15°.
- **It is not monotone.** 8° leaves nothing outside itself; 15° leaves a candidate at 20.512°.
  Do not pick a value by asking how far outside it the set reaches — that quantity does not
  order with the constant.

**It is a floor, not a knob.** The selected plane spans 3.758 mm and 14.584 mm at the food
over 1…90°, and **every millimetre is below 10°**. From 10° to 90° — the gate fully off at the
top, since both fitters orient onto gravity's half-space before measuring — the plane is
unchanged to **0.000 mm** on both captures. Unlike `inlierBandMm` and
`ransacSuccessProbability`, which wander across their range, this one either admits the
hypothesis that produces the correct fit or it does not.

**The floor's derivation is the margin, and it is the number to remember.** The corpus's one
intended-correct fit is the **plate top at 8.309°**, from a hypothesis at **8.900°**, so the
shipped 15° carries **6.100°** of margin. Its own table candidate in the same capture is at
2.030°: the surface this feature exists to find sits **6.3° off the surface the fallback leg
finds**, in the same frame. That is why the two legs disagree about how much room the guard
needs — the fallback fits the table at 1.742° and 0.579° and would be comfortable at 5°.

Consequences worth not re-deriving:

- **The fallback leg barely moves** — 0.226 mm and 0.074 mm over the whole sweep, inside
  Req 5.1 even at a 1° cone, against 14.584 mm on the promoted leg. This is the **exact
  reverse of Decision 54**, where the fallback moved further. Two constants both fitters read,
  opposite sensitivities.
- **Below 8° the joint `maxCrossedSectors` interval is empty**, and at 8° the plane still
  moves 1.802 mm (353.130 mm, support 0.536, 2 crossed against 351.328 / 0.629 / 0). 10° is
  the first swept value that reproduces the shipped answer exactly.
- **No ceiling anywhere.** At 90° the corpus reads the same planes and the same 2…2. The one
  thing the cone buys above 45° is excluding `1785135663727`'s **79.809°** third-pass
  candidate 1305.187 mm away — which `minAcceptedExtentMm` rejects anyway at 35.370 mm. On
  this corpus the guard could be deleted without changing an answer; the wall-and-floor scenes
  it exists for are not in it.
- **Req 7.6 is denominated here in the *tightening* direction**, which no other owed constant
  is. The fallback's fixed 256-iteration budget loses 137 and 10 draws to the gate at 15°,
  173 and 29 at 8°, 252 and 207 at 1°; extraction pays again because `requiredIterations`
  cannot stop adaptively until a good component exists (pass 1 of `1785135663727`: 72 draws
  at 15° and above, 86 at 8°, **169** at 1°).
- **Do not re-derive it from `CaptureFlowModel`'s 15° oblique shutter gate.** That is a camera
  **pose** tolerance (`abs(θ − 25) ≤ 15`); this is the angle between a fitted plane's normal
  and gravity. The two 15s are a coincidence.
- The 6.3° disagreement between the plate top and its own table is **unexplained** — it could
  be the plate, the fit, or the recorded gravity, and two captures cannot separate them.

## The envelope percentile is a denominator, and it re-denominates the tightest bracket here (Decision 56)

`SupportRegion.foodEnvelopePercentile = 0.90` was the last unswept constant on the promoted leg,
and it survived eleven passes because of its **marker**. It reads `[derived] Decision 22`, and
that derivation is real — it is why the guard is in millimetres rather than a sample-count
fraction, and why `foodAboveFractionMax` was retired. It derives the guard's **kind**. Nothing
derives the **0.90**. That is a third kind of provenance failure, after the missing markers of
Decisions 47/48/51 and Decision 52's four markers pointing at an underived constant: a marker
that reads correctly and covers a different quantity.

**It is the denominator of `foodEnvelopeMinMm`.** The two are one measure — a bar in millimetres
and the statistic compared against it — so every bound quoted on that constant is a reading at
this one. The corpus ceiling runs **−19.415 mm at p = 0 to +26.038 mm at p = 1**: 45.453 mm of
movement, more than three times the width of the bracket it caps.

**Bracketed 0.1…0.92, and interpolable.** A percentile of a fixed multiset cannot fall as the
percentile rises, so the readings are monotone *by construction*, not by measurement. (Asserted
anyway: `SupportRegion.percentile` special-cases `p == 0.5` and averages the two middle samples
where every other value takes a nearest-rank index, so the sweep crosses a code branch.)

- **Floor 0.1** — the committed suite's, at the **shipped** `foodEnvelopeMinMm = 0`, so it
  involves no owed value at all. `overhangingFood`'s test requires the envelope guard to pass and
  its envelope goes negative below 0.1: −2.579 mm at 0.05, −4.968 at 0.02, −6.440 at 0. A
  percentile that low reads the overhanging lobe rather than the loaf.
- **Ceiling 0.92** — where the corpus floor rises past the suite ceiling: 8.171 vs 8.245 mm at
  0.92, 9.366 vs 8.264 at 0.95. Decision 41's collision prediction on a fourth constant.

**Decision 48's 1.079 mm joint window — "the narrowest in the feature" — is a slice at two
constants that decision did not name.** The first is this percentile: the same window reads
**8.779 mm at p = 0.5**, 8.1× wider, and 0.075 mm at 0.92. The second is `ringSupportMin`,
because a candidate floors the envelope bar only if the envelope guard is what has to reject it
(Decision 34's own rule for the suite, read on the corpus). The two above-surface candidates
carry **0.183** and **0.304** inner-band support, both inside `ringSupportMin`'s (0, 0.362]
bracket, so at the shipped percentile there are three live regimes:

| `ringSupportMin` | corpus floor | joint window at p = 0.90 |
|---|---|---|
| ≤ 0.183 | 8.958 mm | **EMPTY** by 0.725 mm |
| 0.183…0.304 | 7.154 mm (Decision 48's) | 1.079 mm |
| > 0.304 | none — Decision 34's reading restored | 14.991 mm |

**So the shipped 0.90 is admissible only where `ringSupportMin` exceeds 0.183.** Set the
percentile and the support bar before the envelope bar.

**It cannot move the candidate set** — extraction never reads it — which makes it the only
constant swept since Decision 46 that cannot reorder or re-roll the candidates. Its one route to
the answer is `admissibility`, and there it is live: 4 of 6 corpus candidates and 1 of 8
committed scenes cross the shipped `foodEnvelopeMinMm = 0` over the sweep. Whether a crossing
reaches the selected plane depends on bars that are themselves owed.

**`lowerEdgeBandMm` is deleted, not measured.** `LiDARPlaneFitter.lowerEdgeBandMm = 30` had
exactly one occurrence in the repository — its own declaration. The four-edge band scan added by
`lidar-plane-fit-degenerate-on-clean-capture` on 2026-06-16 sizes each band from
`bbox.heightPx` / `bbox.widthPx` and never reads a millimetre bound, so the constant has not
defined the fallback's region since that date, and Decision 36 prices the fallback over a region
it does not set. `collectCandidatePoints` is the region's only definition;
`specs/estimation/pipeline/design.md` §6.2 still described it in the constant's terms and is
marked superseded.

## The fallback's iteration budget, and the search that never finishes (Decision 57)

`LiDARPlaneFitter.maxIterations = 256` is read in `ransac` and nowhere else, which makes it the
**only constant task 26 has measured that one leg reads alone**. The loop is a bare
`for _ in 0..<maxIterations` — no adaptive stopping, no connected component, no early exit.

**Its derivation exists, is correct, and argues against it.** `SupportRegion.ccRansac` and
`SupportRegionCandidateTests` both carry "maxIterations = 256 was sized to find the DOMINANT
plane and must not be inherited on faith — P(clean triple) is 98 % at w = 0.25 but 3 % at
w = 0.05". The promoted leg acted on that and built `requiredIterations`; the fallback leg still
runs on the number the argument rejects. The reasoning is filed on the leg that abandoned the
constant, so it is unreachable from the constant. A fourth kind of provenance failure, after the
missing markers of Decisions 47/48/51, Decision 52's markers pointing at an underived constant,
and Decision 56's marker covering a different quantity.

**The search never converges, so no value is a convergence point.** RANSAC's running best is
monotone in the draws and nothing here stops it:

| capture | points | improvements over 1024 draws |
|---|---|---|
| `1785135663727` | 1,077,427 | #1, #3, #5, #46, #60, #74, **#76**, #689 |
| `1785901032716` | 1,475,580 | #1, #12, #20, **#210**, #1005 |

The bold entry is where a budget of 256 stops. Doubling it finds a better hypothesis on both.
Exact mirror of `SupportRegion.maxIterationsPerPass`, which never binds at all (Decision 51):
one cap cannot fire, the other cannot stop firing.

**It is a floor, not a knob, and the floor is eight draws.** The plane spans 23.474 mm and
0.152 mm at the food over 1…1024, and every millimetre of the wide one is below a budget of 8.
From 8 up the captures hold to 0.027 and 0.152 mm, inside Req 5.1's 1 mm. A budget of 2 sits
23.466 mm out at a 9.504° tilt. Second constant with this shape after `gravityAngleMaxRad`.

**The promoted leg's rule, replayed on this leg's own trace, exits at 39 and 5 draws** — 6.6×
and 51× cheaper — landing 0.019 and 0.069 mm from the shipped plane. The budget is generous
because the surface is easy: the winning hypothesis holds 0.607 and 0.949 of the points, far
above the w = 0.25 the argument treats as comfortable.

**The sweep is exact rather than sampled.** `uniformInt` consumes one `next()` and the loop draws
i, j and k unconditionally before any `continue`, so a budget-B run is a strict **prefix** of a
budget-B′ run and the winner at any budget is the last improvement at or before it. Checked
against independently seeded short runs. No interpolation rider is needed in either direction —
the only owed constant here for which that is true.

**Req 4.3 does not pin it.** That requirement makes the plane *used* equal the plane the
edge-band fit *produces*, and both move together — Decision 54's reading. The line at the top of
this note ("byte-identical to what it produces today") is about the pipeline not substituting a
different plane, not about freezing this fitter's constants. The shipped bits happen to be
reproduced by {256, 512} alone, which is a corpus fact.

**What bounds it is `SupportPlaneRegressionSliceTests`, and this is the suite's first reading
through the fallback leg** — every earlier one was on `SPRScene` scenes, which run neither
extraction nor the fallback fit. At a budget of 1 or 2 the parity capture's pre-feature ring
median goes **negative** (−4.309 mm, the sign Req 6.2 is about), support reads 0.594 against a
0.5 bar, and volume reads 200.885 cm³ against 682.96. All three go red at once; the suite floors
the budget at 4.

**The suite is the looser source, which is new.** Corpus 8, suite 4 — a budget of 4 passes every
committed assertion while sitting 2.231 mm from the shipped plane, past Req 5.1. Decision 41
warned about the reverse. The regression bands are volume and ring-median bands, not transfer
bands.

**Req 7.6 and the corpus point the same way for the first time.** Every iteration is a full O(n)
scan over the **colour** grid — the one place in the feature that runs at 1920×1440 — so 256
draws cost 2.76 × 10⁸ and 3.78 × 10⁸ distance tests, 96.9 % of them past the 8-draw floor, on
the path that produced the 32 GB allocation failure.

**Both brackets are readings at `gravityAngleMaxRad`**: a rejected triple spends an iteration and
buys nothing, so the last improvement moves with the cone (#76 → #46 at 1°, where 45 of 46 draws
are rejected by then; #210 → #236, where 192 of 236 are).

**Not repaired.** Adding adaptive stopping here is what the measurement recommends and it moves
the shipped fallback plane — the plane Decision 36 prices `fallbackPenalty` against and the one
that feeds `lidarMmPerPx` on the legacy path.

## The headrooms, and why the corpus is the worst case for all of them (Decision 63)

Decision 62 found `ringMinSamples`'s "5.6–7.0× margin" reading **2.64×** on a capture 61 mm
further away, and left the obvious follow-up open: every other headroom in this feature was
read at 336.9 and 338.9 mm too. This is that re-check, over all four committed slices at the
shipped constants — `theQuotedHeadroomsAreReadingsAtTheCorpusRange`.

| Reading | 272.9 mm | 336.9 mm | 338.9 mm | 399.9 mm |
|---|---|---|---|---|
| Smear envelope | 73.995 % | 91.963 % | **93.078 %** | **110.054 %** |
| Ring band margin | 5.950× | 6.470× | 5.600× | **2.640×** |
| Pass depth (cap lifted) | 2 | 3 | 3 | 2 |
| Residue left | 0.000 % | 9.202 % | **78.695 %** | 1.146 % |
| Iteration headroom | 204.800× | 49.951× | **8.192×** | 341.333× |
| Polish depth to fixed point | 6 | 5 | **17** | 4 |
| Selected tilt | 0.920° | 1.639° | **8.309°** | 0.755° |
| Smallest admitted extent | 109.513 mm | **47.821 mm** | 141.479 mm | 50.625 mm |

**Nothing recorded has to move.** Every headroom that transfers has its *worst* reading on the
corpus, so the figures Decisions 29–57 quote are worst cases rather than typical ones. Read the
bold column entries: they are the binding value for their row in every case but the two
`mmPerPx` rows.

**Caps transfer; millimetre-denominated quantities need checking.** A cap bounds a *loop*, and
loops count draws and passes, so `maxCandidatePlanes` never fires (extraction stops **starved**
on all four), `maxIterationsPerPass` never fires, and `consensusPolishMaxPasses` always binds —
all three findings intact across 1.5× of range and a different plate.

**The two re-denominations are both evidenced now, by different experiments.**
`minAcceptedExtentMm` holds because extent is a pixel count × `mmPerPx` and the pixel count of a
fixed surface falls as `mmPerPx` rises — the terms cancel, which is exactly why Decision 37
converted it out of pixels. Decision 62 proved the same for `minResidueAreaMm2` across a grid
halving; this proves the extent one across range.

**The two failures are not the same failure.** The smear envelope *is* `mmPerPx` up to a
constant, so it is linear in range and orders by it exactly. The ring band margin is denominated
in `mmPerPx` and is **not a function of it** — 5.600× at 338.9 mm against 5.950× at 272.9 mm,
while two captures 2 mm apart read 5.600× and 6.470×. Perimeter is in that sample count as much
as resolution. Decision 62 flagged this as a caveat; it is now measured non-monotonicity, and
the test asserts it (a future slice making the margin monotone in range fails there on purpose).

**Two things the pair makes look safer without measuring.** The cone margin's binding capture is
the corpus's 8.309°; the pair's plates are an order flatter, so `gravityAngleMaxRad` is still
owed to a capture that tilts the plate deliberately. And the polish depth reads 17, 5, 6, 4 — so
Decision 54's 17 is one capture, and a ceiling set from it is set from an outlier.

**`rangeCaptures`'s admission is now a rule, not a list.** Decision 62 admitted the pair for
"the grid-transfer measurements only"; Decision 63 widens that to "any measurement that reads no
owed constant **as a bar**". The audit reads distances from *shipped* values, so it
re-denominates nothing in Decisions 40–57 — which was the actual condition, the grid being
incidental to it. Harder to check mechanically; check what a new test reads before adding the
pair to it.

## The degeneracy gate, and why it works on one leg and not the other (Decision 64)

`LiDARPlaneFitter.stabilityRatioMin = 1e-6` was the last constant in either file with no
marker and no sweep. It is `refine`'s refusal — σ_min(A)/σ_max(A) for the centred 3×n
sample matrix, computed through the 3×3 scatter matrix — and both fitters reach it:
extraction calls `refine` through `try?` so a refusal silently drops a candidate, the
fallback leg throws `.lidarFitDegenerate`.

**It is disabled by sample count.** On an exactly planar set (σ_min zero by construction):

| n | shipped σ_min/σ_max | gate |
|---|---|---|
| 1,000 – 50,000 | 0.0 | REFUSES |
| 100,000 | 1.43e-3 | admits |
| 200,000 | 1.80e-2 | admits |
| 640,000 | 2.94e-2 | admits |
| 1,300,000 | 3.22e-2 | admits |

Extraction refines annulus sets of **1,752–9,087** samples; the fallback leg refines
colour-grid sets of **641,694** and **1,298,233**. The crossover is between them, so one
fitter's degeneracy guard works and the other's does not, and nothing distinguishes them
but how many samples each hands to the same function.

~~Consistent with a Float running sum losing exactness past 2²⁴ (n ≈ 47,934 at a 350 mm
standoff) — which makes the crossover range-dependent, the `mmPerPx` family again.~~
**Superseded (Decision 65): that table is a reading at the NUMBER 350, not at a 350 mm
standoff, and the crossover is not range-dependent.** See the section below before quoting
any count from it.

**The cause is the centroid, not the normal-equations squaring.** Forming M = AᵀA squares
the condition number and is the obvious suspect; moving the scatter *and* the
decomposition to Double while keeping the shipped Float centroid reproduces the shipped
reading on every rung, so it is not. What is left is Decision 58's three Float
`reduce(0, +)` sums. **An offset centroid displaces every centred sample by a constant, and
a constant displacement is indistinguishable from thickness along the thin axis** — so that
defect manufactures the conditioning this gate reads as healthy. On the corpus: 1.0001×
inflation on the extraction sets, 1.0752× and 1.2631× on the two **largest** fallback sets
— and 1.0034× and 1.0018× on the two smaller ones (Decision 65).

**σ_min/σ_max is not the rank discriminant, so there is no floor to find.** An exactly
planar set and a collinear one both drive it to zero (9.5e-9 and 0.0); σ_2/σ_max separates
them (0.99999 against 0.0) and the gate does not read it. A strip carrying the corpus's own
3.44 mm of per-sample noise is admitted at every width down to 0.02 mm — reading 1e-4, a
hundred times the bar — and only exactly zero refuses. Firing at the shipped value needs a
strip under 0.2 µm. Bracketed **0…0.0113** by the corpus: a ceiling only. First owed
constant recorded as unsettleable rather than bracketed.

**The scenes' claim is true at the scenes' scale.** `SupportRegionScenes.makeDepth` derives
its ±0.3 mm from this gate; at its 1,964- and 2,420-sample surfaces an exactly planar scene
really does yield zero candidates. The same sentence at 200,000 samples is false. The
margin is not delicate — at 0.05 mm the surfaces read 602× and 995× the bar — so any
nonzero noise clears it and 0.3 mm is not a tuned value.

**Not repaired**, on Decisions 52–58's precedent: reading σ_2/σ_max, or accumulating the
centroid in Double, changes which candidates survive `try? refine` and moves the fallback
plane — the one Decision 36 prices `fallbackPenalty` against.

## The crossover is a property of the number, not the range (Decision 65)

Decision 64's crossover table above is a reading at the **number 350**, and quoting a count
from it at any other standoff is wrong. `theCrossoverIsNotARangeBound` sweeps nine
standoffs on the same exactly planar lattice.

A Float running sum of a constant `Z` stays exact while `k × oddSignificand(Z) < 2²⁴`, so
the crossover is **`2²⁴ / oddSignificand(Z)`** and the exponent divides out:

| standoff | odd significand | 2²⁴ / odd | measured crossover |
|---|---|---|---|
| 150 mm | 75 | 223,696 | 223,696 |
| 250 mm | 125 | 134,218 | 134,218 |
| 272.949 mm | 69,875 | 240 | 240 |
| 336.914 mm | 43,125 | 389 | 389 |
| **338.867 mm** | 43,375 | **387** | **17,504** |
| 350 / 700 / 1400 mm | 175 | 95,870 | 95,870 |
| 399.902 mm | 102,375 | 164 | 164 |

- **350, 700 and 1400 mm read the same count** across a 4× range span, which is what rules
  out the 1/z law outright. Range enters only through the exponent, and the exponent
  cancels.
- **Eight of nine land to the rung.** The exception is `1785135663727`'s own range,
  338.867 mm, at 45×. Past the exactness bound the sum's error is a random walk, not a
  monotone drift, so the bound is a **floor** on the crossover rather than its location.
- **The committed ranges cross two to three orders lower than the round ones**, because a
  range is `mmPerPx × fx` and carries a full significand. Nothing physical distinguishes
  336.914 from 338.867 mm; their crossovers differ 45×.

**So do not read the lattice for where either leg sits.** It holds every sample at exactly
the same z, and the corpus's per-sample spread is 3.44 mm.

### What the corpus's own sets say

Subsample the fallback leg's real final inlier set by stride — spatial spread held, only
the count moving — and a **single count separates every reading across all four ranges**:
quiet up to **581,996**, inflating from **641,694**. The largest annulus in the corpus is
**12,551** samples, so the extraction leg is safe by count at **46×**, not the 5× the
synthetic bracket implied.

**Count alone does not set it, and the control is what proves that.** The candidate point
set (`collectCandidatePoints`, before any inlier test) is larger than the inlier set drawn
from it on every capture and does not inflate:

| capture | inlier set | candidate set |
|---|---|---|
| `1785901032716` | 1,298,233 → **1.2631×**, σ ratio 0.009 | 1,475,580 → **0.9989×**, σ ratio 0.021 |
| `1785135663727` | 641,694 → 1.0752×, σ ratio 0.016 | 1,077,427 → 0.9979×, σ ratio 0.267 |
| `1786450130307` | 581,996 → 1.0034× | 1,177,405 → 1.0039× |
| `1786439141215` | 282,430 → 1.0018× | 434,542 → 1.0003× |

A 1.14× larger set, 2.3× thicker, and the inflation goes away. What it tracks is the
centroid's error **over the set's own thickness**; Decision 64 recorded the numerator only.
~~The thinness half is measured on these four controls and **not swept** — no aspect ratio
has been varied at fixed count — so treat "error over thickness" as the shape of the account
rather than its form.~~ **Superseded (Decision 66): swept, and the control table above is
confounded — see below before reading a thickness attribution off it.**

Two consequences worth not re-deriving:

- **"The fallback leg ships with no effective degeneracy guard" is narrower than it reads.**
  What is uniform across the corpus is that the gate cannot *fire* — four orders below the
  bar at every capture, unchanged. Whether its reading is *inflated* is not uniform: half
  the committed captures sit under the turn.
- **The verdict on the constant does not move.** `stabilityRatioMin` is still `[owed]` and
  still unsettleable, on Decision 64's third finding, which this decision does not touch.

## The inflation has a closed form, and it is quadrature (Decision 66)

`theInflationIsErrorOverThickness` holds the count **exactly** — the same points, with only
their out-of-plane component scaled about their own least-squares plane — and sweeps the
thickness over two orders either side, on all four committed captures.

**The form.** An offset centroid displaces every centred sample by the same δ along the thin
axis, so that axis' second moment gains exactly `n·δ²` (the cross term vanishes, because the
exactly-centred coordinates sum to zero) while σ_max is set by the in-plane extent and does
not move. So the ratio the gate compares picks up δ/σ **in quadrature**:

> **inflation = √(1 + (δ/σ)²)**, δ = the Float centroid's error along the thin axis,
> σ = the set's own RMS distance to its least-squares plane.

Over **32 rungs** it predicts the measured inflation to **<1e-4** relative error. A linear
`1 + δ/σ` reading — which is what "the error divided by the thickness" sounds like — is out
by up to **41.4%**. Representative rungs on `1785901032716` (n = 1,298,233 throughout):

| scale | thickness | δ | δ/σ | measured | quadrature | linear |
|---|---|---|---|---|---|---|
| ×⅛ | 0.190 mm | 1.231 mm | 6.470 | 6.5470× | 6.5470× | 7.4702× |
| ×1 | 1.522 mm | 1.184 mm | 0.778 | 1.2671× | 1.2671× | 1.7782× |
| ×16 | 24.352 mm | 0.383 mm | 0.016 | 1.0001× | 1.0001× | 1.0157× |

**Thickness enters twice.** δ is not a constant the sweep divides by — it *falls* as the set
thickens (**3.2×, 5.0×, 18.9×, 21.5×** across the four sweeps), because Decision 65's
exactness bound is about adding the *same* value repeatedly and a spread is what breaks that.
So ×128 of thickness moves δ/σ by 412–2,750×, not by 128×.

### The count half is the same law, and its bracket is the corpus's

Decision 65's `inflationBar` of 1.01 is **δ/σ = 0.1418** in these units. That bar classifies
all **26** count-sweep rungs identically to the inflation bar — **0 disagreements** — so the
count account is this law read on one variable, with the count entering only through δ.

**But do not transfer the 581,996…641,694 bracket.** Its two ends are *different captures*:
across it the count moves **1.10×** while δ moves **5.09×** and the thickness moves 1.21× the
other way. The bracket is a fact about which two captures the corpus contains.

### What this gives the extraction leg

A margin in the deciding quantity rather than in a count. Annulus δ/σ against the 0.1418 bar:

| capture | n | thickness | δ | δ/σ | margin |
|---|---|---|---|---|---|
| `1785135663727` | 10,469 | 9.969 mm | 0.011917 mm | 0.001195 | 119× |
| `1785901032716` | 12,551 | 7.709 mm | 0.000027 mm | 0.000004 | 39,903× |
| `1786450130307` | 12,274 | 5.577 mm | 0.008148 mm | 0.001461 | **97×** |
| `1786439141215` | 5,276 | 3.795 mm | 0.001804 mm | 0.000475 | 298× |

Every one of those is a *measurement* of δ. Decision 67 below replaces the need for one: the
same margin, at 7.6×, from (n, μ, σ) with no δ read at all.

### Decision 65's control is confounded — read this before quoting it

The candidate-point control differs from its inlier set on **both** axes, so it does not
isolate thickness:

| capture | count | thickness | δ | measured |
|---|---|---|---|---|
| `1785135663727` | ×1.68 | ×47.02 | ×0.237 | 1.0000× |
| `1785901032716` | ×1.14 | ×2.16 | **×0.135** | 1.0012× |
| `1786439141215` | ×1.54 | ×3.14 | ×0.622 | 1.0001× |
| `1786450130307` | ×2.02 | ×7.90 | **×11.000** | 1.0040× |

On the capture Decision 65 quotes (`1785901032716`) δ falls 7.4× where the thickness rises
only 2.16×, so most of that reading is the numerator. **The conclusion survives on a capture
it does not quote:** `1786450130307`'s candidate set carries **11× the centroid error** of its
inlier set and is still quiet, because it is 7.9× thicker. That is the one unconfounded
reading of the thinness half in the corpus.

**Still `[owed]` and still unsettleable.** A form for the *inflation* is not a bar for
*degeneracy* — Decision 64's third finding (σ_min/σ_max does not order the degenerate side at
any value) is untouched. **Not repaired**, on Decisions 52–65's precedent.

## δ has a ceiling, not a form (Decision 67)

`theCentroidErrorIsTheSumsOwnDrift` turns the one knob the chain had not: the **standoff**.
A rigid translation along the camera's z axis holds the count, the in-plane geometry and the
thickness all *exactly* and moves only the magnitude the Float sum accumulates. Eight
standoffs, 175 → 2000 mm (an 11.4× lever, against the 1.5× the four captures span), on each
capture's fallback inlier set.

**The ceiling.** A sequential Float sum rounds at each step by at most `u·|S_k|`, and
`S_k ≈ k·μ`, so the sum is out by at most `u·μ·n(n−1)/2` and the **mean** by at most:

> **δ_z ≤ u·μ·(n−1)/2**,  u = 2⁻²⁴ ≈ 5.96e-8, μ = the set's mean |z|, n = its count.

This is Decision 65's exactness bound read as a *magnitude* rather than as a *count*: that
decision measured how many addends a Float sum takes before it rounds at all, this one how
fast it departs afterwards. Over **32 rungs** the measured error sits at **0.0034…0.3117** of
its own ceiling. Never above it — and never near it.

**Inside the ceiling, δ is cancellation and nothing predicts it.** The share spans **91.2×**
(mean 0.0892), and 11.6–51.1× *within a single capture*. δ does not even track μ: fitted
against the standoff it reads **μ^1.52 … μ^2.06**, super-linear where the ceiling is linear,
because the share itself climbs with the standoff — a set whose spread is small against its
own standoff is nearer the constant addend the exactness bound is about, so distance takes
the cancellation away.

**The count half is drift, not a walk.** Read in δ alone, the count sweep fits **n^1.065,
n^1.143, n^1.214, n^1.258** (mean **n^1.170**) against n^1.0 for drift and n^0.5 for an
unbiased walk. So the ceiling's linear-in-n shape is right and the corpus sits at 4.4–10.1 %
of it at full count.

### What the ceiling buys — both legs, from (n, μ, σ) alone

Composed with Decision 66's form: **δ/σ ≤ u·μ·(n−1)·|n̂_z| / 2σ**. Three numbers any set
carries before it is fitted, against the 0.1418 bar:

| set | n | μ | σ | δ/σ ceiling | δ/σ measured |
|---|---|---|---|---|---|
| `1785135663727` annulus | 10,469 | 361.0 mm | 9.969 mm | 0.0113 | 0.001195 |
| `1785901032716` annulus | 12,551 | 352.1 mm | 7.709 mm | 0.0171 | 0.000004 |
| `1786439141215` annulus | 5,276 | 407.2 mm | 3.795 mm | 0.0169 | 0.000475 |
| `1786450130307` annulus | 12,274 | 283.3 mm | 5.577 mm | **0.0185** | 0.001461 |
| `1785135663727` fallback | 641,694 | 375.5 mm | 1.815 mm | 3.94 | 0.3991 |
| `1785901032716` fallback | 1,298,233 | 358.0 mm | 1.522 mm | **9.09** | 0.7782 |
| `1786439141215` fallback | 282,430 | 407.3 mm | 2.439 mm | 1.40 | 0.0619 |
| `1786450130307` fallback | 581,996 | 290.8 mm | 2.199 mm | 2.28 | 0.0647 |

The extraction leg clears the bar by **7.6× on the ceiling alone**, so its degeneracy guard
can be asserted safe on a capture that has not been taken. The bound is not vacuous — it
refuses all four fallback sets.

**It is ONE-SIDED. Do not read "over the ceiling" as "inflated":** two of those four fallback
sets measure *under* the bar (0.0619, 0.0647) while the ceiling refuses all four. The
certificate is of safety only.

**Still `[owed]` and still unsettleable**, on Decision 64's third finding. **Not repaired**,
on Decisions 52–66's precedent.

**Read Decision 68 before quoting "the corpus sits at 4.4–10.1 % of it at full count".**
The count sweep prints `share.max()` over the whole sweep under the label "at the top", and
the share is not monotone in n. At full count the four sets read **10.12 %, 8.56 %, 2.84 %
and 4.41 %** — 2.8–10.1 %. Nothing else in Decision 67 moves.

## The share has no form at all, so the ceiling is the end of the line (Decision 68)

`theShareHasNoFormInTheSetsShape` closes the chain by refuting Decision 67's own account of
why the share moves. It fits **no plane**: the ceiling and the share are both written on the
z sum, so `SpreadReading` reads μ, σ_z and δ_z directly and four paths become affordable
where Decision 67 could afford one. 118 rungs, 6 dropped for straddling z = 0 (ARKit puts
the scene down the camera's **−z**, so "shares a sign" is a negative sign here and the
ceiling is written on |μ| throughout).

**The knob nobody could turn: hold the ratio, move both its ends.** A dilation about the
camera origin scales μ and σ_z by the same factor, so `σ_z/μ` is held to the last bit.
Powers of two are excluded from the sweep — a dilation by 2^k is exact in binary floating
point and re-rounds nothing.

| capture | ratio held | μ swept | share |
|---|---|---|---|
| `1785135663727` | 0.023466 | −113 → −2140 mm | 0.0030…0.1218 (**40.4×**) |
| `1785901032716` | 0.020157 | −107 → −2040 mm | 0.0003…0.3592 (**1353.2×**) |
| `1786450130307` | 0.034861 | −87 → −1657 mm | 0.0262…0.1608 (6.1×) |
| `1786439141215` | 0.010729 | −122 → −2322 mm | 0.0140…0.0954 (6.8×) |

One capture, one held ratio, three orders of share. **No function of `σ_z/μ` can produce
that**, whatever its shape — which is why this path refutes more than a power law does.

### And no other combination of the set's shape replaces it

The whole power-law family over `(n, μ, σ_z)` fitted at once, with the ratio account as the
one-regressor model nested inside it. Residual spread is quoted as a FACTOR, the same unit
as the raw span, so "explained" and "left over" are comparable:

| model | left of a 1640.7× span |
|---|---|
| the ceiling alone (intercept only) | 1640.7× |
| the ratio account, share ∝ (σ_z/μ)^−0.543 | 1353.2× |
| the free family, share ∝ μ^0.695 · n^0.298 · σ_z^−0.489 | **946.8×** |

A three-exponent law removes a factor of **1.7 from a factor of 1641**. Per capture — four
free parameters against 27–29 rungs, the most generous reading the corpus supports — it
still leaves **97.8×, 290.8×, 42.3× and 39.6×**, and the exponents disagree with each other
(μ^0.591…μ^1.372, σ_z^−0.906…σ_z^−0.399). The width is the share's, not the pooling's.

### This refutes the account, not the measurement

Read through the plane-free δ_z, the standoff path returns **μ^2.059, μ^1.523, μ^1.840,
μ^1.563** — Decision 67's μ^1.52…μ^2.06 exactly, from a reading that never forms a scatter
matrix. Those numbers are confirmed; the sentence written underneath them is what falls.

### What survives, and it is a question for the sitting

| set | n | μ | σ_z | σ_z/μ | share |
|---|---|---|---|---|---|
| `1785135663727` | 641,694 | −375.5 mm | 8.812 mm | 2.35e-02 | 0.1012 |
| `1785901032716` | 1,298,233 | −358.0 mm | 7.216 mm | 2.02e-02 | 0.0856 |
| `1786450130307` | 581,996 | −290.8 mm | 10.137 mm | 3.49e-02 | 0.0284 |
| `1786439141215` | 282,430 | −407.3 mm | 4.371 mm | 1.07e-02 | 0.0441 |

The four committed sets span **3.6× at a mean of 0.0648**, where the synthetic family around
them spans 1640.7×. Real captures sit in a narrow band that nothing in the arithmetic
predicts. **Four points — a question for the sitting, not a bracket.**

`σ_z` here is the RMS of z about the mean z. It is NOT Decision 67's `σ`, which is the RMS
about the least-squares plane; a tilted plane puts its in-plane extent into σ_z, which is why
`1785135663727` reads 8.812 mm here and 1.815 mm there.

**So the ceiling is final.** Decision 67's `δ/σ ≤ u·μ·(n−1)·|n̂_z| / 2σ` is the tightest a
priori statement the feature can make, its 7.6× of extraction margin is the number to quote,
and its one-sidedness is **structural**: it is one-sided because the share that would make it
two-sided is not a function of anything the set carries. Every remaining question about
`stabilityRatioMin` is a capture question. **Still `[owed]`, still unsettleable, still not
repaired.**

## δ belongs to the summation ORDER, not to the set (Decision 69)

`theShareIsNotAPropertyOfTheSetAtAll` closes Decision 68's one remaining non-capture
negative — "the refutation is over the power-law family; a form outside it is not excluded
by the fits" — in the general form. Every knob in Decisions 66–68 moved the SET (thickness,
standoff, count, dilation), so each could only refute the families its own knob separates.
A **permutation** moves nothing the set carries: the multiset is held exactly, so n, μ, σ,
the aspect ratio and the least-squares plane are the same numbers rather than close ones,
and every function of the set's shape is held with them. Any movement in δ is movement no
such function can produce.

Ten orders of each of the eight committed sets (four captures × two legs, 80 readings).
Four orders are **structural** — a raster scan, a reversed scan, and the two `|z|` sorts —
and six are Fisher-Yates shuffles against fixed SplitMix64 seeds, so no reading is a
property of one clever permutation.

| set | n | δ span | structural span | shuffle span | noisiest order |
|---|---|---|---|---|---|
| `1785135663727` annulus | 10,469 | 34.3× | 34.3× | 1.82× | shipped |
| `1785135663727` fallback | 641,694 | 30.3× | 30.3× | 1.02× | shipped |
| `1785901032716` annulus | 12,551 | **272.8×** | 272.8× | 3.37× | `|z|` ascending |
| `1785901032716` fallback | 1,298,233 | 6.5× | 6.5× | 1.01× | `|z|` ascending |
| `1786439141215` annulus | 5,276 | 6.2× | 2.8× | 2.16× | `|z|` ascending |
| `1786439141215` fallback | 282,430 | 14.3× | 3.1× | 1.12× | `|z|` ascending |
| `1786450130307` annulus | 12,274 | 16.0× | 16.0× | 1.26× | `|z|` descending |
| `1786450130307` fallback | 581,996 | 9.5× | 9.5× | 1.02× | `|z|` descending |

**The spread is STRUCTURE, not chance.** Six independent shuffles agree to 1.01…3.37× while
the structural orders span 2.8…272.8×, and a structural order is the noisiest on **8 of 8**
sets. A random order gives a typical value with little variance; the orders a real scan
produces are the outliers. So the shipped δ is set by how the depth raster correlates with
z, and it is reproducible without being predictable.

**`|z|` ascending — the classic error-minimising order for addends that share a sign — is
the noisiest on 4 of 8 and the quietest on none.** The account: these addends are one
surface at one standoff, so a sort does not order magnitudes, it orders the *residuals*
about the mean and puts every below-mean sample before every above-mean one, so the partial
sum drifts one way for the first half instead of cancelling. That is an ACCOUNT, on Decision
68's precedent; the measurement stands without it. **Do not "fix" this by sorting.**

### What survives a permutation, and what does not

Decision 67's ceiling is written on n and μ, which a permutation holds by construction, so
it does not move — and no order reaches it. The fullest any of the 80 readings fills its own
ceiling is **0.4440** (`1785901032716` fallback, `|z|` ascending), against the 0.3117 that
decision's own 32 rungs reached.

| statement | at the shipped order | at the worst order |
|---|---|---|
| Decision 66's **measured** annulus margin | 97–39,903× | **72.7×** |
| Decision 67's **asserted** annulus margin | 7.6× | **7.6×** — cannot move |

The measured figure loses 549× off its headline and 1.3× off its binding end: nearly all the
loss is in the number that was quoted, and the number that actually bounded anything barely
moves. Extraction is safe under every order by both readings. **Quote the asserted one** —
per-capture ceilings 0.011272, 0.017063, 0.018543 and 0.016858, identical in every order.

### Decision 67's one-sidedness is vindicated on the fallback leg

That decision refused all four fallback sets by the ceiling while two of them MEASURED under
the 0.1418 bar, and read the gap as conservatism. Under permutation both go over:

| set | shipped δ/σ | worst order | vs the 0.1418 bar |
|---|---|---|---|
| `1786439141215` fallback | 0.061936 (under) | **0.190712** | 1.3× over |
| `1786450130307` fallback | 0.064674 (under) | **0.616915** | 4.4× over |

The ceiling was right about them; what looked like slack was the shipped scan order.

### The control, and where the shipped order sits

The Double reference re-summed in each order moves **0.000e+00 mm** — bit-identical across
all ten orders on all eight sets — against a smallest Float δ of 2.739e-05 mm. The multiset
is held to the last bit and the movement is the Float sum's alone.

The shipped scan order is **not systematically flattering**: it is the noisiest of the ten on
*both* legs of `1785135663727`, the quietest on `1785901032716`'s annulus and
`1786450130307`'s fallback set, and mid-pack (6 of 9 quieter) on both legs of
`1786439141215`. It lands at both extremes. But δ on the capture that anchors Decision 36's
`fallbackPenalty` pricing is the largest any order produces there — one more reason that
pricing is a reading and not a value.

### What this costs the decisions above

Every per-set δ quoted in Decisions 64–68 is a reading at the shipped scan order, with
6.2…272.8× of spread around it. Those decisions' CONCLUSIONS survive — each rests on the
ceiling, or on a ratio taken within one order — but **no δ quoted in them transfers to a
capture not yet taken.**

**Not repaired**, on Decisions 52–68's precedent. Pairwise or Kahan accumulation would make
δ order-independent and small at once, and it changes the centroid, hence which candidates
survive `try? refine`, hence the shipped fallback plane Decision 36 prices against.
`stabilityRatioMin` stays `[owed]` and unsettleable; every remaining question about it is a
capture question.

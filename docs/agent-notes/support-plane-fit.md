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
| `foodEnvelopeMinMm` | −6.758…8.233 mm | 7.154…21.041 mm (Decision 48) |
| `escapeBandMm` | ≥ 14.868 mm | reaches +5.750 mm |
| `maxCrossedSectors` | 0…2 | **2…2** at full pass depth (Decision 48) |
| `maxCandidatePlanes` | ≥ 2 | ≥ 2, no ceiling — *at 2× removal* (Decisions 48, 50) |
| `inlierRemovalMultiple` | none — no scene runs extraction | 1…2.5× (Decision 50) |
| `ransacSuccessProbability` | none — no scene runs extraction | 0.9…unbounded, NOT interpolable (Decision 51) |
| `maxIterationsPerPass` | none — no scene runs extraction | 128…unbounded, never fires (Decision 51) |
| `consensusPolishMaxPasses` | none — no scene runs extraction or the fallback fit | 1…unbounded, **always** fires, interpolable (Decision 54) |
| `gravityAngleMaxRad` | none — no scene runs extraction or the fallback fit | 10°…unbounded, a **floor** not a knob (Decision 55) |

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

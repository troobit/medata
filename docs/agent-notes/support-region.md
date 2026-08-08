# SupportRegion (support-plane-reference)

`MedataCore/Sources/SupportPlane/SupportRegion.swift` — the restricted (food-derived)
support-plane fitter. Extracts up to `maxCandidatePlanes` gravity-aligned planes from an
annulus around the food mask on the native depth grid (CC-RANSAC), scores candidates by
contact-ring evidence, and returns the admissible candidate with the highest inner-band
support fraction. See `specs/estimation/support-plane-reference/` for the full spec;
this note covers implementation details the design doc doesn't (or gets slightly wrong
as a literal interface sketch).

> **Two competing full implementations of this spec exist on local orbit branches**
> (25/27 tasks each, both green) — see
> [support-plane-variants.md](support-plane-variants.md) before extending this line.

## Architecture

One pass, shared geometry: `ringAndAnnulusSamples(depthGridFoodMask:depth:depthIntrinsics:)`
computes a chamfer distance-to-food-mask field once, converts it to millimetres via a
single per-capture scalar (`medianFoodDepthMm / focalAvg`), and buckets every non-food,
confidence-passing, valid-depth pixel into the **ring** (8–25 mm, `SupportRegion.RingSample`)
and the **annulus** (0–50 mm, `2×ringOuterMm`) in one scan. Both `contactRing` and
`ringStatistics` (task 3/4) and the CC-RANSAC candidate extraction (task 5/6) consume this
same structure — the annulus IS the RANSAC candidate set.

`fitFoodSupportPlane` (the public entry) downsamples the colour-grid mask and derives depth
intrinsics, computes ring/annulus samples once, extracts candidates via
`extractCandidatePlanes`, computes `ringStatistics` and `isAdmissible` per candidate, then
picks the highest-`supportFraction` admissible candidate (rejecting to nil if the top two
are within `ringSupportMarginMin`).

## Deviations from the design doc's illustrative signatures

The design's "Components and Interfaces" code block is a sketch, not a literal contract —
a few things there don't typecheck once you have real data flowing:

- `contactRing`/`ringStatistics` take the **depth-grid-native** mask + depth intrinsics
  directly (not colour-grid). `fitFoodSupportPlane` does the downsample/intrinsics-derivation
  once at the top and passes native-grid inputs down.
- `ringStatistics(ring:annulus:foodSampleCount:plane:...)`'s sketched signature takes raw
  `[Int]` index arrays for ring/annulus, which can't carry the 3-D points/angles the
  statistics actually need without recomputing the distance field a second time per
  candidate. The real signature takes `[RingSample]` (index + point + distMm + angle),
  computed once by `ringAndAnnulusSamples`.
- The signed `|median|` admission guard (Req 3.2) and the `escapeBandMm` annulus-median
  guard (Req 3.3, Decision 22) both reuse existing fields rather than adding new
  `SupportRegion` constants — signed median reuses `ringBandMm` (the same "approximately
  zero" neighbourhood Req 3.1 defines), not a separate unstated constant.

## Gotchas

**Synthetic-fixture flatness triggers a REAL degeneracy gate, not a fixture bug in
`refine`.** `LiDARPlaneFitter.refine`'s SVD stability check (`sMin/sMax >= 1e-6`) is
correct — a truly zero-variance direction (perfectly flat synthetic data, zero noise) *is*
degenerate by that check's own logic, even though "flat" is exactly the physical case being
tested. Test fixtures that construct a depth map via exact ray-plane intersection produce
EXACTLY flat regions (zero Y-variance), which fails `refine` the moment CC-RANSAC actually
calls it (task 3/4's `ringStatistics` doesn't call `refine` at all, so this only bites task
5+ tests that go through extraction). Fix: add deterministic, **zero-mean** jitter to the
synthetic height field (see `heightFieldDepthMap` in
`MedataCore/Tests/SupportPlaneTests/SupportRegionFixtures.swift`).

**The jitter amplitude has a real floor, and it's scale-dependent.** Float32's ~7-digit
precision means a scatter-matrix term computed from millimetre-scale X/Z spread over
hundreds of points can reach the millions (`M22 ~ 4.68e6` was observed at the guard-scale
fixture's ring radii). A jitter variance below roughly `M22 × 1.2e-7` (Float32's relative
precision) is indistinguishable from zero once accumulated into the scatter matrix — the
plane still gets rejected as degenerate, just for a different underlying reason (precision
loss, not true collinearity). The jitter must be non-zero-mean-cancelling (median-based
statistics elsewhere have ~1–2 mm accuracy tolerances) AND large enough (mm-scale, not
hundredths-of-a-mm) to survive cancellation at the coordinate magnitudes the fixture
actually produces. `(residue − 2) × 0.6 mm` (zero mean over residues 0–4) is what's in use;
if a future fixture uses a much larger focal length / spread, re-check this margin.

**`fitFoodSupportPlane` end-to-end tests are expensive — annulus size is what matters, not
image size.** CC-RANSAC cost is ~linear in candidate-annulus point count per iteration,
and iterations only shrink once a good inlier ratio is found. A "ring/contactRing-only"
scene (task 3/4 scale, `sceneIntrinsics`, annulus ~30k points) is fine for those tests, but
running full `fitFoodSupportPlane` end-to-end at that scale took 10–40s **per test** in
debug builds. Task 7/8's end-to-end tests use a deliberately smaller focal length
(`guardIntrinsics`, `MedataCore/Tests/SupportPlaneTests/SupportRegionFixtures.swift`) to
keep the candidate annulus in the low thousands of points — same physical geometry
(8/25/50 mm bounds), far fewer pixels. Don't reuse `sceneIntrinsics` for a new
`fitFoodSupportPlane` test without checking timing first.

**mm↔px conversion is a single per-capture scalar, not a true distance transform.** Ring/
band/annulus boundaries are computed by converting `ringInnerMm`/`ringOuterMm`/etc. to
pixels via `medianFoodDepthMm / focalAvg`, then running a chamfer (approximate Euclidean)
distance transform in PIXEL space. If a test scene's FOOD HEIGHT differs from the value
some other pixel-radius constant was derived against, the derived boundary is wrong for
that scene (bit someone once: `sceneRingInnerBoundaryPx` etc. in the test fixtures are only
valid at `foodHeightMm = 126`; other food heights need `scenePixelRadius(mm:foodHeightMm:)`,
which mirrors the SUT's own conversion formula).

**Test scene depth-map construction needs `cy` chosen so `dirY = (y − cy) / fy > 0` for
every pixel actually used**, or the ray/plane intersection `t = d / dirY` goes negative
(invalid depth, silently dropped). Pinning `cy` well above the image (very negative) is the
simplest way to guarantee this for an arbitrarily-shaped scene.

## Guard test strategy

Two layers, deliberately: `SupportRegionAdmissibilityTests` calls `isAdmissible` directly
against hand-built `RingStatistics`/`SupportPlaneCandidate` fixtures (one field perturbed
per guard row — fast, exact, no RANSAC). `SupportRegionFitEndToEndTests` exercises the
named design scenes (plate/table, straddling ring, rimmed plate both ways, bowl, overhang,
frame edge, determinism) through the full public entry. Prefer the direct-`isAdmissible`
pattern for any new guard-specific test; reserve end-to-end scenes for cases that
genuinely need multi-candidate selection or the full extraction pipeline.

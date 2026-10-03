# Depth-grown food region

Spec: `specs/estimation/depth-grown-food-region/` (smolspec + decision log).
Code: `MedataCore/Sources/Volume/FoodRegionGrowth.swift`; wiring in
`Pipeline.estimate` (single-view branch) and `HarnessCore/FixtureRunner.run`.

## What it does

Grows every food-like region of the regularised nadir label map into the
raised depth slab around it before volume, so a food the segmenter only
partly recognises (the 2026-09-24 sesame roll: 0.5 % of the frame labelled,
7 % raised) is measured whole. The single-view LiDAR branch integrates over
the grown map. Since two-view-trust Decision 10 the two-view branch runs the
same sequence but takes the PLANE only: the carve silhouette, the review
outline and the persisted mask stay the segmenter's own (see "Two-view: plane
only" below).

Order matters and is the whole design: **grow → refit → prune.**

The sequence lives in one place, `Volume/GrownRegionPlaneRefit.refit`, with
the fitter injected as a closure (`SupportPlaneFitter.fitOutcome` on device,
`LiDARSupportPlaneFitter.fitFromDepth` in the harness — the same code under
the wrapper). `Pipeline.refitPlaneFromGrownRegion` adds the pipeline's own
consequences of an adopted plane (diagnostics row, LiDAR rescale, the
`event=region.grow` line); `FixtureRunner.refitPlaneFromGrownRegion` is the
replay twin and `CarveResidualAudit`'s `grownRefit` variant calls it too, so
the audit reports the plane production adopts, not a raw refit.

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
   volume will use, plus the seed band (Decision 4): height above that
   surface ≥ the seed cells' median height − `seedBandMm`.

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

`FoodRegionGrowthConfig.standard` = cliff 3 mm, floor 5 mm, cap 0.35, seed band 10 mm, seed-area gate 200 cm² (floor was 3 mm until 2026-09-25, Decision 3; the band is Decision 4; the gate is Decision 5, below). The band is a second prune test: an added cell whose height above the support surface is more than 10 mm below the seed cells' median height is dropped. It exists because the first plane can sit 4–5° off the table — on `1790315900185` the plate read 6–16 mm above it with the food at 30 mm, so no fixed floor separates them, while a food-relative band does and the tilt cancels out of it (`HarnessCLI ... --growth-band-mm N`, 0 = no band). A refit is adopted only when it references `foodSupport` (`SupportPlaneFitOutcome.foodSupportPlane`); a table refit keeps the first plane, because the integrator measures from the adopted plane with no offset and an adopted table plane added 19 mm to every pixel of the 2026-09-25 roll (519 cm³ against 247). The harness fits the first plane from the bundle's pre-shutter mask, as the device does; replays before 2026-09-25 fitted it from the argmax and diverged.
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

## The sweep that gates the merge (Decision 2, re-run 2026-09-25)

Decision 1's table came from the divergent replay path and is superseded by
the re-run in Decision 2, over 20 single-view `ab812dc3aa9d` bundles (19
scored) at commit `a785187`. Headline: at the shipped cliff 3 / floor 5 /
cap 0.35 / band 10 the median added area on the 11 captures with at least
5 % ungrown food-like area is **+0.5 %**, the largest single addition is
**+36 %**, the **cap trips on nothing** anywhere in the grid (verified by
re-running every no-growth cell at `--growth-cap 1.0`), and the roll
`1790223818017` grows 0.49 % → 7.45 % of the frame with a `foodSupport`
refit. That passes Req 8. Floor 3 with the band also passes (+5.5 % median),
so the rule's "smallest floor" clause names floor 3 and the shipped floor 5
is one notch above it, carried by Decision 3's device evidence and backed by
the corpus on the two figures the median hides (largest addition halves;
13 of 19 refits land `foodSupport` against 11 of 19). Against the corpus's
three weighed plates, growth **costs** accuracy: carb mean absolute error
rises 33.2 g → 40.4 g, all of it on `1785901032716`, an 80 g flat-bread plate
that already read 3.2× over. Since Decision 5 the seed-area gate keeps growth
off that plate (seed 330 cm²) and the weighed roll joined the set: 25.8 g gated
against 31.6 g ungated and 32.9 g off, over four plates.

Two practical corrections to the paragraph above. `HarnessCLI accuracy` is
the wrong command for field bundles — they carry zero ground truth, so every
meal is UNSCORED and it exits non-zero, and its loader holds the whole
directory in memory; use `HarnessCLI volumes` one bundle at a time, which
reports `foodPixelsBefore/After`, `refitReference`, `planeReference` and the
per-class volumes as JSON. And the corpus has more than 10 loadable
single-view successes: `captures/1786450130307-success.fixture` is the
truncated copy, but `pulls/20260827-3/captures/1786450130307-success.fixture`
is intact and loads, and `1785054950406` (the 208 g rice plate that once
yielded zero meals) now replays at 636 cm³. Build the harness from a scratch
copy of committed `HEAD` when other agents are editing the tree, or a
mid-sweep rebuild will mix two binaries into one table.

## The seed-area gate (Decision 5, 2026-10-03)

Growth now runs on the single-view path only when the segmenter's own
food-like footprint on the FIRST plane is at most
`FoodRegionGrowthConfig.standardSeedAreaGateCm2` = 200 cm²
(`FoodRegionGrowth.foodAreaCm2`: per pixel α²·cos³θ / (fx·fy·|n̂·r̂|), the ray's
footprint on the plane). Over it, `GrownRegionPlaneRefit.refit` runs `grow`
with `.disabled` (so a seed restriction still shapes the map) and skips the
refit: the estimate is byte-identical to growth off. The gate is opt-in per
caller (`gateBySeedArea:`, default false): `Pipeline.refitPlaneFromGrownRegion`
passes `!planeOnly`, `FixtureRunner`'s single-view replay passes true, and the
two-view branch and `CarveResidualAudit` pass nothing — the two-view refit is
never gated, so the "never silently the first plane" rule below still holds.
Outcome rows carry `regionGrowth.seedAreaCm2`, `seedAreaGateCm2`, `gated`;
`event=region.grow` prints `seedAreaCm2= gateCm2= gated=`.

Why cm² and not frame fraction: the same 58 g slice is 3.5 % of the frame from
400 mm and 9.8 % from 273 mm (86 and 112 cm²), and N5k's 640×480 rig frame is
not a phone frame. Why 200: every capture with truth that growth improved has a
seed of at most ~145 cm² (weighed roll 25, slice 86/112, the roll's card
captures 94–102); the one it made worse (`1785901032716`, multigrain) is 330.
N5k scores identically to no gate from 175 cm² up. Sweep tables: Decision 5.

How the sweep was run, for the next one:

- N5k: `tmp/n5k_fixtures_ckpt` holds all 3,485 fixtures (10 GB) and
  `accuracy` loads a whole directory, so symlink the 236 `single_dominant`
  ones into their own directory — `grep -l -a single_dominant` on the files
  finds them. `--checkpoint-sha256` is the full 64-hex stamp
  (`ab812dc3aa9d269e…612a88f`), not the 12-character device form.
- Gating yields exactly the ungrown estimate and depends only on the ungrown
  footprint, so one run with growth and one with `--growth-cap 0` give every
  threshold post hoc; `--growth-gate-cm2 N` confirms one for real. The growth
  line on stderr now ends `seedAreaCm2=… gated=…`.
- N5k reads low on 206 of 216 plates, so ANY added volume scores as an
  improvement there; it cannot say whether the added region is food.
- Decision 1's N5k cost (9.47 vs 9.29 g) reproduces exactly with the harness
  built at `3022b80`, and not at `abd9750` (9.18 vs 9.33 g, growth helping);
  floor/band are not the reason. Not bisected.

## No second guard (Decision 6, 2026-10-03)

The 83 g toast (`1790748465041`) reads +105 % with growth (7.4×, 27.8 →
205.2 cm²) and −70 % without. It looked like growth running over the plate,
so a ratio cap (grown/seed) and a grown-footprint cap were swept, each as a
fall-back to the ungrown map and as a clamp on the fill. Nothing shipped.

- **The grown region is the toast.** The segmenter labelled only the crust
  ends of two slices. The depth shows two slabs 18–25 mm above the board and
  the plate 1–4 mm. The cells at least 12 mm up cover 207 cm² and hold 415 cm³;
  growth's region is 205 cm² and 426 cm³. The over-read is the plate under the
  toast (the plane is the board, `edgeBand`, and the refit is `edgeBand` too)
  plus density: 83 g over the depth's 345–405 cm³ is 0.20–0.24 g/cm³, against
  bread_wholemeal's 0.4.
- **The growth ratio measures segmenter recall, not leaks.** Toast 7.4×,
  104 g roll 3.9×, and the founding 2026-09-24 roll capture (`1790223818017`)
  15.2×. Any ratio cap low enough to catch the toast also removes that roll
  (25.6 against 230.7 cm³ for 260). Decision 5 rejected the opposite ratio
  gate for the mirror reason.
- No Nutrition5k plate grows past 2.64× (median 1.02×), so ratio caps from 3×
  up do nothing there, and every footprint cap or clamp that binds costs it
  something. The tables are in Decision 6.
- For a toast-like plate, look at density and the plane, not growth. Render the
  bundle before blaming growth: a minimal raw-protobuf reader (fields 6 image,
  8 depth with float32 mm, 11 argmax, 13 intrinsics) plus a RANSAC table plane
  in numpy is enough. `tools/segmenter/.venv` has numpy and PIL. Background is
  palette index 33 on `ab812dc3aa9d`.
- Sweep mechanics, for the next one: the fall-back is exact post hoc from one
  growth run and one `--growth-cap 0` run. The growth line's `before`/`after`
  give the pixel ratio, and seed cm² × ratio is the grown footprint to within
  1 %. A clamp needs a scratch build. Stage the release binary and its
  `*.bundle` directories together (`MedataCore_Foods.bundle` is loaded at
  runtime), or every run dies with `unable to find bundle`.

## Two-view: plane only (two-view-trust Decision 10)

The two-view branch fitted its plane once and never refitted; the carve
residual audit (`two-view-geometry-audit.md` §7 (c)) measured that as the one
structural difference between the branches, worth 6–23 % on two of five
bundles. The plane is both the carve's floor and the origin the grid height is
measured from, so a first plane sitting on the table hands the carve a slab of
hull under the food. `Pipeline`'s two-view branch now calls the same
`refitPlaneFromGrownRegion` after reconciliation, with `planeOnly: true`:
`plane`, `planeReference` and the LiDAR scale follow an adopted refit exactly
as on the single-view branch; `measuredArgmax` and the carve silhouette do
not. Growth here is a plane-fitting instrument, nothing else — do not pass
`growth.grownRegion` or `growth.argmax` anywhere on that branch. If growth is
ever gated or retired, the two-view refit falls back to a refit from the
reconciled argmax, never silently to the first plane.

Offline replay (`HarnessCLI carve-audit`, `volumes`) is the regression bar:
the single-view rows are byte-identical to before the refactor, and the
two-view rows moved only where the refit lands `foodSupport` and the pruned
region stands.

## Gotchas

- The bundle keeps the segmenter's (ungrown) argmax; replay re-grows. The
  mask artefact the review outline reads is the grown map on the single-view
  branch and the segmenter's map on the two-view branch.
- Outcome rows carry `regionGrowth.planeOnly` (`true` on the two-view
  branch, `false` single-view, absent on rows written before it existed).
- The colour-grid edge follows the bilinear depth contour, not the 7.5 × 7.5
  px cell blocks: a pixel is added when its own bilinear depth clears the
  floor and its cell or a 4-neighbour cell was filled (evening 2026-09-24,
  after the "speckles around edge of roll" field note). Counts in tests are
  therefore ranges, not cell multiples.
- `pipelineStageLog` is Debug-only; `event=region.grow` is on
  `supportPlaneLog` so it reaches the Release log.
- Outcome rows carry `regionGrowth {applied, capTripped, foodPixelsBefore,
  foodPixelsAfter, refitReference, refitRefused, planeOnly, seedAreaCm2,
  seedAreaGateCm2, gated}`; the plane fields describe the plane the volume used
  (the refit when adopted). A gated row reads `applied=false`, `gated=true`,
  before = after.
- `regionGrowth.grownAreaCm2` (also `grownAreaCm2=` on `event=region.grow`, the `HarnessCLI` growth line and `volumes` rows) is the returned map's footprint on the same first plane by the same `foodAreaCm2`, so it reads directly against `seedAreaCm2` (equal on a gated or ungrown row) and replaces Decision 6's seed × pixel-ratio estimate.
- The weighed corpus for this feature is four single-view bundles:
  `tmp/device_captures/{1785901032716,1786439141215,1786450130307}-success.fixture`
  and `medata-corpus/reports/calibration-20260929-roll/1790655022746-success.fixture`.
  Everything under `medata-corpus/captures/` and `pulls/` was discarded
  2026-09-29; the symlink farms in `/private/tmp` point at nothing. The roll
  replays as `unknown_food` + a phantom `coffee`; score its `unknown_food`
  volume as bread_wholemeal (0.152 g carbs/cm³).

# Field-truth capture sessions (weighed ground truth)

Scale-weighed plates captured on device, with the app's estimates — the
evidence base for β_c calibration and class-coverage decisions. Pull the
outcome rows and bundles per the devicectl recipe in
`device-build-and-test.md`.

## 2026-08-16 — toast and a cereal bowl, model `coreml_ab812dc3aa9d`, build `a33cb5d-20260815-231735` (Release, clean tree)

The `myfoodrepo-bridge` task 7 capture pass. No scale truth taken — the developer
judged by eye, so the numbers below are against nominal portions, not weighed
ground truth. Every attempt wrote a bundle to `Documents/captures/`.

**This session is what closed task 6.** All nine outcome rows carry
`modelVersion=coreml_ab812dc3aa9d` on a build installed the night before, which
is the live-lineage evidence the launch log cannot give (see
`device-build-and-test.md`, "`segmenterSource` has two forms").

### Scene 1 — one slice of toast, 11:42–11:44

| Time | Path | Outcome | Estimate / failure |
|---|---|---|---|
| 11:42:56 | single-view LiDAR | success | `bread_wholemeal` 188.9 cm³ → 75.6 g / **28.7 g carbs** |
| 11:43:21 | two-view SfS | refused | `noFoodVolumeRecovered`, oblique 28.2° |
| 11:44:09 | two-view SfS | refused | `noFoodPixels`, no oblique mask at all |
| 11:44:33 | two-view SfS | refused | `noFoodVolumeRecovered`, oblique 29.3° |

Nominal for one medium wholemeal slice is ~36 g / ~15 g carbs, so the LiDAR
reading is about **2x over** — the familiar direction. `planeReference=edgeBand`,
`planeRingBandMediansMm=[3.75, 5.49, 6.90]`, median **5.15 mm**: the same
plane-below-the-table mechanism as the 26.1 mm reproductions below, an order of
magnitude smaller this time. Solving the excess over a nominal ~110 cm³ against a
5.15 mm offset implies a ~150 cm² footprint, about one slice — self-consistent,
but inferred, not weighed. **Take a scale truth on the next flat-food capture**;
this session cannot settle whether the offset shrank or the slice was thick.

### Scene 2 — a bowl of milk, yogurt and submerged Weetbix, 11:55

| Time | Path | Outcome | Estimate / failure |
|---|---|---|---|
| 11:55:31 | two-view SfS | refused | `noFoodPixels`; `supportplane.end failure=emptyFoodMask candidates=0`, oblique 18.2° |
| 11:55:33 | two-view SfS | refused | same, same frame |
| 11:55:34 | two-view SfS | refused | `worldTrackingDegraded` at oblique capture |
| 11:55:43 | two-view SfS | success | `bread_wholemeal` 63.8 cm³ + `tomato` 246.6 cm³ = **14.5 g carbs**; oblique 25.3° |
| 11:55:56 | single-view LiDAR | success | `cheese` 66.9 cm³ → 73.6 g / **0.07 g carbs** |

Every mask read `topClass=33 topClassPercent=94–98` — class 33 is `background`
(`ClassPalette.swift:69`) — leaving 0–2 % food coverage, against 8–10 % on the
toast.

**This is not a cereal misclassification, and reading it as one would send the
next retrain in the wrong direction.** The developer's account of the scene:
the visible surface was milk and yogurt, with the Weetbix submerged beneath it.
So `cereal` (24) was not visible to be predicted, `milk` (28) exists as a liquid
class but was not chosen, and **yogurt has no class in the palette at all**. No
correct answer was available to the segmenter. The gap is that the pipeline
estimates what it can see and has no concept of food occluded beneath a liquid
or another food — a bowl whose contents are mostly hidden is outside what the
visual hull plus a surface segmentation can express, however the model is
trained. Adding cereal training images does not address it.

**Third reproduction of the dangerous-direction failure.** `cheese` at 0.07 g
carbs for a breakfast bowl repeats the pattern of `carrot` at 1.50 g for bread
(2026-08-05, below): a confident success whose wrong class hides a large carb
load. For a dosing tool an under-read is the direction that harms; the toast's
2x over-read at least errs safe.

**The bowl defeats the edge-band plane reference.** The LiDAR capture fitted
`planeReference=edgeBand` with a ring median of **23.3 mm** — the ring is sitting
on the bowl rim, not the table — while the two-view capture of the same scene
fitted `foodSupport` and got **1.57 mm**. That is the sharpest edgeBand-vs-
foodSupport contrast recorded so far and it is direct evidence for
`estimation/support-plane-reference`: whatever else it settles, the reference
must not be the rim of the vessel.

### On the two-view carve

Mixed, and it partly rehabilitates `specs/bugfixes/two-view-carve-no-volume`,
whose Resolution blames a mis-aimed oblique and left the on-device verification
open. Today the carve **recovered volume at an oblique of 25.3°** — dead on the
target ring — and recovered nothing at 28.2° and 29.3°, both inside the 10–40°
arming band. Aim matters more than "inside the band" captures. What that report
still does not explain: the 28.2°/29.3° attempts had food pixels in *both* views
(10/8 % and 5/4 %) with `degenerateRaySkipCount=0`,
`degenerateVoxelSkipCount=0` and nothing threshold-discarded, and still carved
nothing. Do not close that report on this session — it needs a trail where the
oblique is aimed and the tilt is off the ring.

## 2026-08-13 — speckle/stability gate closed (no weighed truth)

Developer verdict on device: speckle is gone and readings are stable.
`tasks-segmenter-training-pipeline` task 7 (the on-device STOP acceptance
gate) is now **closed** on this evidence — accepted on the promoted
`coreml_ab812dc3aa9d` model plus the shipped `PostProcessing.swift`
connected-component cleanup, explicitly overriding the 2026-08-04 hold that
reserved the gate for the retrained model. Task 6 (the new-recipe training
run) remains open but is no longer what acceptance waits on.

## 2026-08-11 — weighed bread slice, model `coreml_ab812dc3aa9d`, build `9509b27-20260811-185011` (Release)

Scene: **1 slice of bread, 58 g total** (scale truth), white plate. Yellow bank
card as the ID-1 reference for two-view captures. iPhone 16 Pro. 15 attempts
19:05–19:08 local; bundles for every attempt (successes and refusals) in
`Documents/captures/`, single-view bundle pulled to
`tmp/device_captures/1786439141215-success.fixture`.

| Time | Stem | Path | Outcome | Estimate |
|---|---|---|---|---|
| 19:05:41 | `1786439141215` | single-view LiDAR | success | bread_wholemeal 48.6 cm³ → **19.4 g / 7.4 g carbs** |
| 19:07:14 | `1786439234576` | two-view SfS | success | bread_wholemeal 382.9 cm³ → 153.2 g + **cheese 43.7 g (the bank card)** = 196.9 g / 58.2 g carbs |
| 19:08:20 | `1786439300420` | two-view SfS | success | bread_wholemeal 301.3 cm³ → **120.5 g / 45.8 g carbs** |

Interleaved refusals, all in two-view mode: `noFoodPixels` ×7,
`worldTrackingDegraded` ×5 — the same framing-refusal pattern as the 2026-08-05
session, roughly half the shutter presses again.

Paired re-shoot at 22:08, same plate, same 58 g, build `6675525-20260811-192504`
— taken from **inside** the ~365 mm smear envelope after the range finding below
(median food depth 272.9 mm vs the first capture's 399.9 mm, measured off the
committed slices):

| Time | Stem | Path | Outcome | Estimate |
|---|---|---|---|---|
| 22:08:50 | `1786450130307` | single-view LiDAR | success (`foodSupport`, 8/8 sectors) | bread_wholemeal 77.1 cm³ → **30.8 g / 11.7 g carbs** |
| 22:09:22 | `1786450162911` | two-view SfS | refused `unrecognisedFood` | — |

The inside-envelope capture still under-reads **1.9×** with a stronger plane
verdict than the contaminated one — range explains 3.0× → 1.9× and no more.
Slice committed as `1786450130307.depthslice`; the residual under-read is the
lead question for the support-plane task 26 pass.

Readings:

- **First field firing of the promoted support plane.** The single-view capture
  selected `planeReference=foodSupport` (6/8 supporting sectors, ring median
  −0.97 mm, residual 1.81 mm) — the first real capture where the restricted fit
  was admissible under the shipped placeholder constants. But the estimate is
  **3.0× UNDER** by mass (19.4 vs 58 g; ~215 cm³ expected vs 48.6 measured),
  where the pre-feature defect was a 2–3.6× over-read. Plausible mechanism: the
  admitted plane sits at or near the bread's top surface rather than the plate,
  truncating the height field. The pulled bundle is the evidence for
  support-plane task 26; slice with `tools/fixture_slice.py` and add to
  `SupportPlaneCorpusMeasurementTests`.
- **Two-view still over-reads over the table plane.** Both two-view successes
  kept `planeReference=edgeBand`; capture 3's ring median is **+12.9 mm** (the
  table), and the over-reads (2.1×, 2.6× on the bread rows) match the known
  constant-height mechanism on flat food.
- **The reference card is segmented as food.** The yellow bank card was
  classified `cheese` (39.7 cm³ → 43.7 g phantom mass, EST_SOLID density) in
  capture 2 — out-of-palette-object-as-food, same family as the brussels-sprouts
  and pumpkin sessions, but now corrupting the two-view decomposition while the
  card simultaneously serves scale (`scaleSource=card+lidar`). A card mask
  exclusion zone may be worth a spec: the card's pose is already solved, so its
  image-plane extent is known to the pipeline.
- Weighed carb truth for the plate is ~24 g (58 g wholemeal at ~42 g/100 g), so
  the carb errors are −69 % (single), +143 % (capture 2, incl. phantom cheese),
  +91 % (capture 3).

## 2026-07-26 — staged plate, model `coreml_ab812dc3aa9d` (36-channel palette)

Build: PRE-gate binary for all four attempts (the unrecognised-food gate and
palette fixes deployed 18:39, after this session). Scale truth from the user;
estimates from `estimation_outcomes` (localtime timestamps).

| Time | Plate (scale truth) | Outcome | Estimate |
|---|---|---|---|
| 18:35:50 | 208 g white rice | success | white_rice 603 cm³ → **440 g / 141 g carbs** |
| 18:36:47 | + fried brussels sprouts = 309 g | refused `noFoodVolumeRecovered` (white_rice 0 cm³) | — |
| 18:36:49 | same plate | refused `noFoodPixels` | — |
| 18:37:40 | + squash & pumpkin = 551 g | success | carrot 45 g + mixed_vegetables 350 g = **395 g / 17.7 g carbs** |

Readings:

- **Rice-only over-read is 2.1× by mass** (440 vs 208 g; 603 cm³ carved vs
  ~285 cm³ at FAO cooked-rice density). This is the expected uncalibrated
  β = 1.0 upward bias (model-production "uncalibrated honesty") plus
  height-field over-carve on a mounded pile. Prime β_c calibration datum.
- **Brussels sprouts are effectively out-of-palette** (fried, dark): the
  segmenter returned a rice sliver then nothing — same failure family as the
  pumpkin session (unrecognised-food-estimated-as-residual-sliver). On the
  post-gate binary these refusals surface as `unrecognisedFood`.
- **Layered plates break the nadir path**: with vegetables on top, the rice
  disappeared entirely from the 551 g capture (subsumed into
  mixed_vegetables), so the true carb load (~58 g from 208 g cooked rice)
  read as 17.7 g. Squash/pumpkin chunks read as `carrot` (orange). Occlusion
  is structural for single-nadir capture — no segmenter fixes a food that is
  not visible; flag for the estimation roadmap (multi-view / user-assisted
  layering).
- Earlier same day, 17:27: pumpkin-only plate — 3 refusals + one "cheese
  18 cm³" estimate from a 0.21 % sliver; full analysis in
  `specs/bugfixes/unrecognised-food-estimated-as-residual-sliver/report.md`.
- **The 208 g rice bundle does not replay, and the capture itself is bad.**
  `1785054950406-success.fixture` is still on the device and pulls fine
  (194.9 MB, stamp `ab812dc3aa9d`), but `FixtureLoader` loads **zero meals**
  from it — `make harness-accuracy` over a directory containing it reports one
  fewer meal than files present, with no error. The two bread-session bundles
  from the same era (`1785135663727`, `1785901032716`) load normally, so it is
  not an era-wide format problem.

  **Diagnosed 2026-08-05 at the depth level** (support-plane-reference
  Decision 31). `tools/fixture_slice.py` cuts it cleanly — the loader failure is
  not a slice-level one — but **41 %** of the frame and **43.2 %** of the food
  mask carry ARKit's low confidence, against 22.7 %/0.0 % and 0.1 %/0.0 % on the
  two bread captures. The discarded samples are the near ones (median 247.9 mm
  against the surviving 277.8 mm): τ_conf removes the rice mound and leaves the
  flat remnant around it, so the best support-plane candidate reports the food
  as 9.0 mm *below* its own plane. The bundle still returned a "success" and
  603 cm³ at capture time, which is the lesson worth carrying — **an estimate
  is no evidence the depth frame was any good**. The slice is committed as a
  rejected fixture in `SupportPlaneCorpusMeasurementTests` so the exclusion is
  reproducible. Don't re-pull it expecting it to work, and don't re-slice it
  expecting it to serve as a non-flat anchor.

Follow-ups seeded by this session:

- Mass readout in the UI (specs/ui/mass-readout) so scale validation is
  real-time.
- These weighed plates are benchmark-meal material (BenchmarkView →
  weighed fidelity); logging them there scores every future model/β change
  against today's truth.

## 2026-08-04 — device session, speckle verdict (no weighed truth)

Qualitative pass during the roadmap §2 device session; no scale truth taken, so
nothing here is a calibration datum.

- **Overlay speckle is gone.** Developer verdict on device: "speckles
  DEFINITELY gone". Attributable to the shipped deterministic
  connected-component cleanup in `Segmentation/PostProcessing.swift`
  (`estimation-quality` → `tasks-mask-post-processing-cleanup`, all ticked)
  running against the promoted `coreml_ab812dc3aa9d` model — **not** to the new
  training recipe, which has not been run
  (`tasks-segmenter-training-pipeline` task 6 is still open). So
  `tasks-segmenter-training-pipeline` task 7 stays open: it is the acceptance
  gate for the *retrained* model, and ticking it on this evidence would credit a
  run that never happened. *(Superseded: the developer closed task 7 on
  2026-08-13 — see that session's entry.)*
- **Estimation quality improved substantially but is not yet at target.**
  Developer verdict: "improved HUGELY since this bugfix, albeit is not yet as
  accurate as hoped". No numbers — this session took no weighed truth, so the
  gap is an impression, not a measurement.
- **Follow-up:** the only way to move that verdict from impression to number is
  the accuracy loop in `docs/roadmap.md` §4 — a truth manifest joined at
  evaluation time plus the append-only per-fixture error log keyed on
  `(fixture_id, segmenter_sha)`. Until that lands, "not as accurate as hoped"
  cannot be attributed between the segmenter, β = 1.0, the carve, or the
  support-plane offset. Weigh the next session's plates.

## 2026-08-05 — raw sweet potato, two-view + card: refused (correct), no truth taken

Build `6db23e7-20260805-115608` (Release + `coreml_ab812dc3aa9d`), mode=double, five shutter
attempts 12:53:01–12:53:20. Log at `/tmp/medata-device.log`; bundles
`1785898381149`, `1785898392365`, `1785898394289`, `1785898400083`.

**Outcome: every attempt refused. That is the correct behaviour, not a defect.** A raw sweet
potato has no target class anywhere in the system:

- The v2 segmenter palette's 25 solid classes are cooked staples. The only potato channels are
  `potato_boiled` and `potato_mashed`; there is no raw-potato and no sweet-potato class.
- The bundled food database agrees — all 33 `class_id` rows, and the only raw entries are
  `apple`, `banana`, `tomato`. Even `carrot` is "Carrot (boiled)".
- Both training corpora (FoodSeg103, FoodRec2022) are prepared-meal datasets. A whole raw root
  vegetable is out of distribution, not merely unseen.

The segmenter said so plainly: `foodCoveragePercent=0 topClass=33 topClassPercent=94
distinctClasses=3` — class 33 is `background`, so 94 % of the frame read as "not food".

**Two different refusal reasons for one scene, and the mechanism matters.** Attempt 1 refused
`unrecognisedFood`; attempts 2–5 refused `noFoodPixels`. The split is not random:
`Pipeline.estimate` fits the support plane from `captureResult.preShutterFoodMask` at Stage D,
**before** it ever runs its own segmenter.

- No fresh pre-shutter mask → the plane fit proceeds, the pipeline reaches segmentation, logs
  `event=segmenter.mask`, and the recognised-food gate returns `unrecognisedFood`. Bundle
  **205 MB** (full probability tensor).
- Fresh but empty pre-shutter mask → `supportplane.end failure=emptyFoodMask` short-circuits to
  `noFoodPixels` before segmentation. No `segmenter.mask` line, no probs, no argmax. Bundle
  **3.6 MB**.

So the refusal the user sees depends on whether the live preview happened to have published a
mask at the shutter instant. Worth unifying: same scene, same cause, two messages.

**The diagnostic gap this creates.** An `emptyFoodMask` refusal is decided by the *pre-shutter
preview* segmenter, and that mask is recorded nowhere — the bundle carries no probs, no argmax
and no mask. The refusal therefore cannot be replayed or second-guessed offline, which is the
opposite of what the recorder exists for. Recording the pre-shutter mask on this refusal path
would cost a few KB. Filed against `capture-bundle-recorder`.

Also seen once: `capture.end stage=oblique success=false error=worldTrackingDegraded` at
12:53:15 — one oblique frame lost to ARKit tracking, recovered on the next tap. Not investigated.

**Not a truth datum:** nothing was weighed and every attempt refused, so this session contributes
no calibration evidence — only the coverage finding above.

## 2026-08-05 — 2 slices multigrain bread, weighed: independent confirmation of the 26.1 mm plane error

Build `6db23e7-20260805-115608`. **Truth from the developer: ~80 g, ~34 g carbs**, unbuttered.
Two captures ~30 s apart on the same physical scene.

### Capture A — single-view LiDAR (`1785901032716`), class CORRECT, volume 3.6x over

| | Value | Truth |
|---|---|---|
| Class | `bread_wholemeal` ✓ | multigrain bread |
| Volume | 714.84 cm³ | ~200 cm³ (80 g ÷ 0.400 g/cm³) |
| Mass | 285.94 g | 80 g — **3.57x** |
| Carbs | 108.66 g | 34 g — **3.20x** |

Density (0.400, MEASURED) and β (1.0) are both correct, and the class is right, so the entire
error is volume. Solving `(h + 26.1) / h = 3.57` for the plane offset already measured in
`specs/estimation/support-plane-reference/requirements-notes.md` gives an implied true slice
thickness of **10.1 mm**, against the ~10.9 mm that analysis derived from a *different* capture
(`1785135663727`). Implied footprint 197 cm², i.e. ~14 x 14 cm for two slices side by side —
physically right.

**So this is a second, independent, weighed-truth reproduction of the 26.1 mm support-plane
error, agreeing to within about a millimetre.** The defect is no longer inferred from one
capture. `planeResidualMm` was 1.97 with 1,286,181 of 1,478,354 candidates as inliers — the fit
is *confident and wrong*, which is the signature: RANSAC maximises inlier count and the worktop
wins on area.

Flat food is the worst case, and bread is a carb staple. A constant height offset is
proportionally largest on the thinnest food, so the dish type most likely to be photographed is
the one most over-read.

### Capture B — two-view SfS (`1785901065701`), class WRONG, volume 4x under

| | Value | Truth |
|---|---|---|
| Class | `carrot` ✗ | multigrain bread |
| Volume | 46.70 cm³ | ~200 cm³ |
| Mass | 34.09 g | 80 g |
| Carbs | **1.50 g** | 34 g — **23x under** |

`scaleSource=card+lidar`, `cardFallback=false`, so the ID-1 card was detected and used. Two
distinct failures compounding: the SfS carve recovered a quarter of the volume, and the class was
wrong in the direction that hides it — `carrot` at 3.2 g carbs/100 g reads a bread-sized object as
nearly carb-free. A 23x UNDER-read is the dangerous direction for a dosing tool; the single-view
3.2x over-read at least errs safe.

### The finding neither capture shows alone: classification is unstable run-to-run

Captures A and B are the same bread, same worktop, ~30 s apart, and the nadir frames classified
**differently** — `bread_wholemeal` then `carrot`. Nadir food coverage was 17 % then 13 %.
Multigrain crust is brown-orange and `carrot` is the orange class; the same confusion produced
"squash/pumpkin read as carrot" in the 2026-07-26 session. This is not a two-view-path defect —
it is the segmenter giving a different answer to the same question, and it belongs with
`estimation/estimation-quality`'s run-to-run variance work rather than with the carve.

## 2026-08-05 09:09–09:20 UTC — four weighed truths, all on the wrong path

Build carrying `coreml_ab812dc3aa9d`. 49 attempts, 3 successes. **Every weighed truth landed on
`two_view_sfs`; all 22 `single_view_lidar` attempts refused.** Raw notes for integration.

### The four events

| Attempt | Truth | Estimate | Error | Class | Path |
|---|---|---|---|---|---|
| bowl of prawns (09:09–09:12) | — | refused | `noFoodPixels` ×many, one `unrecognisedFood` | — | mixed |
| `1785921329668` bread | 196 g | 20.7 g | **9.5× under** | `bread_white` ✓ | two-view |
| `1785921526968` heaped rice, **lipped plate** | 245 g | 841 g | **3.43× over** | `carrot` + `mixed_vegetables` ✗ | two-view |
| `1785921628874` white rice | 320 g | 31.4 g | **10.2× under** | `white_rice` ✓ | two-view |

Full decompositions:

- `1785921329668` — `bread_white` 54.6 cm³ / 20.7 g / 10.0 g carbs, MEASURED density.
  plane residual 2.47 mm, inliers 599,779 / 1,081,362, nadir tilt 1.9°,
  foodRegionCoverage 99.6 %, segNadir foodCoverage 9 %.
- `1785921526968` — `carrot` 260.0 cm³ / 189.8 g / 8.4 g carbs (FAO_DENS) **plus**
  `mixed_vegetables` 1002.1 cm³ / 651.4 g / 29.3 g carbs (MEASURED). Total 1262 cm³ / 841 g /
  37.7 g carbs. plane residual 2.32 mm, inliers 23,791 / **30,576**, nadir tilt 2.4°,
  **foodRegionCoverage 0 %**, segNadir foodCoverage **0 %**.
- `1785921628874` — `white_rice` 43.0 cm³ / 31.4 g / 10.0 g carbs, FAO_DENS.
  plane residual 2.75 mm, inliers 158,972 / 575,060, nadir tilt 3.5 °,
  foodRegionCoverage 88.9 %, segNadir foodCoverage 6 %.

All three: `scaleSource = card+lidar`, `cardFallback = false`, `sigmaView = 0.75`.

Bundles on device: `1785921329668-success.fixture` (390.5 MB), `1785921526968-success.fixture`
(390.3 MB), `1785921628874-success.fixture` (389.8 MB), plus `1785921175528-refused.fixture`
(198.9 MB, the prawn bowl's `unrecognisedFood`).

### What the numbers say

**The two-view carve under-reads by an order of magnitude, not a margin.** 9.5× and 10.2×, both
with the class *correct*, so this is the carve and not segmentation. The previously recorded figure
was ~4× (2026-08-05 bread session). Belongs to `bugfixes/two-view-carve-no-volume`, not to
`support-plane-reference`.

**Carbs, which is the number that matters:** white rice 320 g → 10.0 g carbs reported against
~90 g expected for cooked rice. The lipped plate reported 37.7 g against ~69 g expected, so mass
was 3.4× *over* while carbs were ~45 % *under* — the wrong classes carry much lower carb density,
and the two errors partly cancel in a way that hides both.

**`1785921526968` is anomalous beyond the misclassification.** `foodRegionCoveragePercent: 0` and
segmenter `foodCoveragePercent: 0`, with `planeCandidateCount` 30,576 against ~1 M on the
neighbouring captures — yet it returned a success carrying 1,262 cm³. A success recorded on a frame
with no confident depth over the food. Worth its own look; not diagnosed here.

**The bowl attempts prove nothing about bowls.** Prawns are not among the 25 solid palette classes,
so segmentation refused before plane selection was ever reached. Same family as the raw sweet potato
(2026-08-05 earlier entry). A bowl capture can only exercise the support-plane fallback if the food
is in palette — rice, pasta or cereal.

**`worldTrackingDegraded` refused 13 of 49 attempts.** Roughly a quarter of shutter presses lost to
ARKit tracking. Not investigated; it sets the realistic yield of a weighed sitting at about half the
presses.

### Consequence for `support-plane-reference`

Four weighed truths, zero usable evidence — the feature corrects the *depth-derived* plane, and no
capture reached that path. `1785921526968` is nonetheless the only lipped-plate capture in
existence, and Decision 14's radial-band and support-visibility mitigations have no field evidence
of any kind. Recorded as Reqs 7.10 (a weighed single-view lipped-plate case) and 7.11 (a weighed
capture counts as evidence only where it completed single-view), with the session written up in
that spec's `prerequisites.md`.

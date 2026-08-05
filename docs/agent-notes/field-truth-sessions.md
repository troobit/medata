# Field-truth capture sessions (weighed ground truth)

Scale-weighed plates captured on device, with the app's estimates — the
evidence base for β_c calibration and class-coverage decisions. Pull the
outcome rows and bundles per the devicectl recipe in
`device-build-and-test.md`.

## 2026-07-26 — staged plate, model `coreml_ab812dc3aa9d` (palette v2)

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
  run that never happened.
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

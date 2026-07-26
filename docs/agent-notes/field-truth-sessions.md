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

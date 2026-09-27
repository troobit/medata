# Mask spike: EdgeTAM vs deeplab_mnv3 vs Vision foreground on the leak-free anchor

Question (docs/research/on-device-models-2026-09.md, "Masks" one-day experiment; MD-29):
does a promptable class-agnostic model give better food masks than the shipping
`deeplab_mnv3` on the 182-image leak-free anchor, with prompts the app could actually
produce? Pass line from the report: **EdgeTAM beats deeplab by >= 0.05 food IoU with app
prompts, without losing boundary F.**

Date 2026-09-27. Repo `fcf0186`. Mac: Apple M5 Pro, macOS 26.6.2. All inference on CPU
(4 torch threads) so it did not contend with the MPS training queue. Checkpoint of record:
`tools/segmenter/build/checkpoint_r3_combined_noweight.pt` (deeplab_mnv3, 36 channels).
EdgeTAM: github.com/facebookresearch/EdgeTAM `7711e01`, `checkpoints/edgetam.pt` (ships in
the repo), image mode only, torch 2.14.0 / timm 1.0.30.

## Verdict

**Fail.** With the prompt source the app has today (one box + centre point per connected
component of deeplab's food mask) EdgeTAM scores **0.791 food IoU vs deeplab's 0.882
(-0.091)**; it loses on 121 of 182 images and wins on 47. The best app-prompt variant tried
(a prompt per class-aware component of deeplab's label map, multimask best-score) reaches
0.862 (-0.020) — still below deeplab, though it lifts boundary F from 0.459 to 0.573. With
oracle boxes EdgeTAM reaches 0.911 food IoU / 0.861 per-prompt IoU, so the model can
delineate food; the bottleneck is the prompt, and the prompt comes from deeplab.

Apple Vision's foreground instance mask (zero bytes, 17 ms) is well below both at 0.734:
it lifts the plate with the food.

## Results

Metrics are class-agnostic, scored in one space: image resized so the longer side is 513
(the segmenter's working resolution). GT food = every label except background (33).
Region IoU: GT regions are 8-connected components (>= 64 px) of the GT label map, each
matched to the predicted component with the largest intersection. Boundary F: DAVIS
boundary F at 2 px on the binary food mask. Means are over 182 images (food IoU, boundary
F) and 900 GT regions (region IoU). Per-prompt IoU is each EdgeTAM mask against its
best-overlap GT region (oracle: against its own region).

| Method | Prompt regime | Food IoU | Region IoU (union mask) | Boundary F (2 px) | Per-prompt IoU |
|---|---|---|---|---|---|
| deeplab_mnv3 (argmax != background) | — | **0.882** | 0.230 | 0.459 | — |
| deeplab_mnv3, components of the label map (class-aware) | — | — | 0.488 | — | — |
| Vision `VNGenerateForegroundInstanceMaskRequest`, all instances | — | 0.734 | 0.159 | 0.405 | — |
| EdgeTAM | app: box + centre point per deeplab food-mask component (275 prompts) | 0.791 | 0.247 | 0.457 | 0.525 |
| EdgeTAM | app: box only | 0.806 | 0.235 | 0.487 | 0.505 |
| EdgeTAM | app: centre point only | 0.304 | 0.151 | 0.209 | 0.485 |
| EdgeTAM | app: box + point, multimask, keep best score | 0.793 | 0.241 | 0.465 | 0.527 |
| EdgeTAM | app: box + point per deeplab label-map component (1597 prompts) | 0.848 | 0.278 | 0.521 | 0.338 |
| EdgeTAM | app: label-map components, multimask, keep best score | 0.862 | 0.244 | **0.573** | 0.355 |
| EdgeTAM | oracle: box + centre point per GT region (900 prompts) | **0.911** | **0.314** | **0.607** | **0.861** |

Per-image delta in food IoU, EdgeTAM minus deeplab (wins / losses at > 0.01):

| Regime | Mean | Median | Wins | Losses |
|---|---|---|---|---|
| app, box + point | -0.091 | -0.045 | 47 | 121 |
| app, box only | -0.076 | -0.026 | 51 | 102 |
| app, label-map components | -0.034 | -0.016 | 49 | 97 |
| app, label-map components, multimask | -0.020 | +0.001 | 75 | 72 |

Shortlist hit rate (GT class in the top-3 of deeplab's softmax mean-pooled inside a region):

| Pooling region | Hit rate |
|---|---|
| GT regions (900) | 0.824 |
| EdgeTAM app masks, box + point (275) | 0.778 |
| EdgeTAM app masks, label-map components (1597) | 0.783 |
| EdgeTAM oracle masks (900) | 0.827 |

The shortlist bar in the report is >= 80 % of anchor regions; deeplab's own pooling over
true regions sits at 82 %, so option (i) of the report (class from deeplab, mask from a
promptable model) does not lose the shortlist when the mask is right.

## Wall-clock per image (CPU, this Mac)

| Step | ms |
|---|---|
| deeplab_mnv3 forward at 513x513 | 127 |
| Vision foreground request (scoring-space PNG input) | 17 |
| EdgeTAM `set_image` (RepViT-M1 encoder at 1024x1024) | 275–330 |
| EdgeTAM per prompt (prompt encoder + mask decoder) | 29–36 |

EdgeTAM with app prompts is one encode plus 1.5 prompts per image (275 / 182), about
320 ms; with label-map components it is 8.8 prompts per image, about 600 ms. CPU numbers
only; they say nothing about the ANE.

## Why it loses

Two failure modes, both caused by deeplab merging every food on the plate into one
component (130 of the 275 app prompts have a box covering >= 60 % of the frame; their mean
per-prompt IoU is 0.51 against 0.79 for boxes covering 10–30 %):

1. **Whole-frame box + centre point → one item.** The point lands on one food and EdgeTAM
   returns that food (examples/loss_-0.55_00000830.png: the bread slice, not the plate).
2. **Whole-frame box → a degenerate plate mask.** With no useful box the decoder returns a
   speckled, low-stability mask of the plate (examples/loss_-0.62_00001975.png,
   loss_-0.62_00000595.png). Identical on MPS, so not a CPU numerics artefact; the
   multimask alternatives with better IoU carry a lower predicted score, so "keep the best
   score" does not rescue it.

Where deeplab already separates the foods, EdgeTAM refines every boundary
(examples/win_+0.17_00003082.png, 0.76 → 0.94). Splitting the prompt by deeplab's label
map recovers most of the gap (0.791 → 0.862) because touching foods of different classes
become separate boxes, but a wrongly labelled fragment becomes a wrong prompt too.

Vision's foreground request treats the plate as the salient object; on close-up crops it
lifts the whole frame.

## Reading

- On this anchor food already covers most of the frame (deeplab's food IoU is 0.88 with a
  class-mean IoU of 0.42), so the class-agnostic food IoU has little headroom; the
  interesting numbers are region IoU and boundary F, where deeplab is weak (0.23 / 0.46
  on the union mask) and EdgeTAM with oracle prompts is much better (0.31 / 0.61).
- The per-region numbers on the union mask are low for every method because the metric
  matches GT regions to components of the binary mask: a plate of touching foods is one
  component. deeplab's class-aware components score 0.488 on the same metric.
- A promptable model only pays off with a better prompt source than deeplab's argmax
  components. The candidates named in the report — Vision instance boxes, a point grid —
  were not run here; Vision's union mask suggests its instances are plate-level, not
  food-level.

## What was not done

- MobileSAM: not needed, EdgeTAM ran.
- No Core ML conversion, no device run, no ANE residency check.
- No Vision-instance-box or point-grid prompt regimes.
- `make spell` (`tools/check_spelling.sh`) scans only `*.swift` and `*.xcstrings`; this file
  was checked by hand against its banned-word list.

## Commands

```
cd tools/segmenter/spike_masks
python3.13 -m venv .venv && .venv/bin/pip install torch torchvision pillow numpy scipy
git clone --depth 1 https://github.com/facebookresearch/EdgeTAM.git   # checkpoint is in the repo
.venv/bin/pip install -e EdgeTAM timm   # timm downloads repvit_m1 weights on first build
.venv/bin/python run_deeplab.py         # baseline masks, label maps, probs, prompts, shortlist
.venv/bin/python run_vision.py          # compiles vision_foreground.swift, writes out/vision/
.venv/bin/python run_edgetam.py app oracle app_labels app:box app:point app:multi app_labels:multi
.venv/bin/python report.py              # table, out/results.json, examples/
```

Outputs under `out/` (gitignored): per-method masks, `results.json`, per-prompt JSON,
timings. `scoring.py` is the single scoring module all three methods share.

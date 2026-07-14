# Segmenter improvement research — the ~0.40 mIoU plateau and what to try next

**Date:** 2026-07-10
**Scope:** written analysis only (estimation-quality PRD, "Segmentation approach research" context). No runtime or training code changes here; the training-recipe implementation is the sibling "Segmenter training pipeline" context, and the runtime speckle cleanup is the "Mask post-processing cleanup" context.
**Prior conclusion honoured:** the YCbCr→RGB / stride / pixel-format path was audited clean 2026-07-06 — the artefact is model quality plus missing spatial regularisation, **not** a format bug. Nothing below re-opens that.

## 1. Where the model stands (evidence)

Two real models have shipped, both under Decision 11 developer-phase overrides
(`docs/agent-notes/model-production.md`):

| Checkpoint | Recipe | Held-out mean food-class IoU |
| --- | --- | --- |
| `0295ea61edd9` (2026-07-05) | square-resize, hflip + scale-up crop, poly-0.9 lr | 0.4259 |
| `24e0b022241a` (2026-07-06, shipped) | letterbox parity + independent v-flip added | 0.4054 |

The strict export gate is mean ≥ 0.60 AND every carb-priority staple ≥ 0.50
(`tools/segmenter/validation.py`, `MEAN_IOU_BAR` / `CARB_PRIORITY_IOU_BAR`).
(Bars since re-derived to 0.48/0.45 — segmenter-foundation D5/D14.)
The earlier fixed-lr, no-augmentation baseline plateaued at ~0.34 by epoch 22/60;
the recipe improvements since have moved the number to 0.40–0.43 and stalled.

Per-class IoU for the shipped model (`tools/segmenter/build/lineage.json`,
`metrics.per_class_iou`) shows a very characteristic spread:

| Band | Classes (IoU) |
| --- | --- |
| Strong | background 0.927, broccoli 0.814, carrot 0.700, peas 0.636, tomato 0.635, white_rice 0.602 |
| Middling | chips_fries 0.567, pasta 0.554, fruit_juice 0.549, mixed_vegetables 0.522, potato_boiled 0.465, beef 0.444, bread_white 0.431 |
| Collapsed | apple 0.197, pork 0.193, milk 0.176, wine 0.175, cheese 0.068, **tea 0.017** |
| Absent from held-out | brown_rice, bread_wholemeal, potato_mashed (plus water, beer) — recorded as unprovable shortfalls |

Two separate readings of the 0.405 mean follow from this:

- **The mean is dragged by the tail, not the staples.** The carb-priority staples
  present sit at 0.43–0.60; the mean is pulled to 0.40 by rare/low-contrast
  classes (cheese, tea, milk, wine, pork, apple) that have nearly collapsed.
- **The staples still individually miss the 0.50 floor** (bread_white 0.431,
  potato_boiled 0.465), and three staples cannot be proven at all because the
  FoodSeg103 remap leaves them without held-out examples.

## 2. Diagnosis: why the plateau

The concrete contributing factors, all present in `tools/segmenter/train.py`
today, ranked by how load-bearing the evidence says they are:

### 2.1 Unweighted cross-entropy over a heavily imbalanced 35-class palette (most load-bearing)

`train.py:511` is a plain `criterion = nn.CrossEntropyLoss()` — no class
weights, no focal term, no region-overlap term. Every pixel contributes
equally, and pixel counts are extremely skewed: background dominates FoodSeg103
masks (letterbox padding is additionally labelled background,
`PALETTE_BACKGROUND = 32`), and on-device masks are 92–99% background with
`topClass=34`. Under that skew, unweighted CE minimises loss fastest by getting
the dominant classes right and letting rare classes ride; the gradient signal
for a class like tea or cheese is a rounding error per batch.

The per-class IoU spread in §1 is exactly the signature of this failure mode:
classes that are frequent, large, and visually distinctive (background,
broccoli, carrot, white_rice) do fine; classes that are rare, thin, or
low-contrast collapse towards zero. The mean cannot pass 0.60 while a third of
the evaluated classes sit below 0.2 — and no amount of geometry augmentation or
lr tuning changes the loss's indifference to them.

### 2.2 Small effective training set per class (~5.5k images, 103→35 remap)

The train split is 5,553 images (`data/foodseg103_remapped`, split seed 1234;
`docs/agent-notes/dataset-strategy.md` §5). After the 103→35 remap, several
palette classes inherit only a handful of FoodSeg103 categories — three
carb-priority staples (brown_rice, bread_wholemeal, potato_mashed) have so few
examples they do not even appear in the 854-image held-out split. The 8 liquid
channels train on little-to-no data by design (`docs/ml-training.md` §2), yet
liquids present in held-out (tea 0.017, milk 0.176) still count towards the
food-class mean, deflating it. This is a data-coverage ceiling that no loss
function fully removes; it caps the tail and makes the mean structurally hard
to lift. It also interacts with 2.1: rare classes are precisely the ones
unweighted CE ignores.

### 2.3 Geometry-only augmentation (no photometric variation)

`FoodSegDataset._letterbox_pair` applies flips, mild scale-down jitter and
random placement — geometry only. The docstring forbids colour jitter "without
a lockstep serve-side decision", but that caveat conflates two different
things: the *normalisation/colour-space contract* (which must stay matched to
`SegmenterPreProcessor`, and does) and *photometric augmentation of training
inputs* (which changes only what the model sees during training and cannot
introduce train/serve skew — if anything it widens the appearance distribution
towards real device captures, whose lighting differs from FoodSeg103
photography). With ~5.5k images and no appearance variation, the model
memorises the dataset's colour statistics — consistent with the original
baseline overfitting (train loss falling while val mIoU plateaued at 0.34) and
with low-contrast classes (cheese, milk, pork) collapsing.

### 2.4 MobileNetV3-Large capacity (real, but fixed by the budget)

DeepLabV3 + MobileNetV3-Large is 11.03 M params = 22.1 MB FP16, deliberately
chosen (pipeline Decision 25) to fit `SegmenterWeightsBudget.maxBytes`
(24 MiB, `MedataCore/Sources/Segmentation/CoreMLSegmenter.swift:157`, Decision
13) with ANE residency and ≤ 250 ms/view. It is an accuracy-for-feasibility
trade: this backbone family scores roughly 10–15 mIoU points below large
research backbones on comparable benchmarks. Capacity therefore bounds the
ceiling, but it does not explain the *shape* of the failure (a capacity-bound
model degrades broadly; ours bifurcates into strong and collapsed classes,
which is an imbalance signature). Treat capacity as the last lever, not the
first.

### 2.5 What is NOT a factor

- **Colour-space / stride / byte layout** — audited clean 2026-07-06.
- **Train/serve geometry skew** — closed by the letterbox recipe
  (`_letterbox_pair` matches the runtime letterbox; model `24e0b022241a`).
- **Checkpoint↔artefact drift** — export oracle gates pass (argmax agreement
  ≥ 0.9985, FP16 logit drift 0.13–0.30; model-production Decision 14).

## 3. The "linear stripes of spots" symptom

The overlay speckle is the *visible* form of the same two absences: no
class-imbalance handling in training, and no spatial regularisation anywhere in
the chain. The mechanism, end to end:

1. **Low-margin logits on food pixels.** An unweighted-CE model trained on
   background-dominated data produces confident background and near-tie logits
   among plausible food classes elsewhere. The measured healthy FP16 export
   drift (0.13–0.30 abs logit) is the same order as those margins.
2. **Per-pixel argmax with no neighbourhood term.**
   `MedataCore/Sources/Segmentation/PostProcessing.swift` does softmax → crop →
   bilinear resize → per-pixel argmax. Nothing in training (no dice/region
   loss, no boundary loss) or inference (no majority filter, no
   connected-component cleanup, no CRF) couples a pixel's label to its
   neighbours', so near-tie pixels flip class independently — speckle.
3. **The "linear stripes" arrangement.** The network predicts logits on a
   coarse feature grid (output stride 16 for this DeepLabV3 head) that is
   bilinearly upsampled to 513×513, then cropped and bilinearly resized again
   to the capture resolution. Argmax over smoothly interpolated near-tie logits
   changes winner along the interpolation lattice, producing regularly spaced
   runs of flipped pixels — stripes of spots aligned with the feature grid, not
   with image content. That is a resampling-of-ties artefact, not a byte-layout
   one, consistent with the prior "model quality, not a format bug" conclusion.

Consequences for the fix: training-side, class-imbalance-aware and
region-overlap losses raise the logit margins (speckle shrinks at the source);
runtime-side, a deterministic minimum-region/majority cleanup on the argmax map
(the PRD's "Mask post-processing cleanup" context) removes whatever speckle
remains regardless of model quality. Both are needed; neither re-opens the
format audit.

## 4. Ranked recommendations (highest expected IoU-per-effort first)

All training-recipe items land as **opt-in flags defaulting to the current
recipe**, recorded in checkpoint + `build/lineage.json` `train_config`, per the
sibling training-pipeline context. Never edit `train.py` while a run is live.

| # | Change | Expected effect | Cost | Risk |
| --- | --- | --- | --- | --- |
| 1 | Class-weighted CE | +0.03–0.08 mean; lifts collapsed tail | Very low | Low |
| 2 | Combined CE + dice/Tversky | +0.02–0.05 on top; higher margins, less speckle | Low | Low–medium |
| 3 | Photometric augmentation | +0.01–0.03 offline; larger on-device gain | Low | Low |
| 4 | Rare-class (repeat-factor) sampling | +0.01–0.03 on tail; helps absent staples | Medium | Medium |
| 5 | Focal loss (variant of 1/2) | Similar band to 1; tune γ | Low | Medium |
| 6 | Architecture/backbone change | Potentially +0.05–0.10 | High | High |

### 4.1 Class-weighted cross-entropy (do first)

Weight each class by capped inverse frequency computed once from the train
split's mask pixel counts — e.g. `w_c ∝ (1/√freq_c)` normalised, capped at
~10× the median weight so tea/liquid channels cannot destabilise training.
Directly attacks §2.1. This is the standard first move for imbalanced
segmentation and the cheapest: one flag, one weight vector.
**Files:** `tools/segmenter/train.py` (flag + criterion wiring), a new
torch-free helper for weight derivation (e.g. `tools/segmenter/losses.py`),
tests under `tools/segmenter/tests/`.

### 4.2 Combined loss: weighted CE + dice (or Tversky)

Dice/Tversky optimises region overlap per class, so a rare class's few pixels
matter as much as background's millions; it also rewards coherent regions over
scattered ones, raising argmax margins (speckle shrinks at the source, §3).
Standard combination is `L = L_wCE + λ·L_dice` with λ = 1; Tversky (α > β)
if false negatives on staples dominate after 4.1. Compute dice on softmax
probabilities per class, skipping classes absent from the batch.
**Files:** same as 4.1 (`--loss combined` variant in `train.py` + helper +
tests).

### 4.3 Photometric augmentation (image only, never the mask)

Random brightness/contrast/saturation/hue jitter (mild: e.g. ±20% brightness/
contrast, ±10% saturation, small hue shift) applied to the PIL image before
normalisation. Addresses §2.3; expected to matter *more* on device than on the
held-out bench, since it widens the appearance distribution towards real
captures — the offline bench under-reports this one, which is exactly the
letterbox lesson (`24e0b022241a` scored lower offline but was expected to be
better on device). The existing docstring caveat about colour jitter should be
restated: normalisation stays untouched, so serve parity is preserved.
**Files:** `tools/segmenter/train.py` (`FoodSegDataset.__getitem__` /
`_letterbox_pair`, behind a flag), tests for the flag plumbing.

### 4.4 Rare-class balanced sampling (repeat-factor)

Oversample images containing rare classes (LVIS-style repeat-factor sampling:
repeat an image proportional to `max_c √(t/freq_c)` over the classes it
contains). Complements 4.1 — weighting fixes the per-pixel gradient, sampling
fixes how often rare classes are seen at all. Also the only training-side lever
for classes so thin they are absent from held-out. Medium cost because it
touches the DataLoader/sampler path and must respect the spawn-pickling
gotchas.
**Files:** `tools/segmenter/train.py` (`_make_loader` gains a
`WeightedRandomSampler` path), torch-free repeat-factor computation in the
losses/weights helper, tests.

### 4.5 Focal loss

`FL = −(1−p_t)^γ log p_t` down-weights easy pixels (background) automatically,
without a precomputed weight table. Worth having as a selectable option in the
same `--loss` flag, but ranked below 4.1/4.2 because γ needs tuning per
dataset and weighted CE + dice usually matches or beats it on this kind of
skew — try it only if 4.1/4.2 stall.
**Files:** same helper + `train.py` flag as 4.1.

### 4.6 Architecture/backbone alternative (last; gated)

Evaluated against the hard constraints: ≤ 24 MiB FP16
(`SegmenterWeightsBudget.maxBytes`) and ANE residency (≤ 250 ms/view).

- **DeepLabV3+ style decoder on the current MobileNetV3-Large backbone** (add a
  low-level skip connection and a small decoder; effectively output stride 8
  detail at modest param cost, ~1–2 MB FP16 over the current 22.1 MB — tight
  but plausibly within budget after measuring). Best boundary/detail
  improvement per risk: stays a torchvision-family CNN, so the Core ML export
  path and ANE mapping remain boring. This is the recommended architecture
  candidate.
- **SegFormer-B0** (~3.8 M params ≈ 7.6 MB FP16 — comfortably within budget,
  and typically +5–10 mIoU over MobileNet-class CNNs on ADE20K-scale data).
  The catch is ANE residency: transformer attention ops convert but commonly
  fall back to GPU/CPU in Core ML, which silently blows the latency bar — the
  Xcode performance report check is mandatory before any commitment.
- **LR-ASPP MobileNetV3** (torchvision) is smaller/faster but strictly weaker
  than the current head — reject; the budget headroom is better spent on a
  decoder.

Any change here must keep the single-source-of-truth contract: the
architecture is built via `export.load_checkpoint` (Decision 28), so
**`tools/segmenter/export.py`** changes in lockstep with `train.py`, the
export gates (weight budget, 35 channels, PyTorch-oracle agreement) re-run,
and on-device ANE verification is a human-gated STOP. Per the PRD's process
note, an architecture swap is an estimation-subsystem redesign and goes
through a spec/decision-log gate, not directly through this lane.
**Files:** `tools/segmenter/export.py` + `tools/segmenter/train.py` (+ their
tests); no MedataCore changes so long as the head stays 35-channel in palette
order.

### Recommended first run

4.1 + 4.2 + 4.3 together (one flagged run: weighted CE + dice, photometric
augmentation on), same 60-epoch/poly-0.9/513 envelope, then `run_validation.py`
against the same seed-1234 held-out split. Add 4.4 in a second run if the tail
(and the absent staples) still lag. Hold 4.5/4.6 in reserve.

## 5. Carb-reading consistency and β coverage

Run-to-run carb variance for the same plate is a product of the deterministic
chain: mask → plane fit → volume → β → macros. Levers, with routing:

- **Mask speckle → silhouette instability (largest coupled win).** Speckle
  changes the silhouette between captures, which perturbs voxel carving
  directly. The deterministic minimum-region/majority cleanup is owned by this
  PRD's **Mask post-processing cleanup** context
  (`MedataCore/Sources/Segmentation/PostProcessing.swift`), and §4's
  margin-raising losses shrink it at the source.
- **Plane-fit inlier robustness.** Small inlier-set differences in
  `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` move the support
  plane and rescale every height/volume downstream. Conservative additive
  guards (deterministic inlier selection, outlier rejection) are owned by the
  **Estimation runtime consistency** context, as is voxel-carve boundary
  sensitivity in `MedataCore/Sources/Volume/`.
- **Fail closed on near-empty masks.** With 92–99% background masks, a
  handful of speckle pixels can currently drive a wildly variable estimate;
  refusing/flagging below a coverage threshold (existing `EstimationFailure`
  semantics) is also owned by the runtime-consistency context.
- **β coverage without new hand-measured data (data-gated; route, don't do).**
  Every class currently ships β = 1.0 `uncalibrated_unity`, so carb numbers are
  systematically over-estimated. Two existing specs own the fix from public
  data alone:
  - `specs/estimation/cross-dataset-calibration/` — MetaFood3D single-food 3D
    captures with per-object mass give the carb staples clean volume↔mass β
    samples, independent of the segmenter checkpoint; explicitly designed to
    need no human meal-weighing.
  - `specs/estimation/nutrition5k-calibration/` — Nutrition5k overhead RGB-D
    (~3.5k dishes, per-ingredient gravimetric mass) for population β via the
    device estimator path; gated on the partial dataset download.
  Both are STOP-flagged in the PRD; this document routes them rather than
  proposing edits. Note β = 1.0 is a *bias*, not a variance, so β work improves
  accuracy and cross-plate consistency, while the mask/geometry levers above
  are what reduce same-plate run-to-run variance.

## 6. Offline accept/reject metric for recipe variants

No device needed to compare variants. The instrument already exists:
`tools/segmenter/run_validation.py` runs a checkpoint over the fixed held-out
split (854 images, split seed 1234 — identical across runs) and records
`mean_iou`, `per_class_iou` and `carb_priority_iou` into
`tools/segmenter/build/lineage.json`. Evaluation is deterministic given a
checkpoint, so deltas between checkpoints are attributable to the recipe (plus
training seed noise, empirically ≲ 0.01 against recipe-level deltas of
0.03–0.09 seen so far).

**Accept a variant (worth an export + device deploy) when all of:**

1. Held-out mean food-class IoU ≥ **incumbent + 0.02** absolute (incumbent
   `24e0b022241a` = 0.4054, so ≥ 0.4254 today). +0.02 clears seed noise with
   margin while staying reachable per iteration.
2. **No carb-priority staple present in held-out regresses by more than 0.02**,
   and at least one currently-short staple (bread_white 0.431, potato_boiled
   0.465) moves towards its 0.50 floor. The staples gate the carb number; a
   mean bought by sacrificing a staple is a regression.
3. Export gates still pass (≤ 24 MiB FP16, 35 channels, oracle agreement) —
   `export.py` enforces these mechanically.

**Reject** anything that misses (1) or (2) — no deploy, iterate again.
Photometric-augmentation caveat: the offline bench under-reports device gains
(§4.3), so a variant that is flat offline (within ±0.01) but adds photometric
robustness may still justify a deploy — record that reasoning in the Decision
11 override if used.

The strict gate is unchanged: `export_eligible` remains mean ≥ 0.60 AND every
staple ≥ 0.50; the threshold above only governs which developer-phase
iterations are worth the export/deploy cycle under a Decision 11 override.
(Bars since re-derived to 0.48/0.45 — segmenter-foundation D5/D14.)
Optional future refinement (not landed here): a speckle proxy in
`run_validation.py` — mean count of sub-threshold connected components per
predicted mask — would track §3 directly alongside IoU.

## Sources

- `tools/segmenter/train.py` (loss at line 511; `_letterbox_pair`; recipe docstrings)
- `tools/segmenter/build/lineage.json` (shipped-model per-class IoU, shortfall, override)
- `tools/segmenter/validation.py`, `tools/segmenter/run_validation.py` (gate + held-out runner)
- `docs/agent-notes/model-production.md`, `docs/agent-notes/dataset-strategy.md`, `docs/agent-notes/class-palette.md`
- `docs/ml-training.md` §§2, 4, 5, 11
- `MedataCore/Sources/Segmentation/CoreMLSegmenter.swift` (`SegmenterWeightsBudget.maxBytes`), `PostProcessing.swift`
- `specs/estimation/estimation-quality/prd.md`; `specs/estimation/cross-dataset-calibration/`; `specs/estimation/nutrition5k-calibration/`

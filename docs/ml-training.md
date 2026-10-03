# ML training pipeline


Note, MIoU is "mean intersection over union".
> **To unblock the MVP now,** follow the ordered, time-boxed critical path in
> [`mvp-unblock-runbook.md`](mvp-unblock-runbook.md); it links back into the sections here for detail.
> Audience: anyone training or refining the on-device estimation models.
> Mixed background assumed — ML concepts get a brief sentence, then commands.
> Status: Sections 1–11 drafted (explanation + runbook). The dataset/training/
> fixture scripts named in §§3–5 now exist (`build_class_mapping.py`,
> `prepare_dataset.py`, `train.py`, `make_fixtures.py`), authored and
> smoke-tested on synthetic data.
> **Update 2026-07-06:** the real runs have happened — two real models have
> shipped (`0295ea61edd9`, 2026-07-05; letterbox-trained `24e0b022241a`,
> 2026-07-06), both trained locally on Apple-silicon MPS. See the §5
> developer-phase gate note for how they were validated.
> **Update 2026-07-16:** the co-occurrence retrain (segmenter-foundation
> tasks 18/19) was rejected — same-set regression vs the pinned model
> (Decision 24); the bundled model remains `24e0b022241a`.

This document is the end-to-end recipe for producing the two model artefacts that
the iOS app depends on at runtime:

1. **The segmenter** — a 35-class semantic segmentation network
   (`segmenter.mlpackage`) bundled into the iOS binary, run on the Apple Neural
   Engine. `export.py` writes it to
   `MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage` and
   `PipelineFactory.makeSegmenter` loads that exact name via `Bundle.module`
   (the loader-alignment gap is now closed — model-production tasks 1–2; see
   [`architecture.md`](architecture.md) §9).
2. **The β_c table** — a per-class bulk-correction factor baked into
   `cofid_db.sqlite`, applied to volume estimates before macro calculation.

Both are produced offline; neither trains, fine-tunes, or recalibrates on-device.

For project-level prerequisites (Apple Dev account, Xcode, device, fixtures repo)
see [`specs/estimation/pipeline/prerequisites.md`](../specs/estimation/pipeline/prerequisites.md). This
document is the ML-specific overlay on top of those.

For where this fits in the runtime wiring — what's already built versus what the
trained model unblocks — see
[`agent-notes/pipeline-wiring-status.md`](agent-notes/pipeline-wiring-status.md)
(only the trained checkpoint remained; real checkpoints have since shipped —
see the status note above).

## Contents

1. [Prerequisites & environment](#1-prerequisites--environment)
2. [The class palette](#2-the-class-palette)
3. [Dataset preparation](#3-dataset-preparation)
4. [Training the segmenter](#4-training-the-segmenter)
5. [Validating the segmenter](#5-validating-the-segmenter)
6. [Exporting to Core ML + TFLite](#6-exporting-to-core-ml--tflite)
7. [Bundling into the iOS app](#7-bundling-into-the-ios-app)
8. [Capturing gravimetric meal fixtures](#8-capturing-gravimetric-meal-fixtures)
9. [Bulk-correction calibration](#9-bulk-correction-calibration)
10. [End-to-end accuracy harness](#10-end-to-end-accuracy-harness)
11. [Iteration loop and segmenter coupling](#11-iteration-loop-and-segmenter-coupling)

---

## 1. Prerequisites & environment

[`specs/estimation/pipeline/prerequisites.md`](../specs/estimation/pipeline/prerequisites.md) is the
authoritative list of project prerequisites. This section adds the ML-specific
detail not duplicated there.

> **Human-gated stages (cannot be automated).** Sections 3, 4, 5 (the training/validation
> *run*), 6–7, and 8–10 below each need something no coding agent can supply — a dataset
> download, a CUDA GPU, a Mac with Xcode, a physical iPhone, or weighed meals. The surrounding
> code (loader, lineage, `export.py` gates, validation reporting, palette↔DB bake lock) is
> implemented; these stages produce the model and the on-device proof the MVP gate (Req 6.3)
> depends on. The consolidated, ordered checklist of exactly what a human must do — and which
> stages block the MVP versus are deferred — is
> [`specs/estimation/model-production/prerequisites.md`](../specs/estimation/model-production/prerequisites.md).
> Use that as the "what's left for me to do" list; use the sections below for the how.

### Hardware

| For | Hardware |
| --- | --- |
| Segmenter training | Local Apple-silicon Mac (M5 Pro-class, MPS) is a supported route: expect roughly 5–10× a mid-range CUDA card per epoch; run iteratively with `train.py --resume` (see §4 run hygiene). A Linux/Windows CUDA box (RTX 3060 12 GB or better) remains the faster alternative; smaller cards work with a smaller batch size. |
| Export to Core ML + TFLite | macOS 14+. `coremltools` requires Apple OS; cross-OS export is not supported. |
| On-device validation | iPhone 16 Pro (hardware floor — segmenter-foundation Decision 22, supersedes the Req 1.2 13 Pro Max floor; iOS 26.5+). Needed for the Apple Neural Engine residency check (Req 16.5) and per-stage latency bar (Req 16.2). |
| β_c gravimetric capture | Calibrated kitchen scale, 1 g resolution or finer; ID-1 reference card (any expired credit / library card); the same iPhone used for on-device validation. |

### Python environment

A single virtualenv covers both training and export. Training deps are added on
top of the existing export requirements in step 4.

```sh
uv venv tools/segmenter/.venv
source tools/segmenter/.venv/bin/activate
uv pip install -r tools/segmenter/requirements.txt
```

One venv covers training **and** export. `requirements.txt` pins `torch`,
`torchvision`, `coremltools>=8`, `ai-edge-torch`, `tensorflow`, `pillow`,
`numpy`.

Heads-up: `tensorflow` (pulled in by `ai-edge-torch` for TFLite validation) and
a CUDA-built PyTorch can occasionally conflict on the same machine. If you hit
that, treat it as a packaging bug to fix at the time — pin versions in
`requirements.txt` rather than splitting environments.

### Datasets

For the MVP, we rely entirely on public datasets. Building our own labelled
training set is a multi-month effort and is deliberately out of scope.

| Dataset | Licence | Use here | Source |
| --- | --- | --- | --- |
| FoodSeg103 | Apache 2.0 | Primary segmenter training + held-out test set | <https://xiongweiwu.github.io/foodseg103.html> |
| Food Recognition Benchmark 2022 | CC BY 4.0 | Merged-corpus supplement (myfoodrepo-bridge, MD-30): supervision for cereal + the three zero-image staples; 39,962 train / 1,000 val images, 498 categories | Kaggle mirror `sainikhileshreddy/food-recognition-2022` (AIcrowd upstream broken — `dataset-strategy.md` §6.1); provenance in `data/foodrec2022/SOURCE.md` |
| UECFOOD-256 | Permissive (per-image, see source) | Optional supplement for classes thin in FoodSeg103 | <http://foodcam.mobi/dataset256.html> |
| UNIMIB2016 | CC-BY-4.0 | Optional; Anthimopoulos / GoCARB lineage. Bounding boxes mainly — kept here for cross-paper comparison | <http://www.ivl.disco.unimib.it/activities/food-recognition/> |
| Project gravimetric set | Internal | β_c calibration + end-to-end accuracy bar | Captured during step 8 (see caveat below) |

Notes on the academic-paper datasets: Dehais 2017's GoFood is not openly
distributed; the Anthimopoulos / GoCARB lineage relied on UNIMIB-family
detection sets which don't supply pixel-accurate masks. FoodSeg103 is the
single best public starting point for the v1 35-class segmenter and is the
MVP default.

**β_c calibration cannot be done from public data.** Calibrated β_c values
require ground-truth gravimetric mass per food per meal (Req 21.1) — public
food datasets don't carry that. The MVP fall-back is documented and supported:
every class ships with β = 1.0 and a `betaCalibrationStatus` of
`uncalibrated_unity`, the design's permitted v1 state (design §6.9 step 3).
End-to-end MAPE / MAE accuracy (Req 21.3) is not measurable without a
gravimetric set; ship the MVP with the accuracy bar unverified and the
calibration status surfaced on the meal record. See step 8 for the capture
recipe when you're ready to lift the bar.

### Held-out segmenter test set

`HarnessCLI seg-bench` measures mean food-class mIoU (Req 8.9 as amended).
Carve the held-out split from
FoodSeg103: 10–15% of the remapped
images, kept entirely separate from train + val. Use the same fixed RNG seed
for the split so the held-out set is reproducible across training runs.

The bench is invoked with `--fixtures-dir <path>` pointing at the held-out
fixture directory.

### Acceptance bars at a glance

| Bar | Source | Where it's measured |
| --- | --- | --- |
| Segmenter mean food-class mIoU — recorded | Req 8.9 as amended | `HarnessCLI seg-bench` |
| Segmenter weights ≤ 24 MiB (FP16, Decision 13) | Req 8.2 | `SegmenterWeightsBudget.validate(at:)` |
| Segmenter inference ≤ 250 ms / view on iPhone 16 Pro (v1 hardware floor — segmenter-foundation Decision 22) | Req 8.3 | XCTest with `XCTClockMetric` |
| Segmenter resident on the Apple Neural Engine | Req 16.5 | Xcode → Core ML performance report (manual, post-bundle) |
| End-to-end MAPE < 20% AND MAE ≤ 25 g | Req 21.3 | `HarnessCLI accuracy` |
| ≥ 30 calibration meals per class for `calibrated` β_c status | Req 11.7 | `HarnessCLI calibrate` |

A class that misses the 30-meal bar falls back to a pooled β_c
(`uncalibrated_pooled`) or to β = 1.0 (`uncalibrated_unity`) — both are
permitted v1 states (design §6.9 step 3); the meal record persists which one
was used.

---

## 2. The class palette

The segmenter has **36 output channels**, not 24 (Req 8.4; the palette redefined in place
per Decision 23). `PostProcessing` asserts the model's channel count equals
`ClassPalette.totalClasses` (`foodClasses.count + liquidClasses.count + 3` = 35):

- Channels 0–23: 24 solid food classes
- Channels 24–31: 8 coarse liquid classes — `water`, `coffee`, `tea`, `milk`,
  `fruit_juice`, `soup`, `beer`, `wine`
- Channel 32: `background`
- Channel 33: `unknown_food` — pixel looks like food but doesn't match a known class
- Channel 34: `unsupported_liquid` — standalone liquid outside the 8 coarse classes
  (excluded from volume; Req 8.7)

The segmenter has **35 channels**, but the food database (`cofid_db.sqlite`) carries only the
**32 food classes** (channels 0–31: 24 solid + 8 liquid). The three sentinel channels (32–34) are
not foods and have no DB row — so "35-class segmenter" and "32-class food DB" are the same palette,
counted with and without the sentinels.

FoodSeg103 carries **no** standalone-liquid supervision, so the 8 liquid channels train on
little-to-no data — recognising liquids at inference is a deferred dependency owned by
model-production (Req 7.7). They are still real channels: the runtime palette and the
`ProbabilityTensor` are sized to 35, so the export must produce a 35-channel head.

Channel ordering is load-bearing. The Swift runtime indexes into the
`ProbabilityTensor` by these exact integer offsets ([design §3.5](../specs/estimation/pipeline/design.md#L246)).
If you reorder classes during training, the on-device pipeline breaks
silently — voxel ownership and macro lookup both index by channel.

### Where the canonical list lives

Two sources of truth, kept in sync by hand because they're tiny:

| File | Role |
| --- | --- |
| [tools/food_db/generate.py](../tools/food_db/generate.py) | The 24 solid + 8 liquid class IDs + names + density / macro / β rows (`FOOD_DATA`) that get baked into `cofid_db.sqlite`. |
| [MedataCore/Sources/Segmentation/ClassPalette.swift:41-53](../MedataCore/Sources/Segmentation/ClassPalette.swift#L41-L53) | Swift `ClassPalette.standard` — the runtime palette consumed by `CoreMLSegmenter`. Index order must match `FOOD_DATA`. |

When training, use the Python list — that's the one that maps onto the SQLite
DB and the per-class β_c calibration target.

### Palette ↔ DB edition lock

The palette and `cofid_db.sqlite` are released as a **versioned pair**
(Req 11.4). The DB's `meta.palette_version` (`v1`) must match the Swift
`ClassPalette.version` (`v1`). Re-derivation across palette versions requires
an explicit class-mapping file ([design §6.12](../specs/estimation/pipeline/design.md#L1244));
that's a v2-and-beyond concern — for v1, just don't reorder.

### Class composition (composite vs single-ingredient)

Some classes are composite by design (`mixed_vegetables`, `beans_baked`
includes its tomato sauce, etc.) — a deliberate choice from Decision 8.
Pourable accompaniments served on a solid food (curry sauce on rice, gravy on
roast) are part of the solid's class, not separated out (Req 8.7). When
preparing training masks (step 3), annotate the composite as a single region
rather than splitting it.

### The FoodSeg103 mismatch

FoodSeg103 has **103 classes**; we have 24 solid classes. The class mapping is the central
problem step 3 has to solve: most FoodSeg103 classes either map onto one of
our 24, fold into a composite (`mixed_vegetables`), or get dropped (anything
that doesn't appear in our palette and can't be merged sensibly). The 8 liquid channels
(24–31) have no FoodSeg103 source and so get no supervision from this dataset.

The mapping table lives at `tools/segmenter/class_mapping_foodseg103.json`,
generated by `build_class_mapping.py` (§3b). It carries a curated default
routing (built from FoodSeg103's canonical category list); re-run the generator
against the real `category_id.txt` once the dataset is downloaded and review the
routing summary it prints before training.

## How to read sections 3–7

Each section below is **explanation first, then a runbook**: a short "why" so
you know what the step is for and where it can bite, followed by the exact
commands. All paths are relative to the repo root. Commands assume `uv` (set up
in §1) and that steps 3–5 run on the Linux/CUDA training box; **step 6 (export)
must run on macOS** — `coremltools` is Apple-only, so sync the checkpoint over
first.

Scripts marked **(exists)** are in the repo today. The dataset/training/fixture
scripts (`build_class_mapping.py`, `prepare_dataset.py`, `train.py`,
`make_fixtures.py`) now exist alongside `export.py` and the `HarnessCLI` benches.
The real runs have since happened (status note at the top of this document);
the commands below remain the canonical recipe.

## 3. Dataset preparation

### Why

FoodSeg103 is the v1 primary set (§1 "Datasets"). It has 103 classes; we have
24 solid classes, so the load-bearing artefact of this section is the **class-mapping
file** that collapses 103 → our 35-channel palette. Get this wrong and everything
downstream is wrong: the §2 channel ordering is what the Swift runtime indexes
by, and over-dropping classes shrinks the set the mIoU bar (§5) can even
measure. The held-out split defined in §1 ("Held-out segmenter test set") is cut
here and must stay reproducible across training runs.

### Runbook

**3a. Download FoodSeg103** (Apache-2.0):

```sh
# from https://xiongweiwu.github.io/foodseg103.html — Images/ + Annotations/ (PNG masks)
mkdir -p data/foodseg103
# fetch + unzip the release archive into data/foodseg103/
```

**3b. Build the FoodSeg103→palette class mapping.** Map each FoodSeg103 class onto one of
our 24, fold it into a composite (`mixed_vegetables`), or drop it. The canonical
24 IDs/names live in `tools/food_db/generate.py:120-148` — map **to that
ordering** (§2), never reorder. Annotate composites as a **single** region:
pourable accompaniments belong to the solid's class (Req 8.7) — curry sauce on
rice is the rice class, not a separate region.

```sh
# produces tools/segmenter/class_mapping_foodseg103.json
python tools/segmenter/build_class_mapping.py \
    --foodseg-labels data/foodseg103/category_id.txt \
    --palette tools/food_db/generate.py \
    --out tools/segmenter/class_mapping_foodseg103.json   # (exists)
```

**3c. Remap masks and cut splits.** Apply the mapping to every PNG mask
(remapping pixel values to the 35-channel palette: 0–23 solid food, 24–31 liquid
[no FoodSeg103 source], 32 background, 33 `unknown_food`, 34 `unsupported_liquid`), then
carve train / val / **held-out**
(10–15%) with a **fixed RNG seed** so the held-out set is reproducible.

```sh
python tools/segmenter/prepare_dataset.py \
    --src data/foodseg103 \
    --mapping tools/segmenter/class_mapping_foodseg103.json \
    --out data/foodseg103_remapped \
    --heldout-frac 0.12 --seed 1234                          # (exists)
```

## 4. Training the segmenter

### Why

The architecture — DeepLabV3 + MobileNetV3-Large at 513×513 — is fixed by
Decision 25 to hit the on-device budget (≤ 24 MiB FP16 — Decision 13 amended the original 10 MB, ≤ 250 ms/view, ANE
residency; §1 acceptance bars). It is a deliberate accuracy-for-feasibility
trade. You transfer-learn: take the torchvision backbone and re-teach a 35-class
head rather than training from scratch. Watch **food-class** mIoU during
training, not overall accuracy — background dominates pixel counts and inflates
the naive number while thin food classes quietly fail the §5 bar.

### Runbook

```sh
python tools/segmenter/train.py \
    --data data/foodseg103_remapped \
    --num-classes 35 --target-size 513 \
    --epochs 60 --batch-size 16 --lr 1e-3 \
    --out tools/segmenter/build/checkpoint.pt                # (exists)
```

Output: a PyTorch checkpoint at `tools/segmenter/build/checkpoint.pt`. This `.pt`
is the **single source of truth** (Decision 28) that both export paths (§6)
consume — there is no separate iOS vs Android training run.

### The incumbent recipe (myfoodrepo-bridge, 2026-07-26): merged corpus at 36 classes

This is the recipe that produced the **shipped** model `ab812dc3aa9d` (Decision 27),
and it is the baseline every later run is judged against. R2 re-runs it verbatim
with the corpus as the only change, so keep it launchable as written.

Palette v2 (MD-29) and the Food Recognition 2022 bridge (MD-30) move training
to the merged corpus — `data/merged_foodseg_foodrec2022` (train 45,515 /
val 1,711 / heldout 854; built by `merge_corpus_foodrec2022.py`, leak-free
anchor preserved verbatim). The corpus is ~8× FoodSeg103, so epoch counts are
chosen by total-optimisation-step parity with the incumbent (60 × 5,553 ≈
333k images seen ≈ 7.3 merged epochs), not copied from the 60-epoch runbook.
Staple-safe recipe per the PRD: plain CE (`--class-weighting none` — matching
the incumbent `24e0b022241a` for an attributable comparison), geometric
augmentation on, no photometric augmentation, `--num-classes 36`:

```sh
nohup caffeinate -is tools/segmenter/.venv/bin/python tools/segmenter/train.py \
    --data /Users/r/repos/medata/data/merged_foodseg_foodrec2022 \
    --num-classes 36 --target-size 513 \
    --epochs 12 --batch-size 16 --lr 1e-3 \
    --out tools/segmenter/build/checkpoint_merged_v2.pt \
    >> tools/segmenter/build/train_merged_v2.log 2>&1 &
```

### The adopted recipe (estimation-quality R3, 2026-08-28): `combined`, no weighting

**This is the recipe of record** (segmenter-foundation Decision 36). It beats the shipped
`ab812dc3aa9d` by +0.0265 mean food-class IoU on the 182-image leak-free anchor (0.4192 vs 0.3927)
and improves four of the five measurable staples, `bread_white` crossing its 0.45 floor for the
first time. Start any new run from this, not from the R1 line below.

```sh
nohup caffeinate -is tools/segmenter/.venv/bin/python tools/segmenter/train.py \
    --data /Users/r/repos/medata/data/merged_foodseg_foodrec2022 \
    --num-classes 36 --target-size 513 \
    --epochs 12 --batch-size 16 --lr 1e-3 \
    --loss combined --class-weighting none --photometric-augment \
    --out tools/segmenter/build/checkpoint_r3_combined_noweight.pt \
    >> tools/segmenter/build/train_r3_combined_noweight_20260828.log 2>&1 &
```

Judged with (note the **v2** corpus — the v1 tree is a 35-channel label space and
`run_validation.py` refuses it rather than returning a plausible wrong number):

```sh
tools/segmenter/.venv/bin/python tools/segmenter/run_validation.py \
    --checkpoint /Users/r/repos/medata/tools/segmenter/build/checkpoint_r3_combined_noweight.pt \
    --data /Users/r/repos/medata/data/foodseg103_remapped_v2 \
    --split heldout_leakfree \
    --lineage /Users/r/repos/medata/tools/segmenter/build/lineage-r3.json
```

Pass `--lineage` an ABSOLUTE path or the metrics land in a stray nested tree. Twelve epochs took
about 6 h 20 m on MPS, and the run was still climbing at epoch 12 (0.4335 → 0.4510 on merged val),
so a longer schedule is an open question rather than a settled one.

**`--class-weighting sqrt_inverse` is retired.** R1 ran the same recipe with it and lost three
strong staples — white_rice, pasta and chips_fries each down 0.09 to 0.14 — which R3 recovered by
changing only that flag. Decision 25 established inverse-frequency weighting as the staple-killer;
sqrt is not mild enough either.

### Current run (estimation-quality R1, 2026-08-14): `combined` + `sqrt_inverse`

R1 is the settled class-imbalance recipe from estimation-quality task 6: the
incumbent corpus and step budget with three levers changed —
`--loss combined` (Dice + CE at `--dice-weight` 0.5), `--class-weighting
sqrt_inverse`, and `--photometric-augment`. This is the exact command that
produced `e4e92a9df9d3`, recovered from the shell that launched it:

```sh
tools/segmenter/.venv/bin/python tools/segmenter/train.py \
    --data /Users/r/repos/medata/data/merged_foodseg_foodrec2022 \
    --num-classes 36 --target-size 513 \
    --epochs 12 --batch-size 16 --lr 1e-3 \
    --loss combined --class-weighting sqrt_inverse --photometric-augment \
    --out tools/segmenter/build/checkpoint_combined_sqrtinv.pt \
    >> tools/segmenter/build/train_combined_sqrtinv_20260814.log 2>&1 &
```

Launched 01:52, finished 08:17 — 12/12 epochs in about 6h25m on MPS, roughly
32 min/epoch. Two hygiene notes, because R2 will be launched from this block:

- The command above carries **no `nohup caffeinate -is` prefix**; `caffeinate -is`
  was started by hand in a second shell 42 seconds later. That worked, but it is
  not what "Detached runs" below prescribes — prefix the launch as documented and
  the run survives both a closed shell and a sleeping Mac.
- The 13 Aug attempt (`train_combined_sqrtinv_20260813.log`, 35 bytes) is a
  mistyped `asdcanohup` prefix that never started a run. Check the log has epoch
  lines in it before walking away.

Validated on the binding surface with:

```sh
tools/segmenter/.venv/bin/python tools/segmenter/run_validation.py \
    --checkpoint tools/segmenter/build/checkpoint_combined_sqrtinv.pt \
    --data /Users/r/repos/medata/data/foodseg103_remapped_v2 \
    --split heldout_leakfree \
    --lineage /Users/r/repos/medata/tools/segmenter/build/lineage-e4e92a9df9d3.json \
    > tools/segmenter/build/validate_combined_sqrtinv_leakfree_v2anchor.log 2>&1
```

> **`--data` must be `foodseg103_remapped_v2`, not `foodseg103_remapped.**
> Both directories hold the same 182 leak-free stems, but their masks are in
> different label spaces — v1 tops out at class 34 (35 classes), v2 at class 35
> (36 classes), and the indices diverge above 23. Validating a 36-class model
> against the v1 masks silently mis-scores every class above the divergence and
> understates the mean by roughly 0.07 without failing. R1 was first measured
> that way and read 0.2472; the same command against v2 reads 0.3215. The
> incumbent reproduces its recorded 0.3927 **only** against v2, which is what
> identifies v2 as the surface Decisions 27 and 30 were measured on.
>
> `splits.json` `anchor.path` points at the v1 directory and is wrong — the
> default at `merge_corpus_foodrec2022.py:121-122` was never moved to `_v2` when
> the corpus was. The leak-free guarantee itself is unaffected: the stems are
> identical in both directories, so the no-overlap check still holds.

Measured on the v2 anchor, against the incumbent re-measured the same day with
the same script: mean food-class IoU **0.3215 vs 0.3927** (−0.071), and a staple
mean of 0.3549 vs 0.3870 over the incumbent's seven measurable staples (−0.032).
On merged val R1 peaked at 0.4046 (epoch 12, still
climbing) against the incumbent's 0.4418.

The per-staple split is the informative part, and it is the classic
class-weighting trade: R1 **lifts `bread_white` from 0.3927 to 0.4605**, taking
the incumbent's weakest staple over the 0.45 floor, while regressing the strong
ones — `pasta` 0.6497 → 0.5158, `chips_fries` 0.5599 → 0.4703, `white_rice`
0.6320 → 0.5873. `bread_wholemeal` and `potato_mashed` read 0.0000 for both
models (Decision 21: zero FoodSeg103 images), and `brown_rice` is `absent` for
the incumbent but 0.0000 for R1 — meaning only R1 predicts it anywhere.

The promote-or-reject verdict is
`specs/estimation/segmenter-foundation/decision_log.md`, not this runbook.

### Superseded: recommended next run (estimation-quality PRD)

> **Superseded 2026-07-16/26:** this recipe's inverse-frequency class
> weighting was deleted as the attributed staple-killer (snaq-parity
> Decision 13, segmenter-foundation Decision 25); `--loss combined` now pairs
> with `--class-weighting {none, sqrt_inverse}` only, and the current run is
> the merged-corpus block above. Kept for the historical record.

The plain unweighted cross-entropy above collapses toward the dominant
background class on the imbalanced 35-class palette — the speckled masks the
shipped models produce. The trainer now takes opt-in flags for a
class-imbalance-aware recipe (`--loss`, see `tools/segmenter/loss_config.py`)
and train-only photometric jitter (`--photometric-augment`); omitting them
reproduces the historical recipe exactly. The recommended next run combines the
Dice + inverse-frequency-weighted CE loss with photometric augmentation:

```sh
caffeinate -is python tools/segmenter/train.py \
    --data data/foodseg103_remapped \
    --num-classes 35 --target-size 513 \
    --epochs 60 --batch-size 16 --lr 1e-3 \
    --loss combined --photometric-augment \
    --out tools/segmenter/build/checkpoint_combined.pt
```

A distinct `--out` keeps the current checkpoint and its lineage intact for
comparison. If the run is interrupted, resume with the SAME flags plus
`--resume tools/segmenter/build/checkpoint_combined.pt.resume.pt` — the trainer
treats a `--loss`/`--photometric-augment` change mid-run as hyperparameter
drift and refuses it (run hygiene below applies as usual). The selected loss
and augmentation are recorded in the checkpoint and `build/lineage.json`
`train_config` (absent keys mean the historical recipe); accept or reject the
variant on held-out food-class IoU via `run_validation.py` (§5).

### Run hygiene (local Mac, MPS)

The trainer writes a resume sidecar (`<--out>.resume.pt`) atomically after every
completed epoch, so an interrupted run loses at most one epoch — continue it with
`train.py --resume <sidecar>` using identical hyperparameters (the trainer
refuses drift, and refuses to start over an existing sidecar without `--resume`).
For long runs on the local Mac:

- Wrap the run in `caffeinate -is` so the Mac doesn't sleep mid-epoch.
- Treat `PYTORCH_ENABLE_MPS_FALLBACK=1` as a safety net only — verify nothing
  hot falls back to the CPU, or hours quietly become days.
- Measure one epoch before committing to a full run; it should land in the
  expected range (roughly 5–10× a mid-range CUDA card per epoch, §1).
- Watch **food-class** mIoU, not overall accuracy (see "Why" above).

### Detached runs — launch, find, watch, resume

`caffeinate` survives a closed terminal via `nohup`, but never a reboot
(2026-07-15: a reboot killed a run at epoch 30; the sidecar resumed it losing
nothing). Lid-closed running IS supported, but only in **clamshell mode**: AC
power plus an external display and keyboard/mouse (a powered hub carrying all
three works — the 2026-08 runs use exactly that). `caffeinate` alone does NOT
survive a lid close without the external display: clamshell exit forces sleep
regardless of any assertion. The working setup is therefore either lid open on
power, or lid closed on the hub, with `caffeinate -is` wrapped around the run
in both cases.

Belt-and-braces (optional): `sudo pmset -b disablesleep 1` forces sleep off at
the firmware-settings level, guarding the run if the hub or display drops
mid-epoch and clamshell mode exits. Restore afterwards with
`sudo pmset -b sleep 1; sudo pmset -b disablesleep 0` — note that pair is the
RESTORE half (it re-enables sleep); don't confuse the two. With a reliable hub
this is unnecessary, and `-b` targets the battery profile anyway (the run
should always be on AC) — use it only when the hub's power delivery is in
doubt.

```sh
# Launch detached (log name: train_<variant>_<date>.log)
nohup caffeinate -is tools/segmenter/.venv/bin/python tools/segmenter/train.py \
    <flags> >> tools/segmenter/build/train_<name>.log 2>&1 &

# Find a running train later (shows PID + full flags)
pgrep -fl "train.py|caffeinate"

# Watch progress (one epoch line every ~20 min on M5 Pro MPS)
tail -f tools/segmenter/build/train_<name>.log

# Recover the exact flags from a sidecar (they must match on --resume)
tools/segmenter/.venv/bin/python -c "import torch; s = torch.load(
    'tools/segmenter/build/<out>.resume.pt', map_location='cpu');
print({k: v for k, v in s.items() if k not in ('model', 'optimizer')})"

# Resume: SAME flags + --resume <out>.resume.pt, appending to the same log
```

### Seeded runs and the serial queue (2026-09-26)

`--seed N` pins the trainer's own randomness (RNGs, shuffle order, per-worker
augmentation) and lands in lineage `train_config.seed`; `--dice-weight W` sets
the dice share of the `combined` loss (default 0.5). Both are checked by the
resume drift-check. An unseeded exact repeat of R3 (R7) showed the anchor mean
stable to 0.001 but single classes moving by up to 0.45 and staples by 0.05, so
recipe comparisons are seeded from here on and read against the seeded
reference R8 (`--seed 1`).

Six runs of the R3 recipe (R3, R7, R8, R9, R10, R8b; 2026-09-26 to 09-29) set what this anchor
can resolve. A class needs about **20 of the 182 held-out images** to be readable at single-run
resolution: every class above that bar has a spread of 0.097 or less over the six, while soup
(1 image) swings 0.775, banana and apple (2) swing 0.69 and 0.60, and fruit_juice (3) swings
0.30. The thirteen readable classes are unknown_food, mixed_vegetables, bread_white,
potato_boiled, beef, carrot, wine, chicken, white_rice, pork, tomato, broccoli and peas; their
mean spans 0.4783–0.5031 across the six, so **0.025 is the smallest recipe effect one run can
resolve**. Score verdicts on that mean and on the mask-quality block (spread over the six: food IoU 0.008,
region IoU 0.022, boundary F 0.016, top-3 hit 0.021). The tool's own
`mean_iou` is not usable for verdicts — it includes classes with no held-out truth and classes
present in one image, and it ranks the six runs differently from the readable thirteen.

Multi-hour runs go through the serial queue rather than hand-launched
`nohup` lines: entries in `tools/segmenter/queue/`, runner
`tools/segmenter/run_queue.sh`, state under `tools/segmenter/build/queue/`.
Mechanics, the pause window for trainer edits and the reading rules are in
`docs/agent-notes/segmenter-run-queue.md`.

### Repeat-factor sampling (2026-09-26)

`--repeat-factor-threshold T` turns on LVIS repeat-factor sampling (research
note §4.4): each train image is drawn with weight `max(1, max_c sqrt(T / f_c))`
over the food classes it contains, `f_c` being the fraction of train images
holding class c, so images with a class rarer than `T` are seen more often per
epoch while the epoch length stays `len(train)`. The per-image class presence
comes from one scan of the train masks, cached under
`tools/segmenter/build/class_presence/` and keyed by split path and image
count. Omitted, sampling is the plain once-per-epoch shuffle; the value lands
in lineage `train_config.repeat_factor_threshold` and is checked by the resume
drift-check.

### Boundary-weighted loss (2026-09-27)

`--boundary-weight W` makes the per-pixel cross-entropy term of whichever
`--loss` is selected (ce, weighted_ce, focal, the CE half of combined, the CE
base of co_occurrence) care about edges: every pixel within
`--boundary-band-px K` (default 2, Chebyshev distance) of a label change in
the train mask is weighted `W`, every other pixel 1, and the term is the
weighted mean `sum(w * ce) / sum(w)` rather than the plain mean, so the loss
scale stays comparable to the unweighted run. Background counts as a class, so
food/background edges are boundaries; dice and presence terms are untouched.
The map is built per sample in the Dataset from the letterboxed, augmented
mask (`loss_config.boundary_weight_map`) and collated as a third tensor. Why:
re-scoring R3/R6/R7/R8/R9 and the shipped model on class-agnostic metrics
(MD-29) put boundary F at 2 px at 0.45–0.46 and region IoU at 0.48–0.50 for
every recipe tried, inside the 0.01–0.02 noise band, so no recipe to date has
moved the edges. Omitted, the loss is the plain per-pixel mean as before; both
values land in lineage `train_config.boundary_weight` /
`train_config.boundary_band_px` and are checked by the resume drift-check.

### DeepLabV3+ decoder: `--arch deeplabv3plus_mnv3` (2026-10-03)

The one architecture lever left after ten runs (research note §4.6). R15 showed
boundary quality is not loss-limited, so this tests whether the model can draw
a sharper edge when it is given higher-resolution features to draw it from.
`deeplab_mnv3` predicts on the stride-16 grid (41×41 at 641; the backbone's
dilated tail holds it at 16, not 8) and upsamples the logits bilinearly to the
input. `deeplabv3plus_mnv3` keeps the same backbone and ASPP and replaces the
head with a DeepLabV3+ decoder:

- skip: `features[3]` (end of the stride-4 stage, 24 channels, 161×161 at 641)
  → 1×1 conv to 48 channels + BN + ReLU;
- ASPP output (256 channels, stride 16) → bilinear upsample to the skip's grid
  → concatenate (304 channels);
- two 3×3 conv (256) + BN + ReLU blocks, a 1×1 classifier to 36, then bilinear
  upsample to the input.

The backbone starts from the same torchvision COCO-seg `DEFAULT` weights as
`deeplab_mnv3`, and the ASPP and decoder start fresh, as `deeplab_mnv3`'s head
does, so the decoder is the only difference. Output contract unchanged:
`{"out": [1, 36, H, W]}` at the input size. `train.py` stamps `arch` into the
checkpoint and lineage, so `export.py` and `run_validation.py` resolve it with
no flag; its checkpoint loader is strict, so a wrong-arch file fails instead of
exporting an untrained decoder.

Cost at 641, measured on the Mac (2026-10-03, export of a 50-step CPU smoke
checkpoint against the bundled R16 export):

| | `deeplab_mnv3` | `deeplabv3plus_mnv3` |
| --- | --- | --- |
| Parameters | 11.03 M | 11.73 M |
| FP16 weights (export gate ≤ 25,165,824 B) | 22,169,442 B | 23,577,303 B (1,588,521 B margin) |
| Conv multiply-adds | 16.1 G | 48.8 G (3.0×) |
| Core ML CPU-only predict, 20 interleaved runs | 1.00× | about 1.8× |

The smoke export passed every gate: 36 channels, Core ML against the PyTorch
oracle on a real anchor image max abs logit error 0.114 and argmax agreement
0.9998. The CPU ratio is about 1.8× fastest-run to fastest-run (1.83–1.89 over
three sessions); the medians (1.61–1.90) were taken with the training queue
loading the CPU. The multiply-adds triple because the two 3×3 convs run on the
161×161 stride-4 grid; the CPU time rises less. The phone (ANE) ratio will
differ and must be measured before any adoption. A depthwise-separable decoder
(each 3×3 split into a depthwise 3×3 and a 1×1) measured 21,292,093 B, 19.2 G
multiply-adds and 1.22× CPU — the cheaper follow-up if R19 shows the decoder
helps.

Queued as R19 (`tools/segmenter/queue/120-r19_dlv3plus_641_seed1.sh`): the R8
recipe at 641, seed 1, read against R16 (seed 1) and R17 (seed 2) at 641 on
the mask block, boundary F first. The entry raises `MEDATA_STALL_SECS` to 3 h:
the train log only moves once an epoch (stdout is flushed when the next
epoch's DataLoader workers spawn), R16's epochs took 50 minutes, and a
decoder epoch can pass the default 90-minute stall window.

## 5. Validating the segmenter

### Why

The number reported is mean **food-class** mIoU (Req 8.9 as amended).
`HarnessCLI seg-bench` **(exists)** reports it, but note how it works: it does
**not** run the model.

> **Note (2026-07-06):** seg-bench has not been run for the
> shipped models, and its held-out fixture bundle has not been generated — it
> would be ~16 GB and record nothing beyond what
> `tools/segmenter/run_validation.py` already writes into `build/lineage.json`.
> Both shipped models read (`0295ea61edd9` mean 0.4259;
> letterbox-trained `24e0b022241a` mean 0.4054 — the letterbox recipe closes the
> train↔runtime square-resize skew, which this offline bench cannot see).
> For judging uplifts, the 0.4054 full-heldout figure is superseded: the pinned
> model trained on most of the re-cut held-out split, so that table is
> leakage-inflated; the leak-free anchor is mean 0.3776 on the 182-image clean
> subset (segmenter-foundation Decision 21, 2026-07-15).
> seg-bench remains the mechanism described below for when fixture generation is
> worth the disk.
It reads fixtures containing the model's FP16 probability tensors plus
ground-truth argmax, stamped with the checkpoint's SHA-256 (the SHA guards
against benching stale predictions). So you first run the trained model over the
held-out split to produce those fixtures, then bench them.

> **Coupling worth stating outright:** this bench runs against FoodSeg103's
> already-RGB images. It is therefore **blind to device train/serve skew** — if
> the on-device pre-processor feeds the model a different colour space than you
> trained on, mIoU here stays green while real-device inference degrades. The
> capture path now emits BGRA8 (`PixelBufferAdapter`, shipped via
> `specs/capture/rawframe-rgb-conversion/`); train on BGRA-consistent inputs and keep the
> training transform matched to `SegmenterPreProcessor`. See §11.

### Runbook

```sh
# 5a. Run the trained model over the held-out split → fixture bundle
python tools/segmenter/make_fixtures.py \
    --checkpoint tools/segmenter/build/checkpoint.pt \
    --heldout data/foodseg103_remapped/heldout \
    --out tests/fixtures/segmenter/heldout                   # (exists)

# 5b. Bench (reports mIoU)
SHA=$(shasum -a 256 tools/segmenter/build/checkpoint.pt | cut -d' ' -f1)
swift run HarnessCLI seg-bench \
    --fixtures-dir tests/fixtures/segmenter/heldout \
    --checkpoint-sha256 "$SHA" \
    --output build/seg-bench.json
```

If it fails, revisit the class mapping (§3b) — over-dropping shrinks the
evaluable class set — then retrain. Don't proceed to export until the bar is
green.

### Mask quality (class-agnostic, MD-29)

`specs/DECISIONS.md` MD-29 re-scoped the segmenter to "clean, coherent food
masks with a good ranked shortlist" — the user fixes a wrong class with a tap,
not a wrong region. `run_validation.py` therefore makes a second pass over the
same split and records `metrics.mask_quality` in the lineage file beside the
class metrics, and prints four `[validate] mask …` lines beside the mean. The
metrics live in `tools/segmenter/mask_quality.py` (pure numpy; the EdgeTAM
spike's `spike_masks/scoring.py` imports the same code). Record only: no gate
reads the block yet — segmenter-foundation Decision 37 names the numbers a
replacement bar would be pinned against.

```json
"mask_quality": {
  "food_iou": 0.88, "region_iou": 0.49, "boundary_f2": 0.46,
  "shortlist_top3_hit": 0.82, "n_images": 182, "n_regions": 900,
  "scored_at": "2026-09-27T05:00:00+00:00"
}
```

Everything is scored on the image content only (the letterbox padding is
cropped off), so a 2 px tolerance means the same thing on every image. "Food"
is every channel except the palette's special channels (background 33,
unknown_food 34, unsupported_liquid 35 — `validation.special_channel_indices`).

- `food_iou` — IoU of the binary food-versus-not-food mask, mean over images:
  is the food where the model says it is, whatever it called it.
- `region_iou` — each GT region (an 8-connected component of one class,
  ≥ 64 px) matched to the predicted label-map component with the largest
  overlap; IoU of that pair, mean over regions: does each food come out as one
  coherent blob the user could swap the label on.
- `boundary_f2` — DAVIS boundary F on the binary food mask with a 2 px
  tolerance, mean over images: are the edges tight (speckle and halo pull it
  down; area IoU barely notices them).
- `shortlist_top3_hit` — softmax mean-pooled inside each GT region, ranked
  over the food classes; the fraction of regions whose true class is in the
  top 3: would the review screen's shortlist hold the right food.
- `n_images`, `n_regions` — the denominators; `scored_at` — UTC time of the pass.

Re-score an old checkpoint into its lineage file without touching the class
metrics or the gate verdict (CPU is about 3 minutes for the 182-image anchor
and leaves MPS to a live training run):

```sh
tools/segmenter/.venv/bin/python tools/segmenter/run_validation.py \
    --checkpoint tools/segmenter/build/checkpoint_r3_combined_noweight.pt \
    --data data/foodseg103_remapped_v2 --split heldout_leakfree \
    --lineage tools/segmenter/build/lineage-r3.json \
    --device cpu --mask-quality-only
```

The lineage block uses the spike's food definition (RESULTS.md): everything
except background (channel 33) is food, so `unknown_food` and
`unsupported_liquid` count — a wrong class is the user's tap, a wrong mask is
the volume (MD-29). Regions are matched against the label map's class-aware
components, which is what the review screen shows. Under this definition R3
reads 0.882 food IoU / 0.489 region IoU / 0.459 boundary F / 0.824 top-3 hit;
excluding the sentinels instead (the first re-scoring pass, 2026-09-27) gave
0.736 / 0.484 / 0.398 / 0.829, and those two sets are not interchangeable.

## 6. Exporting to Core ML + TFLite

### Why

`tools/segmenter/export.py` **(exists)** consumes the `.pt` checkpoint directly
(the ONNX hop is bypassed per Decision 28) and emits both Core ML (`.mlpackage`,
iOS) and TFLite (future Android), FP16 throughout to fit the ≤ 24 MiB budget (Decision 13). It
then runs a reference image through both artefacts and asserts per-pixel argmax
agreement > 99% with max-abs logit error < 0.05 — this is the mechanical proof
of the single-source-of-truth portability requirement, and the place
FP16-quantisation or op-translation drift will surface if you change the
architecture.

### Runbook

Run on **macOS**:

```sh
python tools/segmenter/export.py \
    --checkpoint tools/segmenter/build/checkpoint.pt \
    --num-classes 35 --target-size 513 \
    --reference-image tests/fixtures/segmenter/reference.png \
    --out-coreml MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage \
    --out-tflite tools/segmenter/build/segmenter.tflite
```

`--out-coreml` already defaults to
`MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage` — the exact location
the runtime loader (`PipelineFactory.makeSegmenter`) resolves via `Bundle.module`
(model-production tasks 2/5). The path moved under the `Pipeline` target so SPM
bundles it as a package resource; don't rename it.
`tests/fixtures/segmenter/reference.png` must exist and be representative of real
plate captures. The export also runs its gates (≤ 24 MiB weights, 35 channels in
palette order, PyTorch-oracle equivalence + runtime-preprocessing parity) and
stamps the checkpoint's 12-hex `model_version` into the Core ML metadata
(`build/lineage.json` is the join key).

## 7. Bundling into the iOS app

### Why

The exported artefact lands at
`MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage` (gitignored; bundled
at build time as a package resource). The app selects its inference engine at
compile time: **Debug / `DEV_STUB_SEGMENTER`** uses `StubInferenceEngine` (no
model file, placeholder estimates, `segmenterSource = "dev_stub"`); **Release**
loads the real model via `PipelineFactory` and stamps
`segmenterSource = "coreml_<modelVersion>"` (the 12-hex checkpoint id read back
from the Core ML metadata, model-production task 5). So to exercise the trained
model you must build Release. The three on-device bars (§1) are only meaningful
here — and ANE residency in particular is a manual check that is easy to miss.

> **Bundling (loader gap closed, model-production tasks 1–2):** the loader
> resolves `segmenter.mlpackage` via `Bundle.module` (the
> `GRDBFoodDatabase.bundled()` pattern), and the `Pipeline` target declares
> `resources: [.copy("Resources")]` in `Package.swift`. A directory `.copy`
> (not a named-file copy) is used so clean Debug + Release builds stay green
> before any model exists, and the gitignored `.mlpackage` bundles automatically
> once `export.py` drops it in (Decision 7). A missing model still throws
> `PipelineFactoryError.segmenterModelMissing`. See
> [`architecture.md`](architecture.md) §9.

### Runbook

1. Build a **Release** config (so `DEV_STUB_SEGMENTER` is undefined) and
   side-load to an iPhone 16 Pro (hardware floor — segmenter-foundation Decision 22) — see
   [`ios-device-setup.md`](ios-device-setup.md) and
   [`agent-notes/device-build-and-test.md`](agent-notes/device-build-and-test.md).
2. Confirm the bars:
   - **Size ≤ 24 MiB (Decision 13)** — `SegmenterWeightsBudget.validate(at:)` runs at load.
   - **≤ 250 ms / view** — XCTest with `XCTClockMetric`.
   - **ANE residency** — Xcode → Core ML performance report (manual). A model
     that converts fine but falls back to CPU/GPU silently blows the latency bar.
3. Tap the shutter on device → a real `MealRecord` with a non-placeholder carb
   total reaches the result view.

### Swapping which model is bundled

Judging a candidate in the real world means putting it on the phone, and the app
has **no model picker** — the bundled artefact is the model, chosen at build
time. That is deliberate: nothing on the device selects a model, so there is no
way for a build to disagree with itself about what it is running.

The rule that makes swapping cheap is: **never export over the bundled path.**
Export each candidate to its own name under `build/`, with its own lineage
manifest, and treat `Resources/segmenter.mlpackage` purely as a copy target.

```sh
# Export a candidate ASIDE — never straight into Resources/.
tools/segmenter/.venv/bin/python tools/segmenter/export.py \
    --checkpoint tools/segmenter/build/checkpoint_combined_sqrtinv.pt \
    --out-coreml tools/segmenter/build/segmenter-e4e92a9df9d3.mlpackage \
    --lineage    tools/segmenter/build/lineage-e4e92a9df9d3.json \
    --skip-tflite

# Put it on the phone: one copy, one build.
rm -rf MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage
cp -R tools/segmenter/build/segmenter-e4e92a9df9d3.mlpackage \
      MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage
make dev
```

Swapping back to the incumbent is the same two commands with
`segmenter-ab812dc3aa9d.mlpackage` — no re-export and no retrain, because the
candidate's artefact and manifest are still sitting in `build/`. `build/` is
gitignored in full, so the accumulated candidates cost nothing but disk.

`--lineage` is the load-bearing flag. `emit_lineage` writes to
`build/lineage.json` by default and `preserve_metrics` only protects a re-export
of the **same** checkpoint, so an export without it silently overwrites whatever
model the manifest last described. That is not hypothetical: the R1 run
(§4) overwrote the incumbent's recorded metrics and its developer-phase release
override, and only the checkpoint surviving on disk made them recoverable.

### Knowing which model is on the phone

Three surfaces name the model, and they agree by construction because all three
read the same 12-hex id that `export.py` stamps into the Core ML metadata as
`medata.modelVersion`:

- **The build** — `make dev` prints `BUNDLED SEGMENTER:` before
  building and `DEPLOYED SEGMENTER:` after installing. Read it out of the
  artefact itself, not out of a variable, so a stale copy cannot lie.
- **Every capture** — the app stamps `segmenterSource = coreml_<modelVersion>`
  on each `MealRecord` and `EstimationOutcome`; Settings › Estimation log shows
  it per capture, and the Benchmark report is scoped by it, so captures taken
  under different models never pool into one accuracy number.
- **The launch line** — `event=launch buildStamp=… segmenterSource=…` via
  `make logs`. Note this one reports only `stub` or `coreml`: it tells you
  whether a real model is bound, **not which**. Use the build output or a capture
  for that.

The build stamp identifies the *build*, not the model inside it — a `cp -R` swap
followed by a rebuild changes both, but a rebuild without a swap changes only the
stamp. Match the model id, not just the stamp, before trusting a captured trail.

## 8. Capturing gravimetric meal fixtures

### Why

β_c calibration (§9) and the end-to-end accuracy bar (§10) both need
ground-truth gravimetric mass per food per meal (Req 21.1), which **no public
dataset provides** (§1 "Datasets"). This is the only step that requires
capturing your own data. It is **out of scope for the MVP** — ship with every
class at β = 1.0 / `betaCalibrationStatus = uncalibrated_unity` (the permitted v1
state, design §6.9 step 3) and the accuracy bar unverified. Do this section only
when you're ready to lift that bar.

### Runbook

Per meal, using the kit from §1 (1 g-resolution scale, ID-1 reference card, the
same iPhone used for on-device validation):

1. Weigh each food component individually on the scale; record grams per palette
   class. Aim for **≥ 30 meals per class** (Req 11.7) for `calibrated` status —
   classes below that fall back to pooled or unity β (both permitted).
2. Capture the meal with the app exactly as an end user would (card in frame for
   scale where used).
3. Record the gravimetric truth alongside the capture in the fixture format the
   `HarnessCLI calibrate` / `accuracy` benches consume (keyed by checkpoint
   SHA-256, as in §5).

## 9. Bulk-correction calibration

### Why

β_c is a per-class bulk-correction factor baked into `cofid_db.sqlite`, applied
to volume estimates before macro calculation. It corrects systematic volume bias
per food class. It is computed offline from the §8 gravimetric set; a class with
fewer than 30 meals falls back to a pooled β (`uncalibrated_pooled`) or to
β = 1.0 (`uncalibrated_unity`) — the meal record persists which one was used.

### Runbook

```sh
SHA=$(shasum -a 256 tools/segmenter/build/checkpoint.pt | cut -d' ' -f1)
swift run HarnessCLI calibrate \
    --fixtures-dir <gravimetric-fixtures> \
    --checkpoint-sha256 "$SHA" \
    --output build/beta.json
```

Bake the resulting β_c table into the DB via `tools/food_db/generate.py`, keeping
the palette ↔ DB edition lock from §2 intact (`meta.palette_version` must match
`ClassPalette.version`).

## 10. End-to-end accuracy harness

### Why

The product bar is **MAPE < 20% AND MAE ≤ 25 g** (Req 21.3) measured end to end
(segmenter → volume → macros), not the per-stage mIoU of §5. It is only
measurable once you have the §8 gravimetric set; until then the MVP ships with
this bar explicitly unverified.

### Runbook

```sh
# calibrate β_c and evaluate accuracy in one pass
swift run HarnessCLI calibrate-and-eval \
    --fixtures-dir <gravimetric-fixtures> \
    --checkpoint-sha256 "$SHA" \
    --output build/accuracy.json
```

## 11. Iteration loop and segmenter coupling

### Why

This section is the set of couplings that make the segmenter different from a
standalone ML model — get these wrong and the §5 bench stays green while the
shipped app is wrong.

- **Channel ordering is load-bearing and silent on failure** (§2). The Swift
  runtime indexes `ProbabilityTensor` by exact integer offsets for voxel
  ownership *and* macro lookup. Reordering classes during training corrupts the
  app with no crash. Always train against `tools/food_db/generate.py:120-148`.
- **Train/serve colour-space skew is invisible to mIoU** (§5). FoodSeg103 is
  RGB; the device path emits BGRA8 via `PixelBufferAdapter`. Keep the training
  input transform matched to `SegmenterPreProcessor`, and prefer validating a few
  real device captures, not just the public held-out set.
- **Checkpoint provenance.** The `.mlpackage` and `.pt` are gitignored, so there
  is no automatic reproducibility trail. Record, per release, the checkpoint
  SHA-256, the `class_mapping_foodseg103.json` version, the dataset snapshot,
  and the seg-bench / accuracy JSON outputs.

### The loop

> **What to try next:** [`agent-notes/segmenter-improvement-research.md`](agent-notes/segmenter-improvement-research.md) — diagnosis of the ~0.40 held-out mIoU plateau, ranked training-recipe recommendations, and the offline accept/reject threshold for recipe variants.

1. Adjust the class mapping (§3b) and/or training (§4).
2. Retrain → new `checkpoint.pt`.
3. Regenerate fixtures and re-bench mIoU (§5). Read it against the measured noise bands; there is no bar to clear
   (segmenter-foundation Decision 5).
4. Export (§6), bundle, and validate on device (§7).
5. When the gravimetric set exists, calibrate β_c (§9) and check end-to-end
   accuracy (§10).
6. Stamp the new checkpoint's provenance and ship the palette ↔ DB pair together
   (§2).

---

## Related documentation

### Tooling and prerequisites
- [`specs/estimation/pipeline/prerequisites.md`](../specs/estimation/pipeline/prerequisites.md) —
  authoritative project prerequisites (Apple Dev account, Xcode, device,
  datasets, GPU); this document is the ML-specific overlay on top of it.
- [`tools/segmenter/README.md`](../tools/segmenter/README.md) +
  [`export.py`](../tools/segmenter/export.py) — the export pipeline (§6).
- `tools/segmenter/requirements.txt` — the single venv for train + export (§1).

### Spec & decisions behind the bars
- [`specs/estimation/pipeline/requirements.md`](../specs/estimation/pipeline/requirements.md) — Req
  8.2/8.3/8.4/8.7/8.9 (budget, latency, palette, liquids, mIoU), 16.x
  (latency/ANE), 21.x (accuracy), §23 (the Phase 1 dev-stub this replaces).
- [`specs/estimation/pipeline/design.md`](../specs/estimation/pipeline/design.md) — §3.5
  `ProbabilityTensor` channel indexing; §6.9 β_c states; §6.12 palette versioning.
- [`specs/estimation/pipeline/decision_log.md`](../specs/estimation/pipeline/decision_log.md) —
  Decision 8 (composites), 25 (FP16/architecture), 28 (single-checkpoint, ONNX
  bypass).
- [`specs/OVERVIEW.md`](../specs/OVERVIEW.md) — index of every spec + status.

### Runtime wiring
- [`agent-notes/pipeline-wiring-status.md`](agent-notes/pipeline-wiring-status.md)
  — what's built vs what the trained checkpoint unblocks (written before the
  first real checkpoint shipped; see the status note at the top).
- [`architecture.md`](architecture.md) §9 — the `Bundle.main` → `Bundle.module`
  loader alignment, now closed (model-production tasks 1–2; §7).
- [`specs/capture/rawframe-rgb-conversion/`](../specs/capture/rawframe-rgb-conversion/) +
  [`agent-notes/camera-input-fix.md`](agent-notes/camera-input-fix.md) — the
  shipped BGRA8 capture conversion behind the train/serve-skew caveat (§5, §11).
- [`agent-notes/swift-package.md`](agent-notes/swift-package.md) — how bundled
  resources (the `.mlpackage`, food DB) are declared and loaded.

### Sources of truth that must stay in sync (channel ordering — §2)
- [`tools/food_db/generate.py`](../tools/food_db/generate.py) — the `FOOD_DATA` table:
  24 solid + 8 liquid class IDs/names/density/macro/β rows baked into `cofid_db.sqlite`.
  **Train against this ordering.**
- [`ClassPalette.swift`](../MedataCore/Sources/Segmentation/ClassPalette.swift)
  (lines 41–53) — `ClassPalette.standard`, the runtime palette; index order
  must match `FOOD_DATA`.
- `MedataCore/Sources/Segmentation/CoreMLSegmenter.swift` (lines 18–44, 66–91) —
  segmenter constructor + `SegmenterWeightsBudget.validate(at:)` (§1, §7).

### On-device build/validate
- [`ios-device-setup.md`](ios-device-setup.md) — sign and side-load to an
  iPhone 16 Pro (needed for the ANE residency check).
- [`agent-notes/device-build-and-test.md`](agent-notes/device-build-and-test.md)
  — the device build/test loop.
- [`README.md`](README.md) — documentation index and Phase 1/2/3 plan.

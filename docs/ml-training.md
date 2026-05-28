# ML training pipeline

> Audience: anyone training or refining the on-device estimation models.
> Mixed background assumed — ML concepts get a brief sentence, then commands.
> Status: Draft. Sections marked _pending_ are stubs to be filled in as we iterate.

This document is the end-to-end recipe for producing the two model artefacts that
the iOS app depends on at runtime:

1. **The segmenter** — a 27-class semantic segmentation network (`segmenter.mlpackage`)
   bundled into the iOS binary, run on the Apple Neural Engine.
2. **The β_c table** — a per-class bulk-correction factor baked into
   `food_db.sqlite`, applied to volume estimates before macro calculation.

Both are produced offline; neither trains, fine-tunes, or recalibrates on-device.

For project-level prerequisites (Apple Dev account, Xcode, device, fixtures repo)
see [`specs/research/prerequisites.md`](../specs/research/prerequisites.md). This
document is the ML-specific overlay on top of those.

## Contents

1. [Prerequisites & environment](#1-prerequisites--environment)
2. [The 24-class palette](#2-the-24-class-palette) — _pending_
3. [Dataset preparation](#3-dataset-preparation) — _pending_
4. [Training the segmenter](#4-training-the-segmenter) — _pending_
5. [Validating the segmenter](#5-validating-the-segmenter) — _pending_
6. [Exporting to Core ML + TFLite](#6-exporting-to-core-ml--tflite) — _pending_
7. [Bundling into the iOS app](#7-bundling-into-the-ios-app) — _pending_
8. [Capturing gravimetric meal fixtures](#8-capturing-gravimetric-meal-fixtures) — _pending_
9. [Bulk-correction calibration](#9-bulk-correction-calibration) — _pending_
10. [End-to-end accuracy harness](#10-end-to-end-accuracy-harness) — _pending_
11. [Iteration loop and segmenter coupling](#11-iteration-loop-and-segmenter-coupling) — _pending_

---

## 1. Prerequisites & environment

[`specs/research/prerequisites.md`](../specs/research/prerequisites.md) is the
authoritative list of project prerequisites. This section adds the ML-specific
detail not duplicated there.

### Hardware

| For | Hardware |
| --- | --- |
| Segmenter training | Linux/Windows box with a CUDA GPU (RTX 3060 12 GB or better is comfortable; smaller works with a smaller batch size). M-series Mac with MPS is acceptable for short fine-tunes but ~5–10× slower than a mid-range CUDA card. |
| Export to Core ML + TFLite | macOS 14+. `coremltools` requires Apple OS; cross-OS export is not supported. |
| On-device validation | iPhone 12 Pro or later Pro / Pro Max (Req 1.2). Needed for the Apple Neural Engine residency check (Req 16.5) and per-stage latency bar (Req 16.2). |
| β_c gravimetric capture | Calibrated kitchen scale, 1 g resolution or finer; ID-1 reference card (any expired credit / library card); the same iPhone used for on-device validation. |

### Python environment

A single virtualenv covers both training and export. Training deps are added on
top of the existing export requirements in step 4.

```sh
python3 -m venv tools/segmenter/.venv
source tools/segmenter/.venv/bin/activate
pip install -r tools/segmenter/requirements.txt
```

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
| UECFOOD-256 | Permissive (per-image, see source) | Optional supplement for classes thin in FoodSeg103 | <http://foodcam.mobi/dataset256.html> |
| UNIMIB2016 | CC-BY-4.0 | Optional; Anthimopoulos / GoCARB lineage. Bounding boxes mainly — kept here for cross-paper comparison | <http://www.ivl.disco.unimib.it/activities/food-recognition/> |
| Project gravimetric set | Internal | β_c calibration + end-to-end accuracy bar | Captured during step 8 (see caveat below) |

Notes on the academic-paper datasets: Dehais 2017's GoFood is not openly
distributed; the Anthimopoulos / GoCARB lineage relied on UNIMIB-family
detection sets which don't supply pixel-accurate masks. FoodSeg103 is the
single best public starting point for the v1 27-class segmenter and is the
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

`HarnessCLI seg-bench` measures the mIoU bar from Req 8.9 (mean food-class mIoU
≥ 0.60). Carve the held-out split from FoodSeg103: 10–15% of the remapped
images, kept entirely separate from train + val. Use the same fixed RNG seed
for the split so the held-out set is reproducible across training runs.

The bench is invoked with `--fixtures-dir <path>` pointing at the held-out
fixture directory.

### Acceptance bars at a glance

| Bar | Source | Where it's measured |
| --- | --- | --- |
| Segmenter mean food-class mIoU ≥ 0.60 | Req 8.9 | `HarnessCLI seg-bench` |
| Segmenter weights ≤ 10 MB (FP16) | Req 8.2 | `SegmenterWeightsBudget.validate(at:)` |
| Segmenter inference ≤ 250 ms / view on iPhone 12 Pro | Req 8.3 | XCTest with `XCTClockMetric` |
| Segmenter resident on the Apple Neural Engine | Req 16.5 | Xcode → Core ML performance report (manual, post-bundle) |
| End-to-end MAPE < 20% AND MAE ≤ 10 g | Req 21.3 | `HarnessCLI accuracy` |
| ≥ 30 calibration meals per class for `calibrated` β_c status | Req 11.7 | `HarnessCLI calibrate` |

A class that misses the 30-meal bar falls back to a pooled β_c
(`uncalibrated_pooled`) or to β = 1.0 (`uncalibrated_unity`) — both are
permitted v1 states (design §6.9 step 3); the meal record persists which one
was used.

---

## 2. The 24-class palette

The segmenter has **27 output channels**, not 24 (Req 8.4):

- Channels 0–23: 24 food classes
- Channel 24: `background`
- Channel 25: `unknown_food` — pixel looks like food but doesn't match a known class
- Channel 26: `unsupported_liquid` — standalone liquid (excluded from volume; Req 8.7)

Channel ordering is load-bearing. The Swift runtime indexes into the
`ProbabilityTensor` by these exact integer offsets ([design §3.5](../specs/research/design.md#L246)).
If you reorder classes during training, the on-device pipeline breaks
silently — voxel ownership and macro lookup both index by channel.

### Where the canonical list lives

Two sources of truth, kept in sync by hand because they're tiny:

| File | Role |
| --- | --- |
| [tools/food_db/generate.py:78-104](../tools/food_db/generate.py#L78-L104) | The 24 food class IDs + names + density / macro / β rows that get baked into `food_db.sqlite`. |
| [MedataCore/Sources/Segmentation/ClassPalette.swift:41-53](../MedataCore/Sources/Segmentation/ClassPalette.swift#L41-L53) | Swift `ClassPalette.v1Standard` — the runtime palette consumed by `CoreMLSegmenter`. Index order must match `FOOD_DATA`. |

When training, use the Python list — that's the one that maps onto the SQLite
DB and the per-class β_c calibration target.

### Palette ↔ DB edition lock

The palette and `food_db.sqlite` are released as a **versioned pair**
(Req 11.4). The DB's `meta.palette_version` (`v1`) must match the Swift
`ClassPalette.version` (`v1`). Re-derivation across palette versions requires
an explicit class-mapping file ([design §6.12](../specs/research/design.md#L1244));
that's a v2-and-beyond concern — for v1, just don't reorder.

### Class composition (composite vs single-ingredient)

Some classes are composite by design (`mixed_vegetables`, `beans_baked`
includes its tomato sauce, etc.) — a deliberate choice from Decision 8.
Pourable accompaniments served on a solid food (curry sauce on rice, gravy on
roast) are part of the solid's class, not separated out (Req 8.7). When
preparing training masks (step 3), annotate the composite as a single region
rather than splitting it.

### The FoodSeg103 mismatch

FoodSeg103 has **103 classes**; we have 24. The class mapping is the central
problem step 3 has to solve: most FoodSeg103 classes either map onto one of
our 24, fold into a composite (`mixed_vegetables`), or get dropped (anything
that doesn't appear in our palette and can't be merged sensibly).

The mapping table is **not in the repo yet** — building it is part of step 3
and lands at `tools/segmenter/class_mapping_foodseg103_v1.json` when
written.

## 3. Dataset preparation

_Pending._

## 4. Training the segmenter

_Pending. Will land alongside a wireframe `tools/segmenter/train.py`._

## 5. Validating the segmenter

_Pending._

## 6. Exporting to Core ML + TFLite

_Pending._

## 7. Bundling into the iOS app

_Pending._

## 8. Capturing gravimetric meal fixtures

_Pending._

## 9. Bulk-correction calibration

_Pending._

## 10. End-to-end accuracy harness

_Pending._

## 11. Iteration loop and segmenter coupling

_Pending._

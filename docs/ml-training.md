# ML training pipeline

> Audience: anyone training or refining the on-device estimation models.
> Mixed background assumed — ML concepts get a brief sentence, then commands.
> Status: Sections 1–11 drafted (explanation + runbook). The dataset/training/
> fixture scripts named in §§3–5 now exist (`build_class_mapping.py`,
> `prepare_dataset.py`, `train.py`, `make_fixtures.py`), authored and
> smoke-tested on synthetic data; the real runs still need the FoodSeg103
> dataset and a GPU.

This document is the end-to-end recipe for producing the two model artefacts that
the iOS app depends on at runtime:

1. **The segmenter** — a 27-class semantic segmentation network
   (`segmenter.mlpackage`) bundled into the iOS binary, run on the Apple Neural
   Engine. `export.py` writes `segmenter.mlpackage` and
   `PipelineFactory.makeSegmenter` loads that exact name. (Runtime bundling still
   reads it from `Bundle.main` rather than `Bundle.module`; that loader alignment
   is a Phase 3 task — see the "Known gap" note in
   [`architecture.md`](architecture.md) §9.)
2. **The β_c table** — a per-class bulk-correction factor baked into
   `cofid_db.sqlite`, applied to volume estimates before macro calculation.

Both are produced offline; neither trains, fine-tunes, or recalibrates on-device.

For project-level prerequisites (Apple Dev account, Xcode, device, fixtures repo)
see [`specs/estimation/pipeline/prerequisites.md`](../specs/estimation/pipeline/prerequisites.md). This
document is the ML-specific overlay on top of those.

For where this fits in the runtime wiring — what's already built versus what the
trained model unblocks — see
[`agent-notes/pipeline-wiring-status.md`](agent-notes/pipeline-wiring-status.md)
(only the trained checkpoint remains).

## Contents

1. [Prerequisites & environment](#1-prerequisites--environment)
2. [The 24-class palette](#2-the-24-class-palette)
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

### Hardware

| For | Hardware |
| --- | --- |
| Segmenter training | Linux/Windows box with a CUDA GPU (RTX 3060 12 GB or better is comfortable; smaller works with a smaller batch size). M-series Mac with MPS is acceptable for short fine-tunes but ~5–10× slower than a mid-range CUDA card. |
| Export to Core ML + TFLite | macOS 14+. `coremltools` requires Apple OS; cross-OS export is not supported. |
| On-device validation | iPhone 13 Pro Max (Req 1.2 spec floor; iOS 26.5+). Needed for the Apple Neural Engine residency check (Req 16.5) and per-stage latency bar (Req 16.2). |
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
| Segmenter inference ≤ 250 ms / view on iPhone 13 Pro Max (v1 hardware floor) | Req 8.3 | XCTest with `XCTClockMetric` |
| Segmenter resident on the Apple Neural Engine | Req 16.5 | Xcode → Core ML performance report (manual, post-bundle) |
| End-to-end MAPE < 20% AND MAE ≤ 25 g | Req 21.3 | `HarnessCLI accuracy` |
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
`ProbabilityTensor` by these exact integer offsets ([design §3.5](../specs/estimation/pipeline/design.md#L246)).
If you reorder classes during training, the on-device pipeline breaks
silently — voxel ownership and macro lookup both index by channel.

### Where the canonical list lives

Two sources of truth, kept in sync by hand because they're tiny:

| File | Role |
| --- | --- |
| [tools/food_db/generate.py:72-95](../tools/food_db/generate.py#L72-L95) | The 24 food class IDs + names + density / macro / β rows that get baked into `cofid_db.sqlite`. |
| [MedataCore/Sources/Segmentation/ClassPalette.swift:41-53](../MedataCore/Sources/Segmentation/ClassPalette.swift#L41-L53) | Swift `ClassPalette.v1Standard` — the runtime palette consumed by `CoreMLSegmenter`. Index order must match `FOOD_DATA`. |

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

FoodSeg103 has **103 classes**; we have 24. The class mapping is the central
problem step 3 has to solve: most FoodSeg103 classes either map onto one of
our 24, fold into a composite (`mixed_vegetables`), or get dropped (anything
that doesn't appear in our palette and can't be merged sensibly).

The mapping table lives at `tools/segmenter/class_mapping_foodseg103_v1.json`,
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
They are authored and smoke-tested on tiny synthetic data; the real runs still
need the FoodSeg103 dataset (§3a) and a GPU (§1).

## 3. Dataset preparation

### Why

FoodSeg103 is the v1 primary set (§1 "Datasets"). It has 103 classes; we have
24, so the load-bearing artefact of this section is the **class-mapping file**
that collapses 103 → our 27-channel palette. Get this wrong and everything
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

**3b. Build the 103→24 class mapping.** Map each FoodSeg103 class onto one of
our 24, fold it into a composite (`mixed_vegetables`), or drop it. The canonical
24 IDs/names live in `tools/food_db/generate.py:72-95` — map **to that
ordering** (§2), never reorder. Annotate composites as a **single** region:
pourable accompaniments belong to the solid's class (Req 8.7) — curry sauce on
rice is the rice class, not a separate region.

```sh
# produces tools/segmenter/class_mapping_foodseg103_v1.json
python tools/segmenter/build_class_mapping.py \
    --foodseg-labels data/foodseg103/category_id.txt \
    --palette tools/food_db/generate.py \
    --out tools/segmenter/class_mapping_foodseg103_v1.json   # (exists)
```

**3c. Remap masks and cut splits.** Apply the mapping to every PNG mask
(remapping pixel values to the 27-channel palette: 0–23 food, 24 background, 25
`unknown_food`, 26 `unsupported_liquid`), then carve train / val / **held-out**
(10–15%) with a **fixed RNG seed** so the held-out set is reproducible.

```sh
python tools/segmenter/prepare_dataset.py \
    --src data/foodseg103 \
    --mapping tools/segmenter/class_mapping_foodseg103_v1.json \
    --out data/foodseg103_remapped \
    --heldout-frac 0.12 --seed 1234                          # (exists)
```

## 4. Training the segmenter

### Why

The architecture — DeepLabV3 + MobileNetV3-Large at 513×513 — is fixed by
Decision 25 to hit the on-device budget (≤ 10 MB FP16, ≤ 250 ms/view, ANE
residency; §1 acceptance bars). It is a deliberate accuracy-for-feasibility
trade. You transfer-learn: take the torchvision backbone and re-teach a 27-class
head rather than training from scratch. Watch **food-class** mIoU during
training, not overall accuracy — background dominates pixel counts and inflates
the naive number while thin food classes quietly fail the §5 bar.

### Runbook

```sh
python tools/segmenter/train.py \
    --data data/foodseg103_remapped \
    --num-classes 27 --target-size 513 \
    --epochs 60 --batch-size 16 --lr 1e-3 \
    --out tools/segmenter/build/checkpoint.pt                # (exists)
```

Output: a PyTorch checkpoint at `tools/segmenter/build/checkpoint.pt`. This `.pt`
is the **single source of truth** (Decision 28) that both export paths (§6)
consume — there is no separate iOS vs Android training run.

## 5. Validating the segmenter

### Why

The bar is mean **food-class** mIoU ≥ 0.60 (Req 8.9). `HarnessCLI seg-bench`
**(exists)** is the gate, but note how it works: it does **not** run the model.
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

# 5b. Bench (exits non-zero if mean food-class mIoU < 0.60)
SHA=$(shasum -a 256 tools/segmenter/build/checkpoint.pt | cut -d' ' -f1)
swift run HarnessCLI seg-bench \
    --fixtures-dir tests/fixtures/segmenter/heldout \
    --checkpoint-sha256 "$SHA" \
    --output build/seg-bench.json
```

If it fails, revisit the class mapping (§3b) — over-dropping shrinks the
evaluable class set — then retrain. Don't proceed to export until the bar is
green.

## 6. Exporting to Core ML + TFLite

### Why

`tools/segmenter/export.py` **(exists)** consumes the `.pt` checkpoint directly
(the ONNX hop is bypassed per Decision 28) and emits both Core ML (`.mlpackage`,
iOS) and TFLite (future Android), FP16 throughout to fit the ≤ 10 MB budget. It
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
    --num-classes 27 --target-size 513 \
    --reference-image tests/fixtures/segmenter/reference.png \
    --out-coreml MedataCore/Resources/segmenter.mlpackage \
    --out-tflite tools/segmenter/build/segmenter.tflite
```

`--out-coreml` already defaults to `MedataCore/Resources/segmenter.mlpackage` —
the exact name the runtime loader (`PipelineFactory.makeSegmenter`) expects.
Don't rename it. `tests/fixtures/segmenter/reference.png` must exist and be
representative of real plate captures.

## 7. Bundling into the iOS app

### Why

The exported artefact lands at `MedataCore/Resources/segmenter.mlpackage`
(gitignored; bundled at build time). The app selects its inference engine at
compile time: **Debug / `DEV_STUB_SEGMENTER`** uses `StubInferenceEngine` (no
model file, placeholder estimates, `segmenterSource = "dev_stub"`); **Release**
loads the real model via `PipelineFactory` and stamps
`segmenterSource = "coreml_<modelVersion>"`. So to exercise the trained model you
must build Release. The three on-device bars (§1) are only meaningful here — and
ANE residency in particular is a manual check that is easy to miss.

> **Loader tidy-up (tracked, not blocking):** the loader reads
> `segmenter.mlpackage` from `Bundle.main` rather than via `Bundle.module`, and
> the resource is not yet declared in `Package.swift`. Align it to the
> `GRDBFoodDatabase.bundled()` pattern when convenient — see
> [`architecture.md`](architecture.md) §9.

### Runbook

1. Build a **Release** config (so `DEV_STUB_SEGMENTER` is undefined) and
   side-load to an iPhone 13 Pro Max — see
   [`ios-device-setup.md`](ios-device-setup.md) and
   [`agent-notes/device-build-and-test.md`](agent-notes/device-build-and-test.md).
2. Confirm the bars:
   - **Size ≤ 10 MB** — `SegmenterWeightsBudget.validate(at:)` runs at load.
   - **≤ 250 ms / view** — XCTest with `XCTClockMetric`.
   - **ANE residency** — Xcode → Core ML performance report (manual). A model
     that converts fine but falls back to CPU/GPU silently blows the latency bar.
3. Tap the shutter on device → a real `MealRecord` with a non-placeholder carb
   total reaches the result view.

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
  app with no crash. Always train against `tools/food_db/generate.py:72-95`.
- **Train/serve colour-space skew is invisible to mIoU** (§5). FoodSeg103 is
  RGB; the device path emits BGRA8 via `PixelBufferAdapter`. Keep the training
  input transform matched to `SegmenterPreProcessor`, and prefer validating a few
  real device captures, not just the public held-out set.
- **Checkpoint provenance.** The `.mlpackage` and `.pt` are gitignored, so there
  is no automatic reproducibility trail. Record, per release, the checkpoint
  SHA-256, the `class_mapping_foodseg103_v1.json` version, the dataset snapshot,
  and the seg-bench / accuracy JSON outputs.

### The loop

1. Adjust the class mapping (§3b) and/or training (§4).
2. Retrain → new `checkpoint.pt`.
3. Regenerate fixtures and re-bench mIoU (§5). Iterate until ≥ 0.60.
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
  — what's built vs what the trained checkpoint unblocks (only Blocker 1 remains).
- [`architecture.md`](architecture.md) §9 — the `Bundle.main` → `Bundle.module`
  loader gap (§7).
- [`specs/capture/rawframe-rgb-conversion/`](../specs/capture/rawframe-rgb-conversion/) +
  [`agent-notes/camera-input-fix.md`](agent-notes/camera-input-fix.md) — the
  shipped BGRA8 capture conversion behind the train/serve-skew caveat (§5, §11).
- [`agent-notes/swift-package.md`](agent-notes/swift-package.md) — how bundled
  resources (the `.mlpackage`, food DB) are declared and loaded.

### Sources of truth that must stay in sync (channel ordering — §2)
- [`tools/food_db/generate.py`](../tools/food_db/generate.py) (lines 72–95) — the
  24 class IDs/names/density/macro/β rows baked into `cofid_db.sqlite`. **Train
  against this ordering.**
- [`ClassPalette.swift`](../MedataCore/Sources/Segmentation/ClassPalette.swift)
  (lines 41–53) — `ClassPalette.v1Standard`, the runtime palette; index order
  must match `FOOD_DATA`.
- `MedataCore/Sources/Segmentation/CoreMLSegmenter.swift` (lines 18–44, 66–91) —
  segmenter constructor + `SegmenterWeightsBudget.validate(at:)` (§1, §7).

### On-device build/validate
- [`ios-device-setup.md`](ios-device-setup.md) — sign and side-load to an
  iPhone 13 Pro Max (needed for the ANE residency check).
- [`agent-notes/device-build-and-test.md`](agent-notes/device-build-and-test.md)
  — the device build/test loop.
- [`README.md`](README.md) — documentation index and Phase 1/2/3 plan.

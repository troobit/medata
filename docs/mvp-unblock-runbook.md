# MVP unblock runbook — produce the on-device segmenter

> **Audience:** the developer doing the human/GPU/device-gated work.
> **Goal:** get the app to show a **real** carbohydrate number instead of the dev-stub placeholder.
> **Status when written (2026-07-04):** every surrounding subsystem is code-complete; the app
> is blocked on exactly one artefact that no coding agent can produce — a trained
> `segmenter.mlpackage`. FoodSeg103 is **not yet downloaded**; all scripts are in the repo.
> **This is the long-lived operational guide for this stage** — the detailed *how* lives in
> [`ml-training.md`](ml-training.md); this file is the ordered, time-boxed critical path and the
> go/no-go gates. Re-run it every time a new checkpoint is produced.

## Why this is the whole MVP (the what and the why)

The capture → segment → volume → macros pipeline runs end-to-end on device today, but against a
development stub that paints a centred ellipse, so estimates are garbage. Swap in a real model and
the pipeline produces a real number — **nothing else is on the critical path.**

- **The blocker, stated once:** no `segmenter.mlpackage` exists anywhere in the tree; Release builds
  throw `segmenterModelMissing` (`PipelineFactory`). See the gap analysis:
  [`agent-notes/mvp-gap-analysis.md`](agent-notes/mvp-gap-analysis.md) (verdict) and
  [`agent-notes/pipeline-wiring-status.md`](agent-notes/pipeline-wiring-status.md) (what the checkpoint
  unblocks — only Blocker 1 remains).
- **What "done" means:** the composite **MVP gate** — model-production **Req 6.3** — is met only when the
  export-eligibility gates, bundling, ANE residency, and a real on-device capture all hold. It does
  **not** require β_c calibration or the numeric-accuracy bar (both deferred; see step 7).
- **Authoritative human checklist** this runbook operationalises:
  [`specs/estimation/model-production/prerequisites.md`](../specs/estimation/model-production/prerequisites.md).
- **Two myths not to chase:** the "~22 s freeze" is a Debug `-Onone` artefact (Release ≈ 827 ms); and
  OVERVIEW "Done" means code-complete, not accuracy-verified. Both in the gap analysis.

## The 36-hour critical path at a glance

| # | Step | Runs on | Est. time | Go/no-go gate |
|---|------|---------|-----------|----------------|
| 0 | Environment + palette lock | training box | 15 min | venv installs; palette = 35 classes |
| 1 | Acquire FoodSeg103 | training box | 30–60 min | dataset on disk, archive SHA recorded |
| 2 | Build mapping + prep splits | training box (automated) | 10–20 min | mapping summary reviewed |
| 3 | **Train** — the long pole | CUDA GPU **or** Mac MPS | see timing note | checkpoint written |
| 4 | Validate (seg-bench) | any | 10 min | **mean food mIoU ≥ 0.60, each carb class ≥ 0.50** |
| 5 | Export to Core ML | **macOS** | 10 min | export gates pass, `.mlpackage` bundled |
| 6 | **On-device verify = MVP gate** | iPhone 13 Pro Max | 45–60 min | `estimate.end success=true`, `segmenterSource=coreml_…`, carb > 0 |

**Timing and the 36-hour window — read before step 3.** Training is the only step that can blow the
budget. On a CUDA box (RTX 3060 12 GB or better) 60 epochs is a few hours; on a Mac (MPS) it is
**5–10× slower** and 60 epochs may exceed 36 h. So: **measure one epoch first** (step 3), extrapolate,
then decide — use a CUDA box if you have one; on Mac, wrap in `caffeinate -is`, use `train.py --resume`,
and if needed reduce epochs and re-bench (the mIoU gate is what matters, not epoch count). Everything
else in the table is minutes-to-an-hour.

---

## Step 0 — Environment and palette lock

One virtualenv covers training and export ([`ml-training.md` §1](ml-training.md#1-prerequisites--environment)):

```sh
uv venv tools/segmenter/.venv
source tools/segmenter/.venv/bin/activate
uv pip install -r tools/segmenter/requirements.txt
```

**Confirm the palette is locked at 35 classes before training** — training on the wrong channel count
forces a full retrain. The count must be **24 solid + 8 liquid + 3 special = 35**, matching
`MedataCore/Sources/Segmentation/ClassPalette.swift` (`v1Standard`) and `tools/food_db/generate.py`
(`FOOD_DATA`). Channel ordering is load-bearing — never reorder. Detail:
[`ml-training.md` §2](ml-training.md#2-the-class-palette),
[`agent-notes/class-palette.md`](agent-notes/class-palette.md).

## Step 1 — Acquire FoodSeg103 (~30–60 min)

FoodSeg103 is the v1 primary training set. Download **Images/ + Annotations/** into `data/foodseg103/`
and **record the archive SHA** (it goes into `build/lineage.json` as `foodseg103_source`). This is
Stage 0 of [`prerequisites.md`](../specs/estimation/model-production/prerequisites.md); commands in
[`ml-training.md` §3a](ml-training.md#3-dataset-preparation).

```sh
mkdir -p data/foodseg103
# fetch + unzip the release archive from https://xiongweiwu.github.io/foodseg103.html
```

`data/` is gitignored — never commit the dataset.

## Step 2 — Build the mapping and cut splits (automated, ~10–20 min)

```sh
python tools/segmenter/build_class_mapping.py \
    --foodseg-labels data/foodseg103/category_id.txt \
    --palette tools/food_db/generate.py \
    --out tools/segmenter/class_mapping_foodseg103_v1.json

python tools/segmenter/prepare_dataset.py \
    --src data/foodseg103 --mapping tools/segmenter/class_mapping_foodseg103_v1.json \
    --out data/foodseg103_remapped --heldout-frac 0.12 --seed 1234
```

**Review the routing summary** `build_class_mapping.py` prints before training — over-dropping classes
shrinks the set the mIoU gate can measure. FoodSeg103 has no liquid supervision, so channels 24–31 get
little-to-no data; that is expected and deferred (not an MVP blocker). Detail:
[`ml-training.md` §3](ml-training.md#3-dataset-preparation).

## Step 3 — Train the segmenter (the long pole)

DeepLabV3 + MobileNetV3-Large @ 513×513, transfer-learned to a **35-class** head:

```sh
python tools/segmenter/train.py \
    --data data/foodseg103_remapped \
    --num-classes 35 --target-size 513 \
    --epochs 60 --batch-size 16 --lr 1e-3 \
    --out tools/segmenter/build/checkpoint.pt
```

- **`--num-classes 35`** — not 27. The pre-liquid count silently trains a mismatched head (fixed in
  runbook commit `09c841a`).
- **Watch food-class mIoU, not overall accuracy** — background dominates pixel counts and hides thin-class
  failures.
- **Mac hygiene:** `caffeinate -is python tools/segmenter/train.py …`; resume an interrupted run with
  `--resume tools/segmenter/build/checkpoint.pt.resume.pt` (identical hyperparameters — the trainer
  refuses drift). Measure one epoch before committing to the full run.

Detail and run hygiene: [`ml-training.md` §4](ml-training.md#4-training-the-segmenter).

## Step 4 — Validate — GO/NO-GO gate

The bench reads fixtures of the model's predictions over the held-out split (stamped with the checkpoint
SHA) and gates on mIoU:

```sh
python tools/segmenter/make_fixtures.py \
    --checkpoint tools/segmenter/build/checkpoint.pt \
    --heldout data/foodseg103_remapped/heldout \
    --out tests/fixtures/segmenter/heldout

SHA=$(shasum -a 256 tools/segmenter/build/checkpoint.pt | cut -d' ' -f1)
swift run HarnessCLI seg-bench \
    --fixtures-dir tests/fixtures/segmenter/heldout \
    --checkpoint-sha256 "$SHA" --output build/seg-bench.json
```

**Gate (must pass to proceed):**
- **Mean food-class mIoU ≥ 0.60** (exits non-zero otherwise).
- **Every carb-priority class ≥ 0.50:** white_rice, brown_rice, pasta, bread_white, bread_wholemeal,
  potato_boiled, potato_mashed, chips_fries.

**If it fails:** revisit the class mapping (step 2 — over-dropping shrinks the evaluable set), then
retrain. **Do not export a sub-bar checkpoint.** Detail:
[`ml-training.md` §5](ml-training.md#5-validating-the-segmenter). Bars table:
[`ml-training.md` §1 "Acceptance bars"](ml-training.md#1-prerequisites--environment).

## Step 5 — Export to Core ML (on macOS, ~10 min)

`coremltools` is Apple-only; sync the checkpoint to a Mac first.

```sh
python tools/segmenter/export.py \
    --checkpoint tools/segmenter/build/checkpoint.pt \
    --num-classes 35 --target-size 513 \
    --reference-image tests/fixtures/segmenter/reference.png \
    --out-coreml MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage \
    --out-tflite tools/segmenter/build/segmenter.tflite
```

Gates run automatically: **≤ 10 MB FP16 weights, 35 channels in palette order, PyTorch-oracle
equivalence + runtime-preprocessing parity**, and it stamps the 12-hex `model_version` into the Core ML
metadata. **Do not rename the output path** — the loader resolves that exact name via `Bundle.module`
(`architecture.md` §9). The `.mlpackage` is gitignored and bundles automatically once dropped in. Detail:
[`ml-training.md` §6](ml-training.md#6-exporting-to-core-ml--tflite).

## Step 6 — On-device verify — THE MVP GATE

Build **Release** (so `DEV_STUB_SEGMENTER` is undefined and the real model loads) and side-load to an
iPhone 13 Pro Max. Sign/side-load steps: [`ios-device-setup.md`](ios-device-setup.md); build/test loop:
[`agent-notes/device-build-and-test.md`](agent-notes/device-build-and-test.md).

**Confirm all of:**
- **ANE residency** — Xcode → Core ML performance report (manual). A model that converts fine but falls
  back to CPU/GPU silently blows the ≤ 250 ms/view latency bar.
- Tap the shutter → `estimate.end success=true`, `segmenterSource = coreml_<modelVersion>` (**not**
  `dev_stub`), a finite carbohydrate value **> 0**, and a non-degenerate food mask with plausible
  coverage for the plate.

**Fold in here — two uncompiled `App/` edits.** `make build` only compiles the MedataCore SwiftPM core,
not the Xcode target, so these were never compiled: the Δθ readout (`App/ResultView.swift`, commit
`73343f2`) and the Shutter-logger reroute (`App/CaptureFlowModel.swift`, commit `0cb9bf5`). This Release
build is where you confirm they compile clean. Detail:
[`ml-training.md` §7](ml-training.md#7-bundling-into-the-ios-app).

**When this passes, the MVP is unblocked.**

---

## Deferred — explicitly NOT needed for the MVP gate

- **β_c gravimetric calibration** (weighed meals). The MVP ships every class at β = 1.0 /
  `uncalibrated_unity`, a permitted v1 state; calibration only tightens accuracy later. See
  [`ml-training.md` §§8–9](ml-training.md#8-capturing-gravimetric-meal-fixtures).
- **Broadening calibration to more public datasets** — the `cross-dataset-calibration` spec
  ([requirements](../specs/estimation/cross-dataset-calibration/requirements.md) ·
  [design](../specs/estimation/cross-dataset-calibration/design.md)) is planned and deferred behind this
  work; it does not gate the MVP.

## Troubleshooting and pitfalls

| Symptom | Cause / fix |
|---|---|
| Estimates look wrong after shipping the model | `segmenterSource` still `dev_stub` → you built Debug, not Release |
| Latency far above 250 ms/view | Model fell back off the ANE — check the Core ML performance report |
| Export rejects the checkpoint | Channel count ≠ 35, or weights > 10 MB — retrain with `--num-classes 35` |
| mIoU green in bench but bad on device | Train/serve colour-space skew — training transform must match `SegmenterPreProcessor` (BGRA8); validate a few real captures ([`ml-training.md` §11](ml-training.md#11-iteration-loop-and-segmenter-coupling)) |
| Mac training "quietly becomes days" | A hot op fell back to CPU — verify MPS residency; `PYTORCH_ENABLE_MPS_FALLBACK=1` is a safety net only |
| App still throws `segmenterModelMissing` | `.mlpackage` not at `MedataCore/Sources/Pipeline/Resources/` — don't rename the export path |

## For future iterations (why this document is long-lived)

Each new checkpoint repeats steps 3–6; the mapping (step 2) and dataset (step 1) only change when you
add data or revise the palette. **Record per release**, so the run is reproducible: the checkpoint
SHA-256, the `class_mapping_foodseg103_v1.json` version, the dataset snapshot/archive SHA, and the
`seg-bench` JSON. The palette and food DB ship as a **versioned pair** — never reorder classes without a
new palette version. The full iteration loop and coupling notes:
[`ml-training.md` §11](ml-training.md#11-iteration-loop-and-segmenter-coupling).

## References — the why and the what

- **Human checklist:** [`specs/estimation/model-production/prerequisites.md`](../specs/estimation/model-production/prerequisites.md)
- **Detailed recipe:** [`ml-training.md`](ml-training.md) · **Device setup:** [`ios-device-setup.md`](ios-device-setup.md) · **Loader wiring:** [`architecture.md`](architecture.md) §9
- **Why the model is the whole gap:** [`agent-notes/mvp-gap-analysis.md`](agent-notes/mvp-gap-analysis.md) · [`agent-notes/pipeline-wiring-status.md`](agent-notes/pipeline-wiring-status.md) · [`agent-notes/dataset-strategy.md`](agent-notes/dataset-strategy.md)
- **Requirements & design behind the bars:** [`specs/estimation/model-production/`](../specs/estimation/model-production/) (MVP gate Req 6.x) · [`specs/estimation/pipeline/requirements.md`](../specs/estimation/pipeline/requirements.md) (§8 mIoU/budget/latency, §16 ANE, §23 the dev-stub this replaces) · [`specs/estimation/pipeline/design.md`](../specs/estimation/pipeline/design.md) (§3.5 channel indexing)
- **Spec index:** [`specs/OVERVIEW.md`](../specs/OVERVIEW.md)
</content>

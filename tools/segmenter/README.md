# Segmenter training & export pipeline

Builds the 35-class semantic segmenter the iOS app runs on-device. Full
end-to-end recipe (env, dataset, bars, iteration loop) lives in
[`docs/ml-training.md`](../../docs/ml-training.md) — that is the source of truth;
this README is the per-script index.

Architecture: DeepLabV3 + MobileNetV3-Large at 513×513 input, FP16 weights
(decision 25). Output: 35-class semantic segmenter — 24 solid food + 8 coarse
liquid + background + unknown_food + unsupported_liquid (the redefined v1
palette, nutrition5k-calibration Decisions 23/24); channel order is fixed by
`tools/food_db/generate.py` FOOD_DATA / `ClassPalette.v1Standard` and must never
be reordered. The class list must be locked at this final v1 before the
training run starts — the checkpoint's output-channel count must match the
shipped palette (nutrition5k-calibration Req 9.4, Decisions 22–23).

## Scripts (run in order)

| Script | Step | Does |
| --- | --- | --- |
| `build_class_mapping.py` | §3b | FoodSeg103 (103 classes) → 35-channel palette JSON (`class_mapping_foodseg103_v1.json`). Foundational — every later script consumes it. |
| `prepare_dataset.py` | §3c | Remap FoodSeg103 PNG masks via the mapping + cut train/val/held-out splits (fixed seed). |
| `train.py` | §4 | Transfer-learn DeepLabV3+MobileNetV3-Large → `build/checkpoint.pt`. Needs a GPU + dataset. |
| `make_fixtures.py` | §5a | Run a checkpoint over the held-out split → `HarnessCLI seg-bench` fixtures + the export `reference.png`. |
| `export.py` | §6 | `checkpoint.pt` → Core ML `.mlpackage` (+ TFLite), with a numerical-equivalence gate. Runs on macOS. |

The four non-export scripts are authored and smoke-tested on tiny synthetic
data; their real runs need the FoodSeg103 dataset (§3a) and a GPU (§1). Each
follows the same conventions: lazy heavy-imports (importable without torch),
`--help`, and a `main(argv) -> int` entry point.

## Setup

```sh
python -m venv .venv && source .venv/bin/activate
pip install -r tools/segmenter/requirements.txt
```

## Nutrition5k dataset (β_c calibration, not segmenter training)

Nutrition5k (CC BY 4.0 — attribution required) has no per-pixel masks, so it
never feeds the training scripts above. `tools/nutrition5k/ingest.py` bridges
its overhead RGB-D into `.fixture` files for β_c bulk-correction calibration
(spec: `specs/estimation/nutrition5k-calibration/`, which mirrors this layout
in its `prerequisites.md`).

Do **not** pull the full archive — `nutrition5k_dataset.tar.gz` is 181.4 GB,
mostly side-angle video the calibration does not use. Fetch only these
directories from `gs://nutrition5k_dataset/nutrition5k_dataset/` via
`gsutil -m cp -r` (or the gcloud CLI):

- `imagery/realsense_overhead/` — one `dish_<id>/` folder per dish
  (~3.5k of the ~5k dishes carry RGB-D). Ingestion consumes `rgb.png` and
  `depth_raw.png`; `depth_color.png` is an optional visualisation artifact.
- `metadata/` — `dish_metadata_cafe1.csv`, `dish_metadata_cafe2.csv`,
  `ingredients_metadata.csv`.
- `dish_ids/` — including `splits/depth_train_ids.txt` and
  `splits/depth_test_ids.txt` (the depth split is the RGB-D one calibration
  uses; `depth_test_ids.txt` is the held-out eval split).

The local layout lives under the gitignored `data/` directory at the repo
root — N5k imagery and metadata are never committed — and **differs from the
bucket layout**. It is what `ingest.py --n5k-dir` (default `data/`) expects,
and it defines the "required files" for the ingestion tool's startup check:

```
data/
├── n5k/realsense_overhead/dish_<id>/{rgb.png, depth_raw.png, depth_color.png}
├── metadata/{dish_metadata_cafe1.csv, dish_metadata_cafe2.csv, ingredients_metadata.csv}
└── dish_ids/splits/{depth_train_ids.txt, depth_test_ids.txt, rgb_train_ids.txt, rgb_test_ids.txt}
```

The bucket is unversioned, so the release identifier recorded in lineage is
operational: a SHA-256 manifest of the metadata + split files plus the
download date, generated at first ingestion.

## Export

```sh
python tools/segmenter/export.py \
    --checkpoint path/to/fine-tuned.pt \
    --num-classes 35 \
    --target-size 513 \
    --reference-image tests/fixtures/segmenter/reference.png \
    --out-coreml MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage \
    --out-tflite tools/segmenter/build/segmenter.tflite
```

The Core ML artefact lands in
`MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage`, declared as a
`Pipeline` target resource so `Bundle.module` resolves it at build time. The TFLite artefact is a
validation-only output in v1 (decision 28); the Android port consumes the
same checkpoint and re-exports for its target runtime.

## Notes

- ONNX is bypassed. Both export paths consume the PyTorch checkpoint
  directly via `torch.export` / `coremltools.convert` / `ai-edge-torch`.
- The script runs a reference image through both artefacts and asserts
  per-pixel argmax agreement >99% with max abs logit error <0.05. A
  disagreement above that threshold fails the export.
- The Core ML model is FP16 throughout to fit the ≤10 MB weight budget
  (Req 8.2); the iOS `CoreMLSegmenter` runtime validates the bundled
  artefact's size via `SegmenterWeightsBudget.validate(at:)`.

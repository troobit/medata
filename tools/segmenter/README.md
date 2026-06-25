# Segmenter training & export pipeline

Builds the 27-class semantic segmenter the iOS app runs on-device. Full
end-to-end recipe (env, dataset, bars, iteration loop) lives in
[`docs/ml-training.md`](../../docs/ml-training.md) — that is the source of truth;
this README is the per-script index.

Architecture: DeepLabV3 + MobileNetV3-Large at 513×513 input, FP16 weights
(decision 25). Output: 27-class semantic segmenter (24 food + background +
unknown_food + unsupported_liquid); channel order is fixed by
`tools/food_db/generate.py` FOOD_DATA / `ClassPalette.v1Standard` and must never
be reordered.

## Scripts (run in order)

| Script | Step | Does |
| --- | --- | --- |
| `build_class_mapping.py` | §3b | FoodSeg103 (103 classes) → 27-channel palette JSON (`class_mapping_foodseg103_v1.json`). Foundational — every later script consumes it. |
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

## Export

```sh
python tools/segmenter/export.py \
    --checkpoint path/to/fine-tuned.pt \
    --num-classes 27 \
    --target-size 513 \
    --reference-image tests/fixtures/segmenter/reference.png \
    --out-coreml MedataCore/Resources/segmenter.mlpackage \
    --out-tflite tools/segmenter/build/segmenter.tflite
```

The Core ML artefact lands in `MedataCore/Resources/segmenter.mlpackage`
where the iOS app target picks it up at build time. The TFLite artefact is a
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

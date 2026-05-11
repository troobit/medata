# Segmenter export pipeline

Implements task 23 of `specs/research/tasks.md`: PyTorch → Core ML + TFLite
from a single source-of-truth checkpoint (decision 28).

Architecture: DeepLabV3 + MobileNetV3-Large at 513×513 input, FP16 weights
(decision 25). Output: 27-class semantic segmenter (24 food + background +
unknown_food + unsupported_liquid).

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

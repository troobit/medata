#!/usr/bin/env python3
"""Segmenter export pipeline (task 23, decision 28).

Trains-from / fine-tunes DeepLabV3 + MobileNetV3-Large (torchvision) on the
27-class palette (24 food + background + unknown_food + unsupported_liquid),
then exports the **same** PyTorch checkpoint to:

  - Core ML (.mlpackage) for iOS via ``coremltools.convert``.
  - TFLite (.tflite) for the future Android port via ``ai-edge-torch``.

The ONNX hop is bypassed per decision 28: both export paths consume the
PyTorch checkpoint directly. After export, the script runs a reference image
through both artefacts and asserts numerical agreement so the "single source
of truth" portability requirement (decision 2) is mechanically verified.

Usage::

    python tools/segmenter/export.py \\
        --checkpoint path/to/deeplabv3_mbv3_large.pt \\
        --num-classes 27 \\
        --target-size 513 \\
        --reference-image tests/fixtures/segmenter/reference.png \\
        --out-coreml MedataCore/Resources/segmenter.mlpackage \\
        --out-tflite tools/segmenter/build/segmenter.tflite

The script is intended to run on macOS (where ``coremltools`` runs natively)
with PyTorch and ``ai-edge-torch`` installed. The fine-tuning loop itself is
left to the training pipeline; this file deals solely with the post-training
export step.
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Tuple

import numpy as np


def _import_torch():
    try:
        import torch
        import torchvision
        return torch, torchvision
    except ImportError as exc:
        raise SystemExit(
            "PyTorch + torchvision are required. Install with:\n"
            "  pip install torch torchvision"
        ) from exc


def _import_coremltools():
    try:
        import coremltools as ct
        return ct
    except ImportError as exc:
        raise SystemExit(
            "coremltools is required. Install with:\n"
            "  pip install 'coremltools>=8.0'"
        ) from exc


def _import_ai_edge_torch():
    try:
        import ai_edge_torch
        return ai_edge_torch
    except ImportError as exc:
        raise SystemExit(
            "ai-edge-torch is required for TFLite export. Install with:\n"
            "  pip install ai-edge-torch"
        ) from exc


def load_checkpoint(num_classes: int, checkpoint_path: str | None):
    """Load DeepLabV3 + MobileNetV3-Large; replace head for num_classes (decision 25)."""
    torch, torchvision = _import_torch()
    from torchvision.models.segmentation import (
        deeplabv3_mobilenet_v3_large, DeepLabV3_MobileNet_V3_Large_Weights,
    )
    from torchvision.models.segmentation.deeplabv3 import DeepLabHead

    weights = DeepLabV3_MobileNet_V3_Large_Weights.DEFAULT
    model = deeplabv3_mobilenet_v3_large(weights=weights, aux_loss=False)
    in_ch = model.classifier[0].convs[0][0].in_channels
    model.classifier = DeepLabHead(in_ch, num_classes)
    if checkpoint_path is not None and Path(checkpoint_path).is_file():
        state = torch.load(checkpoint_path, map_location="cpu")
        if isinstance(state, dict) and "model" in state:
            state = state["model"]
        model.load_state_dict(state, strict=False)
    model.eval()
    return model


def reference_input(target_size: int, image_path: str | None) -> "np.ndarray":
    """Load reference image as FP32 [1, 3, target_size, target_size]; falls back to a
    deterministic synthetic image when no path is supplied."""
    if image_path and Path(image_path).is_file():
        from PIL import Image
        img = Image.open(image_path).convert("RGB").resize((target_size, target_size))
        arr = np.asarray(img, dtype=np.float32) / 255.0
    else:
        rng = np.random.default_rng(seed=0)
        arr = rng.random((target_size, target_size, 3), dtype=np.float32)
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    arr = (arr - mean) / std
    arr = arr.transpose(2, 0, 1)[None, ...]  # [1, 3, H, W]
    return arr.astype(np.float32)


def export_coreml(model, target_size: int, num_classes: int, out_path: str) -> None:
    """torch.export → coremltools.convert(...) → .mlpackage (decision 28, FP16 per
    decision 25). Forces FP16 precision for both compute and weights to fit the
    ≤10 MB budget (Req 8.2)."""
    torch, _ = _import_torch()
    ct = _import_coremltools()

    example = torch.randn(1, 3, target_size, target_size, dtype=torch.float32)
    # torchvision's segmentation model returns a dict with "out". Wrap so the
    # exporter sees a tensor output.
    class Wrapper(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m
        def forward(self, x):
            return self.m(x)["out"]

    wrapped = Wrapper(model).eval()
    with torch.no_grad():
        traced = torch.jit.trace(wrapped, example, strict=False)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="input", shape=example.shape, dtype=np.float16)],
        outputs=[ct.TensorType(name="logits", dtype=np.float16)],
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.ALL,        # ANE-eligible (req 16.5)
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
    )
    mlmodel.short_description = (
        f"medata-orbit segmenter, {num_classes} classes, {target_size}x{target_size} input"
    )
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(out))


def export_tflite(model, target_size: int, out_path: str) -> None:
    """torch.export → ai-edge-torch → .tflite (decision 28)."""
    torch, _ = _import_torch()
    aet = _import_ai_edge_torch()

    example = (torch.randn(1, 3, target_size, target_size, dtype=torch.float32),)
    class Wrapper(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m
        def forward(self, x):
            return self.m(x)["out"]
    wrapped = Wrapper(model).eval()
    edge = aet.convert(wrapped, example)
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    edge.export(str(out))


def run_coreml(out_path: str, x_chw: "np.ndarray") -> "np.ndarray":
    ct = _import_coremltools()
    model = ct.models.MLModel(out_path)
    pred = model.predict({"input": x_chw.astype(np.float16)})
    # Output is FP16 logits; promote to FP32 for comparison.
    return np.asarray(list(pred.values())[0], dtype=np.float32)


def run_tflite(out_path: str, x_chw: "np.ndarray") -> "np.ndarray":
    # Use TensorFlow's lite interpreter; it ships with ai-edge-torch.
    try:
        import tensorflow as tf
    except ImportError as exc:
        raise SystemExit("tensorflow is required to load TFLite for validation") from exc
    interpreter = tf.lite.Interpreter(model_path=out_path)
    interpreter.allocate_tensors()
    in_det = interpreter.get_input_details()[0]
    out_det = interpreter.get_output_details()[0]
    interpreter.set_tensor(in_det["index"], x_chw.astype(in_det["dtype"]))
    interpreter.invoke()
    return interpreter.get_tensor(out_det["index"]).astype(np.float32)


def numerical_agreement(a: "np.ndarray", b: "np.ndarray", tol: float = 5e-2) -> Tuple[float, bool]:
    """Compare two logit tensors via per-pixel argmax agreement and max abs error."""
    a = a.squeeze()
    b = b.squeeze()
    if a.shape != b.shape:
        return float("inf"), False
    err = float(np.max(np.abs(a - b)))
    # Argmax agreement (the practical signal for a segmenter).
    ax = np.argmax(a, axis=0)
    bx = np.argmax(b, axis=0)
    agreement = float((ax == bx).mean())
    ok = (err < tol) and (agreement > 0.99)
    return err, ok


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", default=None,
                        help="Optional path to a fine-tuned state dict; otherwise the "
                             "torchvision ImageNet+VOC checkpoint is used.")
    parser.add_argument("--num-classes", type=int, default=27)
    parser.add_argument("--target-size", type=int, default=513)
    parser.add_argument("--reference-image", default=None,
                        help="Optional PNG for the equivalence check.")
    parser.add_argument("--out-coreml", default="MedataCore/Resources/segmenter.mlpackage")
    parser.add_argument("--out-tflite", default="tools/segmenter/build/segmenter.tflite")
    parser.add_argument("--skip-tflite", action="store_true",
                        help="Skip the TFLite export (validation only in v1).")
    parser.add_argument("--skip-validation", action="store_true",
                        help="Skip the numerical equivalence check.")
    args = parser.parse_args(argv)

    model = load_checkpoint(args.num_classes, args.checkpoint)

    print(f"[export] Core ML → {args.out_coreml}")
    export_coreml(model, args.target_size, args.num_classes, args.out_coreml)

    if not args.skip_tflite:
        print(f"[export] TFLite → {args.out_tflite}")
        export_tflite(model, args.target_size, args.out_tflite)

    if not args.skip_validation:
        print("[validate] running reference image through both artefacts")
        x = reference_input(args.target_size, args.reference_image)
        coreml_out = run_coreml(args.out_coreml, x)
        if not args.skip_tflite:
            tflite_out = run_tflite(args.out_tflite, x)
            err, ok = numerical_agreement(coreml_out, tflite_out)
            print(f"[validate] max abs error = {err:.4f}; agree = {ok}")
            if not ok:
                print("[validate] FAILED — Core ML and TFLite disagree", file=sys.stderr)
                return 2

    print("[export] done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

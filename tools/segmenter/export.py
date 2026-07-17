#!/usr/bin/env python3
"""Segmenter export pipeline (task 23, decision 28).

Trains-from / fine-tunes DeepLabV3 + MobileNetV3-Large (torchvision) on the
35-class palette (24 solid + 8 coarse liquid + background + unknown_food +
unsupported_liquid — the redefined v1, Decisions 23/24),
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
        --num-classes 35 \\
        --target-size 513 \\
        --reference-image tests/fixtures/segmenter/reference.png \\
        --out-coreml MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage \\
        --out-tflite tools/segmenter/build/segmenter.tflite

The script is intended to run on macOS (where ``coremltools`` runs natively)
with PyTorch and ``ai-edge-torch`` installed. The fine-tuning loop itself is
left to the training pipeline; this file deals solely with the post-training
export step.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import sys
from pathlib import Path
from typing import Tuple

import numpy as np


def _load_lineage_module():
    """Import the sibling lineage.py by path (pure stdlib; no torch needed)."""
    lineage_path = Path(__file__).resolve().with_name("lineage.py")
    spec = importlib.util.spec_from_file_location("segmenter_lineage", lineage_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Could not load sibling lineage module at {lineage_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_archs_module():
    """Import the sibling archs.py by NAME via sys.path (the loss_config
    pattern) so export, train, and validation all dispatch through the SAME
    registry instance (snaq-parity Decision 14). Torch-free import."""
    tools_dir = str(Path(__file__).resolve().parent)
    if tools_dir not in sys.path:
        sys.path.insert(0, tools_dir)
    import archs
    return archs


def emit_lineage(checkpoint_path: str, out_path: str | None = None) -> str:
    """Write build/lineage.json for the checkpoint being exported (Req 1.3, task 3).

    Reconstructs ``train_config`` from the provenance keys ``train.py`` saves into
    the checkpoint dict; the checkpoint SHA-256 join key (and its 12-hex
    ``model_version``) is what task 7 stamps into the Core ML metadata. Returns
    the ``model_version`` so the caller can stamp it without re-reading the file.
    """
    torch, _ = _import_torch()
    lineage = _load_lineage_module()
    raw = torch.load(checkpoint_path, map_location="cpu")
    train_config: dict = {}
    if isinstance(raw, dict):
        train_config = {
            k: raw[k] for k in (
                "num_classes", "target_size", "epochs", "lr", "lr_schedule",
                "augment", "pretrained", "arch"
            ) if k in raw
        }
    manifest = lineage.build_lineage(
        checkpoint_path,
        train_config=train_config,
        palette_version=raw.get("palette_version") if isinstance(raw, dict) else None,
    )
    # A re-export of the SAME checkpoint must not wipe validation metrics (or a
    # release override) already recorded in the existing lineage file.
    lineage.preserve_metrics(manifest, out_path or lineage.DEFAULT_LINEAGE_PATH)
    written = lineage.write_lineage(
        manifest, out_path or lineage.DEFAULT_LINEAGE_PATH
    )
    print(f"[export] lineage → {written} (model_version={manifest['model_version']})")
    return manifest["model_version"]


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


def load_checkpoint(num_classes: int, checkpoint_path: str | None,
                    arch: str | None = None):
    """Load a checkpoint through the architecture registry (archs.py).

    ``arch`` None resolves the architecture from the checkpoint file's own
    provenance keys (absence — or no checkpoint — means the historical
    ``deeplab_mnv3``), so exporting a trained bake-off winner needs no extra
    flag. The deeplab path is byte-identical to the pre-registry construction
    (decision 25 head swap; snaq-parity Decision 14 moved it into archs.py).
    """
    archs = _load_archs_module()
    if arch is None:
        arch = archs.arch_from_checkpoint(checkpoint_path)
    return archs.get(arch).load_checkpoint(num_classes, checkpoint_path)


def reference_input(target_size: int, image_path: str | None) -> "np.ndarray":
    """Load reference image as FP32 [1, 3, target_size, target_size]; falls back to a
    deterministic synthetic image when no path is supplied."""
    if image_path and Path(image_path).is_file():
        from PIL import Image, ImageOps
        # exif_transpose matches the train.py loader: orientation-tagged JPEGs
        # must be rotated before resize or the pixels skew against their masks.
        img = ImageOps.exif_transpose(Image.open(image_path))
        img = img.convert("RGB").resize((target_size, target_size))
        arr = np.asarray(img, dtype=np.float32) / 255.0
    else:
        rng = np.random.default_rng(seed=0)
        arr = rng.random((target_size, target_size, 3), dtype=np.float32)
    mean = np.array([0.485, 0.456, 0.406], dtype=np.float32)
    std = np.array([0.229, 0.224, 0.225], dtype=np.float32)
    arr = (arr - mean) / std
    arr = arr.transpose(2, 0, 1)[None, ...]  # [1, 3, H, W]
    return arr.astype(np.float32)


def _logits_wrapper(model, forward_logits=None):
    """Wrap a model so the exporters see a plain logits tensor at input
    resolution — the arch registry's forward normaliser (default: torchvision's
    ``["out"]`` dict convention). Traceable for torch.jit / coremltools."""
    torch, _ = _import_torch()
    archs = _load_archs_module()
    normalise = forward_logits or archs.dict_out_logits

    class Wrapper(torch.nn.Module):
        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, x):
            return normalise(self.m, x)

    return Wrapper(model).eval()


def export_coreml(model, target_size: int, num_classes: int, out_path: str,
                  model_version: str | None = None, forward_logits=None) -> None:
    """torch.export → coremltools.convert(...) → .mlpackage (decision 28, FP16 per
    decision 25). Forces FP16 precision for both compute and weights to fit the
    ≤10 MB budget (Req 8.2). Stamps ``model_version`` (the 12-hex checkpoint id)
    into the model's user-defined metadata under ``MODEL_VERSION_METADATA_KEY`` so
    a persisted meal traces to its build (Req 5.4, read back by
    CoreMLInferenceEngine.resolveModelVersion)."""
    torch, _ = _import_torch()
    ct = _import_coremltools()

    example = torch.randn(1, 3, target_size, target_size, dtype=torch.float32)
    wrapped = _logits_wrapper(model, forward_logits)
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
    if model_version:
        # Contract key shared with CoreMLInferenceEngine.modelVersionMetadataKey.
        mlmodel.user_defined_metadata[MODEL_VERSION_METADATA_KEY] = model_version
    out = Path(out_path)
    out.parent.mkdir(parents=True, exist_ok=True)
    mlmodel.save(str(out))


def export_tflite(model, target_size: int, out_path: str,
                  forward_logits=None) -> None:
    """torch.export → ai-edge-torch → .tflite (decision 28)."""
    torch, _ = _import_torch()
    aet = _import_ai_edge_torch()

    example = (torch.randn(1, 3, target_size, target_size, dtype=torch.float32),)
    wrapped = _logits_wrapper(model, forward_logits)
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


def run_pytorch(model, x_chw: "np.ndarray", forward_logits=None) -> "np.ndarray":
    """The equivalence ORACLE (Req 4.3): the PyTorch checkpoint's logits for a
    CHW [1, 3, H, W] input. Core ML and TFLite are validated against THIS, not
    against each other. ``forward_logits`` (the arch registry normaliser) keeps
    the oracle on the same output convention as the exported artefact; the
    default handles the historical dict-or-tensor forms."""
    torch, _ = _import_torch()
    with torch.no_grad():
        t = torch.from_numpy(np.ascontiguousarray(x_chw)).float()
        if forward_logits is not None:
            out = forward_logits(model, t)
        else:
            out = model(t)
            out = out["out"] if isinstance(out, dict) else out
    return out.cpu().numpy().astype(np.float32)


def read_coreml_output_channels(out_path: str) -> int:
    """Channel dimension of the exported Core ML model's logit output (for the
    Req 4.4 gate). coremltools-gated; runs only during a real export."""
    ct = _import_coremltools()
    model = ct.models.MLModel(out_path)
    out_desc = model.get_spec().description.output[0]
    dims = list(out_desc.type.multiArrayType.shape)
    # Strip a leading batch dim; channels is the first non-spatial dim (NCHW/CHW).
    while dims and dims[0] <= 1:
        dims = dims[1:]
    return int(dims[0]) if dims else 0


# ──────────────────────────────────────────────────────────────────────────────
# Export gates (Req 4.2–4.5, model-production tasks 6/7)
#
# These are the pure, torch/coremltools-free predicates that decide whether an
# exported artefact is shippable. They are unit-tested directly (task 6); the
# wiring in main() that produces their inputs (reading channels off a real Core ML
# model, running the PyTorch oracle) is gated on a trained checkpoint (stage 3).
# ──────────────────────────────────────────────────────────────────────────────

# Mirrors SegmenterWeightsBudget.maxBytes (CoreMLSegmenter.swift) — pipeline Req 8.2
# as amended by Decision 13: DeepLabV3+MobileNetV3-Large (Decision 25) is 11.03 M
# params = 22.1 MB at FP16, so the original 10 MB budget was unachievable for this
# architecture. 24 MiB fits FP16 with headroom and still catches an accidental
# FP32 export (~44 MB).
WEIGHTS_MAX_BYTES = 24 * 1024 * 1024
# v1 palette channel count (24 solid + 8 liquid + background + unknown_food +
# unsupported_liquid — redefined v1, Decisions 23/24).
EXPECTED_CHANNEL_COUNT = 35
# Equivalence oracle thresholds (Req 4.3 as amended by Decision 14). Argmax
# agreement is the functional bar; the abs-logit bar was recalibrated from 0.05
# after the first real FP16 export measured drift of 0.13 (synthetic input) /
# 0.30 (real image) on ~±20-magnitude logits with argmax agreement >= 0.9985.
# Real weight corruption shifts logits by whole units and collapses argmax.
ORACLE_ARGMAX_MIN = 0.99
ORACLE_MAX_ABS_ERR = 0.5
# Contract key shared with CoreMLInferenceEngine.modelVersionMetadataKey (Swift).
MODEL_VERSION_METADATA_KEY = "medata.modelVersion"

_MAPPING_PATH = Path(__file__).resolve().with_name("class_mapping_foodseg103_v1.json")


class ExportGateError(RuntimeError):
    """Raised when an export gate fails (budget, channel count, oracle, parity)."""


def palette_channel_names() -> list[str]:
    """The 35 v1 channel names in palette/index order, read from the committed
    class-mapping file (the single source of truth shared with ClassPalette.v1Standard)."""
    import json
    d = json.loads(_MAPPING_PATH.read_text())
    channels = sorted(d["target_channels"], key=lambda c: c["index"])
    return [c["name"] for c in channels]


def validate_channel_count(num_channels: int) -> None:
    """Req 4.4: the exported model must declare exactly 35 output channels."""
    if num_channels != EXPECTED_CHANNEL_COUNT:
        raise ExportGateError(
            f"channel count {num_channels} != expected {EXPECTED_CHANNEL_COUNT} "
            "(palette order of design §3.3)"
        )


def mlpackage_weight_bytes(path: str) -> int:
    """Recursive sum of regular-file sizes under an .mlpackage directory, mirroring
    SegmenterWeightsBudget.totalBytes (CoreMLSegmenter.swift)."""
    p = Path(path)
    if not p.exists():
        raise ExportGateError(f"path does not exist: {p}")
    if p.is_file():
        return p.stat().st_size
    return sum(f.stat().st_size for f in p.rglob("*") if f.is_file())


def validate_weight_budget(path: str, max_bytes: int = WEIGHTS_MAX_BYTES) -> int:
    """Req 4.2 (amended, Decision 13): exported weights ≤ 24 MiB. Returns the size."""
    size = mlpackage_weight_bytes(path)
    if size > max_bytes:
        raise ExportGateError(f"weights {size} bytes exceed budget {max_bytes} bytes")
    return size


def _resize_bilinear(img: "np.ndarray", out_h: int, out_w: int) -> "np.ndarray":
    """Half-pixel-centre bilinear resize of an HxWx3 FP32 image (matches the
    PreProcessing.swift mapping closely enough for the equivalence oracle, which
    feeds the SAME preprocessed input to both checkpoint and artefact)."""
    in_h, in_w = img.shape[:2]
    if (in_h, in_w) == (out_h, out_w):
        return img.astype(np.float32)
    ys = np.clip((np.arange(out_h) + 0.5) * in_h / out_h - 0.5, 0, in_h - 1)
    xs = np.clip((np.arange(out_w) + 0.5) * in_w / out_w - 0.5, 0, in_w - 1)
    y0 = np.floor(ys).astype(int); y1 = np.minimum(y0 + 1, in_h - 1)
    x0 = np.floor(xs).astype(int); x1 = np.minimum(x0 + 1, in_w - 1)
    wy = (ys - y0)[:, None, None]; wx = (xs - x0)[None, :, None]
    top = img[y0][:, x0] * (1 - wx) + img[y0][:, x1] * wx
    bot = img[y1][:, x0] * (1 - wx) + img[y1][:, x1] * wx
    return (top * (1 - wy) + bot * wy).astype(np.float32)


def preprocess_reference(
    rgb01: "np.ndarray",
    target_size: int,
    mean: Tuple[float, float, float] = (0.485, 0.456, 0.406),
    std: Tuple[float, float, float] = (0.229, 0.224, 0.225),
) -> "np.ndarray":
    """Req 4.5: replicate the RUNTIME preprocessing path (PreProcessing.swift) so
    oracle inputs match what the device feeds the model — aspect-preserving
    letterbox scale (longest side → target_size, bilinear), ImageNet normalise,
    then top-left pad to target×target with pad[c] = (0 − mean[c]) / std[c].

    Input: HxWx3 RGB in [0, 1]. Output: target×target×3 FP32, HWC (the layout the
    Swift path emits before its FP16 cast). The caller transposes to CHW for the
    PyTorch oracle.
    """
    h, w = rgb01.shape[:2]
    mean_a = np.asarray(mean, dtype=np.float32)
    std_a = np.asarray(std, dtype=np.float32)
    scale = target_size / max(w, h)
    scaled_w = max(1, round(w * scale))
    scaled_h = max(1, round(h * scale))
    resized = _resize_bilinear(rgb01.astype(np.float32), scaled_h, scaled_w)
    normalised = (resized - mean_a) / std_a
    pad = (0.0 - mean_a) / std_a
    canvas = np.empty((target_size, target_size, 3), dtype=np.float32)
    canvas[:] = pad
    canvas[:scaled_h, :scaled_w, :] = normalised
    return canvas


def oracle_agreement(a: "np.ndarray", b: "np.ndarray") -> Tuple[float, float, bool]:
    """Equivalence oracle (Req 4.3, amended by Decision 14): compare two CxHxW
    logit tensors by per-pixel argmax agreement and max abs logit error. Passes
    when agreement > 99% AND max abs error < 0.5 (FP16-compute drift tolerance).
    Returns (max_abs_err, argmax_agreement, ok)."""
    a = a.squeeze()
    b = b.squeeze()
    if a.shape != b.shape:
        return float("inf"), 0.0, False
    err = float(np.max(np.abs(a - b)))
    agreement = float((np.argmax(a, axis=0) == np.argmax(b, axis=0)).mean())
    ok = (err < ORACLE_MAX_ABS_ERR) and (agreement > ORACLE_ARGMAX_MIN)
    return err, agreement, ok


def model_version_from_lineage(lineage_path: str) -> str:
    """Read the 12-hex model_version from a build/lineage.json (the value
    export_coreml stamps into the Core ML metadata; links tasks 3, 5, 7)."""
    import json
    return str(json.loads(Path(lineage_path).read_text())["model_version"])


def build_reference_chw(target_size: int, image_path: str | None) -> "np.ndarray":
    """Oracle input: load an RGB image (or a deterministic synthetic one), run it
    through the runtime preprocessing path (Req 4.5), and return CHW [1, 3, H, W].
    The SAME array feeds the PyTorch oracle and the exported artefact."""
    if image_path and Path(image_path).is_file():
        from PIL import Image
        img = Image.open(image_path).convert("RGB")
        rgb01 = np.asarray(img, dtype=np.float32) / 255.0
    else:
        rng = np.random.default_rng(seed=0)
        rgb01 = rng.random((target_size, target_size, 3), dtype=np.float32)
    hwc = preprocess_reference(rgb01, target_size)        # runtime path (Req 4.5)
    chw = hwc.transpose(2, 0, 1)[None, ...]               # → [1, 3, H, W]
    return np.ascontiguousarray(chw, dtype=np.float32)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checkpoint", default=None,
                        help="Optional path to a fine-tuned state dict; otherwise the "
                             "torchvision ImageNet+VOC checkpoint is used.")
    parser.add_argument("--num-classes", type=int, default=35)
    parser.add_argument("--target-size", type=int, default=513)
    parser.add_argument("--reference-image", default=None,
                        help="Optional PNG for the equivalence check.")
    parser.add_argument("--out-coreml",
                        default="MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage")
    parser.add_argument("--out-tflite", default="tools/segmenter/build/segmenter.tflite")
    parser.add_argument("--skip-tflite", action="store_true",
                        help="Skip the TFLite export (validation only in v1).")
    parser.add_argument("--skip-validation", action="store_true",
                        help="Skip the numerical equivalence check.")
    args = parser.parse_args(argv)

    # Arch resolved from the checkpoint's own provenance (absence means the
    # historical deeplab_mnv3) so a trained bake-off winner exports without a
    # flag — snaq-parity Decision 14: train, judge, and export share archs.py.
    archs = _load_archs_module()
    arch = archs.arch_from_checkpoint(args.checkpoint)
    arch_spec = archs.get(arch)
    print(f"[export] arch = {arch}")
    model = load_checkpoint(args.num_classes, args.checkpoint, arch=arch)

    # Build-lineage manifest (Req 1.3, task 3) + the 12-hex model_version to stamp
    # into the Core ML metadata (Req 5.4, task 7). Only when exporting a real
    # checkpoint — without one there is no SHA-256 to anchor reproducibility.
    model_version: str | None = None
    if args.checkpoint and Path(args.checkpoint).is_file():
        model_version = emit_lineage(args.checkpoint)
    else:
        print("[export] no --checkpoint file; skipping lineage manifest + version stamp")

    print(f"[export] Core ML → {args.out_coreml}")
    export_coreml(model, args.target_size, args.num_classes, args.out_coreml,
                  model_version=model_version,
                  forward_logits=arch_spec.forward_logits)

    if not args.skip_tflite:
        print(f"[export] TFLite → {args.out_tflite}")
        export_tflite(model, args.target_size, args.out_tflite,
                      forward_logits=arch_spec.forward_logits)

    # ── Export gates (Req 4.2, 4.4) ──────────────────────────────────────────
    try:
        size = validate_weight_budget(args.out_coreml)
        print(f"[gate] weights = {size} bytes (≤ {WEIGHTS_MAX_BYTES})")
        channels = read_coreml_output_channels(args.out_coreml)
        validate_channel_count(channels)
        print(f"[gate] output channels = {channels}")
    except ExportGateError as exc:
        print(f"[gate] FAILED — {exc}", file=sys.stderr)
        return 3

    # ── Equivalence oracle (Req 4.3) + preprocessing parity (Req 4.5) ─────────
    # The PyTorch checkpoint is the oracle; Core ML (and TFLite, if produced) are
    # validated against it, NOT against each other. Inputs flow through the
    # runtime preprocessing path so a train/inference mismatch surfaces here.
    if not args.skip_validation:
        print("[validate] oracle = PyTorch checkpoint; feeding runtime-preprocessed input")
        x = build_reference_chw(args.target_size, args.reference_image)
        oracle_out = run_pytorch(model, x, forward_logits=arch_spec.forward_logits)

        coreml_out = run_coreml(args.out_coreml, x)
        err, agree, ok = oracle_agreement(oracle_out, coreml_out)
        print(f"[validate] Core ML vs oracle: max abs err = {err:.4f}, argmax agree = {agree:.4f}, ok = {ok}")
        if not ok:
            print("[validate] FAILED — Core ML disagrees with the PyTorch oracle", file=sys.stderr)
            return 2

        if not args.skip_tflite:
            tflite_out = run_tflite(args.out_tflite, x)
            err, agree, ok = oracle_agreement(oracle_out, tflite_out)
            print(f"[validate] TFLite vs oracle: max abs err = {err:.4f}, argmax agree = {agree:.4f}, ok = {ok}")
            if not ok:
                print("[validate] FAILED — TFLite disagrees with the PyTorch oracle", file=sys.stderr)
                return 2

    print("[export] done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

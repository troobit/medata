#!/usr/bin/env python3
"""State-dict adapter probe: timm MobileNetV3-Large (in21k-MIL) → torchvision graph.

segmenter-foundation design §4.2 / Decisions 17 and 19. Candidate 1 for the
recipe upgrade's initialisation is timm
``mobilenetv3_large_100.miil_in21k_ft_in1k`` (ImageNet-21k MIL pretraining —
the strongest documented pretraining for this exact backbone; Apache-2.0 per
its Hugging Face model card). The training pipeline builds the TORCHVISION
MobileNetV3-Large graph (via ``export.load_checkpoint``, Decision 28), whose
layer naming differs from timm's, so the timm weights need a state-dict
adapter. Decision 17 adopts the timm checkpoint ONLY IF this probe round-trips:
identical logits on a probe input from (a) timm-native inference and (b) the
adapted state dict loaded into the torchvision graph.

Both implementations register the same MobileNetV3-Large 1.0x layer sequence
(paper table 1), so the adapter maps tensors POSITIONALLY, asserting shapes
match at every step (the classifier head needs one reshape: timm's 1x1
``conv_head`` [1280, 960, 1, 1] → torchvision's ``classifier.0`` linear
[1280, 960] — mathematically identical after global pooling). Any positional
shape mismatch means the graphs diverge and the probe FAILS — Decision 17 then
falls back to torchvision ``MobileNet_V3_Large_Weights.IMAGENET1K_V2``.

RUN REQUIREMENTS (gated session — this script is written ahead of it and must
NOT be run in an environment without the training deps): torch, torchvision,
and timm (probe-only dependency, installed ad hoc: ``pip install timm``).
Running it downloads the timm weights (~22 MiB) from Hugging Face.

Usage::

    python tools/segmenter/adapter_probe.py \\
        [--image path/to/probe.jpg] [--tolerance 1e-4] \\
        [--save-adapted tools/segmenter/build/mnv3l_miil_torchvision.pt]

Exit code 0 = round-trip PASSED (identical logits within tolerance); 1 =
FAILED (shape mismatch or logit divergence) — record either outcome against
Decision 19.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Optional

TIMM_MODEL = "mobilenetv3_large_100.miil_in21k_ft_in1k"

# FP32 CPU inference of the same graph with the same weights should agree to
# float rounding; 1e-4 on ~±10-magnitude logits is "identical" for Decision 17
# while still catching any real graph divergence (BN epsilon, activation
# placement), which shows up orders of magnitude larger.
DEFAULT_TOLERANCE = 1e-4

PROBE_SIZE = 224  # both classifiers are 224x224 ImageNet models


def _import_heavy():
    try:
        import timm
        import torch
        import torchvision
    except ImportError as exc:
        raise SystemExit(
            "The probe needs torch, torchvision and timm (probe-only, not in "
            "requirements.txt). Install with:\n"
            "  pip install -r tools/segmenter/requirements.txt timm"
        ) from exc
    return torch, torchvision, timm


def adapt_state_dict(timm_sd: dict, tv_sd: dict) -> dict:
    """Positionally map timm tensors onto torchvision keys, shape-checked.

    Both state dicts enumerate the same registration order for the same
    architecture (stem conv/bn → 15 inverted-residual blocks with SE →
    final 960-channel conv/bn → 1280 head → 1000-class classifier). A tensor
    is accepted when shapes match exactly or when the timm side is a 1x1 conv
    whose squeeze matches a torchvision linear (the head). Raises SystemExit
    naming the first divergence otherwise — a mismatch means the graphs are
    NOT the same network and the adapter is infeasible (Decision 17 → fall
    back to torchvision IMAGENET1K_V2).
    """
    timm_items = list(timm_sd.items())
    tv_keys = list(tv_sd.keys())
    if len(timm_items) != len(tv_keys):
        raise SystemExit(
            f"[probe] tensor-count mismatch: timm has {len(timm_items)} "
            f"entries, torchvision {len(tv_keys)} — graphs differ, adapter "
            "infeasible"
        )
    adapted = {}
    for (timm_key, tensor), tv_key in zip(timm_items, tv_keys):
        want = tv_sd[tv_key].shape
        if tensor.shape == want:
            adapted[tv_key] = tensor
        elif (tensor.ndim == 4 and tensor.shape[2:] == (1, 1)
              and tensor.shape[:2] == tuple(want)):
            # 1x1 conv (timm conv_head) → linear (torchvision classifier.0).
            adapted[tv_key] = tensor.reshape(want)
        else:
            raise SystemExit(
                f"[probe] shape mismatch at position of {tv_key!r}: timm "
                f"{timm_key!r} has {tuple(tensor.shape)}, torchvision expects "
                f"{tuple(want)} — graphs differ, adapter infeasible"
            )
    return adapted


def probe_input(image_path: Optional[str]):
    """Deterministic probe tensor [1, 3, 224, 224]. The SAME tensor feeds both
    models — the probe compares graph+weights equivalence, so preprocessing
    parity is irrelevant as long as the input is identical and image-like."""
    import numpy as np

    torch, _, _ = _import_heavy()
    if image_path and Path(image_path).is_file():
        from PIL import Image

        img = Image.open(image_path).convert("RGB").resize((PROBE_SIZE, PROBE_SIZE))
        arr = np.asarray(img, dtype=np.float32) / 255.0
        # ImageNet normalisation (both models are ImageNet classifiers).
        arr = (arr - np.array([0.485, 0.456, 0.406], dtype=np.float32)) \
            / np.array([0.229, 0.224, 0.225], dtype=np.float32)
        arr = arr.transpose(2, 0, 1)[None, ...]
    else:
        rng = np.random.default_rng(seed=0)
        arr = rng.standard_normal((1, 3, PROBE_SIZE, PROBE_SIZE)).astype(np.float32)
    return torch.from_numpy(np.ascontiguousarray(arr))


def main(argv: Optional[list] = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--image", default=None,
                        help="Optional probe image; otherwise a deterministic "
                             "synthetic input is used.")
    parser.add_argument("--tolerance", type=float, default=DEFAULT_TOLERANCE,
                        help="Max abs logit difference counted as identical.")
    parser.add_argument("--save-adapted", default=None, metavar="PATH",
                        help="On a PASS, save the adapted torchvision-keyed "
                             "state dict here for train.py to consume.")
    args = parser.parse_args(argv)

    torch, torchvision, timm = _import_heavy()

    print(f"[probe] loading timm {TIMM_MODEL} (downloads ~22 MiB on first run)")
    timm_model = timm.create_model(TIMM_MODEL, pretrained=True).eval()

    from torchvision.models import mobilenet_v3_large

    tv_model = mobilenet_v3_large(weights=None).eval()

    adapted = adapt_state_dict(timm_model.state_dict(), tv_model.state_dict())
    tv_model.load_state_dict(adapted, strict=True)

    x = probe_input(args.image)
    with torch.no_grad():
        timm_logits = timm_model(x)
        tv_logits = tv_model(x)
    err = float((timm_logits - tv_logits).abs().max())
    agree = bool(timm_logits.argmax(1).item() == tv_logits.argmax(1).item())
    ok = err < args.tolerance and agree

    print(json.dumps({
        "timm_model": TIMM_MODEL,
        "max_abs_logit_err": err,
        "tolerance": args.tolerance,
        "argmax_agrees": agree,
        "round_trip_ok": ok,
    }, indent=2))

    if ok and args.save_adapted:
        out = Path(args.save_adapted)
        out.parent.mkdir(parents=True, exist_ok=True)
        torch.save({"model": adapted, "source": TIMM_MODEL}, str(out))
        print(f"[probe] adapted state dict -> {out}")

    print(f"[probe] round-trip {'PASSED' if ok else 'FAILED'} "
          "(record the outcome against Decision 19)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

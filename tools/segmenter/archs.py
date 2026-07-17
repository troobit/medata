#!/usr/bin/env python3
"""Architecture registry for the segmenter chain (snaq-parity design lane C).

The pipeline was DeepLab-hard-wired in more places than ``train.py``:
``export.load_checkpoint`` rebuilt ``deeplabv3_mobilenet_v3_large`` directly,
and both ``run_validation.py`` and the training loop assumed the torchvision
``model(images)["out"]`` dict output. A bake-off winner (snaq-parity Req 5.4)
must be trainable, judgeable, AND exportable, so the registry is the single
shared seam all three consumers build models through (Decisions 12 and 14).

Contract per architecture (``ArchSpec``):

  - ``build(num_classes, pretrained)``      — model constructor. ``pretrained``
    True uses the architecture's published initialisation (may download);
    False builds weights-free for smoke runs.
  - ``load_checkpoint(num_classes, path)``  — build + load a trained state dict
    (accepts the ``{"model": ...}`` checkpoint wrapper), returned in eval mode.
  - ``forward_logits(model, images)``       — normalise the forward output to
    the ``["out"]``-at-input-resolution convention: a ``[B, C, H, W]`` logits
    tensor at the INPUT spatial resolution. torchvision dict-output models
    index ``"out"``; plain-tensor architectures (SegFormer-class, which emit
    stride-4 logits) are bilinearly upsampled via ``plain_tensor_logits``.

Only ``deeplab_mnv3`` is registered; the bake-off winner is added when its
spike passes (spike_convert.py measures candidates — it does not train them).
The ``arch`` recorded in checkpoint/lineage ``train_config`` resolves back
through ``arch_from_lineage`` / ``arch_from_checkpoint``; absence means the
historical ``deeplab_mnv3``, so pre-registry artefacts stay resolvable.

Torch-free at import (the loss_config / lineage pattern): heavy imports live
inside the callables, so ``--help`` and the registry-fixture tests run without
the training venv.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

DEFAULT_ARCH = "deeplab_mnv3"


@dataclass(frozen=True)
class ArchSpec:
    """The per-architecture contract every consumer dispatches through."""

    name: str
    output: str  # "dict_out" (torchvision {"out": ...}) | "plain_tensor"
    build: Callable[[int, bool], Any]            # (num_classes, pretrained)
    load_checkpoint: Callable[[int, Any], Any]   # (num_classes, path | None)
    forward_logits: Callable[[Any, Any], Any]    # (model, images) -> [B,C,H,W]


_REGISTRY: dict[str, ArchSpec] = {}

# Tuple mirror of the registry keys for argparse ``choices``; rebuilt on
# (un)register so a fixture/candidate arch is immediately selectable.
ARCH_CHOICES: tuple[str, ...] = ()


def _rebuild_choices() -> None:
    global ARCH_CHOICES
    ARCH_CHOICES = tuple(_REGISTRY)


def register(spec: ArchSpec) -> ArchSpec:
    """Add an architecture to the registry (the seam the bake-off winner — and
    the test fixtures — land through). Duplicate names are rejected so an arch
    can never be silently redefined out from under recorded lineage."""
    if spec.name in _REGISTRY:
        raise ValueError(f"architecture {spec.name!r} is already registered")
    _REGISTRY[spec.name] = spec
    _rebuild_choices()
    return spec


def unregister(name: str) -> None:
    """Remove a registered architecture (test fixtures only — the committed
    entries stay for the life of the process)."""
    _REGISTRY.pop(name, None)
    _rebuild_choices()


def get(name: str) -> ArchSpec:
    """Look up an architecture; unknown names raise with the choices listed."""
    if name not in _REGISTRY:
        raise ValueError(
            f"unknown architecture {name!r}; choose one of {', '.join(_REGISTRY)}"
        )
    return _REGISTRY[name]


def normalise_arch_name(name: str | None) -> str:
    """Default ``None`` to ``DEFAULT_ARCH`` and validate the result."""
    resolved = DEFAULT_ARCH if name is None else name
    get(resolved)  # raises on unknown
    return resolved


def arch_from_lineage(manifest: dict[str, Any]) -> str:
    """The architecture a lineage manifest's run used. Absence of the
    ``train_config.arch`` key means the historical default — every
    pre-registry lineage was a deeplab_mnv3 run."""
    return manifest.get("train_config", {}).get("arch", DEFAULT_ARCH)


def arch_from_checkpoint(checkpoint_path: str | Path | None) -> str:
    """The architecture recorded inside a checkpoint file's provenance keys
    (``train.py`` stamps ``arch`` only for non-default runs; absence — or no
    checkpoint at all — means deeplab_mnv3). Torch-gated: peeks the dict."""
    if checkpoint_path is None or not Path(checkpoint_path).is_file():
        return DEFAULT_ARCH
    import torch

    raw = torch.load(str(checkpoint_path), map_location="cpu")
    if isinstance(raw, dict):
        return str(raw.get("arch", DEFAULT_ARCH))
    return DEFAULT_ARCH


# ── Forward-output normalisers ──────────────────────────────────────────────────

def dict_out_logits(model, images):
    """torchvision segmentation convention: ``model(x)["out"]`` is already a
    logits tensor at the input resolution."""
    return model(images)["out"]


def plain_tensor_logits(model, images):
    """SegFormer-class convention: the model emits a plain logits tensor at a
    reduced spatial stride (SegFormer's native output is input/4); upsample
    bilinearly to the input resolution so every consumer sees the same
    ``["out"]``-at-input-resolution shape. Traceable (torch.jit / coremltools):
    only tensor ops and ``F.interpolate``."""
    import torch.nn.functional as F

    out = model(images)
    if isinstance(out, dict):
        out = out["out"]
    if out.shape[-2:] != images.shape[-2:]:
        out = F.interpolate(out, size=images.shape[-2:], mode="bilinear",
                            align_corners=False)
    return out


# ── deeplab_mnv3 (the shipping architecture — pipeline Decision 25) ─────────────

def _deeplab_build(num_classes: int, pretrained: bool):
    """DeepLabV3 + MobileNetV3-Large with the head replaced for ``num_classes``.

    ``pretrained`` True keeps the historical export.load_checkpoint
    construction: torchvision DEFAULT (COCO-seg) weights, built with the aux
    head (torchvision >= 0.13 refuses aux_loss=False alongside these weights)
    and the aux head dropped — the resulting state_dict key set is identical
    to an aux_loss=False construction, which is what the weights-free path
    builds (no network download; smoke runs and resume rebuilds).
    """
    from torchvision.models.segmentation import (
        deeplabv3_mobilenet_v3_large, DeepLabV3_MobileNet_V3_Large_Weights,
    )
    from torchvision.models.segmentation.deeplabv3 import DeepLabHead

    if pretrained:
        weights = DeepLabV3_MobileNet_V3_Large_Weights.DEFAULT
        model = deeplabv3_mobilenet_v3_large(weights=weights, aux_loss=True)
        model.aux_classifier = None
    else:
        model = deeplabv3_mobilenet_v3_large(weights=None, aux_loss=False)
    in_ch = model.classifier[0].convs[0][0].in_channels
    model.classifier = DeepLabHead(in_ch, num_classes)
    return model


def _deeplab_load_checkpoint(num_classes: int, checkpoint_path):
    """The historical ``export.load_checkpoint`` semantics: pretrained build,
    then load the trained state dict (``{"model": ...}`` wrapper accepted)
    when a file exists; eval mode either way."""
    import torch

    model = _deeplab_build(num_classes, pretrained=True)
    if checkpoint_path is not None and Path(checkpoint_path).is_file():
        state = torch.load(str(checkpoint_path), map_location="cpu")
        if isinstance(state, dict) and "model" in state:
            state = state["model"]
        model.load_state_dict(state, strict=False)
    model.eval()
    return model


register(ArchSpec(
    name="deeplab_mnv3",
    output="dict_out",
    build=_deeplab_build,
    load_checkpoint=_deeplab_load_checkpoint,
    forward_logits=dict_out_logits,
))

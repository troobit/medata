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

Registered: ``deeplab_mnv3`` (shipping), ``segformer_b0`` (backbone-swap
candidate — its conversion spike passed in full, segmenter-foundation
Decision 28, so the task-22 comparison retrain can select it via ``--arch``)
and ``deeplabv3plus_mnv3`` (the shipping backbone and ASPP plus a
DeepLabV3+-style low-level skip decoder — research note 4.6, queued as R19).
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
    ``train_config.arch`` key means the historical deeplab_mnv3 — the literal,
    not ``DEFAULT_ARCH``: every pre-registry lineage was a deeplab_mnv3 run,
    regardless of what the default becomes later."""
    return manifest.get("train_config", {}).get("arch", "deeplab_mnv3")


def checkpoint_arch_stamp(checkpoint_path: str | Path | None) -> str | None:
    """The ``arch`` value a checkpoint file itself stamps, or ``None`` when
    the file (or the key) is absent. Torch-gated: peeks the dict."""
    if checkpoint_path is None or not Path(checkpoint_path).is_file():
        return None
    import torch

    raw = torch.load(str(checkpoint_path), map_location="cpu")
    if isinstance(raw, dict) and "arch" in raw:
        return str(raw["arch"])
    return None


def arch_from_checkpoint(checkpoint_path: str | Path | None) -> str:
    """The architecture recorded inside a checkpoint file's provenance keys
    (``train.py`` stamps ``arch`` only for non-default runs; absence — or no
    checkpoint at all — means the historical deeplab_mnv3, the literal rather
    than ``DEFAULT_ARCH``, regardless of what the default becomes later)."""
    stamped = checkpoint_arch_stamp(checkpoint_path)
    return "deeplab_mnv3" if stamped is None else stamped


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


# ── segformer_b0 (backbone-swap candidate — segmenter-foundation Decision 28) ───

# Published initialisation for segformer_b0 ``pretrained`` builds: the same
# public checkpoint the conversion spike measured (spike_segformer.py). Like
# deeplab_mnv3's COCO-seg DEFAULT weights, it embodies dense-prediction
# transfer rather than a classification-only init (design §4.2's stated
# preference).
SEGFORMER_B0_CHECKPOINT = "nvidia/segformer-b0-finetuned-ade-512-512"


def segformer_b0_grafted(num_classes: int, checkpoint: str | None):
    """SegFormer-B0 (HF ``transformers`` — spike-only dependency until an
    adoption decision) with the classifier grafted to ``num_classes`` and
    wrapped to emit the raw logits tensor at SegFormer's native H/4 output
    stride. Shared with spike_segformer.py so the graph the spike converted is
    the graph this registration trains and exports.

    ``checkpoint`` is an HF id or local path; ``None`` builds weights-free
    from the default ``SegformerConfig`` (the published B0 variant — no
    download; smoke runs and checkpoint rebuilds). Both paths produce the same
    state-dict key set."""
    import torch
    from transformers import SegformerConfig, SegformerForSemanticSegmentation

    if checkpoint is None:
        model = SegformerForSemanticSegmentation(
            SegformerConfig(num_labels=num_classes))
    else:
        model = SegformerForSemanticSegmentation.from_pretrained(checkpoint)
        head = model.decode_head.classifier
        model.decode_head.classifier = torch.nn.Conv2d(
            head.in_channels, num_classes, kernel_size=1)

    # MPS workaround: the decode head's BatchNorm2d saves its (non-contiguous,
    # via the fuse-conv over concatenated reshaped stages) input for backward,
    # and the MPS batch-norm backward kernel rejects it ("view size is not
    # compatible..."). Making the input contiguous fixes backward; on CPU and
    # in the export trace it is a no-op (contiguous() returns the tensor
    # unchanged when the layout is already dense).
    model.decode_head.batch_norm.register_forward_pre_hook(
        lambda module, args: (args[0].contiguous(),))

    class PlainLogits(torch.nn.Module):
        """Adapter to the plain-tensor convention: forward(x) -> [B, C, H/4,
        W/4] logits; ``plain_tensor_logits`` upsamples to input resolution."""

        def __init__(self, m):
            super().__init__()
            self.m = m

        def forward(self, x):
            return self.m(pixel_values=x).logits

    return PlainLogits(model).eval()


def _segformer_build(num_classes: int, pretrained: bool):
    checkpoint = SEGFORMER_B0_CHECKPOINT if pretrained else None
    return segformer_b0_grafted(num_classes, checkpoint)


def _segformer_load_checkpoint(num_classes: int, checkpoint_path):
    """Weights-free build + trained state dict (``{"model": ...}`` wrapper
    accepted), eval mode. Unlike deeplab_mnv3's loader — whose pretrained
    build is preserved historical behaviour — this never downloads: a trained
    segformer_b0 checkpoint covers every parameter."""
    import torch

    model = segformer_b0_grafted(num_classes, checkpoint=None)
    if checkpoint_path is not None and Path(checkpoint_path).is_file():
        state = torch.load(str(checkpoint_path), map_location="cpu")
        if isinstance(state, dict) and "model" in state:
            state = state["model"]
        model.load_state_dict(state, strict=False)
    model.eval()
    return model


register(ArchSpec(
    name="segformer_b0",
    output="plain_tensor",
    build=_segformer_build,
    load_checkpoint=_segformer_load_checkpoint,
    forward_logits=plain_tensor_logits,
))


# ── deeplabv3plus_mnv3 (decoder candidate — research note 4.6, R19) ─────────────

# The backbone stage the skip is taken from: the output of features[3], the
# last block at stride 4 (24 channels; 161x161 at a 641 input). features[16]
# (960 channels, stride 16 — the dilated tail keeps it there) feeds the ASPP
# exactly as in deeplab_mnv3.
DLV3PLUS_LOW_LEVEL_LAYER = "3"
DLV3PLUS_LOW_LEVEL_IN = 24
# Skip projection width and decoder width: the DeepLabV3+ paper's choices
# (48 low-level channels; two 3x3 convs with 256 filters). The ASPP emits 256.
DLV3PLUS_LOW_LEVEL_OUT = 48
DLV3PLUS_DECODER_CHANNELS = 256
DLV3PLUS_ASPP_CHANNELS = 256


def _conv_bn_relu(nn, in_ch: int, out_ch: int, kernel: int) -> list:
    return [
        nn.Conv2d(in_ch, out_ch, kernel, padding=kernel // 2, bias=False),
        nn.BatchNorm2d(out_ch),
        nn.ReLU(),
    ]


def _dlv3plus_build(num_classes: int, pretrained: bool):
    """DeepLabV3+ on MobileNetV3-Large: deeplab_mnv3's backbone and a fresh
    ASPP, then a decoder that upsamples the stride-16 ASPP output to stride 4,
    concatenates a 48-channel projection of the stride-4 backbone features,
    runs two 3x3 conv/BN/ReLU blocks and a 1x1 classifier, and upsamples the
    logits bilinearly to the input size.

    The backbone comes from ``_deeplab_build`` so its initialisation is the
    shipping arch's exactly (``pretrained`` True: the torchvision COCO-seg
    DEFAULT weights, which is what every R-series run started from; False:
    weights-free). The ASPP and decoder start fresh, as deeplab_mnv3's head
    does, so the only difference from deeplab_mnv3 is the decoder.

    Forward returns ``{"out": logits}`` at the input resolution — the
    torchvision dict convention, so ``dict_out_logits`` is its normaliser and
    the export, oracle and validation paths see the same [B, C, H, W] contract.
    Only conv / BN / ReLU / concat / bilinear resize, all of which Core ML
    converts and the ANE runs.
    """
    import torch
    import torch.nn.functional as F
    from torch import nn
    from torchvision.models._utils import IntermediateLayerGetter
    from torchvision.models.segmentation.deeplabv3 import ASPP

    base = _deeplab_build(num_classes, pretrained=pretrained)
    # Re-wrap the same feature modules with a second return point; the
    # state-dict keys under ``backbone.`` are identical to deeplab_mnv3's.
    backbone = IntermediateLayerGetter(
        base.backbone, return_layers={DLV3PLUS_LOW_LEVEL_LAYER: "low", "16": "out"})
    in_ch = base.classifier[0].convs[0][0].in_channels

    class DeepLabV3PlusMNV3(nn.Module):
        def __init__(self):
            super().__init__()
            self.backbone = backbone
            self.aspp = ASPP(in_ch, [12, 24, 36], out_channels=DLV3PLUS_ASPP_CHANNELS)
            self.low_proj = nn.Sequential(*_conv_bn_relu(
                nn, DLV3PLUS_LOW_LEVEL_IN, DLV3PLUS_LOW_LEVEL_OUT, 1))
            self.decoder = nn.Sequential(
                *_conv_bn_relu(nn, DLV3PLUS_ASPP_CHANNELS + DLV3PLUS_LOW_LEVEL_OUT,
                               DLV3PLUS_DECODER_CHANNELS, 3),
                *_conv_bn_relu(nn, DLV3PLUS_DECODER_CHANNELS,
                               DLV3PLUS_DECODER_CHANNELS, 3),
                nn.Conv2d(DLV3PLUS_DECODER_CHANNELS, num_classes, 1),
            )

        def forward(self, x):
            feats = self.backbone(x)
            low = self.low_proj(feats["low"])
            high = F.interpolate(self.aspp(feats["out"]), size=low.shape[-2:],
                                 mode="bilinear", align_corners=False)
            logits = self.decoder(torch.cat([high, low], dim=1))
            logits = F.interpolate(logits, size=x.shape[-2:], mode="bilinear",
                                   align_corners=False)
            return {"out": logits}

    return DeepLabV3PlusMNV3()


def _dlv3plus_load_checkpoint(num_classes: int, checkpoint_path):
    """Weights-free build + trained state dict (``{"model": ...}`` wrapper
    accepted), eval mode. Never downloads: a trained checkpoint covers every
    parameter. Strict, unlike the older loaders: this arch has no legacy
    checkpoints, so a key mismatch is a wrong file and must fail loudly
    rather than export a half-random decoder."""
    import torch

    model = _dlv3plus_build(num_classes, pretrained=False)
    if checkpoint_path is not None and Path(checkpoint_path).is_file():
        state = torch.load(str(checkpoint_path), map_location="cpu")
        if isinstance(state, dict) and "model" in state:
            state = state["model"]
        model.load_state_dict(state)
    model.eval()
    return model


register(ArchSpec(
    name="deeplabv3plus_mnv3",
    output="dict_out",
    build=_dlv3plus_build,
    load_checkpoint=_dlv3plus_load_checkpoint,
    forward_logits=dict_out_logits,
))

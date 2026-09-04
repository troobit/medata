#!/usr/bin/env python3
"""Segmenter training pipeline (step 4 of docs/ml-training.md §4, decisions 25/28).

Transfer-learns DeepLabV3 + MobileNetV3-Large (torchvision) at 513x513 for the
36-class palette (25 solid + 8 coarse liquid + background + unknown_food +
unsupported_liquid — the palette of Decisions 23/24 plus the
cereal solid at index 24, myfoodrepo-bridge PRD),
starting from the torchvision pretrained backbone, fine-tuning head + backbone on
the remapped train split, and saving a single PyTorch checkpoint.

That ``.pt`` is the single source of truth (Decision 28): ``export.py`` and
``make_fixtures.py`` both consume it directly. The architecture here is NOT
redefined locally -- it is built via the shared registry (``archs.py``,
``--arch``, default ``deeplab_mnv3``; snaq-parity Decision 14) so the saved
``state_dict`` is byte-compatible with what the exporter loads back.

Long local runs (e.g. Apple-silicon MPS) are interruptible: a resume sidecar
(``<--out>.resume.pt``) is written atomically after every completed epoch and
``--resume`` continues the epoch sequence with identical hyperparameters
(docs/ml-training.md §4; specs/estimation/resumable-segmenter-training/).

Usage (docs/ml-training.md §4)::

    python tools/segmenter/train.py \\
        --data data/foodseg103_remapped_v2 \\
        --num-classes 36 --target-size 513 \\
        --epochs 60 --batch-size 16 --lr 1e-3 \\
        --out tools/segmenter/build/checkpoint.pt

Watch FOOD-class mIoU on val (not overall accuracy). Background dominates pixel
counts and inflates the naive number while thin food classes quietly fail the §5
bar of mean food-class mIoU >= 0.48 (Req 8.9 as amended by segmenter-foundation
Decision 5; was 0.60).

RECIPE: the train split gets geometric augmentation (horizontal flip + random
scale-up crop, ``--no-augment`` to disable) and the learning rate follows a
per-epoch poly-0.9 decay from ``--lr`` (LR_SCHEDULE). The first fixed-lr,
no-augmentation baseline overfit — train loss kept falling while val food-class
mIoU plateaued around 0.34 by epoch 22 of 60. OPT-IN extensions (both default
to the historical recipe when omitted): ``--loss`` selects a class-imbalance-
aware loss (see ``loss_config``) and ``--photometric-augment`` adds train-only
colour/brightness/contrast jitter to the IMAGE (never the mask).

NEVER edit this file while a run is live: DataLoader workers are respawned each
epoch and re-import the script from disk, so they execute NEW code against the
OLD pickled dataset object and crash the run mid-training.

COLOUR SPACE (docs/ml-training.md §5, §11): training runs on RGB to match
``export.reference_input`` (ImageNet mean/std, CHW). The on-device capture path
emits BGRA8 (``PixelBufferAdapter``); the training transform MUST stay matched to
``SegmenterPreProcessor`` or the §5 bench stays green while real-device inference
degrades (train/serve skew is invisible to mIoU). Do not change the normalization
here without changing it in lockstep with both ``export.reference_input`` and the
device pre-processor.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import sys
from pathlib import Path

# Pure, torch-free loss selection + class-weight derivation. Safe to import at
# module top: loss_config touches no heavy deps (same family as lineage.py), so
# `--help` and the torch-free test suite still import train.py without torch.
# Imported via sys.path (the run_validation._load_sibling pattern), NOT
# spec_from_file_location, so spawn DataLoader workers can re-import it by name.
_TOOLS_DIR = str(Path(__file__).resolve().parent)
if _TOOLS_DIR not in sys.path:
    sys.path.insert(0, _TOOLS_DIR)
import archs  # noqa: E402  (torch-free at import, same family as loss_config)
import loss_config  # noqa: E402
import validation  # noqa: E402  (pure stdlib — label-space guard only)

# ImageNet normalization -- MUST match export.reference_input (train/serve match).
IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)

# Palette background channel (ClassPalette standard palette / prepare_dataset.py:
# 25 solid incl. cereal at 24 + 8 liquid at 25–32, then background at 33 —
# design §3.3). Letterbox padding is labelled background so the model learns
# padded regions are not food.
PALETTE_BACKGROUND = 33

# Special (non-food) channels excluded from food-class mIoU. These mirror
# class_mapping_foodseg103.json:special_channels and §11 channel ordering.
BACKGROUND_CLASS = 33
UNKNOWN_FOOD_CLASS = 34
UNSUPPORTED_LIQUID_CLASS = 35
NON_FOOD_CLASSES = (BACKGROUND_CLASS, UNKNOWN_FOOD_CLASS, UNSUPPORTED_LIQUID_CLASS)

PALETTE_VERSION = "v0"

# Per-epoch poly learning-rate decay (standard DeepLab recipe); recorded in
# checkpoint/lineage provenance. lr_e = base_lr * (1 - (e-1)/epochs) ** 0.9.
LR_SCHEDULE = "poly-0.9-per-epoch"

# Mask file extensions tried for each image stem, in order.
_MASK_EXTS = (".png", ".PNG")
_IMAGE_EXTS = (".png", ".jpg", ".jpeg", ".PNG", ".JPG", ".JPEG")

# Opt-in photometric jitter range (--photometric-augment): each of brightness /
# contrast / colour saturation gets an independent uniform factor from this
# range per sample. Mild by design — the goal is robustness to kitchen
# lighting, not a new colour distribution.
PHOTOMETRIC_JITTER_RANGE = (0.8, 1.2)


def _photometric_jitter(img):
    """Brightness/contrast/colour jitter on a PIL RGB image (train split only).

    Applied BEFORE the letterbox so the padding stays exact black, and NEVER to
    the mask — photometric changes do not move class boundaries.
    """
    import random

    from PIL import ImageEnhance

    lo, hi = PHOTOMETRIC_JITTER_RANGE
    for enhancer in (ImageEnhance.Brightness, ImageEnhance.Contrast, ImageEnhance.Color):
        img = enhancer(img).enhance(random.uniform(lo, hi))
    return img


def _import_torch():
    try:
        import torch
        import torchvision  # noqa: F401  (imported for the side of being available)
        return torch
    except ImportError as exc:
        raise SystemExit(
            "PyTorch + torchvision are required. Install with:\n"
            "  pip install torch torchvision"
        ) from exc


def _import_pillow():
    try:
        from PIL import Image
        return Image
    except ImportError as exc:
        raise SystemExit(
            "Pillow is required for image/mask loading. Install with:\n"
            "  pip install pillow"
        ) from exc


def _load_lineage_module():
    """Import the sibling lineage.py by path (pure stdlib; no torch needed)."""
    lineage_path = Path(__file__).resolve().with_name("lineage.py")
    spec = importlib.util.spec_from_file_location("segmenter_lineage", lineage_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Could not load sibling lineage module at {lineage_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_model(num_classes: int, pretrained: bool,
                init_checkpoint: str | None = None,
                arch: str = archs.DEFAULT_ARCH):
    """Build the training model via the architecture registry (archs.py).

    The registry is the single source of architecture truth shared with
    ``export.load_checkpoint`` and ``run_validation.py`` (Decision 28 as
    extended by snaq-parity Decision 14), so the saved ``state_dict`` stays
    byte-compatible with what the exporter loads back. ``pretrained`` False
    builds weights-free so a smoke run needs no network download.

    ``init_checkpoint`` (segmenter-foundation Req 2.2 / Decisions 17 and 19)
    names a LOCAL MobileNetV3-Large classifier state dict — the
    ``adapter_probe.py --save-adapted`` output or a downloaded torchvision
    ``IMAGENET1K_V2`` file — whose ``features.*`` tensors initialise the
    backbone instead of the COCO-seg ``DEFAULT`` weights; the DeepLab head
    starts fresh. It is deeplab_mnv3-specific (the backbone-key surgery below)
    and rejected for any other architecture.
    """
    _import_torch()
    spec = archs.get(arch)

    if init_checkpoint is not None:
        if arch != archs.DEFAULT_ARCH:
            raise SystemExit(
                f"[train] --init-checkpoint is {archs.DEFAULT_ARCH}-specific "
                f"(MobileNetV3 backbone surgery) and cannot initialise {arch!r}"
            )
        model = spec.build(num_classes, pretrained=False)
        _load_backbone_init(model, Path(init_checkpoint))
    else:
        model = spec.build(num_classes, pretrained=pretrained)

    model.train()
    return model


def _load_backbone_init(model, path: Path) -> None:
    """Initialise ``model.backbone`` from a MobileNetV3-Large CLASSIFIER state
    dict (the ``--init-checkpoint`` wiring).

    The DeepLabV3 backbone is the classifier's ``features`` module behind
    torchvision's IntermediateLayerGetter, so the ``features.``-prefixed
    tensors map key-for-key once the prefix is stripped; classifier-head
    tensors are discarded (the DeepLab head stays fresh). Accepts either a
    plain torchvision state dict or the ``{"model": ...}`` wrapper that
    ``adapter_probe.py --save-adapted`` writes. Loads strict so a partial or
    misshapen init fails loudly instead of silently training from a
    half-random backbone.
    """
    torch = _import_torch()
    if not path.is_file():
        raise SystemExit(f"[train] --init-checkpoint not found: {path}")
    state = torch.load(str(path), map_location="cpu")
    if isinstance(state, dict) and isinstance(state.get("model"), dict):
        state = state["model"]  # adapter_probe.py --save-adapted wrapper
    prefix = "features."
    backbone_state = {
        key[len(prefix):]: tensor
        for key, tensor in state.items()
        if key.startswith(prefix)
    }
    if not backbone_state:
        raise SystemExit(
            f"[train] {path} contains no 'features.*' tensors — expected a "
            "MobileNetV3-Large classifier state dict (adapter_probe.py "
            "--save-adapted output or a torchvision IMAGENET1K_V2 download)"
        )
    try:
        model.backbone.load_state_dict(backbone_state)
    except RuntimeError as exc:
        raise SystemExit(
            f"[train] --init-checkpoint {path} does not match the "
            f"MobileNetV3-Large backbone: {exc}"
        ) from exc
    print(f"[train] backbone initialised from {path}")


class FoodSegDataset:
    """image+mask pairs from a remapped split dir (prepare_dataset.py output).

    Expected layout (docs/ml-training.md §3; prepare_dataset.py, written in
    parallel)::

        <split>/images/<stem>.{png,jpg,...}
        <split>/masks/<stem>.png        # single-channel uint8, values in [0, num_classes)

    Image -> RGB -> ImageNet-normalized target_size float CHW (matches
    export.reference_input). Mask -> nearest-resized long tensor [H, W] of class
    ids. This is a torch.utils.data.Dataset; constructed lazily so the module
    imports without torch (CLI --help must work torch-free).

    ``augment=True`` (train split only) applies joint GEOMETRIC augmentation —
    horizontal flip + random scale-up crop — before normalisation.

    ``photometric=True`` (train split only, opt-in via ``--photometric-augment``)
    additionally jitters brightness/contrast/colour on the IMAGE ONLY — the mask
    is never touched, and the jitter lands BEFORE the letterbox so the padding
    stays exact black (normalised zero). This is augmentation, not a
    preprocessing change: the val path and the serve-side normalisation
    (``SegmenterPreProcessor`` — module docstring) are untouched, so train/serve
    colour handling stays matched. Do NOT change the normalisation itself
    without a lockstep serve-side decision.
    """

    def __init__(self, split_dir: Path, target_size: int, limit: int | None = None,
                 augment: bool = False, photometric: bool = False):
        # Availability check only — do NOT store the modules on the instance.
        # macOS DataLoader workers start via spawn, which pickles the dataset,
        # and module objects are unpicklable.
        _import_torch()
        _import_pillow()
        self.target_size = target_size
        self.augment = augment
        self.photometric = photometric

        images_dir = split_dir / "images"
        masks_dir = split_dir / "masks"
        if not images_dir.is_dir() or not masks_dir.is_dir():
            raise SystemExit(
                f"Expected {images_dir} and {masks_dir} (prepare_dataset.py output). "
                "Run step 3 (prepare_dataset.py) first."
            )

        pairs: list[tuple[Path, Path]] = []
        for img_path in sorted(images_dir.iterdir()):
            if img_path.suffix not in _IMAGE_EXTS:
                continue
            mask_path = self._find_mask(masks_dir, img_path.stem)
            if mask_path is not None:
                pairs.append((img_path, mask_path))
        if not pairs:
            raise SystemExit(f"No image/mask pairs found under {split_dir}")
        if limit is not None:
            pairs = pairs[:limit]
        self.pairs = pairs

    @staticmethod
    def _find_mask(masks_dir: Path, stem: str) -> Path | None:
        for ext in _MASK_EXTS:
            candidate = masks_dir / f"{stem}{ext}"
            if candidate.is_file():
                return candidate
        return None

    def __len__(self) -> int:
        return len(self.pairs)

    def __getitem__(self, idx: int):
        import numpy as np

        torch = _import_torch()
        Image = _import_pillow()
        img_path, mask_path = self.pairs[idx]

        # --- image: RGB, ImageNet-normalized CHW (match export.reference_input) ---
        # exif_transpose first: a handful of FoodSeg103 JPEGs carry an EXIF
        # orientation tag and their masks match the *rotated* pixels.
        from PIL import ImageOps

        img = ImageOps.exif_transpose(Image.open(img_path)).convert("RGB")
        if self.photometric:
            img = _photometric_jitter(img)
        mask_img = Image.open(mask_path)
        img, mask_img = self._letterbox_pair(img, mask_img, Image, augment=self.augment)

        arr = np.asarray(img, dtype=np.float32) / 255.0
        mean = np.array(IMAGENET_MEAN, dtype=np.float32)
        std = np.array(IMAGENET_STD, dtype=np.float32)
        arr = (arr - mean) / std
        arr = arr.transpose(2, 0, 1)  # HWC -> CHW
        image = torch.from_numpy(np.ascontiguousarray(arr))

        # --- mask: NEAREST resize, long [H, W] of class ids ---
        mask_arr = np.asarray(mask_img, dtype=np.int64)
        if mask_arr.ndim == 3:  # defensive: collapse an accidental RGB mask
            mask_arr = mask_arr[..., 0]
        mask = torch.from_numpy(np.ascontiguousarray(mask_arr))

        return image, mask

    def _letterbox_pair(self, img, mask_img, Image, augment: bool):
        """Aspect-preserving letterbox into a target×target canvas, matching the
        on-device ``SegmenterPreProcessor`` EXACTLY on the val path:
        ``scale = target / max(w, h)``, bilinear image / nearest mask, content
        blitted TOP-LEFT, image padded black (which is the normalised-zero pad
        value ``(0 - mean)/std`` after ImageNet normalisation), mask padded with
        the background label. The previous recipe resized to a SQUARE (stretched
        aspect); the device letterboxes, so a stretch-trained model saw
        off-distribution input on device — the train/serve geometry skew that is
        invisible to mIoU (docs/ml-training.md §11).

        ``augment=True`` (train split) adds INDEPENDENT horizontal and vertical
        flips (each p=0.5 → all four orientations, since the phone can be held at
        any rotation over a top-down plate), a mild scale-down jitter, and random
        placement of the content within the canvas — geometric augmentation that
        STAYS aspect-preserving (no stretch), so it remains matched to the serve
        path. The vertical flip is train-only; the val/test path stays
        device-faithful (no flip) so mIoU measures real device parity.
        DataLoader workers re-seed ``random`` per epoch.
        """
        import random

        target = self.target_size
        w, h = img.size

        if augment and random.random() < 0.5:
            img = img.transpose(Image.FLIP_LEFT_RIGHT)
            mask_img = mask_img.transpose(Image.FLIP_LEFT_RIGHT)
        if augment and random.random() < 0.5:
            img = img.transpose(Image.FLIP_TOP_BOTTOM)
            mask_img = mask_img.transpose(Image.FLIP_TOP_BOTTOM)

        base = target / max(w, h)
        scale = base * random.uniform(0.75, 1.0) if augment else base
        sw = max(1, min(target, round(w * scale)))
        sh = max(1, min(target, round(h * scale)))
        img_r = img.resize((sw, sh), Image.BILINEAR)
        mask_r = mask_img.resize((sw, sh), Image.NEAREST)

        if augment:
            ox = random.randint(0, target - sw)
            oy = random.randint(0, target - sh)
        else:
            ox = oy = 0  # top-left, exact device parity

        canvas = Image.new("RGB", (target, target), (0, 0, 0))
        canvas.paste(img_r, (ox, oy))
        mask_canvas = Image.new("L", (target, target), PALETTE_BACKGROUND)
        mask_canvas.paste(mask_r, (ox, oy))
        return canvas, mask_canvas


def _make_loader(dataset, batch_size: int, shuffle: bool, num_workers: int,
                 drop_last: bool = False):
    _import_torch()  # ensure torch is present before importing its DataLoader
    from torch.utils.data import DataLoader

    return DataLoader(
        dataset,
        batch_size=batch_size,
        shuffle=shuffle,
        num_workers=num_workers,
        drop_last=drop_last,
    )


def _resolve_device(device_arg: str):
    torch = _import_torch()
    if device_arg != "auto":
        return torch.device(device_arg)
    if torch.cuda.is_available():
        return torch.device("cuda")
    if getattr(torch.backends, "mps", None) is not None and torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


def _train_pixel_counts(dataset: FoodSegDataset, num_classes: int) -> list[int]:
    """Per-class pixel counts over the train split's ORIGINAL mask files.

    One pass with PIL + numpy (no torch, no letterbox): letterbox padding is
    always background, so counting the raw masks slightly under-counts
    background relative to what the model sees — irrelevant for a frequency-
    based weighting of the (rare) food classes. Values >= num_classes would be
    a prepare_dataset.py bug and abort loudly.
    """
    import numpy as np

    Image = _import_pillow()
    total = np.zeros(num_classes, dtype=np.int64)
    for _, mask_path in dataset.pairs:
        arr = np.asarray(Image.open(mask_path), dtype=np.int64)
        if arr.ndim == 3:  # defensive: collapse an accidental RGB mask
            arr = arr[..., 0]
        counts = np.bincount(arr.ravel(), minlength=num_classes)
        if counts.size > num_classes:
            raise SystemExit(
                f"[train] {mask_path} contains class ids >= {num_classes}; "
                "re-run prepare_dataset.py"
            )
        total += counts
    return total.tolist()


def _build_criterion(loss_spec: dict, class_weights: list[float] | None, device,
                     co_stats: dict | None = None):
    """Build the torch loss for a loss_config spec (torch side of the recipe).

    ``loss_spec`` comes from ``loss_config.resolve_loss_spec`` (already
    validated); ``class_weights`` is the ``loss_config.class_weights`` vector —
    None under ``--class-weighting none``, in which case the CE base of
    combined/co_occurrence runs unweighted (weighted_ce itself rejects the
    combination at launch). ``co_stats`` (the validated co_stats.json dict) is
    required exactly for ``co_occurrence``. The default ``ce`` returns a plain
    ``nn.CrossEntropyLoss()`` — the historical recipe, untouched.
    """
    torch = _import_torch()
    import torch.nn as nn

    name = loss_spec["loss"]
    if name == "ce":
        return nn.CrossEntropyLoss()

    def _weights_tensor():
        # None under --class-weighting none: the CE base runs unweighted while
        # the loss keeps its other terms (snaq-parity Req 6.3).
        if class_weights is None:
            return None
        return torch.tensor(class_weights, dtype=torch.float32, device=device)

    if name == "weighted_ce":
        # weighted_ce + scheme none is rejected at spec resolution; a None here
        # would be plain ce in disguise.
        assert class_weights is not None, "weighted_ce requires class weights"
        return nn.CrossEntropyLoss(weight=_weights_tensor())

    if name == "focal":
        gamma = float(loss_spec["focal_gamma"])

        def focal(logits, targets):
            # Standard focal loss (Lin et al. 2017) over the per-pixel CE.
            ce = nn.functional.cross_entropy(logits, targets, reduction="none")
            pt = torch.exp(-ce)
            return ((1.0 - pt) ** gamma * ce).mean()

        return focal

    def dice(logits, targets):
        # Soft Dice over softmax probabilities vs one-hot targets, averaged
        # over classes; smoothing keeps absent classes finite.
        probs = torch.softmax(logits, dim=1)
        one_hot = nn.functional.one_hot(targets, probs.shape[1])
        one_hot = one_hot.permute(0, 3, 1, 2).to(probs.dtype)
        dims = (0, 2, 3)
        inter = (probs * one_hot).sum(dims)
        denom = probs.sum(dims) + one_hot.sum(dims)
        score = (2.0 * inter + loss_config.DICE_SMOOTH) / (denom + loss_config.DICE_SMOOTH)
        return 1.0 - score.mean()

    if name == "dice":
        return dice

    if name == "combined":
        dice_weight = float(loss_spec["dice_weight"])
        weighted_ce = nn.CrossEntropyLoss(weight=_weights_tensor())

        def combined(logits, targets):
            return dice_weight * dice(logits, targets) + (1.0 - dice_weight) * weighted_ce(logits, targets)

        return combined

    if name == "co_occurrence":
        # L = weighted_ce + lambda * L_co (segmenter-foundation design §4.3).
        # L_co: image-level predicted presence p_c = maxpool(softmax_c) — the
        # log-sum-exp / top-k pooling fallback (loss_config.DEFAULT_CO_POOLING
        # comment) is the documented alternative if a single spurious
        # activation saturating the max proves unstable — penalised with BCE
        # against ground-truth presence, pair-weighting implausible FALSE
        # presences (the confusion half); missed ground-truth classes (the
        # collapse half) are carried by the BCE term itself and the
        # weighted_ce base.
        assert co_stats is not None, "co_occurrence requires validated co_stats"
        weighted_ce = nn.CrossEntropyLoss(weight=_weights_tensor())
        lam = float(loss_spec["co_lambda"])
        # Decision 20: the presence term operates on the FOOD channels only —
        # "background present" is trivially true of every plate, and the
        # special channels are already supervised by the CE base — so the
        # priors, both presence vectors, and the pair weights are all
        # restricted to these palette indices.
        food = torch.tensor(
            loss_config.food_channel_indices(co_stats),
            dtype=torch.long, device=device,
        )
        priors = torch.tensor(
            loss_config.co_occurrence_priors(
                co_stats["joint_presence_counts"], co_stats["presence_counts"]
            ),
            dtype=torch.float32, device=device,
        )[food][:, food]  # [F, F]: priors[c, k] = P(c present | k present)

        def co_occurrence(logits, targets):
            base = weighted_ce(logits, targets)
            probs = torch.softmax(logits, dim=1)                    # [B, C, H, W]
            pred_presence = probs.amax(dim=(2, 3))[:, food]         # max-pool -> [B, F]
            gt_all = torch.zeros(                                   # [B, C] presence
                logits.shape[0], logits.shape[1],
                dtype=probs.dtype, device=logits.device,
            )
            gt_all.scatter_(1, targets.flatten(1), 1.0)
            gt = gt_all[:, food]                                    # [B, F]
            # compat[b, c] = max over ground-truth classes k of priors[c, k];
            # pair weight 1 for true presences, 1 + gain*(1 - compat) for
            # false ones (loss_config.false_presence_weights is the pure
            # single-image reference of this batched form).
            compat = (priors.unsqueeze(0) * gt.unsqueeze(1)).amax(dim=2)
            weights = torch.where(
                gt > 0,
                torch.ones_like(gt),
                1.0 + loss_config.CO_PAIR_GAIN * (1.0 - compat),
            )
            l_co = nn.functional.binary_cross_entropy(
                pred_presence.clamp(1e-6, 1.0 - 1e-6), gt, weight=weights
            )
            return base + lam * l_co

        return co_occurrence

    raise SystemExit(f"[train] unhandled loss {name!r}")  # unreachable: spec validated


def food_class_miou(model, loader, device, num_classes: int,
                    forward_logits=None) -> float:
    """Mean IoU over FOOD classes only (excludes 24/25/26 per §4/§5).

    Background dominates pixels; food-class mIoU is the §5 gate (>= 0.48,
    segmenter-foundation Decision 5). Classes
    absent from the val split (no GT and no prediction) are skipped from the mean.
    ``forward_logits`` is the arch registry's output normaliser (default: the
    torchvision ``["out"]`` dict convention).
    """
    torch = _import_torch()
    forward_logits = forward_logits or archs.dict_out_logits

    model.eval()
    inter = torch.zeros(num_classes, dtype=torch.float64)
    union = torch.zeros(num_classes, dtype=torch.float64)

    with torch.no_grad():
        for images, masks in loader:
            images = images.to(device)
            masks = masks.to(device)
            logits = forward_logits(model, images)
            preds = logits.argmax(dim=1)
            for cls in range(num_classes):
                pred_c = preds == cls
                gt_c = masks == cls
                inter[cls] += (pred_c & gt_c).sum().item()
                union[cls] += (pred_c | gt_c).sum().item()

    food_ious = []
    for cls in range(num_classes):
        if cls in NON_FOOD_CLASSES:
            continue
        if union[cls] == 0:
            continue  # class not present in GT or predictions on this split
        food_ious.append((inter[cls] / union[cls]).item())

    model.train()
    if not food_ious:
        return 0.0
    return float(sum(food_ious) / len(food_ious))


def _sidecar_path(out: str | Path) -> Path:
    """Default resume sidecar written next to the final checkpoint: <--out>.resume.pt."""
    out = Path(out)
    return out.parent / (out.name + ".resume.pt")


def _tensors_to_cpu(obj):
    """Recursively move tensors to CPU so the sidecar resumes across devices
    (MPS/CUDA/CPU) without misplaced optimizer state."""
    torch = _import_torch()
    if torch.is_tensor(obj):
        return obj.cpu()
    if isinstance(obj, dict):
        return {k: _tensors_to_cpu(v) for k, v in obj.items()}
    if isinstance(obj, (list, tuple)):
        return type(obj)(_tensors_to_cpu(v) for v in obj)
    return obj


def _load_resume_state(args) -> dict:
    """Load and validate the --resume sidecar BEFORE any model is built.

    Decision 3 (decision_log.md): reject hyperparameter drift, don't reconcile
    it — with the flags below forced to match, the restored optimizer state is
    consistent with the CLI by construction and provenance stays truthful.
    """
    torch = _import_torch()
    path = Path(args.resume)
    if not path.is_file():
        raise SystemExit(f"[train] resume file not found: {path}")
    try:
        state = torch.load(str(path), map_location="cpu")
    except Exception as exc:  # torn/corrupt file — same message style, no traceback
        raise SystemExit(f"[train] could not read resume file {path}: {exc}") from exc
    if not isinstance(state, dict) or "model" not in state or "optimizer" not in state:
        raise SystemExit(f"[train] {path} is not a training resume sidecar")
    expected = {
        "num_classes": args.num_classes,
        "palette_version": PALETTE_VERSION,
        "target_size": args.target_size,
        "lr": args.lr,
        "batch_size": args.batch_size,
        "augment": not args.no_augment,
        "loss": loss_config.normalise_loss_name(args.loss),
        "photometric_augment": args.photometric_augment,
        "init_checkpoint": args.init_checkpoint,
        "arch": args.arch,
        "class_weighting": args.class_weighting,
    }
    # Sidecars written before the opt-in loss/photometric/init/arch/weighting
    # flags existed lack these keys; absence means the historical defaults, not
    # drift. EXCEPT a weighted-loss sidecar with no class_weighting key: that
    # run used the removed inverse-frequency weighting (Decision 25), so
    # defaulting the missing key to "none" would silently change the training
    # criterion mid-run — reject it as unresumable instead.
    sidecar_loss = state.get("loss", loss_config.DEFAULT_LOSS)
    if "class_weighting" not in state and sidecar_loss in loss_config.WEIGHTED_LOSSES:
        raise SystemExit(
            f"[train] {path} is a legacy weighted-loss sidecar (loss "
            f"{sidecar_loss!r} with no class_weighting key): its run used the "
            "removed inverse-frequency weighting (Decision 25) and cannot be "
            "resumed without silently changing the criterion — start a fresh run"
        )
    legacy_defaults = {"loss": loss_config.DEFAULT_LOSS, "photometric_augment": False,
                       "init_checkpoint": None, "arch": archs.DEFAULT_ARCH,
                       "class_weighting": loss_config.DEFAULT_WEIGHTING}
    for key, want in expected.items():
        got = state.get(key, legacy_defaults.get(key))
        if got != want:
            raise SystemExit(
                f"[train] resume mismatch on {key}: sidecar has {got!r} but this "
                f"invocation has {want!r} — changing hyperparameters mid-run is not "
                "supported; start a fresh run"
            )
    return state


def _save_resume_state(sidecar: Path, model, optimizer, args,
                       pretrained: bool, epoch: int, last_miou: float) -> None:
    """Atomic per-epoch sidecar write (temp file + os.replace) so an interrupt
    mid-save can never leave a torn file; at most one epoch of progress is lost."""
    torch = _import_torch()
    # The first sidecar lands before _save_checkpoint's mkdir — create the
    # directory here too or epoch 1 of a fresh run dies at its first save.
    sidecar.parent.mkdir(parents=True, exist_ok=True)
    state = {
        "model": _tensors_to_cpu(model.state_dict()),
        "optimizer": _tensors_to_cpu(optimizer.state_dict()),
        "epoch": epoch,
        "num_classes": args.num_classes,
        "target_size": args.target_size,
        "palette_version": PALETTE_VERSION,
        "lr": args.lr,
        "batch_size": args.batch_size,
        "augment": not args.no_augment,
        "loss": loss_config.normalise_loss_name(args.loss),
        "photometric_augment": args.photometric_augment,
        "init_checkpoint": args.init_checkpoint,
        "arch": args.arch,
        "class_weighting": args.class_weighting,
        "pretrained": pretrained,
        "last_food_class_miou": last_miou,
    }
    tmp = sidecar.parent / (sidecar.name + ".tmp")
    torch.save(state, str(tmp))
    os.replace(tmp, sidecar)


def _loss_spec(args) -> dict:
    """The loss spec for this invocation (single construction point so the
    criterion and the recorded provenance can never disagree on co_lambda or
    the class-weighting scheme)."""
    return loss_config.resolve_loss_spec(args.loss, co_lambda=args.co_lambda,
                                         class_weighting=args.class_weighting)


def train(args) -> int:
    torch = _import_torch()

    sidecar = _sidecar_path(args.out)
    if args.resume is None and sidecar.is_file():
        raise SystemExit(
            f"[train] {sidecar} exists — a previous run was interrupted. Pass "
            f"--resume {sidecar} to continue it, or delete the file to start fresh."
        )
    resume_state = _load_resume_state(args) if args.resume else None

    device = _resolve_device(args.device)
    print(f"[train] device = {device}")

    loss_spec = _loss_spec(args)

    data_root = Path(args.data)

    # Co-occurrence statistics: fail fast BEFORE any data/model work when the
    # stats are missing or stale (seed / class-mapping SHA mismatch) — a silent
    # fallback would falsify the lineage's claim about the recipe (design §4.3).
    # --co-stats points at an EXTERNAL (corpus-derived) file when one is used
    # (snaq-parity Req 6.1); load_co_stats arbitrates the seed rules by source.
    co_stats = None
    co_stats_sha256 = None
    if loss_spec["loss"] == "co_occurrence":
        lineage = _load_lineage_module()
        mapping_path = Path(__file__).resolve().with_name(
            "class_mapping_foodseg103.json"
        )
        co_stats_path = (Path(args.co_stats) if args.co_stats
                         else data_root / loss_config.CO_STATS_FILENAME)
        co_stats = loss_config.load_co_stats(
            co_stats_path,
            split_seed=args.split_seed,
            class_mapping_sha256=lineage.file_sha256(mapping_path),
        )
        co_stats_sha256 = lineage.file_sha256(co_stats_path)
    augment = not args.no_augment
    train_ds = FoodSegDataset(data_root / "train", args.target_size, limit=args.limit,
                              augment=augment, photometric=args.photometric_augment)
    print(f"[train] train samples = {len(train_ds)}")

    val_dir = data_root / "val"
    val_loader = None
    if (val_dir / "images").is_dir():
        val_ds = FoodSegDataset(val_dir, args.target_size, limit=args.limit)
        val_loader = _make_loader(val_ds, args.batch_size, False, args.num_workers)
        print(f"[train] val samples = {len(val_ds)}")
    else:
        print("[train] no val split found; skipping mIoU eval")

    # drop_last: a trailing batch of size 1 crashes BatchNorm in train mode
    # (ASPP's global-pool branch yields [1, C, 1, 1] — one value per channel).
    # Val keeps every sample: eval mode uses running stats, so size-1 is fine.
    train_loader = _make_loader(train_ds, args.batch_size, True, args.num_workers,
                                drop_last=True)

    arch_spec = archs.get(args.arch)
    if resume_state is not None:
        # Weights come from the sidecar — build with weights=None (no download);
        # pretrained provenance carries the ORIGINAL run's value, not this flag.
        model = build_model(args.num_classes, pretrained=False, arch=args.arch)
        model.load_state_dict(resume_state["model"])
        pretrained = bool(resume_state["pretrained"])
        resumed_from_epoch = int(resume_state["epoch"])
        start_epoch = resumed_from_epoch + 1
        print(f"[train] resuming from {args.resume} (epoch {resumed_from_epoch} completed)")
    else:
        model = build_model(args.num_classes, pretrained=not args.no_pretrained,
                            init_checkpoint=args.init_checkpoint, arch=args.arch)
        pretrained = not args.no_pretrained
        resumed_from_epoch = None
        start_epoch = 1
    model.to(device)

    # Fine-tune the whole network (head + backbone) per §4 "fine-tuning the
    # head (and backbone)".
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr)
    if resume_state is not None:
        # load_state_dict casts restored state to each param's device/dtype.
        optimizer.load_state_dict(resume_state["optimizer"])

    class_weights = None
    if loss_config.loss_uses_class_weights(loss_spec["loss"], args.class_weighting):
        print(f"[train] deriving {args.class_weighting} class weights from train masks…")
        counts = _train_pixel_counts(train_ds, args.num_classes)
        class_weights = loss_config.class_weights(args.class_weighting, counts,
                                                  args.num_classes)
    criterion = _build_criterion(loss_spec, class_weights, device, co_stats)
    print(f"[train] loss = {loss_spec}"
          + (" | photometric augment ON" if args.photometric_augment else ""))

    last_miou = float(resume_state["last_food_class_miou"]) if resume_state else float("nan")
    for epoch in range(start_epoch, args.epochs + 1):
        # Poly decay (standard DeepLab recipe), stepped per epoch. Stateless by
        # design: the lr is a pure function of (epoch, args), so --resume needs
        # no scheduler state in the sidecar.
        lr = args.lr * (1.0 - (epoch - 1) / max(args.epochs, 1)) ** 0.9
        for group in optimizer.param_groups:
            group["lr"] = lr
        model.train()
        running = 0.0
        n_batches = 0
        for images, masks in train_loader:
            images = images.to(device)
            masks = masks.to(device)
            optimizer.zero_grad()
            logits = arch_spec.forward_logits(model, images)
            loss = criterion(logits, masks)
            loss.backward()
            optimizer.step()
            running += float(loss.item())
            n_batches += 1
        avg_loss = running / max(n_batches, 1)
        msg = f"[train] epoch {epoch}/{args.epochs} loss = {avg_loss:.4f}"

        if val_loader is not None and (epoch % args.val_every == 0 or epoch == args.epochs):
            miou = food_class_miou(model, val_loader, device, args.num_classes,
                                   forward_logits=arch_spec.forward_logits)
            last_miou = miou
            msg += f" | food-class mIoU = {miou:.4f}"
        print(msg)
        _save_resume_state(sidecar, model, optimizer, args, pretrained, epoch, last_miou)

    _save_checkpoint(model, args, last_miou, pretrained, resumed_from_epoch,
                     co_stats_sha256=co_stats_sha256,
                     co_stats_provenance=_co_stats_provenance(co_stats))
    if sidecar.is_file():
        sidecar.unlink()
        print(f"[train] removed resume sidecar {sidecar}")
    return 0


def _co_stats_provenance(co_stats: dict | None) -> dict | None:
    """The lineage ``co_stats_provenance`` object for EXTERNAL co-occurrence
    statistics (snaq-parity Req 6.1): source, ingredient-mapping SHA-256, and
    the palette-coverage lists the builder recorded. None for internal
    (split-derived) stats — the historical lineage shape is unchanged — and
    for runs without the co-occurrence loss."""
    if co_stats is None or "source" not in co_stats:
        return None
    return {
        "source": co_stats["source"],
        "ingredient_mapping_sha256": co_stats.get("ingredient_mapping_sha256"),
        "palette_coverage": co_stats.get("palette_coverage"),
    }


def _pretrained_checkpoint_record(args) -> dict | None:
    """The ``pretrained_checkpoint`` lineage object (segmenter-foundation
    Req 2.2 / Decision 17, model-production Req 1.3): source URL, licence, and
    SHA-256 of the published initialisation, recorded only when the invocation
    supplies them — absent fields stay "unknown" rather than guessed."""
    values = (args.pretrained_source_url, args.pretrained_licence,
              args.pretrained_sha256)
    if not any(values):
        return None
    return {
        "source_url": args.pretrained_source_url or "unknown",
        "licence": args.pretrained_licence or "unknown",
        "sha256": args.pretrained_sha256 or "unknown",
    }


def _save_checkpoint(model, args, last_miou: float, pretrained: bool,
                     resumed_from_epoch: int | None = None,
                     co_stats_sha256: str | None = None,
                     co_stats_provenance: dict | None = None) -> None:
    """Save a dict consumed directly by export.load_checkpoint and make_fixtures.

    export.load_checkpoint does ``if isinstance(state, dict) and "model" in state:
    state = state["model"]`` -- so the "model" key holds the state_dict. The other
    keys are provenance (§11) for the iteration loop / fixture stamping. On
    resumed runs ``pretrained`` carries the original run's value (from the
    sidecar) and the lineage records ``resumed_from_epoch``.
    """
    torch = _import_torch()
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)

    # Opt-in recipe provenance. EMPTY for the default recipe (no --loss, no
    # --photometric-augment) so a default run's checkpoint keys and recorded
    # train_config stay byte-for-byte identical to a pre-flag run; absence
    # means the historical unweighted CE / no photometric jitter. For the
    # co-occurrence loss this carries co_lambda and co_pooling into lineage
    # (design §4.3).
    recipe_extras = loss_config.loss_train_config(_loss_spec(args))
    if args.photometric_augment:
        recipe_extras["photometric_augment"] = True
    if args.arch != archs.DEFAULT_ARCH:
        # Non-default architecture (snaq-parity Req 5.4): recorded in checkpoint
        # + lineage train_config so run_validation.py and export.py resolve the
        # arch back from provenance; absence means the historical deeplab_mnv3.
        recipe_extras["arch"] = args.arch
    if args.init_checkpoint:
        # Local path of the consumed init (Decision 19 wiring); the
        # pretrained_checkpoint object carries its source URL/licence/SHA-256.
        recipe_extras["init_checkpoint"] = args.init_checkpoint

    checkpoint = {
        "model": model.state_dict(),
        "num_classes": args.num_classes,
        "target_size": args.target_size,
        "palette_version": PALETTE_VERSION,
        "epochs": args.epochs,
        "lr": args.lr,
        "lr_schedule": LR_SCHEDULE,
        "augment": not args.no_augment,
        "pretrained": pretrained,
        "last_food_class_miou": last_miou,
        **recipe_extras,
    }
    torch.save(checkpoint, str(out))
    print(f"[train] saved checkpoint -> {out}")

    # Build-lineage manifest (Req 1.3, task 3). Written alongside the checkpoint
    # under build/; provenance only, not shipped in the app bundle. mIoU metrics
    # are populated by the validation step (task 9), null here.
    lineage = _load_lineage_module()
    train_config = {
        "num_classes": args.num_classes,
        "target_size": args.target_size,
        "epochs": args.epochs,
        "batch_size": args.batch_size,
        "lr": args.lr,
        "lr_schedule": LR_SCHEDULE,
        "augment": not args.no_augment,
        "pretrained": pretrained,
        **recipe_extras,
    }
    if resumed_from_epoch is not None:
        # Provenance must never claim a single uninterrupted run.
        train_config["resumed_from_epoch"] = resumed_from_epoch
    manifest = lineage.build_lineage(
        out,
        train_config=train_config,
        split_seed=args.split_seed,
        foodseg103_source=args.foodseg103_source,
        palette_version=PALETTE_VERSION,
        pretrained_checkpoint=_pretrained_checkpoint_record(args),
        co_stats_sha256=co_stats_sha256,
        co_stats_provenance=co_stats_provenance,
    )
    lineage_path = lineage.write_lineage(manifest, out.parent / "lineage.json")
    print(f"[train] lineage -> {lineage_path} (model_version={manifest['model_version']})")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", default="data/foodseg103_remapped_v2",
                        help="Remapped dataset root with train/val[/heldout] splits.")
    parser.add_argument("--num-classes", type=int, default=36)
    parser.add_argument("--target-size", type=int, default=513)
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--out", default="tools/segmenter/build/checkpoint.pt")
    parser.add_argument("--arch", default=archs.DEFAULT_ARCH,
                        choices=archs.ARCH_CHOICES,
                        help="Model architecture from the shared registry "
                             "(archs.py; snaq-parity Req 5.4). Default is the "
                             "shipping deeplab_mnv3; recorded in checkpoint/"
                             "lineage train_config for non-default runs and "
                             "checked by the resume drift-check.")
    parser.add_argument("--resume", default=None, metavar="PATH",
                        help="Resume an interrupted run from its sidecar "
                             "(<--out>.resume.pt, written after every completed epoch). "
                             "Hyperparameters must match the original invocation.")
    parser.add_argument("--split-seed", type=int, default=None,
                        help="Dataset split seed (from prepare_dataset.py); recorded in build lineage.")
    parser.add_argument("--foodseg103-source", default=None,
                        help="FoodSeg103 source/version string; recorded in build lineage.")
    parser.add_argument("--device", default="auto",
                        help="auto (default) detects cuda/mps/cpu; or pass an explicit device.")
    parser.add_argument("--val-every", type=int, default=1,
                        help="Run food-class mIoU eval every N epochs (and on the last epoch).")
    parser.add_argument("--limit", type=int, default=None,
                        help="Cap samples per split for smoke runs.")
    parser.add_argument("--no-pretrained", action="store_true",
                        help="Build with weights=None (no network download) for smoke runs.")
    parser.add_argument("--init-checkpoint", default=None, metavar="PATH",
                        help="Initialise the MobileNetV3 backbone from a LOCAL "
                             "classifier state dict (adapter_probe.py "
                             "--save-adapted output or a torchvision "
                             "IMAGENET1K_V2 download) instead of the COCO-seg "
                             "DEFAULT weights; the DeepLab head starts fresh. "
                             "Recorded in the checkpoint/lineage train_config; "
                             "pair with the --pretrained-* flags so lineage "
                             "records the source (Req 2.2 / Decision 19).")
    parser.add_argument("--no-augment", action="store_true",
                        help="Disable train-split augmentation (hflip + random "
                             "scale-up crop) — e.g. for deterministic smoke runs.")
    parser.add_argument("--loss", default=None, choices=loss_config.LOSS_CHOICES,
                        help="Training loss (see loss_config.py). Omit for the "
                             "historical unweighted cross-entropy. weighted_ce/"
                             "combined/co_occurrence derive class weights from "
                             "the train masks per --class-weighting. "
                             "co_occurrence (design §4.3) adds an image-level "
                             "presence BCE term weighted by the co_stats.json "
                             "priors and requires --split-seed to match the "
                             "prepared dataset's co_stats.json.")
    parser.add_argument("--class-weighting", default=loss_config.DEFAULT_WEIGHTING,
                        choices=loss_config.WEIGHTING_CHOICES,
                        help="Class-weighting scheme for the weighted losses "
                             "(snaq-parity Req 6.3). Default none; sqrt_inverse "
                             "is the deliberately milder re-test scheme — "
                             "inverse frequency is removed (segmenter-"
                             "foundation Decision 25). weighted_ce requires an "
                             "active scheme.")
    parser.add_argument("--co-stats", default=None, metavar="PATH",
                        help="Override the co-occurrence statistics file "
                             "(default: <--data>/co_stats.json). Point at a "
                             "build_external_co_stats.py output to train "
                             "against corpus-derived priors (snaq-parity "
                             "Req 6.1); source, mapping SHA, and palette "
                             "coverage land in lineage.")
    parser.add_argument("--co-lambda", type=float,
                        default=loss_config.DEFAULT_CO_LAMBDA,
                        help="Mixing weight for the co-occurrence presence "
                             "term (co_occurrence loss only); recorded in "
                             "lineage.")
    parser.add_argument("--pretrained-source-url", default=None,
                        help="Source URL of the published pretrained checkpoint "
                             "this run initialises from; recorded in lineage "
                             "(Req 2.2).")
    parser.add_argument("--pretrained-licence", default=None,
                        help="Licence identifier of the pretrained checkpoint "
                             "(e.g. BSD-3-Clause); recorded in lineage.")
    parser.add_argument("--pretrained-sha256", default=None,
                        help="SHA-256 of the pretrained checkpoint file; "
                             "recorded in lineage.")
    parser.add_argument("--photometric-augment", action="store_true",
                        help="Opt-in brightness/contrast/colour jitter on the "
                             "TRAIN images only (never the mask); off by default.")
    parser.add_argument("--num-workers", type=int, default=4)
    args = parser.parse_args(argv)

    if args.init_checkpoint and args.no_pretrained:
        parser.error(
            "--init-checkpoint and --no-pretrained are mutually exclusive: "
            "the init checkpoint IS the pretrained initialisation."
        )

    if (loss_config.normalise_loss_name(args.loss) == "weighted_ce"
            and args.class_weighting == "none"):
        parser.error(
            "--loss weighted_ce needs an active --class-weighting scheme "
            "(sqrt_inverse): under 'none' it is plain ce in disguise and would "
            "corrupt a loss-sweep verdict (snaq-parity Req 6.3)."
        )

    if args.num_classes <= PALETTE_BACKGROUND:
        parser.error(
            f"--num-classes {args.num_classes} does not cover the palette: "
            f"letterbox padding labels masks with the background channel "
            f"({PALETTE_BACKGROUND}), so at least {PALETTE_BACKGROUND + 1} "
            f"classes are required."
        )

    # A corpus in a different label space trains happily and scores plausibly —
    # every index it reads is legal (bugfix anchor-label-space-mismatch). Cheaper
    # to refuse here than to discover it after a multi-hour run.
    validation.assert_label_space(args.data, args.num_classes)

    return train(args)


if __name__ == "__main__":
    sys.exit(main())

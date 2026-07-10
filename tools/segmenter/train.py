#!/usr/bin/env python3
"""Segmenter training pipeline (step 4 of docs/ml-training.md §4, decisions 25/28).

Transfer-learns DeepLabV3 + MobileNetV3-Large (torchvision) at 513x513 for the
35-class palette (24 solid + 8 coarse liquid + background + unknown_food +
unsupported_liquid — the redefined v1, Decisions 23/24),
starting from the torchvision pretrained backbone, fine-tuning head + backbone on
the remapped FoodSeg103 train split, and saving a single PyTorch checkpoint.

That ``.pt`` is the single source of truth (Decision 28): ``export.py`` and
``make_fixtures.py`` both consume it directly. The architecture here is NOT
redefined locally -- it is built via ``export.load_checkpoint(num_classes, None)``
so the saved ``state_dict`` is byte-compatible with what the exporter loads back.

Long local runs (e.g. Apple-silicon MPS) are interruptible: a resume sidecar
(``<--out>.resume.pt``) is written atomically after every completed epoch and
``--resume`` continues the epoch sequence with identical hyperparameters
(docs/ml-training.md §4; specs/estimation/resumable-segmenter-training/).

Usage (docs/ml-training.md §4)::

    python tools/segmenter/train.py \\
        --data data/foodseg103_remapped \\
        --num-classes 35 --target-size 513 \\
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
import loss_config  # noqa: E402

# ImageNet normalization -- MUST match export.reference_input (train/serve match).
IMAGENET_MEAN = (0.485, 0.456, 0.406)
IMAGENET_STD = (0.229, 0.224, 0.225)

# Palette background channel (ClassPalette.v1Standard / prepare_dataset.py:
# 24 solid + 8 liquid, then background at 32). Letterbox padding is labelled
# background so the model learns padded regions are not food.
PALETTE_BACKGROUND = 32

# Special (non-food) channels excluded from food-class mIoU. These mirror
# class_mapping_foodseg103_v1.json:special_channels and §11 channel ordering.
BACKGROUND_CLASS = 32
UNKNOWN_FOOD_CLASS = 33
UNSUPPORTED_LIQUID_CLASS = 34
NON_FOOD_CLASSES = (BACKGROUND_CLASS, UNKNOWN_FOOD_CLASS, UNSUPPORTED_LIQUID_CLASS)

PALETTE_VERSION = "v1"

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


def _load_export_module():
    """Import the sibling export.py by path so we reuse its model construction.

    Keeping a single source of architecture truth (Decision 28) means train and
    export must build the identical DeepLabV3+MobileNetV3-Large with the head
    swapped for num_classes; importing export.load_checkpoint guarantees that.
    """
    export_path = Path(__file__).resolve().with_name("export.py")
    spec = importlib.util.spec_from_file_location("segmenter_export", export_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Could not load sibling export module at {export_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _load_lineage_module():
    """Import the sibling lineage.py by path (pure stdlib; no torch needed)."""
    lineage_path = Path(__file__).resolve().with_name("lineage.py")
    spec = importlib.util.spec_from_file_location("segmenter_lineage", lineage_path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"Could not load sibling lineage module at {lineage_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_model(num_classes: int, pretrained: bool):
    """Build the training model via export.load_checkpoint for architectural parity.

    ``export.load_checkpoint(num_classes, None)`` returns the torchvision
    pretrained-backbone model with the head replaced for ``num_classes`` (and set
    to eval); we switch it back to train mode. When ``pretrained`` is False we
    rebuild with weights=None so a smoke run needs no network download.
    """
    torch = _import_torch()
    export = _load_export_module()

    if pretrained:
        model = export.load_checkpoint(num_classes, None)
    else:
        # Mirror export.load_checkpoint's construction but skip the weight
        # download. This stays consistent with the exporter's architecture:
        # same model family, same head replacement.
        from torchvision.models.segmentation import deeplabv3_mobilenet_v3_large
        from torchvision.models.segmentation.deeplabv3 import DeepLabHead

        model = deeplabv3_mobilenet_v3_large(weights=None, aux_loss=False)
        in_ch = model.classifier[0].convs[0][0].in_channels
        model.classifier = DeepLabHead(in_ch, num_classes)

    model.train()
    return model


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


def _build_criterion(loss_spec: dict, class_weights: list[float] | None, device):
    """Build the torch loss for a loss_config spec (torch side of the recipe).

    ``loss_spec`` comes from ``loss_config.resolve_loss_spec`` (already
    validated); ``class_weights`` is required exactly when
    ``loss_config.loss_uses_class_weights`` says so. The default ``ce`` returns
    a plain ``nn.CrossEntropyLoss()`` — the historical recipe, untouched.
    """
    torch = _import_torch()
    import torch.nn as nn

    name = loss_spec["loss"]
    if name == "ce":
        return nn.CrossEntropyLoss()

    def _weights_tensor():
        assert class_weights is not None, f"{name} requires class weights"
        return torch.tensor(class_weights, dtype=torch.float32, device=device)

    if name == "weighted_ce":
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

    raise SystemExit(f"[train] unhandled loss {name!r}")  # unreachable: spec validated


def food_class_miou(model, loader, device, num_classes: int) -> float:
    """Mean IoU over FOOD classes only (excludes 24/25/26 per §4/§5).

    Background dominates pixels; food-class mIoU is the §5 gate (>= 0.48,
    segmenter-foundation Decision 5). Classes
    absent from the val split (no GT and no prediction) are skipped from the mean.
    """
    torch = _import_torch()

    model.eval()
    inter = torch.zeros(num_classes, dtype=torch.float64)
    union = torch.zeros(num_classes, dtype=torch.float64)

    with torch.no_grad():
        for images, masks in loader:
            images = images.to(device)
            masks = masks.to(device)
            logits = model(images)["out"]
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
    }
    # Sidecars written before the opt-in loss/photometric flags existed lack
    # these keys; absence means the historical defaults, not drift.
    legacy_defaults = {"loss": loss_config.DEFAULT_LOSS, "photometric_augment": False}
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
        "pretrained": pretrained,
        "last_food_class_miou": last_miou,
    }
    tmp = sidecar.parent / (sidecar.name + ".tmp")
    torch.save(state, str(tmp))
    os.replace(tmp, sidecar)


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

    loss_spec = loss_config.resolve_loss_spec(args.loss)

    data_root = Path(args.data)
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

    if resume_state is not None:
        # Weights come from the sidecar — build with weights=None (no download);
        # pretrained provenance carries the ORIGINAL run's value, not this flag.
        model = build_model(args.num_classes, pretrained=False)
        model.load_state_dict(resume_state["model"])
        pretrained = bool(resume_state["pretrained"])
        resumed_from_epoch = int(resume_state["epoch"])
        start_epoch = resumed_from_epoch + 1
        print(f"[train] resuming from {args.resume} (epoch {resumed_from_epoch} completed)")
    else:
        model = build_model(args.num_classes, pretrained=not args.no_pretrained)
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
    if loss_config.loss_uses_class_weights(loss_spec["loss"]):
        print("[train] deriving inverse-frequency class weights from train masks…")
        counts = _train_pixel_counts(train_ds, args.num_classes)
        class_weights = loss_config.inverse_frequency_weights(counts, args.num_classes)
    criterion = _build_criterion(loss_spec, class_weights, device)
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
            logits = model(images)["out"]
            loss = criterion(logits, masks)
            loss.backward()
            optimizer.step()
            running += float(loss.item())
            n_batches += 1
        avg_loss = running / max(n_batches, 1)
        msg = f"[train] epoch {epoch}/{args.epochs} loss = {avg_loss:.4f}"

        if val_loader is not None and (epoch % args.val_every == 0 or epoch == args.epochs):
            miou = food_class_miou(model, val_loader, device, args.num_classes)
            last_miou = miou
            msg += f" | food-class mIoU = {miou:.4f}"
        print(msg)
        _save_resume_state(sidecar, model, optimizer, args, pretrained, epoch, last_miou)

    _save_checkpoint(model, args, last_miou, pretrained, resumed_from_epoch)
    if sidecar.is_file():
        sidecar.unlink()
        print(f"[train] removed resume sidecar {sidecar}")
    return 0


def _save_checkpoint(model, args, last_miou: float, pretrained: bool,
                     resumed_from_epoch: int | None = None) -> None:
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
    # means the historical unweighted CE / no photometric jitter.
    recipe_extras = loss_config.loss_train_config(loss_config.resolve_loss_spec(args.loss))
    if args.photometric_augment:
        recipe_extras["photometric_augment"] = True

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
    )
    lineage_path = lineage.write_lineage(manifest, out.parent / "lineage.json")
    print(f"[train] lineage -> {lineage_path} (model_version={manifest['model_version']})")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--data", default="data/foodseg103_remapped",
                        help="Remapped dataset root with train/val[/heldout] splits.")
    parser.add_argument("--num-classes", type=int, default=35)
    parser.add_argument("--target-size", type=int, default=513)
    parser.add_argument("--epochs", type=int, default=60)
    parser.add_argument("--batch-size", type=int, default=16)
    parser.add_argument("--lr", type=float, default=1e-3)
    parser.add_argument("--out", default="tools/segmenter/build/checkpoint.pt")
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
    parser.add_argument("--no-augment", action="store_true",
                        help="Disable train-split augmentation (hflip + random "
                             "scale-up crop) — e.g. for deterministic smoke runs.")
    parser.add_argument("--loss", default=None, choices=loss_config.LOSS_CHOICES,
                        help="Training loss (see loss_config.py). Omit for the "
                             "historical unweighted cross-entropy; weighted_ce/"
                             "combined derive inverse-frequency class weights "
                             "from the train masks.")
    parser.add_argument("--photometric-augment", action="store_true",
                        help="Opt-in brightness/contrast/colour jitter on the "
                             "TRAIN images only (never the mask); off by default.")
    parser.add_argument("--num-workers", type=int, default=4)
    args = parser.parse_args(argv)

    return train(args)


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Remap FoodSeg103 masks to the 27-channel palette and cut splits (ml-training §3c).

This is step 3c of the segmenter training pipeline. It consumes the class-mapping
JSON produced by ``build_class_mapping.py`` (§3b) and applies it to every
FoodSeg103 PNG mask, remapping each source category-id pixel value to the medata
27-channel palette:

    channels 0-23 : the 24 food classes (ClassPalette.v1Standard order)
    channel  24   : background
    channel  25   : unknown_food
    channel  26   : unsupported_liquid

Mapping entries with ``target_index: null`` (rule ``curated_drop``) are remapped
to background (channel 24) so dropped source classes never pollute a food class.

After remapping, the full image set is shuffled deterministically with a fixed
RNG seed and carved into held-out / val / train splits. The held-out split is the
"Held-out segmenter test set" of §1 and MUST stay reproducible across training
runs -- the seed and fractions are recorded in ``out/splits.json`` alongside the
exact file lists.

Usage::

    python tools/segmenter/prepare_dataset.py \\
        --src data/foodseg103 \\
        --mapping tools/segmenter/class_mapping_foodseg103_v1.json \\
        --out data/foodseg103_remapped \\
        --heldout-frac 0.12 --val-frac 0.1 --seed 1234

Heavy deps (numpy, pillow) are imported lazily so the module imports -- and
``--help`` works -- without them installed.
"""

from __future__ import annotations

import argparse
import json
import random
import shutil
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple


def _import_numpy():
    try:
        import numpy as np
        return np
    except ImportError as exc:
        raise SystemExit(
            "numpy is required. Install with:\n"
            "  pip install numpy"
        ) from exc


def _import_pillow():
    try:
        from PIL import Image
        return Image
    except ImportError as exc:
        raise SystemExit(
            "Pillow is required. Install with:\n"
            "  pip install pillow"
        ) from exc


# FoodSeg103 ships its background as category id 0; the mapping JSON already
# routes id 0 -> channel 24 (background), so no special-casing is needed here.
# Dropped classes (target_index null) fall back to this channel too.
BACKGROUND_CHANNEL = 24

IMAGE_EXTS = (".jpg", ".jpeg", ".png")


def load_mapping(path: Path) -> dict:
    """Load and lightly validate the §3b class-mapping JSON."""
    mapping = json.loads(path.read_text(encoding="utf-8"))
    if "mappings" not in mapping or "channel_count" not in mapping:
        raise SystemExit(
            f"{path} does not look like a build_class_mapping.py output "
            "(missing 'mappings'/'channel_count')."
        )
    return mapping


def build_lut(mapping: dict):
    """Build a numpy uint8 lookup table: source category id -> target channel.

    The LUT has size (max_source_id + 1). Source ids absent from the mapping
    (shouldn't happen for a real FoodSeg103 mask, but be defensive) and entries
    with ``target_index: null`` (rule ``curated_drop``) resolve to background.
    """
    np = _import_numpy()
    entries = mapping["mappings"]
    max_id = max(e["source_id"] for e in entries)
    lut = np.full(max_id + 1, BACKGROUND_CHANNEL, dtype=np.uint8)
    for e in entries:
        target = e["target_index"]
        lut[e["source_id"]] = BACKGROUND_CHANNEL if target is None else target
    return lut


def discover_pairs(src: Path) -> List[Tuple[Path, Path]]:
    """Find (image, mask) path pairs under a FoodSeg103 tree.

    Preferred layout (the dataset's own release structure):
        Images/img_dir/{train,test}/*.jpg   images
        Images/ann_dir/{train,test}/*.png   single-channel masks

    Fallback: if that exact layout isn't present, discover every ``*.png`` under
    ``src`` and treat each as a mask, then look for an image with the same
    basename (any of .jpg/.jpeg/.png) somewhere under ``src``. This keeps the
    script usable on flattened / non-standard dumps and on the synthetic smoke
    fixtures. Assumption: mask and image share a basename (stem).
    """
    pairs: List[Tuple[Path, Path]] = []

    img_root = src / "Images" / "img_dir"
    ann_root = src / "Images" / "ann_dir"
    if img_root.is_dir() and ann_root.is_dir():
        for split in ("train", "test"):
            ann_dir = ann_root / split
            img_dir = img_root / split
            if not ann_dir.is_dir():
                continue
            for mask in sorted(ann_dir.glob("*.png")):
                img = _find_image(img_dir, mask.stem)
                if img is not None:
                    pairs.append((img, mask))
        if pairs:
            return pairs

    # Fallback discovery: every PNG is a candidate mask; match images by stem.
    # We index images first so a mask that happens to itself be a .png isn't
    # mistaken for its own image.
    images: Dict[str, Path] = {}
    masks: List[Path] = []
    for p in sorted(src.rglob("*")):
        if not p.is_file():
            continue
        suffix = p.suffix.lower()
        # Heuristic: files under an *ann* / *mask* / *label* dir, or any lone
        # png, are masks; everything else with an image ext is an image.
        lowered = str(p).lower()
        is_mask_dir = any(k in lowered for k in ("ann", "mask", "label", "seg"))
        if suffix == ".png" and (is_mask_dir or "img" not in lowered):
            masks.append(p)
        elif suffix in IMAGE_EXTS:
            images.setdefault(p.stem, p)

    for mask in masks:
        img = images.get(mask.stem)
        if img is not None and img != mask:
            pairs.append((img, mask))
    return pairs


def _find_image(img_dir: Path, stem: str) -> Optional[Path]:
    for ext in IMAGE_EXTS:
        candidate = img_dir / f"{stem}{ext}"
        if candidate.is_file():
            return candidate
    return None


def remap_mask(mask_path: Path, lut, out_path: Path) -> None:
    """Apply the LUT to a single-channel mask and write a uint8 PNG."""
    np = _import_numpy()
    Image = _import_pillow()
    arr = np.asarray(Image.open(mask_path))
    if arr.ndim == 3:
        # Tolerate masks stored as RGB(A) where the id sits in the first channel.
        arr = arr[..., 0]
    arr = arr.astype(np.int64)
    if int(arr.max()) >= lut.shape[0]:
        raise SystemExit(
            f"{mask_path}: pixel id {int(arr.max())} exceeds mapping range "
            f"(LUT covers 0..{lut.shape[0] - 1}). Wrong mapping file?"
        )
    remapped = lut[arr].astype(np.uint8)
    Image.fromarray(remapped, mode="L").save(out_path)


def carve_splits(
    pairs: List[Tuple[Path, Path]],
    heldout_frac: float,
    val_frac: float,
    seed: int,
) -> Dict[str, List[Tuple[Path, Path]]]:
    """Deterministically shuffle and slice pairs into heldout / val / train.

    Order is held-out first, then val, then the remainder is train. Slicing the
    fixed-seed shuffle this way keeps the held-out set stable even if val_frac
    changes between runs.
    """
    if heldout_frac < 0 or val_frac < 0 or heldout_frac + val_frac >= 1:
        raise SystemExit(
            f"invalid fractions: heldout={heldout_frac} val={val_frac} "
            "(each >= 0 and their sum < 1)"
        )
    ordered = sorted(pairs, key=lambda p: p[1].stem)  # stable base order
    rng = random.Random(seed)
    rng.shuffle(ordered)

    n = len(ordered)
    n_heldout = int(n * heldout_frac)
    n_val = int(n * val_frac)
    heldout = ordered[:n_heldout]
    val = ordered[n_heldout:n_heldout + n_val]
    train = ordered[n_heldout + n_val:]
    return {"train": train, "val": val, "heldout": heldout}


def write_split(
    name: str,
    pairs: List[Tuple[Path, Path]],
    out: Path,
    lut,
) -> List[str]:
    """Copy images and write remapped masks for one split; return the stems."""
    img_out = out / name / "images"
    mask_out = out / name / "masks"
    img_out.mkdir(parents=True, exist_ok=True)
    mask_out.mkdir(parents=True, exist_ok=True)

    stems: List[str] = []
    for img, mask in pairs:
        stem = mask.stem
        shutil.copy2(img, img_out / img.name)
        remap_mask(mask, lut, mask_out / f"{stem}.png")
        stems.append(stem)
    return stems


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--src", required=True,
                        help="FoodSeg103 root (contains Images/img_dir + ann_dir).")
    parser.add_argument("--mapping", required=True,
                        help="class_mapping_foodseg103_v1.json from §3b.")
    parser.add_argument("--out", required=True,
                        help="Output root for remapped masks + splits.")
    parser.add_argument("--heldout-frac", type=float, default=0.12,
                        help="Fraction of all images for the held-out test set.")
    parser.add_argument("--val-frac", type=float, default=0.1,
                        help="Fraction of all images for the validation set.")
    parser.add_argument("--seed", type=int, default=1234,
                        help="RNG seed; fixes the held-out split across runs.")
    args = parser.parse_args(argv)

    src = Path(args.src)
    out = Path(args.out)
    mapping = load_mapping(Path(args.mapping))
    lut = build_lut(mapping)

    pairs = discover_pairs(src)
    if not pairs:
        raise SystemExit(
            f"no (image, mask) pairs found under {src}. Expected "
            "Images/img_dir/{train,test}/*.jpg + Images/ann_dir/{train,test}/*.png "
            "or matching image/mask basenames."
        )

    splits = carve_splits(pairs, args.heldout_frac, args.val_frac, args.seed)

    out.mkdir(parents=True, exist_ok=True)
    split_stems = {
        name: write_split(name, split_pairs, out, lut)
        for name, split_pairs in splits.items()
    }

    manifest = {
        "source": str(src),
        "mapping": str(Path(args.mapping)),
        "channel_count": mapping["channel_count"],
        "seed": args.seed,
        "heldout_frac": args.heldout_frac,
        "val_frac": args.val_frac,
        "total": len(pairs),
        "counts": {name: len(stems) for name, stems in split_stems.items()},
        "files": split_stems,
    }
    (out / "splits.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )

    print(
        f"[prepare_dataset] {len(pairs)} pairs -> "
        f"train={manifest['counts']['train']} "
        f"val={manifest['counts']['val']} "
        f"heldout={manifest['counts']['heldout']} "
        f"(seed={args.seed}); wrote {out}/splits.json"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

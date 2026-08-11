#!/usr/bin/env python3
"""Merge FoodSeg103 (v2-remapped) + Food Recognition 2022 into one training
corpus (myfoodrepo-bridge dataset-bridge task 5, MD-30).

Split posture (recorded in the output ``splits.json``):

- **FoodSeg103** keeps its frozen-seed stratified carve verbatim (seed
  20260715, membership verified identical to the v1 carve): train/val/heldout
  link through unchanged. The 182-image leak-free anchor
  (``data/foodseg103_remapped/heldout_leakfree/``) is a subset of that heldout
  split, is never written to, and its stems are asserted absent from merged
  train/val.
- **Food Recognition 2022** joins with its official splits: the 39,962-image
  training release enters merged ``train``, the 1,000-image public validation
  release enters merged ``val``. It contributes nothing to ``heldout`` — the
  promotion metric stays the FoodSeg103 leak-free anchor, apples-to-apples
  with the 0.3776 baseline of ``24e0b022241a``.

Files are symlinked, not copied (the corpus lives only in the main checkout's
gitignored ``data/`` tree). Food-Recognition entries are prefixed ``fr22_`` so
their numeric stems can never collide with FoodSeg103's zero-padded ids.

``co_stats.json`` (schema ``co_stats``, food-channels-only presence) is
rebuilt over the MERGED train split via ``prepare_dataset.build_co_stats``.
The stamped ``class_mapping_sha256`` is the FoodSeg103 mapping's (what
``train.py`` hashes by default); the Food-Recognition mapping's SHA-256 is
recorded alongside as ``class_mapping_sha256_foodrec2022``.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path
from typing import Dict, List

import numpy as np
from PIL import Image

from prepare_dataset import build_co_stats

CHANNEL_COUNT = 36
SPECIALS = [33, 34, 35]
FOODSEG_SEED = 20260715
FR22_PREFIX = "fr22_"


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def link_pair(images_dst: Path, masks_dst: Path, image: Path, mask: Path,
              stem: str) -> None:
    img_link = images_dst / f"{stem}{image.suffix}"
    mask_link = masks_dst / f"{stem}.png"
    if not img_link.exists():
        img_link.symlink_to(image.resolve())
    if not mask_link.exists():
        mask_link.symlink_to(mask.resolve())


def link_foodseg_split(src_split: Path, dst_split: Path) -> List[str]:
    stems = []
    images_dst = dst_split / "images"
    masks_dst = dst_split / "masks"
    images_dst.mkdir(parents=True, exist_ok=True)
    masks_dst.mkdir(parents=True, exist_ok=True)
    for image in sorted((src_split / "images").iterdir()):
        mask = src_split / "masks" / f"{image.stem}.png"
        if not mask.is_file():
            raise SystemExit(f"FoodSeg103 mask missing for {image}")
        link_pair(images_dst, masks_dst, image, mask, image.stem)
        stems.append(image.stem)
    return stems


def link_foodrec_split(images_src: Path, masks_src: Path,
                       dst_split: Path) -> List[str]:
    stems = []
    images_dst = dst_split / "images"
    masks_dst = dst_split / "masks"
    images_dst.mkdir(parents=True, exist_ok=True)
    masks_dst.mkdir(parents=True, exist_ok=True)
    for mask in sorted(masks_src.glob("*.png")):
        image = images_src / f"{mask.stem}.jpg"
        if not image.is_file():
            raise SystemExit(f"Food-Recognition image missing for {mask}")
        stem = f"{FR22_PREFIX}{mask.stem}"
        link_pair(images_dst, masks_dst, image, mask, stem)
        stems.append(stem)
    return stems


def scan_masks(split_dir: Path) -> tuple:
    """Per-channel pixel counts and per-image food-presence for one split."""
    pixel_counts = np.zeros(CHANNEL_COUNT, dtype=np.int64)
    presence: List[frozenset] = []
    for mask_path in sorted((split_dir / "masks").iterdir()):
        arr = np.asarray(Image.open(mask_path))
        counts = np.bincount(arr.ravel(), minlength=CHANNEL_COUNT)
        if len(counts) > CHANNEL_COUNT:
            raise SystemExit(
                f"{mask_path} has pixel values >= {CHANNEL_COUNT}")
        pixel_counts += counts
        presence.append(frozenset(int(c) for c in np.nonzero(counts)[0]))
    return pixel_counts.tolist(), presence


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--foodseg",
                        default="/Users/r/repos/medata/data/foodseg103_remapped_v2")
    parser.add_argument("--foodrec",
                        default="/Users/r/repos/medata/data/foodrec2022")
    parser.add_argument("--anchor",
                        default="/Users/r/repos/medata/data/foodseg103_remapped/heldout_leakfree")
    parser.add_argument("--foodseg-mapping",
                        default="/Users/r/repos/medata/tools/segmenter/class_mapping_foodseg103.json")
    parser.add_argument("--foodrec-mapping",
                        default="/Users/r/repos/medata/tools/segmenter/class_mapping_foodrec2022.json")
    parser.add_argument("--out",
                        default="/Users/r/repos/medata/data/merged_foodseg_foodrec2022")
    args = parser.parse_args(argv)

    foodseg = Path(args.foodseg)
    foodrec = Path(args.foodrec)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    stems: Dict[str, Dict[str, List[str]]] = {}
    print("[merge] linking FoodSeg103 v2 splits …")
    fs = {split: link_foodseg_split(foodseg / split, out / split)
          for split in ("train", "val", "heldout")}
    print("[merge] linking Food Recognition 2022 …")
    fr_train = link_foodrec_split(
        foodrec / "raw_data/public_training_set_release_2.0/images",
        foodrec / "masks_v2/train", out / "train")
    fr_val = link_foodrec_split(
        foodrec / "raw_data/public_validation_set_2.0/images",
        foodrec / "masks_v2/validation", out / "val")
    stems = {
        "train": fs["train"] + fr_train,
        "val": fs["val"] + fr_val,
        "heldout": fs["heldout"],
    }

    # Leak-free anchor invariants: byte-digest recorded; no anchor stem in
    # merged train/val.
    anchor = Path(args.anchor)
    anchor_stems = sorted(p.stem for p in (anchor / "images").iterdir())
    digest = hashlib.sha256()
    for p in sorted(anchor.rglob("*")):
        if p.is_file():
            digest.update(p.name.encode())
            digest.update(p.read_bytes())
    anchor_digest = digest.hexdigest()
    leaked = (set(anchor_stems) & set(stems["train"])) | \
             (set(anchor_stems) & set(stems["val"]))
    if leaked:
        raise SystemExit(f"leak-free anchor stems in merged train/val: "
                         f"{sorted(leaked)[:5]}")
    missing = set(anchor_stems) - set(stems["heldout"])
    if missing:
        raise SystemExit(f"anchor stems missing from merged heldout: "
                         f"{sorted(missing)[:5]}")
    print(f"[merge] anchor OK: {len(anchor_stems)} stems all in heldout, "
          f"none in train/val; digest {anchor_digest[:12]}…")

    print("[merge] scanning merged masks for co-stats …")
    pixel_counts_by_split = {}
    train_presence = None
    for split in ("train", "val", "heldout"):
        counts, presence = scan_masks(out / split)
        pixel_counts_by_split[split] = counts
        if split == "train":
            train_presence = presence

    co_stats = build_co_stats(
        pixel_counts_by_split, train_presence, CHANNEL_COUNT,
        FOODSEG_SEED, sha256_file(Path(args.foodseg_mapping)), SPECIALS,
    )
    co_stats["class_mapping_sha256_foodrec2022"] = \
        sha256_file(Path(args.foodrec_mapping))
    (out / "co_stats.json").write_text(json.dumps(co_stats) + "\n")

    splits = {
        "sources": {
            "foodseg103": {"root": str(foodseg), "split_seed": FOODSEG_SEED,
                           "posture": "frozen stratified carve, verbatim"},
            "foodrec2022": {"root": str(foodrec),
                            "posture": "official splits: train->train, "
                                       "validation->val, nothing in heldout",
                            "prefix": FR22_PREFIX},
        },
        "channel_count": CHANNEL_COUNT,
        "counts": {k: len(v) for k, v in stems.items()},
        "anchor": {"path": str(anchor), "stems": len(anchor_stems),
                   "sha256": anchor_digest},
        "files": stems,
    }
    (out / "splits.json").write_text(json.dumps(splits) + "\n")
    print(f"[merge] done: train={len(stems['train'])} val={len(stems['val'])} "
          f"heldout={len(stems['heldout'])} -> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

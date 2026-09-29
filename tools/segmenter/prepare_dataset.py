#!/usr/bin/env python3
"""Remap FoodSeg103 masks to the 36-channel palette and cut splits (ml-training §3c).

This is step 3c of the segmenter training pipeline. It consumes the class-mapping
JSON produced by ``build_class_mapping.py`` (§3b) and applies it to every
FoodSeg103 PNG mask, remapping each source category-id pixel value to the medata
36-channel palette:

    channels 0-24  : the 25 solid food classes (ClassPalette.standard order)
    channels 25-32 : the 8 coarse liquid classes
    channel  33    : background
    channel  34    : unknown_food
    channel  35    : unsupported_liquid

Mapping entries with ``target_index: null`` (rule ``curated_drop``) are remapped
to background (channel 32) so dropped source classes never pollute a food class.

After remapping, the full image set is shuffled deterministically with a fixed
RNG seed and carved into held-out / val / train splits. The held-out split is the
"Held-out segmenter test set" of §1 and MUST stay reproducible across training
runs -- the seed and fractions are recorded in ``out/splits.json`` alongside the
exact file lists.

STRATIFIED CARVE (segmenter-foundation design §3.5, Req 2.6 — default ON,
``--no-stratify`` restores the plain seeded shuffle): before the shuffle, each
of the eight carb-priority staples is guaranteed held-out representation.
Pass 1 computes staple presence by applying the class-mapping LUT to the RAW
masks in memory (remapping to files happens after the carve, in
``write_split``). Pass 2 iterates the staples in palette-index order and
assigns images to held-out until each staple's quota is met, where

    quota = min(max(3, ceil(heldout_frac * n)), floor(n / 3))

for a staple appearing in ``n`` images (design §3.5 states the formula with
0.12, the default ``--heldout-frac``). The ``floor(n/3)`` cap keeps a training
majority for thin staples; an image already assigned to held-out counts toward
every staple quota it contains. Infeasibility (n < 3): held-out gets exactly 1
image and a warning lands in the ``stratification`` block of ``splits.json``.
The remainder is shuffled and sliced as before (held-out topped up to
``heldout_frac``, then val, then train).

CO-OCCURRENCE STATISTICS (segmenter-foundation design §4.3, Decisions 15 and
20): the remap pass also writes ``out/co_stats.json`` — per-class pixel counts
per split (all 35 channels, descriptive) plus image-level presence and
joint-presence counts over the TRAINING split only, restricted to the 32 FOOD
channels (Decision 20: background is in every image, so counting it would hand
every false presence a compatibility floor near its marginal frequency). The
file is stamped with the split seed and the class-mapping file's SHA-256 so
``train.py`` can fail fast on stale statistics; its own SHA-256 is recorded in
build lineage by ``train.py`` when the co-occurrence loss consumes it.

Usage::

    python tools/segmenter/prepare_dataset.py \\
        --src data/foodseg103 \\
        --mapping tools/segmenter/class_mapping_foodseg103.json \\
        --out data/foodseg103_remapped \\
        --heldout-frac 0.12 --val-frac 0.1 --seed 1234

Heavy deps (numpy, pillow) are imported lazily so the module imports -- and
``--help`` works -- without them installed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
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


# Pure stdlib sibling: the carb-priority staple names (single source of truth,
# shared with the validation gate). Imported via sys.path like train.py does
# with loss_config so the script runs standalone from any cwd.
_TOOLS_DIR = str(Path(__file__).resolve().parent)
if _TOOLS_DIR not in sys.path:
    sys.path.insert(0, _TOOLS_DIR)
from validation import CARB_PRIORITY_CLASSES  # noqa: E402

# FoodSeg103 ships its background as category id 0; the mapping JSON already
# routes id 0 -> channel 32 (background), so no special-casing is needed here.
# Dropped classes (target_index null) fall back to this channel too.
BACKGROUND_CHANNEL = 32

IMAGE_EXTS = (".jpg", ".jpeg", ".png")

# Minimum held-out images per staple when the staple has >= 3 images at all
# (design §3.5); below that the infeasibility rule applies (held-out gets 1).
_STAPLE_MIN_QUOTA = 3


def load_mapping(path: Path) -> dict:
    """Load and lightly validate the §3b class-mapping JSON."""
    mapping = json.loads(path.read_text(encoding="utf-8"))
    if "mappings" not in mapping or "channel_count" not in mapping:
        raise SystemExit(
            f"{path} does not look like a build_class_mapping.py output "
            "(missing 'mappings'/'channel_count')."
        )
    return mapping


def file_sha256(path: Path) -> str:
    """Streaming SHA-256 of a file (stamped into co_stats.json for fail-fast)."""
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def staple_channels(mapping: dict) -> List[Tuple[str, int]]:
    """The eight carb-priority staples as (name, palette index), in
    palette-index order — the iteration order of the stratified carve
    (design §3.5)."""
    by_name = {c["name"]: int(c["index"]) for c in mapping["target_channels"]}
    missing = [n for n in CARB_PRIORITY_CLASSES if n not in by_name]
    if missing:
        raise SystemExit(
            f"class mapping lacks carb-priority channels: {', '.join(missing)}"
        )
    ordered = sorted(
        ((name, by_name[name]) for name in CARB_PRIORITY_CLASSES),
        key=lambda item: item[1],
    )
    # Ordering belt: carve_splits iterates CARB_PRIORITY_CLASSES directly and
    # claims palette-index order — if the palette ever reorders, fail loudly
    # here (staple_channels runs right before the carve) rather than letting
    # the two orders silently diverge.
    if tuple(name for name, _ in ordered) != CARB_PRIORITY_CLASSES:
        raise SystemExit(
            "CARB_PRIORITY_CLASSES is not in palette-index order for this "
            "mapping; the stratified carve iterates that constant directly "
            "(design §3.5) — re-order it to match the palette."
        )
    return ordered


def compute_staple_presence(
    pairs: List[Tuple[Path, Path]],
    lut,
    staples: List[Tuple[str, int]],
) -> Dict[str, frozenset]:
    """Pass 1 of the stratified carve: staple presence per image, from the RAW
    masks. ``carve_splits`` runs before ``write_split`` remaps to disk, so the
    class-mapping LUT is applied to each raw mask's unique pixel values in
    memory — no remapped masks exist at carve time (design §3.5)."""
    np = _import_numpy()
    Image = _import_pillow()
    index_to_name = {idx: name for name, idx in staples}
    presence: Dict[str, frozenset] = {}
    for _, mask_path in pairs:
        arr = np.asarray(Image.open(mask_path))
        if arr.ndim == 3:
            arr = arr[..., 0]
        ids = np.unique(arr).astype(np.int64)
        if int(ids.max(initial=0)) >= lut.shape[0]:
            raise SystemExit(
                f"{mask_path}: pixel id {int(ids.max())} exceeds mapping range "
                f"(LUT covers 0..{lut.shape[0] - 1}). Wrong mapping file?"
            )
        channels = set(int(c) for c in lut[ids])
        presence[mask_path.stem] = frozenset(
            index_to_name[c] for c in channels if c in index_to_name
        )
    return presence


def staple_quota(n: int, heldout_frac: float) -> int:
    """Held-out quota for a staple appearing in ``n`` images (design §3.5):
    min(max(3, ceil(heldout_frac * n)), floor(n / 3)). The design states the
    formula with 0.12 — the default held-out fraction. Callers handle the
    infeasibility rule (n < 3 → quota would be 0 → held-out gets 1 + warning).
    """
    return min(max(_STAPLE_MIN_QUOTA, math.ceil(heldout_frac * n)), n // 3)


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


def remap_mask(mask_path: Path, lut, out_path: Path):
    """Apply the LUT to a single-channel mask and write a uint8 PNG.

    Returns the remapped array so ``write_split`` can accumulate the
    co-occurrence statistics (design §4.3) in the same pass — no re-read.
    """
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
    return remapped


def carve_splits(
    pairs: List[Tuple[Path, Path]],
    heldout_frac: float,
    val_frac: float,
    seed: int,
    staple_presence: Optional[Dict[str, frozenset]] = None,
) -> Tuple[Dict[str, List[Tuple[Path, Path]]], Optional[dict]]:
    """Deterministically carve pairs into heldout / val / train.

    Without ``staple_presence`` this is the original seeded shuffle-and-slice:
    held-out first, then val, then the remainder is train (slicing this way
    keeps the held-out set stable even if val_frac changes between runs), and
    the returned stratification block is ``None``.

    With ``staple_presence`` (stem -> set of staple names, from
    ``compute_staple_presence``) the carve is STRATIFIED per design §3.5: the
    staples are visited in palette-index order (``CARB_PRIORITY_CLASSES`` is
    already palette order) and images containing each staple are assigned to
    held-out — seeded, deterministic — until its ``staple_quota`` is met. An
    image already in held-out counts toward every staple quota it contains. A
    staple with fewer than 3 images gets exactly 1 held-out image plus a
    warning (infeasibility rule); a staple with 0 images gets a warning only.
    The remainder is then shuffled and sliced as before, topping held-out up
    to ``heldout_frac`` of the total. Returns ``(splits, stratification)``
    where the stratification block carries per-staple heldout/train counts,
    quotas, and warnings for ``splits.json``.
    """
    if heldout_frac < 0 or val_frac < 0 or heldout_frac + val_frac >= 1:
        raise SystemExit(
            f"invalid fractions: heldout={heldout_frac} val={val_frac} "
            "(each >= 0 and their sum < 1)"
        )
    ordered = sorted(pairs, key=lambda p: p[1].stem)  # stable base order
    rng = random.Random(seed)
    n = len(ordered)
    n_heldout = int(n * heldout_frac)
    n_val = int(n * val_frac)

    if staple_presence is None:
        rng.shuffle(ordered)
        heldout = ordered[:n_heldout]
        val = ordered[n_heldout:n_heldout + n_val]
        train = ordered[n_heldout + n_val:]
        return {"train": train, "val": val, "heldout": heldout}, None

    # ── Pass 2 (pass 1 was compute_staple_presence): stratified assignment ──
    heldout: List[Tuple[Path, Path]] = []
    heldout_stems: set = set()
    warnings: List[str] = []
    quotas: Dict[str, int] = {}

    def _staples_of(pair: Tuple[Path, Path]) -> frozenset:
        return staple_presence.get(pair[1].stem, frozenset())

    # Palette-index order (indices 0–7) — asserted by staple_channels() before
    # the carve runs, so the constant cannot silently diverge from the palette.
    for name in CARB_PRIORITY_CLASSES:
        members = [p for p in ordered if name in _staples_of(p)]
        n_s = len(members)
        if n_s == 0:
            quotas[name] = 0
            warnings.append(
                f"staple '{name}' has no images in the dataset; "
                "held-out representation impossible"
            )
            continue
        if n_s < 3:
            quota = 1  # infeasibility rule: floor(n/3) < 1 → held-out gets 1
            warnings.append(
                f"staple '{name}' has only {n_s} image(s); held-out gets 1 — "
                "floor and learnability are judged on what exists (design §3.5)"
            )
        else:
            quota = staple_quota(n_s, heldout_frac)
        quotas[name] = quota
        have = sum(1 for p in members if p[1].stem in heldout_stems)
        if have >= quota:
            continue
        candidates = [p for p in members if p[1].stem not in heldout_stems]
        rng.shuffle(candidates)
        for pair in candidates[:quota - have]:
            heldout.append(pair)
            heldout_stems.add(pair[1].stem)

    # Remainder: shuffled and sliced as before; held-out topped up to its
    # fraction of the WHOLE set (stratified picks count toward it).
    remainder = [p for p in ordered if p[1].stem not in heldout_stems]
    rng.shuffle(remainder)
    top_up = max(0, n_heldout - len(heldout))
    heldout = heldout + remainder[:top_up]
    val = remainder[top_up:top_up + n_val]
    train = remainder[top_up + n_val:]

    heldout_stems.update(p[1].stem for p in remainder[:top_up])
    train_stems = {p[1].stem for p in train}
    stratification = {
        "staples": {
            name: {
                "quota": quotas[name],
                "heldout": sum(
                    1 for stem, staples in staple_presence.items()
                    if name in staples and stem in heldout_stems
                ),
                "train": sum(
                    1 for stem, staples in staple_presence.items()
                    if name in staples and stem in train_stems
                ),
            }
            for name in CARB_PRIORITY_CLASSES
        },
        "warnings": warnings,
    }
    return {"train": train, "val": val, "heldout": heldout}, stratification


def write_split(
    name: str,
    pairs: List[Tuple[Path, Path]],
    out: Path,
    lut,
    channel_count: int,
) -> Tuple[List[str], List[int], List[frozenset]]:
    """Copy images and write remapped masks for one split.

    Returns ``(stems, pixel_counts, presence)`` where ``pixel_counts`` is the
    split's per-class pixel total over the REMAPPED masks and ``presence`` is
    the per-image set of present classes — the raw material for
    ``build_co_stats`` (design §4.3), accumulated in the remap pass itself.
    """
    np = _import_numpy()
    img_out = out / name / "images"
    mask_out = out / name / "masks"
    img_out.mkdir(parents=True, exist_ok=True)
    mask_out.mkdir(parents=True, exist_ok=True)

    stems: List[str] = []
    pixel_counts = np.zeros(channel_count, dtype=np.int64)
    presence: List[frozenset] = []
    for img, mask in pairs:
        stem = mask.stem
        shutil.copy2(img, img_out / img.name)
        remapped = remap_mask(mask, lut, mask_out / f"{stem}.png")
        counts = np.bincount(remapped.ravel(), minlength=channel_count)
        pixel_counts += counts
        presence.append(frozenset(int(c) for c in np.nonzero(counts)[0]))
        stems.append(stem)
    return stems, pixel_counts.tolist(), presence


def build_co_stats(
    pixel_counts_by_split: Dict[str, List[int]],
    train_presence: List[frozenset],
    channel_count: int,
    split_seed: int,
    class_mapping_sha256: str,
    special_channel_indices: List[int],
) -> dict:
    """Assemble ``co_stats.json`` (design §4.3, Decisions 15 and 20).

    Per-class pixel counts per split are recorded for ALL channels — they are
    descriptive (``train.py`` derives its class weights from its own mask
    scan). The image-level presence and joint-presence counts over the
    TRAINING split — the co-occurrence matrix for the loss — cover the FOOD
    channels only (Decision 20): background is in every image, so counting it
    would give any class's false presence a compatibility floor near its
    marginal frequency and dilute the implausible-pair contrast the loss
    exists to create. The special channels' rows/columns stay in the matrix as
    zeros so indices remain palette indices. Schema ``co_stats``; the split
    seed and class-mapping SHA-256 are stamped in so ``train.py`` can fail
    fast when the statistics are missing, stale, or in a superseded
    pre-release format; the file's own SHA-256 joins the build lineage when the loss
    consumes it.
    """
    specials = {int(c) for c in special_channel_indices}
    presence_counts = [0] * channel_count
    joint = [[0] * channel_count for _ in range(channel_count)]
    for present in train_presence:
        classes = sorted(c for c in present if c not in specials)
        for c in classes:
            presence_counts[c] += 1
            for k in classes:
                joint[c][k] += 1
    return {
        "schema": "co_stats",
        "split_seed": split_seed,
        "class_mapping_sha256": class_mapping_sha256,
        "channel_count": channel_count,
        "special_channel_indices": sorted(specials),
        "train_images": len(train_presence),
        "pixel_counts": pixel_counts_by_split,
        "presence_counts": presence_counts,
        "joint_presence_counts": joint,
    }


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--src", required=True,
                        help="FoodSeg103 root (contains Images/img_dir + ann_dir).")
    parser.add_argument("--mapping", required=True,
                        help="class_mapping_foodseg103.json from §3b.")
    parser.add_argument("--out", required=True,
                        help="Output root for remapped masks + splits.")
    parser.add_argument("--heldout-frac", type=float, default=0.12,
                        help="Fraction of all images for the held-out test set.")
    parser.add_argument("--val-frac", type=float, default=0.1,
                        help="Fraction of all images for the validation set.")
    parser.add_argument("--seed", type=int, default=1234,
                        help="RNG seed; fixes the held-out split across runs.")
    parser.add_argument("--no-stratify", action="store_true",
                        help="Disable the stratified held-out carve (design "
                             "§3.5) and use the plain seeded shuffle. "
                             "Stratification is ON by default: every "
                             "carb-priority staple is guaranteed held-out "
                             "representation (Req 2.6).")
    args = parser.parse_args(argv)

    src = Path(args.src)
    out = Path(args.out)
    mapping_path = Path(args.mapping)
    mapping = load_mapping(mapping_path)
    lut = build_lut(mapping)
    channel_count = int(mapping["channel_count"])

    pairs = discover_pairs(src)
    if not pairs:
        raise SystemExit(
            f"no (image, mask) pairs found under {src}. Expected "
            "Images/img_dir/{train,test}/*.jpg + Images/ann_dir/{train,test}/*.png "
            "or matching image/mask basenames."
        )

    staple_presence = None
    if not args.no_stratify:
        staples = staple_channels(mapping)
        staple_presence = compute_staple_presence(pairs, lut, staples)
    splits, stratification = carve_splits(
        pairs, args.heldout_frac, args.val_frac, args.seed, staple_presence
    )

    out.mkdir(parents=True, exist_ok=True)
    split_stems: Dict[str, List[str]] = {}
    pixel_counts_by_split: Dict[str, List[int]] = {}
    train_presence: List[frozenset] = []
    for name, split_pairs in splits.items():
        stems, pixel_counts, presence = write_split(
            name, split_pairs, out, lut, channel_count
        )
        split_stems[name] = stems
        pixel_counts_by_split[name] = pixel_counts
        if name == "train":
            train_presence = presence

    manifest = {
        "source": str(src),
        "mapping": str(mapping_path),
        "channel_count": channel_count,
        "seed": args.seed,
        "heldout_frac": args.heldout_frac,
        "val_frac": args.val_frac,
        "total": len(pairs),
        "counts": {name: len(stems) for name, stems in split_stems.items()},
        "files": split_stems,
    }
    if stratification is not None:
        manifest["stratification"] = stratification
        for warning in stratification["warnings"]:
            print(f"[prepare_dataset] WARNING: {warning}", file=sys.stderr)
    (out / "splits.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )

    co_stats = build_co_stats(
        pixel_counts_by_split, train_presence, channel_count,
        args.seed, file_sha256(mapping_path),
        special_channel_indices=list(mapping["special_channels"].values()),
    )
    (out / "co_stats.json").write_text(
        json.dumps(co_stats, indent=2) + "\n", encoding="utf-8"
    )

    print(
        f"[prepare_dataset] {len(pairs)} pairs -> "
        f"train={manifest['counts']['train']} "
        f"val={manifest['counts']['val']} "
        f"heldout={manifest['counts']['heldout']} "
        f"(seed={args.seed}, stratify={'off' if args.no_stratify else 'on'}); "
        f"wrote {out}/splits.json + {out}/co_stats.json"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

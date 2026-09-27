#!/usr/bin/env python3
"""Class-agnostic mask metrics shared by the three methods in this spike.

Everything is scored in one "scoring space": the anchor image resized so its
longer side is SCORE_SIZE (513, the segmenter's working resolution), aspect
preserved. deeplab's letterboxed argmax is exactly this canvas (top-left crop,
no resampling); EdgeTAM and Vision masks are nearest-resized into it. The
2-pixel boundary tolerance therefore means the same thing for every method.

GT food = every palette label except background (33), so unknown_food (34)
and unsupported_liquid (35) count as food: they are regions the segmenter is
asked to delineate, whatever the label.

Metrics:
  food_iou     union food vs background, per image.
  region_iou   GT regions are 8-connected components of the GT LABEL map (so two
               touching foods of different classes are two regions). Each GT
               region is matched to the predicted binary-mask component with
               the largest intersection; IoU of that pair (0 if none).
  boundary_f   Perazzi/DAVIS boundary F with a 2 px tolerance on the binary
               food mask.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps
from scipy import ndimage

REPO = Path(__file__).resolve().parents[3]
ANCHOR = REPO / "data/foodseg103_remapped_v2/heldout_leakfree"
OUT = Path(__file__).resolve().parent / "out"
BACKGROUND = 33
SCORE_SIZE = 513
BOUNDARY_TOL = 2
MIN_REGION_PX = 64  # GT components smaller than this (in scoring space) are ignored
EIGHT = np.ones((3, 3), dtype=bool)


def stems() -> list[str]:
    return sorted(p.stem for p in (ANCHOR / "images").iterdir() if p.suffix.lower() in {".jpg", ".png", ".jpeg"})


def image_path(stem: str) -> Path:
    for ext in (".jpg", ".png", ".jpeg"):
        p = ANCHOR / "images" / f"{stem}{ext}"
        if p.is_file():
            return p
    raise FileNotFoundError(stem)


def load_image(stem: str) -> Image.Image:
    """RGB, EXIF-rotated (masks match the rotated pixels — train.py does the same)."""
    return ImageOps.exif_transpose(Image.open(image_path(stem))).convert("RGB")


def score_shape(w: int, h: int) -> tuple[int, int]:
    """(sw, sh) of the scoring canvas for a native (w, h) image."""
    s = SCORE_SIZE / max(w, h)
    return max(1, min(SCORE_SIZE, round(w * s))), max(1, min(SCORE_SIZE, round(h * s)))


def load_gt_labels(stem: str) -> np.ndarray:
    """GT label map nearest-resized into scoring space, uint8 [sh, sw]."""
    m = Image.open(ANCHOR / "masks" / f"{stem}.png")
    sw, sh = score_shape(*m.size)
    return np.asarray(m.resize((sw, sh), Image.NEAREST), dtype=np.uint8)


def to_score_space(mask: np.ndarray, sw: int, sh: int) -> np.ndarray:
    """Nearest-resize a native-resolution bool mask into the scoring canvas."""
    if mask.shape == (sh, sw):
        return mask.astype(bool)
    return np.asarray(Image.fromarray(mask.astype(np.uint8) * 255).resize((sw, sh), Image.NEAREST)) > 127


def save_mask(mask: np.ndarray, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(mask.astype(np.uint8) * 255).save(path)


def load_mask(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("L")) > 127


def gt_regions(labels: np.ndarray) -> list[tuple[int, np.ndarray]]:
    """[(class_id, bool mask)] for every GT food component of >= MIN_REGION_PX."""
    regions = []
    for cls in np.unique(labels):
        if cls == BACKGROUND:
            continue
        comp, n = ndimage.label(labels == cls, structure=EIGHT)
        for i in range(1, n + 1):
            r = comp == i
            if r.sum() >= MIN_REGION_PX:
                regions.append((int(cls), r))
    return regions


def components(mask: np.ndarray, min_px: int = 0) -> list[np.ndarray]:
    comp, n = ndimage.label(mask, structure=EIGHT)
    out = [comp == i for i in range(1, n + 1)]
    return [c for c in out if c.sum() >= min_px]


def iou(a: np.ndarray, b: np.ndarray) -> float:
    union = (a | b).sum()
    return float((a & b).sum() / union) if union else 1.0


def boundary(mask: np.ndarray) -> np.ndarray:
    return mask & ~ndimage.binary_erosion(mask, structure=EIGHT, border_value=0)


def boundary_f(pred: np.ndarray, gt: np.ndarray, tol: int = BOUNDARY_TOL) -> float:
    pb, gb = boundary(pred), boundary(gt)
    if pb.sum() == 0 and gb.sum() == 0:
        return 1.0
    if pb.sum() == 0 or gb.sum() == 0:
        return 0.0
    gd = ndimage.binary_dilation(gb, structure=EIGHT, iterations=tol)
    pd = ndimage.binary_dilation(pb, structure=EIGHT, iterations=tol)
    precision = (pb & gd).sum() / pb.sum()
    recall = (gb & pd).sum() / gb.sum()
    return float(2 * precision * recall / (precision + recall)) if precision + recall else 0.0


def region_ious(pred: np.ndarray, regions: list[tuple[int, np.ndarray]],
                comps: list[np.ndarray] | None = None) -> list[float]:
    """Best-overlap component IoU for each GT region. ``comps`` overrides the
    predicted components (default: 8-connected components of ``pred``)."""
    if comps is None:
        comps = components(pred)
    out = []
    for _, r in regions:
        best, best_inter = 0.0, 0
        for c in comps:
            inter = (r & c).sum()
            if inter > best_inter:
                best_inter, best = inter, iou(r, c)
        out.append(best)
    return out


def score_image(pred: np.ndarray, labels: np.ndarray) -> dict:
    gt = labels != BACKGROUND
    regions = gt_regions(labels)
    return {
        "food_iou": iou(pred, gt),
        "boundary_f": boundary_f(pred, gt),
        "region_ious": region_ious(pred, regions),
    }


def score_method(mask_dir: Path) -> dict:
    """Score every <stem>.png under mask_dir; returns per-image and mean metrics."""
    per_image = {}
    for stem in stems():
        pred = load_mask(mask_dir / f"{stem}.png")
        per_image[stem] = score_image(pred, load_gt_labels(stem))
    return {"per_image": per_image, "mean": summarise(per_image)}


def summarise(per_image: dict) -> dict:
    regions = [v for s in per_image.values() for v in s["region_ious"]]
    return {
        "images": len(per_image),
        "food_iou": float(np.mean([s["food_iou"] for s in per_image.values()])),
        "boundary_f": float(np.mean([s["boundary_f"] for s in per_image.values()])),
        "region_iou": float(np.mean(regions)),
        "regions": len(regions),
    }


def write_json(obj, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=1))


if __name__ == "__main__":
    import sys

    for d in sys.argv[1:]:
        print(d, json.dumps(score_method(Path(d))["mean"]))

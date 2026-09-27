#!/usr/bin/env python3
"""Class-agnostic mask-quality metrics (MD-29, segmenter-foundation Decision 37).

MD-29 re-scoped the segmenter from "predict the right class" to "produce clean,
coherent food masks with a good ranked shortlist", because the user fixes a wrong
class with a tap and cannot fix a wrong region. These are the numbers that
measure that, first computed by the EdgeTAM spike
(``tools/segmenter/spike_masks/RESULTS.md``) and recorded by every validation
run since (``run_validation.py`` → lineage ``metrics.mask_quality``).

Every metric takes label maps in one scoring space: the image resized so its
longer side is the segmenter's working resolution (513), aspect preserved, with
NO letterbox padding (``content_shape``). A 2 px boundary tolerance then means
the same thing on every image.

``non_food`` is the set of class indices that are NOT food regions. The
validation run passes the palette's special channels (background 33,
unknown_food 34, unsupported_liquid 35); the spike passed background only.

  food_iou       IoU of the binary food mask (label not in ``non_food``), pred vs GT.
  region_iou     GT regions are 8-connected components of the GT label map per
                 class (touching foods of different classes are two regions),
                 ≥ MIN_REGION_PX. Each is matched to the predicted label-map
                 component with the largest intersection; IoU of that pair, 0
                 when nothing overlaps. Mean over regions, not images.
  boundary_f     Perazzi/DAVIS boundary F on the binary food mask, 2 px tolerance.
  shortlist_hit  Softmax mean-pooled inside each GT region, ranked over the food
                 classes; hit when the region's true class is in the top 3.

Pure numpy (no torch, no scipy) so it imports under the torch-free test suite
and inside the training venv alike. The 8-connected labelling is a vectorised
hook-and-compress union-find; the morphology is 3x3 shifts.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Iterable, Mapping, Sequence

import numpy as np

BACKGROUND = 33
SCORE_SIZE = 513
BOUNDARY_TOL = 2
MIN_REGION_PX = 64  # GT components smaller than this (in scoring space) are ignored
TOP_K = 3

_OFFSETS_8 = tuple((dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if (dy, dx) != (0, 0))
# Forward half of the 8-neighbourhood: every unordered adjacent pair once.
_FORWARD_4 = ((0, 1), (1, -1), (1, 0), (1, 1))


# ── scoring space ───────────────────────────────────────────────────────────────

def content_shape(w: int, h: int, target: int = SCORE_SIZE) -> tuple[int, int]:
    """(sw, sh) the segmenter's letterbox gives a native (w, h) image: longer side
    to ``target``, aspect preserved, same rounding as train.py's val path."""
    s = target / max(w, h)
    return max(1, min(target, round(w * s))), max(1, min(target, round(h * s)))


# ── binary morphology ───────────────────────────────────────────────────────────

def _shifted(mask: np.ndarray, dy: int, dx: int) -> np.ndarray:
    """``mask`` moved by (dy, dx) with False filled in (scipy border_value=0)."""
    h, w = mask.shape
    out = np.zeros_like(mask, dtype=bool)
    ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
    xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
    out[yd, xd] = mask[ys, xs]
    return out


def erode(mask: np.ndarray) -> np.ndarray:
    """3x3 binary erosion; pixels on the image edge erode (border is False)."""
    out = np.asarray(mask, dtype=bool).copy()
    for dy, dx in _OFFSETS_8:
        out &= _shifted(mask, dy, dx)
    return out


def dilate(mask: np.ndarray, iterations: int = 1) -> np.ndarray:
    """3x3 binary dilation, repeated ``iterations`` times."""
    out = np.asarray(mask, dtype=bool)
    for _ in range(iterations):
        grown = out.copy()
        for dy, dx in _OFFSETS_8:
            grown |= _shifted(out, dy, dx)
        out = grown
    return out


def boundary(mask: np.ndarray) -> np.ndarray:
    mask = np.asarray(mask, dtype=bool)
    return mask & ~erode(mask)


# ── connected components (8-connected, pure numpy) ──────────────────────────────

def label_components(mask: np.ndarray) -> tuple[np.ndarray, int]:
    """8-connected components of a bool mask → (labels int32 [H, W], count).

    Labels are 1..count in raster order of each component's first pixel (the
    order ``scipy.ndimage.label`` gives); 0 is background.
    """
    mask = np.asarray(mask, dtype=bool)
    h, w = mask.shape
    lab = np.zeros((h, w), dtype=np.int32)
    n = int(mask.sum())
    if n == 0:
        return lab, 0

    idx = np.full((h, w), -1, dtype=np.int64)
    idx[mask] = np.arange(n)
    edges_a, edges_b = [], []
    for dy, dx in _FORWARD_4:
        src = idx[0:h - dy, max(0, -dx):w - max(0, dx)]
        dst = idx[dy:h, max(0, dx):w - max(0, -dx)]
        both = (src >= 0) & (dst >= 0)
        edges_a.append(src[both])
        edges_b.append(dst[both])
    a = np.concatenate(edges_a)
    b = np.concatenate(edges_b)

    parent = np.arange(n)
    while True:
        # Full pointer jumping: parent[i] becomes the root of i.
        while True:
            grand = parent[parent]
            if np.array_equal(grand, parent):
                break
            parent = grand
        ra, rb = parent[a], parent[b]
        differ = ra != rb
        if not differ.any():
            break
        lo = np.minimum(ra, rb)[differ]
        hi = np.maximum(ra, rb)[differ]
        np.minimum.at(parent, hi, lo)  # hook the larger root under the smaller

    roots, inverse = np.unique(parent, return_inverse=True)
    lab[mask] = inverse.astype(np.int32) + 1
    return lab, int(len(roots))


def components(mask: np.ndarray, min_px: int = 0) -> list[np.ndarray]:
    """List of bool masks, one per 8-connected component of ``mask`` ≥ ``min_px``."""
    lab, n = label_components(mask)
    out = [lab == i for i in range(1, n + 1)]
    return [c for c in out if c.sum() >= min_px]


def _labels_to_components(masks: Sequence[np.ndarray], shape: tuple[int, int]) -> np.ndarray:
    """Stack non-overlapping bool masks into one int32 label map (1-based)."""
    lab = np.zeros(shape, dtype=np.int32)
    for i, m in enumerate(masks, start=1):
        lab[np.asarray(m, dtype=bool)] = i
    return lab


def region_labels(labels: np.ndarray, non_food: Iterable[int] = (BACKGROUND,),
                  min_px: int = MIN_REGION_PX) -> tuple[np.ndarray, np.ndarray]:
    """GT regions of a label map → (region map int32 [H, W], class per region).

    One region per 8-connected component of each food class (label not in
    ``non_food``) with ≥ ``min_px`` pixels; regions are numbered 1..G in class
    order then raster order. Pass ``min_px=0`` for the predicted label map's
    components (nothing is dropped from a prediction).
    """
    labels = np.asarray(labels)
    excluded = set(int(c) for c in non_food)
    region = np.zeros(labels.shape, dtype=np.int32)
    classes: list[int] = []
    for cls in np.unique(labels):
        if int(cls) in excluded:
            continue
        lab, n = label_components(labels == cls)
        if n == 0:
            continue
        sizes = np.bincount(lab.ravel(), minlength=n + 1)
        for i in range(1, n + 1):
            if sizes[i] >= min_px:
                classes.append(int(cls))
                region[lab == i] = len(classes)
    return region, np.asarray(classes, dtype=np.int64)


def gt_regions(labels: np.ndarray, non_food: Iterable[int] = (BACKGROUND,),
               min_px: int = MIN_REGION_PX) -> list[tuple[int, np.ndarray]]:
    """``region_labels`` as [(class_id, bool mask)] — the spike's list form."""
    region, classes = region_labels(labels, non_food, min_px)
    return [(int(c), region == i) for i, c in enumerate(classes, start=1)]


# ── metrics ─────────────────────────────────────────────────────────────────────

def iou(a: np.ndarray, b: np.ndarray) -> float:
    a = np.asarray(a, dtype=bool)
    b = np.asarray(b, dtype=bool)
    union = (a | b).sum()
    return float((a & b).sum() / union) if union else 1.0


def boundary_f(pred: np.ndarray, gt: np.ndarray, tol: int = BOUNDARY_TOL) -> float:
    """DAVIS boundary F: precision = predicted boundary pixels within ``tol`` of
    the GT boundary, recall the converse, F their harmonic mean."""
    pb, gb = boundary(pred), boundary(gt)
    if pb.sum() == 0 and gb.sum() == 0:
        return 1.0
    if pb.sum() == 0 or gb.sum() == 0:
        return 0.0
    precision = (pb & dilate(gb, tol)).sum() / pb.sum()
    recall = (gb & dilate(pb, tol)).sum() / gb.sum()
    return float(2 * precision * recall / (precision + recall)) if precision + recall else 0.0


def matched_region_ious(region: np.ndarray, pred_components: np.ndarray) -> np.ndarray:
    """For each GT region (1..G in ``region``) the IoU against the predicted
    component (1..P in ``pred_components``) with the largest intersection; 0 when
    no component touches it. Both inputs are int label maps with 0 = none."""
    g_count = int(region.max())
    p_count = int(pred_components.max())
    if g_count == 0:
        return np.zeros(0, dtype=np.float64)
    if p_count == 0:
        return np.zeros(g_count, dtype=np.float64)
    pair = region.astype(np.int64) * (p_count + 1) + pred_components.astype(np.int64)
    inter = np.bincount(pair.ravel(), minlength=(g_count + 1) * (p_count + 1))
    inter = inter.reshape(g_count + 1, p_count + 1)
    g_size = inter.sum(axis=1)
    p_size = inter.sum(axis=0)
    out = np.zeros(g_count, dtype=np.float64)
    for g in range(1, g_count + 1):
        row = inter[g, 1:]
        best = int(row.argmax()) + 1
        if row[best - 1] == 0:
            continue
        out[g - 1] = inter[g, best] / (g_size[g] + p_size[best] - inter[g, best])
    return out


def region_ious(pred: np.ndarray | None, regions: Sequence[tuple[int, np.ndarray]],
                comps: Sequence[np.ndarray] | None = None) -> list[float]:
    """Spike-style entry point over lists: ``regions`` from ``gt_regions``,
    predicted components either ``comps`` (non-overlapping bool masks) or the
    8-connected components of the binary mask ``pred``."""
    if not regions:
        return []
    shape = regions[0][1].shape
    region = _labels_to_components([r for _, r in regions], shape)
    if comps is None:
        pred_lab, _ = label_components(np.asarray(pred, dtype=bool))
    else:
        pred_lab = _labels_to_components(comps, shape)
    return matched_region_ious(region, pred_lab).tolist()


def shortlist_hits(probs: np.ndarray, region: np.ndarray, region_classes: np.ndarray,
                   non_food: Iterable[int] = (BACKGROUND,), k: int = TOP_K) -> np.ndarray:
    """Per GT region: is its true class in the top-``k`` of the softmax mean-pooled
    over the region, ranking food classes only? ``probs`` is [C, H, W]."""
    g_count = len(region_classes)
    if g_count == 0:
        return np.zeros(0, dtype=bool)
    flat = region.ravel()
    pooled = np.stack(
        [np.bincount(flat, weights=probs[c].ravel(), minlength=g_count + 1)[1:]
         for c in range(probs.shape[0])], axis=1)  # [G, C] sums; ranking ignores the mean's divisor
    pooled[:, [int(c) for c in non_food]] = -np.inf
    top = np.argsort(-pooled, axis=1, kind="stable")[:, :k]
    return (top == np.asarray(region_classes)[:, None]).any(axis=1)


def score_image(gt_labels: np.ndarray, pred_labels: np.ndarray,
                probs: np.ndarray | None = None,
                non_food: Iterable[int] = (BACKGROUND,)) -> dict[str, Any]:
    """All metrics for one image in scoring space. ``probs`` ([C, H, W] softmax)
    is optional; without it there is no shortlist reading."""
    non_food = tuple(int(c) for c in non_food)
    gt_labels = np.asarray(gt_labels)
    pred_labels = np.asarray(pred_labels)
    gt_food = ~np.isin(gt_labels, non_food)
    pred_food = ~np.isin(pred_labels, non_food)
    region, classes = region_labels(gt_labels, non_food)
    pred_components, _ = region_labels(pred_labels, non_food, min_px=0)
    out = {
        "food_iou": iou(pred_food, gt_food),
        "boundary_f": boundary_f(pred_food, gt_food),
        "region_ious": matched_region_ious(region, pred_components).tolist(),
    }
    if probs is not None:
        out["shortlist_hits"] = shortlist_hits(probs, region, classes, non_food).tolist()
    return out


def summarise(per_image: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    """Means over images (food_iou, boundary_f2) and over regions (region_iou,
    shortlist_top3_hit); the lineage ``mask_quality`` block minus ``scored_at``."""
    scores = list(per_image)
    regions = [v for s in scores for v in s["region_ious"]]
    hits = [v for s in scores for v in s.get("shortlist_hits", [])]
    return {
        "food_iou": float(np.mean([s["food_iou"] for s in scores])) if scores else None,
        "region_iou": float(np.mean(regions)) if regions else None,
        "boundary_f2": float(np.mean([s["boundary_f"] for s in scores])) if scores else None,
        "shortlist_top3_hit": float(np.mean(hits)) if hits else None,
        "n_images": len(scores),
        "n_regions": len(regions),
    }


def lineage_block(per_image: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    """``summarise`` stamped with a UTC ``scored_at`` — what lineage records."""
    block = summarise(per_image)
    block["scored_at"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    return block

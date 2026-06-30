#!/usr/bin/env python3
"""Validation reporting + export-eligibility decision (model-production task 9).

The validation step (design §2.1 stage 4) computes mean food-class IoU, per-class
IoU, and the carb-priority-staple IoU subset on the held-out split, then decides
**export eligibility** and records the result — plus any shortfall — into
``build/lineage.json``'s ``metrics`` block (Req 3.2–3.6).

Export-eligibility rule (Req 3.2 / 3.5):

  mean food-class IoU >= 0.60  AND  every carb-priority staple IoU >= 0.50

A mean alone can hide a near-zero staple class that dominates the carb number
(Decision 6), so the carb-priority floor is checked per class. A staple that
cannot meet the floor is surfaced as a shortfall (Req 3.6: flag low-confidence or
map to ``unknown_food``) rather than blocking indefinitely.

This module is PURE DECISION LOGIC: it takes a ``per_class_iou`` mapping (the
output of the GPU validation run) and is independent of running the model. The
*running* of validation on real held-out data is gated on the training
prerequisite (stage 3); this is the code that computes, reports, and records.

Pure stdlib (no torch) so it imports and runs without the training deps.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Mapping

# Export-eligibility bars (Req 3.2 mean, Req 3.5 per-class carb-priority floor).
MEAN_IOU_BAR = 0.60
CARB_PRIORITY_IOU_BAR = 0.50

# High-carbohydrate staples that dominate the carb number; each must individually
# clear CARB_PRIORITY_IOU_BAR (Req 3.5). Names/order mirror ClassPalette.v1Standard
# indices 0–7 and the requirements list. Design may refine the set/floor against
# the first real training run.
CARB_PRIORITY_CLASSES: tuple[str, ...] = (
    "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
    "potato_boiled", "potato_mashed", "chips_fries",
)

_MAPPING_PATH = Path(__file__).resolve().with_name("class_mapping_foodseg103_v1.json")


def _mapping() -> dict[str, Any]:
    return json.loads(_MAPPING_PATH.read_text())


def special_channel_names() -> tuple[str, ...]:
    """The non-food channels (background, unknown_food, unsupported_liquid) — excluded
    from the food-class mean, mirroring train.food_class_miou's NON_FOOD_CLASSES."""
    return tuple(_mapping()["special_channels"].keys())


def food_class_names() -> tuple[str, ...]:
    """The 24 food-class names in palette/index order (specials removed)."""
    specials = set(special_channel_names())
    channels = sorted(_mapping()["target_channels"], key=lambda c: c["index"])
    return tuple(c["name"] for c in channels if c["name"] not in specials)


def empty_metrics() -> dict[str, Any]:
    """Unpopulated metrics block (matches lineage.empty_metrics plus decision fields)."""
    return {
        "mean_iou": None,
        "per_class_iou": None,
        "carb_priority_iou": None,
        "export_eligible": None,
        "shortfall": None,
    }


def food_mean_iou(per_class_iou: Mapping[str, float]) -> float:
    """Mean IoU over FOOD classes only (Req 3.2). Special channels are excluded so
    background's huge pixel share cannot inflate or deflate the number. Food classes
    absent from the report (no GT and no prediction on the split) are skipped from
    the mean, matching train.food_class_miou. Returns 0.0 when no food class is
    present."""
    foods = set(food_class_names())
    values = [
        float(v) for name, v in per_class_iou.items()
        if name in foods and v is not None
    ]
    if not values:
        return 0.0
    return sum(values) / len(values)


def carb_priority_iou(per_class_iou: Mapping[str, float]) -> dict[str, float]:
    """The carb-priority staple IoU subset that is present in the report (Req 3.3)."""
    return {
        c: float(per_class_iou[c])
        for c in CARB_PRIORITY_CLASSES
        if c in per_class_iou and per_class_iou[c] is not None
    }


def shortfall(per_class_iou: Mapping[str, float]) -> list[dict[str, Any]]:
    """List the bars that fell short (empty when export-eligible). Each entry is
    ``{"class": <name|"mean">, "iou": <value|None>, "bar": <float>}`` (Req 3.4):

      - ``"mean"`` when the food-class mean is below MEAN_IOU_BAR;
      - a staple name when its IoU is below the floor OR it is absent from the
        report (absent → cannot prove the floor, Req 3.6).
    """
    failures: list[dict[str, Any]] = []

    mean = food_mean_iou(per_class_iou)
    if mean < MEAN_IOU_BAR:
        failures.append({"class": "mean", "iou": mean, "bar": MEAN_IOU_BAR})

    for c in CARB_PRIORITY_CLASSES:
        value = per_class_iou.get(c)
        if value is None or float(value) < CARB_PRIORITY_IOU_BAR:
            failures.append({
                "class": c,
                "iou": None if value is None else float(value),
                "bar": CARB_PRIORITY_IOU_BAR,
            })
    return failures


def is_export_eligible(per_class_iou: Mapping[str, float]) -> bool:
    """Req 3.2 + 3.5: mean food-class IoU >= 0.60 AND every carb-priority staple
    present with IoU >= 0.50. Equivalent to ``shortfall(...) == []``."""
    return not shortfall(per_class_iou)


def evaluate(per_class_iou: Mapping[str, float]) -> dict[str, Any]:
    """Compute the full metrics + decision block from a per-class IoU report.

    Returns ``{mean_iou, per_class_iou, carb_priority_iou, export_eligible,
    shortfall}`` — the object recorded into ``lineage.metrics`` (Req 3.3/3.4).
    """
    return {
        "mean_iou": food_mean_iou(per_class_iou),
        "per_class_iou": dict(per_class_iou),
        "carb_priority_iou": carb_priority_iou(per_class_iou),
        "export_eligible": is_export_eligible(per_class_iou),
        "shortfall": shortfall(per_class_iou),
    }


def record_metrics_into_lineage(
    lineage: dict[str, Any], per_class_iou: Mapping[str, float]
) -> dict[str, Any]:
    """Write the validation metrics + eligibility decision into a lineage manifest's
    ``metrics`` block (Req 3.4). Mutates and returns ``lineage`` for convenience."""
    lineage["metrics"] = evaluate(per_class_iou)
    return lineage


def update_lineage_file(
    per_class_iou: Mapping[str, float], lineage_path: str | Path
) -> dict[str, Any]:
    """Load ``build/lineage.json``, record the metrics, and write it back (Req 3.4).

    The validation harness calls this after running the trained model over the
    held-out split; the *running* is gated on the GPU prerequisite (stage 3)."""
    path = Path(lineage_path)
    lineage = json.loads(path.read_text())
    record_metrics_into_lineage(lineage, per_class_iou)
    path.write_text(json.dumps(lineage, indent=2, sort_keys=True) + "\n")
    return lineage

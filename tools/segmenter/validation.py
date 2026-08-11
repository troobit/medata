#!/usr/bin/env python3
"""Validation reporting + export-eligibility decision (model-production task 9).

The validation step (design §2.1 stage 4) computes mean food-class IoU, per-class
IoU, and the carb-priority-staple IoU subset on the held-out split, then decides
**export eligibility** and records the result — plus any shortfall — into
``build/lineage.json``'s ``metrics`` block (Req 3.2–3.6).

Export-eligibility rule (Req 3.2 / 3.5, as amended by segmenter-foundation
Decisions 5 and 14 — the re-derived bars; were 0.60/0.50):

  mean food-class IoU >= 0.48  AND  every carb-priority staple IoU >= 0.45

A mean alone can hide a near-zero staple class that dominates the carb number
(Decision 6), so the carb-priority floor is checked per class. A staple that
cannot meet the floor is surfaced as a shortfall (Req 3.6: flag low-confidence or
map to ``unknown_food``) rather than blocking indefinitely.

During the developer phase the strict gate ADVISES rather than hard-blocks: a
below-gate model may be released for normal-use testing via an explicit,
attributable override recorded in lineage (``record_release_override`` /
``release_allowed``, Decision 11). ``export_eligible`` itself always stays
truthful.

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

# Export-eligibility bars (Req 3.2 mean, Req 3.5 per-class carb-priority floor),
# re-derived by segmenter-foundation Decision 5 (gate) and Decision 14 (floors);
# were 0.60/0.50. Authoritative home: specs/estimation/segmenter-foundation/decision_log.md.
MEAN_IOU_BAR = 0.48
CARB_PRIORITY_IOU_BAR = 0.45

# High-carbohydrate staples that dominate the carb number; each must individually
# clear CARB_PRIORITY_IOU_BAR (Req 3.5). Names/order mirror palette indices 0–7
# (unchanged v1 → v2 — the cereal solid appends at index 24, myfoodrepo-bridge
# PRD) and the requirements list. Whether cereal joins this set is the palette
# context's decision-log call once its training coverage is known; until then it
# is a plain food class.
CARB_PRIORITY_CLASSES: tuple[str, ...] = (
    "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
    "potato_boiled", "potato_mashed", "chips_fries",
)

_MAPPING_PATH = Path(__file__).resolve().with_name("class_mapping_foodseg103.json")


def _mapping() -> dict[str, Any]:
    return json.loads(_MAPPING_PATH.read_text())


def special_channel_names() -> tuple[str, ...]:
    """The non-food channels (background, unknown_food, unsupported_liquid) — excluded
    from the food-class mean, mirroring train.food_class_miou's NON_FOOD_CLASSES."""
    return tuple(_mapping()["special_channels"].keys())


def food_class_names() -> tuple[str, ...]:
    """The 33 food-class names in palette/index order (the 36-channel palette
    minus the 3 special channels)."""
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
    """Req 3.2 + 3.5 (as amended by segmenter-foundation Decisions 5/14): mean
    food-class IoU >= 0.48 AND every carb-priority staple present with IoU >= 0.45.
    Equivalent to ``shortfall(...) == []``."""
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


def record_release_override(
    lineage: dict[str, Any], reason: str, authorised_by: str = "developer"
) -> dict[str, Any]:
    """Record an explicit decision to release a model that misses the strict gate.

    ``export_eligible`` stays truthful — the override is a separate, attributable
    record inside ``metrics`` so lineage never claims a below-gate model passed.
    Developer-phase policy (Decision 11): a below-gate model may ship for
    normal-use testing while the model improves iteratively; the strict gate
    returns to blocking before any non-developer release. Mutates and returns
    ``lineage``.
    """
    if not reason or not reason.strip():
        raise ValueError("a release override requires a non-empty reason")
    metrics = lineage.setdefault("metrics", empty_metrics())
    metrics["release_override"] = {
        "allowed": True,
        "reason": reason.strip(),
        "authorised_by": authorised_by,
    }
    return lineage


def release_allowed(metrics: Mapping[str, Any]) -> bool:
    """True when the strict gate passes OR an explicit override was recorded.

    This is the RELEASE decision; ``export_eligible`` remains the strict-gate
    verdict. Re-running validation rewrites ``metrics`` and therefore drops any
    prior override — a new metrics outcome needs a fresh, deliberate override.
    """
    if metrics.get("export_eligible"):
        return True
    override = metrics.get("release_override") or {}
    return bool(override.get("allowed"))


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

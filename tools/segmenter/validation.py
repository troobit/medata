#!/usr/bin/env python3
"""Validation reporting: held-out per-class IoU -> lineage (model-production task 9).

The validation step computes mean food-class IoU, per-class IoU and the
carb-priority-staple subset on the held-out split, then records them into
``build/lineage.json``'s ``metrics`` block.

**This module measures and reports. It does not gate.** There was an
export-eligibility gate here (mean food-class IoU >= 0.48 and every carb staple
>= 0.45), plus an attributable "release override" to get around it. Both were
removed - segmenter-foundation Decision 38 - for two reasons:

  1. The gate read ``mean_iou``, a mean over all 33 food classes of the
     182-image leak-free anchor. That anchor resolves only 13 of them: the
     other 20 appear in fewer than 20 held-out images, and there the SAME
     recipe and seed swing by up to 0.78 between runs. The gate's input was not
     a measurement, so neither was its verdict.
  2. Nothing ever passed it, so every release went through the override, and an
     override that is always taken is not a control - it is a prose field
     attached to an unconditional yes.

What replaces it is nothing. Metrics are recorded in lineage, printed by the
runner, and read by a person. The checks that still block an export live in
``export.py`` and are structural - weight budget, output channel count, Core ML
vs PyTorch oracle parity - because those catch a broken artefact rather than an
underperforming one.

``CARB_PRIORITY_CLASSES`` survives as a REPORTING subset: those classes dominate
the carb number, so they are worth printing separately. No floor is attached.

This module is PURE REPORTING LOGIC: it takes a ``per_class_iou`` mapping (the
output of the GPU validation run) and is independent of running the model.

Pure stdlib (no torch) so it imports and runs without the training deps.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Mapping

# High-carbohydrate staples that dominate the carb number, reported as their own
# subset so a near-zero staple stays visible behind a healthy mean. Names/order
# mirror palette indices 0-7
# (unchanged v1 → v2 — the cereal solid appends at index 24, myfoodrepo-bridge
# PRD) and the requirements list. Whether cereal joins this set is the palette
# context's decision-log call once its training coverage is known; until then it
# is a plain food class. No floor is attached to these (Decision 38).
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


def special_channel_indices() -> tuple[int, ...]:
    """Channel indices of the non-food channels — the ``non_food`` set the
    class-agnostic mask metrics exclude (mask_quality.py)."""
    return tuple(int(i) for i in _mapping()["special_channels"].values())


def food_class_names() -> tuple[str, ...]:
    """The 33 food-class names in palette/index order (the 36-channel palette
    minus the 3 special channels)."""
    specials = set(special_channel_names())
    channels = sorted(_mapping()["target_channels"], key=lambda c: c["index"])
    return tuple(c["name"] for c in channels if c["name"] not in specials)


def dataset_channel_count(data_root: str | Path) -> int | None:
    """The label-space width a prepared dataset directory records for itself.

    Every directory `prepare_dataset.py` / `merge_corpus_foodrec2022.py` emits
    carries a `splits.json` stating its `channel_count`. Returns ``None`` when the
    directory makes no such claim — an unmanifested root is unknown, not wrong.
    """
    manifest = Path(data_root) / "splits.json"
    if not manifest.is_file():
        return None
    try:
        return json.loads(manifest.read_text()).get("channel_count")
    except (json.JSONDecodeError, OSError):
        return None


def assert_label_space(data_root: str | Path, expected_channels: int) -> None:
    """Fail fast when a dataset's label space differs from the model's.

    Two remapped FoodSeg103 roots exist with the SAME image stems but different
    class indices — `foodseg103_remapped` at 35 channels and
    `foodseg103_remapped_v2` at 36, diverging above index 23. Scoring across that
    boundary reads only legal indices, so it never raises on its own: it silently
    mis-attributes every class above the divergence and returns a plausible,
    roughly 0.07-low mean. That is not hypothetical — it put a wrong figure into
    two recorded verdicts before anyone noticed
    (specs/bugfixes/anchor-label-space-mismatch/report.md).

    Silent on an unmanifested root, by the same reasoning as
    ``dataset_channel_count``: this guard exists to catch a contradiction, not to
    require a manifest.
    """
    recorded = dataset_channel_count(data_root)
    if recorded is not None and recorded != expected_channels:
        raise SystemExit(
            f"[validate] label-space mismatch: the model has {expected_channels} "
            f"channels but {data_root} records {recorded} — its masks are in a "
            "different class-index space, and scoring against them would return a "
            "plausible WRONG number rather than fail. Point --data at the matching "
            "corpus (36 channels: data/foodseg103_remapped_v2)."
        )


def empty_metrics() -> dict[str, Any]:
    """Unpopulated metrics block (matches lineage.empty_metrics)."""
    return {"mean_iou": None, "per_class_iou": None, "carb_priority_iou": None}


def food_mean_iou(per_class_iou: Mapping[str, float]) -> float:
    """Mean IoU over FOOD classes only. Special channels are excluded so
    background's huge pixel share cannot inflate or deflate the number. Food classes
    absent from the report (no GT and no prediction on the split) are skipped from
    the mean, matching train.food_class_miou. Returns 0.0 when no food class is
    present.

    READ THIS WITH CARE. On the 182-image leak-free anchor only 13 food classes
    appear in 20 or more images; the rest swing by up to 0.78 between identical
    runs, so this mean is dominated by noise and is NOT what to judge a run on
    (estimation-quality task 14). It is recorded because it is cheap and the
    historical runs carry it, not because it decides anything."""
    foods = set(food_class_names())
    values = [
        float(v) for name, v in per_class_iou.items()
        if name in foods and v is not None
    ]
    if not values:
        return 0.0
    return sum(values) / len(values)


def carb_priority_iou(per_class_iou: Mapping[str, float]) -> dict[str, float]:
    """The carb-priority staple IoU subset that is present in the report."""
    return {
        c: float(per_class_iou[c])
        for c in CARB_PRIORITY_CLASSES
        if c in per_class_iou and per_class_iou[c] is not None
    }


def evaluate(per_class_iou: Mapping[str, float]) -> dict[str, Any]:
    """Compute the metrics block from a per-class IoU report.

    Returns ``{mean_iou, per_class_iou, carb_priority_iou}`` - the object
    recorded into ``lineage.metrics``. No verdict: see the module docstring.
    """
    return {
        "mean_iou": food_mean_iou(per_class_iou),
        "per_class_iou": dict(per_class_iou),
        "carb_priority_iou": carb_priority_iou(per_class_iou),
    }


def record_metrics_into_lineage(
    lineage: dict[str, Any], per_class_iou: Mapping[str, float]
) -> dict[str, Any]:
    """Write the validation metrics into a lineage manifest's ``metrics`` block.
    Mutates and returns ``lineage`` for convenience."""
    lineage["metrics"] = evaluate(per_class_iou)
    return lineage


def update_lineage_file(
    per_class_iou: Mapping[str, float], lineage_path: str | Path
) -> dict[str, Any]:
    """Load ``build/lineage.json``, record the metrics, and write it back.

    The validation harness calls this after running the trained model over the
    held-out split; the *running* is gated on the GPU prerequisite (stage 3)."""
    path = Path(lineage_path)
    lineage = json.loads(path.read_text())
    record_metrics_into_lineage(lineage, per_class_iou)
    path.write_text(json.dumps(lineage, indent=2, sort_keys=True) + "\n")
    return lineage


def update_lineage_mask_quality(
    block: Mapping[str, Any], lineage_path: str | Path
) -> dict[str, Any]:
    """Record the class-agnostic mask metrics (MD-29; ``mask_quality.lineage_block``)
    under ``metrics.mask_quality`` without touching the class metrics - so an old
    checkpoint can be re-scored in place."""
    path = Path(lineage_path)
    lineage = json.loads(path.read_text())
    lineage.setdefault("metrics", empty_metrics())["mask_quality"] = dict(block)
    path.write_text(json.dumps(lineage, indent=2, sort_keys=True) + "\n")
    return lineage

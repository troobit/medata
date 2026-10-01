"""Validation reporting tests (model-production task 8).

Pure reporting logic over synthetic per-class IoU inputs. There is no
export-eligibility gate and no release override to test any more - both were
removed by segmenter-foundation Decision 38, because the bar read a mean over 33
classes of an anchor that resolves 13, and nothing ever passed it. What is left
is the contract that the reporter computes and records the right numbers.
"""

import json

import pytest

import validation


def _food_iou(value: float) -> dict[str, float]:
    """Every food class at ``value`` (special channels are excluded by the reporter)."""
    return {name: value for name in validation.food_class_names()}


# The committed mapping file is regenerated to the 36-channel v2 order by the
# dataset-bridge context (myfoodrepo-bridge tasks); the v2 expectations below are
# integration-gated and activate automatically once channel_count reads 36.
_COMMITTED_MAPPING_IS_V2 = (
    json.loads(validation._MAPPING_PATH.read_text()).get("channel_count") == 36
)


# ── Bars / set contract ─────────────────────────────────────────────────────────

def test_no_gate_survives_anywhere_in_the_reporter():
    """Decision 38. A re-introduced bar would silently start blocking exports."""
    for gone in ("MEAN_IOU_BAR", "CARB_PRIORITY_IOU_BAR", "is_export_eligible",
                 "shortfall", "record_release_override", "release_allowed"):
        assert not hasattr(validation, gone), f"{gone} is back"
    assert set(validation.evaluate({"pasta": 0.5})) == {
        "mean_iou", "per_class_iou", "carb_priority_iou"}


def test_carb_priority_set_matches_spec():
    assert validation.CARB_PRIORITY_CLASSES == (
        "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
        "potato_boiled", "potato_mashed", "chips_fries",
    )
    # Carb-priority staples are a subset of the food classes.
    assert set(validation.CARB_PRIORITY_CLASSES) <= set(validation.food_class_names())


@pytest.mark.skipif(
    not _COMMITTED_MAPPING_IS_V2,
    reason="class_mapping_foodseg103.json still v1/35-channel — the "
           "dataset-bridge context regenerates it to v2; lock activates on "
           "integration",
)
def test_v2_palette_has_cereal_and_three_sentinels():
    foods = validation.food_class_names()
    assert "cereal" in foods
    assert len(foods) == 33  # 36-channel v2 minus the 3 special channels
    assert set(validation.special_channel_names()) == {
        "background", "unknown_food", "unsupported_liquid",
    }


# ── Export-eligibility decision (Req 3.2 / 3.5) ─────────────────────────────────

def test_reports_mean_per_class_and_carb_priority():
    iou = _food_iou(0.65)
    report = validation.evaluate(iou)
    assert report["per_class_iou"] == iou
    assert report["carb_priority_iou"] == {
        c: 0.65 for c in validation.CARB_PRIORITY_CLASSES
    }
    assert abs(report["mean_iou"] - 0.65) < 1e-9


def test_special_channels_excluded_from_mean():
    iou = _food_iou(0.70)
    # Background near zero must NOT drag the food-class mean down.
    iou["background"] = 0.0
    report = validation.evaluate(iou)
    assert abs(report["mean_iou"] - 0.70) < 1e-9


# ── Lineage recording (Req 3.4) ─────────────────────────────────────────────────

def test_records_metrics_into_lineage():
    lineage = {"metrics": {"mean_iou": None, "per_class_iou": None, "carb_priority_iou": None}}
    out = validation.record_metrics_into_lineage(lineage, _food_iou(0.70))
    metrics = out["metrics"]
    assert metrics["mean_iou"] is not None
    assert metrics["per_class_iou"] == _food_iou(0.70)
    assert set(metrics["carb_priority_iou"]) == set(validation.CARB_PRIORITY_CLASSES)


def test_a_poor_run_records_the_same_shape_as_a_good_one():
    """No verdict key appears or disappears with the numbers (Decision 38)."""
    good = validation.evaluate(_food_iou(0.70))
    poor = validation.evaluate(_food_iou(0.05))
    assert set(good) == set(poor)
    assert poor["mean_iou"] < good["mean_iou"]

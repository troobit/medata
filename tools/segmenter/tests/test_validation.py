"""Validation reporting + export-eligibility tests (model-production task 8).

Pure decision logic over synthetic per-class IoU inputs (Req 3.2 / 3.5 / 3.6):
a checkpoint is export-eligible only when mean food-class IoU >= 0.60 AND every
carb-priority staple >= 0.50. Independent of the gated GPU run that produces the
real IoUs — these tests feed fixed synthetic IoUs.
"""

import validation


def _food_iou(value: float) -> dict[str, float]:
    """Every food class at ``value`` (special channels are excluded by the reporter)."""
    return {name: value for name in validation.food_class_names()}


# ── Bars / set contract ─────────────────────────────────────────────────────────

def test_bars_and_carb_priority_set_match_spec():
    assert validation.MEAN_IOU_BAR == 0.60
    assert validation.CARB_PRIORITY_IOU_BAR == 0.50
    assert validation.CARB_PRIORITY_CLASSES == (
        "white_rice", "brown_rice", "pasta", "bread_white", "bread_wholemeal",
        "potato_boiled", "potato_mashed", "chips_fries",
    )
    # Carb-priority staples are a subset of the food classes.
    assert set(validation.CARB_PRIORITY_CLASSES) <= set(validation.food_class_names())


# ── Export-eligibility decision (Req 3.2 / 3.5) ─────────────────────────────────

def test_eligible_when_mean_and_carb_priority_pass():
    report = validation.evaluate(_food_iou(0.70))
    assert report["export_eligible"] is True
    assert report["mean_iou"] >= validation.MEAN_IOU_BAR
    assert report["shortfall"] == []
    assert set(report["carb_priority_iou"]) == set(validation.CARB_PRIORITY_CLASSES)


def test_not_eligible_when_mean_below_bar():
    # Mean 0.55 < 0.60, even though each carb-priority staple clears its 0.50 floor.
    report = validation.evaluate(_food_iou(0.55))
    assert report["export_eligible"] is False
    assert any(s["class"] == "mean" for s in report["shortfall"])


def test_not_eligible_when_a_carb_priority_class_below_floor():
    # Mean is high, but one staple dips under the 0.50 per-class floor (Req 3.5):
    # a mean alone would hide it (Decision 6).
    iou = _food_iou(0.90)
    iou["white_rice"] = 0.40
    report = validation.evaluate(iou)
    assert report["mean_iou"] >= validation.MEAN_IOU_BAR
    assert report["export_eligible"] is False
    failing = {s["class"] for s in report["shortfall"]}
    assert "white_rice" in failing


def test_missing_carb_priority_class_is_a_shortfall():
    # A staple absent from the held-out IoU report cannot prove the floor (Req 3.6).
    iou = _food_iou(0.90)
    del iou["pasta"]
    report = validation.evaluate(iou)
    assert report["export_eligible"] is False
    assert "pasta" in {s["class"] for s in report["shortfall"]}


# ── Reporting (Req 3.3) ─────────────────────────────────────────────────────────

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
    assert metrics["export_eligible"] is True
    assert metrics["shortfall"] == []


def test_records_shortfall_into_lineage_when_sub_bar():
    lineage = {"metrics": validation.empty_metrics() if hasattr(validation, "empty_metrics") else {}}
    out = validation.record_metrics_into_lineage(lineage, _food_iou(0.30))
    metrics = out["metrics"]
    assert metrics["export_eligible"] is False
    assert metrics["shortfall"]  # non-empty: records what fell short

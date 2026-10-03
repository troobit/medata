#!/usr/bin/env python3
"""`make field-score`: the layout of the harness's figures, not the figures.

Every number the report prints comes from HarnessCLI's own JSON. What this
module adds is the cross-group average and the β explanation, so those are
what is pinned here.
"""

from field_loop import field_score


def row(**over):
    base = {"fixture": "a-success", "volume": 200.0, "volumes": {"bread_white": 200.0},
            "relabelled": {}, "rejected": {}, "plane": "foodSupport",
            "carbs": 40.0, "truth_carbs": 30.0, "truth_classes": ["bread_wholemeal"],
            "segmenter": "coreml_88d34e27e8bf", "prediction_ms": {"nadir": 60}}
    base.update(over)
    return base


def test_the_set_error_is_the_mean_over_rows_carrying_truth():
    rows = [row(carbs=40.0, truth_carbs=30.0), row(carbs=20.0, truth_carbs=40.0),
            row(carbs=5.0, truth_carbs=0.0)]
    mape, mae = field_score.aggregate(rows, "carbs", "truth_carbs")
    assert round(mape, 3) == round((10 / 30 + 20 / 40) / 2 * 100, 3)
    assert mae == 15.0
    assert field_score.aggregate([row(truth_carbs=0.0)], "carbs", "truth_carbs") \
        == (None, None)


def test_the_classes_column_names_what_the_review_changed():
    text = field_score.classes_text(row(
        volumes={"bread_wholemeal": 226.3}, relabelled={"unknown_food": "bread_wholemeal"},
        rejected={"coffee": 59.5}))
    assert text == "bread_wholemeal 226.3 (was unknown_food); coffee 59.5 rejected"


def test_an_unbaked_beta_names_the_floor_and_each_excluded_plate():
    artifact = {
        "classes": {"bread_wholemeal": {"status": "uncalibrated_unity", "beta": 1.0,
                                        "effective_sample": 1, "provenance": "none"}},
        "lineage": {"effective_sample_min": 30, "tau_purity": 0.9},
        "support_plane_reference": "foodSupport",
        "run_summary": {"purity_dropped": ["a-success"],
                        "support_plane_reference_excluded": ["b-success"],
                        "plane_fit_skipped": []}}
    lines = field_score.beta_lines("88d34e27e8bf", artifact, [
        row(), row(fixture="b-success", plane="edgeBand")])
    assert lines[0] == ("beta 88d34e27e8bf: none baked — bread_wholemeal has 1 "
                        "admitted plate(s), the floor is 30")
    assert "purity 0.00 < 0.90" in lines[1] and "truth bread_wholemeal" in lines[1]
    assert lines[2] == ("  reference excluded b-success: plane edgeBand; beta is "
                        "fitted on foodSupport")


def test_the_predict_column_brackets_the_oblique_on_a_two_view_capture():
    assert field_score.prediction_text(row()) == "60"
    assert field_score.prediction_text(
        row(prediction_ms={"nadir": 61, "oblique": 59})) == "61 (59)"
    assert field_score.prediction_text(row(prediction_ms={})) == "n/a"


def test_the_median_line_is_per_segmenter_over_nadir_predictions():
    rows = [row(prediction_ms={"nadir": 97}), row(prediction_ms={"nadir": 60}),
            row(prediction_ms={"nadir": 61, "oblique": 59}),
            row(segmenter="coreml_ab812dc3aa9d", prediction_ms={"nadir": 53}),
            row(segmenter="coreml_ab812dc3aa9d", prediction_ms={"nadir": 52}),
            row(segmenter="coreml_ab812dc3aa9d", prediction_ms={})]
    assert field_score.prediction_medians(rows) == (
        "predict ms median (nadir): coreml_88d34e27e8bf 61 over 3 capture(s); "
        "coreml_ab812dc3aa9d 52.5 over 2 capture(s)")
    assert field_score.prediction_medians([row(prediction_ms={})]) \
        == "predict ms median (nadir): nothing timed"

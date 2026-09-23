"""The alignment report (tasks 19/20; Reqs 6.1-6.6, 8.7)."""

import json
import subprocess

import pytest

from field_loop import causes, config, corpus, field_report

SETTINGS = config.load()
TS = 1_756_000_000_000


def seed(index, rows):
    """Insert capture + note + diagnosis triples straight into the index."""
    for i, spec in enumerate(rows):
        stem = spec.get("stem") or corpus.stem_for(TS + i * 1000, "success")
        corpus.upsert_capture(index, {
            "stem": stem, "pull_id": "p1", "timestamp_ms": TS + i * 1000,
            "outcome": "success",
            "capture_mode": spec.get("capture_mode", "single_view_lidar"),
            "scale_source": spec.get("scale_source", "lidar"),
            "build_stamp": spec.get("build_stamp", "abc1234-20260827-101500"),
            "model_version": spec.get("model_version", "ab812dc3aa9d"),
            "db_edition": "cofid-2026-01", "db_hash": spec.get("db_hash"),
            "slimmed": 0, "training_used": int(spec.get("training_used", 0)),
            "detected_classes": spec.get("classes", "white_rice"),
            "sha256": "0" * 64, "bytes": 10})
        note_id = "n%d" % i
        corpus.upsert_note(index, {
            "id": note_id, "pull_id": "p1", "created_at_ms": TS + i * 1000 + 500,
            "screen_id": "capture.result", "text": "note", "carbs_g": 30.0,
            "meal_id": None, "outcome_id": None, "timestamp_ms": TS + i * 1000,
            "meal_linked": 1, "stem": stem, "join_route": "outcome_id",
            "unmatched_reason": None, "snapshot_json": None, "screenshot": None,
            "build_stamp": spec.get("build_stamp", "abc1234-20260827-101500"),
            "model_version": "coreml_ab812dc3aa9d", "sha256": "1" * 64})
        corpus.upsert_diagnosis(index, {
            "stem": stem, "note_id": note_id, "cycle": spec.get("cycle", 1),
            "replay_status": spec.get("replay_status", "replayed"),
            "replay_version_skew": int(spec.get("skew", 0)),
            "replay_delta_g": spec.get("delta", 1.0),
            "cause": spec.get("cause", causes.WITHIN_REPLAY_NOISE),
            "evidence_json": json.dumps(spec.get("evidence", {}), sort_keys=True),
            "cluster_id": spec.get("cluster", stem)})
    index.commit()


def lines_of(index, settings=None, cycle=None):
    out = []
    field_report.report(index, settings or SETTINGS, cycle, out=out.append)
    return out


# --------------------------------------------------------- output conventions

def test_every_figure_prints_its_cell_count(index):
    seed(index, [{"evidence": {"gap_g": 5.0}} for _ in range(3)])
    for line in lines_of(index):
        if "value=" in line:
            assert " n=" in line


def test_a_cell_below_the_floor_reads_insufficient(index):
    seed(index, [{"evidence": {"gap_g": 5.0}} for _ in range(3)])
    gap = [l for l in lines_of(index) if l.startswith("quantity_gap_g")]
    assert gap and "value=insufficient n=3" in gap[0]


def test_a_cell_at_the_floor_carries_a_figure(index):
    seed(index, [{"evidence": {"gap_g": 4.0}} for _ in range(10)])
    gap = [l for l in lines_of(index) if l.startswith("quantity_gap_g")]
    assert "value=4.0000 n=10" in gap[0]


def test_stated_values_are_labelled_developer_stated(index):
    """Req 6.5: never presented as ground truth."""
    seed(index, [{"evidence": {"gap_g": 4.0}} for _ in range(10)])
    text = "\n".join(lines_of(index))
    assert "labelling=developer_stated" in text
    assert "not ground truth" in text
    assert "developer_stated=true" in text


# ------------------------------------------------------------ train/eval split

def test_training_used_rows_are_excluded_with_both_sizes_printed(index):
    seed(index, [{"evidence": {"gap_g": 4.0}} for _ in range(6)]
         + [{"training_used": True, "evidence": {"gap_g": 99.0}} for _ in range(4)])
    header = [l for l in lines_of(index) if l.startswith("report evaluation_set")]
    assert header == ["report evaluation_set n=6 training_used_excluded n=4"]


def test_a_trained_on_capture_cannot_move_the_metric(index):
    seed(index, [{"evidence": {"gap_g": 4.0}} for _ in range(10)]
         + [{"training_used": True, "evidence": {"gap_g": 1000.0}} for _ in range(5)])
    gap = [l for l in lines_of(index) if l.startswith("quantity_gap_g")][0]
    assert "value=4.0000 n=10" in gap


# ------------------------------------------------------------- segmentation

def test_capture_mode_crosses_path_with_card_presence(index):
    row = {"capture_mode": "two_view_sfs", "scale_source": "card"}
    assert field_report.capture_mode(row) == "two_view_sfs/card"
    assert field_report.capture_mode(
        {"capture_mode": "single_view_lidar", "scale_source": "lidar"}) \
        == "single_view_lidar/no_card"
    assert field_report.capture_mode(
        {"capture_mode": "two_view_sfs", "scale_source": None}) \
        == "two_view_sfs/card_unknown"


def test_metrics_are_segmented_by_capture_mode(index):
    """Req 6.6: the deferred Decision 13 evidence base needs both modes."""
    seed(index, [{"evidence": {"gap_g": 4.0}} for _ in range(3)]
         + [{"capture_mode": "two_view_sfs", "scale_source": "card",
             "evidence": {"gap_g": 9.0}} for _ in range(3)])
    modes = {l.split("mode=")[1].split(" ")[0]
             for l in lines_of(index) if l.startswith("quantity_gap_g")}
    assert modes == {"single_view_lidar/no_card", "two_view_sfs/card"}


def test_a_dirty_stamp_is_bucketed_unattributable(index):
    assert field_report.build_bucket("abc1234-dirty-20260827-101500") == \
        field_report.UNATTRIBUTABLE
    assert field_report.build_bucket(None) == field_report.UNATTRIBUTABLE
    assert field_report.build_bucket("abc1234-20260827-101500") == \
        "abc1234-20260827-101500"


def test_dirty_builds_appear_as_their_own_segment(index):
    seed(index, [{"build_stamp": "abc1234-dirty-20260827-101500"}])
    segments = [l for l in lines_of(index) if l.startswith("segment ")]
    assert any("build=unattributable" in l for l in segments)


def test_commit_of_a_stamp_is_its_leading_sha(index):
    assert field_report.commit_of("abc1234-20260827-101500") == "abc1234"
    assert field_report.commit_of("abc1234-dirty-20260827-101500") is None


def test_loop_fix_containment_is_derived_with_merge_base(tmp_path):
    """Req 6.2: which loop fixes a build actually contained."""
    calls = []

    def runner(cmd, **kwargs):
        calls.append(cmd)

        class Result:
            returncode = 0
            stdout = "aaa\x00[ml-feedback-loop]: bread density\n" if cmd[1] == "log" else ""
        return Result()

    fixes = field_report.fixes_in_build("abc1234", "field-loop", tmp_path, runner)
    assert fixes == ["[ml-feedback-loop]: bread density"]
    assert ["git", "merge-base", "--is-ancestor", "aaa", "abc1234"] in calls


def test_a_build_that_predates_a_fix_does_not_claim_it(tmp_path):
    def runner(cmd, **kwargs):
        class Result:
            returncode = 0 if cmd[1] == "log" else 1
            stdout = "aaa\x00[ml-feedback-loop]: bread density\n" if cmd[1] == "log" else ""
        return Result()

    assert field_report.fixes_in_build("abc1234", "field-loop", tmp_path, runner) == []


def test_db_hash_covers_both_artifacts_in_order(tmp_path):
    import hashlib

    seen = []

    def runner(cmd, **kwargs):
        seen.append(cmd[2])

        class Result:
            returncode = 0
            stdout = b"x" if "cofid" in cmd[2] else b"y"
        return Result()

    digest = field_report.db_hash_at("abc1234", tmp_path, runner)
    assert digest == hashlib.sha256(b"xy").hexdigest()
    assert [s.split(":")[1] for s in seen] == list(field_report.DB_ARTIFACTS)


# ---------------------------------------------------------------- the metrics

def test_class_selection_error_counts_only_class_causes(index):
    seed(index, [{"cause": causes.WRONG_CLASS} for _ in range(3)]
         + [{"cause": causes.WRONG_DENSITY} for _ in range(7)])
    line = [l for l in lines_of(index) if l.startswith("class_selection_error")][0]
    assert "value=0.3000 n=10" in line


def test_mask_consistency_reports_all_three_numbers_and_cluster_sizes(index):
    evidence = {"dominant_agreement": 0.5, "mean_pairwise_iou": 0.4,
                "carbs_cov": 0.2}
    seed(index, [{"cluster": "c1", "evidence": evidence} for _ in range(2)]
         + [{"cluster": "c2", "evidence": evidence} for _ in range(3)])
    text = "\n".join(lines_of(index))
    assert "mask_consistency dominant_agreement value=insufficient n=2" in text
    assert "mask_consistency mean_pairwise_iou" in text
    assert "mask_consistency carbs_cov" in text
    assert "clusters=2 sizes=2,3" in text


def test_a_food_that_did_not_improve_is_flagged(index):
    """Req 6.3: directional target, non-decrease flagged into the verdict."""
    seed(index,
         [{"build_stamp": "aaa1111-20260801-100000", "cause": causes.WITHIN_REPLAY_NOISE}]
         + [{"build_stamp": "bbb2222-20260827-100000", "cause": causes.WRONG_MASK}])
    result = field_report.report(index, SETTINGS, out=lambda _: None)
    assert result["non_decrease_flagged"] == ["white_rice"]


def test_a_food_that_improved_is_not_flagged(index):
    seed(index,
         [{"build_stamp": "aaa1111-20260801-100000", "cause": causes.WRONG_MASK}]
         + [{"build_stamp": "bbb2222-20260827-100000",
             "cause": causes.WITHIN_REPLAY_NOISE}])
    result = field_report.report(index, SETTINGS, out=lambda _: None)
    assert result["non_decrease_flagged"] == []


def test_a_single_build_has_no_trend_to_report(index):
    seed(index, [{"cause": causes.WRONG_MASK} for _ in range(3)])
    line = [l for l in lines_of(index) if l.startswith("per_food ")][0]
    assert "trend=single_build" in line
    assert "flag_non_decrease=false" in line


# ---------------------------------------------------- corpus growth and floors

def test_corpus_growth_reports_count_share_and_per_class_coverage(index):
    """Req 8.7."""
    seed(index, [{"classes": "white_rice"}, {"classes": "banana"}])
    corpus.upsert_capture(index, {
        "stem": "unannotated", "pull_id": "p1", "timestamp_ms": TS, "outcome": "x",
        "capture_mode": "single_view_lidar", "scale_source": None,
        "build_stamp": None, "model_version": None, "db_edition": None,
        "db_hash": None, "slimmed": 0, "training_used": 0,
        "detected_classes": "white_rice", "sha256": "2" * 64, "bytes": 1})
    index.commit()
    text = "\n".join(lines_of(index))
    assert "corpus_growth captures=3 annotated=2 annotated_share=0.6667" in text
    assert "corpus_coverage food=white_rice n=2" in text
    assert "corpus_coverage food=banana n=1" in text


def test_the_evaluation_floor_names_the_starved_cells(index):
    seed(index, [{"classes": "banana"}])
    text = "\n".join(lines_of(index))
    assert "eval_floor per_cell=5 cells=1 below_floor=1" in text
    assert "eval_floor_below food=banana mode=single_view_lidar/no_card n=1" in text


def test_evaluation_cells_ignore_trained_on_captures(index):
    """A cell the loop already consumed cannot count toward its own floor."""
    seed(index, [{"classes": "banana", "training_used": True} for _ in range(9)])
    rows, _ = field_report.evaluation_split(field_report.load_rows(index))
    assert field_report.evaluation_cells(rows) == {}


def test_report_writes_the_same_text_it_printed(index, tmp_path, capsys):
    seed(index, [{"evidence": {"gap_g": 1.0}}])
    out = tmp_path / "reports" / "alignment.txt"
    field_report.main(["--corpus", str(index.execute(
        "PRAGMA database_list").fetchone()[2]).rsplit("/", 1)[0],
        "--out", str(out)])
    printed = capsys.readouterr().out
    assert out.read_text() == printed

#!/usr/bin/env python3
"""Training-material derivation from the field corpus (tasks 25/26; Req 8).

Req 8.4 wants field captures to become training and evaluation material in the
formats the existing pipelines already consume, following the merged-corpus
precedent. Four properties carry the risk, and each has its own section below:

* field data must never reach the frozen leak-free anchor;
* one developer's kitchen must not dominate the corpus (the mixing cap);
* a derivation that starves an evaluation cell would make the alignment metric
  go `insufficient` through the loop's own training appetite;
* every derived label must say where it came from, and a model-predicted mask
  must say that it is one.
"""

import json

import pytest

from conftest import grey_png, make_fixture
from field_loop import config, corpus, derive_dataset

SETTINGS = config.load()
TS = 1_756_000_000_000


# ------------------------------------------------------------------ fixtures

def seed_capture(index, corpus_root, stem_ms, *, classes=(1,), note_id=None,
                 mode="single_view_lidar", training_used=0):
    stem = corpus.stem_for(stem_ms, "success")
    path = corpus_root / "captures" / ("%s.fixture" % stem)
    make_fixture(path, fixture_id=stem, classes=classes, with_image=True)
    from field_loop import bundle

    info = bundle.read_summary(path)
    corpus.upsert_capture(index, {
        "stem": stem, "pull_id": "p1", "timestamp_ms": stem_ms,
        "outcome": "success", "capture_mode": mode, "scale_source": "lidar",
        "build_stamp": "abc1234-20260827-101500",
        "model_version": "coreml_ab812dc3aa9d", "db_edition": "cofid-2026-01",
        "db_hash": None, "slimmed": 0, "training_used": training_used,
        "detected_classes": ",".join(info["detected_classes"]),
        "sha256": corpus.sha256_file(path), "bytes": path.stat().st_size})
    if note_id:
        corpus.upsert_note(index, {
            "id": note_id, "pull_id": "p1", "created_at_ms": stem_ms + 5000,
            "screen_id": "capture.result", "text": "two spoons of rice",
            "carbs_g": 30.0, "meal_id": "m-%s" % note_id, "outcome_id": None,
            "timestamp_ms": stem_ms, "meal_linked": 1, "stem": stem,
            "join_route": "outcome_id", "unmatched_reason": None,
            "snapshot_json": None, "screenshot": None,
            "build_stamp": "abc1234-20260827-101500",
            "model_version": "coreml_ab812dc3aa9d", "sha256": "0" * 64})
    index.commit()
    return stem


def seed_many(index, corpus_root, count, **over):
    return [seed_capture(index, corpus_root, TS + i * 600_000,
                         note_id="n%d" % i, **over) for i in range(count)]


@pytest.fixture
def public_corpus(tmp_path):
    """A stand-in merged public corpus: enough train images to allow mixing."""
    root = tmp_path / "merged"
    for split in ("train", "val", "heldout"):
        (root / split / "images").mkdir(parents=True)
        (root / split / "masks").mkdir(parents=True)
    for index in range(90):
        (root / ("train/images/%04d.png" % index)).write_bytes(grey_png(2, 2))
        (root / ("train/masks/%04d.png" % index)).write_bytes(grey_png(2, 2))
    for index in range(10):
        (root / ("val/images/v%03d.png" % index)).write_bytes(grey_png(2, 2))
        (root / ("val/masks/v%03d.png" % index)).write_bytes(grey_png(2, 2))
    for index in range(20):
        (root / ("heldout/images/h%03d.png" % index)).write_bytes(grey_png(2, 2))
        (root / ("heldout/masks/h%03d.png" % index)).write_bytes(grey_png(2, 2))
    return root


def run(index, corpus_root, out, settings=None, ident="anthropic:m:v",
        cycle_dir=None):
    return derive_dataset.derive(
        index, corpus_root, out, settings or dict(SETTINGS),
        interpreting_ident=ident, cycle_dir=cycle_dir)


# ------------------------------------------------------------------- prefix

def test_every_derived_stem_carries_the_field_prefix(index, corpus_root,
                                                     public_corpus):
    seed_many(index, corpus_root, 6)
    summary = run(index, corpus_root, public_corpus)
    derived = summary["files"]["train"] + summary["files"]["val"]
    assert derived
    assert all(stem.startswith(derive_dataset.FIELD_PREFIX) for stem in derived)


def test_the_prefix_cannot_collide_with_the_public_stems(index, corpus_root,
                                                         public_corpus):
    seed_many(index, corpus_root, 6)
    summary = run(index, corpus_root, public_corpus)
    public = {p.stem for p in (public_corpus / "train/images").iterdir()
              if not p.stem.startswith(derive_dataset.FIELD_PREFIX)}
    assert not public & set(summary["files"]["train"])


def test_the_image_and_mask_land_in_the_prepare_dataset_layout(
        index, corpus_root, public_corpus):
    seed_many(index, corpus_root, 6)
    summary = run(index, corpus_root, public_corpus)
    stem = summary["files"]["train"][0]
    assert (public_corpus / "train/images" / ("%s.png" % stem)).exists()
    mask = public_corpus / "train/masks" / ("%s.png" % stem)
    assert mask.exists()
    assert mask.read_bytes().startswith(b"\x89PNG")


def test_co_stats_and_splits_are_written_beside_the_splits(
        index, corpus_root, public_corpus):
    seed_many(index, corpus_root, 6)
    run(index, corpus_root, public_corpus)
    assert json.loads((public_corpus / "co_stats.json").read_text())["schema"] \
        == "co_stats"
    assert (public_corpus / "splits.json").exists()


# ------------------------------------------------------- the frozen anchor

def test_nothing_is_ever_written_to_heldout(index, corpus_root, public_corpus):
    before = sorted(p.name for p in (public_corpus / "heldout/images").iterdir())
    seed_many(index, corpus_root, 6)
    summary = run(index, corpus_root, public_corpus)
    after = sorted(p.name for p in (public_corpus / "heldout/images").iterdir())
    assert before == after
    assert "heldout" not in summary["files"]


def test_the_derivation_asserts_the_anchor_is_untouched(index, corpus_root,
                                                        public_corpus):
    seed_many(index, corpus_root, 6)
    summary = run(index, corpus_root, public_corpus)
    assert summary["anchor"]["untouched"] is True
    assert summary["anchor"]["images"] == 20


def test_a_field_stem_appearing_in_heldout_aborts_the_derivation(
        index, corpus_root, public_corpus):
    (public_corpus / "heldout/images/fld_smuggled.png").write_bytes(grey_png(2, 2))
    seed_many(index, corpus_root, 6)
    with pytest.raises(SystemExit) as error:
        run(index, corpus_root, public_corpus)
    assert "heldout" in str(error.value)


# ---------------------------------------------------------------- mixing cap

def test_the_field_share_of_train_never_exceeds_the_cap(index, corpus_root,
                                                        public_corpus):
    seed_many(index, corpus_root, 40)
    summary = run(index, corpus_root, public_corpus)
    train = summary["counts"]["train"]
    field = summary["counts"]["field_train"]
    assert field / train <= config.get(SETTINGS, "field_train_share_cap")


def test_the_cap_is_recorded_in_splits_json(index, corpus_root, public_corpus):
    seed_many(index, corpus_root, 40)
    run(index, corpus_root, public_corpus)
    splits = json.loads((public_corpus / "splits.json").read_text())
    field = splits["sources"]["field"]
    assert field["mixing_cap"] == config.get(SETTINGS, "field_train_share_cap")
    assert field["prefix"] == derive_dataset.FIELD_PREFIX
    assert field["field_share_of_train"] <= field["mixing_cap"]


def test_captures_beyond_the_cap_are_left_for_a_later_derivation(
        index, corpus_root, public_corpus):
    seed_many(index, corpus_root, 40)
    summary = run(index, corpus_root, public_corpus)
    assert summary["deferred_by_cap"] > 0
    unconsumed = index.execute(
        "SELECT count(*) FROM captures WHERE training_used = 0").fetchone()[0]
    # Everything still in the corpus is there for one of exactly two reasons.
    assert unconsumed == summary["deferred_by_cap"] \
        + summary["blocked_by_eval_floor"]


def test_the_cap_is_computed_against_the_merged_train_total():
    """f/(p+f) <= cap, not f/p — the cap is a share OF the training set."""
    assert derive_dataset.cap_allowance(public_train=90, cap=0.10) == 10
    assert derive_dataset.cap_allowance(public_train=0, cap=0.10) == 0


# ------------------------------------------------------- evaluation floor

def test_derivation_refuses_to_starve_an_evaluation_cell(index, corpus_root,
                                                         public_corpus):
    """Consuming these would drop the (class, mode) cell below the floor."""
    settings = dict(SETTINGS, eval_floor_per_cell=5)
    seed_many(index, corpus_root, 6)
    summary = run(index, corpus_root, public_corpus, settings=settings)
    assert summary["blocked_by_eval_floor"] > 0
    remaining = index.execute(
        "SELECT count(*) FROM captures WHERE training_used = 0").fetchone()[0]
    assert remaining >= settings["eval_floor_per_cell"]


def test_a_well_stocked_cell_is_not_blocked(index, corpus_root, public_corpus):
    settings = dict(SETTINGS, eval_floor_per_cell=2)
    seed_many(index, corpus_root, 8)
    summary = run(index, corpus_root, public_corpus, settings=settings)
    assert summary["counts"]["field_train"] + summary["counts"]["field_val"] > 0


def test_the_floor_leaves_at_least_the_configured_count_per_cell(
        index, corpus_root, public_corpus):
    settings = dict(SETTINGS, eval_floor_per_cell=3)
    seed_many(index, corpus_root, 10)
    run(index, corpus_root, public_corpus, settings=settings)
    left = [dict(r) for r in index.execute(
        "SELECT detected_classes, capture_mode FROM captures "
        "WHERE training_used = 0")]
    assert len(left) >= 3


# ------------------------------------------------------------------ signal

def test_a_capture_with_no_note_or_correction_is_not_derived(
        index, corpus_root, public_corpus):
    seed_capture(index, corpus_root, TS, note_id=None)
    summary = run(index, corpus_root, public_corpus,
                  settings=dict(SETTINGS, eval_floor_per_cell=0))
    assert summary["counts"]["field_train"] == 0
    assert summary["counts"]["field_val"] == 0


def test_a_correction_record_is_signal_even_without_a_note(
        index, corpus_root, public_corpus):
    stem = seed_capture(index, corpus_root, TS, note_id=None)
    corpus.upsert_correction(index, {
        "meal_id": "m1", "predicted_class": "white_rice", "pull_id": "p1",
        "outcome_id": "o1", "created_at": TS, "updated_at": TS,
        "class_corrected": 1, "rejected": 0, "absent": 0,
        "amount_corrected": 0, "record_json": "{}"})
    corpus.upsert_outcome(index, {
        "id": "o1", "pull_id": "p1", "last_pull_id": "p1", "timestamp_ms": TS,
        "outcome": "success", "failure": None, "meal_id": "m1",
        "model_version": "coreml_ab812dc3aa9d", "benchmark_meal_id": None,
        "measurements_json": "{}", "protected": 0})
    index.commit()
    summary = run(index, corpus_root, public_corpus,
                  settings=dict(SETTINGS, eval_floor_per_cell=0))
    assert derive_dataset.FIELD_PREFIX + stem in \
        summary["files"]["train"] + summary["files"]["val"]


def test_an_already_consumed_capture_is_not_derived_twice(
        index, corpus_root, public_corpus):
    settings = dict(SETTINGS, eval_floor_per_cell=0)
    seed_many(index, corpus_root, 6)
    first = run(index, corpus_root, public_corpus, settings=settings)
    second = run(index, corpus_root, public_corpus, settings=settings)
    assert first["counts"]["field_train"] > 0
    assert second["counts"]["field_train"] == 0
    assert second["counts"]["field_val"] == 0


# -------------------------------------------------------------- provenance

def test_every_derived_label_records_the_note_that_produced_it(
        index, corpus_root, public_corpus):
    settings = dict(SETTINGS, eval_floor_per_cell=0)
    seed_many(index, corpus_root, 6)
    summary = run(index, corpus_root, public_corpus, settings=settings)
    stem = (summary["files"]["train"] + summary["files"]["val"])[0]
    record = json.loads(
        (public_corpus / "provenance" / ("%s.json" % stem)).read_text())
    assert record["notes"]
    assert record["field_stem"] == stem


def test_the_interpreting_model_ident_is_recorded(index, corpus_root,
                                                  public_corpus):
    settings = dict(SETTINGS, eval_floor_per_cell=0)
    seed_many(index, corpus_root, 6)
    summary = run(index, corpus_root, public_corpus, settings=settings,
                  ident="google:gemini-3-pro:2026-05")
    stem = (summary["files"]["train"] + summary["files"]["val"])[0]
    record = json.loads(
        (public_corpus / "provenance" / ("%s.json" % stem)).read_text())
    assert record["interpreting_model_ident"] == "google:gemini-3-pro:2026-05"


def test_a_model_predicted_mask_is_flagged_as_self_training(
        index, corpus_root, public_corpus):
    settings = dict(SETTINGS, eval_floor_per_cell=0)
    seed_many(index, corpus_root, 6)
    summary = run(index, corpus_root, public_corpus, settings=settings)
    stem = (summary["files"]["train"] + summary["files"]["val"])[0]
    record = json.loads(
        (public_corpus / "provenance" / ("%s.json" % stem)).read_text())
    assert record["self_training"] is True
    assert record["mask_source"] == "model_argmax"


def test_provenance_quarantines_the_note_text(index, corpus_root, public_corpus):
    settings = dict(SETTINGS, eval_floor_per_cell=0)
    seed_many(index, corpus_root, 6)
    summary = run(index, corpus_root, public_corpus, settings=settings)
    stem = (summary["files"]["train"] + summary["files"]["val"])[0]
    record = json.loads(
        (public_corpus / "provenance" / ("%s.json" % stem)).read_text())
    quoted = record["notes"][0]["text"]
    assert quoted.startswith('"') and json.loads(quoted) == "two spoons of rice"


# ------------------------------------------------------- training_used marks

def test_consumed_captures_are_marked_training_used(index, corpus_root,
                                                    public_corpus):
    settings = dict(SETTINGS, eval_floor_per_cell=0)
    stems = seed_many(index, corpus_root, 6)
    run(index, corpus_root, public_corpus, settings=settings)
    marked = {r[0] for r in index.execute(
        "SELECT stem FROM captures WHERE training_used = 1")}
    assert marked and marked <= set(stems)


def test_a_marked_capture_leaves_the_evaluation_set(index, corpus_root,
                                                    public_corpus):
    from field_loop import field_report

    settings = dict(SETTINGS, eval_floor_per_cell=0)
    seed_many(index, corpus_root, 6)
    run(index, corpus_root, public_corpus, settings=settings)
    rows = [dict(r) for r in index.execute(
        "SELECT training_used FROM captures")]
    evaluated, excluded = field_report.evaluation_split(rows)
    assert excluded


# ---------------------------------------------------- calibration derivation

def test_calibration_derivation_emits_a_fixture_and_a_run_summary(
        index, corpus_root, tmp_path):
    stem = seed_capture(index, corpus_root, TS, note_id="n0")
    corpus.upsert_benchmark(index, {
        "id": "b1", "pull_id": "p1", "name": "weighed rice", "created_at": TS,
        "items": "[]", "truth_carbs_g": 42.0, "db_edition": "cofid-2026-01",
        "fidelity": "weighed"})
    corpus.upsert_outcome(index, {
        "id": "o1", "pull_id": "p1", "last_pull_id": "p1", "timestamp_ms": TS,
        "outcome": "success", "failure": None, "meal_id": "m1",
        "model_version": "coreml_ab812dc3aa9d", "benchmark_meal_id": "b1",
        "measurements_json": "{}", "protected": 0})
    index.commit()

    out = tmp_path / "calibration"
    summary = derive_dataset.derive_calibration(index, corpus_root, out)
    assert (out / ("%s.fixture" % stem)).exists()
    document = json.loads((out / "run_summary.json").read_text())
    assert summary["ingested"] == 1
    for key in ("dataset", "licence", "snapshot", "mapping_version",
                "render_config"):
        assert key in document
    for key in ("image_width", "image_height", "seating_rule"):
        assert key in document["render_config"]


def test_calibration_derivation_takes_only_weighed_benchmarks(
        index, corpus_root, tmp_path):
    seed_capture(index, corpus_root, TS, note_id="n0")
    out = tmp_path / "calibration"
    summary = derive_dataset.derive_calibration(index, corpus_root, out)
    assert summary["ingested"] == 0
    assert json.loads((out / "run_summary.json").read_text())["ingested"] == 0


# ------------------------------------------------------ recommended commands

def test_the_recommended_commands_reach_the_cycle_verdict(
        index, corpus_root, public_corpus, tmp_path):
    cycle_dir = tmp_path / "cycle-3"
    cycle_dir.mkdir()
    (cycle_dir / "verdict.json").write_text(json.dumps({"cycle": 3, "applied": []}))
    settings = dict(SETTINGS, eval_floor_per_cell=0)
    seed_many(index, corpus_root, 6)
    run(index, corpus_root, public_corpus, settings=settings, cycle_dir=cycle_dir)
    verdict = json.loads((cycle_dir / "verdict.json").read_text())
    assert "retrain" in verdict["recommended_commands"]
    assert "recalibrate" in verdict["recommended_commands"]
    assert verdict["derivation"]["counts"]["field_train"] >= 0


def test_launching_a_run_stays_human_gated(index, corpus_root, public_corpus,
                                           tmp_path):
    """The commands are recorded, never executed."""
    cycle_dir = tmp_path / "cycle-3"
    cycle_dir.mkdir()
    (cycle_dir / "verdict.json").write_text(json.dumps({"cycle": 3}))
    settings = dict(SETTINGS, eval_floor_per_cell=0)
    seed_many(index, corpus_root, 6)
    run(index, corpus_root, public_corpus, settings=settings, cycle_dir=cycle_dir)
    verdict = json.loads((cycle_dir / "verdict.json").read_text())
    assert verdict["recommended_commands"]["human_gated"] is True


def test_with_no_verdict_the_commands_are_written_beside_the_cycle(
        index, corpus_root, public_corpus, tmp_path):
    cycle_dir = tmp_path / "cycle-4"
    cycle_dir.mkdir()
    settings = dict(SETTINGS, eval_floor_per_cell=0)
    seed_many(index, corpus_root, 6)
    run(index, corpus_root, public_corpus, settings=settings, cycle_dir=cycle_dir)
    assert not (cycle_dir / "verdict.json").exists()
    document = json.loads((cycle_dir / "derivation.json").read_text())
    assert "retrain" in document["recommended_commands"]

"""Pull, ingest, and the corpus index (tasks 15/16; Reqs 3.3-3.5, 3.7, 8.1)."""

import json
import sqlite3
import subprocess
from pathlib import Path

import pytest

from conftest import (make_fixture, make_meals_db, make_note, snapshot_of)
from field_loop import corpus, field_pull
from field_loop.ingest import NOTE_WINDOW_MS, ingest_pull, verify_snapshot

TS = 1_756_000_000_000


def build_pull(root, pull_id="20260827-1", *, captures=(), notes=(), db=None,
               slimming=None):
    """A pull directory shaped exactly as `field_pull` leaves one."""
    pull_dir = root / "pulls" / pull_id
    (pull_dir / "captures").mkdir(parents=True, exist_ok=True)
    (pull_dir / "notes").mkdir(parents=True, exist_ok=True)
    for spec in captures:
        make_fixture(pull_dir / "captures" / ("%s.fixture" % spec.pop("stem")), **spec)
    for spec in notes:
        make_note(pull_dir / "notes" / ("%s.json" % spec["note_id"]), **spec)
    if db is not None:
        make_meals_db(pull_dir / "meals.sqlite", **db)
    if slimming is not None:
        (pull_dir / "slimming_state.json").write_text(json.dumps(slimming))
    return pull_dir


# ------------------------------------------------------------- Req 3.4 counts

def test_ingest_reports_the_required_counts(corpus_root, index):
    pull = build_pull(
        corpus_root,
        captures=[{"stem": corpus.stem_for(TS, "success"), "classes": (0,)}],
        notes=[{"note_id": "n1", "created_at_ms": TS + 5_000,
                "meal": {"outcome_id": "o1", "timestamp_ms": TS}}],
        db={"outcomes": [{"id": "o1", "timestamp": TS, "outcome": "success"}],
            "corrections": [{"meal_id": "m1", "predicted_class": "white_rice",
                             "created_at": TS}],
            "benchmarks": [{"id": "b1", "name": "porridge", "truth_carbs_g": 27.0}]})

    summary = ingest_pull(pull, corpus_root, index)

    assert (summary.notes, summary.bundles, summary.outcomes,
            summary.corrections) == (1, 1, 1, 1)
    assert summary.joins_resolved == 1
    assert summary.db_integrity == "ok"
    assert summary.benchmarks == 1
    head = summary.lines()[0]
    for key in ("notes=1", "bundles=1", "outcome_rows=1", "correction_rows=1",
                "joins_resolved=1"):
        assert key in head


def test_reingesting_the_same_pull_changes_nothing(corpus_root, index):
    pull = build_pull(
        corpus_root,
        captures=[{"stem": corpus.stem_for(TS, "success"), "classes": (0, 5)}],
        notes=[{"note_id": "n1", "created_at_ms": TS + 5_000,
                "meal": {"outcome_id": "o1", "timestamp_ms": TS}}],
        db={"outcomes": [{"id": "o1", "timestamp": TS, "outcome": "success"}]})

    ingest_pull(pull, corpus_root, index)
    once = corpus.dump_index(index)
    ingest_pull(pull, corpus_root, index)
    assert corpus.dump_index(index) == once


def test_a_later_pull_accretes_rather_than_replaces(corpus_root, index):
    first = build_pull(
        corpus_root, "20260827-1",
        captures=[{"stem": corpus.stem_for(TS, "success")}])
    ingest_pull(first, corpus_root, index)
    second = build_pull(
        corpus_root, "20260828-1",
        captures=[{"stem": corpus.stem_for(TS, "success")},
                  {"stem": corpus.stem_for(TS + 90_000, "refusal")}])
    ingest_pull(second, corpus_root, index)

    stems = [r["stem"] for r in index.execute("SELECT stem FROM captures ORDER BY stem")]
    assert stems == [corpus.stem_for(TS, "success"),
                     corpus.stem_for(TS + 90_000, "refusal")]
    # Re-copied in the second pull, but the corpus dates it to the first.
    kept = index.execute("SELECT pull_id FROM captures WHERE stem = ?",
                         (corpus.stem_for(TS, "success"),)).fetchone()
    assert kept["pull_id"] == "20260827-1"
    assert len(list((corpus_root / "captures").glob("*.fixture"))) == 2


# ------------------------------------------------------------ join resolution

def test_note_joins_through_its_outcome_id(corpus_root, index):
    pull = build_pull(
        corpus_root,
        captures=[{"stem": corpus.stem_for(TS, "success")}],
        notes=[{"note_id": "n1", "created_at_ms": TS + 3_000,
                "meal": {"outcome_id": "o1"}}],
        db={"outcomes": [{"id": "o1", "timestamp": TS, "outcome": "success"}]})
    ingest_pull(pull, corpus_root, index)

    row = index.execute("SELECT stem, join_route FROM notes WHERE id = 'n1'").fetchone()
    assert row["stem"] == corpus.stem_for(TS, "success")
    assert row["join_route"] == "outcome_id"


def test_timestamp_fallback_verifies_against_detected_classes(corpus_root, index):
    """Two bundles share the instant; only one explains what the note saw."""
    pull = build_pull(
        corpus_root,
        captures=[{"stem": corpus.stem_for(TS, "success"), "classes": (0,)},
                  {"stem": corpus.stem_for(TS, "success-2"), "classes": (21,)}],
        notes=[{"note_id": "n1", "created_at_ms": TS + 4_000,
                "meal": {"timestamp_ms": TS},
                "snapshot": snapshot_of(("banana", 118.0, 27.0))}])
    ingest_pull(pull, corpus_root, index)

    row = index.execute("SELECT stem, join_route FROM notes WHERE id = 'n1'").fetchone()
    assert row["stem"] == corpus.stem_for(TS, "success-2")   # class 21 = banana
    assert row["join_route"] == "timestamp_window"


def test_note_without_a_capture_timestamp_uses_the_window(corpus_root, index):
    pull = build_pull(
        corpus_root,
        captures=[{"stem": corpus.stem_for(TS, "success"), "classes": (0,)}],
        notes=[{"note_id": "n1", "created_at_ms": TS + NOTE_WINDOW_MS - 1,
                "meal": {"meal_id": "m1"},
                "snapshot": snapshot_of(("white_rice", 150.0, 45.0))}])
    ingest_pull(pull, corpus_root, index)
    assert index.execute(
        "SELECT stem FROM notes WHERE id = 'n1'").fetchone()["stem"]


def test_a_note_outside_the_window_is_unmatched_not_dropped(corpus_root, index):
    pull = build_pull(
        corpus_root,
        captures=[{"stem": corpus.stem_for(TS, "success")}],
        notes=[{"note_id": "n1", "created_at_ms": TS + NOTE_WINDOW_MS + 60_000,
                "meal": {"meal_id": "m1"}}])
    summary = ingest_pull(pull, corpus_root, index)

    row = index.execute("SELECT stem, unmatched_reason FROM notes "
                        "WHERE id = 'n1'").fetchone()
    assert row["stem"] is None
    assert row["unmatched_reason"] == "never_present"
    assert summary.unmatched == {"never_present": 1}


def test_unmatched_reason_deleted_when_protection_outlived_the_row(corpus_root, index):
    """The outcome row is gone; its protection row is not. Req 3.5's `deleted`."""
    pull = build_pull(
        corpus_root,
        notes=[{"note_id": "n1", "created_at_ms": TS + 3_000,
                "meal": {"outcome_id": "o-gone"}}],
        db={"protected": ["o-gone"]})
    summary = ingest_pull(pull, corpus_root, index)

    assert index.execute("SELECT unmatched_reason FROM notes WHERE id = 'n1'"
                         ).fetchone()["unmatched_reason"] == "deleted"
    assert summary.unmatched == {"deleted": 1}


def test_unmatched_reason_never_present_for_an_unknown_outcome(corpus_root, index):
    pull = build_pull(
        corpus_root,
        notes=[{"note_id": "n1", "created_at_ms": TS,
                "meal": {"outcome_id": "o-unknown"}}],
        db={"outcomes": []})
    summary = ingest_pull(pull, corpus_root, index)
    assert summary.unmatched == {"never_present": 1}


def test_missing_bundle_is_its_own_reason(corpus_root, index):
    """The outcome joined; the bundle it names was never pulled."""
    pull = build_pull(
        corpus_root,
        notes=[{"note_id": "n1", "created_at_ms": TS + 1_000,
                "meal": {"outcome_id": "o1"}}],
        db={"outcomes": [{"id": "o1", "timestamp": TS, "outcome": "success"}]})
    summary = ingest_pull(pull, corpus_root, index)
    assert summary.unmatched == {"missing_bundle": 1}


def test_eviction_of_a_protected_outcome_is_reported_as_a_defect(corpus_root, index):
    """Req 3.2 makes this impossible. Its occurrence is a defect signal, and
    the ingest says so rather than filing it as ordinary data loss."""
    first = build_pull(
        corpus_root, "20260827-1",
        db={"outcomes": [{"id": "o1", "timestamp": TS, "outcome": "success"}],
            "protected": ["o1"]})
    ingest_pull(first, corpus_root, index)

    second = build_pull(corpus_root, "20260828-1",
                        db={"outcomes": [], "protected": ["o1"]})
    summary = ingest_pull(second, corpus_root, index)

    assert summary.evicted_defect == ["o1"]
    assert any("DEFECT protected_outcome_evicted" in line for line in summary.lines())


def test_non_meal_notes_ingest_without_a_join_attempt(corpus_root, index):
    """Req 7.1: the same persistence and pull, no estimation join to make."""
    pull = build_pull(
        corpus_root,
        notes=[{"note_id": "n1", "created_at_ms": TS, "screen_id": "records",
                "text": "the emoji on this row is wrong"}])
    summary = ingest_pull(pull, corpus_root, index)

    row = index.execute("SELECT meal_linked, stem, unmatched_reason FROM notes"
                        ).fetchone()
    assert (row["meal_linked"], row["stem"], row["unmatched_reason"]) == (0, None, None)
    assert summary.unmatched == {}
    assert summary.notes == 1


def test_multiple_notes_on_one_capture_all_survive(corpus_root, index):
    """Req 2.5 on the Mac side: a later note never overwrites an earlier one."""
    pull = build_pull(
        corpus_root,
        captures=[{"stem": corpus.stem_for(TS, "success")}],
        notes=[{"note_id": "n1", "created_at_ms": TS + 1_000,
                "meal": {"outcome_id": "o1"}},
               {"note_id": "n2", "created_at_ms": TS + 9_000, "text": "and cold",
                "meal": {"outcome_id": "o1"}}],
        db={"outcomes": [{"id": "o1", "timestamp": TS, "outcome": "success"}]})
    ingest_pull(pull, corpus_root, index)

    stems = [r["stem"] for r in index.execute("SELECT stem FROM notes ORDER BY id")]
    assert stems == [corpus.stem_for(TS, "success")] * 2


# --------------------------------------------------------- snapshot integrity

def test_a_torn_snapshot_is_refused_before_anything_is_written(corpus_root, index):
    pull = build_pull(corpus_root,
                      captures=[{"stem": corpus.stem_for(TS, "success")}])
    (pull / "meals.sqlite").write_bytes(b"SQLite format 3\x00" + b"\x00" * 200)

    with pytest.raises(SystemExit) as caught:
        ingest_pull(pull, corpus_root, index)
    assert "integrity_check" in str(caught.value)
    assert index.execute("SELECT count(*) FROM captures").fetchone()[0] == 0


def test_verify_snapshot_passes_a_sound_database(tmp_path):
    path = make_meals_db(tmp_path / "meals.sqlite")
    assert verify_snapshot(path) == "ok"


# ------------------------------------------------------- corpus index details

def test_capture_mode_and_slimming_are_indexed(corpus_root, index):
    pull = build_pull(
        corpus_root,
        captures=[{"stem": corpus.stem_for(TS, "success"),
                   "capture_path": "two_view_sfs", "with_probs": False}])
    (pull / "captures" / ("%s.slimmed" % corpus.stem_for(TS, "success"))).write_text("")
    ingest_pull(pull, corpus_root, index)

    row = index.execute("SELECT capture_mode, slimmed, model_version, "
                        "detected_classes FROM captures").fetchone()
    assert row["capture_mode"] == "two_view_sfs"
    assert row["slimmed"] == 1
    assert row["model_version"] == "ab812dc3aa9d"
    assert row["detected_classes"] == "white_rice"


def test_build_stamp_and_scale_source_backfill_from_the_join(corpus_root, index):
    """Neither is in the fixture: Req 6.2/6.6 segmentation would be blind
    without the note and outcome supplying them."""
    pull = build_pull(
        corpus_root,
        captures=[{"stem": corpus.stem_for(TS, "success")}],
        notes=[{"note_id": "n1", "created_at_ms": TS + 2_000,
                "build_stamp": "deadbee-20260827-120000",
                "meal": {"outcome_id": "o1"}}],
        db={"outcomes": [{"id": "o1", "timestamp": TS, "outcome": "success"}]})
    ingest_pull(pull, corpus_root, index)

    row = index.execute("SELECT build_stamp, scale_source FROM captures").fetchone()
    assert row["build_stamp"] == "deadbee-20260827-120000"
    assert row["scale_source"] == "lidar"


def test_slimming_state_is_surfaced_in_the_summary(corpus_root, index):
    """Req 3.6: when the sweep cannot reach the watermark, the next pull says so."""
    pull = build_pull(corpus_root, slimming={
        "at_ms": TS, "footprint_bytes": 41_000_000_000,
        "watermark_bytes": 20_000_000_000, "bundles_slimmed": 112,
        "watermark_reached": False, "deferred_reason": None})
    summary = ingest_pull(pull, corpus_root, index)
    assert summary.slimming["watermark_reached"] is False
    assert any("watermark_reached=False" in line for line in summary.lines())


def test_corpus_root_follows_the_main_checkout_not_the_worktree(monkeypatch, tmp_path):
    monkeypatch.delenv(corpus.CORPUS_ENV, raising=False)
    root = corpus.corpus_root()
    assert root.name == corpus.CORPUS_DIRNAME
    assert root.parent == corpus.repo_root().parent


# -------------------------------------------------------- manifest and pruning

class RecordingTransport:
    """Stands in for devicectl: records what would have crossed the wire."""

    def __init__(self):
        self.pushed = []

    def copy_to(self, local, remote):
        self.pushed.append((remote, Path(local).read_bytes()))
        return True


def test_manifest_lists_only_verified_files_and_retirable_protections(corpus_root,
                                                                     index):
    stem = corpus.stem_for(TS, "success")
    pull = build_pull(
        corpus_root,
        captures=[{"stem": stem}],
        notes=[{"note_id": "n1", "created_at_ms": TS + 2_000,
                "meal": {"outcome_id": "o1"}}],
        db={"outcomes": [{"id": "o1", "timestamp": TS, "outcome": "success"},
                         {"id": "o2", "timestamp": TS + 60_000, "outcome": "success"}],
            "protected": ["o1", "o2"]})
    ingest_pull(pull, corpus_root, index)

    hashes = {"captures/%s.fixture" % stem: "aa" * 32, "notes/n1.json": "bb" * 32}
    manifest = field_pull.build_manifest(index, "20260827-1", hashes)

    assert manifest["bundles"] == [{"stem": stem, "sha256": "aa" * 32}]
    assert manifest["notes"] == [{"stem": "n1", "sha256": "bb" * 32}]
    # o2 has no note pointing at it in this pull, so its protection stays.
    assert manifest["protected_outcomes"] == ["o1"]


def test_manifest_push_is_two_phase_and_sentinel_verifiable(tmp_path):
    transport = RecordingTransport()
    manifest = {"pull_id": "20260827-1", "bundles": [], "notes": [],
                "protected_outcomes": []}
    assert field_pull.push_manifest(transport, manifest, tmp_path / "staging")

    (first, body), (second, sentinel_body) = transport.pushed
    assert first.endswith(corpus.MANIFEST_NAME)
    assert second.endswith(corpus.SENTINEL_NAME)
    sentinel = json.loads(sentinel_body)
    import hashlib
    assert sentinel["sha256"] == hashlib.sha256(body).hexdigest()
    assert sentinel["length"] == len(body)


def test_pull_summary_prints_corpus_size_and_the_acceptance_line(corpus_root,
                                                                 capsys):
    build_pull(corpus_root, captures=[{"stem": corpus.stem_for(TS, "success")}])
    field_pull.main(["--corpus", str(corpus_root),
                     "--pull-dir", str(corpus_root / "pulls" / "20260827-1")])
    out = capsys.readouterr().out
    assert "corpus root=" in out and "bytes=" in out
    assert corpus.SINGLE_COPY_ACCEPTANCE in out


def test_next_pull_id_counts_within_the_utc_day(corpus_root):
    from datetime import datetime, timezone
    now = datetime(2026, 8, 27, 9, 0, tzinfo=timezone.utc)
    assert field_pull.next_pull_id(corpus_root, now) == "20260827-1"
    (corpus_root / "pulls" / "20260827-1").mkdir(parents=True)
    assert field_pull.next_pull_id(corpus_root, now) == "20260827-2"


def test_devicectl_listing_is_flattened_structurally():
    payload = {"result": {"files": [
        {"name": "notes", "files": [{"name": "1-a.json"}, {"name": "1-a.png"}]},
        {"name": "meals.sqlite"}]}}
    assert field_pull._flatten_listing(payload, "Documents") == [
        "Documents/meals.sqlite", "Documents/notes/1-a.json",
        "Documents/notes/1-a.png"]


def test_listing_entries_prefer_relative_paths_and_sizes():
    payload = {"result": {"files": [
        {"name": "x.json", "relativePath": "x.json",
         "metadata": {"size": 7}, "resources": {"isDirectory": False}},
        {"name": "sub", "relativePath": "sub",
         "resources": {"isDirectory": True}}]}}
    assert field_pull._listing_entries(payload, "Documents/notes") == [
        ("Documents/notes/x.json", 7)]


class StubPullTransport:
    """A device whose files are dict entries; records what crossed the wire."""

    def __init__(self, listing, payloads):
        self.listing = listing          # {subdirectory: [(remote, size)]}
        self.payloads = payloads        # {remote: bytes}
        self.copied = []

    def list_files(self, subdirectory):
        if subdirectory not in self.listing:
            raise subprocess.CalledProcessError(1, "devicectl")
        return self.listing[subdirectory]

    def copy_from(self, remote, local, size=None):
        if remote not in self.payloads:
            return False
        local.parent.mkdir(parents=True, exist_ok=True)
        local.write_bytes(self.payloads[remote])
        self.copied.append(remote)
        return True


def test_pull_skips_present_files_at_listed_size_and_marks_completion(corpus_root):
    pull_dir = corpus_root / "pulls" / "20260827-1"
    (pull_dir / "captures").mkdir(parents=True)
    (pull_dir / "captures" / "a.fixture").write_bytes(b"already-here")
    transport = StubPullTransport(
        {"Documents/captures": [
            ("Documents/captures/a.fixture", len(b"already-here")),
            ("Documents/captures/b.fixture", 3)]},
        {"Documents/captures/b.fixture": b"new"})

    hashes = field_pull.pull_files(transport, pull_dir)

    # The present-at-size file was hashed without a wire copy; only the
    # missing one crossed. Optional DB siblings missing is not a failure, so
    # the completion marker lands.
    assert transport.copied == ["Documents/captures/b.fixture"]
    assert set(hashes) == {"captures/a.fixture", "captures/b.fixture"}
    assert (pull_dir / field_pull.PULL_COMPLETE_NAME).exists()


def test_resolve_pull_dir_resumes_only_incomplete_dirs(corpus_root):
    from datetime import datetime, timezone
    now = datetime(2026, 8, 27, 9, 0, tzinfo=timezone.utc)
    first = corpus_root / "pulls" / "20260827-1"
    first.mkdir(parents=True)
    assert field_pull.resolve_pull_dir(corpus_root, now) == (first, True)
    (first / field_pull.PULL_COMPLETE_NAME).write_text("{}")
    assert field_pull.resolve_pull_dir(corpus_root, now) == (
        corpus_root / "pulls" / "20260827-2", False)

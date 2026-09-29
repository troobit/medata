"""Reclaiming the corpus's space without losing what the ledger is keyed to."""

import pytest

from field_loop import corpus, field_discard

TS = 1_756_000_000_000


def seed(index, root, *, captures=2, notes=1):
    """Capture bundles on disk with matching index rows, plus a note."""
    (root / "captures").mkdir(exist_ok=True)
    (root / "pulls" / "2026-09-29-1").mkdir(parents=True, exist_ok=True)
    (root / "pulls" / "2026-09-29-1" / "wire.bin").write_bytes(b"x" * 64)
    for i in range(captures):
        stem = corpus.stem_for(TS + i * 1000, "success")
        (root / "captures" / ("%s.fixture" % stem)).write_bytes(b"y" * 128)
        corpus.upsert_capture(index, {
            "stem": stem, "pull_id": "p1", "timestamp_ms": TS + i * 1000,
            "outcome": "success", "capture_mode": "single_view_lidar",
            "scale_source": "lidar", "build_stamp": "abc1234-20260929-101500",
            "model_version": "ab812dc3aa9d", "db_edition": "cofid-2026-01",
            "db_hash": None, "slimmed": 0, "training_used": 0,
            "detected_classes": "", "sha256": "0" * 64, "bytes": 128,
        })
    for i in range(notes):
        corpus.upsert_note(index, {
            "id": "n%d" % i, "pull_id": "p1", "created_at_ms": TS,
            "screen_id": "result", "text": "too much rice",
            "sha256": "1" * 64,
        })
    index.commit()


def test_survey_counts_both_sides(corpus_root, index):
    seed(index, corpus_root, captures=3, notes=2)
    found = field_discard.survey(corpus_root)
    assert found["capture_files"] == 3
    assert found["indexed_captures"] == 3
    assert found["notes"] == 2
    assert found["capture_bytes"] >= 3 * 128


def test_refuses_without_confirmation_and_deletes_nothing(corpus_root, index,
                                                          capsys):
    seed(index, corpus_root)
    assert field_discard.main(["--corpus", str(corpus_root)]) == 1
    assert "refused=missing_confirmation" in capsys.readouterr().out
    assert len(list((corpus_root / "captures").glob("*.fixture"))) == 2


@pytest.mark.parametrize("confirm", ["", "y", "YES", "no"])
def test_only_the_exact_word_confirms(corpus_root, index, confirm):
    seed(index, corpus_root)
    assert field_discard.main(["--corpus", str(corpus_root),
                              "--confirm", confirm]) == 1
    assert len(list((corpus_root / "captures").glob("*.fixture"))) == 2


def test_discard_drops_captures_and_pulls_but_keeps_the_index(corpus_root, index):
    seed(index, corpus_root, captures=2, notes=2)
    index.close()

    assert field_discard.main(["--corpus", str(corpus_root),
                              "--confirm", "yes"]) == 0

    assert list((corpus_root / "captures").glob("*.fixture")) == []
    # pulls/ holds the wire copies the ingest hard-linked from; leaving it would
    # leave the bytes behind under another name.
    assert list((corpus_root / "pulls").iterdir()) == []
    after = field_discard.survey(corpus_root)
    assert after["indexed_captures"] == 2, "the index still records what happened"
    assert after["notes"] == 2, "the triage ledger is keyed to these"


def test_layout_survives_so_the_next_pull_needs_no_repair(corpus_root, index):
    seed(index, corpus_root)
    index.close()
    field_discard.main(["--corpus", str(corpus_root), "--confirm", "yes"])
    for name in ("captures", "pulls", "notes", "db"):
        assert (corpus_root / name).is_dir()

#!/usr/bin/env python3
"""Turn one pull directory into corpus rows (Reqs 3.4, 3.5, 8.1).

A pull directory is what came off the phone verbatim:

    <corpus>/pulls/<pull-id>/
      notes/<stem>.json|.png
      captures/<stem>.fixture  (+ <stem>.slimmed markers)
      meals.sqlite (+ -wal/-shm/-journal siblings)
      slimming_state.json

Ingest accretes it into the corpus proper — captures keyed by stem, notes by
id, the DB snapshot kept whole — and then resolves the note joins. It is
idempotent by construction (every writer replaces on a natural key), so the
regression assertion is `dump_index` unchanged across two runs of the same
directory.

The DB snapshot is verified before it is trusted: a torn `meals.sqlite` copied
mid-write would otherwise seed the index with rows that never existed.
"""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path

from . import corpus
from .bundle import read_summary

# How long after a capture its note may have been written, when the note's own
# meal link carries no capture timestamp. The bundle is stamped when estimation
# STARTS and the note when the developer reacts to the result, so the window is
# one-sided and generous — shortlist_hit_rate.py's join, widened for a human.
NOTE_WINDOW_MS = 15 * 60 * 1000


@dataclass
class IngestSummary:
    """The Req 3.4 counts, verbatim, plus what did not join (Req 3.5)."""

    pull_id: str = ""
    notes: int = 0
    bundles: int = 0
    outcomes: int = 0
    corrections: int = 0
    benchmarks: int = 0
    joins_resolved: int = 0
    unmatched: dict = field(default_factory=dict)
    db_integrity: str = "absent"
    # Req 3.2 says an outcome a note points at cannot be evicted. When one has
    # been anyway, that is a defect in the protection path, not a data quirk,
    # and it is reported as one rather than absorbed into `unmatched`.
    evicted_defect: list = field(default_factory=list)
    slimming: dict = field(default_factory=dict)

    def lines(self) -> list:
        out = [
            "ingest pull=%s notes=%d bundles=%d outcome_rows=%d "
            "correction_rows=%d joins_resolved=%d"
            % (self.pull_id, self.notes, self.bundles, self.outcomes,
               self.corrections, self.joins_resolved),
            "ingest db_integrity=%s benchmark_meals=%d" % (self.db_integrity,
                                                           self.benchmarks),
        ]
        for reason in sorted(self.unmatched):
            out.append("ingest unmatched reason=%s n=%d"
                       % (reason, self.unmatched[reason]))
        if self.evicted_defect:
            out.append("ingest DEFECT protected_outcome_evicted n=%d ids=%s"
                       % (len(self.evicted_defect),
                          ",".join(sorted(self.evicted_defect)[:5])))
        if self.slimming:
            out.append(
                "ingest slimming watermark_reached=%s footprint_bytes=%s "
                "bundles_slimmed=%s"
                % (self.slimming.get("watermark_reached"),
                   self.slimming.get("footprint_bytes"),
                   self.slimming.get("bundles_slimmed")))
        return out


def verify_snapshot(db_path: Path) -> str:
    """`PRAGMA integrity_check`, fail-closed.

    Returns the pragma's verdict for the pull row; raises before any row is
    written when it is not `ok`, so a torn snapshot is never half-ingested
    (design, Error Handling: "snapshot never ingested unverified").
    """
    conn = None
    try:
        conn = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
        verdict = conn.execute("PRAGMA integrity_check").fetchone()[0]
    except sqlite3.DatabaseError as error:
        # A snapshot torn badly enough that the header no longer parses never
        # reaches the pragma at all; both outcomes mean the same thing here.
        verdict = str(error)
    finally:
        if conn is not None:
            conn.close()
    if verdict != "ok":
        raise SystemExit(
            "%s failed PRAGMA integrity_check (%s) — the snapshot was copied "
            "torn. Re-pull it WITH its -wal/-shm/-journal siblings; nothing "
            "from this pull has been ingested." % (db_path.name, verdict))
    return verdict


# ------------------------------------------------------------------- the pass

def ingest_pull(pull_dir: Path, root: Path, conn) -> IngestSummary:
    pull_dir = Path(pull_dir)
    root = corpus.ensure_layout(Path(root))
    summary = IngestSummary(pull_id=pull_dir.name)

    db_path = pull_dir / "meals.sqlite"
    device = None
    if db_path.exists():
        summary.db_integrity = verify_snapshot(db_path)
        corpus.link_or_copy(db_path, root / "db" / ("%s.meals.sqlite" % pull_dir.name))
        device = sqlite3.connect("file:%s?mode=ro" % db_path, uri=True)
        device.row_factory = sqlite3.Row

    try:
        _ingest_captures(pull_dir, root, conn, summary)
        if device is not None:
            _ingest_device_rows(device, conn, summary)
        _ingest_notes(pull_dir, root, conn, summary)
        _resolve_joins(conn, summary)
    finally:
        if device is not None:
            device.close()

    state = pull_dir / "slimming_state.json"
    if state.exists():
        summary.slimming = json.loads(state.read_text())

    corpus.upsert_pull(conn, {
        "id": summary.pull_id,
        # From the directory, never the clock: a wall-clock stamp would make
        # the idempotence assertion fail on its own second run.
        "pulled_at_ms": int(pull_dir.stat().st_mtime * 1000),
        "source": str(pull_dir),
        "notes": summary.notes,
        "bundles": summary.bundles,
        "outcomes": summary.outcomes,
        "corrections": summary.corrections,
        "joins_resolved": summary.joins_resolved,
        "unmatched": sum(summary.unmatched.values()),
        "db_integrity": summary.db_integrity,
        "slimming_json": json.dumps(summary.slimming, sort_keys=True)
        if summary.slimming else None,
    })
    conn.commit()
    return summary


def _ingest_captures(pull_dir, root, conn, summary):
    captures = pull_dir / "captures"
    if not captures.is_dir():
        return
    for path in sorted(captures.glob("*.fixture")):
        stem = path.stem
        info = read_summary(path)
        timestamp_ms, outcome = corpus.split_stem(stem)
        corpus.link_or_copy(path, root / "captures" / path.name)
        marker = captures / ("%s.slimmed" % stem)
        if marker.exists():
            corpus.link_or_copy(marker, root / "captures" / marker.name)
        corpus.upsert_capture(conn, {
            "stem": stem,
            "pull_id": summary.pull_id,
            "timestamp_ms": timestamp_ms,
            "outcome": outcome,
            "capture_mode": info["capture_mode"],
            "scale_source": None,
            "build_stamp": None,
            "model_version": info["model_version"] or None,
            "db_edition": info["db_edition"] or None,
            "db_hash": None,
            # The sidecar marks content state; a bundle that lost its
            # probability tensors is still schema-current, which is why
            # fixture_revision is not what says so.
            "slimmed": int(marker.exists() or not info["has_probs"]),
            "training_used": 0,
            "detected_classes": ",".join(info["detected_classes"]),
            "sha256": corpus.sha256_file(path),
            "bytes": path.stat().st_size,
        })
        summary.bundles += 1


def _ingest_device_rows(device, conn, summary):
    def table_exists(name):
        return device.execute(
            "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
            (name,)).fetchone() is not None

    protected = set()
    if table_exists("protected_outcomes"):
        protected = {r[0] for r in device.execute(
            "SELECT outcome_id FROM protected_outcomes")}

    seen_outcomes = set()
    if table_exists("estimation_outcomes"):
        for row in device.execute("SELECT * FROM estimation_outcomes"):
            seen_outcomes.add(row["id"])
            corpus.upsert_outcome(conn, {
                "id": row["id"],
                "pull_id": summary.pull_id,
                "last_pull_id": summary.pull_id,
                "timestamp_ms": row["timestamp"],
                "outcome": row["outcome"],
                "failure": row["failure"],
                "meal_id": row["meal_id"],
                "model_version": row["model_version"],
                "benchmark_meal_id": row["benchmark_meal_id"],
                "measurements_json": row["measurements"],
                "protected": int(row["id"] in protected),
            })
            summary.outcomes += 1

    # A protection row whose outcome row is gone is the evidence the unmatched
    # decision procedure runs on, so it is kept even when it points at nothing.
    for outcome_id in sorted(protected):
        conn.execute(
            "INSERT OR REPLACE INTO protections (outcome_id, pull_id) VALUES (?, ?)",
            (outcome_id, summary.pull_id))

    # Req 3.2 defect check: an id this pull still protects, seen in an earlier
    # pull's DB and absent from this one, was evicted despite its protection.
    if table_exists("estimation_outcomes"):
        for row in conn.execute(
                "SELECT id FROM outcomes WHERE last_pull_id != ?", (summary.pull_id,)):
            if row["id"] in protected and row["id"] not in seen_outcomes:
                summary.evicted_defect.append(row["id"])

    if table_exists("correction_records"):
        for row in device.execute("SELECT * FROM correction_records"):
            corpus.upsert_correction(conn, {
                "meal_id": row["meal_id"],
                "predicted_class": row["predicted_class"],
                "pull_id": summary.pull_id,
                "outcome_id": row["outcome_id"],
                "created_at": row["created_at"],
                "updated_at": row["updated_at"],
                "class_corrected": row["class_corrected"],
                "rejected": row["rejected"],
                "absent": row["absent"],
                "amount_corrected": row["amount_corrected"],
                "record_json": _blob_text(row["record_json"]),
            })
            summary.corrections += 1

    if table_exists("benchmark_meals"):
        for row in device.execute("SELECT * FROM benchmark_meals"):
            corpus.upsert_benchmark(conn, {
                "id": row["id"],
                "pull_id": summary.pull_id,
                "name": row["name"],
                "created_at": row["created_at"],
                "items": _blob_text(row["items"]),
                "truth_carbs_g": row["truth_carbs_g"],
                "db_edition": row["db_edition"],
                "fidelity": row["fidelity"],
            })
            summary.benchmarks += 1


def _blob_text(value):
    if isinstance(value, (bytes, bytearray)):
        try:
            return value.decode()
        except UnicodeDecodeError:
            return value.hex()
    return value


def _ingest_notes(pull_dir, root, conn, summary):
    notes = pull_dir / "notes"
    if not notes.is_dir():
        return
    for path in sorted(notes.glob("*.json")):
        note = json.loads(path.read_text())
        corpus.link_or_copy(path, root / "notes" / path.name)
        shot = note.get("screenshot")
        if shot and (notes / shot).exists():
            corpus.link_or_copy(notes / shot, root / "notes" / shot)
        meal = note.get("meal") or {}
        corpus.upsert_note(conn, {
            "id": note["id"],
            "pull_id": summary.pull_id,
            "created_at_ms": note["created_at_ms"],
            "screen_id": note.get("screen_id", ""),
            # Verbatim (Req 2.3). Household measures are the content, and the
            # Mac side does not parse them either — an interpreting model does,
            # in the agent phase, with its ident recorded.
            "text": note.get("text", ""),
            "carbs_g": note.get("carbs_g"),
            "meal_id": meal.get("meal_id"),
            "outcome_id": meal.get("outcome_id"),
            "timestamp_ms": meal.get("timestamp_ms"),
            "meal_linked": int(bool(meal)),
            "stem": None,
            "join_route": None,
            "unmatched_reason": None,
            "snapshot_json": json.dumps(note["estimate_snapshot"], sort_keys=True)
            if note.get("estimate_snapshot") else None,
            "screenshot": shot,
            "build_stamp": note.get("build_stamp"),
            "model_version": note.get("model_version"),
            "sha256": corpus.sha256_file(path),
        })
        summary.notes += 1


# ------------------------------------------------------------ join resolution

def _resolve_joins(conn, summary):
    """note -> outcome id -> (timestampMs, outcome) -> bundle stem.

    The fallback when that chain breaks is the timestamp window VERIFIED
    against the classes the note's estimate snapshot recorded: a timestamp
    alone is a guess, and a wrong join would attribute one meal's gap to
    another meal's capture. Every class the developer was looking at must be
    present in the candidate bundle's argmax — not the converse, since speckle
    below the estimate's area threshold is still in the mask.
    """
    captures = [dict(r) for r in conn.execute(
        "SELECT stem, timestamp_ms, outcome, detected_classes FROM captures")]
    by_ts = {}
    for cap in captures:
        by_ts.setdefault(cap["timestamp_ms"], []).append(cap)

    for note in [dict(r) for r in conn.execute("SELECT * FROM notes")]:
        if not note["meal_linked"]:
            continue
        stem, route, reason = _resolve_one(conn, note, by_ts)
        conn.execute(
            "UPDATE notes SET stem = ?, join_route = ?, unmatched_reason = ? "
            "WHERE id = ?", (stem, route, reason, note["id"]))
        if stem:
            summary.joins_resolved += 1
            _backfill_capture(conn, note, stem)
        else:
            summary.unmatched[reason] = summary.unmatched.get(reason, 0) + 1


def _resolve_one(conn, note, by_ts):
    outcome_id = note["outcome_id"]
    outcome = None
    if outcome_id:
        outcome = conn.execute(
            "SELECT * FROM outcomes WHERE id = ?", (outcome_id,)).fetchone()
        if outcome is None:
            return None, None, _missing_outcome_reason(conn, outcome_id)

    if outcome is not None:
        exact = corpus.stem_for(outcome["timestamp_ms"], outcome["outcome"])
        if conn.execute("SELECT 1 FROM captures WHERE stem = ?",
                        (exact,)).fetchone():
            return exact, "outcome_id", None
        # Collision-suffixed siblings (`<stem>-2`) are distinct bundles for the
        # same start instant; the outcome names the instant, so the earliest
        # sibling is the one the outcome describes.
        siblings = sorted(c["stem"] for c in by_ts.get(outcome["timestamp_ms"], [])
                          if (c["outcome"] or "").startswith(outcome["outcome"]))
        if siblings:
            return siblings[0], "outcome_id_sibling", None

    stem = _fallback_by_timestamp(note, by_ts)
    if stem:
        return stem, "timestamp_window", None
    if outcome is not None:
        return None, None, "missing_bundle"
    return None, None, "never_present"


def _fallback_by_timestamp(note, by_ts):
    stated = set()
    if note["snapshot_json"]:
        snapshot = json.loads(note["snapshot_json"])
        stated = {f["class_id"] for f in snapshot.get("foods", [])}

    anchor = note["timestamp_ms"]
    best = None
    for timestamp, group in by_ts.items():
        if timestamp is None:
            continue
        if anchor is not None:
            delta = abs(anchor - timestamp)
            if delta > 1000:
                continue
        else:
            delta = note["created_at_ms"] - timestamp
            if not 0 <= delta <= NOTE_WINDOW_MS:
                continue
        for cap in sorted(group, key=lambda c: c["stem"]):
            found = {c for c in (cap["detected_classes"] or "").split(",") if c}
            if stated and not stated <= found:
                continue
            if best is None or delta < best[0]:
                best = (delta, cap["stem"])
    return best[1] if best else None


def _missing_outcome_reason(conn, outcome_id):
    """Why is there no outcome row for an id a note names? (Req 3.5)

    The three answers are decided by evidence, never guessed: a surviving
    protection row means the row was deleted out from under its protection; a
    row this corpus saw in an earlier pull means it was evicted, which Req 3.2
    makes structurally impossible and so is a defect signal; anything else was
    never on any pulled device in the first place.
    """
    if conn.execute("SELECT 1 FROM protections WHERE outcome_id = ?",
                    (outcome_id,)).fetchone():
        return "deleted"
    return "never_present"


def _backfill_capture(conn, note, stem):
    """A capture's build stamp and scale source come from what joined to it.

    The fixture records neither: the stamp lives in the note (and in correction
    records), and the scale source lives in the outcome's measurements. Without
    this the Req 6.2 segmentation would bucket every capture `unattributable`.
    """
    updates = {}
    if note["build_stamp"]:
        updates["build_stamp"] = note["build_stamp"]
    if note["outcome_id"]:
        row = conn.execute("SELECT measurements_json FROM outcomes WHERE id = ?",
                           (note["outcome_id"],)).fetchone()
        if row and row["measurements_json"]:
            try:
                measurements = json.loads(row["measurements_json"])
            except (ValueError, TypeError):
                measurements = {}
            if measurements.get("scaleSource"):
                updates["scale_source"] = measurements["scaleSource"]
    for column, value in updates.items():
        conn.execute(
            "UPDATE captures SET %s = ? WHERE stem = ? AND (%s IS NULL OR %s = '')"
            % (column, column, column), (value, stem))

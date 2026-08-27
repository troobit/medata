#!/usr/bin/env python3
"""Where the corpus lives, what its index holds, and how rows get in.

The corpus (`medata-corpus/`, a sibling of the repo clone) is the accumulating
raw material every diagnosis, metric, and derived dataset is computed from
(Req 8.1). Its location is resolved from `git rev-parse --git-common-dir`
rather than from the process's cwd: a worktree — including the nested ones
agent tooling creates — must see the SAME corpus as the main checkout, not
grow a private one beside itself.

Idempotence is the index's whole contract (Req 3.4): every writer here is
keyed on a natural key and replaces, so re-ingesting an unchanged pull leaves
`dump_index` byte-identical. Anything that would make a row carry wall-clock
time is derived from the pull directory instead.
"""

from __future__ import annotations

import hashlib
import json
import os
import sqlite3
import subprocess
from pathlib import Path

CORPUS_DIRNAME = "medata-corpus"
CORPUS_ENV = "MEDATA_CORPUS"

# Decision 14 / Req 8.3. Printed in every pull summary: device-side pruning is
# gated on this risk being accepted and visible, not on a second copy existing.
SINGLE_COPY_ACCEPTANCE = (
    "corpus_durability=single_copy_accepted "
    "reason='Decision 14 — no second copy exists; a corpus disk failure loses "
    "irreplaceable field data'"
)

# The two-phase device-cleanup handshake. Names are a wire contract with
# App/FieldMaintenance.swift (ManifestFile) — changing one without the other
# silently strands every pull's cleanup.
MANIFEST_NAME = "pulled_manifest.json.partial"
SENTINEL_NAME = "pulled_manifest.ready"

SCHEMA = """
CREATE TABLE IF NOT EXISTS pulls (
    id             TEXT PRIMARY KEY,
    pulled_at_ms   INTEGER NOT NULL,
    source         TEXT    NOT NULL,
    notes          INTEGER NOT NULL,
    bundles        INTEGER NOT NULL,
    outcomes       INTEGER NOT NULL,
    corrections    INTEGER NOT NULL,
    joins_resolved INTEGER NOT NULL,
    unmatched      INTEGER NOT NULL,
    db_integrity   TEXT    NOT NULL,
    slimming_json  TEXT
);
CREATE TABLE IF NOT EXISTS captures (
    stem            TEXT PRIMARY KEY,
    pull_id         TEXT    NOT NULL,
    timestamp_ms    INTEGER,
    outcome         TEXT,
    capture_mode    TEXT    NOT NULL,
    scale_source    TEXT,
    build_stamp     TEXT,
    model_version   TEXT,
    db_edition      TEXT,
    db_hash         TEXT,
    slimmed         INTEGER NOT NULL DEFAULT 0,
    training_used   INTEGER NOT NULL DEFAULT 0,
    detected_classes TEXT   NOT NULL DEFAULT '',
    sha256          TEXT    NOT NULL,
    bytes           INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS notes (
    id             TEXT PRIMARY KEY,
    pull_id        TEXT    NOT NULL,
    created_at_ms  INTEGER NOT NULL,
    screen_id      TEXT    NOT NULL,
    text           TEXT    NOT NULL,
    carbs_g        REAL,
    meal_id        TEXT,
    outcome_id     TEXT,
    timestamp_ms   INTEGER,
    meal_linked    INTEGER NOT NULL DEFAULT 0,
    stem           TEXT,
    join_route     TEXT,
    unmatched_reason TEXT,
    snapshot_json  TEXT,
    screenshot     TEXT,
    build_stamp    TEXT,
    model_version  TEXT,
    sha256         TEXT    NOT NULL
);
CREATE TABLE IF NOT EXISTS outcomes (
    id                TEXT PRIMARY KEY,
    pull_id           TEXT    NOT NULL,
    last_pull_id      TEXT    NOT NULL,
    timestamp_ms      INTEGER NOT NULL,
    outcome           TEXT    NOT NULL,
    failure           TEXT,
    meal_id           TEXT,
    model_version     TEXT,
    benchmark_meal_id TEXT,
    measurements_json TEXT    NOT NULL,
    protected         INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS protections (
    outcome_id TEXT PRIMARY KEY,
    pull_id    TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS corrections (
    meal_id          TEXT NOT NULL,
    predicted_class  TEXT NOT NULL,
    pull_id          TEXT NOT NULL,
    outcome_id       TEXT,
    created_at       INTEGER NOT NULL,
    updated_at       INTEGER NOT NULL,
    class_corrected  INTEGER NOT NULL,
    rejected         INTEGER NOT NULL,
    absent           INTEGER NOT NULL,
    amount_corrected INTEGER NOT NULL,
    record_json      TEXT NOT NULL,
    PRIMARY KEY (meal_id, predicted_class)
);
CREATE TABLE IF NOT EXISTS benchmark_meals (
    id            TEXT PRIMARY KEY,
    pull_id       TEXT    NOT NULL,
    name          TEXT    NOT NULL,
    created_at    INTEGER NOT NULL,
    items         TEXT    NOT NULL,
    truth_carbs_g REAL    NOT NULL,
    db_edition    TEXT    NOT NULL,
    fidelity      TEXT    NOT NULL
);
CREATE TABLE IF NOT EXISTS diagnoses (
    stem                TEXT    NOT NULL,
    note_id             TEXT    NOT NULL,
    cycle               INTEGER NOT NULL,
    replay_status       TEXT    NOT NULL,
    replay_version_skew INTEGER NOT NULL,
    replay_delta_g      REAL,
    cause               TEXT    NOT NULL,
    evidence_json       TEXT    NOT NULL,
    cluster_id          TEXT,
    PRIMARY KEY (stem, note_id, cycle)
);
-- The loop's memory of its own commits. Not derivable from the overlay file:
-- that records the value currently in effect, while the DOF cooldown and the
-- lifetime bound need to know WHICH CYCLE moved which column on which class.
CREATE TABLE IF NOT EXISTS applied_fixes (
    fix_id      TEXT PRIMARY KEY,
    cycle       INTEGER NOT NULL,
    class_id    TEXT    NOT NULL,
    column_name TEXT    NOT NULL,
    prior_value REAL,
    value       REAL,
    commit_sha  TEXT
);
CREATE TABLE IF NOT EXISTS ref_readings (
    image_sha256 TEXT NOT NULL,
    ident        TEXT NOT NULL,
    series       TEXT NOT NULL,
    reading_json TEXT NOT NULL,
    PRIMARY KEY (image_sha256, ident)
);
"""


def repo_root(start=None) -> Path:
    """The MAIN checkout root, seen identically from every worktree.

    `--git-common-dir` names the shared `.git` directory: in a worktree it
    points back at the main checkout, which is exactly the property the corpus
    location needs. `--show-toplevel` would give the worktree's own root and a
    per-worktree corpus.
    """
    start = Path(start) if start else Path(__file__).resolve().parent
    common = subprocess.run(
        ["git", "rev-parse", "--git-common-dir"],
        cwd=str(start), capture_output=True, text=True, check=True,
    ).stdout.strip()
    path = Path(common)
    if not path.is_absolute():
        path = (start / path).resolve()
    return path.parent


def corpus_root(start=None) -> Path:
    """`<repo-parent>/medata-corpus/`, or `$MEDATA_CORPUS` when set.

    The override exists for the test suite and for a developer pointing the
    tooling at a scratch corpus; it is read fresh on every call so a test can
    set it per-case.
    """
    override = os.environ.get(CORPUS_ENV)
    if override:
        return Path(override)
    return repo_root(start).parent / CORPUS_DIRNAME


def ensure_layout(root: Path) -> Path:
    for sub in ("captures", "notes", "db", "pulls", "reports", "cycles"):
        (root / sub).mkdir(parents=True, exist_ok=True)
    return root


def open_index(root: Path) -> sqlite3.Connection:
    ensure_layout(root)
    conn = sqlite3.connect(root / "index.sqlite")
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    conn.commit()
    return conn


# ------------------------------------------------------------------ utilities

def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def stem_for(timestamp_ms: int, outcome: str) -> str:
    """The bundle stem CaptureBundleRecorder.filenameStem writes.

    Zero-padded to 13 digits so a lexicographic sort is chronological — the
    same reason the recorder pads it.
    """
    return "%013d-%s" % (int(timestamp_ms), outcome)


def split_stem(stem: str):
    """(timestamp_ms, outcome) from a stem, or (None, None).

    Collision suffixes (`-2`, `-3`) are part of the outcome segment here: they
    identify a distinct bundle, and folding them together would join a note to
    the wrong capture.
    """
    head, _, tail = stem.partition("-")
    if not head.isdigit() or not tail:
        return None, None
    return int(head), tail


def directory_bytes(path: Path) -> int:
    total = 0
    for item in path.rglob("*"):
        if item.is_file() and not item.is_symlink():
            total += item.stat().st_size
    return total


def link_or_copy(src: Path, dst: Path) -> None:
    """Hardlink into the corpus, copying only across filesystems.

    A capture bundle is ~390 MB; copying every one on every ingest would make
    a day's pull cost tens of gigabytes of needless writes.
    """
    import shutil

    if dst.exists():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        os.link(src, dst)
    except OSError:
        shutil.copy2(src, dst)


# -------------------------------------------------------------------- writers
# Every writer replaces on the natural key. Columns a later pull cannot know
# better than an earlier one (a capture's first pull, a note's join) are read
# back before the replace rather than reset to a default.

def _replace(conn, table: str, row: dict) -> None:
    cols = sorted(row)
    conn.execute(
        "INSERT OR REPLACE INTO %s (%s) VALUES (%s)"
        % (table, ", ".join(cols), ", ".join("?" for _ in cols)),
        [row[c] for c in cols],
    )


def upsert_pull(conn, row: dict) -> None:
    _replace(conn, "pulls", row)


def upsert_capture(conn, row: dict) -> None:
    prior = conn.execute(
        "SELECT pull_id, training_used, db_hash, build_stamp FROM captures WHERE stem = ?",
        (row["stem"],),
    ).fetchone()
    if prior is not None:
        # First-seen pull is the capture's provenance; a later pull re-copying
        # the same stem does not re-date it. training_used, db_hash and a
        # resolved build stamp are downstream findings the ingest never knows.
        row = dict(row, pull_id=prior["pull_id"])
        row.setdefault("training_used", prior["training_used"])
        row["training_used"] = prior["training_used"]
        row["db_hash"] = row.get("db_hash") or prior["db_hash"]
        row["build_stamp"] = row.get("build_stamp") or prior["build_stamp"]
    _replace(conn, "captures", row)


def upsert_note(conn, row: dict) -> None:
    prior = conn.execute(
        "SELECT pull_id FROM notes WHERE id = ?", (row["id"],)
    ).fetchone()
    if prior is not None:
        row = dict(row, pull_id=prior["pull_id"])
    _replace(conn, "notes", row)


def upsert_outcome(conn, row: dict) -> None:
    prior = conn.execute(
        "SELECT pull_id FROM outcomes WHERE id = ?", (row["id"],)
    ).fetchone()
    row = dict(row)
    row["last_pull_id"] = row.get("last_pull_id") or row["pull_id"]
    if prior is not None:
        row["pull_id"] = prior["pull_id"]
    _replace(conn, "outcomes", row)


def upsert_correction(conn, row: dict) -> None:
    _replace(conn, "corrections", row)


def upsert_benchmark(conn, row: dict) -> None:
    _replace(conn, "benchmark_meals", row)


def upsert_diagnosis(conn, row: dict) -> None:
    _replace(conn, "diagnoses", row)


def upsert_ref_reading(conn, row: dict) -> None:
    _replace(conn, "ref_readings", row)


def dump_index(conn) -> str:
    """A deterministic text rendering of the whole index.

    The idempotence assertion (Req 3.4) is `dump == dump` across two ingests of
    the same pull, so this must order everything and hide nothing: a writer
    that quietly stamped wall-clock time would show up here as a diff.
    """
    lines = []
    tables = [r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")]
    for table in tables:
        cols = [r[1] for r in conn.execute("PRAGMA table_info(%s)" % table)]
        lines.append("# %s(%s)" % (table, ",".join(cols)))
        rows = conn.execute(
            "SELECT %s FROM %s" % (", ".join(cols), table)).fetchall()
        for row in sorted(json.dumps(list(r), default=str) for r in rows):
            lines.append(row)
    return "\n".join(lines) + "\n"

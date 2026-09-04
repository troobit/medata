"""Shared builders for the field-loop tests.

Stdlib only, and deliberately so: this suite is the regression net for the
pull/ingest path, which must stay runnable on a bare interpreter (the food-db
bake's `PYTHON=` escape hatch exists because the default python3 on this
machine has no third-party packages at all). Anything heavy — numpy, torch —
is imported lazily inside the code under test, never here.

`tools/field_loop` is imported as the package `field_loop` by putting `tools/`
on sys.path, following tools/food_db/tests/conftest.py's precedent of importing
the tool under test as a plain module rather than installing anything.
"""

import json
import sqlite3
import struct
import sys
from pathlib import Path

import pytest

TOOLS = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(TOOLS))

from field_loop import corpus  # noqa: E402


# ------------------------------------------------------- proto wire synthesis
# A real bundle is ~390 MB. These are the same message with everything the
# index reads and nothing else, written by hand so the suite carries no
# committed binaries it cannot explain.

def _varint(value: int) -> bytes:
    out = bytearray()
    while True:
        byte = value & 0x7F
        value >>= 7
        out.append(byte | (0x80 if value else 0))
        if not value:
            return bytes(out)


def _tag(number: int, wire: int) -> bytes:
    return _varint((number << 3) | wire)


def _bytes_field(number: int, payload: bytes) -> bytes:
    return _tag(number, 2) + _varint(len(payload)) + payload


def _string_field(number: int, text: str) -> bytes:
    return _bytes_field(number, text.encode())


def _varint_field(number: int, value: int) -> bytes:
    return _tag(number, 0) + _varint(value)


def intrinsics(width: int, height: int) -> bytes:
    """CameraIntrinsics with only the two fields parse_intrinsics reads."""
    return _varint_field(6, width) + _varint_field(7, height)


def grey_png(width: int, height: int, fill: int = 0) -> bytes:
    """An 8-bit greyscale PNG, written by hand.

    The derivation copies a bundle's `nadir_image` through untouched, so the
    suite needs real PNG bytes but no image library — zlib and struct are
    enough, and the conftest stays stdlib-only.
    """
    import struct
    import zlib

    raw = b"".join(b"\x00" + bytes([fill]) * width for _ in range(height))

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def make_fixture(path: Path, *, fixture_id="fx", classes=(0,), width=4, height=4,
                 capture_path="single_view_lidar", checkpoint="ab812dc3aa9d",
                 db_edition="cofid-2026-01", with_probs=True,
                 with_image=False) -> Path:
    """A minimal PbMealFixture on the wire.

    `classes` fills the argmax plane, cycling, so the detected-class set is
    exactly the classes named — which is what the join's verification step and
    the mask-consistency measure both read.
    """
    plane = bytes(classes[i % len(classes)] for i in range(width * height))
    body = b"".join([
        _string_field(1, fixture_id),
        _string_field(4, db_edition),
        _string_field(5, checkpoint),
        _bytes_field(11, plane),
        _bytes_field(13, intrinsics(width, height)),
        _string_field(19, capture_path),
    ])
    if with_image:
        body += _bytes_field(6, grey_png(width, height))
    if with_probs:
        # 36 FP16 channels per pixel: presence is all the index reads, so the
        # content is zeros. A bundle without this field reads as slimmed.
        body += _bytes_field(9, b"\x00" * (width * height * 36 * 2))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)
    return path


# ------------------------------------------------------------ device DB + notes

MEALS_SCHEMA = """
CREATE TABLE estimation_outcomes (
    id TEXT PRIMARY KEY, timestamp INTEGER NOT NULL, outcome TEXT NOT NULL,
    failure TEXT, measurements TEXT NOT NULL, meal_id TEXT,
    model_version TEXT NOT NULL, benchmark_meal_id TEXT);
CREATE TABLE correction_records (
    meal_id TEXT NOT NULL, predicted_class TEXT NOT NULL, outcome_id TEXT,
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    class_corrected INTEGER NOT NULL, rejected INTEGER NOT NULL,
    absent INTEGER NOT NULL, amount_corrected INTEGER NOT NULL,
    record_json BLOB NOT NULL, PRIMARY KEY (meal_id, predicted_class));
CREATE TABLE benchmark_meals (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, created_at INTEGER NOT NULL,
    items TEXT NOT NULL, truth_carbs_g REAL NOT NULL, db_edition TEXT NOT NULL,
    fidelity TEXT NOT NULL);
CREATE TABLE protected_outcomes (outcome_id TEXT PRIMARY KEY);
CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
"""


def make_meals_db(path: Path, *, outcomes=(), corrections=(), benchmarks=(),
                  protected=()) -> Path:
    conn = sqlite3.connect(path)
    conn.executescript(MEALS_SCHEMA)
    conn.execute("INSERT INTO meta (k, v) VALUES ('schema_version', '11')")
    for row in outcomes:
        conn.execute(
            "INSERT INTO estimation_outcomes (id, timestamp, outcome, failure, "
            "measurements, meal_id, model_version, benchmark_meal_id) "
            "VALUES (:id, :timestamp, :outcome, :failure, :measurements, "
            ":meal_id, :model_version, :benchmark_meal_id)",
            {"failure": None, "meal_id": None, "benchmark_meal_id": None,
             "measurements": json.dumps({"capturePath": "single_view_lidar",
                                         "scaleSource": "lidar"}),
             "model_version": "coreml_ab812dc3aa9d", **row})
    for row in corrections:
        conn.execute(
            "INSERT INTO correction_records (meal_id, predicted_class, outcome_id, "
            "created_at, updated_at, class_corrected, rejected, absent, "
            "amount_corrected, record_json) VALUES (:meal_id, :predicted_class, "
            ":outcome_id, :created_at, :updated_at, :class_corrected, :rejected, "
            ":absent, :amount_corrected, :record_json)",
            {"outcome_id": None, "updated_at": row.get("created_at", 0),
             "class_corrected": 1, "rejected": 0, "absent": 0,
             "amount_corrected": 0, "record_json": b"{}", **row})
    for row in benchmarks:
        conn.execute(
            "INSERT INTO benchmark_meals (id, name, created_at, items, "
            "truth_carbs_g, db_edition, fidelity) VALUES (:id, :name, "
            ":created_at, :items, :truth_carbs_g, :db_edition, :fidelity)",
            {"items": "[]", "db_edition": "cofid-2026-01",
             "fidelity": "weighed", "created_at": 0, **row})
    for outcome_id in protected:
        conn.execute("INSERT INTO protected_outcomes (outcome_id) VALUES (?)",
                     (outcome_id,))
    conn.commit()
    conn.close()
    return path


def make_note(path: Path, *, note_id, created_at_ms, text="too much rice",
              screen_id="capture.result", carbs_g=None, meal=None,
              snapshot=None, screenshot=None, build_stamp="abc1234-20260827-101500",
              model_version="coreml_ab812dc3aa9d") -> Path:
    note = {"v": 1, "id": note_id, "created_at_ms": created_at_ms,
            "screen_id": screen_id, "text": text, "speech_used": False,
            "build_stamp": build_stamp, "model_version": model_version,
            "profile": "field"}
    if carbs_g is not None:
        note["carbs_g"] = carbs_g
    if meal:
        note["meal"] = meal
    if snapshot:
        note["estimate_snapshot"] = snapshot
    if screenshot:
        note["screenshot"] = screenshot
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(note, sort_keys=True))
    return path


def snapshot_of(*foods) -> dict:
    """`{class_id: (mass_g, carbs_g)}` as the note's frozen estimate."""
    rows = [{"class_id": c, "display_name": c.replace("_", " ").title(),
             "mass_g": m, "carbs_g": g} for c, m, g in foods]
    return {"foods": rows,
            "displayed_total_carbs_g": sum(r["carbs_g"] for r in rows),
            "displayed_total_mass_g": sum(r["mass_g"] for r in rows)}


@pytest.fixture
def corpus_root(tmp_path, monkeypatch):
    root = tmp_path / "medata-corpus"
    monkeypatch.setenv(corpus.CORPUS_ENV, str(root))
    return corpus.ensure_layout(root)


@pytest.fixture
def index(corpus_root):
    conn = corpus.open_index(corpus_root)
    yield conn
    conn.close()

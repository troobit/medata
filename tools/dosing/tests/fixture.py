"""Build a SYNTHETIC medata event log for testing `retrospective.py`.

Nothing here is, resembles, or may be reported as the developer's recorded
history. It exists so the tool's arithmetic — pairing, stacking, coverage,
attrition — can be checked against hand-known answers. `specs/data/insulin-dosing`
task 16 is blocked on a human-produced export precisely because no synthetic
substitute is admissible as evidence.

The DDL mirrors the subset of `GRDBPersistenceStore.createSchema` the tool
reads, including the details that break naive readers: `meta` columns are `k`/`v`,
`correction_json` is declared BLOB, and a meal's `metadata.record` is a JSON
STRING nested inside the envelope.
"""

import json
import sqlite3
import uuid

SCHEMA = """
CREATE TABLE events (
    id          TEXT    PRIMARY KEY,
    timestamp   INTEGER NOT NULL,
    event_type  TEXT    NOT NULL,
    value       REAL,
    metadata    TEXT    NOT NULL
);
CREATE INDEX events_timestamp ON events(timestamp);
CREATE TABLE corrections (
    meal_id         TEXT NOT NULL,
    created_at      INTEGER NOT NULL,
    correction_json BLOB NOT NULL,
    PRIMARY KEY (meal_id, created_at)
);
CREATE TABLE meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
"""

MINUTE = 60_000
HOUR = 60 * MINUTE


def new_id():
    return str(uuid.uuid4())


def meal_metadata(carbs_g=None, sigma=None, fat_g=None, protein_g=None,
                  clinical=True, palette_version="v0"):
    """The two-key envelope, with proto3 default omission applied.

    A field equal to its proto3 default is ABSENT from SwiftProtobuf's JSON, so
    passing None here omits the key rather than writing a zero.
    """
    record = {"id": new_id()}
    macros = {}
    if carbs_g is not None:
        macros["totalCarbsG"] = carbs_g
    if clinical:
        totals = {}
        if fat_g is not None:
            totals["fatG"] = fat_g
        if protein_g is not None:
            totals["proteinG"] = protein_g
        macros["clinicalTotals"] = totals
    if macros:
        record["macros"] = macros
    if sigma is not None:
        record["confidence"] = {"sigmaMeal": sigma}
    return json.dumps({"record": json.dumps(record),
                       "palette_version": palette_version})


def insulin_metadata(kind="bolus", insulin_type="NovoRapid"):
    return json.dumps({"kind": kind, "insulin_type": insulin_type,
                       "schema_version": 1})


def bsl_metadata(source_id="librelinkup", native_instant_ms=0):
    return json.dumps({"source_id": source_id,
                       "native_instant_ms": native_instant_ms})


def screenshot_metadata():
    return json.dumps({"source_hash": "sha256:0" * 1, "source_file": "shot.png",
                       "view": "daily24h"})


def intake_metadata(source="manual", subtype="carb"):
    return json.dumps({"subtype": subtype, "schema_version": 1, "source": source})


class FixtureBuilder:
    def __init__(self, path):
        self.path = str(path)
        self.rows = []
        self.corrections = []

    def event(self, event_type, timestamp_ms, value, metadata, event_id=None):
        event_id = event_id or new_id()
        self.rows.append((event_id, int(timestamp_ms), event_type, value, metadata))
        return event_id

    def meal(self, timestamp_ms, carbs_g, **kwargs):
        return self.event(
            "meal", timestamp_ms, carbs_g,
            meal_metadata(carbs_g=carbs_g, **kwargs))

    def intake(self, timestamp_ms, carbs_g, **kwargs):
        return self.event("intake", timestamp_ms, carbs_g, intake_metadata(**kwargs))

    def bolus(self, timestamp_ms, units):
        return self.event("insulin", timestamp_ms, units, insulin_metadata("bolus"))

    def basal(self, timestamp_ms, units):
        return self.event("insulin", timestamp_ms, units, insulin_metadata("basal"))

    def bsl(self, timestamp_ms, mmol, metadata=None):
        return self.event("bsl", timestamp_ms, mmol,
                          metadata or bsl_metadata(native_instant_ms=int(timestamp_ms)))

    def bsl_series(self, start_ms, end_ms, step_min, mmol=6.0, metadata=None):
        stamp = start_ms
        while stamp <= end_ms:
            self.bsl(stamp, mmol, metadata)
            stamp += step_min * MINUTE

    def correction(self, meal_id, created_at_ms, corrected_carbs_g):
        self.corrections.append(
            (meal_id, int(created_at_ms),
             json.dumps({"createdAtMs": str(int(created_at_ms)),
                         "correctedTotalCarbsG": corrected_carbs_g})))

    def write(self):
        db = sqlite3.connect(self.path)
        try:
            db.executescript(SCHEMA)
            db.executemany(
                "INSERT INTO events (id, timestamp, event_type, value, metadata) "
                "VALUES (?,?,?,?,?)", self.rows)
            db.executemany(
                "INSERT INTO corrections (meal_id, created_at, correction_json) "
                "VALUES (?,?,?)", self.corrections)
            db.execute("INSERT INTO meta (k, v) VALUES ('schema_version', '7')")
            db.commit()
        finally:
            db.close()
        return self.path

"""Bake persistence of the cross-dataset provenance fields (Req 6.1/7.2,
specs/estimation/cross-dataset-calibration).

The calibrate artifact's per-class entries gain ``contributing_datasets``
({dataset: weighted sample count}) and ``single_source_uncorroborated``
(cross-dataset-calibration task 11). The bake persists them as meta JSON
dicts — ``calibration_contributing_datasets_per_class`` and
``calibration_single_source_classes`` — so every baked β's data source and
corroboration status survives into the shipped DB (Req 6.1).

Additive only (Req 7.2): an artifact without the new keys (the current
N5k-only shape) bakes exactly as before with neither meta key present,
and the palette-to-DB edition lock still gates the calibrated path.
"""

import json
import sqlite3

import pytest

import generate

from test_calibrated_bake import LINEAGE, artifact, entry, out_dir  # noqa: F401


def bake_with(out_dir, art) -> str:
    path = out_dir / "calibration.json"
    path.write_text(json.dumps(art))
    generate.bake(calibration_json=str(path))
    return generate.COFID_DB


def meta(db_path):
    conn = sqlite3.connect(db_path)
    try:
        return dict(conn.execute("SELECT k, v FROM meta").fetchall())
    finally:
        conn.close()


def cross_dataset_entry(beta, *, contributing, single_source, **kw):
    e = entry(beta, **kw)
    e["contributing_datasets"] = contributing
    e["single_source_uncorroborated"] = single_source
    return e


# --- Req 6.1: provenance meta dicts persisted ---

def test_contributing_datasets_persisted_per_class(out_dir):
    db = bake_with(out_dir, artifact({
        "white_rice": cross_dataset_entry(
            0.82, contributing={"metafood3d": 34}, single_source=True),
        "broccoli": cross_dataset_entry(
            0.91, contributing={"nutrition5k": 41, "metafood3d": 12},
            single_source=False),
    }))
    persisted = json.loads(
        meta(db)["calibration_contributing_datasets_per_class"])
    assert persisted == {
        "white_rice": {"metafood3d": 34},
        "broccoli": {"nutrition5k": 41, "metafood3d": 12},
    }


def test_single_source_classes_persisted_sorted(out_dir):
    db = bake_with(out_dir, artifact({
        "white_rice": cross_dataset_entry(
            0.82, contributing={"metafood3d": 34}, single_source=True),
        "pasta": cross_dataset_entry(
            0.88, contributing={"metafood3d": 31}, single_source=True),
        "broccoli": cross_dataset_entry(
            0.91, contributing={"nutrition5k": 41, "metafood3d": 12},
            single_source=False),
    }))
    flagged = json.loads(meta(db)["calibration_single_source_classes"])
    assert flagged == ["pasta", "white_rice"]


def test_both_meta_dicts_land_in_both_databases(out_dir):
    bake_with(out_dir, artifact({
        "white_rice": cross_dataset_entry(
            0.82, contributing={"metafood3d": 34}, single_source=True),
    }))
    for db in (generate.COFID_DB, generate.AFCD_DB):
        m = meta(db)
        assert "calibration_contributing_datasets_per_class" in m
        assert "calibration_single_source_classes" in m


# --- Req 7.2: additive — the pre-cross-dataset artifact shape is untouched ---

def test_artifact_without_new_keys_bakes_without_the_meta_dicts(out_dir):
    db = bake_with(out_dir, artifact({"white_rice": entry(0.82)}))
    m = meta(db)
    assert "calibration_contributing_datasets_per_class" not in m
    assert "calibration_single_source_classes" not in m
    # And the row itself bakes exactly as before.
    conn = sqlite3.connect(db)
    try:
        beta, status = conn.execute(
            "SELECT beta, beta_status FROM foods WHERE class_id = ?",
            ("white_rice",)).fetchone()
    finally:
        conn.close()
    assert beta == pytest.approx(0.82)
    assert status == "calibrated"


def test_mixed_artifact_persists_only_carrying_classes(out_dir):
    # Entries without the new keys coexist with entries carrying them
    # (single-dataset classes merged by an older-style path).
    db = bake_with(out_dir, artifact({
        "white_rice": cross_dataset_entry(
            0.82, contributing={"metafood3d": 34}, single_source=True),
        "pasta": entry(0.88),
    }))
    persisted = json.loads(
        meta(db)["calibration_contributing_datasets_per_class"])
    assert persisted == {"white_rice": {"metafood3d": 34}}
    assert json.loads(meta(db)["calibration_single_source_classes"]) == \
        ["white_rice"]


# --- Req 7.2: the palette-to-DB edition lock still holds ---

def test_palette_lock_still_gates_the_cross_dataset_bake(out_dir, monkeypatch):
    monkeypatch.setattr(generate, "PALETTE_VERSION", "v9-drifted")
    with pytest.raises(SystemExit, match="palette"):
        bake_with(out_dir, artifact({
            "white_rice": cross_dataset_entry(
                0.82, contributing={"metafood3d": 34}, single_source=True),
        }))


def test_palette_version_meta_stays_v2(out_dir):
    db = bake_with(out_dir, artifact({
        "white_rice": cross_dataset_entry(
            0.82, contributing={"metafood3d": 34}, single_source=True),
    }))
    assert meta(db)["palette_version"] == "v2"

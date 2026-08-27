"""Loop-overlay consumption in the bake (ml-feedback-loop Req 5.1/5.2).

``tools/food_db/loop_overlay.json`` is the ONLY file the feedback loop may
auto-edit: a provenance-tagged input to this generator whose values carry
``LOOP_OVERLAY`` provenance, distinct from CoFID/AFCD/calibration. It is read
from a fixed committed path **by default**, not behind an opt-in flag — an
opt-in overlay would silently regenerate the DB without landed fixes on any
plain invocation — with the fail-closed inverse guard that a prior DB carrying
``LOOP_OVERLAY`` provenance and no overlay file present aborts the bake.

Ordering is the load-bearing part (Decision 18): the overlay applies to the
in-memory rows BEFORE INSERT and BEFORE ``_apply_calibration``, because β is
fitted against the source densities. Any class whose density or composition
the overlay touches therefore has its β invalidated to
``uncalibrated_overlay_base`` and is skipped by the calibration application
until a human refit. β, the palette, and the class set are outside the overlay
by construction.

These tests bake into a temp dir with ``OVERLAY_JSON`` redirected there, so the
committed artifact and the committed overlay path are never touched.
"""

import json
import sqlite3
from pathlib import Path

import pytest

import generate

LINEAGE = {
    "n5k_release": "sha256:0f3a-manifest",
    "n5k_metadata_version": "sha256:meta-v1",
    "mapping_artifact_version": "sha256:mapping-v1",
    "tau_route": 0.90,
    "tau_purity": 0.90,
    "tau_eff": 0.15,
    "kappa_stacking": 0.6,
    "seed": 42,
    "effective_sample_per_class": {"white_rice": 44},
    "condition_number": 3.2,
    "identifiable_per_class": {"white_rice": True},
    "pinned_intrinsics_model": "RealSense D435 factory intrinsics @ 640x480",
    "licence": "CC BY 4.0",
}


@pytest.fixture()
def out_dir(tmp_path, monkeypatch, overlay_absent):
    monkeypatch.setattr(generate, "OUTPUT_DIR", str(tmp_path))
    monkeypatch.setattr(generate, "COFID_DB", str(tmp_path / "cofid_db.sqlite"))
    monkeypatch.setattr(generate, "AFCD_DB", str(tmp_path / "afcd_db.sqlite"))
    # Redirect the fixed committed overlay path into the temp dir, AFTER
    # conftest's overlay_absent (named as a dependency so the order is stated,
    # not inherited from autouse ordering): still absent by default, so every
    # test writes the overlay it means to exercise.
    monkeypatch.setattr(generate, "OVERLAY_JSON",
                        str(tmp_path / "loop_overlay.json"))
    return tmp_path


def basis(cause="wrong_density"):
    return {
        "notes": ["notes/2026-08-27T101500Z-3f2a.json"],
        "captures": ["cap_1756290000000", "cap_1756290300000"],
        "cause": cause,
        "rationale": "Three clusters read the stated slice count ~2.6x heavy.",
    }


def entry(class_id="bread_white", column="density", value=0.27, **kw):
    e = {"class_id": class_id, "column": column, "value": value,
         "basis": basis(), "fix_id": f"cycle3-{column}-{class_id}",
         "applied_at": "2026-08-30"}
    e.update(kw)
    return e


def write_overlay(entries):
    Path(generate.OVERLAY_JSON).write_text(json.dumps(entries), encoding="utf-8")


def cal_entry(beta, status="calibrated", provenance="n5k_single_dominant"):
    return {"beta": beta, "status": status, "provenance": provenance,
            "standard_error": 0.05, "effective_sample": 44, "clamped": False,
            "support_plane_reference": generate.SUPPORT_PLANE_REFERENCE_IN_USE}


def write_calibration(out_dir, classes) -> str:
    path = out_dir / "calibration.json"
    path.write_text(json.dumps({
        "betaPool": 0.87, "classes": classes, "lineage": LINEAGE,
        "support_plane_reference": generate.SUPPORT_PLANE_REFERENCE_IN_USE,
    }), encoding="utf-8")
    return str(path)


def food(db_path, class_id):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        return conn.execute("SELECT * FROM foods WHERE class_id = ?",
                            (class_id,)).fetchone()
    finally:
        conn.close()


def rows(db_path, sql, args=()):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        return [dict(r) for r in conn.execute(sql, args).fetchall()]
    finally:
        conn.close()


def meta(db_path):
    conn = sqlite3.connect(db_path)
    try:
        return dict(conn.execute("SELECT k, v FROM meta").fetchall())
    finally:
        conn.close()


# --- default committed path, no opt-in flag (design §Fix application) ---

def test_overlay_at_the_default_path_is_read_without_a_flag(out_dir):
    write_overlay([entry()])
    generate.bake()  # no argument names the overlay — the path is the contract
    assert food(generate.COFID_DB, "bread_white")["density"] == pytest.approx(0.27)


def test_absent_overlay_bakes_the_source_values(out_dir):
    generate.bake()
    row = food(generate.COFID_DB, "bread_white")
    assert row["density"] == pytest.approx(0.38)
    assert row["density_source"] == "MEASURED"
    assert not any(k.startswith("overlay_") for k in meta(generate.COFID_DB))


# --- fail-closed inverse guard (Decision 18) ---

def test_missing_overlay_after_a_loop_bake_aborts(out_dir):
    write_overlay([entry()])
    generate.bake()
    Path(generate.OVERLAY_JSON).unlink()
    with pytest.raises(SystemExit, match="LOOP_OVERLAY"):
        generate.bake()
    # Fail BEFORE write: the prior DB survives intact rather than being
    # replaced by an overlay-free bake.
    assert food(generate.COFID_DB, "bread_white")["density"] == pytest.approx(0.27)


def test_missing_overlay_is_fine_when_no_prior_overlay_provenance(out_dir):
    generate.bake()
    generate.bake()  # must not raise — nothing claims LOOP_OVERLAY
    assert food(generate.COFID_DB, "bread_white")["density"] == pytest.approx(0.38)


def test_side_table_only_overlay_still_arms_the_inverse_guard(out_dir):
    # A servings-only overlay rewrites no foods row, so the guard cannot rely
    # on the foods provenance columns alone.
    write_overlay([entry(class_id="bread_white",
                         column="solid_servings.grams_per_unit", value=44.0)])
    generate.bake()
    Path(generate.OVERLAY_JSON).unlink()
    with pytest.raises(SystemExit, match="LOOP_OVERLAY"):
        generate.bake()


# --- column allowlist (design §Fix application) ---

@pytest.mark.parametrize("column", ["energy_kj_100", "beta", "beta_status",
                                    "name", "device_verified",
                                    "solid_servings.step"])
def test_off_allowlist_column_aborts(out_dir, column):
    write_overlay([entry(column=column, value=1.0)])
    with pytest.raises(SystemExit, match="allowlist"):
        generate.bake()
    assert not Path(generate.COFID_DB).exists()


def test_unknown_class_aborts(out_dir):
    # The class set is outside the overlay by construction.
    write_overlay([entry(class_id="dragonfruit")])
    with pytest.raises(SystemExit, match="unknown class"):
        generate.bake()
    assert not Path(generate.COFID_DB).exists()


# --- physical bounds per allowlisted column (Req 5.2) ---

@pytest.mark.parametrize("column,value", [
    ("density", 0.04),
    ("density", 2.01),
    ("carbs_mono_100", -0.1),
    ("carbs_mono_100", 100.1),
    ("protein_100", 100.1),
    ("fat_100", -1.0),
    ("fibre_100", 100.1),
    ("solid_servings.grams_per_unit", 4.9),
    ("solid_servings.grams_per_unit", 500.1),
])
def test_value_outside_declared_bounds_aborts(out_dir, column, value):
    write_overlay([entry(column=column, value=value)])
    with pytest.raises(SystemExit, match="bounds"):
        generate.bake()
    assert not Path(generate.COFID_DB).exists()


@pytest.mark.parametrize("value", [9.0, 3000.0])
def test_serving_ml_outside_bounds_aborts(out_dir, value):
    write_overlay([entry(class_id="beer", column="liquid_servings.serving_ml",
                         value=value, region="UK", vessel="pint")])
    with pytest.raises(SystemExit, match="bounds"):
        generate.bake()


@pytest.mark.parametrize("value", [0.05, 2.0])
def test_value_on_the_bound_is_accepted(out_dir, value):
    write_overlay([entry(class_id="salad_leaves", value=value)])
    generate.bake()
    assert food(generate.COFID_DB, "salad_leaves")["density"] == pytest.approx(value)


def test_grams_per_unit_respects_the_serving_note_precision_rule(out_dir):
    # 150 g is inside the declared 5-500 physical bound but violates the
    # ServingNote 2-dp round-trip lock, which the overlay does not get to
    # bypass — verify_solid_servings runs on the POST-overlay rows.
    write_overlay([entry(column="solid_servings.grams_per_unit", value=150.0)])
    with pytest.raises(SystemExit, match="grams_per_unit >= 100"):
        generate.bake()
    assert not Path(generate.COFID_DB).exists()


# --- provenance rewrite (Req 5.1) ---

def test_density_override_rewrites_only_density_source(out_dir):
    write_overlay([entry(class_id="white_rice", value=0.61)])
    generate.bake()
    row = food(generate.COFID_DB, "white_rice")
    assert row["density"] == pytest.approx(0.61)
    assert row["density_source"] == "LOOP_OVERLAY"
    assert row["composition_source"] == "CoFID"  # untouched, still honest


def test_composition_override_rewrites_only_composition_source(out_dir):
    write_overlay([entry(class_id="white_rice", column="carbs_mono_100",
                         value=29.5)])
    generate.bake()
    row = food(generate.COFID_DB, "white_rice")
    assert row["carbs_mono_100"] == pytest.approx(29.5)
    assert row["composition_source"] == "LOOP_OVERLAY"
    assert row["density_source"] == "FAO_DENS"
    assert row["density"] == pytest.approx(0.73)


def test_untouched_classes_keep_their_source_values(out_dir):
    write_overlay([entry(class_id="white_rice", value=0.61)])
    generate.bake()
    pasta = food(generate.COFID_DB, "pasta")
    assert pasta["density"] == pytest.approx(0.58)
    assert pasta["density_source"] == "FAO_DENS"


def test_solid_serving_override_rewrites_its_row_only(out_dir):
    write_overlay([entry(column="solid_servings.grams_per_unit", value=44.0)])
    generate.bake()
    served = {r["class_id"]: r for r in rows(
        generate.COFID_DB, "SELECT * FROM solid_servings")}
    assert served["bread_white"]["grams_per_unit"] == pytest.approx(44.0)
    assert served["bread_white"]["source"] == "LOOP_OVERLAY"
    assert served["bread_white"]["unit_singular"] == "slice"  # untouched
    assert served["bread_wholemeal"]["grams_per_unit"] == pytest.approx(36.0)
    assert served["bread_wholemeal"]["source"] != "LOOP_OVERLAY"


def test_liquid_serving_override_is_keyed_by_region_and_vessel(out_dir):
    write_overlay([entry(class_id="beer", column="liquid_servings.serving_ml",
                         value=500.0, region="UK", vessel="pint")])
    generate.bake()
    served = {(r["region"], r["vessel"]): r for r in rows(
        generate.COFID_DB,
        "SELECT * FROM liquid_servings WHERE class_id = 'beer'")}
    assert served[("UK", "pint")]["serving_ml"] == pytest.approx(500.0)
    assert served[("UK", "pint")]["source"] == "LOOP_OVERLAY"
    assert served[("US", "pint")]["serving_ml"] == pytest.approx(473.0)
    assert served[("UK", "half_pint")]["serving_ml"] == pytest.approx(284.0)


def test_liquid_serving_override_without_a_key_aborts(out_dir):
    write_overlay([entry(class_id="beer", column="liquid_servings.serving_ml",
                         value=500.0)])
    with pytest.raises(SystemExit, match="region"):
        generate.bake()


def test_liquid_serving_override_of_a_nonexistent_row_aborts(out_dir):
    write_overlay([entry(class_id="beer", column="liquid_servings.serving_ml",
                         value=500.0, region="US", vessel="mug")])
    with pytest.raises(SystemExit, match="no liquid_servings row"):
        generate.bake()


def test_solid_serving_override_of_a_class_without_a_row_aborts(out_dir):
    write_overlay([entry(class_id="beer",
                         column="solid_servings.grams_per_unit", value=50.0)])
    with pytest.raises(SystemExit, match="no solid_servings row"):
        generate.bake()


# --- β invalidation on touched classes (Decision 18) ---

@pytest.mark.parametrize("column,value", [
    ("density", 0.61),
    ("carbs_mono_100", 29.5),
    ("fibre_100", 0.4),
])
def test_touched_class_beta_is_invalidated(out_dir, column, value):
    write_overlay([entry(class_id="white_rice", column=column, value=value)])
    generate.bake()
    row = food(generate.COFID_DB, "white_rice")
    assert row["beta"] == pytest.approx(1.0)
    assert row["beta_status"] == "uncalibrated_overlay_base"
    assert row["beta_provenance"] == "uncalibrated_overlay_base"


def test_serving_override_does_not_invalidate_beta(out_dir):
    # grams_per_unit is a household unit, not a term in the β fit.
    write_overlay([entry(column="solid_servings.grams_per_unit", value=44.0)])
    generate.bake()
    row = food(generate.COFID_DB, "bread_white")
    assert row["beta_status"] == "uncalibrated_unity"
    assert row["beta_provenance"] == "none"


def test_untouched_class_keeps_its_default_beta_status(out_dir):
    write_overlay([entry(class_id="white_rice", value=0.61)])
    generate.bake()
    assert food(generate.COFID_DB, "pasta")["beta_status"] == "uncalibrated_unity"


# --- overlay applies before _apply_calibration (Decision 18) ---

def test_calibration_is_not_applied_to_an_overlay_touched_class(out_dir, capsys):
    # β fitted against the SOURCE density must not ship on top of an overlay
    # density — that is the corruption the ordering exists to prevent.
    write_overlay([entry(class_id="white_rice", value=0.61)])
    cal = write_calibration(out_dir, {"white_rice": cal_entry(0.82),
                                      "pasta": cal_entry(0.90)})
    generate.bake(calibration_json=cal)
    rice = food(generate.COFID_DB, "white_rice")
    assert rice["density"] == pytest.approx(0.61)
    assert rice["beta"] == pytest.approx(1.0)
    assert rice["beta_status"] == "uncalibrated_overlay_base"
    pasta = food(generate.COFID_DB, "pasta")
    assert pasta["beta"] == pytest.approx(0.90)
    assert pasta["beta_status"] == "calibrated"
    assert "white_rice" in capsys.readouterr().err
    assert json.loads(
        meta(generate.COFID_DB)["calibration_overlay_invalidated_classes"]
    ) == ["white_rice"]


def test_serving_overlay_leaves_calibration_applied(out_dir):
    write_overlay([entry(column="solid_servings.grams_per_unit", value=44.0)])
    cal = write_calibration(out_dir, {"white_rice": cal_entry(0.82)})
    generate.bake(calibration_json=cal)
    assert food(generate.COFID_DB, "white_rice")["beta"] == pytest.approx(0.82)


def test_density_spot_check_message_quotes_the_post_overlay_density(out_dir):
    write_overlay([entry(class_id="white_rice", value=0.61)])
    cal = write_calibration(out_dir, {"white_rice": cal_entry(0.40)})
    with pytest.raises(SystemExit, match=r"DB ρ = 0\.610"):
        generate.bake(calibration_json=cal)


# --- overlay applies to in-memory rows before INSERT ---

def test_module_source_tables_are_not_mutated_by_a_bake(out_dir):
    before_foods = [tuple(r) for r in generate.FOOD_DATA]
    before_solid = [tuple(r) for r in generate.SOLID_SERVINGS]
    before_liquid = [tuple(r) for r in generate.LIQUID_SERVINGS]
    write_overlay([
        entry(class_id="white_rice", value=0.61),
        entry(column="solid_servings.grams_per_unit", value=44.0),
        entry(class_id="beer", column="liquid_servings.serving_ml",
              value=500.0, region="UK", vessel="pint"),
    ])
    generate.bake()
    assert [tuple(r) for r in generate.FOOD_DATA] == before_foods
    assert [tuple(r) for r in generate.SOLID_SERVINGS] == before_solid
    assert [tuple(r) for r in generate.LIQUID_SERVINGS] == before_liquid


def test_afcd_rows_and_meta_carry_no_overlay(out_dir):
    # The overlay targets the CoFID tables the runtime's CoFID-wins COALESCE
    # already prefers; claiming LOOP_OVERLAY on an AFCD row would be a lie.
    write_overlay([entry(class_id="white_rice", value=0.61)])
    generate.bake()
    afcd = food(generate.AFCD_DB, "white_rice")
    assert afcd["density"] == pytest.approx(0.73)
    assert afcd["density_source"] == "AFCD 2024"
    assert not any(k.startswith("overlay_") for k in meta(generate.AFCD_DB))


# --- idempotent re-bake ---

def test_re_baking_the_same_overlay_is_idempotent(out_dir):
    write_overlay([entry(class_id="white_rice", value=0.61),
                   entry(column="solid_servings.grams_per_unit", value=44.0)])
    generate.bake()
    first = (rows(generate.COFID_DB, "SELECT * FROM foods ORDER BY class_id"),
             rows(generate.COFID_DB, "SELECT * FROM solid_servings ORDER BY class_id"),
             meta(generate.COFID_DB))
    generate.bake()
    second = (rows(generate.COFID_DB, "SELECT * FROM foods ORDER BY class_id"),
              rows(generate.COFID_DB, "SELECT * FROM solid_servings ORDER BY class_id"),
              meta(generate.COFID_DB))
    assert first == second


# --- meta lineage (Req 5.1, calibration_* keys precedent) ---

def test_overlay_entries_and_lineage_are_recorded_in_meta(out_dir):
    entries = [entry(class_id="white_rice", value=0.61),
               entry(class_id="pasta", column="carbs_mono_100", value=24.0)]
    write_overlay(entries)
    generate.bake()
    m = meta(generate.COFID_DB)
    assert json.loads(m["overlay_json"]) == entries
    assert json.loads(m["overlay_fix_ids"]) == [
        "cycle3-carbs_mono_100-pasta", "cycle3-density-white_rice"]
    assert json.loads(m["overlay_beta_invalidated_classes"]) == [
        "pasta", "white_rice"]


# --- palette-lock interaction (Req 5.7) ---

def test_palette_lock_aborts_the_overlay_bake_on_version_mismatch(
        out_dir, monkeypatch):
    write_overlay([entry()])
    monkeypatch.setattr(generate, "PALETTE_VERSION", "v9-drifted")
    with pytest.raises(SystemExit, match="palette"):
        generate.bake()
    assert not Path(generate.COFID_DB).exists()


# --- malformed overlay files (fail before write) ---

def test_overlay_that_is_not_a_list_aborts(out_dir):
    Path(generate.OVERLAY_JSON).write_text(
        json.dumps({"class_id": "bread_white"}), encoding="utf-8")
    with pytest.raises(SystemExit, match="list of entries"):
        generate.bake()


@pytest.mark.parametrize("key", ["class_id", "column", "value", "fix_id",
                                 "basis", "applied_at"])
def test_entry_missing_a_required_key_aborts(out_dir, key):
    e = entry()
    del e[key]
    write_overlay([e])
    with pytest.raises(SystemExit, match=key):
        generate.bake()


def test_entry_citing_neither_notes_nor_captures_aborts(out_dir):
    # Req 5.1: every auto-applied fix cites the notes and captures that
    # motivated it — an uncited value change must not bake.
    write_overlay([entry(basis={"notes": [], "captures": [],
                                "cause": "wrong_density",
                                "rationale": "hunch"})])
    with pytest.raises(SystemExit, match="cite"):
        generate.bake()


@pytest.mark.parametrize("bad", ["0.27", None, True, [0.27]])
def test_non_numeric_value_aborts(out_dir, bad):
    write_overlay([entry(value=bad)])
    with pytest.raises(SystemExit, match="numeric"):
        generate.bake()


def test_two_entries_targeting_the_same_cell_abort(out_dir):
    write_overlay([entry(value=0.27), entry(value=0.31)])
    with pytest.raises(SystemExit, match="twice"):
        generate.bake()


def test_same_class_different_columns_is_allowed(out_dir):
    write_overlay([entry(class_id="white_rice", value=0.61),
                   entry(class_id="white_rice", column="carbs_mono_100",
                         value=29.5)])
    generate.bake()
    row = food(generate.COFID_DB, "white_rice")
    assert row["density"] == pytest.approx(0.61)
    assert row["carbs_mono_100"] == pytest.approx(29.5)
    assert row["density_source"] == "LOOP_OVERLAY"
    assert row["composition_source"] == "LOOP_OVERLAY"

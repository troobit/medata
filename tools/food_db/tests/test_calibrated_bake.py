"""Bake consumption of the calibrate JSON artifact (Req 1.5/5.2-5.7).

The JSON artifact written by ``HarnessCLI calibrate`` is the SOLE interface
between the Swift harness (stream B) and this bake (stream C) — design §DB
bake handoff contract. The fixtures here are hand-written to that contract
(betaPool / classes / lineage / run_summary keys as encoded by
CalibrationArtifact.swift); they deliberately do not depend on the harness.

Covered: per-row β/status/provenance with device_verified defaulting 0 (5.4);
clamped class -> calibration-quality warning, never silent acceptance (5.6);
mixture -> single-dominant supersession recorded in lineage meta, read from
the PRIOR DB (5.2); density-basis spot-check aborting on rice/pasta (5.3);
lineage meta incl. pinned intrinsics model and licence CC BY 4.0 (1.5/5.5);
palette lock running on the calibrated path (5.7).
"""

import json
import sqlite3

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
    "effective_sample_per_class": {"white_rice": 44, "pasta": 31},
    "condition_number": 3.2,
    "identifiable_per_class": {"white_rice": True, "pasta": True},
    "pinned_intrinsics_model": "RealSense D435 factory intrinsics @ 640x480",
    "licence": "CC BY 4.0",
}


def entry(beta, status="calibrated", provenance="n5k_mixture",
          standard_error=0.05, effective_sample=44, clamped=False,
          support_plane_reference=generate.SUPPORT_PLANE_REFERENCE_IN_USE):
    return {"beta": beta, "status": status, "provenance": provenance,
            "standard_error": standard_error,
            "effective_sample": effective_sample, "clamped": clamped,
            "support_plane_reference": support_plane_reference}


def artifact(classes, beta_pool=0.87, lineage=LINEAGE,
             support_plane_reference=generate.SUPPORT_PLANE_REFERENCE_IN_USE):
    art = {"betaPool": beta_pool, "classes": classes, "lineage": lineage}
    art["support_plane_reference"] = support_plane_reference
    return art


@pytest.fixture()
def out_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(generate, "OUTPUT_DIR", str(tmp_path))
    monkeypatch.setattr(generate, "COFID_DB", str(tmp_path / "cofid_db.sqlite"))
    monkeypatch.setattr(generate, "AFCD_DB", str(tmp_path / "afcd_db.sqlite"))
    return tmp_path


def bake_with(out_dir, art) -> str:
    path = out_dir / "calibration.json"
    path.write_text(json.dumps(art))
    generate.bake(calibration_json=str(path))
    return generate.COFID_DB


def fetch(db_path, class_id):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        return conn.execute(
            "SELECT beta, beta_status, beta_provenance, device_verified "
            "FROM foods WHERE class_id = ?", (class_id,)).fetchone()
    finally:
        conn.close()


def meta(db_path):
    conn = sqlite3.connect(db_path)
    try:
        return dict(conn.execute("SELECT k, v FROM meta").fetchall())
    finally:
        conn.close()


# --- default path unchanged (task 28: no flag, no behaviour change) ---

def test_without_json_defaults_unchanged(out_dir):
    generate.bake()
    row = fetch(generate.COFID_DB, "white_rice")
    assert row["beta"] == pytest.approx(1.0)
    assert row["beta_status"] == "uncalibrated_unity"
    assert row["beta_provenance"] == "none"
    assert row["device_verified"] == 0
    assert not any(k.startswith("calibration_") for k in meta(generate.COFID_DB))


# --- per-row bake (Req 5.4) ---

def test_calibrated_rows_written_with_device_verified_zero(out_dir):
    db = bake_with(out_dir, artifact({
        "white_rice": entry(0.82, provenance="n5k_mixture"),
        "pasta": entry(0.87, status="uncalibrated_pooled", provenance="none",
                       standard_error=None, effective_sample=3),
    }))
    rice = fetch(db, "white_rice")
    assert rice["beta"] == pytest.approx(0.82)
    assert rice["beta_status"] == "calibrated"
    assert rice["beta_provenance"] == "n5k_mixture"
    assert rice["device_verified"] == 0  # only the device-spot-check spec flips it
    pasta = fetch(db, "pasta")
    assert pasta["beta"] == pytest.approx(0.87)
    assert pasta["beta_status"] == "uncalibrated_pooled"
    assert pasta["beta_provenance"] == "none"
    # A class the JSON does not mention keeps its uncalibrated defaults.
    chicken = fetch(db, "chicken")
    assert chicken["beta"] == pytest.approx(1.0)
    assert chicken["beta_status"] == "uncalibrated_unity"


# --- support-plane reference guard (support-plane-reference Req 5.3/5.4) ---

def test_absent_support_plane_reference_blocks_the_bake(out_dir):
    # Absent must BLOCK, not permit. Every artifact produced before the
    # support-plane-reference feature records none, and those are exactly the
    # ones calibrated above the table — the basis that over-reads ~3x.
    art = artifact({"white_rice": entry(0.82)})
    del art["support_plane_reference"]
    with pytest.raises(SystemExit, match="no 'support_plane_reference'"):
        bake_with(out_dir, art)


def test_null_support_plane_reference_blocks_the_bake(out_dir):
    # The Swift writer encodes the absent case as an explicit null rather than
    # omitting the key, so both spellings have to be refused.
    with pytest.raises(SystemExit, match="no 'support_plane_reference'"):
        bake_with(out_dir, artifact({"white_rice": entry(0.82)},
                                    support_plane_reference=None))


def test_mismatched_support_plane_reference_blocks_the_bake(out_dir):
    with pytest.raises(SystemExit, match="support-plane reference"):
        bake_with(out_dir, artifact({"white_rice": entry(0.82)},
                                    support_plane_reference="edgeBand"))


def test_class_fitted_under_another_reference_is_not_applied(out_dir, capsys):
    # A single artifact spans two references by construction: the mixture path
    # keeps the plate-region flood fill permanently (Decision 17). The
    # off-reference class keeps its uncalibrated default and is reported.
    db = bake_with(out_dir, artifact({
        "white_rice": entry(0.82),
        "pasta": entry(0.60, support_plane_reference="plateRegion"),
    }))
    assert fetch(db, "white_rice")["beta"] == pytest.approx(0.82)
    pasta = fetch(db, "pasta")
    assert pasta["beta"] == pytest.approx(1.0)
    assert pasta["beta_status"] == "uncalibrated_unity"
    assert "pasta" in capsys.readouterr().err
    assert json.loads(
        meta(db)["calibration_reference_skipped_classes"].replace("'", '"')
    ) == ["pasta"]


def test_support_plane_reference_recorded_in_meta(out_dir):
    db = bake_with(out_dir, artifact({"white_rice": entry(0.82)}))
    assert (meta(db)["calibration_support_plane_reference"]
            == generate.SUPPORT_PLANE_REFERENCE_IN_USE)


def test_unknown_class_in_json_aborts(out_dir):
    with pytest.raises(SystemExit, match="unknown class"):
        bake_with(out_dir, artifact({"dragonfruit": entry(0.9)}))


def test_liquid_class_beta_in_json_aborts(out_dir):
    # Liquids never enter the β fit (Req 4.7); a mis-keyed artifact carrying
    # a liquid β must not bake.
    with pytest.raises(SystemExit, match="liquid"):
        bake_with(out_dir, artifact({"beer": entry(0.9)}))


@pytest.mark.parametrize("key", ["licence", "pinned_intrinsics_model"])
def test_missing_mandatory_lineage_key_aborts(out_dir, key):
    # Req 1.5/5.5: these are SHALL-record lineage values — a missing key
    # aborts rather than silently baking an unattributed DB.
    lineage = {k: v for k, v in LINEAGE.items() if k != key}
    with pytest.raises(SystemExit, match=key):
        bake_with(out_dir, artifact({"white_rice": entry(0.82)},
                                    lineage=lineage))


# --- lineage meta (Req 1.5/5.5) ---

def test_lineage_recorded_in_meta(out_dir):
    db = bake_with(out_dir, artifact({"white_rice": entry(0.82)}))
    m = meta(db)
    assert m["calibration_licence"] == "CC BY 4.0"
    assert m["calibration_pinned_intrinsics_model"] == \
        LINEAGE["pinned_intrinsics_model"]
    assert m["calibration_n5k_release"] == LINEAGE["n5k_release"]
    assert m["calibration_mapping_artifact_version"] == \
        LINEAGE["mapping_artifact_version"]
    assert float(m["calibration_tau_purity"]) == pytest.approx(0.90)
    assert int(m["calibration_seed"]) == 42
    assert json.loads(m["calibration_effective_sample_per_class"]) == \
        LINEAGE["effective_sample_per_class"]
    assert json.loads(m["calibration_identifiable_per_class"]) == \
        LINEAGE["identifiable_per_class"]
    assert float(m["calibration_condition_number"]) == pytest.approx(3.2)
    # Per-class SE travels into lineage so the 5.4 gate stays auditable.
    se = json.loads(m["calibration_standard_error_per_class"])
    assert se["white_rice"] == pytest.approx(0.05)


# --- clamp warning (Req 5.6) ---

def test_clamped_class_warns_and_is_recorded(out_dir, capsys):
    db = bake_with(out_dir, artifact({
        "white_rice": entry(1.5, clamped=True),
    }))
    err = capsys.readouterr().err
    assert "calibration-quality warning" in err
    assert "white_rice" in err
    # Not silently REJECTED either — the clamped value bakes, with the warning.
    assert fetch(db, "white_rice")["beta"] == pytest.approx(1.5)
    assert "white_rice" in json.loads(meta(db)["calibration_clamped_classes"])


# --- supersession (Req 5.2) ---

def test_single_dominant_supersedes_prior_mixture_in_lineage(out_dir):
    # First bake: mixture β. The JSON carries no prior-bake state — generate.py
    # must read the prior DB itself.
    bake_with(out_dir, artifact({"white_rice": entry(0.82,
                                                     provenance="n5k_mixture")}))
    db = bake_with(out_dir, artifact({
        "white_rice": entry(0.79, provenance="n5k_single_dominant"),
    }))
    supersessions = json.loads(meta(db)["calibration_supersessions"])
    assert {"class_id": "white_rice",
            "from": "n5k_mixture",
            "to": "n5k_single_dominant"} in supersessions
    assert fetch(db, "white_rice")["beta_provenance"] == "n5k_single_dominant"


def test_no_supersession_recorded_without_prior_mixture(out_dir):
    db = bake_with(out_dir, artifact({"white_rice": entry(0.82)}))
    assert json.loads(meta(db)["calibration_supersessions"]) == []


# --- density-basis spot-check (Req 5.3) ---

@pytest.mark.parametrize("class_id", ["white_rice", "pasta"])
def test_density_spot_check_aborts_on_basis_error(out_dir, class_id):
    # The fit's implied density is ρ_DB × β, so a cooked/dry basis mismatch
    # (2-3× on rice/pasta) surfaces as an extreme β. The spot-check IS the
    # Req 5.3 assert: outside tolerance, the bake must abort, not warn.
    with pytest.raises(SystemExit, match="density"):
        bake_with(out_dir, artifact({class_id: entry(0.4)}))
    # Nothing may have been written by the aborted bake.
    assert not (out_dir / "cofid_db.sqlite").exists()


def test_density_spot_check_passes_plausible_bulk_correction(out_dir):
    db = bake_with(out_dir, artifact({"white_rice": entry(0.75)}))
    assert fetch(db, "white_rice")["beta"] == pytest.approx(0.75)


# --- palette lock on the calibrated path (Req 5.7) ---

def test_palette_lock_aborts_calibrated_bake_on_version_mismatch(
        out_dir, monkeypatch):
    monkeypatch.setattr(generate, "PALETTE_VERSION", "v9-drifted")
    with pytest.raises(SystemExit, match="palette"):
        bake_with(out_dir, artifact({"white_rice": entry(0.82)}))

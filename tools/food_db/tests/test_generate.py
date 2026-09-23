"""Regression tests for food-DB staple densities (bugfix: food-db-staple-density-fao-bulk).

Bug: tools/food_db/generate.py shipped granular/piled staples (rice, pasta,
boiled potato, lentils) with near-1.0 *material/grain* densities mislabeled
FAO_DENS. The `density` column is contractually a served-portion *bulk* density
(generate.py schema line; FoodEntry.swift), which for a pile must include the
inter-grain air captured by the visual hull. The inflated values over-count mass
~1.4-1.9x on exactly the carb-priority classes that dominate the estimate, and
because beta ships at 1.0 (uncalibrated_unity) that error flows straight through.

Verified 2026-06-30 against FAO/INFOODS Density DB v2.0 (2012):
  white_rice 0.73, pasta 0.55-0.59, potato_boiled 0.59, lentils 0.85.

These tests read the committed cofid_db.sqlite, so they only pass once
generate.py is corrected AND the database is re-baked.
"""

import sqlite3

import pytest

# Granular / piled staples: the visual hull of a served pile includes inter-grain
# air, so served-portion bulk density is well below material density (~1.0).
PILED_STAPLES = {"white_rice", "brown_rice", "pasta", "potato_boiled", "lentils"}

# Carb-priority classes whose corrected bulk densities are FAO-verifiable.
# (brown_rice has no comparable FAO v2.0 cooked entry; checked separately.)
FAO_BULK_EXPECTED = {
    "white_rice": 0.73,
    "pasta": 0.58,        # FAO range 0.55-0.59
    "potato_boiled": 0.59,
    "lentils": 0.85,
}

# Contiguous solids: FAO/INFOODS v2.0 has no comparable cooked entry, so they
# must NOT carry the FAO_DENS provenance label.
CONTIGUOUS_SOLIDS = {"chicken", "beef", "pork", "fish_white", "egg", "cheese",
                     "potato_mashed", "apple", "banana", "tomato"}


@pytest.fixture(scope="session")
def rows(cofid_db_path):
    conn = sqlite3.connect(cofid_db_path)
    try:
        cur = conn.execute("SELECT class_id, density, density_source FROM foods")
        return {r[0]: {"density": r[1], "source": r[2]} for r in cur.fetchall()}
    finally:
        conn.close()


@pytest.mark.parametrize("class_id,expected", FAO_BULK_EXPECTED.items())
def test_carb_priority_staples_match_fao_bulk_density(rows, class_id, expected):
    # Expected (FAO bulk) vs actual (shipped). Pre-fix the shipped values are
    # ~1.0-1.08, so this fails until generate.py is corrected and re-baked.
    actual = rows[class_id]["density"]
    assert actual == pytest.approx(expected, abs=0.03), (
        f"{class_id} density {actual} should be FAO served-portion bulk ~{expected}"
    )


def test_no_piled_staple_keeps_material_density(rows):
    # Material/grain density is ~1.0; a served pile must be well below that.
    for class_id in PILED_STAPLES:
        density = rows[class_id]["density"]
        assert density < 0.90, (
            f"{class_id} density {density} looks like material density, not "
            f"served-portion bulk density"
        )


def test_fao_dens_label_only_on_bulk_regime_values(rows):
    # A row may keep the FAO_DENS label only if its value is in the FAO bulk
    # regime. This catches near-1.0 values masquerading as FAO densities.
    for class_id, row in rows.items():
        if row["source"] == "FAO_DENS":
            assert row["density"] <= 0.85, (
                f"{class_id} is labeled FAO_DENS but density {row['density']} is "
                f"above the FAO bulk regime"
            )


def test_contiguous_solids_not_labeled_fao(rows):
    # FAO v2.0 has no comparable cooked entry for these, so the FAO_DENS
    # provenance was unverifiable and must be corrected to an honest source.
    for class_id in CONTIGUOUS_SOLIDS:
        assert rows[class_id]["source"] != "FAO_DENS", (
            f"{class_id} has no FAO v2.0 cooked entry; density_source must not "
            f"claim FAO_DENS"
        )


def test_density_fix_does_not_touch_nutrition(cofid_db_path):
    # The fix is density-only: nutrition coefficients and beta are unchanged.
    conn = sqlite3.connect(cofid_db_path)
    try:
        carbs, energy, beta, beta_status = conn.execute(
            "SELECT carbs_mono_100, energy_kj_100, beta, beta_status "
            "FROM foods WHERE class_id = 'white_rice'"
        ).fetchone()
    finally:
        conn.close()
    assert carbs == pytest.approx(32.0)
    assert energy == pytest.approx(580.0)
    assert beta == pytest.approx(1.0)
    assert beta_status == "uncalibrated_unity"

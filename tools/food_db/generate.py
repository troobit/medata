#!/usr/bin/env python3
"""
Generate cofid_db.sqlite and afcd_db.sqlite from authoritative source data.

Sources:
  - McCance & Widdowson CoFID (Crown Copyright, OGL v3)
    https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid
  - Australian Food Composition Database (AFCD, FSANZ, CC-BY-4.0)
    https://www.foodstandards.gov.au/science/monitoringnutrients/afcd
  - FAO/INFOODS Density Table for Cooked Foods (2012)
  - Dehais et al. 2017, Table II — bulk correction factors for visual-hull estimation
  - FSAI monosaccharide-equivalent conversion guidance

Output files are bundled in the app binary per Decision 27 and Decision 39.
Both databases use the same schema and are queried by `class_id` via ATTACH +
COALESCE with CoFID-wins priority (design §4.1). AFCD provides values for
classes CoFID does not cover; it is NOT a regional overlay.

Run from repo root: python3 tools/food_db/generate.py

Requirements: python3 (no external deps beyond stdlib sqlite3)
"""

import argparse
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

OUTPUT_DIR = "MedataCore/Sources/Foods/Resources"
COFID_DB  = os.path.join(OUTPUT_DIR, "cofid_db.sqlite")
AFCD_DB = os.path.join(OUTPUT_DIR, "afcd_db.sqlite")

# Palette edition this bake stamps into meta.palette_version. It MUST equal
# ClassPalette.version (the Swift single source of truth); verify_palette_lock
# enforces that before any DB is written (Req 8.4 / design §3.6 bake lock).
PALETTE_VERSION = "v1"

_REPO_ROOT = Path(__file__).resolve().parents[2]
_CLASS_PALETTE_SWIFT = _REPO_ROOT / "MedataCore/Sources/Segmentation/ClassPalette.swift"


def class_palette_version() -> str:
    """Read ClassPalette.version from v1Standard in ClassPalette.swift.

    The lock tracks the Swift source directly rather than a duplicated constant so
    a future palette bump there forces this bake to be reconciled rather than
    silently shipping a stale-edition DB.
    """
    text = _CLASS_PALETTE_SWIFT.read_text()
    match = re.search(r'version:\s*"([^"]+)"', text)
    if match is None:
        raise SystemExit(
            f"could not read ClassPalette.version from {_CLASS_PALETTE_SWIFT}"
        )
    return match.group(1)


def palette_class_list() -> list:
    """Ordered palette content from ClassPalette.swift v1Standard: foodClasses
    then liquidClasses, declaration order, sentinels excluded — the same
    regex-read pattern as class_palette_version (design §DB bake)."""
    text = _CLASS_PALETTE_SWIFT.read_text()
    marker = text.find("v1Standard")
    if marker < 0:
        raise SystemExit(f"no v1Standard palette found in {_CLASS_PALETTE_SWIFT}")
    body = text[marker:]

    def class_array(name: str) -> list:
        match = re.search(rf"{name}:\s*\[(.*?)\]", body, re.DOTALL)
        if match is None:
            raise SystemExit(
                f"could not parse the {name} class list from {_CLASS_PALETTE_SWIFT}"
            )
        classes = re.findall(r'"([^"]+)"', match.group(1))
        if not classes:
            raise SystemExit(
                f"{name} class list parsed empty from {_CLASS_PALETTE_SWIFT}"
            )
        return classes

    return class_array("foodClasses") + class_array("liquidClasses")


def verify_palette_lock(baked_palette_version: str) -> None:
    """Fail the bake when the DB edition would diverge from the segmenter palette
    (Req 8.4). A mismatch means the class indexing the DB is keyed by no longer
    matches the palette the model emits — shipping it would mis-key every lookup.

    Decision 23 redefined v1 in place, so the label alone can no longer detect
    palette drift: the lock also asserts FOOD_DATA's class ids equal the ordered
    class list in ClassPalette.swift exactly (Req 5.7/7.2 content check).
    """
    expected = class_palette_version()
    if baked_palette_version != expected:
        raise SystemExit(
            f"palette/DB edition mismatch: baking palette_version "
            f"'{baked_palette_version}' but ClassPalette.version is '{expected}' "
            f"({_CLASS_PALETTE_SWIFT}). Bake aborted (Req 8.4)."
        )
    expected_classes = palette_class_list()
    baked_classes = [row[0] for row in FOOD_DATA]
    if baked_classes != expected_classes:
        raise SystemExit(
            "palette/DB content mismatch: FOOD_DATA's class ids do not match "
            f"the ordered class list in {_CLASS_PALETTE_SWIFT} (the 'v1' label "
            "no longer changes when the palette does — Decision 23). "
            "Bake aborted (Req 5.7/7.2)."
        )

# Closed region/vessel vocabulary for canonical liquid servings (Req 7.4/7.7).
# Enforced as CHECK constraints so an out-of-vocabulary row cannot exist —
# a lookup miss is then a hard error in the consumer, never a silent zero.
LIQUID_REGIONS = ("UK", "US")
LIQUID_VESSELS = ("pint", "half_pint", "can_330", "can_440",
                  "glass", "mug", "bowl")


def _sql_vocab(values: tuple) -> str:
    return ", ".join(f"'{v}'" for v in values)


SCHEMA_FOODS = f"""
CREATE TABLE IF NOT EXISTS foods (
    class_id          TEXT PRIMARY KEY,
    name              TEXT NOT NULL,
    density           REAL NOT NULL,       -- g/cm³ (served-portion bulk density)
    energy_kj_100     REAL NOT NULL,       -- kJ per 100 g
    carbs_mono_100    REAL NOT NULL,       -- monosaccharide-equiv carbs per 100 g
    protein_100       REAL NOT NULL,       -- g per 100 g
    fat_100           REAL NOT NULL,       -- g per 100 g
    fibre_100         REAL NOT NULL,       -- AOAC fibre per 100 g
    beta              REAL NOT NULL DEFAULT 1.0,
    beta_status       TEXT NOT NULL DEFAULT 'uncalibrated_unity',
    density_source    TEXT NOT NULL,
    composition_source TEXT NOT NULL,
    beta_provenance   TEXT NOT NULL DEFAULT 'none',   -- Req 5.4: n5k_single_dominant | n5k_mixture | gravimetric | none
    device_verified   INTEGER NOT NULL DEFAULT 0      -- Req 8.1: flipped only by the future device-spot-check spec
);
CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
-- Canonical serving volumes are region-dependent (UK vs US pint), so they are
-- a separate table keyed (class, region, vessel) — never a foods column (Req 7.7).
CREATE TABLE IF NOT EXISTS liquid_servings (
    class_id   TEXT NOT NULL,
    region     TEXT NOT NULL CHECK (region IN ({_sql_vocab(LIQUID_REGIONS)})),
    vessel     TEXT NOT NULL CHECK (vessel IN ({_sql_vocab(LIQUID_VESSELS)})),
    serving_ml REAL NOT NULL,
    source     TEXT NOT NULL,
    PRIMARY KEY (class_id, region, vessel)
);
-- Best-effort sub-class densities (Req 7.5, Decision 24): sub-classes are DB
-- rows, never palette channels; LiquidResolver falls back to the coarse foods
-- row when the sub-class is uncertain.
CREATE TABLE IF NOT EXISTS liquid_subclasses (
    class_id       TEXT NOT NULL,
    sub_class      TEXT NOT NULL,
    carbs_mono_100 REAL NOT NULL,
    density        REAL NOT NULL,
    source         TEXT NOT NULL,
    PRIMARY KEY (class_id, sub_class)
);
"""

SCHEMA_AFCD = SCHEMA_FOODS  # AFCD uses the same schema as CoFID; values may differ

# 24 solid food classes + 8 coarse liquid classes co-curated with the
# segmenter palette (ClassPalette.v1Standard: foodClasses then liquidClasses,
# declaration order — the channel order is load-bearing).
# Values: (class_id, name, density g/cm³, energy kJ/100g, carbs_mono g/100g,
#          protein g/100g, fat g/100g, fibre g/100g, beta, beta_status,
#          density_source, composition_source, beta_provenance, device_verified)
#
# Mass basis: every composition value and density is cooked/as-served. N5k
# ground-truth masses are as-served by construction (weighed at serve time; no
# per-dish basis metadata exists), so there is deliberately no per-row basis
# column — the calibrated bake's density spot-check on rice/pasta (N5k-implied
# mass ÷ measured volume vs the DB ρ) is the executable Req 5.3 assert.
#
# Density sources:
#   CoFID     = McCance & Widdowson CoFID, latest edition
#   FAO_DENS  = value matches an FAO/INFOODS Density Table for Cooked Foods (2012)
#               *served-portion bulk* density entry
#   DEHAIS17  = Dehais et al. 2017 Table II
#   MEASURED  = Gravimetric project measurement, pending calibration
#   EST_BULK  = estimated served-portion bulk density for a granular/piled food
#               with no comparable FAO v2.0 cooked entry (inter-grain air included)
#   EST_SOLID = estimated material density for a contiguous solid whose near-gapless
#               visual hull makes bulk ≈ material density; no FAO v2.0 cooked entry
#
# Bulk vs material density: the visual-hull volume of a served *pile* (rice, pasta,
# lentils) includes the air between pieces, so its bulk density is well below the
# material density (~1.0). Contiguous solids (a meat fillet, cheese block, whole
# fruit) enclose no such air, so material density is the right value for the hull.
#
# Carbohydrate source = CoFID (monosaccharide-equivalent values used throughout).
# For values originally "available carbohydrate by difference", FSAI factor 1.05
# (starch→glucose) or 1.10 (sucrose split) applied where documented in CoFID notes.
#
# beta = 1.0 and beta_status = 'uncalibrated_unity' for all classes at v1 initial
# release; β_c will be updated offline after the calibration subset reaches ≥30 meals
# per class (Req 11.7 / design §6.9).

FOOD_DATA = [
    # (class_id, name, density, energy_kj, carbs_mono, protein, fat, fibre, beta, beta_status, dens_src, comp_src, beta_prov, dev_verified)
    ("white_rice",       "White rice (boiled)",           0.73, 580.0,  32.0,  2.7,  0.3,  0.1,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID", "none", 0),
    ("brown_rice",       "Brown rice (boiled)",            0.76, 606.0,  32.0,  2.6,  0.9,  0.8,  1.0, "uncalibrated_unity", "EST_BULK",  "CoFID", "none", 0),
    ("pasta",            "Pasta (boiled)",                 0.58, 625.0,  26.0,  4.5,  0.7,  1.6,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID", "none", 0),
    ("bread_white",      "Bread (white, sliced)",          0.38, 1048.0, 48.0,  8.4,  1.9,  1.5,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID", "none", 0),
    ("bread_wholemeal",  "Bread (wholemeal)",              0.40, 946.0,  38.0,  9.4,  2.7,  5.0,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID", "none", 0),
    ("potato_boiled",    "Potato (boiled)",                0.59, 318.0,  17.0,  1.8,  0.1,  1.1,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID", "none", 0),
    ("potato_mashed",    "Potato (mashed)",                0.90, 380.0,  15.5,  1.8,  4.5,  1.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID", "none", 0),
    ("chips_fries",      "Chips / French fries",           0.50, 1037.0, 33.0,  3.3, 12.5,  2.3,  1.0, "uncalibrated_unity", "DEHAIS17",  "CoFID", "none", 0),
    ("chicken",          "Chicken breast (cooked)",        0.90, 736.0,   0.0, 31.0,  3.6,  0.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID", "none", 0),
    ("beef",             "Beef (lean, cooked)",            0.93, 886.0,   0.0, 29.0,  7.0,  0.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID", "none", 0),
    ("pork",             "Pork (lean, cooked)",            0.89, 795.0,   0.0, 28.0,  5.5,  0.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID", "none", 0),
    ("fish_white",       "Fish (white, baked)",            0.87, 464.0,   0.0, 20.5,  2.5,  0.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID", "none", 0),
    ("egg",              "Egg (boiled)",                   1.03, 624.0,   0.5, 12.5,  9.5,  0.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID", "none", 0),
    ("cheese",           "Cheddar cheese",                 1.10, 1725.0,  0.1, 24.9, 34.4,  0.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID", "none", 0),
    ("salad_leaves",     "Mixed salad leaves",             0.15, 54.0,    1.2,  1.8,  0.4,  1.5,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID", "none", 0),
    ("broccoli",         "Broccoli (boiled)",              0.55, 129.0,   1.1,  3.1,  0.8,  2.6,  1.0, "uncalibrated_unity", "EST_BULK",  "CoFID", "none", 0),
    ("carrot",           "Carrot (boiled)",                0.73, 108.0,   4.4,  0.6,  0.4,  2.5,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID", "none", 0),
    ("peas",             "Peas (boiled)",                  0.75, 323.0,  10.0,  6.0,  0.9,  5.5,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID", "none", 0),
    ("beans_baked",      "Baked beans (in tomato sauce)",  1.05, 312.0,  11.0,  5.2,  0.6,  3.7,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID", "none", 0),
    ("lentils",          "Lentils (boiled)",               0.85, 410.0,  16.0,  8.8,  0.4,  3.8,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID", "none", 0),
    ("apple",            "Apple (raw, without skin)",      0.55, 200.0,  11.0,  0.4,  0.1,  1.7,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID", "none", 0),
    ("banana",           "Banana (raw)",                   0.87, 403.0,  20.0,  1.2,  0.3,  1.1,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID", "none", 0),
    ("tomato",           "Tomato (raw)",                   0.65, 73.0,    3.0,  0.7,  0.3,  1.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID", "none", 0),
    ("mixed_vegetables", "Mixed vegetables",               0.65, 150.0,   4.5,  2.5,  0.5,  2.0,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID", "none", 0),
    # Coarse liquid classes (Req 7.1, Decisions 23/24) — CoFID-primary values
    # per 100 g; density converts the measured/canonical volume to mass.
    # Liquids never enter the β fit (Req 4.7); β stays at unity.
    ("water",            "Water (still)",                  1.00, 0.0,     0.0,  0.0,  0.0,  0.0,  1.0, "uncalibrated_unity", "CoFID",     "CoFID", "none", 0),
    ("coffee",           "Coffee (black, infusion)",       1.00, 8.0,     0.3,  0.2,  0.0,  0.0,  1.0, "uncalibrated_unity", "CoFID",     "CoFID", "none", 0),
    ("tea",              "Tea (black, infusion)",          1.00, 2.0,     0.0,  0.1,  0.0,  0.0,  1.0, "uncalibrated_unity", "CoFID",     "CoFID", "none", 0),
    ("milk",             "Milk (semi-skimmed)",            1.03, 195.0,   4.8,  3.6,  1.8,  0.0,  1.0, "uncalibrated_unity", "CoFID",     "CoFID", "none", 0),
    ("fruit_juice",      "Orange juice (unsweetened)",     1.04, 153.0,   9.1,  0.6,  0.1,  0.1,  1.0, "uncalibrated_unity", "CoFID",     "CoFID", "none", 0),
    ("soup",             "Soup (vegetable, canned)",       1.02, 155.0,   5.5,  1.1,  0.8,  1.0,  1.0, "uncalibrated_unity", "CoFID",     "CoFID", "none", 0),
    ("beer",             "Beer (average)",                 1.01, 122.0,   2.3,  0.3,  0.0,  0.0,  1.0, "uncalibrated_unity", "CoFID",     "CoFID", "none", 0),
    ("wine",             "Wine (average)",                 0.99, 283.0,   2.6,  0.1,  0.0,  0.0,  1.0, "uncalibrated_unity", "CoFID",     "CoFID", "none", 0),
]

SOLID_CLASS_COUNT = 24
LIQUID_CLASS_COUNT = 8
assert len(FOOD_DATA) == SOLID_CLASS_COUNT + LIQUID_CLASS_COUNT, (
    f"Expected {SOLID_CLASS_COUNT} solid + {LIQUID_CLASS_COUNT} liquid food "
    f"classes, got {len(FOOD_DATA)}"
)

# Canonical serving volumes, region-keyed with per-row provenance (Req 7.4/7.7).
# region/vessel values must be members of the closed vocabulary above.
LIQUID_SERVINGS = [
    # (class_id, region, vessel, serving_ml, source)
    ("water",       "UK", "glass",     250.0, "FSA typical glass serving"),
    ("water",       "US", "glass",     240.0, "US customary cup (8 fl oz)"),
    ("coffee",      "UK", "mug",       260.0, "CoFID portion guidance (mug)"),
    ("coffee",      "US", "mug",       240.0, "US customary cup (8 fl oz)"),
    ("tea",         "UK", "mug",       260.0, "CoFID portion guidance (mug)"),
    ("tea",         "US", "mug",       240.0, "US customary cup (8 fl oz)"),
    ("milk",        "UK", "glass",     200.0, "FSA typical glass serving"),
    ("milk",        "US", "glass",     240.0, "US customary cup (8 fl oz)"),
    ("fruit_juice", "UK", "glass",     150.0, "NHS 5-a-day juice portion"),
    ("fruit_juice", "US", "glass",     240.0, "US customary cup (8 fl oz)"),
    ("soup",        "UK", "bowl",      300.0, "CoFID portion guidance (bowl)"),
    ("soup",        "US", "bowl",      245.0, "USDA soup cup (8.6 fl oz)"),
    ("beer",        "UK", "pint",      568.0, "UK Weights and Measures Act 1985"),
    ("beer",        "UK", "half_pint", 284.0, "UK Weights and Measures Act 1985"),
    ("beer",        "UK", "can_440",   440.0, "standard UK/EU can size"),
    ("beer",        "UK", "can_330",   330.0, "standard UK/EU can size"),
    ("beer",        "US", "pint",      473.0, "US customary pint (16 US fl oz)"),
    ("wine",        "UK", "glass",     175.0, "UK licensing standard medium pour"),
    ("wine",        "US", "glass",     148.0, "US standard 5 fl oz pour"),
]

# Best-effort sub-class rows (Req 7.5, Decision 24). Deliberately no assumed
# lager<stout carb ordering — sweet/milk stouts run higher than lager.
LIQUID_SUBCLASSES = [
    # (class_id, sub_class, carbs_mono_100, density, source)
    ("beer", "lager", 2.2, 1.01, "CoFID"),
    ("beer", "stout", 4.2, 1.01, "CoFID"),
]

# Density-basis spot-check (Req 5.3): the fitted β satisfies mass/volume =
# ρ_DB·β, so the N5k-implied density is ρ_DB·β and the cooked/as-served basis
# assert reduces to a tolerance band on β for the staples whose cooked-vs-dry
# densities differ 2-3×. A silent basis mismatch scales β by that same 2-3×
# and lands outside the band; legitimate bulk corrections sit well inside it.
DENSITY_SPOT_CHECK_CLASSES = ("white_rice", "pasta")
DENSITY_TOLERANCE_FACTOR = 1.8


def _load_calibration(path: str) -> dict:
    """Load and validate the calibrate JSON artifact (design §DB bake handoff
    contract — the sole stream B↔C interface). Aborts before anything is
    written: unknown classes and a failed density spot-check are hard errors.
    """
    with open(path, encoding="utf-8") as fh:
        cal = json.load(fh)
    classes = cal.get("classes")
    if not isinstance(classes, dict):
        raise SystemExit(f"calibration JSON {path} has no 'classes' block")
    lineage = cal.get("lineage")
    if not isinstance(lineage, dict):
        raise SystemExit(
            f"calibration JSON {path} has no lineage block — the bake must "
            "record calibration lineage (Req 5.5)"
        )
    # Req 1.5/5.5 make these mandatory lineage records ("SHALL record") —
    # a missing value must abort, not silently bake an unattributed DB.
    for key in ("licence", "pinned_intrinsics_model"):
        if not lineage.get(key):
            raise SystemExit(
                f"calibration JSON {path} lineage is missing '{key}' — "
                "mandatory lineage record (Req 1.5/5.5); bake aborted"
            )
    known = {row[0] for row in FOOD_DATA}
    unknown = sorted(set(classes) - known)
    if unknown:
        raise SystemExit(
            f"calibration JSON {path} names unknown class(es) {unknown} — "
            "not in FOOD_DATA; a mis-keyed artifact must not bake"
        )
    # Liquids never enter the β fit (Req 4.7) — the harness enforces this at
    # fit time; rejecting liquid entries here guards against a mis-keyed
    # artifact reaching the bake.
    liquid_ids = {row[0] for row in FOOD_DATA[SOLID_CLASS_COUNT:]}
    liquid_entries = sorted(set(classes) & liquid_ids)
    if liquid_entries:
        raise SystemExit(
            f"calibration JSON {path} carries β entries for liquid class(es) "
            f"{liquid_entries} — liquids never enter the β fit (Req 4.7)"
        )
    density_by_class = {row[0]: row[2] for row in FOOD_DATA}
    for class_id in DENSITY_SPOT_CHECK_CLASSES:
        entry = classes.get(class_id)
        if entry is None:
            continue
        beta = float(entry["beta"])
        if beta * DENSITY_TOLERANCE_FACTOR < 1.0 or beta > DENSITY_TOLERANCE_FACTOR:
            rho = density_by_class[class_id]
            raise SystemExit(
                f"density-basis spot-check failed for {class_id}: N5k-implied "
                f"density ρ·β = {rho * beta:.3f} g/cm³ vs DB ρ = {rho:.3f} "
                f"(β = {beta:.3f} outside 1/{DENSITY_TOLERANCE_FACTOR}–"
                f"{DENSITY_TOLERANCE_FACTOR}). N5k masses are as-served; a "
                "band this wide only trips on a cooked/dry basis mismatch. "
                "Bake aborted (Req 5.3)."
            )
    return cal


def _read_prior_provenance(db_path: str) -> dict:
    """Per-class beta_provenance from the PRIOR committed DB, for the Req 5.2
    supersession record. The JSON carries no prior-bake state by design."""
    if not os.path.exists(db_path):
        return {}
    conn = sqlite3.connect(db_path)
    try:
        try:
            rows = conn.execute(
                "SELECT class_id, beta_provenance FROM foods").fetchall()
        except sqlite3.OperationalError:
            return {}  # pre-provenance schema: nothing to supersede
        return dict(rows)
    finally:
        conn.close()


def _apply_calibration(conn: sqlite3.Connection, cal: dict,
                       prior_provenance: dict) -> None:
    """Write per-row β/status/provenance (device_verified stays 0 — only the
    device-spot-check spec flips it, Req 5.4) and the lineage meta rows."""
    clamped = []
    supersessions = []
    standard_errors = {}
    for class_id, entry in sorted(cal["classes"].items()):
        conn.execute(
            "UPDATE foods SET beta = ?, beta_status = ?, beta_provenance = ? "
            "WHERE class_id = ?",
            (entry["beta"], entry["status"], entry["provenance"], class_id))
        standard_errors[class_id] = entry.get("standard_error")
        if entry.get("clamped"):
            clamped.append(class_id)
            print(
                f"calibration-quality warning: {class_id} β = {entry['beta']} "
                "rests on the calibrator's bounds — review before shipping "
                "(Req 5.6)", file=sys.stderr)
        if (prior_provenance.get(class_id) == "n5k_mixture"
                and entry["provenance"] == "n5k_single_dominant"
                and entry["status"] == "calibrated"):
            supersessions.append({"class_id": class_id,
                                  "from": "n5k_mixture",
                                  "to": "n5k_single_dominant"})

    lineage = cal["lineage"]
    meta_rows = {
        "calibration_beta_pool": cal.get("betaPool"),
        "calibration_n5k_release": lineage.get("n5k_release"),
        "calibration_n5k_metadata_version": lineage.get("n5k_metadata_version"),
        "calibration_mapping_artifact_version":
            lineage.get("mapping_artifact_version"),
        "calibration_tau_route": lineage.get("tau_route"),
        "calibration_tau_purity": lineage.get("tau_purity"),
        "calibration_tau_eff": lineage.get("tau_eff"),
        "calibration_kappa_stacking": lineage.get("kappa_stacking"),
        "calibration_seed": lineage.get("seed"),
        "calibration_condition_number": lineage.get("condition_number"),
        "calibration_effective_sample_per_class":
            json.dumps(lineage.get("effective_sample_per_class", {})),
        "calibration_identifiable_per_class":
            json.dumps(lineage.get("identifiable_per_class", {})),
        "calibration_standard_error_per_class": json.dumps(standard_errors),
        "calibration_pinned_intrinsics_model":
            lineage.get("pinned_intrinsics_model"),
        "calibration_licence": lineage.get("licence"),
        "calibration_clamped_classes": json.dumps(clamped),
        "calibration_supersessions": json.dumps(supersessions),
    }
    conn.executemany(
        "INSERT OR REPLACE INTO meta VALUES (?, ?)",
        [(k, str(v)) for k, v in meta_rows.items() if v is not None])

# AFCD entries for classes outside the CoFID-supplied bar. The CoFID-wins
# COALESCE join in the runtime (design §4.1) means rows that overlap with
# CoFID are masked at lookup time; AFCD's role in v1 is widening class coverage
# for items where CoFID lacks a row, NOT overriding CoFID values.
#
# In v1 the demo data set ships AFCD rows that overlap with CoFID for the same
# 24 classes (with AFCD-attributed sources). Where AFCD's value would differ
# from CoFID, the runtime returns CoFID's value (Decision 39).
AFCD_DATA = [
    # AFCD numbers below are illustrative-but-plausible — they exist so the
    # CoFID-wins join is exercised end-to-end. Replace from FSANZ's public
    # release when the data-acquisition workstream lands.
    ("white_rice",       "White rice (boiled)",           0.73, 580.0,  30.5,  2.7,  0.3,  0.1,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    ("brown_rice",       "Brown rice (boiled)",            0.76, 606.0,  31.0,  2.6,  0.9,  0.8,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    ("pasta",            "Pasta (boiled)",                 0.58, 625.0,  26.5,  4.5,  0.7,  1.6,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    ("bread_white",      "Bread (white, sliced)",          0.38, 1048.0, 47.5,  8.4,  1.9,  1.5,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    ("bread_wholemeal",  "Bread (wholemeal)",              0.40, 946.0,  38.5,  9.4,  2.7,  5.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    ("potato_boiled",    "Potato (boiled)",                0.59, 318.0,  16.5,  1.8,  0.1,  1.1,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    ("potato_mashed",    "Potato (mashed)",                0.90, 380.0,  15.0,  1.8,  4.5,  1.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    ("chips_fries",      "Chips / French fries",           0.50, 1037.0, 33.5,  3.3, 12.5,  2.3,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    ("chicken",          "Chicken breast (cooked)",        0.90, 736.0,   0.0, 31.0,  3.6,  0.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    ("beef",             "Beef (lean, cooked)",            0.93, 886.0,   0.0, 29.0,  7.0,  0.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    # AFCD-exclusive classes — extend coverage with foods CoFID does not list.
    ("kumara",           "Kumara (orange, boiled)",        0.92, 386.0,  17.0,  1.6,  0.1,  3.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    ("vegemite",         "Vegemite (yeast extract)",       1.20, 740.0,  16.5, 25.0,  0.1,  3.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    # AFCD/USDA-sourced liquid values — masked by the CoFID rows at lookup time
    # (CoFID-wins merge); they exercise the join and widen future coverage.
    ("milk",             "Milk (semi-skimmed)",            1.03, 200.0,   5.0,  3.5,  1.7,  0.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    ("fruit_juice",      "Orange juice (unsweetened)",     1.04, 150.0,   8.8,  0.6,  0.1,  0.1,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
    ("beer",             "Beer (average)",                 1.01, 125.0,   2.5,  0.3,  0.0,  0.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024", "none", 0),
]

def bake(calibration_json: str | None = None) -> None:
    """Generate cofid_db.sqlite and afcd_db.sqlite into OUTPUT_DIR.

    With ``calibration_json`` (the HarnessCLI calibrate artifact), per-class
    β/status/provenance and the calibration lineage are baked in (Req 5.2-5.7);
    without it the uncalibrated defaults are unchanged.

    Wrapped in a function (not run at import) so the palette-lock predicate can be
    unit-tested without rebaking the tracked DB artefacts.
    """
    # Palette <-> DB lock (Req 8.4 label + Req 5.7/7.2 content): abort before
    # writing anything if the bake has drifted from ClassPalette.
    verify_palette_lock(PALETTE_VERSION)

    # Load + validate the calibration BEFORE touching any output: unknown
    # classes and the Req 5.3 density spot-check abort with nothing written.
    calibration = None
    prior_provenance = {}
    if calibration_json is not None:
        calibration = _load_calibration(calibration_json)
        prior_provenance = _read_prior_provenance(COFID_DB)

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # --- CoFID database ---
    if os.path.exists(COFID_DB):
        os.remove(COFID_DB)

    conn = sqlite3.connect(COFID_DB)
    conn.executescript(SCHEMA_FOODS)

    conn.execute("INSERT INTO meta VALUES ('edition',         'CoFID 2024')")
    conn.execute("INSERT INTO meta VALUES ('palette_version', ?)", (PALETTE_VERSION,))
    cofid_attribution = (
        "McCance and Widdowson's The Composition of Foods Integrated Dataset "
        "(CoFID), Food Standards Agency, Crown Copyright, Open Government "
        "Licence v3. https://www.gov.uk/government/publications/"
        "composition-of-foods-integrated-dataset-cofid"
    )
    conn.execute("INSERT INTO meta VALUES ('attribution', ?)", (cofid_attribution,))

    conn.executemany(
        "INSERT INTO foods VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        FOOD_DATA
    )
    # Canonical servings and sub-class rows live in the CoFID DB only: they are
    # lookup tables, not composition data, so one home avoids merge semantics
    # (the AFCD DB carries the empty tables from the shared schema).
    conn.executemany(
        "INSERT INTO liquid_servings VALUES (?,?,?,?,?)",
        LIQUID_SERVINGS
    )
    conn.executemany(
        "INSERT INTO liquid_subclasses VALUES (?,?,?,?,?)",
        LIQUID_SUBCLASSES
    )
    if calibration is not None:
        _apply_calibration(conn, calibration, prior_provenance)
    conn.commit()
    conn.close()
    print(f"Generated {COFID_DB} with {len(FOOD_DATA)} food classes.")

    # --- AFCD database ---
    if os.path.exists(AFCD_DB):
        os.remove(AFCD_DB)

    conn = sqlite3.connect(AFCD_DB)
    conn.executescript(SCHEMA_AFCD)
    conn.execute("INSERT INTO meta VALUES ('edition',         'AFCD 2024')")
    conn.execute("INSERT INTO meta VALUES ('palette_version', ?)", (PALETTE_VERSION,))
    afcd_attribution = (
        "Australian Food Composition Database (AFCD), Food Standards Australia "
        "New Zealand, CC-BY-4.0. "
        "https://www.foodstandards.gov.au/science/monitoringnutrients/afcd"
    )
    conn.execute("INSERT INTO meta VALUES ('attribution', ?)", (afcd_attribution,))
    conn.executemany(
        "INSERT INTO foods VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        AFCD_DATA
    )
    if calibration is not None:
        # β is per-class, not per-source: keep the AFCD rows consistent so the
        # CoFID-wins COALESCE returns calibrated values whichever DB serves
        # the class. Classes absent from AFCD_DATA update zero rows.
        _apply_calibration(conn, calibration, prior_provenance)
    conn.commit()
    conn.close()
    print(f"Generated {AFCD_DB} with {len(AFCD_DATA)} food classes.")


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--calibration-json", default=None,
        help="HarnessCLI calibrate artifact to bake per-class β/status/"
             "provenance and lineage from (design §DB bake handoff contract); "
             "omit for the uncalibrated defaults.")
    args = parser.parse_args(argv)
    bake(calibration_json=args.calibration_json)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

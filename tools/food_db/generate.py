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
# Pre-release there is exactly one palette, stamped "v0" until the first main
# release (pipeline Decision 50).
PALETTE_VERSION = "v0"

# The single standard palette declaration in ClassPalette.swift this bake is
# locked against. The full declaration text keeps the find() anchor unambiguous
# (the bare word "standard" appears in prose comments too).
_PALETTE_MARKER = "static let standard"

_REPO_ROOT = Path(__file__).resolve().parents[2]
_CLASS_PALETTE_SWIFT = _REPO_ROOT / "MedataCore/Sources/Segmentation/ClassPalette.swift"

# The feedback loop's overlay file (ml-feedback-loop Req 5.1): the ONLY file
# that loop may auto-edit. Read from this fixed committed path BY DEFAULT, with
# no opt-in flag — an opt-in overlay would silently regenerate the DBs without
# landed fixes on any plain invocation — and with the fail-closed inverse guard
# in _prior_db_carries_overlay: a prior DB claiming LOOP_OVERLAY provenance
# while the file is absent aborts the bake.
#
# Anchored to the repo, not to cwd like OUTPUT_DIR. Inputs are repo-relative
# (see _CLASS_PALETTE_SWIFT above), outputs cwd-relative — EndToEndCalibrateBake
# runs this script from a temp directory so the baked DBs land there, and a
# cwd-relative overlay path would make that bake silently overlay-free while
# `make food-db` bakes with it.
OVERLAY_JSON = str(_REPO_ROOT / "tools" / "food_db" / "loop_overlay.json")


def class_palette_version() -> str:
    """Read ClassPalette.version from the current standard palette declaration
    (_PALETTE_MARKER) in ClassPalette.swift.

    The lock tracks the Swift source directly rather than a duplicated constant so
    a future palette change there forces this bake to be reconciled rather than
    silently shipping a stale-edition DB. The search anchors AFTER the marker so
    only the standard declaration's version string can match.
    """
    text = _CLASS_PALETTE_SWIFT.read_text()
    marker = text.find(_PALETTE_MARKER)
    if marker < 0:
        raise SystemExit(
            f"no {_PALETTE_MARKER} palette found in {_CLASS_PALETTE_SWIFT}"
        )
    match = re.search(r'version:\s*"([^"]+)"', text[marker:])
    if match is None:
        raise SystemExit(
            f"could not read ClassPalette.version from {_CLASS_PALETTE_SWIFT}"
        )
    return match.group(1)


def palette_class_list() -> list:
    """Ordered palette content from ClassPalette.swift's current standard
    palette (_PALETTE_MARKER): foodClasses then liquidClasses, declaration
    order, sentinels excluded — the same regex-read pattern as
    class_palette_version (design §DB bake)."""
    text = _CLASS_PALETTE_SWIFT.read_text()
    marker = text.find(_PALETTE_MARKER)
    if marker < 0:
        raise SystemExit(
            f"no {_PALETTE_MARKER} palette found in {_CLASS_PALETTE_SWIFT}"
        )
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

    Pre-release the label is fixed at "v0" and a palette change redefines the
    declaration in place (pipeline Decision 50), so the label alone cannot
    detect palette drift: the lock also asserts FOOD_DATA's class ids equal the
    ordered class list in ClassPalette.swift exactly (Req 5.7/7.2 content
    check).
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
            f"the ordered class list in {_CLASS_PALETTE_SWIFT} (the label "
            "does not change when the palette does — pipeline Decision 50). "
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
-- Household serving definitions for solid classes (serving-adjust PRD Req 1),
-- mirroring the liquid_servings precedent. step is the stepper increment in
-- serving units (0.5 or 1.0) so granularity is data, not code.
CREATE TABLE IF NOT EXISTS solid_servings (
    class_id       TEXT PRIMARY KEY,
    unit_singular  TEXT NOT NULL,
    unit_plural    TEXT NOT NULL,
    grams_per_unit REAL NOT NULL CHECK (grams_per_unit > 0),
    step           REAL NOT NULL CHECK (step > 0),
    source         TEXT NOT NULL
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

# 25 solid food classes + 8 coarse liquid classes co-curated with the
# segmenter palette (ClassPalette.standard: foodClasses then liquidClasses,
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
    # Breakfast cereal class (myfoodrepo-bridge PRD).
    # Coarse family row covering porridge/muesli/granola/cornflakes as served
    # in a bowl. Representative: CoFID 11-1108 "Porridge, made with whole milk"
    # — the as-served basis matching this table's cooked/as-served contract
    # (dry-flake values would over-count a milk-swollen bowl 5-6x by volume).
    # Density: contiguous semi-fluid mass near milk density; no FAO v2.0
    # cooked-porridge entry, hence EST_SOLID.
    ("cereal",           "Breakfast cereal (porridge, made with whole milk)", 1.03, 472.0, 13.3, 4.9, 4.7, 0.9, 1.0, "uncalibrated_unity", "EST_SOLID", "CoFID", "none", 0),
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

SOLID_CLASS_COUNT = 25
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

# Household serving definitions for the solid classes (serving-adjust PRD
# Req 1). Serving-first display is an experiment, so these are data, not code:
# tune weights/units/steps here and rebake — no Swift change needed.
# step = stepper increment in serving units: 0.5 for countable whole items
# (half a potato is a natural correction), 1.0 for spoon/handful measures.
_BDA_PORTION_SHEET = (
    "BDA Food Fact Sheet: Portion sizes, "
    "https://www.bda.uk.com/resource/food-facts-portion-sizes.html"
)
_CRAWLEY_UNVERIFIED = "Crawley Food Portion Sizes (unverified figure)"

SOLID_SERVINGS = [
    # (class_id, unit_singular, unit_plural, grams_per_unit, step, source)
    ("white_rice",       "spoon",            "spoons",             50.0, 1.0, _BDA_PORTION_SHEET),
    ("brown_rice",       "spoon",            "spoons",             50.0, 1.0, _BDA_PORTION_SHEET),
    ("pasta",            "spoon",            "spoons",             50.0, 1.0, _BDA_PORTION_SHEET),
    ("bread_white",      "slice",            "slices",             36.0, 0.5, _BDA_PORTION_SHEET),
    ("bread_wholemeal",  "slice",            "slices",             36.0, 0.5, _BDA_PORTION_SHEET),
    ("potato_boiled",    "potato",           "potatoes",           58.0, 0.5, _BDA_PORTION_SHEET),
    ("potato_mashed",    "scoop",            "scoops",             60.0, 1.0, _CRAWLEY_UNVERIFIED),
    ("chips_fries",      "handful",          "handfuls",           55.0, 1.0, _CRAWLEY_UNVERIFIED),
    ("chicken",          "palm-sized piece", "palm-sized pieces",  90.0, 0.5, _BDA_PORTION_SHEET),
    ("beef",             "palm-sized piece", "palm-sized pieces",  90.0, 0.5, _BDA_PORTION_SHEET),
    ("pork",             "palm-sized piece", "palm-sized pieces",  90.0, 0.5, _BDA_PORTION_SHEET),
    ("fish_white",       "palm-sized piece", "palm-sized pieces",  90.0, 0.5, _BDA_PORTION_SHEET),
    ("egg",              "egg",              "eggs",               50.0, 0.5, _BDA_PORTION_SHEET),
    ("cheese",           "matchbox piece",   "matchbox pieces",    30.0, 0.5, _BDA_PORTION_SHEET),
    ("salad_leaves",     "handful",          "handfuls",           20.0, 1.0, _CRAWLEY_UNVERIFIED),
    ("broccoli",         "heaped tablespoon", "heaped tablespoons", 27.0, 1.0, _BDA_PORTION_SHEET),
    ("carrot",           "heaped tablespoon", "heaped tablespoons", 27.0, 1.0, _BDA_PORTION_SHEET),
    ("peas",             "heaped tablespoon", "heaped tablespoons", 27.0, 1.0, _BDA_PORTION_SHEET),
    ("beans_baked",      "tablespoon",       "tablespoons",        37.0, 1.0, _BDA_PORTION_SHEET),
    ("lentils",          "tablespoon",       "tablespoons",        37.0, 1.0, _CRAWLEY_UNVERIFIED),
    ("apple",            "apple",            "apples",             80.0, 0.5, _BDA_PORTION_SHEET),
    ("banana",           "banana",           "bananas",            80.0, 0.5, _BDA_PORTION_SHEET),
    ("tomato",           "tomato",           "tomatoes",           80.0, 0.5, _BDA_PORTION_SHEET),
    ("mixed_vegetables", "heaped tablespoon", "heaped tablespoons", 27.0, 1.0, _BDA_PORTION_SHEET),
    # As-served porridge basis (CoFID 11-1108): a serving spoon of made-up
    # porridge, consistent with the rice/pasta/mash spoon-scale precedent.
    # BDA quotes 40 g of DRY oats, not an as-served figure, so the honest
    # source label is the unverified one.
    ("cereal",           "spoon",            "spoons",             50.0, 1.0, _CRAWLEY_UNVERIFIED),
]

# Solid classes deliberately WITHOUT a serving definition (the app falls back
# to grams). Empty at v1 — every solid class has a citable household unit.
# Absence must be a decision, never an accident: verify_solid_servings fails
# the bake on any class in neither list.
SOLID_SERVINGS_ABSENT: frozenset = frozenset()


def verify_solid_servings(foods: list | None = None,
                          servings: list | None = None) -> None:
    """Coverage lock for solid_servings (serving-adjust PRD Req 1): a class id
    not among the solid palette classes (an orphan or a liquid) aborts, and so
    does a solid class in neither SOLID_SERVINGS nor SOLID_SERVINGS_ABSENT.
    Runs before anything is written.

    Takes the tables as arguments so the bake can lock the POST-overlay rows:
    a loop overlay does not get to bypass the precision rule below."""
    foods = FOOD_DATA if foods is None else foods
    servings = SOLID_SERVINGS if servings is None else servings
    solids = {row[0] for row in foods[:SOLID_CLASS_COUNT]}
    served = {row[0] for row in servings}
    stray = sorted((served | set(SOLID_SERVINGS_ABSENT)) - solids)
    if stray:
        raise SystemExit(
            f"solid_servings names class(es) {stray} that are not solid "
            "palette classes in foods — orphans and liquids must not bake"
        )
    uncovered = sorted(solids - served - set(SOLID_SERVINGS_ABSENT))
    if uncovered:
        raise SystemExit(
            f"solid class(es) {uncovered} have no solid_servings row and are "
            "not listed in SOLID_SERVINGS_ABSENT — absence must be deliberate"
        )
    overlap = sorted(served & set(SOLID_SERVINGS_ABSENT))
    if overlap:
        raise SystemExit(
            f"class(es) {overlap} are both served and deliberately absent — "
            "pick one"
        )
    # Precision coupling: ServingNote trims serving counts to 2 dp, and the
    # result screen hides its log pill when the parse-derived grams sit within
    # gramEpsilon (0.5 g) of the pending amount (App/ResultView.swift). The
    # note round-trip error is at most 0.005 * grams_per_unit, so every
    # grams_per_unit must stay below 100 g or a logged row could reopen with
    # a phantom pending adjustment.
    oversized = sorted(row[0] for row in servings if row[3] >= 100)
    if oversized:
        raise SystemExit(
            f"class(es) {oversized} have grams_per_unit >= 100 — the "
            "ServingNote 2-dp count precision only round-trips within the "
            "result screen's 0.5 g epsilon while grams_per_unit < 100"
        )


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

# The support-plane reference the runtime integrates volume above
# (specs/estimation/support-plane-reference Req 5.3). A β_c is a ratio between a
# measured volume and a weighed mass, so it is only valid against the geometric
# basis it was fitted on: applying a β fitted above the table to volumes measured
# above the plate is a ~3x error, which is the defect that spec exists to remove.
SUPPORT_PLANE_REFERENCE_IN_USE = "foodSupport"


# --- Loop overlay (ml-feedback-loop Req 5.1/5.2, Decisions 9 and 18) --------
#
# The provenance a loop-authored value carries. It never forges CoFID/AFCD:
# an overridden cell rewrites its own row's source column to this, so no row
# claims a source for a value it no longer holds.
OVERLAY_SOURCE = "LOOP_OVERLAY"

# β is fitted against the SOURCE densities, so a class whose density or
# composition the overlay moves has no valid β until a human refit. Its
# beta_status/beta_provenance read this and _apply_calibration skips it.
# BetaCalibrationStatus in Swift has no such case, so GRDBFoodDatabase's
# `?? .uncalibratedUnity` fallback reads it as uncalibrated — which is exactly
# what it is; the DB simply records the more specific reason.
OVERLAY_BETA_STATUS = "uncalibrated_overlay_base"

# Column allowlist with declared physical bounds (inclusive). β, the palette,
# and the class set are outside the overlay by construction — an off-allowlist
# column is refused, never quietly ignored.
#   density               g/cm³, spanning salad leaves to yeast extract
#   composition columns   g per 100 g — a mass fraction cannot exceed 100
#   grams_per_unit        a household unit from a teaspoon to a large loaf;
#                         verify_solid_servings additionally holds the < 100 g
#                         ServingNote precision rule on the post-overlay rows
#   serving_ml            a shot glass to a two-litre jug
OVERLAY_COLUMNS = {
    "density":                        (0.05, 2.0),
    "carbs_mono_100":                 (0.0, 100.0),
    "protein_100":                    (0.0, 100.0),
    "fat_100":                        (0.0, 100.0),
    "fibre_100":                      (0.0, 100.0),
    "solid_servings.grams_per_unit":  (5.0, 500.0),
    "liquid_servings.serving_ml":     (10.0, 2000.0),
}

# FOOD_DATA tuple positions (the INSERT order at the top of this file).
_F_DENSITY, _F_BETA, _F_BETA_STATUS = 2, 8, 9
_F_DENSITY_SOURCE, _F_COMPOSITION_SOURCE, _F_BETA_PROVENANCE = 10, 11, 12
_FOODS_COLUMN_INDEX = {"density": _F_DENSITY, "carbs_mono_100": 4,
                       "protein_100": 5, "fat_100": 6, "fibre_100": 7}
# Which source column an override rewrites: density overrides are a geometric
# claim, composition overrides a nutritional one, and they must not smear.
_COMPOSITION_COLUMNS = frozenset({"carbs_mono_100", "protein_100",
                                  "fat_100", "fibre_100"})
_SOLID_GRAMS_PER_UNIT, _SOLID_SOURCE = 3, 5
_LIQUID_SERVING_ML, _LIQUID_SOURCE = 3, 4

_OVERLAY_REQUIRED_KEYS = ("class_id", "column", "value", "basis", "fix_id",
                          "applied_at")


def _load_overlay(path: str) -> list:
    """Load and validate the loop overlay. Mirrors _load_calibration's
    fail-before-write contract: every rejection raises SystemExit with nothing
    written, so a malformed overlay leaves the committed DBs standing.

    Validated: entry shape, known class, allowlisted column, numeric value
    inside its declared physical bounds, a basis citing the notes and/or
    captures that motivated the change (Req 5.1), a resolvable side-table key,
    and no cell targeted twice.
    """
    with open(path, encoding="utf-8") as fh:
        overlay = json.load(fh)
    if not isinstance(overlay, list):
        raise SystemExit(
            f"loop overlay {path} must be a JSON list of entries, got "
            f"{type(overlay).__name__}")

    known_classes = {row[0] for row in FOOD_DATA}
    solid_classes = {row[0] for row in SOLID_SERVINGS}
    liquid_keys = {(row[0], row[1], row[2]) for row in LIQUID_SERVINGS}
    seen = {}
    for index, entry in enumerate(overlay):
        where = f"loop overlay {path} entry {index}"
        if not isinstance(entry, dict):
            raise SystemExit(f"{where} is not an object")
        missing = [k for k in _OVERLAY_REQUIRED_KEYS if k not in entry]
        if missing:
            raise SystemExit(f"{where} is missing required key(s) "
                             f"{', '.join(missing)}")

        class_id = entry["class_id"]
        if class_id not in known_classes:
            raise SystemExit(
                f"{where} names unknown class '{class_id}' — the class set is "
                "outside the overlay by construction")

        column = entry["column"]
        if column not in OVERLAY_COLUMNS:
            raise SystemExit(
                f"{where} targets column '{column}', which is not on the "
                f"overlay allowlist ({', '.join(sorted(OVERLAY_COLUMNS))})")

        value = entry["value"]
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            raise SystemExit(f"{where} value must be numeric, got {value!r}")
        low, high = OVERLAY_COLUMNS[column]
        if not low <= float(value) <= high:
            raise SystemExit(
                f"{where} sets {class_id}.{column} to {value}, outside the "
                f"declared physical bounds {low}-{high}")

        basis = entry["basis"]
        if not isinstance(basis, dict):
            raise SystemExit(f"{where} basis is not an object")
        notes = basis.get("notes") or []
        captures = basis.get("captures") or []
        if not notes and not captures:
            raise SystemExit(
                f"{where} cites neither notes nor captures — every "
                "auto-applied value change names the evidence that moved it "
                "(Req 5.1)")

        # Side-table keys. solid_servings is keyed by class alone; a
        # liquid_servings cell needs its region and vessel too.
        if column.startswith("solid_servings.") and class_id not in solid_classes:
            raise SystemExit(
                f"{where} targets {class_id}, which has no solid_servings row")
        if column.startswith("liquid_servings."):
            for key in ("region", "vessel"):
                if not entry.get(key):
                    raise SystemExit(
                        f"{where} targets liquid_servings without a '{key}' — "
                        "that table is keyed (class_id, region, vessel)")
            key = (class_id, entry["region"], entry["vessel"])
            if key not in liquid_keys:
                raise SystemExit(
                    f"{where} names no liquid_servings row: {key}")

        target = (column, class_id, entry.get("region"), entry.get("vessel"))
        if target in seen:
            raise SystemExit(
                f"{where} and entry {seen[target]} both set {class_id}."
                f"{column} — a cell overridden twice has no defined value")
        seen[target] = index
    return overlay


def _apply_overlay(overlay: list | None) -> tuple:
    """Return post-overlay copies of the in-memory tables, plus the classes
    whose β the overlay invalidated.

    Copies, never mutation: the module tables stay at their source values so a
    re-bake in the same process is idempotent. Applied BEFORE INSERT and BEFORE
    _apply_calibration (Decision 18) — β fitted against the source density must
    never ship on top of an overlay density.
    """
    foods = [list(row) for row in FOOD_DATA]
    solid = [list(row) for row in SOLID_SERVINGS]
    liquid = [list(row) for row in LIQUID_SERVINGS]
    if not overlay:
        return foods, solid, liquid, frozenset()

    foods_by_class = {row[0]: row for row in foods}
    solid_by_class = {row[0]: row for row in solid}
    liquid_by_key = {(row[0], row[1], row[2]): row for row in liquid}
    invalidated = set()

    for entry in overlay:
        class_id, column, value = entry["class_id"], entry["column"], \
            float(entry["value"])
        if column in _FOODS_COLUMN_INDEX:
            row = foods_by_class[class_id]
            row[_FOODS_COLUMN_INDEX[column]] = value
            if column in _COMPOSITION_COLUMNS:
                row[_F_COMPOSITION_SOURCE] = OVERLAY_SOURCE
            else:
                row[_F_DENSITY_SOURCE] = OVERLAY_SOURCE
            # Density and composition are both terms the β fit rests on.
            row[_F_BETA] = 1.0
            row[_F_BETA_STATUS] = OVERLAY_BETA_STATUS
            row[_F_BETA_PROVENANCE] = OVERLAY_BETA_STATUS
            invalidated.add(class_id)
        elif column == "solid_servings.grams_per_unit":
            row = solid_by_class[class_id]
            row[_SOLID_GRAMS_PER_UNIT] = value
            row[_SOLID_SOURCE] = OVERLAY_SOURCE
        else:  # liquid_servings.serving_ml — the only other allowlisted column
            row = liquid_by_key[(class_id, entry["region"], entry["vessel"])]
            row[_LIQUID_SERVING_ML] = value
            row[_LIQUID_SOURCE] = OVERLAY_SOURCE

    return foods, solid, liquid, frozenset(invalidated)


def _prior_db_carries_overlay(db_path: str) -> bool:
    """Fail-closed inverse guard (Decision 18): does the PRIOR committed DB
    hold loop-authored values? If it does and the overlay file has gone
    missing, a plain bake would silently un-land every fix, so it must abort
    instead. Checks the meta lineage first (it covers side-table-only
    overlays, which rewrite no foods row) and the provenance columns after.
    """
    if not os.path.exists(db_path):
        return False
    conn = sqlite3.connect(db_path)
    try:
        try:
            recorded = conn.execute(
                "SELECT v FROM meta WHERE k = 'overlay_json'").fetchone()
            if recorded and json.loads(recorded[0]):
                return True
            marked = conn.execute(
                "SELECT 1 FROM foods WHERE density_source = ? "
                "OR composition_source = ? LIMIT 1",
                (OVERLAY_SOURCE, OVERLAY_SOURCE)).fetchone()
            return marked is not None
        except (sqlite3.OperationalError, json.JSONDecodeError):
            return False  # pre-overlay schema: nothing to un-land
    finally:
        conn.close()


def _prior_db_carries_calibration(db_path: str) -> bool:
    """Does the PRIOR committed DB hold calibration lineage?

    Same fail-closed reasoning as _prior_db_carries_overlay, for the other
    input the bake cannot reconstruct on its own: the calibrate artifact is
    produced from the N5k corpus and is not in this repo, so a bare re-bake
    would quietly drop every ``calibration_*`` meta row the committed
    artifacts carry — and `make food-db` is a build gate the loop runs
    unattended (ml-feedback-loop Req 5.2), where a silent provenance loss
    would land in a commit nobody read.
    """
    if not os.path.exists(db_path):
        return False
    conn = sqlite3.connect(db_path)
    try:
        try:
            row = conn.execute(
                "SELECT 1 FROM meta WHERE k LIKE 'calibration\\_%' ESCAPE '\\' "
                "LIMIT 1").fetchone()
            return row is not None
        except sqlite3.OperationalError:
            return False  # pre-meta schema: nothing to drop
    finally:
        conn.close()


def _load_calibration(path: str, density_by_class: dict | None = None) -> dict:
    """Load and validate the calibrate JSON artifact (design §DB bake handoff
    contract — the sole stream B↔C interface). Aborts before anything is
    written: unknown classes and a failed density spot-check are hard errors.

    ``density_by_class`` carries the POST-overlay densities so the spot-check
    reports the ρ the bake is actually about to write (Decision 18).
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
    # Req 5.3, fail-closed: an artifact that records NO support-plane reference
    # must block application, not permit it. Every artifact produced before the
    # support-plane-reference feature records none, and those are precisely the
    # ones calibrated on the old (table) basis — so defaulting the absent case to
    # "assume it matches" would bake in exactly the β this guard exists to stop.
    reference = cal.get("support_plane_reference")
    if not reference:
        raise SystemExit(
            f"calibration JSON {path} records no 'support_plane_reference' — "
            "β_c is only valid against the geometric basis it was fitted on, and "
            "an artifact predating that record was fitted above the table "
            "(Req 5.3). Regenerate it with the current harness; bake aborted"
        )
    if reference != SUPPORT_PLANE_REFERENCE_IN_USE:
        raise SystemExit(
            f"calibration JSON {path} was fitted against support-plane reference "
            f"'{reference}', but the runtime integrates above "
            f"'{SUPPORT_PLANE_REFERENCE_IN_USE}' (Req 5.3). Bake aborted"
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
    if density_by_class is None:
        density_by_class = {row[0]: row[_F_DENSITY] for row in FOOD_DATA}
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
                       prior_provenance: dict,
                       overlay_invalidated: frozenset = frozenset()) -> None:
    """Write per-row β/status/provenance (device_verified stays 0 — only the
    device-spot-check spec flips it, Req 5.4) and the lineage meta rows.

    Classes in ``overlay_invalidated`` are skipped: their density or
    composition moved under the overlay, so the fitted β no longer describes
    them and they stay at ``uncalibrated_overlay_base`` until a human refit
    (ml-feedback-loop Decision 18).

    Cross-dataset provenance (cross-dataset-calibration Req 6.1/7.2): entries
    carrying ``contributing_datasets`` / ``single_source_uncorroborated``
    persist as the ``calibration_contributing_datasets_per_class`` and
    ``calibration_single_source_classes`` meta JSON dicts. Additive: an
    artifact without those keys (the pre-cross-dataset N5k-only shape) writes
    neither meta key.
    """
    clamped = []
    supersessions = []
    standard_errors = {}
    reference_skipped = []
    contributing_by_class = {}
    single_source_classes = []
    # Presence is an artifact-shape question (did the harness emit the
    # cross-dataset fields at all?), judged on the raw entries — persisted
    # VALUES below still honour the support-plane-reference gate.
    cross_dataset_artifact = any(
        "contributing_datasets" in e or "single_source_uncorroborated" in e
        for e in cal["classes"].values())
    overlay_skipped = []
    for class_id, entry in sorted(cal["classes"].items()):
        if class_id in overlay_invalidated:
            overlay_skipped.append(class_id)
            continue
        # Req 5.4: β fitted under another reference is NOT applied. A single
        # artifact spans two references by construction — the mixture path keeps
        # the plate-region flood fill permanently (Decision 17) — so a mismatch
        # here is the expected shape of a healthy artifact, not a malformed one,
        # and the class is left at its default β rather than aborting the bake.
        if entry.get("support_plane_reference") != SUPPORT_PLANE_REFERENCE_IN_USE:
            reference_skipped.append(class_id)
            continue
        conn.execute(
            "UPDATE foods SET beta = ?, beta_status = ?, beta_provenance = ? "
            "WHERE class_id = ?",
            (entry["beta"], entry["status"], entry["provenance"], class_id))
        standard_errors[class_id] = entry.get("standard_error")
        # Cross-dataset provenance travels only for APPLIED classes: a
        # reference-skipped β is not baked, so its provenance must not be
        # recorded as if it were (Req 6.1 attributes the baked β).
        if "contributing_datasets" in entry:
            contributing_by_class[class_id] = entry["contributing_datasets"]
        if entry.get("single_source_uncorroborated"):
            single_source_classes.append(class_id)
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

    if overlay_skipped:
        print(
            f"calibration: {len(overlay_skipped)} class(es) not applied — the "
            "loop overlay moved their density or composition, so the fitted β "
            f"no longer describes them (Decision 18): "
            f"{', '.join(overlay_skipped)}", file=sys.stderr)

    if reference_skipped:
        print(
            f"calibration: {len(reference_skipped)} class(es) not applied — "
            f"fitted against a different support-plane reference from "
            f"'{SUPPORT_PLANE_REFERENCE_IN_USE}' (Req 5.4): "
            f"{', '.join(reference_skipped)}", file=sys.stderr)

    lineage = cal["lineage"]
    meta_rows = {
        "calibration_beta_pool": cal.get("betaPool"),
        "calibration_support_plane_reference": cal.get("support_plane_reference"),
        "calibration_reference_skipped_classes": json.dumps(reference_skipped),
        "calibration_overlay_invalidated_classes": json.dumps(overlay_skipped),
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
    if cross_dataset_artifact:
        meta_rows["calibration_contributing_datasets_per_class"] = \
            json.dumps(contributing_by_class)
        meta_rows["calibration_single_source_classes"] = \
            json.dumps(sorted(single_source_classes))
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

    The loop overlay at OVERLAY_JSON is read whenever it is present — no flag,
    no opt-in (ml-feedback-loop Req 5.1) — and applied to the in-memory rows
    before INSERT and before the calibration.

    Wrapped in a function (not run at import) so the palette-lock predicate can be
    unit-tested without rebaking the tracked DB artefacts.
    """
    # Palette <-> DB lock (Req 8.4 label + Req 5.7/7.2 content): abort before
    # writing anything if the bake has drifted from ClassPalette.
    verify_palette_lock(PALETTE_VERSION)

    # Loop overlay (ml-feedback-loop Req 5.1/5.2), loaded before anything is
    # written. Absent-but-previously-applied is the fail-closed case: baking
    # over it would silently un-land every landed fix.
    overlay = None
    if os.path.exists(OVERLAY_JSON):
        overlay = _load_overlay(OVERLAY_JSON)
    elif _prior_db_carries_overlay(COFID_DB):
        raise SystemExit(
            f"{COFID_DB} carries {OVERLAY_SOURCE} provenance but no overlay "
            f"file is present at {OVERLAY_JSON} — baking would silently drop "
            "every landed loop fix. Bake aborted (ml-feedback-loop Req 5.1)")
    foods, solid_servings, liquid_servings, overlay_invalidated = \
        _apply_overlay(overlay)

    # Serving coverage lock (serving-adjust PRD Req 1): same abort-first rule,
    # run on the POST-overlay rows so an overlay cannot bypass it.
    verify_solid_servings(foods, solid_servings)

    # Load + validate the calibration BEFORE touching any output: unknown
    # classes and the Req 5.3 density spot-check abort with nothing written.
    calibration = None
    prior_provenance = {}
    if calibration_json is not None:
        calibration = _load_calibration(
            calibration_json,
            density_by_class={row[0]: row[_F_DENSITY] for row in foods})
        prior_provenance = _read_prior_provenance(COFID_DB)
    elif _prior_db_carries_calibration(COFID_DB):
        raise SystemExit(
            f"{COFID_DB} carries calibration lineage but no calibration "
            "artifact was named — baking would drop it. Rerun with "
            "--calibration-json <artifact> (make food-db CALIBRATION=<artifact>)")

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
        foods
    )
    # Canonical servings and sub-class rows live in the CoFID DB only: they are
    # lookup tables, not composition data, so one home avoids merge semantics
    # (the AFCD DB carries the empty tables from the shared schema).
    conn.executemany(
        "INSERT INTO liquid_servings VALUES (?,?,?,?,?)",
        liquid_servings
    )
    conn.executemany(
        "INSERT INTO solid_servings VALUES (?,?,?,?,?,?)",
        solid_servings
    )
    conn.executemany(
        "INSERT INTO liquid_subclasses VALUES (?,?,?,?,?)",
        LIQUID_SUBCLASSES
    )
    # Overlay lineage, following the calibration_* meta keys precedent. Written
    # to the CoFID DB only: the overlay touches no AFCD row, and recording it
    # there would claim a provenance those rows do not carry.
    if overlay:
        conn.executemany(
            "INSERT OR REPLACE INTO meta VALUES (?, ?)", [
                ("overlay_json", json.dumps(overlay)),
                ("overlay_fix_ids",
                 json.dumps(sorted({e["fix_id"] for e in overlay}))),
                ("overlay_beta_invalidated_classes",
                 json.dumps(sorted(overlay_invalidated))),
            ])
    if calibration is not None:
        _apply_calibration(conn, calibration, prior_provenance,
                           overlay_invalidated)
    conn.commit()
    conn.close()
    print(f"Generated {COFID_DB} with {len(foods)} food classes.")

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
        # the class. Classes absent from AFCD_DATA update zero rows. The
        # overlay invalidation is per-class too, so it travels here as well.
        _apply_calibration(conn, calibration, prior_provenance,
                           overlay_invalidated)
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

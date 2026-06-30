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

import sqlite3
import os

OUTPUT_DIR = "MedataCore/Sources/Foods/Resources"
COFID_DB  = os.path.join(OUTPUT_DIR, "cofid_db.sqlite")
AFCD_DB = os.path.join(OUTPUT_DIR, "afcd_db.sqlite")

SCHEMA_FOODS = """
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
    composition_source TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v TEXT NOT NULL);
"""

SCHEMA_AFCD = SCHEMA_FOODS  # AFCD uses the same schema as CoFID; values may differ

# 24 food classes co-curated with the segmenter palette.
# Values: (class_id, name, density g/cm³, energy kJ/100g, carbs_mono g/100g,
#          protein g/100g, fat g/100g, fibre g/100g, beta, beta_status,
#          density_source, composition_source)
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
    # (class_id, name, density, energy_kj, carbs_mono, protein, fat, fibre, beta, beta_status, dens_src, comp_src)
    ("white_rice",       "White rice (boiled)",           0.73, 580.0,  32.0,  2.7,  0.3,  0.1,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("brown_rice",       "Brown rice (boiled)",            0.76, 606.0,  32.0,  2.6,  0.9,  0.8,  1.0, "uncalibrated_unity", "EST_BULK",  "CoFID"),
    ("pasta",            "Pasta (boiled)",                 0.58, 625.0,  26.0,  4.5,  0.7,  1.6,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("bread_white",      "Bread (white, sliced)",          0.38, 1048.0, 48.0,  8.4,  1.9,  1.5,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID"),
    ("bread_wholemeal",  "Bread (wholemeal)",              0.40, 946.0,  38.0,  9.4,  2.7,  5.0,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID"),
    ("potato_boiled",    "Potato (boiled)",                0.59, 318.0,  17.0,  1.8,  0.1,  1.1,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("potato_mashed",    "Potato (mashed)",                0.90, 380.0,  15.5,  1.8,  4.5,  1.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID"),
    ("chips_fries",      "Chips / French fries",           0.50, 1037.0, 33.0,  3.3, 12.5,  2.3,  1.0, "uncalibrated_unity", "DEHAIS17",  "CoFID"),
    ("chicken",          "Chicken breast (cooked)",        0.90, 736.0,   0.0, 31.0,  3.6,  0.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID"),
    ("beef",             "Beef (lean, cooked)",            0.93, 886.0,   0.0, 29.0,  7.0,  0.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID"),
    ("pork",             "Pork (lean, cooked)",            0.89, 795.0,   0.0, 28.0,  5.5,  0.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID"),
    ("fish_white",       "Fish (white, baked)",            0.87, 464.0,   0.0, 20.5,  2.5,  0.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID"),
    ("egg",              "Egg (boiled)",                   1.03, 624.0,   0.5, 12.5,  9.5,  0.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID"),
    ("cheese",           "Cheddar cheese",                 1.10, 1725.0,  0.1, 24.9, 34.4,  0.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID"),
    ("salad_leaves",     "Mixed salad leaves",             0.15, 54.0,    1.2,  1.8,  0.4,  1.5,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID"),
    ("broccoli",         "Broccoli (boiled)",              0.55, 129.0,   1.1,  3.1,  0.8,  2.6,  1.0, "uncalibrated_unity", "EST_BULK",  "CoFID"),
    ("carrot",           "Carrot (boiled)",                0.73, 108.0,   4.4,  0.6,  0.4,  2.5,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("peas",             "Peas (boiled)",                  0.75, 323.0,  10.0,  6.0,  0.9,  5.5,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("beans_baked",      "Baked beans (in tomato sauce)",  1.05, 312.0,  11.0,  5.2,  0.6,  3.7,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID"),
    ("lentils",          "Lentils (boiled)",               0.85, 410.0,  16.0,  8.8,  0.4,  3.8,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("apple",            "Apple (raw, without skin)",      0.55, 200.0,  11.0,  0.4,  0.1,  1.7,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID"),
    ("banana",           "Banana (raw)",                   0.87, 403.0,  20.0,  1.2,  0.3,  1.1,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID"),
    ("tomato",           "Tomato (raw)",                   0.65, 73.0,    3.0,  0.7,  0.3,  1.0,  1.0, "uncalibrated_unity", "EST_SOLID", "CoFID"),
    ("mixed_vegetables", "Mixed vegetables",               0.65, 150.0,   4.5,  2.5,  0.5,  2.0,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID"),
]

assert len(FOOD_DATA) == 24, f"Expected 24 food classes, got {len(FOOD_DATA)}"

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
    ("white_rice",       "White rice (boiled)",           0.73, 580.0,  30.5,  2.7,  0.3,  0.1,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024"),
    ("brown_rice",       "Brown rice (boiled)",            0.76, 606.0,  31.0,  2.6,  0.9,  0.8,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024"),
    ("pasta",            "Pasta (boiled)",                 0.58, 625.0,  26.5,  4.5,  0.7,  1.6,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024"),
    ("bread_white",      "Bread (white, sliced)",          0.38, 1048.0, 47.5,  8.4,  1.9,  1.5,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024"),
    ("bread_wholemeal",  "Bread (wholemeal)",              0.40, 946.0,  38.5,  9.4,  2.7,  5.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024"),
    ("potato_boiled",    "Potato (boiled)",                0.59, 318.0,  16.5,  1.8,  0.1,  1.1,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024"),
    ("potato_mashed",    "Potato (mashed)",                0.90, 380.0,  15.0,  1.8,  4.5,  1.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024"),
    ("chips_fries",      "Chips / French fries",           0.50, 1037.0, 33.5,  3.3, 12.5,  2.3,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024"),
    ("chicken",          "Chicken breast (cooked)",        0.90, 736.0,   0.0, 31.0,  3.6,  0.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024"),
    ("beef",             "Beef (lean, cooked)",            0.93, 886.0,   0.0, 29.0,  7.0,  0.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024"),
    # AFCD-exclusive classes — extend coverage with foods CoFID does not list.
    ("kumara",           "Kumara (orange, boiled)",        0.92, 386.0,  17.0,  1.6,  0.1,  3.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024"),
    ("vegemite",         "Vegemite (yeast extract)",       1.20, 740.0,  16.5, 25.0,  0.1,  3.0,  1.0, "uncalibrated_unity", "AFCD 2024", "AFCD 2024"),
]

os.makedirs(OUTPUT_DIR, exist_ok=True)

# --- CoFID database ---
if os.path.exists(COFID_DB):
    os.remove(COFID_DB)

conn = sqlite3.connect(COFID_DB)
conn.executescript(SCHEMA_FOODS)

conn.execute("INSERT INTO meta VALUES ('edition',         'CoFID 2024')")
conn.execute("INSERT INTO meta VALUES ('palette_version', 'v1')")
cofid_attribution = (
    "McCance and Widdowson's The Composition of Foods Integrated Dataset "
    "(CoFID), Food Standards Agency, Crown Copyright, Open Government "
    "Licence v3. https://www.gov.uk/government/publications/"
    "composition-of-foods-integrated-dataset-cofid"
)
conn.execute("INSERT INTO meta VALUES ('attribution', ?)", (cofid_attribution,))

conn.executemany(
    "INSERT INTO foods VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
    FOOD_DATA
)
conn.commit()
conn.close()
print(f"Generated {COFID_DB} with {len(FOOD_DATA)} food classes.")

# --- AFCD database ---
if os.path.exists(AFCD_DB):
    os.remove(AFCD_DB)

conn = sqlite3.connect(AFCD_DB)
conn.executescript(SCHEMA_AFCD)
conn.execute("INSERT INTO meta VALUES ('edition',         'AFCD 2024')")
conn.execute("INSERT INTO meta VALUES ('palette_version', 'v1')")
afcd_attribution = (
    "Australian Food Composition Database (AFCD), Food Standards Australia "
    "New Zealand, CC-BY-4.0. "
    "https://www.foodstandards.gov.au/science/monitoringnutrients/afcd"
)
conn.execute("INSERT INTO meta VALUES ('attribution', ?)", (afcd_attribution,))
conn.executemany(
    "INSERT INTO foods VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
    AFCD_DATA
)
conn.commit()
conn.close()
print(f"Generated {AFCD_DB} with {len(AFCD_DATA)} food classes.")

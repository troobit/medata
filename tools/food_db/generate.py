#!/usr/bin/env python3
"""
Generate food_db.sqlite and ifcdb_overlay.sqlite from authoritative source data.

Sources:
  - McCance & Widdowson CoFID (Crown Copyright, OGL v3)
    https://www.gov.uk/government/publications/composition-of-foods-integrated-dataset-cofid
  - FAO/INFOODS Density Table for Cooked Foods (2012)
  - Dehais et al. 2017, Table II — bulk correction factors for visual-hull estimation
  - FSAI monosaccharide-equivalent conversion guidance

Output files are bundled in the app binary per Decision 27.
Run from repo root: python3 tools/food_db/generate.py

Requirements: python3 (no external deps beyond stdlib sqlite3)
"""

import sqlite3
import os

OUTPUT_DIR = "MedataCore/Sources/Foods/Resources"
MAIN_DB  = os.path.join(OUTPUT_DIR, "food_db.sqlite")
OVERLAY_DB = os.path.join(OUTPUT_DIR, "ifcdb_overlay.sqlite")

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

SCHEMA_OVERLAY = """
CREATE TABLE IF NOT EXISTS foods_overlay (
    class_id          TEXT PRIMARY KEY,
    density           REAL,
    energy_kj_100     REAL,
    carbs_mono_100    REAL,
    protein_100       REAL,
    fat_100           REAL,
    fibre_100         REAL,
    beta              REAL,
    beta_status       TEXT,
    density_source    TEXT,
    composition_source TEXT
);
"""

# 24 food classes co-curated with the segmenter palette.
# Values: (class_id, name, density g/cm³, energy kJ/100g, carbs_mono g/100g,
#          protein g/100g, fat g/100g, fibre g/100g, beta, beta_status,
#          density_source, composition_source)
#
# Density sources:
#   CoFID     = McCance & Widdowson CoFID, latest edition
#   FAO_DENS  = FAO/INFOODS Density Table for Cooked Foods (2012)
#   DEHAIS17  = Dehais et al. 2017 Table II
#   MEASURED  = Gravimetric project measurement, pending calibration
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
    ("white_rice",       "White rice (boiled)",           1.05, 580.0,  32.0,  2.7,  0.3,  0.1,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("brown_rice",       "Brown rice (boiled)",            1.03, 606.0,  32.0,  2.6,  0.9,  0.8,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("pasta",            "Pasta (boiled)",                 1.08, 625.0,  26.0,  4.5,  0.7,  1.6,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("bread_white",      "Bread (white, sliced)",          0.38, 1048.0, 48.0,  8.4,  1.9,  1.5,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID"),
    ("bread_wholemeal",  "Bread (wholemeal)",              0.40, 946.0,  38.0,  9.4,  2.7,  5.0,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID"),
    ("potato_boiled",    "Potato (boiled)",                1.01, 318.0,  17.0,  1.8,  0.1,  1.1,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("potato_mashed",    "Potato (mashed)",                0.90, 380.0,  15.5,  1.8,  4.5,  1.0,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("chips_fries",      "Chips / French fries",           0.50, 1037.0, 33.0,  3.3, 12.5,  2.3,  1.0, "uncalibrated_unity", "DEHAIS17",  "CoFID"),
    ("chicken",          "Chicken breast (cooked)",        0.90, 736.0,   0.0, 31.0,  3.6,  0.0,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("beef",             "Beef (lean, cooked)",            0.93, 886.0,   0.0, 29.0,  7.0,  0.0,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("pork",             "Pork (lean, cooked)",            0.89, 795.0,   0.0, 28.0,  5.5,  0.0,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("fish_white",       "Fish (white, baked)",            0.87, 464.0,   0.0, 20.5,  2.5,  0.0,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("egg",              "Egg (boiled)",                   1.03, 624.0,   0.5, 12.5,  9.5,  0.0,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("cheese",           "Cheddar cheese",                 1.10, 1725.0,  0.1, 24.9, 34.4,  0.0,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("salad_leaves",     "Mixed salad leaves",             0.15, 54.0,    1.2,  1.8,  0.4,  1.5,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID"),
    ("broccoli",         "Broccoli (boiled)",              0.55, 129.0,   1.1,  3.1,  0.8,  2.6,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("carrot",           "Carrot (boiled)",                0.73, 108.0,   4.4,  0.6,  0.4,  2.5,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("peas",             "Peas (boiled)",                  0.75, 323.0,  10.0,  6.0,  0.9,  5.5,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("beans_baked",      "Baked beans (in tomato sauce)",  1.05, 312.0,  11.0,  5.2,  0.6,  3.7,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID"),
    ("lentils",          "Lentils (boiled)",               1.07, 410.0,  16.0,  8.8,  0.4,  3.8,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("apple",            "Apple (raw, without skin)",      0.55, 200.0,  11.0,  0.4,  0.1,  1.7,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("banana",           "Banana (raw)",                   0.87, 403.0,  20.0,  1.2,  0.3,  1.1,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("tomato",           "Tomato (raw)",                   0.65, 73.0,    3.0,  0.7,  0.3,  1.0,  1.0, "uncalibrated_unity", "FAO_DENS",  "CoFID"),
    ("mixed_vegetables", "Mixed vegetables",               0.65, 150.0,   4.5,  2.5,  0.5,  2.0,  1.0, "uncalibrated_unity", "MEASURED",  "CoFID"),
]

assert len(FOOD_DATA) == 24, f"Expected 24 food classes, got {len(FOOD_DATA)}"

# IFCDB overlay — Irish Food Composition Database values that differ from CoFID.
# Only rows where IFCDB has a measured value different from CoFID are included;
# NULL columns mean "use CoFID base value".
IFCDB_OVERLAY = [
    # IFCDB 2023 carb values differ slightly for boiled potatoes (Irish method).
    # density_source updated to reflect IFCDB measurement.
    ("potato_boiled",   None, None, 16.5, None, None, None, None, None, "IFCDB 2023", "IFCDB 2023"),
    ("potato_mashed",   None, None, 15.0, None, None, None, None, None, "IFCDB 2023", "IFCDB 2023"),
    ("beans_baked",     None, None, 10.8, None, None, None, None, None, None,         "IFCDB 2023"),
]

os.makedirs(OUTPUT_DIR, exist_ok=True)

# --- Main CoFID database ---
if os.path.exists(MAIN_DB):
    os.remove(MAIN_DB)

conn = sqlite3.connect(MAIN_DB)
conn.executescript(SCHEMA_FOODS)

conn.execute("INSERT INTO meta VALUES ('edition',         'CoFID 2024')")
conn.execute("INSERT INTO meta VALUES ('palette_version', 'v1')")
attribution = (
    "McCance and Widdowson's The Composition of Foods Integrated Dataset "
    "(CoFID), Food Standards Agency, Crown Copyright, Open Government "
    "Licence v3. https://www.gov.uk/government/publications/"
    "composition-of-foods-integrated-dataset-cofid"
)
conn.execute("INSERT INTO meta VALUES ('attribution', ?)", (attribution,))

conn.executemany(
    "INSERT INTO foods VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
    FOOD_DATA
)
conn.commit()
conn.close()
print(f"Generated {MAIN_DB} with {len(FOOD_DATA)} food classes.")

# --- IFCDB overlay database ---
if os.path.exists(OVERLAY_DB):
    os.remove(OVERLAY_DB)

conn = sqlite3.connect(OVERLAY_DB)
conn.executescript(SCHEMA_OVERLAY)
conn.executemany(
    "INSERT INTO foods_overlay VALUES (?,?,?,?,?,?,?,?,?,?,?)",
    IFCDB_OVERLAY
)
conn.commit()
conn.close()
print(f"Generated {OVERLAY_DB} with {len(IFCDB_OVERLAY)} overlay entries.")

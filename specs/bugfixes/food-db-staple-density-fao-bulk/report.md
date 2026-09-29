# Bugfix Report: food-db-staple-density-fao-bulk

**Date:** 2026-06-30
**Status:** Fixed

## Description of the Issue

`tools/food_db/generate.py` bakes the bundled `cofid_db.sqlite` consumed by the
estimation pipeline. The `density` column is contractually a *served-portion bulk
density* in g/cm³ (documented in `generate.py` schema and `FoodEntry.swift:7`).
For granular/piled staples the shipped values were near 1.0 — i.e. *material/grain*
density — and were labeled `FAO_DENS` as if sourced from the FAO/INFOODS density
table.

Because the visual-hull volume of a served pile of rice/pasta/lentils includes the
inter-grain air, the correct bulk density is well below 1.0. A near-1.0 value
over-counts mass, and since β ships at 1.0 (`uncalibrated_unity`) for the MVP, the
density flows straight through to the carbohydrate number with no calibration to
absorb it.

**Reproduction steps:**
1. Open the bundled DB: `sqlite3 MedataCore/Sources/Foods/Resources/cofid_db.sqlite`
2. `SELECT class_id, density, density_source FROM foods WHERE class_id IN ('white_rice','pasta','potato_boiled','lentils');`
3. Observe densities 1.05 / 1.08 / 1.01 / 1.07, all labeled `FAO_DENS`.

**Impact:** Medium–high accuracy defect on the MVP estimate. Carb-priority staples
(rice, pasta, potato) dominate the carbohydrate number and were inflated ~1.4–1.9×.
No crash; the error is silent and systematic.

## Investigation Summary

The root cause was already pinned down (and FAO-verified) during the 2026-06-30
density audit; this fix confirms it in code and bakes the correction. The
heavyweight `systematic-debugger` skill was not invoked because the defect is a
data-correctness error with a known, externally-determined correct value — not a
persistent or intricate runtime interaction.

- **Symptoms examined:** Shipped `density` values for piled staples sitting at
  ~1.0 g/cm³ versus the column's documented "served-portion bulk density" contract.
- **Code inspected:** `tools/food_db/generate.py` (FOOD_DATA / AFCD_DATA tables and
  schema), `MedataCore/Sources/Foods/FoodEntry.swift`,
  `MedataCore/Sources/Foods/GRDBFoodDatabase.swift` (how density is read), and the
  Swift food-DB tests (which use their own inline fixtures, not the bundled DB).
- **Hypotheses tested / ruled out:** That a downstream factor already corrected for
  the bulk/material gap — ruled out: density is read verbatim and multiplied by the
  visual-hull volume, with β = 1.0. That the `FAO_DENS` label was accurate — ruled
  out: FAO/INFOODS v2.0 lists bulk densities of 0.73 (rice), 0.55–0.59 (pasta),
  0.59 (boiled potato), 0.85 (lentils), and has no comparable cooked entry for the
  contiguous-solid rows that were also labeled `FAO_DENS`.

## Discovered Root Cause

The density values were populated with material/grain density (≈ the density of the
solid food substance) rather than the served-portion bulk density that the visual-
hull volume model requires. For a pile of discrete pieces, bulk density < material
density because the hull encloses inter-grain air.

**Defect type:** Incorrect reference data + inaccurate provenance label.

**Why it occurred:** The two physically distinct quantities — material density and
served-portion bulk density — were conflated when the table was first populated, and
`FAO_DENS` was applied broadly even to rows FAO/INFOODS v2.0 does not cover.

**Contributing factors:** β shipped at 1.0 (uncalibrated), so there is no calibration
term masking or absorbing the density error in the MVP.

## Resolution for the Issue

**Changes made:**
- `tools/food_db/generate.py` — corrected piled-staple densities to FAO served-portion
  bulk values and fixed `density_source` provenance:
  - `white_rice` 1.05 → 0.73 (`FAO_DENS`)
  - `pasta` 1.08 → 0.58 (`FAO_DENS`, FAO range 0.55–0.59)
  - `potato_boiled` 1.01 → 0.59 (`FAO_DENS`)
  - `lentils` 1.07 → 0.85 (`FAO_DENS`)
  - `brown_rice` 1.03 → 0.76 (`EST_BULK` — granular; no FAO v2.0 cooked entry, derived
    from the white-rice bulk analog)
  - `broccoli` 0.55 (unchanged value) → `EST_BULK` (florets; no FAO v2.0 entry)
  - Contiguous solids kept their material density but were relabeled `EST_SOLID`
    (FAO v2.0 has no comparable cooked entry): `chicken`, `beef`, `pork`, `fish_white`,
    `egg`, `cheese`, `potato_mashed`, `apple`, `banana`, `tomato`.
  - `peas` (0.75) and `carrot` (0.73) already matched FAO bulk — kept value and `FAO_DENS`.
  - AFCD overlapping piled staples (`white_rice`, `brown_rice`, `pasta`, `potato_boiled`)
    aligned to the same corrected densities for cross-DB consistency (these rows are
    masked by the CoFID-wins join, so no runtime behaviour change).
- Updated the density-source legend comment to define `EST_BULK` / `EST_SOLID` and to
  state that `FAO_DENS` means the value matches an FAO/INFOODS bulk-density entry.
- Re-baked `MedataCore/Sources/Foods/Resources/cofid_db.sqlite` (and `afcd_db.sqlite`)
  by running `python3 tools/food_db/generate.py`.

β and `beta_status` are unchanged (`1.0` / `uncalibrated_unity`); only density and
provenance changed. `palette_version` was deliberately left at `v1` so the change
coexists with the parallel palette↔DB edition bake lock (model-production tasks 11/12).

**Approach rationale:** The column contract is bulk density and FAO/INFOODS supplies
authoritative bulk values for the carb-priority staples, so those rows are corrected to
the cited source. For contiguous solids the material density is the right physical
quantity for a near-gapless visual hull, so the value is kept and only the false FAO
attribution is corrected. This is a model-free accuracy win that shrinks the residual a
future β_c calibration must absorb.

**Alternatives considered:**
- **Blanket-copy FAO bulk for every row** — rejected: contiguous solids (meat, cheese
  block, whole fruit) have no inter-piece air, so their material density is correct;
  FAO bulk would under-count them, and FAO v2.0 lacks comparable cooked entries anyway.
- **Apply a runtime bulk-correction factor instead of fixing the table** — rejected:
  adds a code path and a second tunable that overlaps with β; correcting the source data
  is simpler and keeps a single density quantity end-to-end.

## Regression Test

**Test file:** `tools/food_db/tests/test_generate.py`
**Test names:** `test_carb_priority_staples_match_fao_bulk_density`,
`test_no_piled_staple_keeps_material_density`,
`test_fao_dens_label_only_on_bulk_regime_values`,
`test_contiguous_solids_not_labeled_fao`,
`test_density_fix_does_not_touch_nutrition`

**What it verifies:** The committed `cofid_db.sqlite` carries FAO served-portion bulk
densities for the carb-priority staples, that no piled staple retains a material-regime
(~1.0) density, that the `FAO_DENS` label only appears on bulk-regime values, that
contiguous solids no longer claim `FAO_DENS`, and that nutrition coefficients and β are
unchanged. Reading the committed artifact means the suite only goes green once
`generate.py` is corrected **and** re-baked.

**Run command:** `python3 -m pytest tools/food_db/tests/ -q`

## Affected Files

| File | Change |
|------|--------|
| `tools/food_db/generate.py` | Corrected piled-staple densities + provenance labels; legend update |
| `MedataCore/Sources/Foods/Resources/cofid_db.sqlite` | Re-baked with corrected densities |
| `MedataCore/Sources/Foods/Resources/afcd_db.sqlite` | Re-baked (overlapping staples aligned) |
| `tools/food_db/tests/test_generate.py` | New regression suite |
| `tools/food_db/tests/conftest.py` | Locates the bundled CoFID DB for the tests |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full Python tool test suite passes (`tools/food_db`, `tools/segmenter`)
- [x] Re-bake is deterministic and reproduces the committed artifact

**Manual verification:**
- Queried the re-baked `cofid_db.sqlite` to confirm corrected densities and labels.

## Prevention

**Recommendations to avoid similar bugs:**
- Keep the regression suite as a provenance guard: any future row labeled `FAO_DENS`
  must sit in the FAO bulk regime.
- Treat "material density" and "served-portion bulk density" as distinct, named
  quantities in any future data-entry checklist.
- When β calibration data lands, re-verify these densities against measured bulk values
  and fold any residual into β_c rather than back into the density column.

## Related

- Parallel work: model-production tasks 11/12 add a palette↔DB edition bake lock in the
  same `generate.py`; this fix keeps `palette_version` at `v1` so both coexist.
- FAO/INFOODS Density Database v2.0 (2012) — source for the corrected bulk densities.

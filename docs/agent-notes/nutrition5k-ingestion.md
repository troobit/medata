# Nutrition5k ingestion (tools/nutrition5k/)

Stream A of the nutrition5k-calibration spec: mapping artifact + `ingest.py`
bridging N5k overhead RGB-D into `.fixture` files.

## Layout

- `mapping.py` — loader for `mapping_n5k_to_palette.json`; fails loudly on
  palette-content or metadata-version mismatch (Req 2.5). `parse_palette()`
  regex-reads `ClassPalette.swift`'s standard declaration (same source-of-truth pattern
  as `generate.py`'s lock).
- `build_mapping.py` — curated name→class rules; regenerates the committed
  artifact from the gitignored `data/metadata/ingredients_metadata.csv`.
  Re-run whenever the palette content or the ingredient CSV changes.
- `ingest.py` — mirrors `tools/segmenter/make_fixtures.py`; serialisation
  goes through the **extended** `make_fixtures.build_fixture_bytes` (new
  optional kwargs: depth, intrinsics override, gravity, GT masses/macros,
  `source_dataset`, `estimator_path`; `probs_hwc`/`argmax_hw` now optional —
  mixture fixtures carry neither).
- Fixtures also carry **per-class GT macro maps** (proto fields 24–26,
  Decision 27): `class_macros()` sums N5k per-ingredient carb/protein/fat
  over mapped ingredients. `DishRecord.ingredients` tuples are 6-wide
  (id, name, grams, carbs_g, protein_g, fat_g); `route_info` tolerates
  3-wide test tuples via `*_` unpacking, `class_macros` does not.

## Non-obvious data facts (verified 2026-07-02 on the local download)

- Depth units are the documented 10⁻⁴ m (plate median ≈ 3,500–4,000 raw =
  350–400 mm) — **but early captures are off by ~10×** (e.g.
  `dish_1556572657`: median 373 raw). The per-plate `depth_out_of_band`
  skip catches those; the run-level reference check (median of per-plate
  medians + food-top 1st percentile, both in-band pre-flight) catches a
  systematic unit error and aborts (Req 3.1).
- `DEPTH_CAP_RAW = 4000` (0.4 m). Raw values **above** the cap exist (table
  ≈ 4,010–4,160; sparse outliers to ~22,000) and are zeroed. All plate/food
  surfaces sit below 400 mm, so nothing informative is lost, and zeroing the
  table conveniently hard-stops the plate-region flood fill (stream B).
- N5k publishes **no** RealSense calibration. Pinned nominal model:
  fx=fy=617, cx=319.5, cy=239.5 @ 640×480 (D435 RGB-module factory nominal);
  identical for every plate, recorded in run summary + lineage.
- Dish CSV row layout: `dish_id, cal, mass, fat, carb, protein`, then
  repeating 7-tuples `(ingr_id, name, grams, cal, fat, carb, protein)`.
  Ingredient ids appear as `ingr_%010d` in dish rows but bare ints in
  `ingredients_metadata.csv` — `mapping.canonical_ingredient_id()` bridges.
- Generic "rice" (482), "potatoes" (5), "red potatoes" (432), "bread" (19)
  are the pair-ambiguous ingredients (Req 2.4). `potato_boiled` has **no**
  unambiguous N5k ingredient — documented staple gap (7 of 8 covered).

## Contracts other streams consume

- Run summary (`run_summary.json`) carries `mixture_fit_excluded_unmapped`
  (unmapped+ambiguous mass fraction > 0.10) and `liquid_excluded`
  (liquid-mapped fraction ≥ 0.05) dish lists — the Swift observation builder
  cannot derive these from fixtures alone (fixtures only carry mapped
  masses), so stream B should consume the summary for Req 4.1/4.7 admission.
- Single-dominant fixtures (checkpoint mode) carry probs at 513×513×35 but
  intrinsics stay the pinned 640×480 camera model — the harness resamples
  probs onto the depth grid; `nadir_argmax` is always empty for N5k (no
  masks; τ_purity derives argmax from the probs).
- Gravity is `(0, 0, -1)` in the nadir frame (camera looks along −Z).

## Gotchas

- `build_fixture_bytes` writes an explicit identity `depth_from_colour`
  whenever depth is supplied — the Swift `DepthMap(pb:)` bridge preconditions
  on exactly 16 floats and crashes on an empty matrix (found in the first real
  end-to-end run; synthetic Swift tests always built the matrix). N5k depth is
  pre-registered to RGB, so identity is the documented assumption.

- Test helpers live in `tests/n5k_testkit.py`, not `conftest.py` — `from
  conftest import …` breaks when several tool test dirs run in one pytest
  invocation (module-name collision with `tools/segmenter/tests/conftest.py`).
- `make_fixtures.build_fixture_bytes`: an explicit `intrinsics=` override
  wins even when `probs_hwc` is provided (seg-bench's W/H-from-probs default
  only applies when no override is given).
- Run pytest as `python3 -m pytest tools/nutrition5k/tests tools/segmenter/tests
  tools/food_db/tests` from the repo root.

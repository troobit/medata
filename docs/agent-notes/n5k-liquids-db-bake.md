# Nutrition5k liquids + DB bake (stream C)

Stream C of the nutrition5k-calibration spec (tasks 23–32): the liquid
subsystem, the palette content lock, and the calibrated bake path.

## Palette lock is CONTENT, not just the label

Decision 23 redefined v1 in place (24 solid + 8 liquid classes, sentinels at
32/33/34), so `"v1"` no longer detects palette drift. `generate.py`'s
`verify_palette_lock` now also parses the ordered class list from
`ClassPalette.swift` (`palette_class_list()` — foodClasses then liquidClasses,
declaration order, sentinels excluded, same regex-read pattern as
`tools/nutrition5k/mapping.py`) and requires exact equality with FOOD_DATA ids.
Consequence: **any palette edit obliges regenerating every palette-locked
artifact in the same change** — both sqlite DBs, the FoodSeg103 remap JSON,
and the hard-coded channel constants in `tools/segmenter/`
(`build_class_mapping.py` sentinels, `export.py EXPECTED_CHANNEL_COUNT`,
`train.py` BACKGROUND/UNKNOWN/UNSUPPORTED, `make_fixtures.py
DEFAULT_NUM_CLASSES`, `prepare_dataset.py BACKGROUND_CHANNEL`). No CI hook by
design; the fail-loud loaders/tests are the enforcement.

## DB schema (generate.py)

- `foods` gained `beta_provenance` (default `'none'`) and `device_verified`
  (default 0); FOOD_DATA tuples are 14 columns. Liquids are rows 24–31, β
  stays unity (liquids never enter the β fit, Req 4.7).
- `liquid_servings(class_id, region, vessel, serving_ml, source)` — region and
  vessel vocabularies are CLOSED, enforced with CHECK constraints built from
  `LIQUID_REGIONS`/`LIQUID_VESSELS`. Servings live in the CoFID DB only
  (lookup table, not composition data — avoids merge semantics); the AFCD DB
  carries the empty tables from the shared schema.
- `liquid_subclasses(class_id, sub_class, ...)` — beer → lager/stout. Stout is
  deliberately HIGHER-carb than lager (no assumed ordering, Decision 24).

## Calibrated bake (`--calibration-json`)

`generate.py --calibration-json <artifact>` consumes the HarnessCLI calibrate
JSON (the sole stream B↔C interface). Key behaviours:

- The Req 5.3 density spot-check is computable from the JSON alone: the fit's
  implied density is exactly ρ_DB·β, so the check is a tolerance band on β
  (`DENSITY_TOLERANCE_FACTOR = 1.8`) for white_rice/pasta. It runs BEFORE
  anything is written; a failing artifact leaves no output.
- Supersession (mixture → single-dominant) is derived by reading the PRIOR
  committed DB's `beta_provenance` before it is overwritten; the JSON carries
  no prior-bake state.
- Lineage lands as `calibration_*` meta keys (per-class maps JSON-encoded);
  clamped classes warn on stderr AND are listed in
  `calibration_clamped_classes`.

## Estimator + resolver (Swift)

- `HeightFieldEstimator`: liquids integrate surface-to-plane via
  `isLiquidClass` (opt-in; `isFoodClass` stays solids-only). The coverage
  REFUSAL is solids-only — a poorly-covered transparent liquid reports its low
  coverage instead of throwing, so `LiquidResolver` can apply the Req 7.6
  precedence. `ClassPalette.className(at:)` covers both class kinds.
- `LiquidResolver` (MedataCore/Sources/Volume) is pure: DB content arrives as
  `Tables`, vessel/sub-class as labels (recognition is the deferred
  model-production dependency, Req 7.7). Precedence: vessel → canonical
  serving; else usable surface volume → depth-integrated; else
  `.excludedFlagged`. BOTH estimate paths set `liquidOverEstimate = true`
  (Decision 19). A serving-table miss THROWS (`servingLookupMiss`) — never a
  silent zero. Region defaults `.uk`; the Settings plumbing is stream D's.

## Gotchas

- `tools/check_spelling.sh` fails on pre-existing `App/*.swift` hits
  (framework symbols like `.center`, `colors:`) — predates stream C; owned by
  the App/ banner work.
- `parse_palette` in `build_class_mapping.py` regex-reads the FOOD_DATA
  *literal* — keep FOOD_DATA a single `[...]` list (no concatenation of two
  lists) or the regex read breaks.

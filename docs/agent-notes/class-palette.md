# ClassPalette and the portable contracts

## v2 is live (myfoodrepo-bridge, 2026-07-25)

`v2Standard` = v1 plus `cereal` appended at solid index 24 (liquids
25–32, sentinels 33/34/35, totalClasses 36). `generate.py` locks against
the `v2Standard` marker (`PALETTE_VERSION = "v2"`, 25 solid + 8 liquid)
and the bundled model is 36-channel. `ClassPalette.standard(for:)`
resolves persisted `paletteVersion` labels. β stays keyed by class NAME
throughout the calibration path, so v1→v2 required no β migration
(cross-dataset-calibration Decision 15). Known drift: the committed
`tools/nutrition5k/mapping_n5k_to_palette.json` still carries the v1
content list and its `parse_palette` still reads `v1Standard` — one
pre-existing n5k test failure until that artifact is regenerated;
`tools/metafood3d/` already targets v2.

## Layout (redefined v1, nutrition5k-calibration — superseded by v2 above)

`ClassPalette.v1Standard` (`MedataCore/Sources/Segmentation/ClassPalette.swift`) is 24 solid food classes (indices 0–23), then 8 coarse liquid classes (24–31: water, coffee, tea, milk, fruit_juice, soup, beer, wine), then the sentinels background=32, unknown_food=33, unsupported_liquid=34. `totalClasses = foodClasses.count + liquidClasses.count + 3`.

**The `version` label is still `"v1"`** even though the layout changed (Decision 23: the app never shipped, nothing was trained against the 24-class layout). Consequence: the label cannot detect palette drift — the DB bake's palette lock gains a *content* check (ordered class list vs FOOD_DATA) in stream C of the spec. History readers must compare class lists, not labels.

## Predicate contract (load-bearing)

- `isFoodClass(_:)` is **solids only** — true exactly for `0..<foodClasses.count`. Every pre-existing consumer (β fit, banner, estimator solid loop, mask matching) relies on this and is untouched by the liquid addition.
- `isLiquidClass(_:)` covers exactly the liquid range; liquid handling is strictly opt-in through it (Decisions 23/24).
- The memberwise init defaults `liquidClasses: []`, which is why the many existing test-fixture palettes compile unchanged.

## Gotchas

- `segmenter.mlpackage` output-channel count must equal `totalClasses` (now 35); the final class list must be locked before the FoodSeg103 training run (Decision 22, model-production prerequisite).
- `tools/food_db/generate.py` and `tools/segmenter/build_class_mapping.py` now assert the redefined totals (stream C landed): `generate.py` checks `len(FOOD_DATA) == 24 solid + 8 liquid`, and `build_class_mapping.py` targets the 35-channel palette.
- `.pb.swift` under `PortableContracts/Generated/` is checked in but generated — edit the `.proto` in `Schemas/` and run `Schemas/generate.sh` (needs protoc + protoc-gen-swift, both in Homebrew).
- `MealFixture.estimator_path` (`"single_dominant"` | `"mixture"`) is the authoritative fixture load-path selector; any other value is malformed. The sentinel SHA `"no_segmenter"` alone must never select the path (Decision 17).

# ClassPalette and the portable contracts

## One palette, version "v0" until main (pipeline Decision 50)

There is exactly one palette declaration: `ClassPalette.standard`
(`MedataCore/Sources/Segmentation/ClassPalette.swift`) — 25 solid food
classes (indices 0–24, `cereal` at 24), then 8 coarse liquid classes
(25–32: water, coffee, tea, milk, fruit_juice, soup, beer, wine), then
the sentinels background=33, unknown_food=34, unsupported_liquid=35.
`totalClasses = foodClasses.count + liquidClasses.count + 3 = 36`.

**The `version` label is `"v0"` and stays `"v0"` until the first main
release.** Pre-release, a palette change redefines `standard` in place
(Decision 23's original ruling, reaffirmed and extended by pipeline
Decision 50 after the "v2" episode): no superseded palette declaration is
retained, no internal version is minted, and every palette-locked
artifact is regenerated in the same change. Consequence: the label cannot
detect palette drift — the DB bake's palette lock asserts palette
*content* (ordered class list vs `FOOD_DATA`), and the mapping artifacts
key on `palette_class_list`, not the label.

Tool parsers (`tools/food_db/generate.py`, `tools/nutrition5k/mapping.py`,
`tools/metafood3d/mapping.py`) anchor their regex reads on the marker
`static let standard` — the full declaration text, so prose comments
containing "standard" can never satisfy the `find()`.

`PaletteMigrator` (Persistence) is dormant designed machinery for
*released* palette changes (pipeline Decision 24): it stays, but no
mapping files are bundled and nothing constructs it in production before
the first release.

## Predicate contract (load-bearing)

- `isFoodClass(_:)` is **solids only** — true exactly for `0..<foodClasses.count`. Every pre-existing consumer (β fit, banner, estimator solid loop, mask matching) relies on this and is untouched by the liquid addition.
- `isLiquidClass(_:)` covers exactly the liquid range; liquid handling is strictly opt-in through it (Decisions 23/24).
- The memberwise init defaults `liquidClasses: []`, which is why the many existing test-fixture palettes compile unchanged.

## Gotchas

- `segmenter.mlpackage` output-channel count must equal `totalClasses` (36); the final class list must be locked before a training run (Decision 22, model-production prerequisite).
- `tools/food_db/generate.py` and `tools/segmenter/build_class_mapping.py` assert the totals: `generate.py` checks `FOOD_DATA` equals the ordered class list parsed from the Swift declaration, and `build_class_mapping.py` targets the 36-channel palette.
- `.pb.swift` under `PortableContracts/Generated/` is checked in but generated — edit the `.proto` in `Schemas/` and run `Schemas/generate.sh` (needs protoc + protoc-gen-swift, both in Homebrew).
- `MealFixture.estimator_path` (`"single_dominant"` | `"mixture"`) is the authoritative fixture load-path selector; any other value is malformed. The sentinel SHA `"no_segmenter"` alone must never select the path (Decision 17).

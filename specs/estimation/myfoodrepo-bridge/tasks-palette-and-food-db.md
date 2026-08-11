---
references:
    - specs/estimation/myfoodrepo-bridge/prd.md
---
# MyFoodRepo-273 bridge — Palette and food DB

## Swift palette v2

- [x] 1. Add cereal class to ClassPalette as index 24, bump version to v2 <!-- id:zcnu90o -->
  - **Amended 2026-08-10 (pipeline Decision 50), applies to every task in this file**: the "palette v2" these completed tasks minted violated nutrition5k-calibration Decision 23 and has been expunged — the cereal class stands, but the palette is the single `ClassPalette.standard` stamped "v0", `v1Standard`/`v2Standard` are gone, and the v1→v2 migration tests were removed. Task text throughout this file is the historical record
  - Append cereal after the 24 existing solids: liquids shift to 25-32, sentinels to 33/34/35, totalClasses 36
  - Update the hardcoded assertions in MedataCore/Tests/SegmentationTests/SegmentationModuleTests.swift:59-72
  - Carb-priority staple channels (first 8 solids) keep their indices — do not reorder anything
  - Context owns: ClassPalette.swift, PaletteMigrator.swift, SegmentationModuleTests, tools/food_db/**, sqlite artefacts, specs/DECISIONS.md entry. Do NOT touch tools/segmenter/ or docs/

- [x] 2. Migrate persisted meal data v1 to v2 via PaletteMigrator <!-- id:zcnu90p -->
  - Extend PaletteMigratorTests to exercise the real v1 -> v2 palettes
  - Cereal unmappable-from-v1 is acceptable and retained per existing migrator semantics
  - Check the proto bridge (PbClassPalette) still round-trips with 36 channels
  - Blocked-by: zcnu90o (Add cereal class to ClassPalette as index 24, bump version to v2)

## Food DB bake

- [x] 3. Add cereal FOOD_DATA row with CoFID composition and density <!-- id:zcnu90q -->
  - tools/food_db/generate.py: FOOD_DATA row for cereal (breakfast cereals: porridge/muesli/granola/cornflakes family), SOLID_CLASS_COUNT to 25, PALETTE_VERSION to v2
  - Pick and record the CoFID food codes used for composition and density; beta stays uncalibrated_unity like every class
  - FOOD_DATA order must exactly match Swift foodClasses + liquidClasses declaration order
  - Blocked-by: zcnu90o (Add cereal class to ClassPalette as index 24, bump version to v2)

- [x] 4. Regenerate both sqlite DBs under the bake lock and update food_db tests <!-- id:zcnu90r -->
  - verify_palette_lock() must pass; regenerate and commit cofid_db.sqlite + afcd_db.sqlite under MedataCore/Sources/Foods/Resources/
  - Update tools/food_db/tests/test_bake_lock.py and test_palette_content_lock.py (expect 33 classes, liquid slice at [25:])
  - Run pytest for tools/food_db/tests/ green (no Makefile target — run manually)
  - Blocked-by: zcnu90q (Add cereal FOOD_DATA row with CoFID composition and density)

## Decisions and gates

- [x] 5. Record palette v2 + cereal decision entry in specs/DECISIONS.md <!-- id:zcnu90s -->
  - Enhanced Nygard format (see rules reference already used by existing entries); include the chosen CoFID codes, at least two alternatives, positive and negative consequences
  - Also state whether cereal joins the carb-priority staple set now or only after training coverage is known (PRD Palette req 4) — record the choice and rationale
  - Blocked-by: zcnu90q (Add cereal FOOD_DATA row with CoFID composition and density)

- [x] 6. Context quality gates green <!-- id:zcnu90t -->
  - make build, make test (report BOTH XCTest and swift-testing totals), make spell
  - pytest tools/food_db/tests/ green
  - Blocked-by: zcnu90p (Migrate persisted meal data v1 to v2 via PaletteMigrator), zcnu90r (Regenerate both sqlite DBs under the bake lock and update food_db tests)

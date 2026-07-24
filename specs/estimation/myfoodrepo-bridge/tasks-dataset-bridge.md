---
references:
    - prd.md
---
# MyFoodRepo-273 bridge — Dataset bridge

## Acquisition

- [ ] 1. Acquire MyFoodRepo-273 into data/myfoodrepo273/ with SOURCE.md provenance <!-- id:vbs7lh4 -->
  - AIcrowd Food Recognition Benchmark (MyFoodRepo-273): images + COCO-format polygon annotations
  - Target is the MAIN checkout gitignored tree: /Users/r/repos/medata/data/myfoodrepo273/ (absolute path — data/ does not exist in worktrees)
  - SOURCE.md follows data/foodseg103/SOURCE.md: source URLs, SHA-256 checksums, actual attached licence (expected CC BY 4.0), image/annotation counts
  - CONDITIONAL STOP: if the download needs interactive AIcrowd login/CAPTCHA/terms that cannot be completed non-interactively, document the exact URL and steps, halt this context, and report blocked-at-STOP — do not scrape around an auth wall
  - Context owns: tools/segmenter/build_class_mapping.py, prepare_dataset.py, new bridge scripts, tests/test_class_mapping.py, test_prepare_dataset.py, new tests, mapping JSONs, docs/ml-training.md, docs/agent-notes/dataset-strategy.md. Do NOT touch train.py, export.py, validation.py, tools/food_db/, ClassPalette.swift

## Coverage audit

- [ ] 2. Publish the 273-category to 36-channel coverage audit <!-- id:vbs7lh5 -->
  - Per-channel image counts for every palette class; explicit verdicts for cereal, brown_rice, bread_wholemeal, potato_mashed
  - Settle the unverified caveats from docs/agent-notes/estimation-improvement-avenues.md:80-81 (brown rice, mashed potato never confirmed)
  - Committed artefact (markdown or JSON) under tools/segmenter/ or docs/agent-notes/; absent coverage is stated plainly, never faked
  - Blocked-by: vbs7lh4 (Acquire MyFoodRepo-273 into data/myfoodrepo273/ with SOURCE.md provenance)

## Mapping and merge

- [ ] 3. Build class_mapping_myfoodrepo273_v1.json and update FoodSeg103 mapping to v2 <!-- id:vbs7lh6 -->
  - Curated-rules script in the build_class_mapping.py style; unmapped categories route to unknown_food
  - v2 channel order is pinned by the PRD: cereal index 24, liquids 25-32, sentinels background 33 / unknown_food 34 / unsupported_liquid 35, channel_count 36
  - Update build_class_mapping.py count constants (SOLID_CLASS_COUNT 25, TOTAL_CLASS_COUNT 33) and regenerate class_mapping_foodseg103 for the v2 order
  - Update tools/segmenter/tests/test_class_mapping.py and add tests for the new curated rules + sentinel routing; torch-free pytest green
  - Blocked-by: vbs7lh5 (Publish the 273-category to 36-channel coverage audit)

- [ ] 4. Rasterise COCO polygons to PNG semantic masks in v2 palette space <!-- id:vbs7lh7 -->
  - Instance polygons flatten to semantic masks; overlaps resolved deterministically (document the rule)
  - Output under /Users/r/repos/medata/data/ (absolute paths); torch-free unit tests for the rasterisation logic where practical
  - Blocked-by: vbs7lh6 (Build class_mapping_myfoodrepo273_v1.json and update FoodSeg103 mapping to v2)

- [ ] 5. Produce the merged FoodSeg103 + MyFoodRepo-273 corpus with frozen-seed splits <!-- id:vbs7lh8 -->
  - Stratified train/val/heldout with the seed recorded in splits.json
  - The 182-image leak-free anchor (data/foodseg103_remapped/heldout_leakfree/) stays byte-identical and none of its images enter merged train/val
  - Regenerate co_stats.json food-channels-only (schema co_stats.v2) for the merged corpus
  - FoodSeg103 masks must be re-remapped to the v2 channel order (sentinels moved) — the old 35-channel masks are invalid for training at 36
  - Blocked-by: vbs7lh7 (Rasterise COCO polygons to PNG semantic masks in v2 palette space)

## Docs

- [ ] 6. Update dataset docs for the new corpus <!-- id:vbs7lh9 -->
  - docs/agent-notes/dataset-strategy.md: MyFoodRepo-273 section (licence, counts, split posture, bridge mapping)
  - docs/ml-training.md: dataset table row, 36-channel notes, --num-classes 36 in run commands
  - make spell green
  - Blocked-by: vbs7lh8 (Produce the merged FoodSeg103 + MyFoodRepo-273 corpus with frozen-seed splits)

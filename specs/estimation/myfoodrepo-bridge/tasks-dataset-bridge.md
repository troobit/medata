---
references:
    - prd.md
---
# MyFoodRepo-273 bridge — Dataset bridge

## Acquisition

- [-] 1. Acquire the bridge dataset with SOURCE.md provenance <!-- id:vbs7lh4 -->
  - AMENDED 2026-07-26 (MD-30): the dataset is now the Food Recognition Benchmark 2022 release (Kaggle mirror sainikhileshreddy/food-recognition-2022, 5.27 GB) into /Users/r/repos/medata/data/foodrec2022/ — MyFoodRepo-273 v0.4 is unobtainable (AIcrowd storage 500s, no mirror; background retry watch continues)
  - Images + COCO-format polygon annotations; release 2.0 vs 2.1 settled by the coverage audit and recorded in SOURCE.md
  - BLOCKED on a user-supplied Kaggle API key (free account; kaggle.json)
  - Target is the MAIN checkout gitignored tree (absolute path — data/ does not exist in worktrees)
  - SOURCE.md follows data/foodseg103/SOURCE.md: source URLs, SHA-256 checksums, actual attached licence (expected CC BY 4.0), image/annotation counts
  - CONDITIONAL STOP: if the download needs interactive AIcrowd login/CAPTCHA/terms that cannot be completed non-interactively, document the exact URL and steps, halt this context, and report blocked-at-STOP — do not scrape around an auth wall
  - Context owns: tools/segmenter/build_class_mapping.py, prepare_dataset.py, new bridge scripts, tests/test_class_mapping.py, test_prepare_dataset.py, new tests, mapping JSONs, docs/ml-training.md, docs/agent-notes/dataset-strategy.md. Do NOT touch train.py, export.py, validation.py, tools/food_db/, ClassPalette.swift

## Coverage audit

- [ ] 2. Publish the source-category to 36-channel coverage audit <!-- id:vbs7lh5 -->
  - AMENDED 2026-07-26 (MD-30): audit runs over the 2022 ontology (498 or 323 categories); known-good candidates already confirmed in its class list: porridge/muesli/crunch-muesli/birchermuesli/flakes-oat (cereal), rice-whole-grain, bread-wholemeal(+toast/whole-wheat), mashed-potatoes-prepared-with-full-fat-milk-with-butter
  - Per-channel image counts for every palette class; explicit verdicts for cereal, brown_rice, bread_wholemeal, potato_mashed
  - Settle the unverified caveats from docs/agent-notes/estimation-improvement-avenues.md:80-81 (brown rice, mashed potato never confirmed)
  - Committed artefact (markdown or JSON) under tools/segmenter/ or docs/agent-notes/; absent coverage is stated plainly, never faked
  - Blocked-by: vbs7lh4 (Acquire MyFoodRepo-273 into data/myfoodrepo273/ with SOURCE.md provenance)

## Mapping and merge

- [ ] 3. Build class_mapping_foodrec2022_v1.json and update FoodSeg103 mapping to v2 <!-- id:vbs7lh6 -->
  - AMENDED 2026-07-26 (MD-30): the new mapping targets the 2022 ontology; artefact renamed from class_mapping_myfoodrepo273_v1.json
  - Curated-rules script in the build_class_mapping.py style; unmapped categories route to unknown_food
  - v2 channel order is pinned by the PRD: cereal index 24, liquids 25-32, sentinels background 33 / unknown_food 34 / unsupported_liquid 35, channel_count 36
  - PARTIALLY DONE at integration 2026-07-25 (main-checkout commit after context merges): build_class_mapping.py constants moved to v2 (SOLID 25, TOTAL 33, PALETTE_VERSION v2), class_mapping_foodseg103_v1.json regenerated at 36 channels, test_class_mapping.py updated, ingredient_mapping_recipe1m_v1.json gained cereal terms + v2 metadata, fixture corpus gained two cereal recipes
  - REMAINING for this task: the 2022 mapping itself (class_mapping_foodrec2022_v1.json + curated rules + its tests) once the dataset is on disk
  - Blocked-by: vbs7lh5 (Publish the source-category to 36-channel coverage audit)

- [x] 4. Rasterise COCO polygons to PNG semantic masks in v2 palette space <!-- id:vbs7lh7 -->
  - DONE 2026-07-26 (tool + tests; the run over the real annotations waits on acquisition): tools/segmenter/rasterise_myfoodrepo.py — mapping-driven (source_id -> target_index, any COCO source), deterministic overlap rule documented in the module docstring (area-descending paint order, smaller instance wins, id tie-break, shoelace area), curated_drop -> background, unmapped category and RLE segmentation are hard errors, images without annotations recorded and skipped
  - 11 torch-free tests green in tools/segmenter/tests/test_rasterise_myfoodrepo.py (synthetic COCO fixtures)
  - Blocked-by: vbs7lh6 (Build class_mapping_foodrec2022_v1.json and update FoodSeg103 mapping to v2)

- [ ] 5. Produce the merged FoodSeg103 + Food-Recognition-2022 corpus with frozen-seed splits <!-- id:vbs7lh8 -->
  - Stratified train/val/heldout with the seed recorded in splits.json
  - The 182-image leak-free anchor (data/foodseg103_remapped/heldout_leakfree/) stays byte-identical and none of its images enter merged train/val
  - Regenerate co_stats.json food-channels-only (schema co_stats.v2) for the merged corpus
  - PARTIALLY DONE 2026-07-26: FoodSeg103 masks re-remapped to v2 channel order at data/foodseg103_remapped_v2/ (seed 20260715, split membership verified identical to v1, sentinels 33/34/35 verified in-mask); the v2 chain was smoke-proven end-to-end the same day (1-epoch train at 36 classes + export gates: 22.17 MB weights, 36 channels, argmax parity 1.0000)
  - Blocked-by: vbs7lh7 (Rasterise COCO polygons to PNG semantic masks in v2 palette space)

## Docs

- [ ] 6. Update dataset docs for the new corpus <!-- id:vbs7lh9 -->
  - docs/agent-notes/dataset-strategy.md: MyFoodRepo-273 section (licence, counts, split posture, bridge mapping)
  - docs/ml-training.md: dataset table row, 36-channel notes, --num-classes 36 in run commands
  - make spell green
  - Blocked-by: vbs7lh8 (Produce the merged FoodSeg103 + MyFoodRepo-273 corpus with frozen-seed splits)

---
references:
    - prd.md
---
# MyFoodRepo-273 bridge — Training and export

## 36-channel tooling

- [x] 1. Move export and validation tooling to 36 channels <!-- id:8id22y3 -->
  - export.py EXPECTED_CHANNEL_COUNT 35 -> 36 (line ~316) and --num-classes default; validation.py sentinel/channel expectations
  - Update tools/segmenter/tests/test_export_gates.py EXPECTED_PALETTE (36 names in v2 order: cereal at 24, liquids 25-32, sentinels 33/34/35) and any other 35-channel assertions this context owns
  - Do NOT touch build_class_mapping.py, prepare_dataset.py, test_class_mapping.py (dataset-bridge context owns them) or tools/food_db/ (palette context owns it)
  - Torch-free pytest green for the owned suites
  - Context owns: train.py, export.py, validation.py, run_validation.py, lineage.py, test_export_gates.py, test_validation.py, segmenter.mlpackage swap, specs/estimation/segmenter-foundation/decision_log.md verdict entry, docs/agent-notes/model-production.md

## Training run

- [ ] 2. Preflight the merged corpus and measure one epoch <!-- id:8id22y4 -->
  - PREREQUISITE from another context: the dataset-bridge merged corpus must exist under /Users/r/repos/medata/data/ — if absent, HALT this context and report blocked (the orchestrator resumes it after the bridge lands); do not build the corpus yourself
  - Verify splits.json seed, leak-free anchor untouched, 36-channel masks
  - Launch a one-epoch measurement run per docs/ml-training.md section 4 before committing to the full run; record epoch wall-clock
  - Blocked-by: 8id22y3 (Move export and validation tooling to 36 channels)

- [ ] 3. Run the full detached training job on the merged corpus at 36 classes <!-- id:8id22y5 -->
  - Launch from the MAIN checkout (/Users/r/repos/medata) after palette + bridge merges — never from a temporary worktree; nohup caffeinate -is with the tools/segmenter/.venv python, log file retained, resume sidecar active
  - Staple-safe recipe: class rebalancing none or at most sqrt_inverse; NO inverse-frequency weighting; geometric augmentation on; photometric augmentation at your discretion with the choice recorded
  - NEVER edit train.py or its imports while the run is live (DataLoader spawn workers re-import from disk)
  - Expect roughly 20 min/epoch on M5 Pro MPS; ~10+ hours for 60 epochs
  - Blocked-by: 8id22y4 (Preflight the merged corpus and measure one epoch)

- [ ] 4. Integration follow-up: align make_fixtures.py and test_lineage.py with the v2 mapping
  - Do this together with the dataset-bridge resume: when class_mapping_foodseg103 regenerates to v2, tools/segmenter/make_fixtures.py DEFAULT_NUM_CLASSES moves 35 -> 36 and tools/segmenter/tests/test_lineage.py:31 palette_version assertion moves v1 -> v2
  - Spike files NUM_CLASSES = 35 are pinned historical evidence — leave them
  - Flagged unowned at integration 2026-07-25 by the training context

## Validation and promotion

- [ ] 5. Validate against the leak-free anchor and record the promotion verdict <!-- id:8id22y6 -->
  - run_validation.py output into tools/segmenter/build/lineage.json including per-staple and cereal IoU
  - Promotion criterion: leak-free mean food-class IoU beats the 0.3776 anchor of 24e0b022241a AND no existing carb-priority staple regresses materially; otherwise record the rejection like Decisions 24/25
  - Verdict entry (promotion or rejection, with numbers) in specs/estimation/segmenter-foundation/decision_log.md, Enhanced Nygard format; outcome note in docs/agent-notes/model-production.md
  - If promoting while below the 0.48/0.45 gates: developer-phase override with attributable reason; export_eligible stays truthful
  - Blocked-by: 8id22y5 (Run the full detached training job on the merged corpus at 36 classes)

- [ ] 6. Export, swap the bundled model, and deploy for verification <!-- id:8id22y7 -->
  - Only on promotion; export.py gates: 24 MiB weight budget, 36 channels in palette order, oracle parity
  - make deploy-release; verify device launch log shows the new segmenterSource=coreml_<12-hex> with matching buildStamp via make logs-device
  - Blocked-by: 8id22y6 (Validate against the leak-free anchor and record the promotion verdict)

## Human gates

- [ ] 7. STOP — on-device capture verification by a human <!-- id:8id22y8 -->
  - A human points the phone at real meals (including a cereal bowl) to confirm the overlay and carb readings; the agent verifies only launch log and build stamp
  - Blocked-by: 8id22y7 (Export, swap the bundled model, and deploy for verification)

- [ ] 8. STOP — ANE residency check in Xcode <!-- id:8id22y9 -->
  - Core ML performance report is a manual Xcode step; record as pending rather than claiming it
  - Blocked-by: 8id22y7 (Export, swap the bundled model, and deploy for verification)

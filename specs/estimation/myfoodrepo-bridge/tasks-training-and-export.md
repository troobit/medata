---
references:
    - specs/estimation/myfoodrepo-bridge/prd.md
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

- [x] 2. Preflight the merged corpus and measure one epoch <!-- id:8id22y4 -->
  - DONE 2026-07-26: merged corpus verified by merge_corpus_foodrec2022.py asserts (anchor 182 stems heldout-only, digest recorded, mask scan hard-errors on pixels >= 36); measurement via --limit 4000 one-epoch run (3.3 min) cross-checked against the FoodSeg103-only smoke run (5,553 imgs in 3.8 min) — both ~24 img/s, so the documented 20 min/epoch figure is stale; projected full epoch ~33 min
  - Verify splits.json seed, leak-free anchor untouched, 36-channel masks
  - Launch a one-epoch measurement run per docs/ml-training.md section 4 before committing to the full run; record epoch wall-clock
  - Blocked-by: 8id22y3 (Move export and validation tooling to 36 channels)

- [x] 3. Run the full detached training job on the merged corpus at 36 classes <!-- id:8id22y5 -->
  - LAUNCHED 2026-07-26 from the main checkout: 12 epochs (total-step parity ~1.6x the incumbent's 60x5,553; ~6.5 h projected), batch 16, lr 1e-3, plain CE with class-weighting none (matches incumbent recipe for attributable comparison), geometric augment on, photometric OFF (recorded choice), out build/checkpoint_merged_v2.pt, log build/train_merged_v2.log, resume sidecar active
  - Launch from the MAIN checkout (/Users/r/repos/medata) after palette + bridge merges — never from a temporary worktree; nohup caffeinate -is with the tools/segmenter/.venv python, log file retained, resume sidecar active
  - Staple-safe recipe: class rebalancing none or at most sqrt_inverse; NO inverse-frequency weighting; geometric augmentation on; photometric augmentation at your discretion with the choice recorded
  - NEVER edit train.py or its imports while the run is live (DataLoader spawn workers re-import from disk)
  - Expect roughly 20 min/epoch on M5 Pro MPS; ~10+ hours for 60 epochs
  - Blocked-by: 8id22y4 (Preflight the merged corpus and measure one epoch)

- [x] 4. Integration follow-up: align make_fixtures.py and test_lineage.py with the v2 mapping <!-- id:wbyid81 -->
  - Do this together with the dataset-bridge resume: when class_mapping_foodseg103 regenerates to v2, tools/segmenter/make_fixtures.py DEFAULT_NUM_CLASSES moves 35 -> 36 and tools/segmenter/tests/test_lineage.py:31 palette_version assertion moves v1 -> v2
  - Spike files NUM_CLASSES = 35 are pinned historical evidence — leave them
  - Flagged unowned at integration 2026-07-25 by the training context

## Validation and promotion

- [x] 5. Validate against the leak-free anchor and record the promotion verdict <!-- id:8id22y6 -->
  - run_validation.py output into tools/segmenter/build/lineage.json including per-staple and cereal IoU
  - Promotion criterion: leak-free mean food-class IoU beats the 0.3776 anchor of 24e0b022241a AND no existing carb-priority staple regresses materially; otherwise record the rejection like Decisions 24/25
  - Verdict entry (promotion or rejection, with numbers) in specs/estimation/segmenter-foundation/decision_log.md, Enhanced Nygard format; outcome note in docs/agent-notes/model-production.md
  - If promoting while below the 0.48/0.45 gates: developer-phase override with attributable reason; export_eligible stays truthful
  - Blocked-by: 8id22y5 (Run the full detached training job on the merged corpus at 36 classes)

- [x] 6. Export, swap the bundled model, and deploy for verification <!-- id:8id22y7 -->
  - CLOSED 2026-08-04: Release redeployed to the iPhone 16 Pro (build stamp 470bb1b-20260804-225023) and the developer read `coreml_ab812dc3aa9d` off a live capture's row in Settings → Estimation log. Verified through `EstimationOutcome.modelVersion` rather than the launch line — `log collect --device-name` needs root on this host, and the log row is the stronger evidence anyway: it proves the estimation path BOUND that model, not merely that the app announced it at startup
  - PARTIAL at closeout 2026-07-26: export gates passed (22,169,442 B, 36 channels, oracle argmax parity 0.9999), bundled segmenter.mlpackage swapped (medata.modelVersion=ab812dc3aa9d), make deploy-release INSTALLED the release build on the iPhone 16 Pro but the launch step failed with the device locked
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

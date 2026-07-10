---
references:
    - prd.md
---
# MVP estimation quality — Segmenter training pipeline

## Recipe

- [x] 1. Add a class-imbalance-aware loss option to tools/segmenter/train.py via a CLI flag (--loss {ce,weighted_ce,focal,dice,combined}); omitting it reproduces todays unweighted nn.CrossEntropyLoss byte-for-byte in the recorded train_config <!-- id:pgctxe6 -->

- [x] 2. Express loss selection and class-weight computation as pure, torch-free-testable helpers; record the selected loss + weighting scheme in the checkpoint and build/lineage.json train_config <!-- id:pgctxe7 -->

- [x] 3. Add torch-free unit tests under tools/segmenter/tests/ covering weight-derivation and loss-selection; they pass without torch and the tools pytest suite stays green <!-- id:pgctxe8 -->

- [x] 4. Add opt-in photometric (colour/brightness/contrast) augmentation applied to the image only (never the mask), off by default, recorded in train_config <!-- id:pgctxe9 -->

- [x] 5. Document the recommended next run as a single copy-pasteable command in docs/ml-training.md section 4, consistent with the resume/caffeinate run-hygiene guidance; run make spell clean <!-- id:pgctxea -->

## Gated run

- [ ] 6. STOP — run an actual segmenter training job with the new recipe, export to Core ML, and swap the bundled segmenter.mlpackage (multi-hour local MPS/GPU; changes the shipped artefact) — human/compute-gated, do not run autonomously <!-- id:pgctxeb -->
  - Blocked-by: pgctxe6 (Add a class-imbalance-aware loss option to tools/segmenter/train.py via a CLI flag --loss {ce,weighted_ce,focal,dice,combined}; omitting it reproduces todays unweighted nn.CrossEntropyLoss byte-for-byte in the recorded train_config), pgctxe7 (Express loss selection and class-weight computation as pure, torch-free-testable helpers; record the selected loss + weighting scheme in the checkpoint and build/lineage.json train_config), pgctxe8 (Add torch-free unit tests under tools/segmenter/tests/ covering weight-derivation and loss-selection; they pass without torch and the tools pytest suite stays green), pgctxe9 (Add opt-in photometric colour/brightness/contrast augmentation applied to the image only never the mask, off by default, recorded in train_config), pgctxea (Document the recommended next run as a single copy-pasteable command in docs/ml-training.md section 4, consistent with the resume/caffeinate run-hygiene guidance; run make spell clean)

- [ ] 7. STOP — on-device deploy + capture verification that overlay speckle is gone and readings are stable (physical iPhone + human) — the real acceptance gate, cannot be automated <!-- id:pgctxec -->
  - Blocked-by: pgctxeb (STOP — run an actual segmenter training job with the new recipe, export to Core ML, and swap the bundled segmenter.mlpackage multi-hour local MPS/GPU; changes the shipped artefact — human/compute-gated, do not run autonomously)

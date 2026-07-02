---
references:
    - smolspec.md
    - decision_log.md
---
# Resumable Segmenter Training

- [x] 1. Write failing tests for resume behaviour in tools/segmenter/tests/test_train_resume.py <!-- id:e8gm7va -->
  - Guard the whole module with pytest.importorskip("torch") — the existing suite runs without torch (tests/conftest.py)
  - Build a tiny PIL-generated image/mask tree fixture (2 train images); no synthetic image fixtures exist yet
  - Happy path: run train.main([...]) with --no-pretrained --limit 2 --target-size 64 --epochs 1 (fall back to 128 if ASPP rejects 64); assert the sidecar <out>.resume.pt records epoch == 1; then resume with --epochs 2 and assert via capsys that "epoch 2/2" is logged and "epoch 1/2" is not, the final checkpoint loads through export.load_checkpoint, and the sidecar was deleted
  - Mismatch case: --resume with a different --num-classes exits non-zero with a [train]-prefixed message naming both values
  - Refusal case: default sidecar present but no --resume passed exits non-zero
  - These tests must fail against current train.py (no --resume flag yet)
  - Stream: 1
  - References: specs/estimation/resumable-segmenter-training/smolspec.md, tools/segmenter/tests/conftest.py

- [x] 2. Implement crash-safe sidecar and --resume in tools/segmenter/train.py <!-- id:e8gm7vb -->
  - Sidecar <--out>.resume.pt written atomically (temp file + os.replace) after every completed epoch: {model, optimizer, epoch, num_classes, target_size, palette_version, lr, batch_size, pretrained, last_food_class_miou}; tensors saved on CPU
  - Validate the sidecar before building the model: exit non-zero with a [train]-prefixed message naming both values when num_classes, palette_version, target_size, lr, or batch_size differ (Decision 3: reject, do not reconcile); a missing/unreadable resume file gets the same message style, not a traceback
  - Refuse to start when the default sidecar exists and --resume was not passed (tell the user to pass --resume or delete the file)
  - Resume: load with map_location="cpu" (pattern: export.py:132) then .to(device); build the model with weights=None; loop becomes range(start_epoch, args.epochs + 1); epoch >= --epochs is harmless (no training steps, final save still produced)
  - Rename the misnamed local best_miou (train.py:312) to last_miou; _save_checkpoint dict shape untouched except pretrained sourced from the sidecar on resumed runs and resumed_from_epoch passed into the lineage train_config
  - Delete the sidecar after the final checkpoint save succeeds
  - Log resume events (source path, restored epoch) in [train] prefix style; conventions: lazy _import_torch(), argparse in main(argv) -> int, --help text; PALETTE_VERSION already imported
  - Roughly 55-70 LOC; all task-1 tests pass
  - Blocked-by: e8gm7va (Write failing tests for resume behaviour in tools/segmenter/tests/test_train_resume.py)
  - Stream: 1
  - References: specs/estimation/resumable-segmenter-training/smolspec.md, tools/segmenter/train.py, tools/segmenter/export.py

- [x] 3. Document the local-Mac MPS training route in docs/ml-training.md <!-- id:e8gm7vc -->
  - Section 1: replace the existing "Segmenter training" row text with the exact wording given in the smolspec Implementation Approach (local M5 Pro-class MPS supported route, roughly 5-10x a mid-range CUDA card per epoch, run iteratively with train.py --resume, CUDA box remains the faster alternative)
  - Section 4: add a short run-hygiene note — caffeinate -is; PYTORCH_ENABLE_MPS_FALLBACK=1 as a safety net (verify nothing hot falls back to CPU); measure one epoch before committing to a full run; watch food-class mIoU
  - Run bash tools/check_spelling.sh (Irish/British English)
  - Stream: 1
  - References: specs/estimation/resumable-segmenter-training/smolspec.md, docs/ml-training.md

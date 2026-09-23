# Resumable Segmenter Training

## Overview

`tools/segmenter/train.py` saves its checkpoint once, after the full epoch loop (train.py:336) — an interrupt at epoch 55 of 60 loses the entire run. Training is moving to the local M5 Pro Mac (MPS), where long runs happen in interruptible chunks, so the trainer needs crash-safe periodic state and a `--resume` flag. The shipped checkpoint format must not change: `export.py`, `make_fixtures.py`, and the lineage manifest consume it as-is.

## Requirements

- The system MUST persist a resumable training state after every completed epoch, so an interrupted run loses at most one epoch of progress, written atomically (temp file + `os.replace`; an interrupt mid-save must not leave a torn file).
- The system MUST support `--resume PATH`: restore model weights, optimizer state, and the epoch counter, then continue the epoch sequence to `--epochs`.
- The system MUST validate the sidecar **before building the model** and exit non-zero with a `[train]`-prefixed message naming both values when any of `num_classes`, `palette_version`, `target_size`, `lr`, or `batch_size` differ from the current invocation — changing hyperparameters mid-run is out of scope (start a fresh run); the palette check enforces nutrition5k-calibration Decisions 22–23 across interrupted runs. A missing or unreadable resume file MUST exit non-zero with the same message style, not a raw traceback.
- WHEN the default sidecar (`<--out>.resume.pt`) exists and `--resume` was not passed, the trainer MUST refuse to start (non-zero exit telling the user to pass `--resume` or delete the file) — a forgotten flag must not silently restart from epoch 1 and overwrite epoch-55 state.
- The system MUST delete the sidecar after the final checkpoint save succeeds, so completed runs leave no stale state; resuming a state whose `epoch >= --epochs` MUST be harmless (no training steps; final save still produced).
- On resume the model MUST be built with `weights=None` (no torchvision download — weights come from the sidecar), and the final checkpoint/lineage `pretrained` field MUST carry the sidecar's recorded value from the original run, not the resume invocation's flag.
- The final artifact at `--out` MUST remain byte-compatible with `export.load_checkpoint` (dict whose `"model"` key holds the state_dict, plus the existing provenance keys); the lineage manifest MUST additionally record `resumed_from_epoch` when the run was resumed so provenance never claims a single uninterrupted run.
- The docs SHOULD record the local-Mac MPS path in `docs/ml-training.md` §1 by **amending the existing "Segmenter training" row** (exact text in Implementation Approach) plus a short §4 run-hygiene note: `caffeinate -is`, `PYTORCH_ENABLE_MPS_FALLBACK=1` as a safety net (verify nothing hot falls back to CPU), measure one epoch before committing to a full run, watch **food-class** mIoU.
- The trainer MAY log resume events (source path, restored epoch) in the existing `[train]` prefix style.

## Implementation Approach

- **Files**: `tools/segmenter/train.py` (~55–70 LOC), `docs/ml-training.md`, one new `tools/segmenter/tests/test_train_resume.py`.
- **Sidecar**: `<--out>.resume.pt` with `{"model", "optimizer", "epoch", "num_classes", "target_size", "palette_version", "lr", "batch_size", "pretrained", "last_food_class_miou"}`. `last_food_class_miou` means "as of the last eval" and may be NaN on non-eval epochs (`--val-every > 1`); the final epoch always evals (train.py:330) so the final value is real. Because `lr`/`batch_size` must match on resume, `optimizer.load_state_dict` restoring the old `param_groups` lr is consistent by construction — no re-apply logic needed.
- **Loop change**: `range(start_epoch, args.epochs + 1)`; rename the misnamed local `best_miou` (train.py:312 — it is assigned on *every* eval) to `last_miou` so the variable and sidecar key agree. `_save_checkpoint` (train.py:340) and its dict shape stay untouched apart from sourcing `pretrained` from the sidecar on resumed runs and passing `resumed_from_epoch` into the lineage `train_config`.
- **Conventions**: lazy `_import_torch()`, argparse in `main(argv) -> int`, `[train]` log prefix, `--help` text; `PALETTE_VERSION` already imported. Sidecar tensors saved on CPU; `map_location="cpu"` on load (pattern: export.py:132), then `.to(device)`.
- **§1 hardware row (replace the existing "Segmenter training" row's text with):** "Local Apple-silicon Mac (M5 Pro-class, MPS) is a supported route: expect roughly 5–10× a mid-range CUDA card per epoch; run iteratively with `train.py --resume` (see §4 run hygiene). A Linux/Windows CUDA box (RTX 3060 12 GB or better) remains the faster alternative; smaller cards work with a smaller batch size."
- **Test** (`test_train_resume.py`): the existing suite runs **without torch** (`tests/conftest.py` documents this) and has no synthetic image fixtures — the new test MUST guard with `pytest.importorskip("torch")` and create its own tiny PIL-generated image/mask tree (2 train images). Run `train.main([...])` with `--no-pretrained --limit 2 --target-size 64 --epochs 1` (verify ASPP tolerates 64; if not, use 128), assert the sidecar's `epoch == 1`; then resume with `--epochs 2` and assert via capsys that training logged `epoch 2/2` (and not `epoch 1/2`), the final checkpoint loads through `export.load_checkpoint`, and the sidecar was deleted. One mismatch case: resume with a different `--num-classes` asserting non-zero exit. One refusal case: sidecar present, no `--resume`, asserting non-zero exit.
- **Dependencies**: torch/torchvision (already in `tools/segmenter/requirements.txt`); no new packages.

## Out of Scope

- AMP/fp16 training, LR schedules, early stopping, best-checkpoint selection (final save keeps last-epoch semantics), changing hyperparameters mid-run.
- Changing the shipped checkpoint dict, `export.py`, `make_fixtures.py`, or `lineage.py` beyond the two provenance values above.
- The real 60-epoch training run — it waits for the nutrition5k-calibration palette lock (final v1 class list); smoke runs on the current 27-channel palette are throwaway.
- FoodSeg103 download (agent-executable, tracked in model-production prerequisites).

## Risks and Assumptions

- Risk: optimizer state restored across devices (MPS ↔ CPU) mis-places tensors | Mitigation: save on CPU, load `map_location="cpu"`, `.to(device)` after restore; the test resumes on CPU.
- Risk: `PYTORCH_ENABLE_MPS_FALLBACK=1` masks a hot op on CPU, turning hours into days | Mitigation: docs instruct measuring one epoch first against the expected range.
- Risk: ASPP/global-pooling may not tolerate `--target-size 64` in the test | Mitigation: test falls back to 128; still seconds-scale with 2 images and `--no-pretrained`.
- Assumption: per-epoch sidecar writes (~50–100 MB) are negligible next to epoch compute.
- Prerequisite: none for the code change; the real run additionally needs FoodSeg103 locally and the final palette.

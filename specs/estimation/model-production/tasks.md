---
references:
    - specs/estimation/model-production/requirements.md
    - specs/estimation/model-production/design.md
    - specs/estimation/model-production/decision_log.md
metadata:
    ledger_note: |-
        What `[x]` means here. A checked box means the code / scaffolding for that task
        landed and its MedataCore (or export.py / generate.py) unit tests pass. It does
        NOT mean the human/data-gated stages ran. Per design §2.1 the gated stages are
        0 (FoodSeg103 acquisition), 3 (GPU training), 7 (ANE residency + on-device
        capture), 9 (gravimetric fixtures), and the execution of 10 (β_c calibrate +
        bake) — all of which live in `prerequisites.md`, not here.
        Per Decision 3 / Decision 5 completion is milestone-scoped: the stage 1–8 code
        deltas in this file can all be `[x]` while β_c calibration execution remains
        deferred past the MVP gate. The mIoU ≥ 0.60 (Req 3.2) and per-class ≥ 0.50
        (Req 3.5) bars are asserted by code here but only *produced* by a gated GPU run.
        This note lives in front matter because rune rejects prose between the H1 and the
        first task/phase.
---
# Model Production — Implementation Tasks

## Bundling and Loader Alignment

- [x] 1. Write loader test for the Bundle.module resource path <!-- id:qkb6beh -->
  - Add a MedataCore test (Pipeline target) asserting makeSegmenter resolves a bundled `segmenter.mlpackage` via `Bundle.module` and constructs the Core ML pipeline without throwing when the resource is present (use a tiny fixture .mlpackage, or the real one once it lands).
  - Assert that when the resource is absent the factory still throws `PipelineFactoryError.segmenterModelMissing` (the dev-stub `#if DEV_STUB_SEGMENTER` path is out of scope for this test).
  - Red before task 2: fails today because the loader uses `Bundle.main` and no resource is declared.
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3)

- [x] 2. Switch loader to Bundle.module and declare the bundled package resource <!-- id:qkb6bei -->
  - At `PipelineFactory.swift:61`, inside the `#else` / non-stub branch only, change `Bundle.main.url(forResource:withExtension:)` to `Bundle.module.url(...)`; leave the `#if DEV_STUB_SEGMENTER` branch (`:57-59`) and the `segmenterModelMissing` throw untouched (Req 5.3).
  - Declare `resources: [.copy("Resources/segmenter.mlpackage")]` on the `Pipeline` target in `Package.swift`, mirroring the `Foods` exemplar at `Package.swift:75-84`.
  - Create `MedataCore/Sources/Pipeline/Resources/` (SPM requires the resource live under the target dir) and move the export.py output path to `MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage` (was `MedataCore/Resources/segmenter.mlpackage`); keep this path string in lockstep with task 7 and task 13.
  - Update `.gitignore` for the new resource location.
  - Bundle.main parity audit (Req 5.1): grep `MedataCore/Sources/**` and `App/**` for `Bundle.main.url(forResource:` / `Bundle.main.path(forResource:`; record the result in the task. Expected: `segmenter.mlpackage` at `:61` is the only model lookup (food DB already uses `Bundle.module`; Metal kernels use `.copy`). The result is recorded, not assumed.
  - Blocked-by: qkb6beh (Write loader test for the Bundle.module resource path)
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3)

## Lineage and Model Versioning

- [x] 3. Emit the build lineage manifest from train.py / export.py <!-- id:qkb6bem -->
  - `tools/segmenter/train.py` and `tools/segmenter/export.py` emit `build/lineage.json` recording: `checkpoint_sha256`, `foodseg103_source`, `split_seed`, `class_mapping_version`, `palette_version`, `train_config`, `code_commit`, and a `metrics` object (`mean_iou`, `per_class_iou`, `carb_priority_iou`).
  - `checkpoint_sha256` is the join key: its first 12 hex form the `modelVersion` stamped by task 7 and read by task 5; `metrics` is populated by the validation step (task 9).
  - Reproducibility is to metric level (a re-run meets the same mIoU bar), not byte-identity (design §3.3).
  - Python-side; the manifest is build provenance and is not shipped in the app bundle.
  - Requirements: [1.3](requirements.md#1.3)

- [x] 4. Write test for coreml_<sha12> source-tag derivation <!-- id:qkb6bej -->
  - Add a MedataCore test: given an `MLModel` whose `userDefinedMetadata["medata.modelVersion"]` carries a known id, `segmenterSourceTag` yields `coreml_<id>` (distinct from `dev_stub`).
  - Cover the absent-key fallback: a model with no `medata.modelVersion` key falls back to the back-compat constant rather than producing an empty tag.
  - Red before task 5: today `modelVersion` is the hardcoded `"v0.1"` at `CoreMLSegmenter.swift:136`.
  - Requirements: [5.4](requirements.md#5.4)

- [x] 5. Derive modelVersion from loaded model metadata <!-- id:qkb6bek -->
  - Change `CoreMLInferenceEngine.modelVersion` (`CoreMLSegmenter.swift:136`) from a static `String` to an instance value read from the loaded `MLModel.userDefinedMetadata["medata.modelVersion"]` at init (`CoreMLSegmenter.swift:146-182`); default to the existing constant only if the key is absent (back-compat for fixtures).
  - `segmenterSourceTag` (`PipelineFactory.swift:79-85`) then interpolates `coreml_<sha12>` into `MealRecord.segmenterSource` (`Pipeline.swift:435`) so a persisted meal is traceable to its exact build.
  - Key string `medata.modelVersion` is the contract shared with task 7's export stamp; keep them identical.
  - Blocked-by: qkb6bej (Write test for coreml_<sha12> source-tag derivation)
  - Requirements: [5.4](requirements.md#5.4), [1.3](requirements.md#1.3)

## Export Gates

- [x] 6. Write export.py gate tests against a fixed reference set <!-- id:qkb6bel -->
  - Add export.py-level checks (Python): recursive `.mlpackage` weight sum ≤ 10 MB mirroring `SegmenterWeightsBudget.validate` (`CoreMLSegmenter.swift:89-95`); exported model declares 27 output channels in `ClassPalette.v1Standard` order; `userDefinedMetadata["medata.modelVersion"]` is stamped.
  - Structurally cover the equivalence oracle and preprocessing-parity assertions so the code path is exercised; the full per-pixel argmax / logit-error run against a real `checkpoint.pt` is gated on the GPU training prerequisite (stage 3).
  - Red before task 7.
  - Requirements: [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5)

- [x] 7. Implement the export.py equivalence, parity, channel, budget and metadata gates <!-- id:qkb6ben -->
  - Flip the equivalence oracle to the PyTorch `checkpoint.pt` (was Core ML-vs-TFLite): run the fixed reference set through the checkpoint and the exported artefact; fail unless per-pixel argmax agreement > 99% AND max abs logit error < 0.05 (Req 4.3). TFLite, when produced, is validated against the same PyTorch oracle, not against Core ML.
  - Feed oracle inputs through the runtime preprocessing path (colour space, normalisation, resize interpolation, channel order matching training and `SegmenterPreProcessor.defaultTargetSize`) so a training/inference mismatch surfaces as an oracle failure (Req 4.5).
  - Assert 27 output channels in palette order; fail on mismatch (Req 4.4). Recursively sum the `.mlpackage` weights and fail over 10 MB, mirroring `SegmenterWeightsBudget.validate` (Req 4.2). FP16 export is unchanged (Req 4.1).
  - Stamp `userDefinedMetadata["medata.modelVersion"]` with the first 12 hex of `checkpoint_sha256` from `build/lineage.json` (links task 3 and task 5).
  - Python-side; full oracle run is gated on a real checkpoint (prerequisite).
  - Blocked-by: qkb6bel (Write export.py gate tests against a fixed reference set), qkb6bem (Emit the build lineage manifest from train.py / export.py)
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [5.4](requirements.md#5.4)

## Validation Reporting

- [ ] 8. Write test for export-eligibility decision and IoU reporting <!-- id:qkb6beo -->
  - Add a test (Python) over synthetic per-class IoU inputs: a checkpoint is export-eligible only when mean IoU ≥ 0.60 AND every carb-priority class (white_rice, brown_rice, pasta, bread_white, bread_wholemeal, potato_boiled, potato_mashed, chips_fries) ≥ 0.50.
  - Assert the reporter emits mean + per-class + carb-priority IoU and records the shortfall when below bar.
  - Red before task 9. Pure decision logic — independent of the gated GPU run that produces the real IoUs.
  - Requirements: [3.2](requirements.md#3.2), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6)

- [ ] 9. Implement validation mIoU / per-class / carb-priority reporting into lineage <!-- id:qkb6bep -->
  - The validation step computes and reports mean IoU, per-class IoU, and the carb-priority-class IoU subset on the held-out split, and records export-eligibility (≥ 0.60 mean, ≥ 0.50 each carb-priority) plus any shortfall into `build/lineage.json` `metrics` (Req 3.3, 3.4).
  - A sub-bar checkpoint is marked not export-eligible; a carb-priority class that cannot meet 0.50 after refinement is surfaced as a known limitation (flag low-confidence or map to `unknown_food`) rather than blocking indefinitely (Req 3.6).
  - Python-side. The *running* of this on real held-out data is gated on the GPU training prerequisite; this task is the code that computes, reports, and records.
  - Blocked-by: qkb6beo (Write test for export-eligibility decision and IoU reporting), qkb6bem (Emit the build lineage manifest from train.py / export.py)
  - Requirements: [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.6](requirements.md#3.6)

## Uncalibrated Honesty

- [ ] 10. Surface uncalibrated low-confidence honesty in ResultView
  - In `ResultView`, when `meal.perClassCalibration` is non-`calibrated` (`uncalibrated_unity`), render a low-confidence indication reusing the `ConfidencePill` styling / very-low surface (`ResultView.swift:156`, `:220-248`); no new view type.
  - Add one new copy string (metric-only English) conveying the known upward (over-estimating) volume bias — the carbohydrate value is more likely high than low (Req 7.3). Keep it distinct from the existing `dev_stub` placeholder banner, which marks *fake* numbers; this marks a *real but uncalibrated* number.
  - Confirm (no change): β = 1.0 / `uncalibrated_unity` is already the DB default (`tools/food_db/generate.py:70-96`) and `MealRecord.perClassCalibration` already persists the status (`Pipeline.swift:428-429`) — no schema change.
  - Per the testing-minimal posture this UI predicate is verified by build + on-device (prerequisite); no new UI test target is added.
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3)

## Calibration Bake Lock

- [ ] 11. Write test for the palette↔DB edition bake lock <!-- id:qkb6beq -->
  - Add a test that `tools/food_db/generate.py` fails the bake when `meta.palette_version` does not equal `ClassPalette.version` (currently `'v1'`).
  - Red before task 12.
  - Requirements: [8.4](requirements.md#8.4)

- [ ] 12. Enforce the palette_version edition lock in generate.py <!-- id:qkb6ber -->
  - At `tools/food_db/generate.py:136-137`, add/verify the check so baking a β_c table fails when `meta.palette_version` ≠ `ClassPalette.version` (`ClassPalette.swift:41-53`).
  - This is the only code part of the otherwise deferred β_c calibrate+bake stage (design §2.1 stage 10); fixture capture and the calibrate/bake execution are prerequisites.
  - Blocked-by: qkb6beq (Write test for the palette↔DB edition bake lock)
  - Requirements: [8.4](requirements.md#8.4)

## Runbook and Architecture Sync

- [ ] 13. Sync ml-training.md and architecture.md with the loader/export change <!-- id:qkb6bes -->
  - Update `docs/ml-training.md` §6 (export output path now `MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage`) and §7 (bundling via the `Bundle.module` package-resource pattern) in lockstep with tasks 2 and 7.
  - Update `docs/architecture.md:393` to record that the §9 loader gap is now closed (was `Bundle.main`).
  - Req 1.4: the runbook and the tracked process must not diverge — change them in the same commit as the code.
  - Blocked-by: qkb6bei (Switch loader to Bundle.module and declare the bundled package resource), qkb6ben (Implement the export.py equivalence, parity, channel, budget and metadata gates)
  - Requirements: [1.4](requirements.md#1.4)

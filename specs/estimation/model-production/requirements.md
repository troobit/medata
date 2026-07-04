# Requirements: Model Production

## Introduction

This spec defines the repeatable process that takes the on-device food segmenter from "documented recipe + smoke-tested tooling" to a trained `segmenter.mlpackage` bundled in the iOS app and producing a real carbohydrate number — the single remaining blocker for a simple MVP. It is the ML-production overlay on the existing pipeline spec: the runtime architecture (`specs/estimation/pipeline/design.md`) and project prerequisites (`specs/estimation/pipeline/prerequisites.md`) are already owned there, and the end-to-end recipe lives in `docs/ml-training.md`; this spec references those rather than restating them, and adds the acceptance gates, the executable process, and the human-vs-automated boundary needed to drive the work to done. The MVP gate is a real, accuracy-barred segmenter with β_c calibration deferred (numbers ship flagged low-confidence); full v1 calibration accuracy is tracked as a defined-but-deferred process, not an MVP blocker.

## Non-Goals

- On-device or on-the-fly training, fine-tuning, or recalibration — all model artefacts are produced offline.
- Executing the gravimetric calibration campaign (acquiring ≥30 weighed meals/class) — this spec defines and tracks that process but its execution is deferred past the MVP.
- Re-deriving the runtime inference architecture — owned by `specs/estimation/pipeline/design.md`.
- Production TFLite / Android export — TFLite remains a validation-only output in v1.
- Changing the 27-class palette, its membership, or its channel order.
- A reduced or subset-class MVP model — the full 27-class v1 palette is trained.
- Cloud / API-based food recognition — deferred per pipeline Decision 22.

## Requirements

### 1. Defined, Refinable Production Process

**User Story:** As an ML engineer, I want a single ordered process from dataset to bundled model, so that any contributor can reproduce a model build and refine the process as it is exercised.

**Acceptance Criteria:**

1. <a name="1.1"></a>The spec SHALL define the ordered model-production process as a sequence of stages (dataset preparation, training, validation, export, bundling, on-device verification) referencing `docs/ml-training.md` as the authoritative runbook rather than duplicating its commands.  
2. <a name="1.2"></a>Each process stage SHALL be marked as either automated (scripted/coding-actionable) or human/data-gated (requiring a dataset, GPU run, or physical measurement a coding agent cannot perform).  
3. <a name="1.3"></a>Each model build SHALL record its lineage — training checkpoint SHA-256, FoodSeg103 source version, dataset split seed, `class_mapping` version, training config, and code commit — so a bundled `segmenter.mlpackage` is reproducible to metric level (a re-run meets the same mIoU bar), not merely identifiable.  
4. <a name="1.4"></a>WHEN a process stage is changed during refinement, the spec and `docs/ml-training.md` SHALL be updated together so the runbook and the tracked process do not diverge.  

### 2. Dataset Preparation

**User Story:** As an ML engineer, I want FoodSeg103 remapped to the v1 palette with fixed splits, so that training and held-out evaluation are reproducible.

**Acceptance Criteria:**

1. <a name="2.1"></a>The process SHALL remap FoodSeg103 (103 classes) to the 27-channel v1 palette via `tools/segmenter/build_class_mapping.py` and `class_mapping_foodseg103_v1.json`.  
2. <a name="2.2"></a>The process SHALL cut train, validation, and held-out splits with a fixed seed so the same dataset yields identical splits across runs.  
3. <a name="2.3"></a>The remapped class channel order SHALL match `ClassPalette.v1Standard` (24 food + background + unknown_food + unsupported_liquid); a build whose mapping reorders or drops a channel SHALL fail before training.  
4. <a name="2.4"></a>Acquiring the FoodSeg103 dataset (Apache 2.0) SHALL be recorded as a human-gated prerequisite, not an automated step.  

### 3. Segmenter Training

**User Story:** As an ML engineer, I want to transfer-learn the v1 segmenter to a checkpoint that meets the accuracy bar, so that the bundled model produces usable masks.

**Acceptance Criteria:**

1. <a name="3.1"></a>The process SHALL transfer-learn DeepLabV3 + MobileNetV3-Large at 513×513 input via `tools/segmenter/train.py`, producing `build/checkpoint.pt`; this is a human/data-gated stage requiring the dataset and a GPU.  
2. <a name="3.2"></a>A checkpoint SHALL be export-eligible only if it achieves mean IoU ≥ 0.60 on the held-out split (MD-12 / pipeline Req 8.9), measured by the validation harness.  
3. <a name="3.3"></a>The validation step SHALL report per-class and mean IoU so classes below bar are identifiable for process refinement.  
4. <a name="3.4"></a>IF the held-out mean IoU is below 0.60, THEN the checkpoint SHALL NOT proceed to export and the shortfall SHALL be recorded against the build.  
5. <a name="3.5"></a>Each carb-priority class (the high-carbohydrate staples `white_rice`, `brown_rice`, `pasta`, `bread_white`, `bread_wholemeal`, `potato_boiled`, `potato_mashed`, `chips_fries`) SHALL achieve per-class IoU ≥ 0.50 on the held-out split for a checkpoint to be export-eligible; design MAY refine the floor or the set against the first real training run's per-class distribution.  
6. <a name="3.6"></a>IF a carb-priority class cannot meet the [3.5](#3.5) floor after refinement, THEN it SHALL be surfaced as a known limitation (flagged low-confidence or mapped to `unknown_food`) rather than indefinitely blocking the MVP.  

### 4. Core ML Export

**User Story:** As an ML engineer, I want the checkpoint exported to a size-bounded, numerically faithful Core ML model, so that the bundled artefact matches the trained network within budget.

**Acceptance Criteria:**

1. <a name="4.1"></a>The process SHALL export `build/checkpoint.pt` to `MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage` via `tools/segmenter/export.py` with FP16 weights.  
2. <a name="4.2"></a>The exported `segmenter.mlpackage` weights SHALL be ≤ 24 MiB (pipeline Req 8.2 as amended by Decision 13; the original 10 MB was unachievable for the Decision 25 architecture at FP16) and SHALL pass `SegmenterWeightsBudget.validate(at:)`.  
3. <a name="4.3"></a>The export SHALL run a small fixed set of reference images through the PyTorch checkpoint (the equivalence oracle) and the Core ML artefact and SHALL fail unless per-pixel argmax agreement is > 99% and maximum absolute logit error is < 0.5 (amended by Decision 14: the original 0.05 bar predated any real FP16 export — measured FP16-compute drift is 0.13–0.30 on ~±20-magnitude logits while argmax agreement stays ≥ 0.9985); the TFLite artefact, when produced, SHALL be validated against the same PyTorch oracle, not against Core ML.  
4. <a name="4.4"></a>The exported model SHALL declare 27 output channels in the palette order of [3.3](#3.3); a channel-count mismatch SHALL fail the export.  
5. <a name="4.5"></a>The preprocessing applied before inference (colour space, normalisation, resize interpolation, and channel order) SHALL match the preprocessing used in training; the equivalence check of [4.3](#4.3) SHALL feed inputs through the runtime preprocessing path so a training/inference mismatch fails the export.  

### 5. Bundling and Loader Alignment

**User Story:** As an iOS app, I want the bundled segmenter loaded through the package resource pattern, so that a Release build runs the real model instead of throwing.

**Acceptance Criteria:**

1. <a name="5.1"></a>`segmenter.mlpackage` SHALL be declared as a bundled package resource in `Package.swift` and `PipelineFactory.makeSegmenter` SHALL load it via the `Bundle.module` pattern (aligning with `GRDBFoodDatabase.bundled()`), replacing the current `Bundle.main` lookup (architecture.md §9 known gap).  
2. <a name="5.2"></a>WHEN the bundled model is present, a Release build SHALL construct the Core ML pipeline without throwing `segmenterModelMissing`.  
3. <a name="5.3"></a>WHEN the bundled model is absent, the factory SHALL still throw `segmenterModelMissing` (the existing dev-stub path behind `DEV_STUB_SEGMENTER` is unchanged).  
4. <a name="5.4"></a>A meal produced by the Core ML path SHALL stamp `segmenterSource = "coreml_<modelVersion>"` (distinct from `"dev_stub"`), where `<modelVersion>` derives from the checkpoint SHA-256 of [1.3](#1.3) so a persisted meal is traceable to its exact model build.  

### 6. On-Device Verification (MVP Gate)

**User Story:** As an ML engineer, I want a real on-device estimate confirmed end-to-end, so that the MVP demonstrably produces a real carb number.

**Acceptance Criteria:**

1. <a name="6.1"></a>The exported model SHALL be verified Apple-Neural-Engine-resident in Xcode's Core ML performance report (a human-gated step requiring Xcode and a Mac) before the MVP gate is met.  
2. <a name="6.2"></a>A device capture run with the bundled Core ML segmenter on the v1 hardware floor (iPhone 13 Pro Max, a human-gated step) SHALL complete with `estimate.end success=true`, SHALL stamp `segmenterSource = "coreml_<modelVersion>"` (not the dev-stub tag), SHALL produce a finite carbohydrate value > 0, and SHALL produce a non-degenerate food mask whose coverage is plausible for the captured plate — a sanity check on the deployment distribution, distinct from the FoodSeg103 mIoU bar.  
3. <a name="6.3"></a>The MVP gate SHALL be met when the export-eligibility gates ([3.2](#3.2), [3.5](#3.5), [4.2](#4.2), [4.3](#4.3)), bundling ([5.2](#5.2)), ANE residency ([6.1](#6.1)), and the on-device run ([6.2](#6.2)) all hold; it SHALL NOT require β_c calibration or the v1 numeric-accuracy bar.  

### 7. Uncalibrated Honesty at MVP

**User Story:** As a user, I want an uncalibrated carb number labelled for what it is, so that I am not misled by the known volume bias.

**Acceptance Criteria:**

1. <a name="7.1"></a>At the MVP gate every class SHALL apply `β = 1.0` (`uncalibrated_unity`) — pooled β is unreachable until calibration data exists — and the meal record SHALL persist the `betaCalibrationStatus` used.  
2. <a name="7.2"></a>A meal whose carb number derives from an uncalibrated β SHALL surface a low-confidence indication consistent with the existing confidence-pill pattern in `ResultView`.  
3. <a name="7.3"></a>The uncalibrated indication SHALL convey that the estimate carries a known upward (over-estimating) volume bias, so the carbohydrate value is more likely high than low.  

### 8. β_c Calibration Process (Defined, Execution Deferred)

**User Story:** As an ML engineer, I want the calibration process defined and tracked, so that it can run unchanged once gravimetric data exists without re-blocking the MVP.

**Acceptance Criteria:**

1. <a name="8.1"></a>The spec SHALL define the β_c calibration process — gravimetric fixture capture, `HarnessCLI calibrate` over a checkpoint-pinned fixture set producing `beta.json`, and baking the table into `cofid_db.sqlite` via `tools/food_db/generate.py` — referencing `docs/ml-training.md` §§8–9.  
2. <a name="8.2"></a>The acquisition of ≥ 30 gravimetric meals per class SHALL be recorded as a human-gated step explicitly deferred past the MVP gate, and identified as the project's largest risk.  
3. <a name="8.3"></a>WHEN a class reaches ≥ 30 gravimetric meals and is calibrated, its `betaCalibrationStatus` SHALL change from uncalibrated to calibrated and the v1 accuracy bar (MAPE < 20%, MAE ≤ 25 g per MD-25 / pipeline Req 21.3) SHALL become measurable for that class via the existing accuracy harness.  
4. <a name="8.4"></a>Baking a β_c table SHALL preserve the palette↔DB edition lock (`meta.palette_version` matches `ClassPalette.version`); a mismatch SHALL fail the bake.  

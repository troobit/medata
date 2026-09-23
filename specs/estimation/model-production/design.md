# Model Production — Design

**Version:** 0.1.0
**Date:** 2026-06-29
**Status:** Draft
**Branch:** spec/model-production

This document describes the implementation design for the requirements in `requirements.md` and the decisions in `decision_log.md` (D1–D6). It cites requirements by ID; it does not restate them. It overlays the runtime architecture owned by `specs/estimation/pipeline/design.md` (§0, §9) and references the runbook `docs/ml-training.md` (§§1–11) as authoritative rather than duplicating commands.

---

## 1. Overview

Most of this spec is *process*, not code. The deliverable is a trained `segmenter.mlpackage` that is bundled, loaded through the package-resource pattern, and produces a real (uncalibrated, low-confidence) carb number on device. The design's spine is the **automated vs human/data-gated** split: a coding agent can execute the scripted stages and the loader/lineage/honesty code deltas; it cannot acquire a dataset, run a GPU, hold an iPhone, or weigh a meal. β_c calibration is defined and tracked but its execution is deferred (D5).

---

## 2. Architecture

### 2.1 Process model (Req [1.1](requirements.md#1.1), [1.2](requirements.md#1.2))

Ordered stages. "Automated" = scriptable/coding-actionable end-to-end. "Gated" = requires a dataset download, GPU, Mac+Xcode, or physical measurement a coding agent cannot perform. Runbook column cites `docs/ml-training.md`.

| # | Stage | Mode | Script / surface | Runbook | Gates produced |
|---|---|---|---|---|---|
| 0 | Acquire FoodSeg103 (Apache-2.0) | **gated** (download) | — | §1 | [2.4](requirements.md#2.4) |
| 1 | Build class mapping | automated | `tools/segmenter/build_class_mapping.py` → `class_mapping_foodseg103.json` | §2 | [2.1](requirements.md#2.1), [2.3](requirements.md#2.3) |
| 2 | Dataset prep + fixed-seed splits | automated | `tools/segmenter/prepare_dataset.py` → `data/foodseg103_remapped/` | §3 | [2.2](requirements.md#2.2) |
| 3 | Transfer-learn DeepLabV3+MobileNetV3-Large @513² | **gated** (GPU + dataset) | `tools/segmenter/train.py` → `build/checkpoint.pt` | §4 | [3.1](requirements.md#3.1) |
| 4 | Validate held-out mIoU + per-class IoU | automated (post-train) | validation harness | §5 | [3.2](requirements.md#3.2)–[3.6](requirements.md#3.6) |
| 5 | Export to Core ML (FP16) + oracle/parity/channel/budget gates | automated | `tools/segmenter/export.py` → `MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage` | §6 | [4.1](requirements.md#4.1)–[4.5](requirements.md#4.5) |
| 6 | Bundle + loader alignment | automated (code) | `Package.swift`, `PipelineFactory.makeSegmenter` | §7 | [5.1](requirements.md#5.1)–[5.4](requirements.md#5.4) |
| 7 | On-device verification (ANE residency + real capture) | **gated** (Mac+Xcode, iPhone 13 Pro Max) | Xcode Core ML perf report, capture run | §7 | [6.1](requirements.md#6.1)–[6.3](requirements.md#6.3) |
| 8 | Uncalibrated-honesty surfacing | automated (code) | `ResultView`, DB default already β=1.0 | — | [7.1](requirements.md#7.1)–[7.3](requirements.md#7.3) |
| 9 | β_c gravimetric fixtures | **gated/deferred** (weighed meals) | `tools/segmenter/make_fixtures.py` | §8 | [8.2](requirements.md#8.2) |
| 10 | β_c calibrate + bake | automated-when-data-exists (deferred) | `HarnessCLI calibrate` → `build/beta.json` → `tools/food_db/generate.py` | §9 | [8.1](requirements.md#8.1), [8.3](requirements.md#8.3), [8.4](requirements.md#8.4) |

The MVP gate (Req [6.3](requirements.md#6.3)) is met when stages 1–8 hold; stages 9–10 are tracked but off the MVP critical path (D3, D5).

**Stage 3 sequencing prerequisite — palette class-list lock.** The training run must not start until the palette class list is locked at the final v1: `ClassPalette.v1Standard` as redefined in place with the eight coarse liquid classes (24 solid + 8 liquid + 3 special = 35 channels; the enumerated ordered list lives in `MedataCore/Sources/Segmentation/ClassPalette.swift` and `tools/food_db/generate.py` FOOD_DATA). The trained checkpoint's output-channel count must match the shipped palette, so training against the pre-liquid layout would force a full retrain. Recorded per `specs/estimation/nutrition5k-calibration/` Req 9.4 (Decisions 22–23 of that spec); the checklist item lives in `prerequisites.md` under Training (Stage 3).

Refinement discipline (Req [1.4](requirements.md#1.4)): a change to any stage updates this table **and** the corresponding `ml-training.md` section in the same change; the per-class floor and set in [3.5](requirements.md#3.5)/[3.6](requirements.md#3.6) and the mask-plausibility bound in [6.2](requirements.md#6.2) are explicitly tunable against the first real run.

### 2.2 Integration points (name the symbol)

| Concern | Symbol / file |
|---|---|
| Loader (the §9 known gap) | `Pipeline.makeSegmenter` — `MedataCore/Sources/Pipeline/PipelineFactory.swift:55-74` |
| Source tag | `Pipeline.segmenterSourceTag` — `PipelineFactory.swift:79-85`; stamped at `Pipeline.swift:435` into `MealRecord.segmenterSource` (`MealRecord.swift:20`) |
| modelVersion source | `CoreMLInferenceEngine.modelVersion` — resolved from model metadata via `CoreMLSegmenter.resolveModelVersion` (`CoreMLSegmenter.swift:154`); falls back to `"v0.1"` (`:149`) when the key is absent |
| Runtime wrapper | `CoreMLInferenceEngine` init — `CoreMLSegmenter.swift:146-182` (CHW/HWC detect, channel count, `SegmentationError.modelLoadFailed`) |
| Weights budget | `SegmenterWeightsBudget.validate(at:)` — `CoreMLSegmenter.swift:94-101` (`maxBytes = 10*1024*1024`) |
| Palette | `ClassPalette.v1Standard` / `.version="v1"` — `ClassPalette.swift:41-53` |
| Resource exemplar | `Foods` target `.copy("Resources/cofid_db.sqlite")` — `Package.swift:75-84`; pattern `GRDBFoodDatabase.bundled()` — `GRDBFoodDatabase.swift:23-32` |
| Honesty UI | `ConfidencePill` (`App/ConfidencePill.swift:11-56`), `ConfidenceLevel` (`App/ResultView.swift:11-41`), pill render `ResultView.swift:156`, very-low surface `ResultView.swift:220-248` |
| Calibration status | `BetaCalibrationStatus` (`FoodEntry.swift:41-45`), stamped `Pipeline.swift:428-429` → `MealRecord.perClassCalibration` (`MealRecord.swift:28`) |
| β bake lock | `tools/food_db/generate.py:120-148` (defaults), `:136-137` (`meta.palette_version='v1'`) |

### 2.3 Bundle.main parity audit (Req [5.1](requirements.md#5.1))

The known gap names one loader. Before declaring the audit closed, sweep for any other model-resource lookup that uses `Bundle.main` rather than `Bundle.module`:

- Search `MedataCore/Sources/**` and `App/**` for `Bundle.main.url(forResource:` and `Bundle.main.path(forResource:`.
- The only model resource is `segmenter.mlpackage` at `PipelineFactory.swift:61`. The pre-shutter segmenter (`Pipeline.makeSegmenter`, App-target caller) shares this same loader, so fixing the one call site fixes both pre-shutter and in-shutter paths.
- Food DB already uses `Bundle.module` (`GRDBFoodDatabase.swift:24`); Metal kernels use `.copy("Kernels")` resource. No other model lookups expected — the audit records the grep result, not an assumption.

---

## 3. Components and Interfaces (code deltas)

### 3.1 Loader alignment (Req [5.1](requirements.md#5.1)–[5.3](requirements.md#5.3))

The loader lives in the **`Pipeline`** target. `Bundle.module` resolves resources from the *target's own* source directory, so the resource must be declared on `Pipeline` and live under `MedataCore/Sources/Pipeline/`. SPM forbids resources outside the target dir — therefore the export output path moves (Req [4.1](requirements.md#4.1) path string) and three references must stay in lockstep:

1. `export.py` output → `MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage` (was `MedataCore/Resources/segmenter.mlpackage`).
2. `Package.swift` `Pipeline` target gains `resources: [.copy("Resources/segmenter.mlpackage")]` (mirrors the `Foods` exemplar at `Package.swift:75-84`).
3. `.gitignore` and `architecture.md:393` canonical-name references update together (Req [1.4](requirements.md#1.4) "do not diverge").

Loader change at `PipelineFactory.swift:61` (inside the `#else`/non-stub branch only):

```swift
guard let modelURL = Bundle.module.url(           // was Bundle.main
    forResource: "segmenter", withExtension: "mlpackage"
) else { throw PipelineFactoryError.segmenterModelMissing }   // unchanged
```

Invariants held: the `#if DEV_STUB_SEGMENTER` branch (`:57-59`) is untouched ([5.3](requirements.md#5.3)); `segmenterModelMissing` still thrown when absent ([5.3](requirements.md#5.3)); with the resource declared, a Release build constructs without throwing ([5.2](requirements.md#5.2)).

### 3.2 segmenterSource / modelVersion derivation (Req [5.4](requirements.md#5.4), [1.3](requirements.md#1.3))

`segmenterSourceTag` (`PipelineFactory.swift:105`) stamps `CoreMLInferenceEngine.modelVersion`, which now resolves from the loaded model's `medata.modelVersion` metadata (`CoreMLSegmenter.swift:154`), falling back to `"v0.1"` only when the key is absent. Req [5.4](requirements.md#5.4) requires `<modelVersion>` to derive from the checkpoint SHA-256 so a persisted `MealRecord` is traceable to its exact build.

Design: make the model self-describing rather than carry a constant.

- `export.py` writes a short checkpoint id (first 12 hex of the checkpoint SHA-256 from the lineage manifest, §3.3) into the Core ML model's `userDefinedMetadata` under key `medata.modelVersion`.
- `CoreMLInferenceEngine.modelVersion` changes from a static `String` to a value read off the loaded `MLModel` metadata at init (`CoreMLSegmenter.swift:146-182`), defaulting to the constant only if absent (back-compat for any test fixture without the key).
- `segmenterSourceTag` then yields `coreml_<sha12>` (e.g. `coreml_a1b2c3d4e5f6`), distinct from `dev_stub`.

This keeps a single source of truth (the baked model), survives bundling, and needs no separate manifest at runtime. The full lineage manifest (§3.3) remains the build-time record; only the 12-hex prefix travels into the meal.

### 3.3 Build lineage manifest (Req [1.3](requirements.md#1.3))

`train.py`/`export.py` emit `build/lineage.json` recording the inputs needed to reproduce a build to *metric* level (a re-run meets the same mIoU bar), not byte-identity:

```jsonc
{
  "checkpoint_sha256": "a1b2c3d4e5f6…",   // full hash; 12-hex prefix → modelVersion
  "foodseg103_source": "v1.0 (release tag / archive sha)",
  "split_seed": 1337,                       // fixed seed, Req 2.2
  "class_mapping_version": "v1",            // class_mapping_foodseg103.json
  "palette_version": "v1",                  // ClassPalette.version, Req 2.3
  "train_config": { "arch": "deeplabv3_mobilenetv3_large", "input": 513, "epochs": …, "lr": … },
  "code_commit": "<git rev>",
  "metrics": { "mean_iou": 0.62, "per_class_iou": { … }, "carb_priority_iou": { … } }
}
```

`metrics` carries the validation output (Req [3.3](requirements.md#3.3)) and, on a sub-bar build, the recorded shortfall (Req [3.4](requirements.md#3.4)). The manifest is the artefact Req [1.3](requirements.md#1.3) calls "lineage"; `checkpoint_sha256` is the join key to `segmenterSource`.

### 3.4 Export gates (Req 4) — `export.py` behavior changes

| Gate | Req | export.py behavior |
|---|---|---|
| FP16 export | [4.1](requirements.md#4.1) | unchanged (FP16 already) |
| Weights ≤ 10 MB | [4.2](requirements.md#4.2) | recursively sum `.mlpackage` dir; mirror `SegmenterWeightsBudget.validate` (`CoreMLSegmenter.swift:94-101`); fail on over-budget |
| Equivalence oracle | [4.3](requirements.md#4.3) | **changed**: oracle is now the **PyTorch checkpoint**, not the Core ML model. Run the fixed reference set through `checkpoint.pt` *and* the exported artefact; fail unless per-pixel argmax agreement > 99% **and** max abs logit error < 0.05. The current CoreML-vs-TFLite comparison is replaced; TFLite, when produced, is validated against the **same PyTorch oracle** (not against Core ML). |
| Channel count = 27 | [4.4](requirements.md#4.4) | assert exported model declares 27 output channels in `ClassPalette.v1Standard` order; fail on mismatch (runtime also detects via `CoreMLInferenceEngine` channel resolution `:146-182`) |
| Preprocessing parity | [4.5](requirements.md#4.5) | **new**: feed oracle inputs through the **runtime preprocessing path** (colour space, normalisation, resize interpolation, channel order matching training and `SegmenterPreProcessor.defaultTargetSize`). A training/inference preprocessing mismatch must surface as an oracle failure, not pass silently. |

The two substantive `export.py` changes are: (a) the oracle reference flips to the PyTorch checkpoint and feeds through runtime preprocessing (D6); (b) lineage emission (§3.3) and metadata stamping (§3.2).

### 3.5 Uncalibrated-honesty surface (Req [7.1](requirements.md#7.1)–[7.3](requirements.md#7.3))

State already present:
- β = 1.0 / `uncalibrated_unity` is the DB default for every class (`tools/food_db/generate.py:120-148`); **no change** needed for [7.1](requirements.md#7.1)'s value.
- `MealRecord.perClassCalibration` already persists the `BetaCalibrationStatus` used (`Pipeline.swift:428-429`, `MealRecord.swift:28`) — satisfies [7.1](requirements.md#7.1)'s "persist the status".

Change needed for [7.2](requirements.md#7.2)/[7.3](requirements.md#7.3): the existing `ConfidencePill` keys on σ thresholds (`ResultView.swift:11-41`), which is *uncertainty width*, not *calibration status*. An uncalibrated meal must be flagged on its own axis. Design:

- In `ResultView`, when `meal.perClassCalibration` is `uncalibrated_unity` (or any non-`calibrated` value), render a low-confidence indication consistent with the pill pattern (reuse `ConfidencePill` styling / the very-low surface at `ResultView.swift:220-248`).
- Copy must convey **direction**: the estimate carries a known **upward (over-estimating) volume bias** — the carbohydrate value is more likely high than low ([7.3](requirements.md#7.3)). One new copy string (metric-only, English) near the pill render at `ResultView.swift:156`; no new view type.

This is distinct from the existing `dev_stub` placeholder banner (which marks *fake* numbers); this marks a *real but uncalibrated* number.

### 3.6 β_c calibration process (defined, deferred — Req 8)

Defined pipeline, execution human-gated/deferred (D5):

```
weighed meals (≥30/class, GATED) → make_fixtures.py (SHA-256-stamped, checkpoint-pinned)
   → HarnessCLI calibrate  (HarnessCLI/main.swift:155-174 → BetaCalibrator.calibrate)
   → build/beta.json
   → tools/food_db/generate.py  (bake table into cofid_db.sqlite)
```

- All harness code is under `#if HARNESS_ENABLED` (`Package.swift:7-16`); never in the iOS app target. No code change required now — the path is wired (pipeline tasks 58–65).
- Bake lock (Req [8.4](requirements.md#8.4)): `tools/food_db/generate.py:197,221` must set `meta.palette_version='v1'` matching `ClassPalette.version` (`ClassPalette.swift`); a mismatch fails the bake.
- On calibration of a class (Req [8.3](requirements.md#8.3)): its `foods.beta_status` flips `uncalibrated_unity` → `calibrated` (persisted via `GRDBFoodDatabase.swift:118-119`), at which point the §3.5 honesty surface stops flagging it and the v1 accuracy bar (MAPE < 20%, MAE ≤ 25 g — pipeline Req 21.3 / MD-25) becomes measurable for that class via the existing accuracy harness.
- Fixtures + the ≥30-meals/class acquisition (Req [8.2](requirements.md#8.2)) are recorded as the project's largest risk and explicitly deferred past the MVP gate. Cite `ml-training.md` §§8–9; do not re-document the commands.

---

## 4. Data Models

| Model | Change |
|---|---|
| `build/lineage.json` | **new** build-time manifest (§3.3). Not shipped; build provenance only. |
| Core ML `userDefinedMetadata["medata.modelVersion"]` | **new** 12-hex checkpoint id stamped by `export.py` (§3.2). |
| `MealRecord.segmenterSource` (`MealRecord.swift:20`) | value space gains `coreml_<sha12>` (was `coreml_v0.1`); no schema change. |
| `MealRecord.perClassCalibration` (`MealRecord.swift:28`) | unchanged field; now read by the honesty surface (§3.5). |
| `CoreMLInferenceEngine.modelVersion` | was static `String`; becomes instance value read from model metadata (§3.2). |

No persistence-schema (proto) change: both meal fields already exist.

---

## 5. Error Handling

New / relevant failure modes, all fail **before** a bad artefact ships or a bad meal persists:

| Failure | Where | Behavior |
|---|---|---|
| Mapping reorders/drops a channel | dataset prep (stage 1–2) | fail before training (Req [2.3](requirements.md#2.3)) |
| Held-out mIoU < 0.48 or carb-priority IoU < 0.45 (re-derived bars, segmenter-foundation Decisions 5 and 14; were 0.60/0.50 — see `specs/estimation/segmenter-foundation/`) | validation (stage 4) | not export-eligible; shortfall recorded in `lineage.metrics` (Req [3.4](requirements.md#3.4)); fallback per [3.6](requirements.md#3.6) (flag low-confidence or map to `unknown_food`) |
| Equivalence oracle fail (argmax ≤ 99% or logit ≥ 0.05) | `export.py` (stage 5) | export fails (Req [4.3](requirements.md#4.3)) |
| Preprocessing mismatch | `export.py` via oracle (stage 5) | surfaces as oracle fail (Req [4.5](requirements.md#4.5)) |
| Channel count ≠ 27 | `export.py` + runtime | export fails; runtime `SegmentationError.modelLoadFailed` (Req [4.4](requirements.md#4.4)) |
| Weights > 10 MB | `export.py` + `SegmenterWeightsBudget.validate` | export fails / `SegmentationError.weightsBudgetExceeded` (Req [4.2](requirements.md#4.2)) |
| Model absent in bundle | `PipelineFactory.makeSegmenter` | `PipelineFactoryError.segmenterModelMissing` (Req [5.3](requirements.md#5.3)) |
| Palette↔DB edition mismatch | `tools/food_db/generate.py:197,221` | bake fails (Req [8.4](requirements.md#8.4)) |

Out of scope (D6): bad-model rollback / integrity / kill-switch — recovery is rebuilding and shipping the previous bundle until OTA exists.

---

## 6. Testing Strategy

Code-verifiable (unit/integration, no hardware):

- Loader resolves the bundled resource via `Bundle.module` and constructs without throwing when present; throws `segmenterModelMissing` when absent (Req [5.1](requirements.md#5.1)–[5.3](requirements.md#5.3)). Uses a tiny fixture `.mlpackage` or the real one once it lands.
- `SegmenterWeightsBudget.validate` rejects an over-budget package (Req [4.2](requirements.md#4.2)).
- Channel-count resolution in `CoreMLInferenceEngine` (Req [4.4](requirements.md#4.4)).
- `segmenterSourceTag` derivation: given a model whose metadata carries a known id, the tag is `coreml_<id>` (Req [5.4](requirements.md#5.4)).
- Palette↔DB lock: `generate.py` bake fails on a `palette_version` mismatch (Req [8.4](requirements.md#8.4)).
- Export oracle/parity/channel/budget are testable as `export.py`-level checks against a fixed reference set (Req [4.3](requirements.md#4.3)–[4.5](requirements.md#4.5)) — verifiable once a checkpoint exists (so gated on stage 3 output).
- Honesty surface: a meal with `perClassCalibration == uncalibrated_unity` drives the low-confidence indication (Req [7.2](requirements.md#7.2)); copy asserts upward-bias wording (Req [7.3](requirements.md#7.3)).

Per the testing-minimal posture, keep additions to focused MedataCore tests; verify app/UI by build + on-device, not new UI tests.

Human/data-gated, **not** unit-testable:

- FoodSeg103 acquisition (Req [2.4](requirements.md#2.4)); GPU training (Req [3.1](requirements.md#3.1)); the mIoU/per-class bars themselves (Req [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.5](requirements.md#3.5)) — produced by a GPU run, asserted by the harness but not reproducible in CI.
- ANE residency in Xcode's Core ML performance report (Req [6.1](requirements.md#6.1)).
- On-device capture run asserting `estimate.end success=true`, `segmenterSource = coreml_<…>`, finite carb > 0, and non-degenerate/plausible mask coverage (Req [6.2](requirements.md#6.2)). `estimate.end` is DEBUG-only (`Pipeline.swift:468-473`); carb from `PbMacroResult.totalCarbsG` (`Pipeline.swift:394-398`). Plausibility is a deployment-distribution sanity check, distinct from FoodSeg103 mIoU.
- β_c gravimetric fixtures and calibration execution (Req [8.2](requirements.md#8.2), [8.3](requirements.md#8.3)).

---

## 7. Self-Review

Every requirement maps to a design element:

| Req | Design element |
|---|---|
| [1.1](requirements.md#1.1) | §2.1 process table |
| [1.2](requirements.md#1.2) | §2.1 Mode column |
| [1.3](requirements.md#1.3) | §3.3 lineage manifest |
| [1.4](requirements.md#1.4) | §2.1 refinement discipline; §3.1 lockstep references |
| [2.1](requirements.md#2.1)–[2.4](requirements.md#2.4) | §2.1 stages 0–2; §5 channel-order fail |
| [3.1](requirements.md#3.1)–[3.6](requirements.md#3.6) | §2.1 stages 3–4; §3.3 metrics; §5 IoU rows |
| [4.1](requirements.md#4.1)–[4.5](requirements.md#4.5) | §3.4 export gate table |
| [5.1](requirements.md#5.1)–[5.4](requirements.md#5.4) | §2.3 audit; §3.1 loader; §3.2 modelVersion |
| [6.1](requirements.md#6.1)–[6.3](requirements.md#6.3) | §2.1 stage 7; §6 human-gated list |
| [7.1](requirements.md#7.1)–[7.3](requirements.md#7.3) | §3.5 honesty surface |
| [8.1](requirements.md#8.1)–[8.4](requirements.md#8.4) | §3.6 deferred calibration; §5 lock row |

No requirement is unmapped.

Human-gated acceptance criteria (not code-verifiable; pass only by a person/dataset/hardware): [2.4](requirements.md#2.4), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.5](requirements.md#3.5) (bars produced by a GPU run), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3). [6.3](requirements.md#6.3) is a composite that resolves only once its human-gated members hold.

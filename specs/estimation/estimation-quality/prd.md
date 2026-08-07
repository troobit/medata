# PRD: MVP estimation quality — kill the mask speckle and stabilise carb readings

## Product summary

MeData estimates carbohydrate content from 1–2 iPhone photos using a fully offline, deterministic pipeline: Core ML semantic segmentation of the food, LiDAR/visual-hull volume geometry, and a per-class density factor (β_c) applied against a bundled food-composition database. Target repository: `medata` (this repo; work lands on the `research` line via the PRD/engage lane).

Two user-visible defects motivate this PRD. First, the food-image overlay shows **visual "linear stripes of spots"** — speckled, incoherent per-pixel classification. Second, carb **readings are very inconsistent** between captures of the same plate. Past bug rounds (`2d25bbb`, `06b86fa`, `09aab63`) repeatedly root-caused the visual artefact and misclassification to segmenter model quality: the shipped model (`coreml_0295ea61edd9`, later `24e0b022241a`) reaches only ~0.40–0.43 held-out mean food-class IoU, below the 0.60 gate (bars since re-derived to 0.48/0.45 — segmenter-foundation D5/D14), and ships under a developer-phase override. The stride/format path (YCbCr→RGB) was audited clean 2026-07-06 — this is **not** a colour-space or byte-layout bug; do not re-audit strides.

The root technical finding this PRD acts on: `tools/segmenter/train.py` trains DeepLabV3+MobileNetV3-Large with a **plain, unweighted `nn.CrossEntropyLoss`** over a heavily class-imbalanced 35-class palette (24 solids + 8 liquids + 3 sentinels). Under class imbalance, unweighted CE collapses toward the dominant background class (device masks are 92–99% background, `topClass=34`), and the residual food pixels come through as isolated speckle — the "stripes of spots". The highest-leverage offline work is therefore: (a) research and specify a class-imbalance-aware training recipe and any better-fit architecture; (b) land that recipe as configurable, test-backed code; (c) add a deterministic post-inference mask cleanup that removes speckle regardless of model quality; and (d) reduce carb-reading variance in the deterministic geometry/β chain. Actually running a long training job, exporting/swapping the shipped model, calibrating β against gravimetric data, and on-device verification are compute/data/human-gated and are flagged as STOP points, not executed autonomously.

## Goals

- Produce a rigorous written analysis of why held-out food-class IoU is stuck at ~0.40 and a prioritised, concrete recommendation of training-recipe and algorithmic changes to try next (new loss functions, class balancing, augmentation, architecture/backbone options within the 24 MiB ANE budget).
- Land a class-imbalance-aware training recipe in `tools/segmenter/` as **configurable, off-by-default** options (weighted CE / focal / dice / combined loss; photometric augmentation), fully covered by the existing torch-free unit-test approach, so the next training run is a single command away.
- Add a **deterministic, offline** mask post-processing cleanup step that removes isolated-pixel speckle and consolidates the food silhouette, directly reducing the "stripes of spots" on the overlay independent of model quality — with the existing MedataCore math tests kept green.
- Reduce carb-reading run-to-run variance in the deterministic volume/plane-fit/β application path via conservative, additive robustness (outlier rejection / guards), with the change reviewable in the diff and existing tests green.
- Preserve every hard invariant: no LLM and no network anywhere in the estimation path; fully deterministic and offline.

## Non-goals

- **No actual segmenter training run, model export, or model swap.** These are compute-gated (multi-hour local MPS / GPU) and change the shipped artefact; they are STOP points. This PRD prepares the recipe and leaves the run to the human loop.
- **No re-audit of the YCbCr→RGB / stride / pixel-format path.** It was audited clean (`pipeline-factory-parked` memory, 2026-07-06); the artefact is model quality plus missing spatial regularisation, not a format bug.
- **No β gravimetric data collection and no full Nutrition5k (181 GB) ingestion.** β coverage improvement that needs the gravimetric set or the N5k download stays a recommendation in the research deliverable, routed to the existing `nutrition5k-calibration` / `cross-dataset-calibration` specs — not executed here.
- **No new UI, no UI test scaffolding, no new Swift test target.** The app test gate stays "builds + looks right on device"; keep the MedataCore math tests green and do not add UI tests (per CLAUDE.md test gate).
- **No changes to the class palette, the food databases, or the palette↔DB bake lock.** Palette/DB changes carry their own sequencing and gates.
- **No spec-gate bypass for architecture-level estimation redesigns.** Anything beyond conservative additive changes is written up as a recommendation for the proper spec/decision-log gate, not landed directly.

## Segmentation approach research

Covers a written research deliverable only — no runtime or training-code changes. Output lands as a markdown analysis under `docs/agent-notes/` (e.g. `segmenter-improvement-research.md`), cross-linked from `docs/ml-training.md` §11 (iteration loop).

1. The research MUST diagnose, with evidence from the current code and shipped-model metrics, why held-out mean food-class IoU plateaus at ~0.40–0.43.
   - Acceptance: the document identifies the concrete contributing factors present in `tools/segmenter/train.py` today (unweighted `nn.CrossEntropyLoss`, geometry-only augmentation, MobileNetV3-Large capacity, ~5.5k-image train split, 35-class imbalance) and states which are most likely load-bearing, citing the per-class IoU shortfalls recorded in `build/lineage.json` / `docs/agent-notes/model-production.md`.
   - Acceptance: it explicitly connects the "linear stripes of spots" symptom to the absence of class-imbalance handling and spatial regularisation, consistent with the prior "model quality, not a format bug" conclusion.
2. The research MUST recommend a prioritised set of training-recipe and algorithmic changes to try, each with expected effect, cost, and risk.
   - Acceptance: covers, at minimum, loss-function options (class-weighted CE, focal, dice/Tversky, combined), class-balancing/sampling, photometric augmentation, and at least one architecture/backbone alternative evaluated against the 24 MiB weight budget (`SegmenterWeightsBudget.maxBytes`) and Apple Neural Engine residency constraint.
   - Acceptance: each recommendation is ranked (highest expected IoU-per-effort first) and names the file(s) it would touch.
3. The research SHOULD recommend how to improve carb-reading consistency and β coverage without new hand-measured data where possible, routing anything data-gated to the correct existing spec.
   - Acceptance: names concrete levers in the volume/plane-fit/β application chain and, for β, points at `specs/estimation/cross-dataset-calibration/` and `specs/estimation/nutrition5k-calibration/` rather than proposing direct edits here.
4. The research SHOULD define a lightweight offline metric to compare recipe variants without a device.
   - Acceptance: specifies how `tools/segmenter/run_validation.py` held-out IoU (and per-staple IoU) is used to accept/reject a variant, and what threshold constitutes an improvement worth a device deploy.

## Segmenter training pipeline

Covers `tools/segmenter/` (Python; `train.py`, and its torch-free unit-tested helpers). All new behaviour is **opt-in via flags and defaults to the current recipe**, so no existing run changes unless explicitly requested. Read `docs/agent-notes/model-production.md` and `docs/agent-notes/dataset-strategy.md` before editing; never edit `train.py` while a training run is live (DataLoader `spawn` re-imports it).

1. The training pipeline MUST offer a class-imbalance-aware loss as a configurable option, defaulting to the current unweighted cross-entropy.
   - Acceptance: a CLI flag (e.g. `--loss {ce,weighted_ce,focal,dice,combined}`) selects the loss; omitting it reproduces today's `nn.CrossEntropyLoss` behaviour byte-for-byte in the recorded `train_config`.
   - Acceptance: the selected loss and any weighting scheme are recorded in the checkpoint and `build/lineage.json` `train_config`, so a run is reproducible from lineage.
2. The training pipeline MUST express the loss selection and any class-weight computation as pure, torch-free-testable helpers.
   - Acceptance: new unit tests under `tools/segmenter/tests/` cover the weight-derivation and loss-selection logic and pass without torch installed (matching the existing test pattern for `export.py`/`validation.py`).
   - Acceptance: `make test` (or the tools' pytest path) stays green; no test requires a GPU, a dataset, or torch to pass.
3. The training pipeline SHOULD add photometric (colour/brightness/contrast) augmentation as an opt-in complement to the existing geometry-only augmentation.
   - Acceptance: a flag enables photometric augmentation applied to the image only (never the mask), off by default, recorded in `train_config`.
4. The training pipeline SHOULD document the recommended next run as a single copy-pasteable command.
   - Acceptance: `docs/ml-training.md` §4 gains a ready-to-run command reflecting the new recommended flags, consistent with the resume/`caffeinate` run-hygiene guidance already there.

## Mask post-processing cleanup

Covers `MedataCore/Sources/Segmentation/` (primarily `PostProcessing.swift`, with `ClassColourTable.swift` / overlay colourisation as the consumer). This is a **deterministic, offline** transform of the argmax label map — it does not call the model, the network, or add any nondeterminism. Read `docs/agent-notes/ui-capture-flow.md` and the `pipeline-factory-parked` memory before editing.

1. The post-processing step MUST add a deterministic spatial-regularisation pass over the argmax label map that removes isolated-pixel speckle before the silhouette and overlay are derived.
   - Acceptance: a pure function (e.g. connected-component / morphological majority filter with a minimum-region threshold) reassigns speckle pixels to their dominant neighbour class; identical input always yields identical output.
   - Acceptance: the cleanup runs on the label map only and does not alter the σ_seg / top-probability computation contract described in `PostProcessing.swift`, or the change to that contract is explicit and covered by a test.
2. The post-processing step MUST reduce visible speckle on a representative noisy mask while preserving a coherent food silhouette.
   - Acceptance: a unit test constructs a synthetic speckled label map and asserts the cleanup removes sub-threshold isolated regions while leaving a large contiguous food region intact (area preserved within a stated tolerance).
3. The post-processing step SHOULD be tunable and safe to disable.
   - Acceptance: the minimum-region threshold is a named constant/parameter, and a no-op/passthrough configuration reproduces the pre-change behaviour exactly.
4. The MedataCore math test suite MUST stay green.
   - Acceptance: `make test` passes; report BOTH the XCTest and swift-testing totals (per CLAUDE.md); no new UI test target is added.

## Estimation runtime consistency

Covers the deterministic geometry/β chain in `MedataCore/Sources/` — `SupportPlane/LiDARPlaneFitter.swift`, `Volume/` (`VoxelCarveEstimator.swift`, `HeightFieldEstimator.swift`), and the β application in `Pipeline/PipelineEstimator.swift` / `Pipeline.swift`. Changes here are **conservative and additive** (robustness guards, outlier rejection), not a redesign of the documented estimation contract. Read the relevant `docs/agent-notes/` module note before touching a module.

1. The runtime MUST reduce run-to-run carb-reading variance for the same plate via conservative robustness in the volume/plane-fit path, without changing the deterministic, offline contract.
   - Acceptance: at least one identified variance source (e.g. plane-fit inlier selection, voxel-carve boundary sensitivity, or β application on near-empty masks) is hardened with an additive guard, and the rationale is stated in the diff/commit and the module's agent note.
   - Acceptance: no LLM and no network are introduced; the path stays fully deterministic (identical inputs → identical output).
2. The runtime SHOULD fail closed and legibly when the mask is near-empty rather than emitting a wildly variable number.
   - Acceptance: when food coverage is below a stated threshold the estimate is refused or flagged consistently (reusing existing `EstimationFailure` semantics), and this is covered by a unit test.
3. The MedataCore math test suite MUST stay green, and the change MUST be individually reviewable.
   - Acceptance: `make test` passes (report both totals); the change is scoped so its diff can be reviewed without reading this conversation.

## Execution notes

- Quality gates (root `Makefile`): `make build` (SwiftPM core), `make test` (reports TWO totals — XCTest and swift-testing; report both), `make spell` (via `tools/check_spelling.sh`). Python tools use their existing pytest suites under `tools/*/tests/` and must stay torch-free-passing. App/device targets (`make build-app`, `make deploy-release`, `make logs-device`) are human/device-gated — do not invoke autonomously.
- Ordering: **Segmentation approach research** is authored first; its ranked recommendations refine the priorities of the **Segmenter training pipeline** context. The two contexts are still independently implementable — the training-pipeline direction (class-imbalance-aware loss + photometric augmentation as opt-in flags) is well-justified on its own, and the research validates/reprioritises rather than blocks it. **Mask post-processing cleanup** and **Estimation runtime consistency** are independent of both and of each other.
- Every landed code change must keep the estimation path deterministic and offline (hard invariant) and pass `make spell`.
- STOP — actually running a segmenter training job (multi-hour local MPS / GPU), exporting to Core ML, and swapping the bundled `segmenter.mlpackage` is human/compute-gated. Autonomous work stops at "the improved recipe is landed, tested, and the run command is documented".
- STOP — on-device verification (deploy a rebuilt model, capture a plate, confirm the overlay speckle is gone and readings are stable) requires a physical iPhone and a human; it is the real acceptance gate for the model-quality half and cannot be automated.
- STOP — β_c coverage improvement that needs gravimetric measurements or the full Nutrition5k download is data-gated; it stays a recommendation routed to `nutrition5k-calibration` / `cross-dataset-calibration`, not executed here.
- Process note: the estimation subsystem historically routes changes through spec/decision-log gates (`docs/agent-notes/dataset-strategy.md`). Under the autonomy flag this PRD lands conservative, test-backed code directly, but any architecture-level redesign surfaced by the research must be written up for the proper gate rather than landed here.

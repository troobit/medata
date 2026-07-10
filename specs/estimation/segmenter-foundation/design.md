# Segmenter Foundation — Design

**Version:** 0.1.0
**Date:** 2026-07-10
**Status:** Draft
**Branch:** estimation/model-foundation

This document describes the implementation design for the requirements in `requirements.md` and the decisions in `decision_log.md` (Decisions 1–4 as drafted; Decisions 5–9 added by this design pass, §8). It cites requirements by ID; it does not restate them. It overlays the production process owned by `specs/estimation/model-production/design.md` (§2.1) and the runtime architecture owned by `specs/estimation/pipeline/design.md`, referencing both rather than duplicating them. The driving research is `docs/agent-notes/model-foundation-research.md`.

---

## 1. Overview

This spec answers three questions the shipped segmenter has left open: what accuracy bar is actually achievable on FoodSeg103 ([Req 1](requirements.md#1-re-derived-accuracy-gate)), what training-recipe change gets the current architecture closest to it ([Req 2](requirements.md#2-training-recipe-upgrade-primary-lever)), and whether a backbone swap is worth its conversion risk ([Req 3](requirements.md#3-backbone-swap-track-gated-on-conversion-spike)). It does not touch `tools/segmenter/` code, run training, or change the production process — it decides the *foundation* that `model-production` (process) and the `debug-read` estimation-quality PRD (the next code landing in `tools/segmenter/`) build against.

The design's spine, same as `model-production`, is the **automated vs human/compute-gated** split: a coding agent can write the gate derivation, the recipe specification, and the conversion-spike procedure; it cannot run the GPU training job, measure on-device ANE latency, or judge the spike's pass/fail against real numbers. Every task below is marked accordingly.

---

## 2. Sequencing and prerequisites

### 2.1 This spec depends on the estimation-quality PRD landing first

`tools/segmenter/` is owned this cycle by the **estimation-quality PRD** (`specs/estimation/estimation-quality/prd.md`, branch `debug-read`), specifically its "Segmenter training pipeline" context. That PRD lands, as code:

- a `--loss {ce,weighted_ce,focal,dice,combined}` flag on `tools/segmenter/train.py` (class-imbalance-aware loss, default reproduces today's unweighted `nn.CrossEntropyLoss`);
- pure, torch-free-testable helpers for loss selection and class-weight derivation, unit-tested under `tools/segmenter/tests/`;
- opt-in photometric augmentation (image-only, off by default);
- the recorded run command in `docs/ml-training.md` §4.

Its own gated stage 6 (STOP — run the actual training job, export, and swap the bundled model) is explicitly **not** executed by that PRD; it is left as a human/compute-gated follow-on, same shape as the gated tasks in this spec.

**Consequence for this spec's task sequencing:** Requirement 2 (training-recipe upgrade) specifies the recipe this spec wants — MIM-pretrained checkpoint initialisation, a class-imbalance countermeasure targeting the eight carb-priority staples, and a checkpoint-vs-baseline comparison protocol — but it does not re-implement the `--loss` flag plumbing; that is `debug-read`'s code to land. This spec's design tasks (recipe specification, checkpoint sourcing/licensing) can proceed independently and in parallel with that PRD, since they produce specification and lineage-recording requirements rather than `tools/segmenter/` edits. But the **gated training run** that exercises Requirement 2 cannot start until:

1. `debug-read`'s "Segmenter training pipeline" context has merged (the `--loss` flag and class-weight helpers exist to run against), **and**
2. this spec's gate-derivation decision (§3 below) is logged, **and**
3. the palette class-list lock already recorded in `model-production/prerequisites.md` still holds (it does — no palette change is in scope here, Non-Goal).

This is a hard sequencing dependency, not a suggestion: the recipe upgrade's countermeasure (Req [2.3](requirements.md#2.3)) is exactly the class-imbalance loss `debug-read` is landing. Re-implementing it here would fork the same code change across two branches. The task list (§6) marks the training-recipe tasks that touch `tools/segmenter/` as blocked on that merge; the tasks that do not (checkpoint sourcing, gate derivation, spike procedure) are not blocked and can run now.

### 2.2 Merge order

`estimation/model-foundation` (this spec) and `debug-read` (the PRD) are independent branches today. Before Requirement 2's gated training run can be scheduled, `debug-read`'s training-pipeline context must land on whichever branch will run the training (`research` or a branch rebased on it). This spec's own merge to `research` does not need to wait — its requirements/design/decision_log are additive documentation — but its **task completion** for the training-touching tasks does wait. This is recorded as a blocked-by relationship in `tasks.md`, not a spec-level gate.

---

## 3. Requirement 1 — Re-deriving the accuracy gate

### 3.1 Inputs to the derivation (Req [1.1](requirements.md#1.1))

Three named inputs, per the research (`docs/agent-notes/model-foundation-research.md`, "Headline finding"):

| Input | Value | Source |
|---|---|---|
| Published FoodSeg103 frontier at a comparable parameter budget | SOTA ≈ 0.52 mIoU (HDF, 52.25%, 100M+ params); mid-size transformer backbones (BEiT v2-L, 441M) reach 49.4%; **no published model at any size clears 0.60** | Research Q0/headline; Swin-TUNA 50.56% (arXiv 2507.17347), HDF 52.25% (10.1007/s11694-025-03647-2), BEiT v2-L 49.4% (arXiv 2306.09203) |
| Shipped baseline | 0.4054 mean food-class IoU (`checkpoint_letterbox.pt`, `model_version=24e0b022241a`), held-out split, `run_validation.py` | `model-production/prerequisites.md` Stage 3 entry, *Done 2026-07-06* |
| Carb-priority per-class floors | Existing model-production Req [3.5](../model-production/requirements.md#3.5): ≥ 0.50 per staple. Current run: `white_rice` 0.6022, `chips_fries` 0.5671, `pasta` 0.5538 clear it; `bread_white` 0.4315, `potato_boiled` 0.4648 fall short; `brown_rice`/`bread_wholemeal`/`potato_mashed` absent from the held-out split | `model-production/prerequisites.md` Stage 3 entry |

The original 0.60 gate (pipeline Decision 14) was set against a **24-class** palette assumption ("0.60 mean food-class mIoU is achievable... on a 24-class food palette") before the 35-channel palette (24 solid + 8 liquid + 3 special) landed via the `v1` redefinition-in-place (`specs/estimation/nutrition5k-calibration/decision_log.md` Decisions 23–24, 2026-07-02: liquid classes appended to `ClassPalette.v1Standard`, keeping the `"v1"` label but changing its channel count from 27 to 35 — "'v1' means something different before and after this spec"). `pipeline` Decision 25 (architecture selection) and `model-production/design.md` §3.4 (export channel-count gate) both predate that redefinition and still cite 27 channels — a known staleness in those documents, not repeated here. The frontier research shows 0.60 is unreached by any published model on FoodSeg103's **103-class** taxonomy regardless of palette remap size, so the shortfall is not explained by the extra 11 channels alone — it is a genuine ceiling.

### 3.2 The re-derived number

**Gate: mean IoU ≥ 0.48 on the fixed FoodSeg103 held-out split.**

Derivation: the published frontier at a comparable parameter budget (the shipped architecture, DeepLabV3+MobileNetV3-Large, is 11.0M params) is well below the 100M+ models that reach 0.50–0.52. A compact-model-realistic target sits meaningfully below SOTA but meaningfully above the shipped 0.4054 baseline. 0.48 is chosen as:

- **≥ baseline + 0.05** (0.4054 → 0.4554 floor from margin alone) rounded up to the nearest 0.01 that also clears the midpoint of the provisional band (0.45–0.52, Req [1.2](requirements.md#1.2)), landing at 0.48 — one point above the band's midpoint (0.485) rounded to the nearer clean value, and comfortably inside the 0.45–0.52 band without requiring justification for an out-of-band value.
- **Below the 100M+-parameter SOTA (0.50–0.52)** by a margin consistent with the compact-vs-large-model gap documented across every source in the research table (Q1): every compact candidate in the research is evaluated on general scenes, not FoodSeg103, so no compact-model FoodSeg103 number exists to anchor to directly — 0.48 is a considered interpolation between "the recipe upgrade should clear a materially higher bar than today" and "we do not credibly expect a 11M-param CNN to approach a 441M-param transformer's frontier."
- **Consistent with the carb-priority floors already in force** (model-production Req 3.5, ≥ 0.50 per staple): a 0.48 mean is compatible with several staples already at or above 0.50 (as the current run shows) while others lag — the mean gate and the per-class floors pull in the same direction rather than one being unreachable while the other is trivial.

This value is fixed here, in design, per Decision 2 in the drafted decision log (derivation method in requirements, number in design). It supersedes 0.60 as the binding export-eligibility number.

### 3.3 Propagation to model-production (Req [1.3](requirements.md#1.3))

`model-production/requirements.md` Req [3.2](../model-production/requirements.md#3.2) currently reads:

> "A checkpoint SHALL be export-eligible only if it achieves mean IoU ≥ 0.60 on the held-out split (MD-12 / pipeline Req 8.9), measured by the validation harness."

This is amended to reference 0.48, with the amendment logged as a `model-production` decision-log entry citing this spec (mirroring how model-production Decision 13 amended pipeline Req 8.2 for the weight budget). Pipeline Decision 14 (0.60 mIoU floor) is marked `superseded by segmenter-foundation Decision 5` rather than deleted — its context and rationale stay as the historical record of why 0.60 was originally chosen. The amendment is `tasks.md` Phase 1 (tasks 2–3) but touches only `model-production/requirements.md` text, `pipeline/decision_log.md`'s status line, and this spec's own decision log — no `tools/segmenter/` or app code changes.

**Numeric-budget precedent already exists for this pattern.** The segmenter weight budget was raised from 10 MB to 24 MiB by model-production Decision 13 after the first real checkpoint showed 10 MB was unachievable for the chosen architecture (22.1 MB at FP16) — the same "gate set above the achievable frontier, amend with a logged decision" shape as this mIoU re-derivation. Note this also means the drafted `requirements.md` for this spec, which cites "≤ 10 MB" in Req [2.5](requirements.md#2.5) and Req [3.1](requirements.md#3.1)(b), carries the same stale figure Decision 13 already corrected elsewhere in the repo; design uses the current binding value (§5.4 below) and this is logged as Decision 6.

### 3.4 Override path unaffected

Req [1.4](requirements.md#1.4) / Decision 4: the developer override is a runtime/process behaviour in `model-production` (shipping a below-gate checkpoint flagged low-confidence) and needs no design change here — it already operates against whatever number Req 3.2 states, so re-pointing 3.2 at 0.48 is sufficient. No code path branches on the gate's specific value; it is compared once in the export script and once (informationally) in build lineage.

---

## 4. Requirement 2 — Training-recipe upgrade

### 4.1 What stays fixed (Req [2.1](requirements.md#2.1))

Architecture, input size, and output contract are unchanged: DeepLabV3+MobileNetV3-Large, 513×513, 35-channel single-pass per-pixel class-probability output (pipeline Decision 11). The exported artefact remains a drop-in replacement for the current loader/bundling path (`model-production` design §2.2) — no `PipelineFactory.swift`, `CoreMLSegmenter.swift`, or `Package.swift` changes are implied by this requirement.

### 4.2 Pretrained checkpoint sourcing (Req [2.2](requirements.md#2.2))

The research's strongest lever is heavy ImageNet-1K masked-image-modelling (MIM) pretraining, not a food-specific pretraining run (Decision 3: public checkpoints only). For a MobileNetV3-Large backbone specifically:

- **Preferred:** a MobileNetV3-Large checkpoint pretrained with a self-supervised or distillation-based recipe stronger than plain ImageNet-1K supervised classification (e.g. torchvision's `IMAGENET1K_V2` weights, which already use an improved training recipe over `V1`, or a published knowledge-distillation checkpoint) — whichever is available under a licence permitting commercial bundling (Apache-2.0, BSD, or MIT preferred; research/non-commercial-only licences are rejected regardless of accuracy).
- **Fallback, per Decision 3's stated risk:** if no MIM-pretrained MobileNetV3-compatible checkpoint exists publicly (plausible — MIM literature concentrates on ViT/Swin backbones, per the research Q2 finding that "MIM transfer... better than plain conv backbones"), the recipe initialises from the best available supervised ImageNet checkpoint and the class-imbalance loss (§4.3) carries the full uplift burden. This is not a spec failure; Decision 3 already anticipated it.
- **Recording:** checkpoint source URL, licence identifier, and SHA-256 are recorded in `build/lineage.json` under a new `pretrained_checkpoint` object (alongside the existing `train_config`), satisfying model-production Req [1.3](../model-production/requirements.md#1.3)'s lineage requirement. This is a `train.py`/`lineage.py` schema addition — one field group, not new plumbing — and lands as part of the `debug-read` PRD's training-pipeline context or a direct follow-on to it (§2.1), not duplicated here.

The actual checkpoint identification (searching torchvision/timm/HuggingFace hubs for a suitable licensed checkpoint) is a **research task this spec can do now** (autonomous) — the licence and SHA are static facts, not a compute-gated activity. Running the transfer-learning job that consumes it is gated (§2.1, §7).

### 4.3 Class-imbalance countermeasure (Req [2.3](requirements.md#2.3))

The research identifies a **co-occurrence-relationship loss** (Springer 10.1007/s11694-025-03647-2) as the most food-domain-relevant, evidence-backed lever: +3.72% overall FoodSeg103 mIoU, built from a co-occurrence matrix (ideally Recipe1M+ priors, up to +16.54% on tail classes) and, unlike a plain class-weighted loss, targets exactly MeData's documented failure mode — background-collapse on visually similar carb staples (rice vs. potato vs. bread) that co-occur on the same plate.

Design specifies the recipe as **one of the loss options the `debug-read` PRD's `--loss` flag must be extensible to** (its scaffolding is `{ce, weighted_ce, focal, dice, combined}`; the co-occurrence loss is a distinct fifth option or a term inside `combined`). This spec does not implement the flag — it specifies which loss variant satisfies Req 2.3 and hands that specification to whichever branch lands the training code next (§2.1). If the co-occurrence loss proves impractical to implement against the current `train.py` structure (e.g. it requires a co-occurrence matrix input the pipeline doesn't currently pass), `weighted_ce` (inverse-frequency class weighting, already scaffolded in the PRD's flag set) is the documented fallback — simpler, still evidence-backed for imbalance, but without the specific co-occurrence signal.

The ≥ 0.05 mean-per-staple-IoU uplift and ≤ 0.02-regression ceiling (Req 2.3) are measured by the existing `run_validation.py` per-class report (`model-production` design §2.1 stage 4) — no new validation tooling.

### 4.4 Mean-IoU uplift measurement (Req [2.4](requirements.md#2.4))

Measured identically to the existing validation harness: `run_validation.py` against the fixed held-out split, comparing the recipe-upgraded checkpoint's mean IoU to the shipped baseline's 0.4054. No design change to the harness; this is a comparison protocol (two numbers, one delta), not new code.

### 4.5 Export budgets carry over unchanged (Req [2.5](requirements.md#2.5))

**Correction to the drafted requirement's stated figure.** Req [2.5](requirements.md#2.5) and Req [3.1](requirements.md#3.1)(b) as drafted say "≤ 10 MB on-disk FP16." The actual binding budget, already amended by `model-production` Decision 13 and enforced in code (`SegmenterWeightsBudget.maxBytes = 24 * 1024 * 1024`, `CoreMLSegmenter.swift:157`) and in `export.py`'s gate, is **≤ 24 MiB FP16**. The shipped baseline (DeepLabV3+MobileNetV3-Large, 11.0M params) is already 22.1 MB at FP16 — a 10 MB ceiling would reject the *current shipped model*, which cannot be the intended acceptance bar. Design uses 24 MiB as the binding number (Decision 6, §8); the 250 ms ANE latency figure is unchanged and matches pipeline Decision 13 (single-view path budget). Any future edit to `requirements.md` should correct the figure to avoid an internal contradiction with `model-production`'s own gate.

---

## 5. Requirement 3 — Backbone swap track (conversion spike)

### 5.1 Spike procedure (Req [3.1](requirements.md#3.1))

The spike is a small, self-contained Core ML conversion exercise — it does **not** require a trained SegFormer-B0-on-FoodSeg103 checkpoint. It uses a publicly available SegFormer-B0 checkpoint (e.g. pretrained on ADE20K or Cityscapes; accuracy is irrelevant to this spike, only conversion mechanics and latency are measured) and answers four questions in order, stopping at the first failure (Req [3.2](requirements.md#3.2)):

1. **Converts to Core ML?** Run `coremltools.convert()` against the SegFormer-B0 PyTorch/ONNX graph at 513×513 input. SegFormer's MiT encoder uses overlap-patch-embedding convolutions and efficient self-attention (spatial-reduction attention) — ops with less Core ML precedent than DeepLabV3's plain convolutions. A hard conversion failure (unsupported op) ends the spike immediately.
2. **FP16 artefact ≤ 24 MiB?** (Corrected from the drafted "≤ 10 MB" for the same reason as §4.5 — the binding budget is 24 MiB.) SegFormer-B0 is 3.8M params (research table, Q1) — roughly a third of the shipped model's 11.0M, so this criterion is the least likely to fail; recorded for completeness and because the decoder/head adds parameters the encoder-only figure excludes.
3. **≤ 250 ms per 513×513 inference, ANE-resident, on the primary device (iPhone 16 Pro)?** Measured via Xcode's Core ML performance report, same method as `model-production` design §2.1 stage 7 (on-device verification). "ANE-resident" specifically means the Core ML performance report shows the compute units executing on the Neural Engine, not falling back to GPU/CPU — attention-heavy architectures are the most common cause of an unwanted CPU/GPU fallback, per the research's flagged unknown ("nobody publishes Core ML / ANE latencies for these").
4. **Matches PyTorch outputs within a stated tolerance?** Reuses the equivalence-oracle pattern already implemented for the current model (`model-production` design §3, `export.py`'s per-pixel argmax agreement + max-abs-logit-error gates, Req 4.3 of that spec): run a small fixed reference set through both the PyTorch graph and the converted Core ML artefact, require > 99% per-pixel argmax agreement and max absolute logit error < 0.05 — the same numeric thresholds already in force for DeepLabV3, so the spike is judged by an existing, non-arbitrary bar rather than a new one invented for this comparison.

All four verdicts are recorded in this spec's decision log as a single dated entry (pass/fail per criterion, with the measured numbers) whether the outcome is pass or fail.

### 5.2 Spike is human/compute-gated

Criteria 1 and 4 need a Python/coremltools environment (autonomous-capable, no GPU required — conversion and the small-reference-set oracle check both run on CPU in reasonable time). Criterion 3 needs the physical iPhone 16 Pro and Xcode's performance report — this half is human-gated. The spike is therefore **split**: the conversion + equivalence half (criteria 1, 2 partially, 4) can be attempted autonomously; the on-device latency half (criterion 3, and confirming criterion 2's real artefact size from the actual conversion) is gated. Both halves are required before any verdict is logged — a spike that only completes the autonomous half is incomplete, not a pass.

### 5.3 Retrain-and-compare gate (Req [3.2](requirements.md#3.2), Req [3.3](requirements.md#3.3))

If the spike fails any criterion, Requirement 3 is closed without a training run — the failure and which criterion tripped it are logged, and Requirement 2 remains the sole track (Req 3.2). If the spike passes all four, a SegFormer-B0 FoodSeg103 retrain is scheduled using the same class-imbalance recipe developed for Requirement 2 (§4.3) — not a separate, unweighted-CE baseline — since the point of the comparison is "does the better backbone plus the same recipe beat the same recipe on the current backbone," not "does SegFormer-B0 beat an under-trained DeepLabV3." The retrained checkpoint is compared against the Requirement-2 checkpoint on both mean IoU and the carb-staple mean (Req 2.3's eight classes); SegFormer-B0 is adopted only if it wins both. A win on one and a loss on the other counts as "does not beat" per Req [3.3](requirements.md#3.3)'s conjunction ("on both").

This retrain is itself a second gated GPU run, sequenced strictly after (a) the spike passes and (b) the Requirement-2 recipe exists to reuse (§2.1's sequencing).

---

## 6. Requirement 4 — Rejected approaches (documentation only)

No design work: Req [4.1](requirements.md#4.1) and [4.2](requirements.md#4.2) are satisfied directly by decision-log entries (Decisions 7 and 8 below), not by any code or process change. They exist so a future session does not re-propose CLIPSeg, MobileSAM/SAM3, or FoodSAM against this spec's budget and contract, and so the `plate`-class question is findable rather than silently dropped.

---

## 7. Testing / verification strategy

There is no runtime code in this spec, so there is no `make build` / `make test` surface to exercise. Verification is:

- **Gate derivation (§3):** checked by a self-review that the three named inputs (frontier, baseline, per-class floors) are cited with sources and the arithmetic in §3.2 is reproducible from them — the same bar `model-production`'s design applies to its own numeric gates.
- **Recipe specification (§4):** no verification until the gated training run executes; the *specification* is checked for internal consistency (does it name real files, real flag names matching the `debug-read` PRD's actual scaffolding) rather than for correctness of an unrun training job.
- **Spike procedure (§5):** the procedure itself is reviewed against `model-production` design §3's existing oracle pattern to confirm it reuses rather than reinvents the equivalence-check numeric thresholds.
- **`make spell`:** run before commit per repo convention; this spec is prose-only so this is the only mechanical check that applies.

---

## 8. Design-time decisions

Five decisions surfaced during design that extend the drafted decision log (Decisions 1–4) and are appended there, not here:

- **Decision 5** — fixes the re-derived gate at 0.48 mean IoU (§3.2), superseding pipeline Decision 14.
- **Decision 6** — corrects the drafted requirements' "≤ 10 MB" figures (Req 2.5, Req 3.1(b)) to the actual binding 24 MiB budget (model-production Decision 13), and records that this is a factual correction of a stale number carried over from the research note, not a re-opening of the size-budget question.
- **Decision 7** — records the SegFormer-B0 spike procedure's reuse of the existing equivalence-oracle thresholds (§5.1) rather than inventing new tolerances.
- **Decision 8** — formalises the rejected-approaches list (CLIPSeg, MobileSAM/SAM3-distilled, FoodSAM) with citations, satisfying Req 4.1.
- **Decision 9** — records the `plate`-class question as open (status `proposed`), satisfying Req 4.2.

See `decision_log.md` for the full entries.

---

## 9. Portability notes

Per `specs/PROCESS.md` §9, the estimation pipeline's algorithm layer is meant to be platform-agnostic. This spec's outputs — a gate number, a training recipe, and a spike verdict — are properties of the *model artefact*, not of any platform binding: whichever future Android port exists, it consumes the same trained checkpoint (or a TFLite export of it, already tracked as validation-only per `model-production` Non-Goals) rather than re-deriving a gate. No portability-specific design is needed here; the seam is already the one `pipeline` design §8 / Req 18 defines, and this spec sits entirely upstream of it (it decides what gets trained, not how a platform loads it).

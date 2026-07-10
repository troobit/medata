# Segmenter Foundation — Design

**Version:** 0.1.0
**Date:** 2026-07-10
**Status:** Draft
**Branch:** estimation/model-foundation

This document describes the implementation design for the requirements in `requirements.md` and the decisions in `decision_log.md` (Decisions 1–4 from requirements drafting; 5–9 from the first design pass; 10–13 from the requirements review; 14–17 from the second design pass, §8). It cites requirements by ID; it does not restate them. It overlays the production process owned by `specs/estimation/model-production/design.md` (§2.1) and the runtime architecture owned by `specs/estimation/pipeline/design.md`, referencing both rather than duplicating them. The driving research is `docs/agent-notes/model-foundation-research.md`.

---

## 1. Overview

This spec answers three questions the shipped segmenter has left open: what accuracy bar is actually achievable on FoodSeg103 ([Req 1](requirements.md#1-re-derived-accuracy-gate)), what training-recipe change gets the current architecture closest to it ([Req 2](requirements.md#2-training-recipe-upgrade-primary-lever)), and whether a backbone swap is worth its conversion risk ([Req 3](requirements.md#3-backbone-swap-track-gated-on-conversion-spike)). Its tasks specify and land `tools/segmenter/` code (carve stratification, the co-occurrence loss option, bar constants, the spike script) plus the sibling-spec amendment pass — but it does not run training or change the production process; the GPU runs and on-device measurements remain human-gated through `model-production`. (First-pass §1 claimed this spec touches no `tools/segmenter/` code; superseded by the second pass — see §3.3, §3.5, §4.3, §5.2.)

The design's spine, same as `model-production`, is the **automated vs human/compute-gated** split: a coding agent can write the gate derivation, the recipe specification, and the conversion-spike procedure; it cannot run the GPU training job, measure on-device ANE latency, or judge the spike's pass/fail against real numbers. Every task below is marked accordingly.

---

## 2. Sequencing and prerequisites

### 2.1 This spec depends on the estimation-quality PRD landing first — SATISFIED

**Status update (2026-07-10, second design pass):** the PRD's training-pipeline context has landed and merged to `research` — verified: `research:tools/segmenter/train.py` carries the `--loss` flag (line 796, `loss_config.LOSS_CHOICES`) and the `weighted_ce` helpers; changelog entry `fdc89a0` records the integration. The sequencing dependency below is therefore met; what remains is that **this worktree** (branched off `research@1b172b2`, pre-merge) does not contain that code, so the code-touching tasks in `tasks.md` execute on a branch containing the PRD landing (merge `research` in, or land the tasks on `research` after this spec's docs merge). The original dependency analysis is kept for the record:

`tools/segmenter/` is owned this cycle by the **estimation-quality PRD** (`specs/estimation/estimation-quality/prd.md`, branch `debug-read`), specifically its "Segmenter training pipeline" context. That PRD lands, as code:

- a `--loss {ce,weighted_ce,focal,dice,combined}` flag on `tools/segmenter/train.py` (class-imbalance-aware loss, default reproduces today's unweighted `nn.CrossEntropyLoss`);
- pure, torch-free-testable helpers for loss selection and class-weight derivation, unit-tested under `tools/segmenter/tests/`;
- opt-in photometric augmentation (image-only, off by default);
- the recorded run command in `docs/ml-training.md` §4.

Its own gated stage 6 (STOP — run the actual training job, export, and swap the bundled model) is explicitly **not** executed by that PRD; it is left as a human/compute-gated follow-on, same shape as the gated tasks in this spec.

**Consequence for this spec's task sequencing:** Requirement 2 (training-recipe upgrade) specifies the recipe this spec wants — stronger-pretraining checkpoint initialisation (§4.2; no true MIM checkpoint exists for this backbone), a class-imbalance countermeasure targeting the eight carb-priority staples, and a checkpoint-vs-baseline comparison protocol — but it does not re-implement the `--loss` flag plumbing; that is `debug-read`'s code to land. This spec's design tasks (recipe specification, checkpoint sourcing/licensing) can proceed independently and in parallel with that PRD, since they produce specification and lineage-recording requirements rather than `tools/segmenter/` edits. But the **gated training run** that exercises Requirement 2 cannot start until:

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
| Carb-priority per-class floors | Input to Decision 5's derivation: the 0.50 floors then in force (model-production Req [3.5](../model-production/requirements.md#3.5)) — since superseded by §3.2a's re-derived 0.45 (Decision 14), which is an *output* of the gate, not an input to it. Current run: `white_rice` 0.6022, `chips_fries` 0.5671, `pasta` 0.5538; `bread_white` 0.4315, `potato_boiled` 0.4648; `brown_rice`/`bread_wholemeal`/`potato_mashed` absent from the held-out split (resolved by the §3.5 re-cut) | `model-production/prerequisites.md` Stage 3 entry; Decisions 5, 14 |

**Label-space comparability (discharges Req [1.1](requirements.md#1.1)'s WHERE clause).** Published FoodSeg103 numbers are 103-class mIoU on the official split; MeData's metric is mean food-class IoU over the 32 food channels of the 35-channel palette (`validation.py:58-61` excludes `background`, `unknown_food`, `unsupported_liquid`) on a local seeded split. The remap pools confusable fine-grained labels into coarser channels, so the remapped task is plausibly easier and the two metrics are not directly comparable — the published ~0.52 SOTA bounds the *harder* task. The 0.48 gate is therefore an interpolation anchored on the baseline and required uplifts (§3.2), not a transplanted literature value.

The original 0.60 gate (pipeline Decision 14) was set against a **24-class** palette assumption ("0.60 mean food-class mIoU is achievable... on a 24-class food palette") before the 35-channel palette (24 solid + 8 liquid + 3 special) landed via the `v1` redefinition-in-place (`specs/estimation/nutrition5k-calibration/decision_log.md` Decisions 23–24, 2026-07-02: liquid classes appended to `ClassPalette.v1Standard`, keeping the `"v1"` label but changing its channel count from 27 to 35 — "'v1' means something different before and after this spec"). `pipeline` Decision 25 (architecture selection) and `model-production/design.md` §3.4 (export channel-count gate) both predate that redefinition and still cite 27 channels — a known staleness in those documents, not repeated here. The frontier research shows 0.60 is unreached by any published model on FoodSeg103's **103-class** taxonomy regardless of palette remap size, so the shortfall is not explained by the extra 11 channels alone — it is a genuine ceiling.

### 3.2 The re-derived number

**Gate: mean IoU ≥ 0.48 on the fixed FoodSeg103 held-out split.**

Derivation: the published frontier at a comparable parameter budget (the shipped architecture, DeepLabV3+MobileNetV3-Large, is 11.0M params) is well below the 100M+ models that reach 0.50–0.52. A compact-model-realistic target sits meaningfully below SOTA but meaningfully above the shipped 0.4054 baseline. 0.48 is chosen as:

- **Above the mandatory-uplift floor with headroom:** baseline 0.4054 + the Req [2.4](requirements.md#2.4) mandatory mean uplift (≥ 0.03) gives 0.4354; the Req [2.3](requirements.md#2.3) staple-specific uplift (+0.05 on below-gate staples) pulls the mean up faster than a uniform improvement, adding roughly another 0.04 of expected headroom — landing at 0.48, inside the provisional band (0.45–0.52, Req [1.2](requirements.md#1.2)) and about half a point below its midpoint (0.485).
- **Below the 100M+-parameter SOTA (0.50–0.52)** by a margin consistent with the compact-vs-large-model gap documented across every source in the research table (Q1): every compact candidate in the research is evaluated on general scenes, not FoodSeg103, so no compact-model FoodSeg103 number exists to anchor to directly — 0.48 is a considered interpolation between "the recipe upgrade should clear a materially higher bar than today" and "we do not credibly expect a 11M-param CNN to approach a 441M-param transformer's frontier."
- **Consistent with the re-derived per-class floors** (§3.2a: 0.45 = gate − 0.03): floors sit below the mean gate and the already-strong staples pull the staple mean above it — the mean gate and the per-class floors pull in the same direction rather than one being unreachable while the other is trivial. (The first-pass version of this bullet argued from the old 0.50 floors; superseded by §3.2a.)

This value is fixed here, in design, per Decision 2 in the drafted decision log (derivation method in requirements, number in design). It supersedes 0.60 as the binding export-eligibility number.

### 3.2a Re-derived per-class floors (Req [1.6](requirements.md#1.6), Decision 14)

**Floor: per-class IoU ≥ 0.45 for each of the eight carb-priority staples**, uniform, replacing model-production Req 3.5's 0.50 (which inherited the same unattainable-frontier assumption as the 0.60 gate — Decision 11). Derivation: floor = gate − 0.03; reachable by the below-gate staples after Req [2.3](requirements.md#2.3)'s mandatory +0.05 uplift (`bread_white` 0.4315 → ≥ 0.4815); the already-strong staples are protected by Req 2.3's ≤ 0.02 no-regression clause, not the floor. Consistency check per Req 1.6: 0.45 floors sit below the 0.48 mean and the three strong staples pull the staple mean above it — no Decision 5 revisit triggered. Export-eligibility rule after the amendment pass: `mean_food_iou ≥ 0.48 AND every staple IoU ≥ 0.45` (`validation.py:39-40` constants `MEAN_IOU_BAR`/`CARB_PRIORITY_IOU_BAR`; override mechanics unchanged).

Two clarifications under the new floors: (a) on the pre-re-cut numbers only `bread_white` (0.4315) is below the 0.45 floor — `potato_boiled` (0.4648) clears it but remains below the 0.48 gate, which is why Req 2.3's uplift set is anchored to the *gate*, not the floor (Decision 18): both weak staples keep the +0.05 obligation. (b) **Per-class revisit trigger:** IF the §3.5 re-measure leaves any staple's baseline below 0.40 — i.e. the floor is unreachable even with the mandatory +0.05 — THEN Decision 14 is revisited with a logged outcome, mirroring Req 2.6's mean-shift trigger for Decision 5.

### 3.3 Propagation to model-production (Req [1.3](requirements.md#1.3))

`model-production/requirements.md` Req [3.2](../model-production/requirements.md#3.2) currently reads:

> "A checkpoint SHALL be export-eligible only if it achieves mean IoU ≥ 0.60 on the held-out split (MD-12 / pipeline Req 8.9), measured by the validation harness."

Both bars are now fixed (0.48 gate, 0.45 floors), so per Req 1.3 the full amendment set is due, executed as tasks (spec phases edit nothing outside this folder). Authoritative home for the values: this spec's decision log (Decisions 5 and 14).

| Site | Edit |
|---|---|
| model-production `requirements.md` Req [3.2](../model-production/requirements.md#3.2), [3.4](../model-production/requirements.md#3.4) | 0.60 → "the re-derived gate (segmenter-foundation Decision 5, currently 0.48)"; amendment logged as a model-production decision-log entry citing this spec (the Decision 13 pattern) |
| model-production `requirements.md` Req [3.5](../model-production/requirements.md#3.5) | 0.50 floors → "the re-derived floors (segmenter-foundation Decision 14, currently 0.45)" |
| model-production `requirements.md` Req [2.2](../model-production/requirements.md#2.2) | note: heldout re-cut under segmenter-foundation Req 2.6 (new seed, stratified, then frozen again) |
| pipeline `requirements.md` Req 8.9 | amended-by note in the existing Req 8.2 style |
| pipeline `decision_log.md` Decision 14 | status → `superseded by segmenter-foundation Decision 5`; context/rationale kept as the historical record |
| `docs/ml-training.md` (all normative 0.60/0.50 sites: lines 133, 144, 341, 350, 378, 560) | values + pointer to this spec |
| model-production `design.md:184` | gate value + pointer |
| model-production `tasks.md` / `prerequisites.md` export-eligibility wording | annotate active entries with the new bars; do not rewrite completed/historical entries |
| `tools/segmenter/validation.py:39-40` | `MEAN_IOU_BAR = 0.48`, `CARB_PRIORITY_IOU_BAR = 0.45`, plus the module/function docstrings still stating the 0.60/0.50 rule and "24 food-class names" (the palette has 32 food channels) — code task with its unit-test update |
| `HarnessCore/SegBench.swift:40` (`passesBar`: ≥ 0.60) + `MedataCore/Tests/HarnessCLITests/SegBenchTests.swift:25,89,101` | 0.60 → 0.48 so `seg-bench` and `validation.py` enforce one gate — a Swift code task, Debug-only surface (`HARNESS_ENABLED`), covered by `make test` |
| `tools/segmenter/train.py:30,337` docstring/comment gate mentions | value + pointer (non-normative text, same pass as validation.py) |

**Numeric-budget precedent already exists for this pattern.** The segmenter weight budget was raised from 10 MB to 24 MiB by model-production Decision 13 after the first real checkpoint showed 10 MB was unachievable for the chosen architecture (22.1 MB at FP16) — the same "gate set above the achievable frontier, amend with a logged decision" shape as this mIoU re-derivation. Note this also means the drafted `requirements.md` for this spec, which cites "≤ 10 MB" in Req [2.5](requirements.md#2.5) and Req [3.1](requirements.md#3.1)(b), carries the same stale figure Decision 13 already corrected elsewhere in the repo; design uses the current binding value (§5.4 below) and this is logged as Decision 6.

### 3.4 Override path unaffected

Req [1.4](requirements.md#1.4) / Decision 4: the developer override is a runtime/process behaviour in `model-production` (shipping a below-gate checkpoint flagged low-confidence) and needs no design change here — it already operates against whatever number Req 3.2 states, so re-pointing 3.2 at 0.48 is sufficient. No code path branches on the gate's specific value; it is compared once in the export script and once (informationally) in build lineage.

Req [1.5](requirements.md#1.5) (planned divergence): if the recipe-upgraded checkpoint meets its uplift criteria but lands below 0.48, the residual gap is a decision-log entry naming its owner (the Requirement 3 track if the spike passed, otherwise follow-up data work) — written when the gated run's numbers exist, not now.

### 3.5 Stratified heldout re-cut and baseline re-measure (Req [2.6](requirements.md#2.6), Decision 10)

**Integration point:** `prepare_dataset.py:carve_splits()` (lines 186–213) — currently a seeded shuffle with no stratification.

**Mechanism:** two-pass carve. Pass 1: `carve_splits()` runs *before* remapping (`write_split` remaps after the carve), so staple presence is computed by applying the `class_mapping_foodseg103_v1.json` LUT to the raw masks in memory (or equivalently, testing raw FoodSeg103 ids against each staple's source-id set) — no remapped masks exist at carve time. Pass 2: iterate the eight staples in palette-index order; for each, deterministically (seeded) assign images to heldout until its quota is met, where **quota = min(max(3, ⌈0.12 × n⌉), ⌊n/3⌋)** for a staple appearing in `n` images — the `⌊n/3⌋` cap guarantees heldout never takes more than a third of a staple's images, so measurability is never bought with unlearnability. An image already assigned to heldout counts toward every staple quota it contains (multi-staple plates satisfy several quotas at once). The remainder is shuffled and sliced as today. A **new** split seed is chosen, recorded in `splits.json` and lineage, and then frozen again (the model-production Req 2.2 amendment above). `splits.json` gains a `stratification` block: per-staple heldout/train counts plus any warnings.

**Infeasibility rule:** when `⌊n/3⌋` < 1 (a staple with fewer than 3 images in the whole dataset), heldout gets exactly 1 image, a warning lands in the `stratification` block, and a decision-log record notes that both the floor *and* learnability for that staple are judged on what exists.

**Baseline re-measure:** run `run_validation.py` for `checkpoint_letterbox.pt` (model `24e0b022241a`) against the re-cut heldout split; record mean and the full per-class table in the decision log. IF |re-measured mean − 0.4054| > 0.02 THEN revisit Decision 5 (Req 2.6 trigger). All uplift deltas (Reqs 2.3, 2.4, 3.3) anchor to this re-measured table.

---

## 4. Requirement 2 — Training-recipe upgrade

### 4.1 What stays fixed (Req [2.1](requirements.md#2.1))

Architecture, input size, and output contract are unchanged: DeepLabV3+MobileNetV3-Large, 513×513, 35-channel single-pass per-pixel class-probability output (pipeline Decision 11). The exported artefact remains a drop-in replacement for the current loader/bundling path (`model-production` design §2.2) — no `PipelineFactory.swift`, `CoreMLSegmenter.swift`, or `Package.swift` changes are implied by this requirement.

### 4.2 Pretrained checkpoint sourcing (Req [2.2](requirements.md#2.2))

The research's strongest lever is heavy ImageNet-1K masked-image-modelling (MIM) pretraining, not a food-specific pretraining run (Decision 3: public checkpoints only). For a MobileNetV3-Large backbone specifically:

Survey candidates, in selection order (Decision 17):

| Candidate | Nature | Cost/risk | Verdict rule |
|---|---|---|---|
| timm `mobilenetv3_large_100.miil_in21k_ft_in1k` | ImageNet-21k MIL pretraining — the strongest documented pretraining published for this exact backbone | state-dict adapter to the torchvision graph (layer naming differs); licence to vet | adopt if the adapter round-trips (identical logits on a probe image vs timm-native inference) and the licence permits commercial bundling |
| torchvision `MobileNet_V3_Large_Weights.IMAGENET1K_V2` backbone + fresh DeepLab head | improved supervised recipe (+1.2 top-1 over V1) | zero surgery; BSD-3 | fallback if the adapter fails or the licence is unsuitable |
| MIM checkpoints (SparK/A2MIM lineage) | true masked-image modelling | none published for MobileNetV3-Large | expected absence → Decision 12 fallback logged; the imbalance loss carries the recipe |

Licence rule regardless of candidate: Apache-2.0/BSD/MIT-class permitting commercial bundling; research/non-commercial licences rejected regardless of accuracy. One trade-off is accepted knowingly: the current init (`DeepLabV3_MobileNet_V3_Large_Weights.DEFAULT`, COCO-with-VOC-labels) already embodies dense-prediction transfer that a classification init lacks; if the survey concludes it beats both candidates for this task, retaining it is the logged outcome and Decision 12's "expected uplift revised down" applies to the pretraining half.
- **Recording:** checkpoint source URL, licence identifier, and SHA-256 are recorded in `build/lineage.json` under a new `pretrained_checkpoint` object (alongside the existing `train_config`), satisfying model-production Req [1.3](../model-production/requirements.md#1.3)'s lineage requirement. This is a `train.py`/`lineage.py` schema addition — one field group, not new plumbing — and lands as part of the `debug-read` PRD's training-pipeline context or a direct follow-on to it (§2.1), not duplicated here.

The actual checkpoint identification (searching torchvision/timm/HuggingFace hubs for a suitable licensed checkpoint) is a **research task this spec can do now** (autonomous) — the licence and SHA are static facts, not a compute-gated activity. Running the transfer-learning job that consumes it is gated (§2.1, §7).

### 4.3 Class-imbalance countermeasure (Req [2.3](requirements.md#2.3))

The research identifies a **co-occurrence-relationship loss** (Springer 10.1007/s11694-025-03647-2) as the most food-domain-relevant, evidence-backed lever: +3.72% overall FoodSeg103 mIoU, built from a co-occurrence matrix (ideally Recipe1M+ priors, up to +16.54% on tail classes) and, unlike a plain class-weighted loss, targets exactly MeData's documented failure mode — background-collapse on visually similar carb staples (rice vs. potato vs. bread) that co-occur on the same plate.

The PRD's `--loss` flag has landed (§2.1): `{ce, weighted_ce, focal, dice, combined}` with class-weight helpers. This spec adds a **co-occurrence option on top of that plumbing** (a new choice or a term inside `combined` — implementer's call against the landed `loss_config` structure), not a fork of it:

- **Matrix source (Decision 15): FoodSeg103-internal.** `prepare_dataset.py` gains a statistics pass during remap, writing `co_stats.json`: per-class pixel counts per split (feeding the existing `weighted_ce` helpers) and image-level joint presence counts over the **training split only**. Its SHA-256 joins the lineage. Recipe1M+ priors — the configuration behind the research's +16.54% tail figure — are recorded as follow-up if tail classes stay collapsed after the first run; acquiring and licence-vetting an external dataset is out of proportion for the first iteration.
- **Loss shape:** `L = base + λ·L_co`: image-level predicted presence `p_c` (max-pooled `softmax_c`; log-sum-exp or top-k pooling is the noted fallback if a single spurious activation saturating the max proves unstable) penalised (BCE) against ground-truth presence, with pair weights that up-weight false presences whose co-occurrence prior with the image's ground-truth classes is near zero. Honest scope: that weighting targets the *confusion* half of the failure mode (implausible false positives); the *collapse* half (staple pixels predicted as background, a false-negative failure) is carried by the presence-BCE term for missed ground-truth classes and by the `weighted_ce` base — the design does not claim the pair weighting fixes collapse directly. `base` is the landed `weighted_ce`. λ defaults to 0.1 — small enough to keep the auxiliary image-level term subordinate to the pixel loss; treated as fixed for the first run and swept only if training logs show `L_co` dominating or vanishing. λ and the pooling choice are recorded in lineage.
- **Fail-fast contract:** `co_stats.json` records the split seed and class-mapping SHA-256 it was built from; if the file is missing, or either value mismatches the training invocation's, `train.py` fails with the regeneration command — a silent fallback to unweighted CE (or stats from a different split) would falsify the lineage's claim about the recipe.
- **Fallback:** if the co-occurrence term proves impractical against the landed structure, `weighted_ce` alone is the documented fallback — simpler, still evidence-backed for imbalance, without the pair signal.

The ≥ 0.05 mean-per-staple-IoU uplift and ≤ 0.02-regression ceiling (Req 2.3) are measured by the existing `run_validation.py` per-class report (`model-production` design §2.1 stage 4) — no new validation tooling.

### 4.4 Mean-IoU uplift measurement (Req [2.4](requirements.md#2.4))

Measured identically to the existing validation harness: `run_validation.py` against the fixed held-out split, comparing the recipe-upgraded checkpoint's mean IoU to the shipped baseline's 0.4054. No design change to the harness; this is a comparison protocol (two numbers, one delta), not new code.

### 4.5 Export budgets carry over unchanged (Req [2.5](requirements.md#2.5))

The binding budgets, now stated correctly in Req [2.5](requirements.md#2.5) after the requirements review (the drafted "≤ 10 MB" was corrected per Decision 6): **≤ 24 MiB FP16** (model-production Decision 13; enforced by `SegmenterWeightsBudget.maxBytes`, `CoreMLSegmenter.swift:157`, and `export.py:296` `WEIGHTS_MAX_BYTES`) and **≤ 250 ms per view on the v1 hardware floor** (pipeline Req 8.3). No recipe change alters the parameter count, so the existing export gates re-verify these per build with no new tooling.

---

## 5. Requirement 3 — Backbone swap track (conversion spike)

### 5.1 Spike procedure (Req [3.1](requirements.md#3.1))

The spike is a small, self-contained Core ML conversion exercise — it does **not** require a trained SegFormer-B0-on-FoodSeg103 checkpoint. It uses a publicly available SegFormer-B0 checkpoint (e.g. pretrained on ADE20K or Cityscapes; accuracy is irrelevant to this spike, only conversion mechanics and latency are measured) and answers four questions in order, stopping at the first failure (Req [3.2](requirements.md#3.2)):

1. **Converts to Core ML?** Run `coremltools.convert()` against the SegFormer-B0 PyTorch/ONNX graph at 513×513 input. SegFormer's MiT encoder uses overlap-patch-embedding convolutions and efficient self-attention (spatial-reduction attention) — ops with less Core ML precedent than DeepLabV3's plain convolutions. A hard conversion failure (unsupported op) ends the spike immediately.
2. **FP16 artefact ≤ 24 MiB?** (Reuse `export.py:296` `WEIGHTS_MAX_BYTES`.) SegFormer-B0 is 3.8M params (research table, Q1) — roughly a third of the shipped model's 11.0M, so this criterion is the least likely to fail; recorded for completeness and because the decoder/head adds parameters the encoder-only figure excludes.
3. **≤ 250 ms per 513×513 inference, ANE-resident, on the v1 hardware floor (iPhone 13 Pro Max — physically available, Decision 16)?** Measured via Xcode's Core ML performance report, same method as `model-production` design §2.1 stage 7 (on-device verification). Measuring on the floor device directly makes the verdict authoritative — no derating argument needed. "ANE-resident" specifically means the Core ML performance report shows the compute units executing on the Neural Engine, not falling back to GPU/CPU — attention-heavy architectures are the most common cause of an unwanted CPU/GPU fallback, per the research's flagged unknown ("nobody publishes Core ML / ANE latencies for these").
4. **Matches PyTorch outputs within the existing oracle thresholds?** Reuses the equivalence oracle already implemented for the current model (`oracle_agreement()` at `export.py:401`, `reference_input()` at `export.py:150`) with model-production Req [4.3](../model-production/requirements.md#4.3)'s thresholds **as amended**: > 99% per-pixel argmax agreement (the functional bar) and max absolute logit error < 0.5 (the FP16-drift-recalibrated bar, model-production Decision 14; the original 0.05 predates any real FP16 export). Decision 7 records this reuse; if SegFormer's attention numerics show materially different FP16 drift, the deviation is logged, not silently absorbed.

All four verdicts are recorded in this spec's decision log as a single dated entry (pass/fail per criterion, with the measured numbers) whether the outcome is pass or fail.

### 5.2 Spike is human/compute-gated

Criteria 1, 2, and 4 need only a Python/coremltools environment (autonomous-capable, no GPU required — conversion produces the FP16 artefact whose size criterion 2 measures directly, and the small-reference-set oracle check runs on CPU in reasonable time); they live in a new `tools/segmenter/spike_segformer.py` (HF `transformers` added to `tools/segmenter/requirements.txt` as a spike-only dependency), emitting a verdict JSON (`build/spike_segformer.json`: four booleans + measurements) that the decision-log entry transcribes. Criterion 3 needs the physical iPhone 13 Pro Max and Xcode's performance report — this half is human-gated. Both halves are required before any verdict is logged — a spike that only completes the autonomous half is incomplete, not a pass.

### 5.3 Retrain-and-compare gate (Req [3.2](requirements.md#3.2), Req [3.3](requirements.md#3.3))

If the spike fails any criterion, Requirement 3 is closed without a training run — the failure and which criterion tripped it are logged, and Requirement 2 remains the sole track (Req 3.2). If the spike passes all four, a SegFormer-B0 FoodSeg103 retrain is scheduled using the same class-imbalance recipe developed for Requirement 2 (§4.3) — not a separate, unweighted-CE baseline — since the point of the comparison is "does the better backbone plus the same recipe beat the same recipe on the current backbone," not "does SegFormer-B0 beat an under-trained DeepLabV3." Both candidates are measured on the same re-cut heldout split (§3.5). The retrained checkpoint is compared against the Requirement-2 checkpoint on both mean food-class IoU and the carb-staple mean (Req 2.3's eight classes); SegFormer-B0 is adopted only if it wins both **by ≥ 0.02** (the Req [3.3](requirements.md#3.3) adoption margin — a sub-margin win buys permanent conversion/maintenance risk for what may be noise). A win on one and a loss on the other counts as "does not beat" per the conjunction. Adoption would then re-run the export-gate integration (channel count, oracle, budget) as a `model-production` concern — out of scope here beyond the spike verdict and comparison.

This retrain is itself a second gated GPU run, sequenced strictly after (a) the spike passes and (b) the Requirement-2 recipe exists to reuse (§2.1's sequencing).

---

## 6. Requirement 4 — Rejected approaches (documentation only)

No design work: Req [4.1](requirements.md#4.1) and [4.2](requirements.md#4.2) are satisfied directly by decision-log entries (Decisions 7 and 8 below), not by any code or process change. They exist so a future session does not re-propose CLIPSeg, MobileSAM/SAM3, or FoodSAM against this spec's budget and contract, and so the `plate`-class question is findable rather than silently dropped.

---

## 7. Testing / verification strategy

One MedataCore-adjacent exception to an otherwise `tools/segmenter/`-only footprint: the amendment pass touches `HarnessCore/SegBench.swift:40` and its tests (§3.3) — a Debug-only surface (`HARNESS_ENABLED`), covered by the existing `make test`; no shipping-app code changes. Everything else this spec's tasks add lives in `tools/segmenter/`, verified by extending its existing pytest suite:

- **Stratified carve (§3.5):** determinism for a fixed seed; every staple present in heldout on a synthetic corpus; the infeasibility rule on a corpus with a 2-image staple.
- **Loss additions (§4.3):** `co_stats.json` statistics generation on synthetic masks; `L_co` is zero when predicted presence matches ground truth; the fail-fast contract for both the missing and the stale case (seed/mapping-SHA mismatch).
- **Bar constants (§3.3):** existing export-eligibility tests updated to 0.48/0.45 in the same task as the `validation.py` change.
- **Gate derivation (§3):** document-level — the three named inputs are cited with sources and §3.2's arithmetic is reproducible from them; no code.
- **Spike (§5):** the verdict JSON is the artefact; the oracle path reuses already-tested `export.py` helpers. Accuracy criteria (Reqs 2.3, 2.4, 3.3) are verified by human-gated validation runs, not tests, per the requirements' closure semantics.
- **`make spell`:** before every docs commit, per repo convention.

Property-based testing is not used: the split/loss invariants are covered by direct cases on synthetic corpora, and `hypothesis` is not a project dependency — adding one contradicts the testing-minimal posture.

---

## 8. Design-time decisions

First design pass (appended to the drafted Decisions 1–4):

- **Decision 5** — fixes the re-derived gate at 0.48 mean IoU (§3.2), superseding pipeline Decision 14 (amendment pass pending, §3.3).
- **Decision 6** — corrects the drafted requirements' "≤ 10 MB" figures to the binding 24 MiB budget (model-production Decision 13); requirements.md has since been corrected.
- **Decision 7** — the SegFormer-B0 spike reuses the existing equivalence-oracle thresholds (§5.1) rather than inventing new tolerances.
- **Decision 8** — formalises the rejected-approaches list (CLIPSeg, MobileSAM/SAM3-distilled, FoodSAM) with citations, satisfying Req 4.1.
- **Decision 9** — records the `plate`-class question as open (status `proposed`), satisfying Req 4.2.

Requirements review (Decisions 10–13): stratified re-cut (10), floors re-derived alongside the gate (11), pretraining fallback (12), permitted gate/recipe divergence (13).

Second design pass:

- **Decision 14** — per-class staple floors fixed at 0.45 uniform (§3.2a), completing the Req 1.1/1.6 derivation with the label-space comparability note (§3.1).
- **Decision 15** — co-occurrence matrix is FoodSeg103-internal (`co_stats.json`, §4.3); Recipe1M+ recorded as follow-up.
- **Decision 16** — spike latency measured directly on the iPhone 13 Pro Max (available), no derating argument (§5.1.3).
- **Decision 17** — initialisation selection order: timm in21k-MIL adapter → torchvision `IMAGENET1K_V2` → retain COCO-seg `DEFAULT` if the survey favours it, with the outcome logged either way (§4.2).

See `decision_log.md` for the full entries.

---

## 9. Portability notes

Per `specs/PROCESS.md` §9, the estimation pipeline's algorithm layer is meant to be platform-agnostic. This spec's outputs — a gate number, a training recipe, and a spike verdict — are properties of the *model artefact*, not of any platform binding: whichever future Android port exists, it consumes the same trained checkpoint (or a TFLite export of it, already tracked as validation-only per `model-production` Non-Goals) rather than re-deriving a gate. No portability-specific design is needed here; the seam is already the one `pipeline` design §8 / Req 18 defines, and this spec sits entirely upstream of it (it decides what gets trained, not how a platform loads it).

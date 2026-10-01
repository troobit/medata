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

## 3. Heldout split

### 3.1 Stratified heldout re-cut and baseline re-measure (Req [2.6](requirements.md#2.6), Decision 10)

**Integration point:** `prepare_dataset.py:carve_splits()` (lines 186–213) — currently a seeded shuffle with no stratification.

**Mechanism:** two-pass carve. Pass 1: `carve_splits()` runs *before* remapping (`write_split` remaps after the carve), so staple presence is computed by applying the `class_mapping_foodseg103.json` LUT to the raw masks in memory (or equivalently, testing raw FoodSeg103 ids against each staple's source-id set) — no remapped masks exist at carve time. Pass 2: iterate the eight staples in palette-index order; for each, deterministically (seeded) assign images to heldout until its quota is met, where **quota = min(max(3, ⌈0.12 × n⌉), ⌊n/3⌋)** for a staple appearing in `n` images — the `⌊n/3⌋` cap guarantees heldout never takes more than a third of a staple's images, so measurability is never bought with unlearnability. An image already assigned to heldout counts toward every staple quota it contains (multi-staple plates satisfy several quotas at once). The remainder is shuffled and sliced as today. A **new** split seed is chosen, recorded in `splits.json` and lineage, and then frozen again (the model-production Req 2.2 amendment above). `splits.json` gains a `stratification` block: per-staple heldout/train counts plus any warnings.

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
3. **≤ 250 ms per 513×513 inference, ANE-resident, on the v1 hardware floor (iPhone 16 Pro — Decision 16 as amended by Decision 22)?** Measured via Xcode's Core ML performance report, same method as `model-production` design §2.1 stage 7 (on-device verification). Measuring on the floor device directly makes the verdict authoritative — no derating argument needed. "ANE-resident" specifically means the Core ML performance report shows the compute units executing on the Neural Engine, not falling back to GPU/CPU — attention-heavy architectures are the most common cause of an unwanted CPU/GPU fallback, per the research's flagged unknown ("nobody publishes Core ML / ANE latencies for these").
4. **Matches PyTorch outputs within the existing oracle thresholds?** Reuses the equivalence oracle already implemented for the current model (`oracle_agreement()` at `export.py:401`, `reference_input()` at `export.py:150`) with model-production Req [4.3](../model-production/requirements.md#4.3)'s thresholds **as amended**: > 99% per-pixel argmax agreement (the functional bar) and max absolute logit error < 0.5 (the FP16-drift-recalibrated bar, model-production Decision 14; the original 0.05 predates any real FP16 export). Decision 7 records this reuse; if SegFormer's attention numerics show materially different FP16 drift, the deviation is logged, not silently absorbed.

All four verdicts are recorded in this spec's decision log as a single dated entry (pass/fail per criterion, with the measured numbers) whether the outcome is pass or fail.

### 5.2 Spike is human/compute-gated

Criteria 1, 2, and 4 need only a Python/coremltools environment (autonomous-capable, no GPU required — conversion produces the FP16 artefact whose size criterion 2 measures directly, and the small-reference-set oracle check runs on CPU in reasonable time); they live in a new `tools/segmenter/spike_segformer.py` (HF `transformers` added to `tools/segmenter/requirements.txt` as a spike-only dependency), emitting a verdict JSON (`build/spike_segformer.json`: four booleans + measurements) that the decision-log entry transcribes. Criterion 3 needs the physical iPhone 16 Pro (Decision 22) and Xcode's performance report — this half is human-gated. Both halves are required before any verdict is logged — a spike that only completes the autonomous half is incomplete, not a pass.

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
- **Gate derivation (§3):** document-level — the three named inputs are cited with sources and §3.2's arithmetic is reproducible from them; no code.
- **Spike (§5):** the verdict JSON is the artefact; the oracle path reuses already-tested `export.py` helpers. Accuracy criteria (Reqs 2.3, 2.4, 3.3) are verified by human-gated validation runs, not tests, per the requirements' closure semantics.
- **`make spell`:** before every docs commit, per repo convention.

Property-based testing is not used: the split/loss invariants are covered by direct cases on synthetic corpora, and `hypothesis` is not a project dependency — adding one contradicts the testing-minimal posture.

---

## 8. Design-time decisions

First design pass (appended to the drafted Decisions 1–4):

- **Decision 6** — corrects the drafted requirements' "≤ 10 MB" figures to the binding 24 MiB budget (model-production Decision 13); requirements.md has since been corrected.
- **Decision 7** — the SegFormer-B0 spike reuses the existing equivalence-oracle thresholds (§5.1) rather than inventing new tolerances.
- **Decision 8** — formalises the rejected-approaches list (CLIPSeg, MobileSAM/SAM3-distilled, FoodSAM) with citations, satisfying Req 4.1.
- **Decision 9** — records the `plate`-class question as open (status `proposed`), satisfying Req 4.2.

Requirements review: stratified re-cut (Decision 10) and the pretraining fallback (Decision 12).

Second design pass:

- **Decision 15** — co-occurrence matrix is FoodSeg103-internal (`co_stats.json`, §4.3); Recipe1M+ recorded as follow-up.
- **Decision 16** — spike latency measured directly on the hardware floor, no derating argument (§5.1.3); floor re-based to the iPhone 16 Pro by Decision 22.
- **Decision 17** — initialisation selection order: timm in21k-MIL adapter → torchvision `IMAGENET1K_V2` → retain COCO-seg `DEFAULT` if the survey favours it, with the outcome logged either way (§4.2).

See `decision_log.md` for the full entries.

---

## 9. Portability notes

Per `specs/PROCESS.md` §9, the estimation pipeline's algorithm layer is meant to be platform-agnostic. This spec's outputs — a gate number, a training recipe, and a spike verdict — are properties of the *model artefact*, not of any platform binding: whichever future Android port exists, it consumes the same trained checkpoint (or a TFLite export of it, already tracked as validation-only per `model-production` Non-Goals) rather than re-deriving a gate. No portability-specific design is needed here; the seam is already the one `pipeline` design §8 / Req 18 defines, and this spec sits entirely upstream of it (it decides what gets trained, not how a platform loads it).

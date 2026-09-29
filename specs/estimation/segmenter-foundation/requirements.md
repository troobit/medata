# Requirements: Segmenter Foundation

## Introduction

This spec decides the model foundation for the on-device food segmenter: the accuracy gate it must meet, the training recipe that gets it there, and whether the backbone changes. It is driven by the Track A deep-research findings (`docs/agent-notes/model-foundation-research.md`): the shipped model's heldout mean food-class IoU of 0.4054 is genuinely low, but the 0.60 gate (pipeline Decision 14, model-production [Req 3.2](../model-production/requirements.md#3.2)) sits above the FoodSeg103 achievable frontier (~0.52 SOTA, reached only by 100M+ parameter models); the re-derived gate is fixed by Decision 5 (currently 0.48). The sibling `model-production` spec owns the dataset→train→export→bundle process and consumes the gate this spec re-derives; this spec changes what is trained and what bar it must clear, not how builds are run. The uplift criteria (Reqs [2.3](#2.3), [2.4](#2.4), [3.3](#3.3)) are verified through `model-production`'s human-gated training stages: this spec's tasks close on the criteria being defined and the first run measured against them, not on the numbers being hit.

## Non-Goals

- Changing the 35-class palette, its membership, or channel order — `plate` as a class is recorded as an open sub-question only (Decision 9).
- In-house self-supervised pretraining runs (BEiT-style MIM from scratch) — only published pretrained checkpoints are used (Decision 3).
- Re-litigating settled calls: FoodSeg103 stays the training set; seefood, FoodSAM, and text-conditioned segmentation remain rejected (Decision 8).
- Retiring the developer override — a below-gate model can still ship flagged (Decision 4).
- Re-deriving the runtime inference architecture or the production process — owned by `estimation/pipeline` and `estimation/model-production`.
- Executing GPU training runs or acquiring datasets — human-gated stages tracked through the `model-production` process.
- Data/taxonomy overhaul of FoodSeg103 (relabelling, class merging beyond the existing v1 remap); the stratified split re-cut of [Req 2.6](#2.6) is a split change, not a relabelling.
- A size-optimisation pass (quantisation below FP16) — the binding weight budget is 24 MiB (pipeline Req 8.2 as amended by model-production Decision 13).
- Android/TFLite production export.

## Requirements

### 1. Re-Derived Accuracy Gate

**User Story:** As the developer, I want the segmenter accuracy gate derived from what is achievable on FoodSeg103, so that the gate steers shipping decisions instead of being permanently overridden.

**Acceptance Criteria:**

1. <a name="1.1"></a>The replacement for the 0.60 gate SHALL be derived from three named inputs — the published FoodSeg103 frontier at a comparable parameter budget, the pinned shipped baseline ([Req 2.4](#2.4)), and the carb-priority per-class floors (model-production [Req 3.5](../model-production/requirements.md#3.5), as re-derived under [1.6](#1.6)) — with its exact metric stated (mean food-class IoU on the remapped 35-channel palette heldout split, excluding non-food channels, as reported by the existing validation harness); WHERE published frontier numbers are 103-class mIoU and thus not directly comparable to the remapped metric, the derivation SHALL record that explicitly rather than transplanting them. The derivation and number SHALL be logged before the first training run of Requirement 2 or 3 is launched. *Satisfied by Decisions 5 and 14 (design §3.1–3.2a): gate ≥ 0.48, floors ≥ 0.45, comparability note recorded.*  
2. <a name="1.2"></a>The re-derived gate SHALL lie within the provisional band 0.45 ≤ mean IoU ≤ 0.52; a value outside this band SHALL require a logged justification. *The re-derived gate (Decision 5, currently 0.48) satisfies this.*  
3. <a name="1.3"></a>WHEN the gate and floors are fixed, every site where the old bars are normative SHALL be amended to reference the re-derived values or their authoritative home (this spec's decision log): model-production [Req 3.2](../model-production/requirements.md#3.2) and [Req 3.4](../model-production/requirements.md#3.4) (the 0.60 export block), [Req 3.5](../model-production/requirements.md#3.5) (the 0.50 floors), pipeline Req 8.9 (with a superseding note on pipeline Decision 14), the gate encodings in `docs/ml-training.md`, and the export-eligibility wording in model-production's tasks and prerequisites.  
4. <a name="1.4"></a>The developer-override path SHALL remain available: IF a checkpoint is below the re-derived gate, THEN it MAY still ship with the shortfall recorded against the build and estimates flagged low-confidence, as under the current process.  
5. <a name="1.5"></a>The recipe-upgrade track (Requirement 2) MAY land below the re-derived gate (Decision 5, currently 0.48) while still meeting its own uplift criteria; IF it does, THEN the residual gap SHALL be recorded in the decision log and assigned to the backbone track (Requirement 3) or to follow-up data work — the gate remains the export bar and the divergence is a planned outcome, not a silent failure.  
6. <a name="1.6"></a>The design SHALL re-derive the carb-priority per-class floors alongside the re-derived mean gate using the same derivation inputs, logged before the first training run of Requirement 2 or 3 is launched, and amend model-production [Req 3.5](../model-production/requirements.md#3.5) with the resulting values; IF the re-derived floors are inconsistent with the mean gate of Decision 5, THEN Decision 5 SHALL be revisited with a logged outcome.  

### 2. Training-Recipe Upgrade (Primary Lever)

**User Story:** As the developer, I want the existing DeepLabV3+MobileNetV3-Large retrained with a stronger recipe, so that accuracy improves — especially on the weak and unmeasured carb staples — without any Core ML conversion risk.

**Acceptance Criteria:**

1. <a name="2.1"></a>The upgraded recipe SHALL keep the existing DeepLabV3+MobileNetV3-Large architecture, 513×513 input, and 35-channel single-pass per-pixel class-probability output (pipeline Decision 11) unchanged, so the exported artefact remains a drop-in replacement.  
2. <a name="2.2"></a>The recipe SHALL initialise from a published checkpoint embodying stronger pretraining than the current ImageNet-supervised weights (masked-image-modelling-style where available), whose licence permits bundling in a commercial app, with source, licence, and SHA-256 recorded in the build lineage (model-production [Req 1.3](../model-production/requirements.md#1.3)); IF no such checkpoint exists for MobileNetV3-Large, THEN that absence SHALL be logged, the current supervised initialisation retained, and the class-imbalance countermeasure of [2.3](#2.3) SHALL carry the recipe alone with the expected uplift revised down in the decision log.  
3. <a name="2.3"></a>The recipe SHALL add a class-imbalance countermeasure aimed at the carb-priority staples (`white_rice`, `brown_rice`, `pasta`, `bread_white`, `bread_wholemeal`, `potato_boiled`, `potato_mashed`, `chips_fries`); the recipe-upgraded checkpoint SHALL raise the per-class heldout IoU of each staple that is below the re-derived gate at the re-measured baseline (currently `bread_white` 0.4315 and `potato_boiled` 0.4648 on the pre-re-cut split — the uplift set anchors to the gate, not the floors, per Decision 18) by ≥ 0.05, with no staple regressing by more than 0.02; staples first measurable after the [2.6](#2.6) re-cut SHALL be judged against the re-derived floors ([1.6](#1.6)) rather than uplift deltas; design MAY refine these margins against the re-measured baseline with a logged rationale.  
4. <a name="2.4"></a>The recipe-upgraded checkpoint SHALL raise heldout mean food-class IoU by ≥ 0.03 over the pinned baseline — model `24e0b022241a` (checkpoint_letterbox, 0.4054 on the current split), re-measured per [2.6](#2.6) — on the same split, with per-class and mean IoU reported by the existing validation harness.  
5. <a name="2.5"></a>The exported artefact SHALL continue to meet the pipeline budgets: ≤ 24 MiB on-disk FP16 (pipeline Req 8.2 as amended by model-production Decision 13; see Decision 6) and ≤ 250 ms per view on the v1 hardware floor (pipeline Req 8.3), verified before bundling.  
6. <a name="2.6"></a>Before any run is judged against Requirements 1–3, the heldout split SHALL be re-cut stratified so every carb-priority staple has heldout instances (recorded as an amendment to model-production [Req 2.2](../model-production/requirements.md#2.2): new fixed seed, then frozen again), and the pinned baseline SHALL be re-measured on the re-cut split with mean and per-class IoU recorded in the decision log; IF the re-measured mean differs from 0.4054 by more than 0.02, THEN the 0.48 gate derivation (Decision 5) SHALL be revisited with a logged outcome.  

### 3. Backbone Swap Track (Gated on Conversion Spike)

**User Story:** As the developer, I want SegFormer-B0 evaluated as a backbone replacement without betting the schedule on it, so that a possible step-change in accuracy is explored only after its on-device feasibility is proven.

**Acceptance Criteria:**

1. <a name="3.1"></a>Before any backbone-swap training run, a conversion spike SHALL determine whether SegFormer-B0 (a) converts to Core ML, (b) produces an FP16 artefact ≤ 24 MiB (pipeline Req 8.2 as amended), (c) runs ≤ 250 ms per 513×513 inference ANE-resident on the v1 hardware floor (pipeline Req 8.3), and (d) matches its PyTorch outputs against the equivalence oracle and thresholds of model-production [Req 4.3](../model-production/requirements.md#4.3) (Decision 7); the verdict on all four SHALL be recorded in the decision log.  
2. <a name="3.2"></a>IF the spike fails any criterion in [3.1](#3.1), THEN the backbone swap SHALL be rejected without a training run and the failure recorded, leaving the training-recipe upgrade (Requirement 2) as the sole track.  
3. <a name="3.3"></a>IF the spike passes, THEN a SegFormer-B0 candidate SHALL be trained with the same recipe (initialisation policy and imbalance countermeasure) on the same re-cut split as the Requirement 2 candidate, and adopted only if it beats the recipe-upgraded checkpoint (amended by Decision 29: the Requirement 2 recipe was rejected and its weighting banned after this was written — Decisions 24/25, snaq-parity Decision 13 — and the v1 label space has left the tree, so "same recipe / same split / comparison target" now means the Decision 27 incumbent recipe on the merged corpus, compared against the promoted `ab812dc3aa9d` checkpoint) by at least an adoption margin — set in design, defaulting to 0.02 — on both mean food-class IoU and the eight-staple mean; otherwise the existing architecture is retained and the comparison recorded.  

### 4. Rejected Approaches Recorded

**User Story:** As the developer, I want the evaluated-and-rejected approaches written down with the constraint each violates, so that they are not re-opened in later sessions.

**Acceptance Criteria:**

1. <a name="4.1"></a>The decision log SHALL record text-conditioned segmentation (CLIPSeg-style), the SAM family (MobileSAM, SAM3-distilled), and FoodSAM as evaluated-and-rejected, each citing only the constraints actually shown violated (weight budget and/or the single-pass multi-class output contract of pipeline Decision 11), with ANE latency recorded as unverified where no measurement exists rather than claimed as a violation. *Satisfied by Decision 8.*  
2. <a name="4.2"></a>The decision log SHALL record the `plate`-class question as open and unresolved, with any palette change explicitly out of scope for this spec. *Satisfied by Decision 9.*  


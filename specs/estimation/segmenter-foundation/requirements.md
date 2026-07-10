# Requirements: Segmenter Foundation

## Introduction

This spec decides the model foundation for the on-device food segmenter: the accuracy gate it must meet, the training recipe that gets it there, and whether the backbone changes. It is driven by the Track A deep-research findings (`docs/agent-notes/model-foundation-research.md`): the shipped model's 0.40–0.43 heldout mIoU is genuinely low, but the 0.60 gate (pipeline Decision 14, model-production [Req 3.2](../model-production/requirements.md#3.2)) sits above the FoodSeg103 achievable frontier (~0.52 SOTA, reached only by 100M+ parameter models). The sibling `model-production` spec owns the dataset→train→export→bundle process and consumes the gate this spec re-derives; this spec changes what is trained and what bar it must clear, not how builds are run.

## Non-Goals

- Changing the 35-class palette, its membership, or channel order — `plate` as a class is recorded as an open sub-question only.
- In-house self-supervised pretraining runs (BEiT-style MIM from scratch) — only published pretrained checkpoints are used.
- Re-litigating settled calls: FoodSeg103 stays the training set; seefood, FoodSAM, and text-conditioned segmentation remain rejected.
- Retiring the developer override — a below-gate model can still ship flagged (Decision 4).
- Re-deriving the runtime inference architecture or the production process — owned by `estimation/pipeline` and `estimation/model-production`.
- Executing GPU training runs or acquiring datasets — human-gated stages tracked through the `model-production` process.
- Data/taxonomy overhaul of FoodSeg103 (relabelling, class merging beyond the existing v1 remap).
- Android/TFLite production export.

## Requirements

### 1. Re-Derived Accuracy Gate

**User Story:** As the developer, I want the segmenter accuracy gate derived from what is achievable on FoodSeg103, so that the gate steers shipping decisions instead of being permanently overridden.

**Acceptance Criteria:**

1. <a name="1.1"></a>The design SHALL derive a replacement for the 0.60 heldout mean-IoU gate from three named inputs: the published FoodSeg103 frontier at a comparable parameter budget, the shipped baseline (0.40–0.43 mIoU), and the carb-priority per-class floors ([Req 2.3](#2.3)); the derivation and resulting number SHALL be recorded in this spec's decision log before the first training run that is judged against it.  
2. <a name="1.2"></a>The re-derived gate SHALL lie within the provisional band 0.45 ≤ mean IoU ≤ 0.52 on the fixed FoodSeg103 heldout split; a value outside this band SHALL require a logged justification.  
3. <a name="1.3"></a>WHEN the gate is fixed in design, the export-eligibility criterion in `model-production` ([Req 3.2](../model-production/requirements.md#3.2)) SHALL be amended to reference the re-derived value, so the gate has one authoritative home and no stale 0.60 reference remains normative.  
4. <a name="1.4"></a>The developer-override path SHALL remain available: IF a checkpoint is below the re-derived gate, THEN it MAY still ship with the shortfall recorded against the build and estimates flagged low-confidence, as under the current process.  

### 2. Training-Recipe Upgrade (Primary Lever)

**User Story:** As the developer, I want the existing DeepLabV3+MobileNetV3-Large retrained with a stronger recipe, so that accuracy improves — especially on the collapsed carb staples — without any Core ML conversion risk.

**Acceptance Criteria:**

1. <a name="2.1"></a>The upgraded recipe SHALL keep the existing DeepLabV3+MobileNetV3-Large architecture, 513×513 input, and 35-channel single-pass per-pixel class-probability output (pipeline Decision 11) unchanged, so the exported artefact remains a drop-in replacement.  
2. <a name="2.2"></a>The recipe SHALL initialise from a published pretrained checkpoint whose licence permits bundling in a commercial app, and the checkpoint's source, licence, and SHA-256 SHALL be recorded in the build lineage (model-production [Req 1.3](../model-production/requirements.md#1.3)).  
3. <a name="2.3"></a>The recipe SHALL add a class-imbalance countermeasure targeting the carb-priority staples (`white_rice`, `brown_rice`, `pasta`, `bread_white`, `bread_wholemeal`, `potato_boiled`, `potato_mashed`, `chips_fries`); the recipe-upgraded checkpoint SHALL raise the mean per-class heldout IoU across these eight classes by ≥ 0.05 over the shipped baseline (`coreml_0295ea61edd9`), with no staple regressing by more than 0.02; design MAY refine these margins against the first run's per-class distribution with a logged rationale.  
4. <a name="2.4"></a>The recipe-upgraded checkpoint SHALL raise heldout mean IoU by ≥ 0.03 over the shipped baseline on the same fixed split, measured by the existing validation harness with per-class and mean IoU reported.  
5. <a name="2.5"></a>The exported artefact SHALL continue to meet the pipeline budgets: ≤ 10 MB on-disk FP16 and ≤ 250 ms per inference ANE-resident on the primary device, verified before bundling.  

### 3. Backbone Swap Track (Gated on Conversion Spike)

**User Story:** As the developer, I want SegFormer-B0 evaluated as a backbone replacement without betting the schedule on it, so that a possible step-change in accuracy is explored only after its on-device feasibility is proven.

**Acceptance Criteria:**

1. <a name="3.1"></a>Before any backbone-swap training run, a conversion spike SHALL determine whether SegFormer-B0 (a) converts to Core ML, (b) produces an FP16 artefact ≤ 10 MB, (c) runs ≤ 250 ms per 513×513 inference ANE-resident on the primary device, and (d) matches its PyTorch outputs within a tolerance stated in design; the verdict on all four SHALL be recorded in the decision log.  
2. <a name="3.2"></a>IF the spike fails any criterion in [3.1](#3.1), THEN the backbone swap SHALL be rejected without a training run and the failure recorded, leaving the training-recipe upgrade (Requirement 2) as the sole track.  
3. <a name="3.3"></a>IF the spike passes, THEN a SegFormer-B0 FoodSeg103 retrain SHALL be adopted only if it beats the recipe-upgraded checkpoint on the same heldout split on both mean IoU and the carb-staple mean of [Req 2.3](#2.3); otherwise the existing architecture is retained and the comparison recorded.  

### 4. Rejected Approaches Recorded

**User Story:** As the developer, I want the evaluated-and-rejected approaches written down with the constraint each violates, so that they are not re-opened in later sessions.

**Acceptance Criteria:**

1. <a name="4.1"></a>The decision log SHALL record text-conditioned segmentation (CLIPSeg-style), the SAM family (MobileSAM, SAM3-distilled), and FoodSAM as evaluated-and-rejected, each citing the specific violated constraint (size budget, ANE latency, and/or the single-pass multi-class output contract of pipeline Decision 11).  
2. <a name="4.2"></a>The decision log SHALL record the `plate`-class question as open and unresolved, with any palette change explicitly out of scope for this spec.  


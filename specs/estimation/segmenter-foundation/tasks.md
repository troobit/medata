---
references:
    - specs/estimation/segmenter-foundation/requirements.md
    - specs/estimation/segmenter-foundation/design.md
    - specs/estimation/segmenter-foundation/decision_log.md
metadata:
    ledger_note: |-
        What `[x]` means here. A checked box means that task's deliverable landed — for
        documentation tasks a logged decision or amended document, for code tasks a merged
        `tools/segmenter/` (or HarnessCore) change with its tests green. It does NOT mean a
        gated stage (GPU training run, dataset-dependent re-cut, on-device ANE latency
        measurement) actually ran: Phase 3 and the STOP tasks in Phase 4 are human/compute-
        gated, tracked here as sequenced tasks, and need a human with the dataset, a GPU/MPS
        box, or the physical iPhone 16 Pro (floor re-based by Decision 22). This spec DOES land code (design.md §1 second
        pass): carve stratification, co-occurrence loss, bar constants, SegBench bar, spike
        script. Code tasks in Phase 2 require a branch containing the estimation-quality
        PRD's training-pipeline landing (design.md §2.1 — merged to research, changelog
        fdc89a0; this worktree branched pre-merge).
---
# Segmenter Foundation — Implementation Tasks

## Phase 1: Bars and Amendment Pass (autonomous)

- [x] 1. Record the re-derived bars in the decision log <!-- id:2mfkxyo -->
  - Done: gate fixed at mean food-class IoU >= 0.48 (Decision 5, arithmetic corrected 2026-07-11), per-staple floors at 0.45 (Decision 14), label-space comparability note recorded (design §3.1), uplift set anchored to the gate (Decision 18). Logged before any training run is judged against them (Decision 2's rule).
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.6](requirements.md#1.6)

- [x] 2. Amend model-production requirements to the re-derived bars <!-- id:2mfkxyp -->
  - Edit specs/estimation/model-production/requirements.md: Req 3.2 and 3.4 (0.60 -> "the re-derived gate, segmenter-foundation Decision 5, currently 0.48"), Req 3.5 (0.50 floors -> "the re-derived floors, Decision 14, currently 0.45"), Req 2.2 (note: heldout re-cut under segmenter-foundation Req 2.6 — new seed, stratified, then frozen again). Add one model-production decision-log entry recording the amendments, citing this spec (the Decision 13 pattern).
  - Blocked-by: 2mfkxyo (Record the re-derived bars in the decision log)
  - Requirements: [1.3](requirements.md#1.3)

- [x] 3. Amend the pipeline spec: Decision 14 superseded, Req 8.9 amended-by note <!-- id:2mfkxyq -->
  - In specs/estimation/pipeline/decision_log.md change Decision 14's Status to 'superseded by segmenter-foundation Decision 5' (keep its text as the historical record). In specs/estimation/pipeline/requirements.md add an amended-by note to Req 8.9 in the existing Req 8.2 style.
  - Blocked-by: 2mfkxyo (Record the re-derived bars in the decision log)
  - Requirements: [1.3](requirements.md#1.3)

- [x] 4. Amend the remaining documentation sites carrying the old bars <!-- id:2mfkxz1 -->
  - docs/ml-training.md all normative 0.60/0.50 sites (lines 133, 144, 341, 350, 378, 560): new values + pointer to this spec. specs/estimation/model-production/design.md:184: gate value + pointer. model-production tasks.md/prerequisites.md: annotate ACTIVE export-eligibility wording with the new bars; do not rewrite completed/historical entries. Run make spell.
  - Blocked-by: 2mfkxyo (Record the re-derived bars in the decision log)
  - Requirements: [1.3](requirements.md#1.3)

- [x] 5. Code: update validation.py bar constants, docstrings, and tests <!-- id:2mfkxz2 -->
  - tools/segmenter/validation.py: MEAN_IOU_BAR = 0.48, CARB_PRIORITY_IOU_BAR = 0.45; correct the module/function docstrings still stating the 0.60/0.50 rule and "24 food-class names" (the palette has 32 food channels); update train.py:30,337 docstring/comment gate mentions in the same pass. Update the existing export-eligibility pytest cases to the new bars.
  - Blocked-by: 2mfkxyo (Record the re-derived bars in the decision log)
  - Requirements: [1.3](requirements.md#1.3)

- [x] 6. Code: update HarnessCore SegBench bar and its tests <!-- id:2mfkxz3 -->
  - HarnessCore/SegBench.swift:40 passesBar: 0.60 -> 0.48 so seg-bench and validation.py enforce one gate; update MedataCore/Tests/HarnessCLITests/SegBenchTests.swift:25,89,101. Debug-only surface (HARNESS_ENABLED); verify with make test (report both totals).
  - Blocked-by: 2mfkxyo (Record the re-derived bars in the decision log)
  - Requirements: [1.3](requirements.md#1.3)

## Phase 2: Dataset and Recipe Code (autonomous; needs the PRD landing in-branch)

- [x] 7. Bring the estimation-quality PRD's training-pipeline code into the working branch <!-- id:2mfkxyr -->
  - The PRD's --loss flag, loss_config helpers, and photometric augmentation are merged to research (research:tools/segmenter/train.py:796; changelog fdc89a0) but this worktree branched pre-merge. Merge research into the working branch (or execute Phase 2 tasks on research after the spec docs merge). Do not re-implement the PRD's scope (design §2.1).
  - Requirements: [2.3](requirements.md#2.3)

- [x] 8. Code: stratified heldout carve in prepare_dataset.py <!-- id:2mfkxz4 -->
  - Implement design §3.5 in carve_splits(): pass 1 computes staple presence by applying the class_mapping_foodseg103.json LUT to raw masks in memory (remapping happens after carving in write_split); pass 2 iterates staples in palette-index order with quota = min(max(3, ceil(0.12*n)), floor(n/3)), an already-assigned image counting toward every staple quota it contains; infeasibility rule (n < 3 -> heldout gets 1 + warning). New split seed recorded in splits.json + lineage, then frozen. splits.json gains a stratification block (per-staple heldout/train counts + warnings). Pytest: determinism for a fixed seed; every staple present in heldout on a synthetic corpus; the 2-image-staple infeasibility case; the quota cap (a 3-5 image staple keeps a training majority).
  - Blocked-by: 2mfkxyr (Bring the estimation-quality PRD's training-pipeline code into the working branch)
  - Requirements: [2.6](requirements.md#2.6)

- [x] 9. Code: co_stats.json statistics pass in prepare_dataset.py <!-- id:2mfkxz5 -->
  - Per design §4.3 (Decision 15): per-class pixel counts per split plus image-level joint presence counts over the training split only, FoodSeg103-internal; the file records the split seed and class-mapping SHA-256 it was built from; its own SHA-256 joins the lineage. Pytest: statistics generation on synthetic masks.
  - Blocked-by: 2mfkxz4 (Code: stratified heldout carve in prepare_dataset.py)
  - Requirements: [2.3](requirements.md#2.3)

- [x] 10. Code: co-occurrence loss option on the landed loss plumbing <!-- id:2mfkxz6 -->
  - Add the co-occurrence option to the landed loss_config structure (new choice or a term inside combined — implementer's call): L = weighted_ce + lambda*L_co per design §4.3, lambda default 0.1, max-pooled presence with LSE/top-k as the noted fallback; pair weights up-weight implausible false presences (the confusion half — the presence-BCE term and weighted_ce base carry the collapse half). Fail-fast when co_stats.json is missing or its seed/mapping-SHA mismatches the invocation. lambda and pooling choice recorded in lineage. weighted_ce alone is the documented fallback if impractical. Pytest: L_co zero when presence matches ground truth; finite gradients; both fail-fast cases.
  - Blocked-by: 2mfkxyr (Bring the estimation-quality PRD's training-pipeline code into the working branch), 2mfkxz5 (Code: co_stats.json statistics pass in prepare_dataset.py)
  - Requirements: [2.3](requirements.md#2.3)

- [x] 11. Survey, vet, and probe the pretrained checkpoint per Decision 17 <!-- id:2mfkxyu -->
  - Selection order (design §4.2): timm mobilenetv3_large_100.miil_in21k_ft_in1k IF the state-dict adapter round-trips (identical logits on a probe image vs timm-native) AND the licence permits commercial bundling; else torchvision MobileNet_V3_Large_Weights.IMAGENET1K_V2 backbone + fresh head; retaining the COCO-seg DEFAULT is a permitted logged outcome if the survey favours it (triggers Decision 12's expected-uplift-revised-down record). Record source URL, licence identifier, SHA-256. Reject research/non-commercial licences regardless of accuracy.
  - Requirements: [2.2](requirements.md#2.2)

- [x] 12. Code: lineage schema additions (pretrained_checkpoint, co_stats reference) <!-- id:2mfkxyw -->
  - Add a pretrained_checkpoint object (source URL, licence, SHA-256) and the co_stats.json SHA-256 to build/lineage.json via lineage.py/train.py, satisfying model-production Req 1.3. Pytest: lineage round-trip includes the new fields.
  - Blocked-by: 2mfkxyr (Bring the estimation-quality PRD's training-pipeline code into the working branch), 2mfkxyu (Survey, vet, and probe the pretrained checkpoint per Decision 17)
  - Requirements: [2.2](requirements.md#2.2)

- [x] 13. Specify the SegFormer-B0 conversion-spike procedure <!-- id:2mfkxza -->
  - Done in design §5.1 (Decisions 7, 16): four ordered stop-on-fail criteria — Core ML conversion; FP16 artefact <= 24 MiB (export.py WEIGHTS_MAX_BYTES); <= 250 ms ANE-resident at 513x513 on the iPhone 16 Pro (v1 hardware floor per Decision 22, measured directly); equivalence per model-production Req 4.3 as amended (argmax > 99%, logit < 0.5).
  - Requirements: [3.1](requirements.md#3.1)

- [x] 14. Code + run: spike_segformer.py autonomous half (criteria 1, 2, 4) <!-- id:2mfkxyx -->
  - Build tools/segmenter/spike_segformer.py (HF transformers added to tools/segmenter/requirements.txt as a spike-only dependency): load a public SegFormer-B0 checkpoint (accuracy irrelevant), graft a 35-channel head, coremltools FP16 export at 513x513, measure artefact size, run the equivalence oracle (oracle_agreement at export.py:401, reference_input at export.py:150). Emit build/spike_segformer.json (four booleans + measurements; latency left pending). A hard conversion failure ends the spike (criterion 1 fails, Req 3.2).
  - 2026-07-11: code half landed and unit-tested; the CONVERSION RUN is still pending — torch/transformers are not installed in the dev environment, so the script must be executed in the gated session (python tools/segmenter/spike_segformer.py) before the verdict JSON exists.
  - 2026-08-09: conversion run executed — autonomous half PASS (Python 3.13 venv at tools/segmenter/.venv; torch 2.7.0, transformers 5.14.1, coremltools 9.0; checkpoint nvidia/segformer-b0-finetuned-ade-512-512). Criterion 1: converts to Core ML (FP16 mlprogram, 513x513, 35 channels) = true. Criterion 2: artefact 7,622,430 bytes vs 25,165,824-byte budget (7.3 MiB of 24 MiB) = true. Criterion 4: oracle max abs logit err 0.0036 (< 0.5), argmax agreement 0.9998 (> 0.99) = true. Criterion 3 (latency, ANE residency) = null, pending task 20 on the iPhone 16 Pro. Verdict JSON at tools/segmenter/build/spike_segformer.json (gitignored build/ — figures transcribed here; task 21 records the full verdict in the decision log after task 20).
  - Blocked-by: 2mfkxza (Specify the SegFormer-B0 conversion-spike procedure)
  - Requirements: [3.1](requirements.md#3.1)

- [x] 15. Record text-conditioning, SAM family, and FoodSAM as evaluated-and-rejected <!-- id:2mfkxzb -->
  - Done as Decision 8 (preamble corrected 2026-07-10: budget/contract violations cited; ANE latency recorded as unverified, not violated).
  - Requirements: [4.1](requirements.md#4.1)

- [x] 16. Record the plate-class question as open <!-- id:2mfkxzc -->
  - Done as Decision 9 (status proposed): recorded open per Req 4.2; no palette change proposed.
  - Requirements: [4.2](requirements.md#4.2)

## Phase 3: Gated Dataset and Training Stages (human/compute-gated)

- [x] 17. STOP — execute the stratified re-cut and re-measure the pinned baseline <!-- id:2mfkxz7 -->
  - Needs the FoodSeg103 dataset on disk. Run prepare_dataset.py with the new stratified carve and a new seed; then run_validation.py for checkpoint_letterbox.pt (model 24e0b022241a) against the re-cut heldout split. Record mean and the FULL per-class table in the decision log. Check both revisit triggers: |re-measured mean - 0.4054| > 0.02 -> revisit Decision 5 (Req 2.6); any staple baseline < 0.40 -> revisit Decision 14 (design §3.2a). All later uplift deltas anchor to this table.
  - 2026-07-15: done (Decision 21). Seed 20260715, frozen; heldout 854 with all five EXISTING staples stratified in. brown_rice/bread_wholemeal/potato_mashed have ZERO images dataset-wide (mapping routes no source class to them) — no seed can make them measurable. Full-heldout re-measure 0.7403 is train-contaminated (pinned model trained on 78.7% of the re-cut heldout); the uplift anchor is the leak-free 182-image table (mean 0.3776). Decision 5 revisit trigger fired (leak-free delta -0.028); Decision 14 trigger did not fire on any measured staple.
  - Blocked-by: 2mfkxz4 (Code: stratified heldout carve in prepare_dataset.py)
  - Requirements: [2.6](requirements.md#2.6)

- [x] 18. STOP — run the recipe-upgraded GPU training job <!-- id:2mfkxys -->
  - Human/compute-gated multi-hour MPS/GPU run of tools/segmenter/train.py: chosen init (task 11), co-occurrence loss (task 10), re-cut splits (task 17), lineage additions (task 12).
  - Blocked-by: 2mfkxz6 (Code: co-occurrence loss option on the landed loss plumbing), 2mfkxyw (Code: lineage schema additions pretrained_checkpoint, co_stats reference), 2mfkxz7 (STOP — execute the stratified re-cut and re-measure the pinned baseline)
  - Requirements: [2.4](requirements.md#2.4)

- [x] 19. STOP — validate the recipe-upgraded checkpoint against Reqs 2.3/2.4/2.5 as written <!-- id:2mfkxyt -->
  - run_validation.py against the re-cut heldout split, judged against the task 17 baseline table: mean food-class IoU uplift >= 0.03 (Req 2.4 — the track's success measure, NOT the gate); each staple below the 0.48 gate at baseline gains >= 0.05, staples first measurable after the re-cut are judged against the 0.45 floors, no staple regresses > 0.02 (Req 2.3/Decision 18). Report the 0.48 gate outcome separately as export-eligibility: below-gate + criteria-met triggers Req 1.5's logged residual-gap entry (owner: backbone track or follow-up data work), and the Decision 4 override applies if shipping. Export budgets: <= 24 MiB FP16, <= 250 ms on the v1 hardware floor (Req 2.5).
  - Blocked-by: 2mfkxys (STOP — run the recipe-upgraded GPU training job)
  - Requirements: [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [1.5](requirements.md#1.5)

## Phase 4: Backbone Swap Spike (gated half + comparison)

- [x] 20. STOP — measure SegFormer-B0 ANE latency and residency on the iPhone 16 Pro <!-- id:2mfkxyy -->
  - Human-gated: Xcode Core ML performance report on the iPhone 16 Pro (v1 hardware floor — Decision 16 as amended by Decision 22). Confirm ANE residency (no GPU/CPU fallback) and <= 250 ms per 513x513 inference. Only runs if task 14's conversion succeeds.
  - 2026-08-13 measured (artifact regenerated same day, matching the 2026-08-09 pass): prediction median 12.68 ms (n=120), compile 67.05 ms, load 21.34 ms; FULL ANE residency — all 315 dispatchable ops prefer the Neural Engine, zero CPU/GPU dispatch. Report committed at artifacts/spike_segformer-you.mlperf/report.json (Decision 28)
  - Blocked-by: 2mfkxyx (Code + run: spike_segformer.py autonomous half criteria 1, 2, 4)
  - Requirements: [3.1](requirements.md#3.1)

- [x] 21. Record the spike verdict in the decision log (pass/fail per criterion) <!-- id:2mfkxyz -->
  - Transcribe build/spike_segformer.json plus the task 20 latency verdict into decision_log.md whether the outcome is pass or fail (Req 3.1). A fail on any criterion closes Requirement 3 without a training run (Req 3.2).
  - 2026-08-13: Decision 28 records the FULL PASS on all four criteria — converts, 7.3 MiB vs 24 MiB, 12.68 ms fully ANE-resident, oracle argmax 99.87%. Task 22's retrain condition is live
  - Blocked-by: 2mfkxyx (Code + run: spike_segformer.py autonomous half criteria 1, 2, 4), 2mfkxyy (STOP — measure SegFormer-B0 ANE latency and residency on the iPhone 16 Pro)
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2)

- [ ] 22. STOP — IF the spike passes, retrain SegFormer-B0 and compare with the adoption margin <!-- id:2mfkxz0 -->
  - Conditional on task 21 being a full pass. Retrain SegFormer-B0 on the same re-cut split with the same recipe (init policy + co-occurrence loss), not an unweighted baseline. Adopt only if it beats the recipe-upgraded checkpoint (task 19) by >= 0.02 on BOTH mean food-class IoU and the eight-staple mean (Req 3.3); otherwise record the comparison and keep the existing architecture. Adoption hands export-gate integration to model-production.
  - 2026-08-13: Decision 29 re-anchors the comparison — the as-written recipe, split, and target were superseded by Decisions 24/25/27 and snaq-parity Decision 13 (weighting banned, v1 label space gone, task-19 checkpoint rejected). Executed instead as: segformer_b0 (published ADE init) with the exact Decision 27 incumbent recipe on the merged corpus, judged against ab812dc3aa9d on the leak-free anchor with the unchanged >= 0.02 two-mean margin. Pre-launch smoke exposed an MPS-only BatchNorm-backward failure in the SegFormer decode head — fixed in archs.py (contiguous-input pre-hook). Run launched: tools/segmenter/build/train_segformer_merged_20260813.log
  - Blocked-by: 2mfkxyz (Record the spike verdict in the decision log pass/fail per criterion), 2mfkxz7 (STOP — execute the stratified re-cut and re-measure the pinned baseline), 2mfkxzd (Code: register segformer_b0 in archs.py agent-executable prep for the task 22 retrain)
  - Requirements: [3.3](requirements.md#3.3)

- [x] 23. Code: register segformer_b0 in archs.py (agent-executable prep for the task 22 retrain) <!-- id:2mfkxzd -->
  - ArchSpec per the archs.py contract: model factory building SegFormer-B0 (transformers, spike-only dep) with the 36-channel head grafted per spike_segformer.py's graft, published-init policy, plain-tensor forward adapter (SegFormer emits logits at H/4 — upsample per the spike), and the export adapter export.py dispatches through
  - Registry-fixture tests pass without torch (lazy imports per the module convention); tools pytest suite stays green; spike_segformer.py may share the graft helper rather than duplicating it
  - Decision 28 settled viability (12.68 ms, fully ANE-resident); this task only makes --arch segformer_b0 selectable so the task 22 STOP can run as a training command
  - 2026-08-13: landed — segformer_b0 registered in archs.py (published init nvidia/segformer-b0-finetuned-ade-512-512, weights-free rebuild for checkpoint loads, plain_tensor_logits normaliser); spike_segformer.py now delegates its graft to the shared archs.segformer_b0_grafted helper; --arch segformer_b0 selectable in train.py. Tools suite green: 266 passed (torch venv), 238 passed + 20 skipped (torch-free)

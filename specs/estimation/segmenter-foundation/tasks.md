---
references:
    - requirements.md
    - design.md
    - decision_log.md
metadata:
    ledger_note: |-
        What `[x]` means here. A checked box means the specification / decision-log /
        cross-reference work for that task landed — this spec produces documentation and
        decisions, not `tools/segmenter/` code (Hard Limit, see design.md §1). It does NOT
        mean a gated stage (GPU training run, on-device ANE latency measurement) actually
        ran. Phase 3 (training run) and Phase 4 (on-device spike half) are human/compute-gated
        and are tracked here as sequenced tasks, not executed by an agent; their completion
        requires a human with a GPU and a physical iPhone 16 Pro. Phase 1 and Phase 2 tasks
        are autonomously executable now. See design.md §2 for the sequencing dependency on
        the `debug-read` branch's estimation-quality PRD (its "Segmenter training pipeline"
        context must land in `tools/segmenter/` before any Phase 3 task can start).
---
# Segmenter Foundation — Implementation Tasks

## Phase 1: Gate Derivation (autonomous)

- [ ] 1. Record the re-derived gate decision in the decision log <!-- id:2mfkxyo -->
  - Fix the gate at mean IoU >= 0.48 per design.md §3.2 (Decision 5): baseline 0.4054 plus the mandatory uplifts (Req 2.3/2.4) rounded to sit inside the 0.45-0.52 band with margin. Log before any training run is judged against it (Decision 2's rule).
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2)

- [ ] 2. Amend model-production Req 3.2 to reference the re-derived gate <!-- id:2mfkxyp -->
  - Edit specs/estimation/model-production/requirements.md Req 3.2: replace mean IoU >= 0.60 with >= 0.48; citing this spec. Add a model-production decision-log entry recording the amendment; mirroring how Decision 13 there amended pipeline Req 8.2 for the weight budget.
  - Blocked-by: 2mfkxyo (Record the re-derived gate decision in the decision log)
  - Requirements: [1.3](requirements.md#1.3)

- [ ] 3. Mark pipeline Decision 14 as superseded <!-- id:2mfkxyq -->
  - In specs/estimation/pipeline/decision_log.md change Decision 14's Status line to 'superseded by segmenter-foundation Decision 5'. Keep its Context/Decision/Rationale text as the historical record; do not delete it.
  - Blocked-by: 2mfkxyo (Record the re-derived gate decision in the decision log)
  - Requirements: [1.3](requirements.md#1.3)

## Phase 2: Recipe Specification (autonomous)

- [ ] 4. Identify and vet a licensed pretrained checkpoint for the training-recipe upgrade <!-- id:2mfkxyu -->
  - Search torchvision/timm/HuggingFace for a MobileNetV3-Large checkpoint pretrained beyond plain ImageNet-1K supervised (design.md §4.2 preference order); record source URL; licence identifier; and SHA-256; reject research/non-commercial-only licences regardless of accuracy. Fallback if none exists: best available supervised ImageNet checkpoint per Decision 3's anticipated risk.
  - Requirements: [2.2](requirements.md#2.2)

- [ ] 5. Specify the class-imbalance countermeasure (co-occurrence loss, weighted_ce fallback) <!-- id:2mfkxyv -->
  - Specify the co-occurrence-relationship loss (Springer 10.1007/s11694-025-03647-2) as the primary recipe option targeting the eight carb-priority staples (design.md §4.3). Specify weighted_ce (inverse-frequency) as the documented fallback if the co-occurrence matrix input proves impractical against the current train.py structure. This is a specification handed to the debug-read PRD's --loss flag scaffolding not a tools/segmenter/ edit.
  - Requirements: [2.3](requirements.md#2.3)

- [ ] 6. Specify the checkpoint-provenance lineage schema addition <!-- id:2mfkxyw -->
  - Specify a pretrained_checkpoint object for build/lineage.json (source URL; licence; SHA-256) alongside the existing train_config satisfying model-production Req 1.3. One field-group addition handed to whichever branch lands train.py/lineage.py changes next (debug-read or its follow-on) — not implemented here.
  - Requirements: [2.2](requirements.md#2.2)

- [ ] 7. Specify the SegFormer-B0 conversion-spike procedure (four criteria, reused oracle thresholds) <!-- id:2mfkxza -->
  - Write the four-criterion spike procedure (design.md §5.1): Core ML conversion success; FP16 artefact <= 24 MiB; <= 250 ms ANE-resident inference on iPhone 16 Pro; and PyTorch-vs-CoreML equivalence within the reused model-production oracle thresholds (Decision 7). Stop at the first failed criterion per Req 3.2.
  - Requirements: [3.1](requirements.md#3.1)

- [ ] 8. Record text-conditioning, SAM family, and FoodSAM as evaluated-and-rejected <!-- id:2mfkxzb -->
  - Already drafted as Decision 8 in decision_log.md: CLIPSeg; MobileSAM/SAM3-distilled; and FoodSAM each citing the specific violated constraint (size budget and/or the single-pass multi-class contract of pipeline Decision 11). This task is the checklist confirmation that Decision 8 satisfies Req 4.1 — no further edit needed unless review finds a gap.
  - Requirements: [4.1](requirements.md#4.1)

- [ ] 9. Record the plate-class question as open <!-- id:2mfkxzc -->
  - Already drafted as Decision 9 in decision_log.md (status proposed): plate-class value recorded open per Req 4.2; no palette change proposed. Checklist confirmation only.
  - Requirements: [4.2](requirements.md#4.2)

## Phase 3: Gated Training Run (human/compute-gated)

- [ ] 10. STOP — wait for debug-read estimation-quality PRD's segmenter-training-pipeline context to land in tools/segmenter/ <!-- id:2mfkxyr -->
  - Human-gated wait not code. Confirm specs/estimation/estimation-quality/prd.md 'Segmenter training pipeline' context (--loss flag; class-weight helpers; photometric augmentation) has merged into the branch that will run training. Do not re-implement its scope here (design.md §2.1).
  - Requirements: [2.1](requirements.md#2.1)

- [ ] 11. STOP — run the recipe-upgraded GPU training job against the re-derived gate <!-- id:2mfkxys -->
  - Human/compute-gated: multi-hour local MPS/GPU run of tools/segmenter/train.py with the recipe from tasks 4-6 wired through debug-read's --loss flag. Judged against the 0.48 gate (task 1) once complete. Cannot run before task 10 clears.
  - Blocked-by: 2mfkxyo (Record the re-derived gate decision in the decision log), 2mfkxyu (Identify and vet a licensed pretrained checkpoint for the training-recipe upgrade), 2mfkxyv (Specify the class-imbalance countermeasure co-occurrence loss, weighted_ce fallback), 2mfkxyw (Specify the checkpoint-provenance lineage schema addition), 2mfkxyr (STOP — wait for debug-read estimation-quality PRD's segmenter-training-pipeline context to land in tools/segmenter/)
  - Requirements: [2.4](requirements.md#2.4)

- [ ] 12. STOP — validate the recipe-upgraded checkpoint (mean IoU, carb-staple per-class IoU, export budgets) <!-- id:2mfkxyt -->
  - Run run_validation.py against the fixed held-out split. Check: mean IoU >= 0.48 (Req 2.4); each of the 8 carb-priority classes >= baseline + 0.05 with no staple regressing > 0.02 (Req 2.3); export artefact <= 24 MiB FP16 and <= 250 ms ANE-resident (Req 2.5; corrected budget per Decision 6).
  - Blocked-by: 2mfkxyr (STOP — wait for debug-read estimation-quality PRD's segmenter-training-pipeline context to land in tools/segmenter/), 2mfkxys (STOP — run the recipe-upgraded GPU training job against the re-derived gate)
  - Requirements: [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5)

## Phase 4: Backbone Swap Spike

- [ ] 13. Run the SegFormer-B0 Core ML conversion + equivalence-oracle check (autonomous half) <!-- id:2mfkxyx -->
  - Autonomous no GPU needed: run coremltools.convert() against a public SegFormer-B0 checkpoint (accuracy irrelevant; only conversion mechanics matter) at 513x513; if it converts run the equivalence-oracle check (Decision 7 thresholds) against a small fixed reference set. A hard conversion failure ends the spike (criterion 1 fails).
  - Blocked-by: 2mfkxza (Specify the SegFormer-B0 conversion-spike procedure four criteria, reused oracle thresholds)
  - Requirements: [3.1](requirements.md#3.1)

- [ ] 14. STOP — measure SegFormer-B0 on-device ANE latency and residency on iPhone 16 Pro <!-- id:2mfkxyy -->
  - Human-gated: Xcode Core ML performance report on the iPhone 16 Pro (devicectl id 6AD781BA-89FF-5A82-A2A1-B5EC9469F465); confirm ANE residency (not GPU/CPU fallback) and <= 250 ms per 513x513 inference. Only runs if task 13's conversion succeeds.
  - Blocked-by: 2mfkxyx (Run the SegFormer-B0 Core ML conversion + equivalence-oracle check autonomous half)
  - Requirements: [3.1](requirements.md#3.1)

- [ ] 15. Record the spike verdict in the decision log (pass/fail per criterion) <!-- id:2mfkxyz -->
  - Record all four criteria's pass/fail verdicts (convert; size; latency/residency; equivalence) in decision_log.md whether the outcome is pass or fail (Req 3.1). A fail on any criterion closes Requirement 3 without a training run (Req 3.2).
  - Blocked-by: 2mfkxyx (Run the SegFormer-B0 Core ML conversion + equivalence-oracle check autonomous half), 2mfkxyy (STOP — measure SegFormer-B0 on-device ANE latency and residency on iPhone 16 Pro)
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2)

- [ ] 16. STOP — IF spike passes, run the SegFormer-B0 FoodSeg103 retrain and compare against the recipe-upgraded checkpoint <!-- id:2mfkxz0 -->
  - Human/compute-gated conditional: only if task 15's verdict is a full pass. Retrain SegFormer-B0 on FoodSeg103 using the same recipe from tasks 4-6 (not an unweighted-CE baseline). Adopt only if it beats the recipe-upgraded checkpoint (task 12) on both mean IoU and the carb-staple mean (Req 3.3); otherwise record the comparison and keep the existing architecture.
  - Blocked-by: 2mfkxyz (Record the spike verdict in the decision log pass/fail per criterion), 2mfkxyt (STOP — validate the recipe-upgraded checkpoint mean IoU, carb-staple per-class IoU, export budgets)
  - Requirements: [3.3](requirements.md#3.3)

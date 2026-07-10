# Prerequisites for Segmenter Foundation

These are the human/compute-gated stages a coding agent cannot perform — a merge from another branch, a GPU, or a physical iPhone. The code-actionable work lives in `tasks.md` (Phase 1 and Phase 2, both autonomous); this file is the checklist behind the two gated stages that block completion of the spec's requirements (Requirement 2's training run and Requirement 3's spike/retrain).

## Cross-branch dependency (blocks Phase 3 entirely)

- [ ] **`debug-read` branch's estimation-quality PRD, "Segmenter training pipeline" context, merges into the branch that will run training.** That PRD (`specs/estimation/estimation-quality/prd.md`, unmerged as of this writing) lands the `--loss {ce,weighted_ce,focal,dice,combined}` flag on `tools/segmenter/train.py`, the torch-free class-weight helpers, and opt-in photometric augmentation — the code this spec's Requirement 2 recipe (tasks 4–6: pretrained-checkpoint sourcing, class-imbalance countermeasure, lineage schema) is specified against. Design §2.1 covers the sequencing reasoning: re-implementing that flag here would fork the same code change across two branches. **This is the single hardest blocker** — nothing in Phase 3 (tasks 10–12) can start before it.

## Training (Requirement 2 — Phase 3)

- [ ] **Run the recipe-upgraded GPU training job** (`tools/segmenter/train.py`, multi-hour local MPS/GPU): DeepLabV3+MobileNetV3-Large @ 513×513, initialised from the licensed pretrained checkpoint (task 4), using the class-imbalance loss (task 5) via the `debug-read` PRD's `--loss` flag. Needs: the merged training-pipeline code (above) and a GPU. Produces the checkpoint judged by task 12.
- [ ] **Validate the recipe-upgraded checkpoint** (`run_validation.py`, automated once the checkpoint exists): mean IoU ≥ 0.48 (the re-derived gate, task 1/Decision 5), each of the 8 carb-priority classes ≥ baseline + 0.05 with no staple regressing > 0.02 (Req 2.3), export artefact ≤ 24 MiB FP16 and ≤ 250 ms ANE-resident (Req 2.5, corrected budget per Decision 6). A sub-bar run is not a spec failure — the developer override (Decision 4) still applies — but the shortfall is recorded.

## Backbone-swap spike (Requirement 3 — Phase 4)

- [ ] **Autonomous half — Core ML conversion + equivalence-oracle check.** No GPU needed; runs in a Python/coremltools environment. Covered by `tasks.md` task 13, not gated, listed here only because it precedes the gated half below.
- [ ] **On-device ANE latency and residency measurement** on the iPhone 16 Pro (devicectl id `6AD781BA-89FF-5A82-A2A1-B5EC9469F465`, name `you`) via Xcode's Core ML performance report. Needs: a Mac + Xcode and the physical device. Confirms criterion 3 of the spike (Req 3.1) — the criterion the research flagged as the single biggest unknown ("nobody publishes Core ML / ANE latencies for these" transformer candidates).
- [ ] **IF the spike passes all four criteria — SegFormer-B0 FoodSeg103 retrain** using the same recipe as the Requirement 2 checkpoint (not a separate unweighted baseline), compared against it on both mean IoU and the carb-staple mean (Req 3.3). A second gated GPU run, strictly after the spike passes and the Requirement 2 recipe exists to reuse. If the spike fails any criterion, this stage does not happen — Requirement 3 closes with the failure recorded (task 15) and Requirement 2 remains the sole track.

## Notes

- Every gated stage above produces an artefact or a verdict that a later `tasks.md` task consumes (task 1's gate value informs task 12's pass/fail check; task 15's verdict gates task 16). None of them are optional for the spec's requirements to be fully satisfied, but Phase 1 and Phase 2 (the specification work) are already complete once written — the spec's *documents* do not wait on these stages, only the *training outcomes* they describe do.
- This spec produces no code and touches no files outside `specs/estimation/segmenter-foundation/` (Hard Limit, design.md §1). The gated stages above are executed by whichever branch/session picks up `tools/segmenter/` work next, informed by tasks 1–9's specifications.

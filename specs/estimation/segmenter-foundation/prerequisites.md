# Prerequisites for Segmenter Foundation

These are the human/compute-gated stages a coding agent cannot perform — a dataset on disk, a GPU/MPS run, or a physical iPhone. The code-actionable work lives in `tasks.md` (Phases 1–2, autonomous); this file is the checklist behind the gated stages (Phase 3 training track, Phase 4 spike half and retrain).

## Cross-branch dependency — SATISFIED, one local action remains

- [x] **`debug-read`'s estimation-quality PRD, "Segmenter training pipeline" context, merged to `research`.** Verified 2026-07-10: `research:tools/segmenter/train.py:796` carries the `--loss` flag and `loss_config` helpers; changelog entry `fdc89a0` records the integration.
- [ ] **Bring that landing into the branch executing Phase 2** (tasks.md task 7): this worktree (`estimation/model-foundation`) branched off `research@1b172b2`, pre-merge — merge `research` in, or execute the Phase 2 code tasks on `research` after the spec docs merge. Do not re-implement the PRD's scope (design §2.1).

## Dataset stage (Requirement 2.6 — Phase 3, task 17)

- [ ] **FoodSeg103 on disk** (already acquired for the 2026-07-06 runs; re-listed because the re-cut re-runs `prepare_dataset.py` from it).
- [ ] **Execute the stratified re-cut + baseline re-measure** (`prepare_dataset.py` with the new carve and a new seed, then `run_validation.py` for `24e0b022241a`). Produces the per-class baseline table every later delta anchors to, and checks both revisit triggers (mean shift > 0.02 → Decision 5; any staple < 0.40 → Decision 14).

## Training (Requirement 2 — Phase 3, tasks 18–19)

- [ ] **Run the recipe-upgraded training job** (`tools/segmenter/train.py`, multi-hour local MPS/GPU): chosen init (Decision 17 survey), co-occurrence loss via the landed `--loss` plumbing, re-cut splits, lineage additions.
- [ ] **Validate against the bars as written**: mean uplift ≥ 0.03 over the re-measured baseline (Req 2.4); +0.05 for staples below the 0.48 gate at baseline, 0.45 floors for newly measurable staples, ≤ 0.02 regression elsewhere (Req 2.3 / Decision 18); the 0.48 gate reported separately as export-eligibility — a criteria-met-but-below-gate run triggers Req 1.5's residual-gap entry and may still ship under the Decision 4 override; budgets ≤ 24 MiB FP16 and ≤ 250 ms on the v1 hardware floor (Req 2.5).

## Backbone-swap spike (Requirement 3 — Phase 4)

- [ ] **Autonomous half — `spike_segformer.py` conversion + size + equivalence oracle** (tasks.md task 14; listed here only because it precedes the gated half).
- [ ] **On-device ANE latency and residency measurement on the iPhone 13 Pro Max** — the v1 hardware floor, physically available (Decision 16); NOT the iPhone 16 Pro. Xcode Core ML performance report; confirms criterion 3 (Req 3.1), the criterion the research flagged as the single biggest unknown.
- [ ] **IF the spike passes all four criteria — SegFormer-B0 retrain** on the same re-cut split with the same recipe, adopted only on a ≥ 0.02 win on both mean food-class IoU and the eight-staple mean (Req 3.3). If the spike fails any criterion, Requirement 3 closes with the failure recorded and Requirement 2 remains the sole track.

## Notes

- Every gated stage produces an artefact or verdict a later task consumes (task 17's baseline table anchors task 19's deltas; task 21's verdict gates task 22). The spec's *documents* do not wait on these stages — only the training outcomes they describe do.
- This spec lands code in `tools/segmenter/` and one Debug-only HarnessCore bar change (design.md §1 second pass; §3.3, §3.5, §4.3, §5.2) — the earlier "produces no code" note described the first-pass design and is superseded. It still does not run training or change the production process.

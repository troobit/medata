---
references:
    - specs/estimation/estimation-quality/prd.md
---
# MVP estimation quality — Segmenter training pipeline

## Recipe

- [x] 1. Add a class-imbalance-aware loss option to tools/segmenter/train.py via a CLI flag (--loss {ce,weighted_ce,focal,dice,combined}); omitting it reproduces todays unweighted nn.CrossEntropyLoss byte-for-byte in the recorded train_config <!-- id:pgctxe6 -->

- [x] 2. Express loss selection and class-weight computation as pure, torch-free-testable helpers; record the selected loss + weighting scheme in the checkpoint and build/lineage.json train_config <!-- id:pgctxe7 -->

- [x] 3. Add torch-free unit tests under tools/segmenter/tests/ covering weight-derivation and loss-selection; they pass without torch and the tools pytest suite stays green <!-- id:pgctxe8 -->

- [x] 4. Add opt-in photometric (colour/brightness/contrast) augmentation applied to the image only (never the mask), off by default, recorded in train_config <!-- id:pgctxe9 -->

- [x] 5. Document the recommended next run as a single copy-pasteable command in docs/ml-training.md section 4, consistent with the resume/caffeinate run-hygiene guidance; run make spell clean <!-- id:pgctxea -->

## Gated run

- [x] 6. STOP — run an actual segmenter training job with the new recipe, export to Core ML, and swap the bundled segmenter.mlpackage (multi-hour local MPS/GPU; changes the shipped artefact) — human/compute-gated, do not run autonomously <!-- id:pgctxeb -->
  - RUN COMPLETE 2026-08-28 — VERDICT: NOT ADOPTED (segmenter-foundation Decision 35). R1 = eb18a668c6ce
  - recipe --loss combined --class-weighting sqrt_inverse --photometric-augment on data/merged_foodseg_foodrec2022 at incumbent parity (36 classes
  - 513
  - 12 epochs
  - batch 16
  - lr 1e-3
  - poly-0.9)
  - Measured on heldout_leakfree (182 images): mean food-class IoU 0.3787 against the incumbent ab812dc3aa9d at 0.3927
  - a regression of 0.0139. Per staple: bread_white +0.0507
  - but pasta -0.1372
  - chips_fries -0.0953
  - white_rice -0.0895
  - potato_boiled -0.0237
  - Fails both halves of the promotion criterion
  - so the incumbent stays and the bundled segmenter.mlpackage is unchanged. Checkpoint and build/lineage-r1.json retained as the baseline R3's ablation reads against
  - The shape — one weak staple up
  - three strong staples down — is the signature of the class re-weighting
  - matching Decision 25's attribution of inverse-frequency weighting as the staple-killer. Probable
  - not measured: three levers moved at once
  - which is why task 10 is an ablation
  - Blocked-by: pgctxe6 (Add a class-imbalance-aware loss option to tools/segmenter/train.py via a CLI flag --loss {ce,weighted_ce,focal,dice,combined}; omitting it reproduces todays unweighted nn.CrossEntropyLoss byte-for-byte in the recorded train_config), pgctxe7 (Express loss selection and class-weight computation as pure, torch-free-testable helpers; record the selected loss + weighting scheme in the checkpoint and build/lineage.json train_config), pgctxe8 (Add torch-free unit tests under tools/segmenter/tests/ covering weight-derivation and loss-selection; they pass without torch and the tools pytest suite stays green), pgctxe9 (Add opt-in photometric colour/brightness/contrast augmentation applied to the image only never the mask, off by default, recorded in train_config), pgctxea (Document the recommended next run as a single copy-pasteable command in docs/ml-training.md section 4, consistent with the resume/caffeinate run-hygiene guidance; run make spell clean)

- [x] 7. STOP — on-device deploy + capture verification that overlay speckle is gone and readings are stable (physical iPhone + human) — the real acceptance gate, cannot be automated <!-- id:pgctxec -->
  - 2026-08-04 device session: overlay speckle confirmed GONE by the developer — but from the shipped PostProcessing connected-component cleanup on the promoted coreml_ab812dc3aa9d model; task 6's retrain has not run; this gate stays open until the new recipe's model is on device (docs/agent-notes/field-truth-sessions.md)
  - 2026-08-13 developer verdict: gate closed — on-device speckle/stability verified, speckle is visibly gone. Accepted on the promoted coreml_ab812dc3aa9d model + PostProcessing cleanup; the developer accepts the outcome without waiting on task 6's retrain, overriding the 2026-08-04 hold
  - Blocked-by: pgctxeb (STOP — run an actual segmenter training job with the new recipe, export to Core ML, and swap the bundled segmenter.mlpackage multi-hour local MPS/GPU; changes the shipped artefact — human/compute-gated, do not run autonomously)

## MetaFood3D synthetic corpus and the serial run queue

- [x] 8. Spike — settle the MetaFood3D mask route, then judge whether the corpus is worth building (agent-executable, no GPU) <!-- id:pgctxed -->
  - RETITLED 2026-08-14 on acceptance of segmenter-foundation Decision 33. The original title was `Build a training corpus from the MetaFood3D Blender renders`, which this task can no longer honestly satisfy: the spike ran, and its verdict is that the corpus should NOT be built. Ticking a build criterion would have claimed work that was deliberately not done; leaving it open would have implied outstanding work when the question is settled. The task is what it turned out to be — a spike with a negative verdict — and closes as one
  - Original detail lines are retained verbatim below as the brief the spike was run against, including the two premises it falsified
  - data/Blender_render_images.tar.gz is 137 GiB gzipped, laid out as Blender_render_images/<Category>/<instance>/<Instance>/{Original,Depth,Normal}/ with about 60 viewpoints per instance across 108 categories. Extraction runs to a few hundred GB against 1.1 TiB free — check df before starting, and note the archive is not seekable, so any listing pass decompresses sequentially
  - This component ships NO segmentation masks — the dataset's masks are in RGBD_videos, which the project did not collect (docs/references.md). Single-object renders plus the Depth channel make masks derivable, but that is an inference: prove it on one category before building anything. The (bowl) categories are the risk, since a bowl or plate in frame is not food
  - tools/metafood3d/mapping_metafood3d_to_palette.json maps 13 of 108 categories onto 11 of 33 palette classes, and it was built for calibration rather than training. Decide deliberately whether to widen it: Rice and Yeast_bread are currently unmapped, and of the three zero-image staples only potato_mashed is covered — brown_rice and bread_wholemeal are not, so these renders do not close the absent-staple gap that Decision 21 recorded
  - Emit a dataset directory in the shape train.py already consumes (splits.json beside images and masks, as in data/merged_foodseg_foodrec2022), so every run below is a recipe or corpus change and never a loader change
  - Renders are synthetic single objects on a rendered background: they carry no plate clutter, no occlusion and no handheld blur, so they are a class-coverage lever, not a realism lever. Say so in whatever verdict they produce
  - VERDICT 2026-08-14 — spike run, corpus deliberately NOT built (segmenter-foundation Decision 33, status proposed). Left open rather than ticked precisely because the build criterion is unmet by choice: closing it is the human's call when Decision 33 is accepted or rejected. Two premises above are false. RGBD_videos HAS been collected, so masks were a real choice, not a fallback; and the zero-image-staple claim is a FoodSeg103-only fact from Decision 21 — the live merged corpus already holds potato_mashed 150 images / 10.77 M px, brown_rice 131 / 11.37 M, bread_wholemeal 2,546 / 229.24 M. Only beans_baked has zero train pixels, and MetaFood3D does not cover it
  - Mask question SETTLED, both routes work: render Original is RGBA with a real alpha matte, and alpha vs depth-background agree at IoU 0.9985-0.9989, so the Depth inference is confirmed; RGBD_videos masks are JPEG but effectively binary (16 levels, all <=10 or >=245, zero mid-tones, exact at >128). The blocker is corpus content, not mask mechanism
  - Rejected on four measurements: masks include the plate/boat/carton for container-served objects (Mashed_Potato/mash1 covers the whole plate at 21.3 % of frame; French_Fry fries_1, new_fries_3 and new_waffle_fry_2 likewise) and potato_mashed + chips_fries are exactly those two staples; effective sample is 80 physical objects, not 16,000 images, so thin classes get n=1 heldout objects; render food-pixel luminance runs L=44-158 by viewpoint against L=137-181 real; and the judging anchor heldout_leakfree is real-image FoodSeg103 only, so the measurable-staple gap cannot be closed from here anyway
  - Mapping deliberately NOT widened: Rice and Yeast_bread carry no grain type in the dataset, so mapping them would guess wrong-class pixels into white_rice/bread_white/bread_wholemeal, which already hold real images
  - Confirmed as stated: these are a class-coverage lever, not a realism lever — and the coverage they offer is 11 of 33 classes from one studio tablecloth, against classes that are no longer the bottleneck

- [x] 9. WITHDRAWN by Decision 33 — R2 does not run; there is no corpus to test and the serial machine time returns to the queue <!-- id:pgctxee -->
  - Closed 2026-08-14 on acceptance of Decision 33, which was `proposed` when this title was written. Ticked to close the ledger entry, NOT to claim the run happened — the title carries the withdrawal. Left `Pending` it would have counted as outstanding work in every task sweep for a run that will never be scheduled
  - Consequence for task 10 (R3), which is blocked-by this one and whose shape was to be `set by R2's verdict`: there is now no R2 verdict to set it. Decision 33 states the serial ordering stands with R2 removed, but R3's premise came from R2. Re-scope or withdraw task 10 before it is picked up
  - ONE MACHINE, STRICTLY SERIAL — do not start this or any run below while another is in flight. About 25 min/epoch, so roughly 5 h for a 12-epoch run on MPS. Clamshell rig with caffeinate -is per docs/agent-notes; the resume sidecar caps a reboot at one lost epoch
  - The question is whether synthetic render data helps at all. Hold the Decision 27 recipe fixed and change only the corpus, so the delta is attributable to the data and nothing else
  - The mixing ratio is both the lever and the risk: these renders reach 11 palette classes, so an unweighted mix shifts class balance toward exactly those and can buy tail coverage with a staple regression — the failure mode Decision 25 already recorded once
  - Judge on heldout_leakfree against the shipped ab812dc3aa9d at 0.3927 mean food-class IoU with the 0.45 staple floors (segmenter-foundation Decisions 5 and 14). Pass an absolute --lineage path or metrics land in a stray nested tree, and seed train_config.arch or run_validation.py fails fast
  - Needs a decision entry either way, in segmenter-foundation/decision_log.md where the corpus and recipe verdicts live
  - Blocked-by: pgctxeb (STOP — run an actual segmenter training job with the new recipe, export to Core ML, and swap the bundled segmenter.mlpackage multi-hour local MPS/GPU; changes the shipped artefact — human/compute-gated, do not run autonomously), pgctxed (Spike — settle the MetaFood3D mask route, then judge whether the corpus is worth building agent-executable, no GPU)

- [x] 10. STOP — R3: attribution follow-up on R1, shape set by R1's verdict <!-- id:pgctxef -->
  - PREMISE SUPPLIED 2026-08-28 by R1's verdict (segmenter-foundation Decision 35). R1 regressed the anchor by 0.0139 with one weak staple up and three strong ones down; three levers moved at once, so the cause was not attributable
  - R3 held --loss combined and --photometric-augment fixed and dropped --class-weighting to none, at incumbent parity on data/merged_foodseg_foodrec2022
  - RUN COMPLETE 2026-08-28 18:19 — 12/12 epochs, checkpoint_r3_combined_noweight.pt, model_version 0a019c00e943. VERDICT: ADOPTED as recipe and reference checkpoint (segmenter-foundation Decision 36)
  - Measured on heldout_leakfree (182 images): mean food-class IoU 0.4192 against the incumbent ab812dc3aa9d at 0.3927 — an improvement of 0.0265
  - Every staple R1 lost is recovered: white_rice 0.6818 (R1 0.5426), pasta 0.6324 (R1 0.5125), chips_fries 0.5718 (R1 0.4646). Against the INCUMBENT: bread_white +0.0665 (and crossing its 0.45 floor for the first time), potato_boiled +0.0652, white_rice +0.0498, chips_fries +0.0119, pasta -0.0172
  - ATTRIBUTION SETTLED: the class weighting was the cause. Decision 25's finding on inverse-frequency weighting extends to the milder sqrt_inverse scheme. The combined loss and photometric augmentation are jointly beneficial once the weighting is out of the way
  - NOT swapped: the bundled segmenter.mlpackage stays ab812dc3aa9d. Export, the gates and an on-device capture pass are the separate gated step, unscheduled
  - Caveats recorded rather than rounded away: pasta is the one measurable staple down against the incumbent; export_eligible is false at the 0.48 bar (the incumbent also fails it and ships under the Decision 11 override); bread_wholemeal is 0.0000 for every model measured and brown_rice/potato_mashed are absent from the anchor
  - Blocked-by: pgctxeb (STOP — run an actual segmenter training job with the new recipe, export to Core ML, and swap the bundled segmenter.mlpackage multi-hour local MPS/GPU; changes the shipped artefact — human/compute-gated, do not run autonomously)

- [ ] 11. STOP — R4/R5: the SegFormer-B0 longer-schedule pair, Decision 30's open question <!-- id:8l5zdrf -->
  - Decision 30 rejected SegFormer-B0 at an equal 12-epoch budget, but the candidate was still climbing at epoch 12 (+0.0116, monotonic throughout) while the incumbent had plateaued at epoch 11. Whether it wins on a longer schedule is genuinely unanswered
  - This is TWO runs, not one: a longer-schedule incumbent has to run alongside the longer-schedule candidate or the comparison stops being attributable, which is Decision 29's step-parity rule. SegFormer took about 6 h at 12 epochs, so an 18-epoch pair is roughly 9 h plus 7.5 h of machine time on top of everything above
  - Lowest priority in the queue. Decision 30's own consequence is that the architectural lever is spent at this budget, so the data and recipe runs earn their machine time first
  - --arch segformer_b0 is already selectable (segmenter-foundation task 23); this task is machine time and a verdict, not code

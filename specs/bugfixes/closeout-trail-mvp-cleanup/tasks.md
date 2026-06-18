---
references:
    - specs/bugfixes/closeout-trail-mvp-cleanup/smolspec.md
---
# MVP Closeout Trail — Tasks

## Phase 1 — UI fixes (no device)

- [x] 1. Expand RefusalSheet to two detents <!-- id:v6kipyy -->
  - App/RefusalSheet.swift:94 — change .presentationDetents([.fraction(0.35)]) to .presentationDetents([.fraction(0.35), .large]).
  - First-appearance detent stays at 35%; user can drag up to .large to read long messages.
  - swift build clean; existing RefusalSheetTests MUST stay green.

- [x] 2. Freeze viewfinder during .estimating <!-- id:v6kipyz -->
  - App/CaptureFlowView.swift:67 — swap ARPreviewView(engine: engine) for a state-driven choice: live preview in every state EXCEPT .estimating(captureResult: let result), where it renders a new CapturedFramesView(result: result).
  - CapturedFramesView is a small View (same file or alongside CaptureFlowView). Decodes CGImages inline from RawFrame.imageBytes + .pixelFormat (BGRA8 post-rawframe-rgb-conversion).
  - Single mode: nadir frame fills the safe area.
  - Two-view mode: nadir + oblique stacked or side-by-side — pick whichever reads better on PhoneMax aspect; document the choice in a one-line comment.
  - All other chrome (top bar, Estimating… hint, badges) renders unchanged over the frozen image.
  - swift build clean; no new module; no public-surface changes.
  - Blocked-by: v6kipyy (Expand RefusalSheet to two detents)

## Phase 2 — Pipeline stage instrumentation

- [x] 3. Add pipeline.stage.end name=<X> latencyMs=N lines <!-- id:v6kipz0 -->
  - MedataCore/Sources/Pipeline/Pipeline.swift — for every stage already emitting pipelineStageLog.info event=pipeline.stage.start name=<X>, also emit pipelineStageLog.info event=pipeline.stage.end name=<X> latencyMs=N on exit (both success and refusal paths).
  - Stages: CardDetection, SupportPlane, MetricScale, Segmentation, Volume, Macros.
  - Compute ms as (ContinuousClock.now - stageStartedAt) / .milliseconds(1) or equivalent integer ms.
  - #if DEBUG-gated like the existing stage logs. Reuse pipelineStageLog.
  - swift build clean; swift test 313/313 green (3 skipped).
  - Blocked-by: v6kipyz (Freeze viewfinder during .estimating)

## Phase 3 — Re-test

- [ ] 4. STOP — human runs device capture; agent reads trail <!-- id:v6kipz1 -->
  - Agent: build for device from this worktree: cd /Users/r/repos/medata.worktrees/no-food-pixels-on-fruit-plate-mvp && xcodebuild -project MeData/MeData.xcodeproj -scheme MeData -destination id=76A45E6D-C57E-5BA6-ABAD-205C3C668572 -configuration Debug build
  - Agent: re-derive DerivedData path with xcodebuild ... -showBuildSettings | grep BUILT_PRODUCTS_DIR; print the install + launch commands for the user.
  - Console filter: subsystem:ie.medata.app category:Shutter, Include Info Messages.
  - User: install, launch, drive Single mode first (one nadir tap on a fruit plate, ~30-40 cm, tilt ≈ 0°). Then Double mode (nadir + oblique, oblique tilt 25 ± 10° — wait for the live indicator badge to be green before tapping oblique). Paste BOTH trails back into the conversation.
  - Agent: read both trails. Identify the dominant slow stage by latencyMs. Note whether Double-mode oblique at well-aimed tilt still refuses with noFoodVolumeRecovered.
  - Different-refusal rule: any failure mode other than noFoodVolumeRecovered aborts this task and is reported verbatim before any code edit.
  - Blocked-by: v6kipz0 (Add pipeline.stage.end name=<X> latencyMs=N lines)

## Phase 4 — Diagnose and apply targeted fixes

- [ ] 5. Apply one targeted latency cut to the dominant slow stage; close volume refusal if reproduced <!-- id:v6kipz2 -->
  - Read the Phase 3 trail pipeline.stage.end latencyMs=N lines. The stage with the largest latencyMs is the cut target.
  - If Segmentation dominates: target SegmenterPostProcessor.process — vectorise the per-pixel sigma_seg / perClassMeanProb loops, or eliminate intermediate copies. Aim for ≥50% cut.
  - If Volume dominates: target VoxelCarveEstimator.carve — reduce grid resolution for MVP, or short-circuit empty class slabs. Aim for ≥50% cut.
  - If CardDetection or MetricScale dominate (unlikely): investigate as a separate bug; document and stop.
  - If the dominant stage cost is intrinsic and no single targeted change cuts ≥50%: append one paragraph to decision_log.md documenting the floor and noting the Phase 3 follow-up; do NOT open-endedly optimise.
  - If well-aimed Double-mode oblique still refused with noFoodVolumeRecovered in task 4: pick one path — (a) tighten obliqueTiltOk to |Δθ − 25°| ≤ 15° with an explanatory obliqueTiltMessage (Decision 18 supersedure, log an ADR), or (b) fix the volume estimator at VoxelGridSizer.size or VoxelCarveEstimator.carve directly. Pick based on which is fewer lines for the same user outcome.
  - If well-aimed Double-mode oblique SUCCEEDED in task 4: no volume-path change. Proceed to closeout.
  - swift build clean; swift test 313/313 green (or whatever the new baseline is if a test was added).
  - Blocked-by: v6kipz1 (STOP — human runs device capture; agent reads trail)

## Phase 5 — Closeout

- [ ] 6. STOP — final on-device verification (Single + Double) <!-- id:v6kipz3 -->
  - Agent: rebuild + reinstall after task 5 fixes.
  - User: same drive as task 4 — Single mode + Double mode at well-aimed tilt. Paste both trails.
  - Success criteria (BOTH modes): event=estimate.start maskAgeMs=N with 0 ≤ N ≤ 750
  - Success criteria (BOTH modes): event=supportplane.end success=true
  - Success criteria (BOTH modes): event=estimate.end success=true mealId=… capturePath=…
  - Success criteria (BOTH modes): total estimate wall-clock ≤ 30 s
  - Success criteria (BOTH modes): ResultView renders carbs + confidence; user confirms.
  - Different-refusal rule: any failure mode aborts closeout — agent reports observed delta and waits.
  - Blocked-by: v6kipz2 (Apply one targeted latency cut to the dominant slow stage; close volume refusal if reproduced)

- [ ] 7. Atomic four-spec closeout commit <!-- id:v6kipz4 -->
  - One commit, no push, no PR.
  - This spec — append ## Verification to smolspec.md with build SHA + verbatim Single + Double success trails; tick this tasks.md tasks 1-6.
  - no-food-pixels-on-fruit-plate-mvp/ — append ## Verification to its smolspec.md with the same trails; tick tasks 8 (id:op0jbky), 9 (id:op0jbkz), 10 (id:op0jbl0); remove the BLOCKED 2026-06-16 annotation from task 8.
  - lidar-plane-fit-degenerate-on-clean-capture/ — append ### On-device observation (2026-06-XX — real-mask path) to report.md under Verification; flip Status to Fixed (real-mask path, both passes); on-device verified <date>; tick tasks 8 (id:bb3f203) and 9 (id:bb3f204).
  - shutter-blocked-feedback/ — append ### On-device observation (complete, rerun) block to decision_log.md; tick task 5 (id:f4inr0r).
  - Blocked-by: v6kipz3 (STOP — final on-device verification (Single + Double))

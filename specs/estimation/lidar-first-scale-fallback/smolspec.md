# LiDAR-First Scale Fallback

## Overview

Metric scale in the capture pipeline should come from LiDAR when LiDAR depth is present, with the card being the fallback only when LiDAR is unavailable. Before this change `Pipeline.estimate` Stage C (card detection/pose block in `MedataCore/Sources/Pipeline/Pipeline.swift`) hard-aborted the whole estimate on a card-pose-solve failure (`cardTooOblique` / `degenerateCardPose`) even when LiDAR depth was available — despite the support-plane fitter and the metric-scale resolver already supporting a LiDAR-only path. This change makes those two card-solve failures non-fatal when LiDAR depth is present, so a mis-read card no longer blocks an otherwise-valid LiDAR estimate. (Roadmap open Decision 2; aligns the pipeline with documented design §6.4.)

## Requirements

- The system MUST continue the estimate (not throw) when card-pose solving throws `cardTooOblique` or `degenerateCardPose` **and** the nadir frame has LiDAR depth (`nadir.depth != nil`), proceeding with `cardPose` treated as absent.
- The system MUST still refuse with the matching `EstimationFailure` (`.cardTooOblique` / `.degenerateCardPose`) when card-pose solving throws one of those cases **and** the nadir frame has no LiDAR depth.
- The system MUST keep mapping any *other* (unexpected) card-solve error to `EstimationFailure.degenerateCardPose` and throwing it regardless of LiDAR depth — only the two known card-pose cases fall back (fail-closed; see decision_log.md).
- The system MUST leave the no-card-detected path (corners absent) and the card-solve-success path behaviourally unchanged.
- The system SHOULD emit a DEBUG-only structured log line `event=scale.card_fallback reason=<cardTooOblique|degenerateCardPose>` on the existing `ie.medata.app` / `Shutter` channel when the fallback fires, so device trails show it occurred.

## Implementation Approach

- **File to modify:** `MedataCore/Sources/Pipeline/Pipeline.swift`, Stage C (`~L106-142`). In the `catch CardPoseError.degenerateCardPose` and `catch CardPoseError.cardTooOblique` arms, branch on `nadir.depth`: if non-nil, assign `cardPose = nil` (and emit the fallback log) instead of throwing; if nil, keep the current `throw`. Leave the generic `catch` arm throwing `degenerateCardPose` as today. `cardPose` stays a `let` — Swift permits the single assignment to occur in the `do` body or a `catch` arm.
- **Why this is sufficient (no other types change):** when `nadir.depth != nil`, `LiDARSupportPlaneFitter.fit` (`MedataCore/Sources/SupportPlane/SupportPlaneFitter.swift:36-43`) uses the LiDAR branch and ignores `cardPose`/`corners`; `MetricScaleResolver.resolve` (`MedataCore/Sources/MetricScale/MetricScaleResolver.swift:48-54`) already returns the LiDAR-only `MetricScale` (`cardScaleAvailable == false`) when `cardScaleMmPerPx == nil`. That LiDAR-only resolver branch is already unit-tested in `MetricScaleResolverTests`.
- **Pattern to follow:** existing Stage C `#if DEBUG` `logStageEnd` / signpost handling and the existing `supportPlaneLog.info("event=...")` lines (for the new fallback log).
- **Tests:** extend `MedataCore/Tests/PipelineTests/EstimationFailureTests.swift` (mirrors its `RawFrame.fixture` + `makeMinimalDepthMap()` style). Add a stub `CardDetector` returning four **collinear** corners — `PixelCorner(100,100)/(200,100)/(300,100)/(400,100)` — which deterministically make `CardPoseSolver.solve` throw `degenerateCardPose` (proven by `CardPoseSolverTests.testDegenerateCardPoseWhenAllCornersCollinear`, no helper dependencies). Drive both branches with that one fixture: (a) nadir **with** depth → must NOT throw a card `EstimationFailure`; (b) nadir **without** depth → must throw `.degenerateCardPose`. `cardTooOblique` shares the identical catch logic and stays covered at the solver level by `CardPoseSolverTests.testCardTooObliqueRefusalAtSteepAngle`.
- **Dependencies:** `CardPoseSolver`, `LiDARSupportPlaneFitter`, `MetricScaleResolver` — all existing, unchanged.
- **Out of Scope:** changing `MetricScaleResolver`, `SupportPlaneFitter`, or `EstimationFailure`; σ_scale / confidence weighting changes; handling a bad card the solver *accepts* (resolver disagreement-weighting already owns that); any two-view volume-recovery / dev-stub-mask work; UI / refusal-sheet copy.

## Risks and Assumptions

- Assumption: when `nadir.depth != nil`, the LiDAR support-plane + LiDAR-only scale path is reliable on its own (supported by the code paths above and device evidence — single mode fits cleanly at 2.85 mm). Validation: branch (a) test asserts no card-failure outcome.
- Test-reachability limit: synthetic fixtures throw downstream in Volume (`noFoodVolumeRecovered`), so the fallback test cannot reach a full `MealRecord` to assert `cardScaleAvailable == false` directly. The strongest unit assertion is "no card `EstimationFailure` thrown"; the `cardScaleAvailable == false` behaviour is guaranteed by `cardPose = nil` feeding the resolver's already-tested LiDAR-only branch.
- Risk: a degenerate/oblique card the solver *accepts* (does not throw) would still feed a bad card scale — out of scope; the resolver's card/LiDAR disagreement weighting handles it.

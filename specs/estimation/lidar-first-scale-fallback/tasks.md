---
references:
    - specs/estimation/lidar-first-scale-fallback/smolspec.md
    - specs/estimation/lidar-first-scale-fallback/decision_log.md
---
# LiDAR-First Scale Fallback

- [x] 1. Card-solve failure falls back to LiDAR scale when nadir depth is present <!-- id:v7wlgt2 -->
  - In Pipeline.estimate Stage C, CardPoseError.cardTooOblique / .degenerateCardPose no longer abort the estimate when nadir.depth != nil: cardPose is treated as absent and the pipeline proceeds on LiDAR scale + support plane.
  - With no LiDAR depth, the same matching EstimationFailure is still thrown.
  - Generic (unexpected) card-solve errors keep throwing regardless of depth (fail-closed, decision_log Decision 2).
  - DEBUG-only event=scale.card_fallback reason=<case> emitted when the fallback fires.
  - Success: builds clean; no-card and card-success paths behaviourally unchanged.
  - References: smolspec.md, decision_log.md

- [x] 2. Regression test: card-solve failure with LiDAR depth does not throw a card EstimationFailure <!-- id:v7wlgt3 -->
  - Stub CardDetector returns four collinear corners (100,100)/(200,100)/(300,100)/(400,100) which deterministically make CardPoseSolver.solve throw degenerateCardPose.
  - Nadir frame carries depth (makeMinimalDepthMap); Pipeline.estimate must NOT throw .degenerateCardPose or .cardTooOblique (downstream synthetic refusals acceptable).
  - Success: test passes; fails if the fallback branch is removed.
  - Blocked-by: v7wlgt2 (Card-solve failure falls back to LiDAR scale when nadir depth is present)
  - References: smolspec.md

- [x] 3. Regression test: card-solve failure without LiDAR depth still refuses with .degenerateCardPose <!-- id:v7wlgt4 -->
  - Same collinear-corner stub CardDetector, nadir frame with no depth.
  - Pipeline.estimate must throw EstimationFailure.degenerateCardPose, proving the no-LiDAR refuse path is preserved.
  - Success: test passes; fails if the fallback fires unconditionally.
  - Blocked-by: v7wlgt2 (Card-solve failure falls back to LiDAR scale when nadir depth is present)
  - References: smolspec.md

- [x] 4. Full MedataCore test suite passes clean <!-- id:v7wlgt5 -->
  - Build MedataCore and run the test suite (swift test or the project Makefile target).
  - New tests pass; no existing Pipeline / MetricScale / CardDetection test regresses.
  - Success: zero test failures, clean build.
  - Blocked-by: v7wlgt3 (Regression test: card-solve failure with LiDAR depth does not throw a card EstimationFailure), v7wlgt4 (Regression test: card-solve failure without LiDAR depth still refuses with .degenerateCardPose)
  - References: smolspec.md

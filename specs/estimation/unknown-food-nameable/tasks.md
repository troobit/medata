---
references:
    - specs/estimation/unknown-food-nameable/smolspec.md
    - specs/estimation/unknown-food-nameable/decision_log.md
---
# Unknown Food Nameable — Tasks

## Pipeline

- [ ] 1. An all-unknown argmax passes the plane-fitter and coverage gates on both capture paths (Req 1, 2) <!-- id:tiv69rm -->
  - Add the volumetric predicate (food, liquid, unknown) to ClassPalette and use it in both mask builders (PreShutterSegmenter, PipelineBridges), foodCoverageFraction, and MaskMatcher/VoxelCarve class filters; remove enforceRecognisedFoodDominance and its constants; keep the unrecognisedFood case, nothing throws it.
  - Verify: MedataCore tests for an all-unknown argmax — coverage fraction counts it, minimum-coverage gate accepts it, PipelineBridges.foodMask has 1-bits; existing tests asserting unrecognisedFood are rewritten; make test green (both totals).
  - Stream: 1

- [ ] 2. Sliver classes are absorbed into their bordering class before volume, deterministically, with fraction 0 as passthrough (Req 10) <!-- id:tiv69rn -->
  - Second rule in regulariseLabelMap driven by a per-class histogram and a sliverFraction (start 0.10) on MaskRegularisationConfig; per class not per component; only food-like classes can be slivers; absorb into dominant bordering non-sliver class read from original labels, ties to lowest id; components bordered only by slivers unchanged.
  - Verify: unit tests — small named component on a larger unknown region absorbed; small unknown fringe on rice joins rice; a class large in total but split into many small pieces kept; two adjacent slivers with no other border unchanged; fraction 0 byte-identical to today; standard config unchanged for the existing speckle tests.
  - Stream: 2

- [ ] 3. The shipped sliver fraction is the largest of 0, 0.05, 0.10 that keeps N5k mean food-class IoU from falling and carb MAE from rising, recorded in the decision log <!-- id:tiv69ro -->
  - Confirm SegBench.sample and FixtureRunner run the regularisation pass on stored probabilities (route them through it if not, so the measurement exercises the rule). Run HarnessCLI seg-bench and make harness-accuracy over tmp/n5k_fixtures at each fraction; spot-check the five bundles in tmp/device_captures.
  - Verify: a table of mIoU and carb MAE per fraction appended to Decision 3; MaskRegularisationConfig.standard carries the chosen value; make test green.
  - Blocked-by: tiv69rn (Sliver classes are absorbed into their bordering class before volume, deterministically, with fraction 0 as passthrough Req 10)
  - Stream: 2

- [ ] 4. Both volume estimators integrate unknown pixels as their own class and the record carries a pre-β volume under unknown_food (Req 3) <!-- id:tiv69rp -->
  - HeightFieldEstimator and VoxelCarveEstimator use the volumetric predicate; confirm the β application tolerates a class with no BetaCorrection entry (unity, uncalibratedUnity) and fix if it throws; occlusion detector stays solid-only.
  - Verify: MedataCore tests — a height-field run over an unknown-only argmax yields a positive volume keyed unknown_food and perClassVolumesPreBetaCm3 round-trips through MealRecord; make test green.
  - Blocked-by: tiv69rm (An all-unknown argmax passes the plane-fitter and coverage gates on both capture paths Req 1, 2)
  - Stream: 1

- [ ] 5. Macros emits an Unknown food row with volume, zero macros, unity β and uncalibratedUnity status, persisted like any other row (Req 4) <!-- id:tiv69rq -->
  - One branch in Macros.compute for classId unknown_food; no food database row; sources marked unknown.
  - Verify: unit test on Macros.compute with an unknown_food volume; a pipeline-level test shows the row in the record and a zero contribution to the total.
  - Blocked-by: tiv69rp (Both volume estimators integrate unknown pixels as their own class and the record carries a pre-β volume under unknown_food Req 3)
  - Stream: 1

## App

- [ ] 6. Review shows the Unknown food row with its outline, cm³ and no amount controls; relabel from the eligible list derives real mass and macros; reject ignores it; recording unnamed succeeds at 0 g with the accessory line; history relabel works (Req 5–9) <!-- id:tiv69rr -->
  - Row arrives from record.macros.perClass; one conditional hides serving/gram controls and shows cm³ while classId is unknown_food; eligible list already excludes unknown; accessory line already reads presentClassIds.
  - Verify: Debug build warning-free via make deploy-device; Settings → Debug worst-case seed extended (or a new seed) to include an unknown row so the surface can be checked without a Release capture; relabel to bread_wholemeal shows a non-zero carb figure; reject removes it; Record with it unnamed lands in Records at 0 g with the accessory line.
  - Blocked-by: tiv69rq (Macros emits an Unknown food row with volume, zero macros, unity β and uncalibratedUnity status, persisted like any other row Req 4)
  - Stream: 1

- [ ] 7. The shutter stays disarmed while the live mask has no food-like pixels and the blocked-shutter chip reads No food in view (Req 11) <!-- id:tiv69rs -->
  - PreShutterSegmenter publishes the 1-bit count with the mask; CaptureFlowModel.hasUsablePreShutterMask requires it to be positive; chip text added to the existing blocked-gate copy.
  - Verify: CaptureFlowModel gating test with an all-zero mask keeps canShutter false and names the gate; Debug build warning-free.
  - Blocked-by: tiv69rm (An all-unknown argmax passes the plane-fitter and coverage gates on both capture paths Req 1, 2)
  - Stream: 2

- [ ] 8. Release build on device estimates the sesame roll: outline shown, relabelled to bread, recorded; then the field note and prerequisites are updated <!-- id:tiv69rt -->
  - make deploy-release; capture the roll single-view and two-view; expect estimate.end success=true and the review surface with an Unknown food row; relabel and record; pull the log and one bundle.
  - Verify: log trail and the record row cited in docs/agent-notes/field-truth-sessions.md under the 2026-09-23 entry; make spell; both make test totals reported.
  - Blocked-by: tiv69ro (The shipped sliver fraction is the largest of 0, 0.05, 0.10 that keeps N5k mean food-class IoU from falling and carb MAE from rising, recorded in the decision log), tiv69rr (Review shows the Unknown food row with its outline, cm³ and no amount controls; relabel from the eligible list derives real mass and macros; reject ignores it; recording unnamed succeeds at 0 g with the accessory line; history relabel works Req 5–9), tiv69rs (The shutter stays disarmed while the live mask has no food-like pixels and the blocked-shutter chip reads No food in view Req 11)
  - Stream: 1

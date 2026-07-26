# Bugfix Report: Unrecognised Food Estimated from a Residual Sliver

**Date:** 2026-07-26
**Status:** Fixed

## Description of the Issue

A plate of raw pumpkin chunks (an out-of-palette food) produced four estimation
attempts on device (2026-07-26, model `coreml_ab812dc3aa9d`, palette v2):

1. Single-view LiDAR — refused `noFoodVolumeRecovered` (a 0.8 % `egg` sliver
   carved to 0 cm³).
2. Two single-view LiDAR retries — refused `noFoodPixels` ("no food" copy),
   despite the segmenter labelling ~11 % of the frame as food.
3. Two-view + card — **succeeded** as "cheese, 18.4 cm³, 20 g" from a 0.21 %
   `cheese` sliver, while 10.2 % of the frame was labelled `unknown_food`.

**Reproduction steps:**
1. Plate an out-of-palette food (pumpkin) and capture in single-view LiDAR
   mode → misleading "no food"/"no volume" refusals.
2. Capture the same plate in two-view + card mode → confident wrong-class
   estimate ("cheese").
3. Device evidence: capture bundles `1785050832559/835690/838857-refused` and
   `1785050864428-success`, outcome rows in `estimation_outcomes` at the same
   timestamps.

**Impact:** Any food the segmenter cannot name (out-of-palette, or
underrepresented classes falling into `unknown_food`) either blocks LiDAR
capture with wrong copy or, worse, produces a confidently wrong class and carb
number. For a carb-estimation tool this is the worst failure shape: a wrong
answer presented as a right one.

## Investigation Summary

- **Symptoms examined:** `estimation_outcomes` rows (failure JSON + stage
  measurements) pulled from the device store; all four capture bundles pulled
  via `devicectl` and their argmax masks histogrammed offline.
- **Code inspected:** `FoodRegionCoverage.swift` (fail-closed coverage gate),
  `Pipeline.swift` stage F/G, `HeightFieldEstimator`/`VoxelCarveEstimator`
  integration predicates, `ClassPalette` predicate contract,
  `class_mapping_foodseg103_v1.json` / `class_mapping_foodrec2022_v1.json`.
- **Hypotheses tested and ruled out:**
  - *Geometry/LiDAR failure* — ruled out: plane fit had 73 338 inliers at
    1.19 mm residual; scale resolved `card+lidar`.
  - *Stride/runtime bug (July precedent)* — ruled out: masks are coherent
    (one contiguous unknown_food region over the pumpkin), not sheared.
  - *Palette omission of pumpkin from training* — partially ruled out:
    pumpkin maps to `mixed_vegetables` (index 23) in both corpora, so the
    model *should* have named it; it emitted `unknown_food` instead (a model
    quality gap on a heterogeneous catch-all class, top-down, dim light).

## Discovered Root Cause

The pipeline has no handling for a **dominant `unknown_food` region**. The
sentinel is excluded from every recognised-food predicate (`isFoodClass` /
`isLiquidClass`), so:

- `enforceMinimumFoodCoverage` sees ~0 % recognised food and refuses
  `noFoodPixels` — factually wrong copy ("Show the meal clearly") when the
  model *did* see food it could not name.
- When a residual recognised sliver clears the 0.1 % floor, the volume→β→carbs
  chain runs on the sliver alone and reports it as the whole meal
  ("cheese"), with no signal that 98 % of the food-like area was dropped.

**Defect type:** Missing validation (unhandled dominant-sentinel state).

**Why it occurred:** The `unknown_food` channel was designed as a training
label; the runtime only ever used it as "not volume-eligible". No spec
requirement covered the case where it dominates the mask.

**Contributing factors:** The palette-v2 model (`ab812dc3aa9d`) places
out-of-palette and weakly-learned foods into `unknown_food` more readily than
the previous model; first field session after promotion surfaced the gap.

## Resolution for the Issue

**Changes made:**
- `MedataCore/Sources/Pipeline/EstimationFailure.swift` — new case
  `unrecognisedFood`.
- `MedataCore/Sources/Pipeline/FoodRegionCoverage.swift` — new fail-closed
  gate `enforceRecognisedFoodDominance(argmax:palette:)`: refuses
  `unrecognisedFood` when the `unknown_food` fraction is ≥ 1 % of the frame
  AND strictly greater than 4× the recognised food+liquid fraction.
- `MedataCore/Sources/Pipeline/Pipeline.swift` — the gate runs on the nadir
  argmax immediately before `enforceMinimumFoodCoverage`, so the
  unknown-dominant case wins over `noFoodPixels` on both capture paths.
- `MedataCore/Sources/Pipeline/PipelineDiagnostics.swift` — outcome-store
  encoding for the new case (`{"domain":"estimation","case":"unrecognisedFood"}`).
- `App/CaptureErrorOverlay.swift` — chip "unknown food", hint "MeData can't
  name this food yet".

**Approach rationale:** The model behaved as designed (out-of-palette food →
`unknown_food`); the defect is the product's silence about it. An honest
refusal is strictly better than a confident wrong class for a carb estimator,
and the gate is deterministic, offline, and cheap (one pass over the argmax).

**Alternatives considered:**
- *Estimate the sliver but flag low confidence* — rejected: σ_seg already read
  0.53 on the cheese estimate and the number still presented as an answer;
  a 100× mass under-read with the wrong class name is not salvageable by a
  confidence pill.
- *Count `unknown_food` towards volume with a generic density/β* — rejected:
  no defensible carb coefficient exists for an unnamed food; fabricating one
  violates the honest-refusal principle.
- *Block the shutter pre-capture instead* — rejected: the pre-shutter mask
  counts unknown_food as food (it is food), and arming then refusing with an
  actionable message gives the user an explanation rather than a dead shutter.

## Regression Test

**Test file:** `MedataCore/Tests/PipelineTests/FoodRegionCoverageTests.swift`
**Test suite:** `RecognisedFoodDominanceGateTests` (7 cases)

**What it verifies:** dominant-unknown-with-sliver refuses (the two-view
capture in miniature); unknown-only refuses `unrecognisedFood` (the LiDAR
captures); recognised meals with speckle accept; even splits accept; the 1 %
floor defers to `noFoodPixels`; the exact 4× boundary accepts; recognised
liquids count as recognised.

**Run command:** `make test`

## Affected Files

| File | Change |
|------|--------|
| `MedataCore/Sources/Pipeline/EstimationFailure.swift` | new `unrecognisedFood` case |
| `MedataCore/Sources/Pipeline/FoodRegionCoverage.swift` | dominance gate + constants |
| `MedataCore/Sources/Pipeline/Pipeline.swift` | gate call before min-coverage gate |
| `MedataCore/Sources/Pipeline/PipelineDiagnostics.swift` | failure encoding |
| `App/CaptureErrorOverlay.swift` | chip/hint copy for the new case |
| `MedataCore/Tests/PipelineTests/FoodRegionCoverageTests.swift` | regression suite |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (`make test`, both totals)
- [x] `make spell` passes

**Manual verification:**
- Offline replay of the four device capture bundles' argmax histograms against
  the gate predicate: all three refused attempts and the "cheese" success
  refuse `unrecognisedFood`; the 2026-07-25 `single_view_lidar` success
  (beef/bread/pork, no unknown dominance) still accepts.

## Prevention

**Recommendations to avoid similar bugs:**
- Sentinel channels that the model can emit must have an explicit runtime
  disposition (estimate / refuse / surface), not just exclusion from
  predicates.
- Field-session triage should start from the outcome store + capture bundles
  (this investigation went device DB → fixtures → offline histogram without a
  single re-capture).
- Model-side follow-up (separate lane): pumpkin/mixed_vegetables is
  undertrained — the class maps exist but the model emits `unknown_food`;
  candidate for the myfoodrepo-bridge data work alongside the cereal class.

## Related

- `specs/bugfixes/segmenter-output-stride-ignored/` — the diagnosis recipe
  (bundle pull + offline histogram) reused here.
- `docs/agent-notes/model-production.md` — palette-v2 promotion context.
- Estimation-runtime-consistency spec — the sibling fail-closed gate this one
  extends.

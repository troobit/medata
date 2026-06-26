# Minimum Viable Volume Estimator

## Overview

The two-view capture → volume → carb-estimate flow currently refuses with `noFoodVolumeRecovered` on the device because both volume estimators carve/integrate strictly over the per-class segmentation argmax, and the Phase-1 device build runs the dev-stub segmenter (`DEV_STUB_SEGMENTER` / `StubInferenceEngine`) whose per-class masks are unusable — no valid food class survives. This change decouples the volume path from the per-class segmenter for the MVP: when the dev-stub is active, the food region is taken from the coarse binary `CaptureResult.preShutterFoodMask`, the recovered volume is attributed to a single default food class, and the flow completes with a rough (low-confidence) carb number instead of refusing. Per-class accuracy is deferred to the real CoreML segmenter (Track 3). Target audience is TestFlight, not the App Store.

## Requirements

- The system MUST, when the active segmenter is the dev-stub (`segmenterSource == "dev_stub"`), derive the two-view SfS food region from `CaptureResult.preShutterFoodMask` rather than the per-class segmentation argmax.
- The system MUST attribute the recovered total volume to a single default food class so that `Macros.compute` produces a carbohydrate value.
- The system MUST allow a normal two-view capture (nadir + well-aimed ~25° oblique) over a non-trivial `preShutterFoodMask` region to complete to `event=estimate.end success=true`, present a result, and persist the meal — i.e. MUST NOT refuse `noFoodVolumeRecovered` in that case.
- The system MUST still refuse cleanly (`noFoodPixels` / `noFoodVolumeRecovered`) when `preShutterFoodMask` is nil or covers a negligible region — it MUST NOT fabricate a volume from nothing.
- The system MUST flag the resulting estimate as degraded/low-confidence (reduced σ) to reflect the single-default-class approximation.
- The system MUST restore the per-class volume path automatically when `segmenterSource` is a real CoreML model — the fallback is gated, not a replacement.
- The system SHOULD record the chosen default class and density as a decision so the value is auditable.
- The system MAY extend the same fallback to the single-view LiDAR height-field path (two-view is the v0 priority).

## Implementation Approach

- **Gate** the fallback on the active segmenter being the dev-stub. `PipelineFactory.segmenterSourceTag` already returns `"dev_stub"` under `DEV_STUB_SEGMENTER`; thread that into `Pipeline` at construction so the volume stage can branch on it.
- **`MedataCore/Sources/Pipeline/Pipeline.swift`** — in the `.twoViewSfS` volume branch (currently builds `foodMask = PipelineBridges.foodMask(from: nadirSeg.argmax)` and per-class matched sets around lines 322–336): when the fallback is active and `captureResult.preShutterFoodMask` is non-nil, size the `VoxelGrid` from that binary mask (`VoxelGridSizer.Inputs.foodMask` already accepts a `BinaryMask`) and run the carve with a synthetic single-class labelling — `matchedClasses = {defaultClassId}` — so `VoxelCarveEstimator` returns one total volume. The estimators are not modified.
- **Default class + density** — attribute the total to one default food class with a representative density/carb coefficient so `Macros.compute` yields a number. The exact class and density are fixed in `decision_log.md`; if the chosen class lacks a `FoodDatabase` entry, add a minimal one or a constant fallback density in the volume→macros bridge.
- **Confidence** — stamp a low σ for the fallback path (the existing `Confidence` combine already floors/limits σ; set the geometry/segmentation sub-factor to a degraded value when the fallback is used) so the rough estimate reads as low-confidence.
- **Patterns to leverage:** `CaptureResult.preShutterFoodMask` is already plumbed and consumed by `fitSupportPlane` (`Pipeline.swift:156/177`); `PipelineBridges.foodMask(from:palette:)` shows how a `BinaryMask` is built from an argmax.
- **Out of scope:** training/integrating the real CoreML segmenter (Track 3); per-class accuracy; the research §16 sub-second performance budget; App Store release plumbing; review/retake UX. The single-view height-field path is not required (MAY only).

## Risks and Assumptions

- **Risk:** a poorly chosen default density mis-scales carbs. **Mitigation:** pick a mid-range mixed-food density + carb coefficient, fix it in `decision_log.md`, and flag the estimate low-confidence; accuracy is Track 3's job, not this spec's.
- **Risk:** the synthetic single-class carve silently swallows a genuinely empty capture. **Mitigation:** the negligible-mask refusal requirement above — keep a minimum food-region area/volume threshold below which the path still refuses.
- **Assumption:** `preShutterFoodMask` is populated on the device path (the support-plane fitter already relies on it today).
- **Prerequisite:** the two-view path must actually reach the volume stage — the recurring `lidarFitDegenerate` support-plane refusal (Track 1, `lidar-plane-fit-degenerate-on-clean-capture`) must be resolved first, or the flow refuses before volume runs.
- **Continuity:** this degrades from the full per-class design in `specs/estimation/pipeline/` (§ Volume Estimation, tasks 24–34) and absorbs the volume half of `specs/bugfixes/closeout-trail-mvp-cleanup/` Phase 4 option (b) for MVP purposes.

# Pipeline Real-Device Correctness — Requirements

**Version:** 0.3
**Date:** 2026-06-13
**Status:** Implemented (tasks 1–16 landed; see `design.md` status note). Caveat: the Req 6.1/6.2 baseline-delta numbers were never formally recorded — budgets were sanity-checked on device, not measured against a pre-spec baseline. Two-view-path end-to-end on-device verification remains open (GAPS Group D).
**Branch:** mvp-refine

## Introduction

This spec lifts three Phase-1 stop-gaps that currently let the on-device pipeline reach `event=estimate.end` only by approximation: the all-ones / centred-rectangle food-region mask used by the LiDAR support-plane fit, the whole-frame LiDAR coverage value wired into `LiDARStatus.foodRegionCoveragePercent`, and the `NullCardDetector` returning `nil` for every nadir frame. The MVP fruit-plate capture on iPhone 13 Pro Max iOS 26.5 needs real food-region signals to pin a numerically correct plane fit, an honest auto-path coverage value (even if the user toggle remains authoritative in v1), and a working card-only fallback. All three are unblocked by adding a throttled pre-shutter segmentation pass that feeds the in-shutter pipeline rather than by reordering the in-shutter stages themselves.

## Non-Goals

- Re-enabling automatic capture-path selection. Decision 35 keeps the user `CaptureMode` toggle authoritative in v1; `selectCapturePath` and the `AUTO_CAPTURE_MODE` flag stay behind their compile gate.
- New live-indicator state for "no food detected". Empty / degenerate masks surface via the existing refusal-modal path; no extra UI ships in this spec.
- New refusal copy or new `EstimationFailure` cases. Empty masks reuse `EstimationFailure.noFoodPixels` or `.lidarFitDegenerate`.
- Replacing the in-shutter segmentation stage. Phase 1 keeps the in-shutter pass at 1920×1440 against the dev-stub engine; this spec adds a separate pre-shutter pass.
- Training / shipping the production Core ML segmenter. Phase 3 owns model rollout (per `specs/estimation/pipeline/` Decision 42). The pre-shutter pass must work against whichever engine `PipelineFactory.makeForDevice` wires.
- Removing `NullCardDetector` from the test surface. Tests inject mock `CardDetector` conformances; the production swap is the App-target Vision implementation.
- Card detection used as a pre-shutter gate or surfaced in a live badge. Detection runs at shutter time only.

## Requirements

### 1. Pre-Shutter Food-Region Mask Production

**User Story:** As the capture flow, I want a fresh food-region mask available at shutter-tap time, so that `Pipeline.fitSupportPlane` receives a real spatial prior instead of the centred-rectangle approximation.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL produce a `BinaryMask` at the nadir frame's native resolution (`imageWidth × imageHeight`) whose `1` pixels mark the food region recognised by the segmenter palette in use.
2. <a name="1.2"></a>The system SHALL provide a mask whose latest update is no older than 750 ms relative to the shutter-tap instant; an older mask SHALL be treated as unavailable for the purposes of [3.2](#3.2). The staleness ceiling is strictly greater than the cadence period in [1.3](#1.3) so cadence jitter does not trip the unavailable path.
3. <a name="1.3"></a>The pre-shutter mask production SHALL run at ≥ 2 Hz on iPhone 13 Pro Max iOS 26.5 throughout the time the capture flow is in `ready`, `initialising`, `trackingLost`, or `armed` state.
4. <a name="1.4"></a>The pre-shutter mask production SHALL halt while the capture flow is in any of `capturing`, `estimating`, `result`, or `refused` state and SHALL resume on return to `ready`.
5. <a name="1.5"></a>The pre-shutter mask production SHALL function when `PipelineFactory.makeForDevice` is built with `DEV_STUB_SEGMENTER` undefined (Core ML engine). When `DEV_STUB_SEGMENTER` is defined, `StubInferenceEngine` SHALL return a deterministic centred-ellipse food region covering 30 ± 2 % of the input image area so the pre-shutter pass produces a non-trivial, OOM-bounded mask under Phase 1 dev builds.
6. <a name="1.6"></a>The pre-shutter mask production SHALL NOT prevent or starve the live indicator stream (`LiveSampleObserver`) from updating tilt / distance / LiDAR-coverage indicators at their current cadence.
7. <a name="1.7"></a>The pre-shutter producer SHALL publish its latest mask using a latest-wins discipline: an in-flight inference task SHALL be cancelled when the capture flow transitions out of a producing state ([1.3](#1.3)), and a fresh task SHALL NOT begin until the previous task's cancellation completes. Concurrent shutter-tap consumers SHALL always observe the most recently completed mask.

### 2. LiDAR Support-Plane Fit Consumes the Real Mask

**User Story:** As the LiDAR support-plane fitter, I want the food-region mask produced upstream, so that the lower-edge scan band lands on the table around the real food silhouette rather than around a centred rectangle.

**Acceptance Criteria:**

1. <a name="2.1"></a>`Pipeline.fitSupportPlane` SHALL accept the pre-shutter food-region mask via `CaptureResult` (or an equivalent shutter-time input) and pass it through to `LiDARPlaneFitter.Inputs.foodRegionMask` without constructing a centred-rectangle replacement.
2. <a name="2.2"></a>`MedataCore/Sources/Pipeline/CentreRectangleMask.swift` and the `centreRectangleFillFraction` constant SHALL be deleted once [2.1](#2.1) is in place.
3. <a name="2.3"></a>The candidate-point count produced inside `LiDARPlaneFitter.fit` on the iPhone 13 Pro Max 1920×1440 fruit-plate fixture SHALL be at most 250 000 (the literal ceiling matches the 236 752-candidate measurement at `fillFraction = 0.7` recorded in the 2026-06-13 device log, with margin), preserving the OOM invariant from `lidar-plane-fit-oom-on-device-1920x1440` Decision 1 without referencing deleted code.
4. <a name="2.4"></a>`event=supportplane.start` SHALL log mask provenance (`source=pre_shutter` / `source=centre_rectangle` for any compile-time fallback) alongside the existing width / height fields, so an on-device trace identifies which mask reached the fitter.

### 3. Empty or Stale Mask Handling

**User Story:** As the capture flow, I want unfit pre-shutter masks to surface as ordinary estimation failures, so that the MVP does not ship new UI before the core flow is proven.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN the pre-shutter mask is empty (zero `1` pixels) at shutter-tap, the pipeline SHALL throw `EstimationFailure.noFoodPixels`.
2. <a name="3.2"></a>WHEN no pre-shutter mask is available (production hasn't produced one yet, or the most recent mask is older than 750 ms per [1.2](#1.2)), the pipeline SHALL throw `EstimationFailure.noFoodPixels`.
3. <a name="3.3"></a>The capture flow SHALL NOT introduce a new live-indicator state, badge, refusal-modal copy, or `EstimationFailure` case to surface either condition.

### 4. Honest `foodRegionCoveragePercent` Signal

**User Story:** As the capture-path dispatcher, I want LiDAR coverage measured on the real food region, so that the value can drive auto-selection (where enabled) without lying about coverage outside the plate.

**Acceptance Criteria:**

1. <a name="4.1"></a>`LiDARStatus.foodRegionCoveragePercent` populated at shutter time SHALL be the percentage of mask `1` pixels (from [1.1](#1.1)) whose corresponding LiDAR confidence value meets `LiveSampleMath.confidenceThreshold` (currently 0.66).
2. <a name="4.2"></a>The value SHALL be 0 when no pre-shutter mask is available or the mask is empty.
3. <a name="4.3"></a>The whole-frame `liveLiDARCoveragePercent` already exposed on `LiveIndicatorBadge` SHALL remain unchanged for the live indicator (it serves the indicator's UX, not the path-decision signal).
4. <a name="4.4"></a>`selectCapturePath` SHALL be invoked only from code paths gated by `#if AUTO_CAPTURE_MODE`; the production app continues to honour the user's `CaptureMode` toggle.
5. <a name="4.5"></a>`event=estimate.end` SHALL log the food-region coverage value alongside the existing `success`/`failure` fields so the corrected signal is captured in device traces. (Erratum from v0.1: originally specified at `estimate.start`, but the value cannot exist there because it is computed inside `Pipeline.estimate` after `fitSupportPlane` returns. See Decision 15.)

### 5. Vision-Backed `CardDetector`

**User Story:** As the pipeline, I want a real card detector on nadir captures, so that the card-only fallback can recover metric scale when LiDAR is unavailable or degraded.

**Acceptance Criteria:**

1. <a name="5.1"></a>The App target SHALL provide a concrete `CardDetector` conformance (in a new file) that uses the system Vision framework to detect a single ISO/IEC 7810 ID-1 rectangle and return its four `PixelCorner`s in the canonical TL→TR→BR→BL order documented for `CardPoseSolver.solve`, expressed in `RawFrame` pixel coordinates (origin at top-left, +x right, +y down).
2. <a name="5.2"></a>`PipelineFactory.makeForDevice` SHALL wire this implementation into `Pipeline.init(cardDetector:…)`; `NullCardDetector` SHALL be removed from production builds.
3. <a name="5.3"></a>The detector SHALL run unconditionally on every nadir frame reaching the pipeline; the pipeline's existing LiDAR-takes-precedence branch ([Pipeline.swift:393](MedataCore/Sources/Pipeline/Pipeline.swift)) SHALL be unchanged so a healthy LiDAR fit continues to ignore the returned `CardPose`.
4. <a name="5.4"></a>WHEN no card is detected in the nadir frame, the detector SHALL return `nil` and the pipeline SHALL fall back to its existing `noScaleAvailable` path if LiDAR is also unavailable.
5. <a name="5.5"></a>WHEN the detector returns corners that `CardPoseSolver.solve` cannot accept, the existing `degenerateCardPose` / `cardTooOblique` mappings SHALL apply unchanged.
6. <a name="5.6"></a>The card detector SHALL complete within 250 ms (warm) on iPhone 13 Pro Max iOS 26.5 on a 1920×1440 nadir frame.
7. <a name="5.7"></a>The capture flow SHALL pre-warm the underlying Vision `VNDetectRectanglesRequest` (or equivalent) once on entry to `ready` state so the first shutter-tap of a session pays warm-path latency only. The warmup SHALL be cancellable and SHALL NOT block the live indicator stream.

### 6. Memory and Performance Invariants

**User Story:** As the device user, I want the new pre-shutter and card-detection work to keep the app within its existing memory and frame-rate envelope, so that the MVP capture does not regress on iPhone 13 Pro Max.

**Acceptance Criteria:**

1. <a name="6.1"></a>The pre-shutter segmentation pass SHALL not increase peak resident memory of the App process by more than 50 MB beyond a numeric baseline captured during the design phase under the fruit-plate capture flow on iPhone 13 Pro Max iOS 26.5. The design document SHALL record the captured baseline MB value before tasks begin.
2. <a name="6.2"></a>The shutter-tap to `event=estimate.start` latency SHALL not regress by more than 100 ms compared with a numeric baseline captured during the design phase. The design document SHALL record the captured baseline ms value before tasks begin.
3. <a name="6.3"></a>`LiDARPlaneFitter.refine` SHALL continue to operate within the bounded-inlier envelope established by `lidar-plane-fit-oom-on-device-1920x1440` Decision 1; the candidate-point ceiling in [2.3](#2.3) is the operative invariant.

### 7. Logging and Diagnostics

**User Story:** As the developer triaging on-device captures, I want the new stages to emit structured Logger events on the existing `ie.medata.app` / `Shutter` channel, so that Console traces continue to tell the full shutter→result story.

**Acceptance Criteria:**

1. <a name="7.1"></a>WHEN the pre-shutter pass produces a mask, a Debug-build Logger line SHALL fire with `event=preshutter.mask.update foodPixels=… ageMs=… source=…` (`source` matches the value used in [2.4](#2.4): `pre_shutter_coreml`, `pre_shutter_stub`, etc.) so cadence, freshness, and engine provenance are observable in Console.
2. <a name="7.2"></a>WHEN the shutter fires, a Debug-build Logger line SHALL include the mask age and food-region coverage value in the existing `event=estimate.start` payload.
3. <a name="7.3"></a>WHEN the card detector completes, a Debug-build Logger line SHALL fire with `event=carddetect.end success=… cornerCount=… latencyMs=…`.
4. <a name="7.4"></a>All new log statements SHALL be `#if DEBUG`-gated to match the existing pattern in `Pipeline.swift`; no new statements SHALL appear in Release builds.

### 8. Regression Tests

**User Story:** As the maintainer, I want regression tests covering each deliverable, so that future changes to capture / pipeline don't re-introduce the stop-gaps.

**Acceptance Criteria:**

1. <a name="8.1"></a>A Swift Testing case SHALL pass the pre-shutter mask through `LiDARPlaneFitter.fit` on the synthetic fruit-plate fixture and assert a finite gravity-aligned plane with `residualMm < LiDARPlaneFitter.residualMaxMm`.
2. <a name="8.2"></a>A Swift Testing case SHALL assert that an empty pre-shutter mask reaching `Pipeline.estimate` throws `EstimationFailure.noFoodPixels`.
3. <a name="8.3"></a>A Swift Testing case SHALL assert that a mask older than 750 ms is treated as unavailable per [3.2](#3.2).
4. <a name="8.4"></a>A Swift Testing case SHALL pass a `LiDARStatus` constructed with a food-region mask of area ≥ 10 000 pixels and a synthesized depth confidence buffer through the coverage computation and assert the percentage matches the masked count divided by mask-area, ±1 %. The ≥ 10 000-pixel floor makes the percentage tolerance meaningful; smaller-mask behaviour is governed by [4.2](#4.2).
5. <a name="8.5"></a>A Swift Testing case SHALL construct a synthetic ID-1 rectangle in a 1920×1440 BGRA buffer and assert the Vision card detector returns four corners in TL→TR→BR→BL order, in `RawFrame` pixel coordinates per [5.1](#5.1).
6. <a name="8.6"></a>The existing `SupportPlaneRoughMaskTests` all-ones-mask sentinel SHALL continue to pass after `CentreRectangleMask.swift` is deleted (it stays as a regression sentinel against any future placeholder mask).
7. <a name="8.7"></a>An integration test SHALL drive `CaptureFlowModel` from `ready` through a simulated shutter-tap with a probe `LiDARPlaneFitter` (or equivalent test double in `Pipeline.fitSupportPlane`) and assert that the mask reaching `LiDARPlaneFitter.Inputs.foodRegionMask` is byte-identical to the most recent mask produced by the pre-shutter pass. This catches a regression in which a correctly computed mask is silently replaced before it reaches the fitter.

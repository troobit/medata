# Decision Log: Minimum Viable Volume Estimator

## Decision 1: Gate the fallback on the dev-stub segmenter

**Date**: 2026-06-22
**Status**: accepted

### Context

The volume estimators only produce a result over per-class segmentation output. The Phase-1 device build runs the dev-stub segmenter, whose per-class masks are unusable, so the volume path refuses `noFoodVolumeRecovered`. We need a fallback for the MVP without disturbing the real (per-class) path that lands with the Track-3 CoreML model.

### Decision

Activate the minimum-viable fallback only when the active segmenter source is the dev-stub (`PipelineFactory.segmenterSourceTag == "dev_stub"`), threaded into `Pipeline` at construction. When a real CoreML segmenter is active, the per-class path runs unchanged.

### Rationale

A single gate keyed off the already-stamped `segmenterSource` tag means the fallback disappears automatically once the real model lands — no later removal step, and no risk of shipping the degraded path to App Store builds (which are not `dev_stub`).

### Alternatives Considered

- **Always-on heuristic (detect garbage masks at runtime)**: Rejected — fragile, and would also degrade the real-model path.
- **Build-flag separate from `DEV_STUB_SEGMENTER`**: Rejected — duplicates an existing signal; `segmenterSourceTag` already distinguishes the two builds.

### Consequences

**Positive:** Self-retiring; zero impact on the real-model path; matches the existing Phase-1/Phase-3 split.
**Negative:** The fallback is only exercised in dev-stub builds, so it needs explicit device verification before it is trusted.

---

## Decision 2: Source the food region from `preShutterFoodMask` via a synthetic single-class carve

**Date**: 2026-06-22
**Status**: accepted

### Context

`VoxelCarveEstimator` and `VoxelGridSizer` carve over food classes derived from the segmentation argmax. We want a total volume from the coarse binary food region without rewriting the estimators.

### Decision

In the `.twoViewSfS` volume branch, when the fallback is active, size the `VoxelGrid` from `CaptureResult.preShutterFoodMask` (binary) and run the existing carve with `matchedClasses = {defaultClassId}` — a synthetic single-class labelling. The estimators are not modified.

### Rationale

`VoxelGridSizer.Inputs.foodMask` already takes a `BinaryMask`, and the carve already produces per-class volumes keyed by class. Feeding it one synthetic class yields one total volume with no change to the volume module — the smallest possible change surface.

### Alternatives Considered

- **New dedicated MV estimator**: Rejected — more code, duplicates carve/grid logic.
- **Modify the estimators to accept a "single-class mode"**: Rejected — spreads the fallback into the volume module rather than isolating it at the pipeline seam.

### Consequences

**Positive:** Volume module untouched; change is confined to the pipeline stage; trivially reverts with Decision 1's gate.
**Negative:** A synthetic argmax is constructed at the seam; care is needed so the negligible-region refusal still fires.

---

## Decision 3: Default class and density for the attributed volume

**Date**: 2026-06-22
**Status**: proposed (confirm at review gate)

### Context

The single total volume needs a class + density to become a carb number. The palette's `unknownFood` (index 25) is excluded by `isFoodClass`, so it is skipped by Macros; a real coefficient is required.

### Decision

Apply a fixed "generic mixed food" density of **1.0 g/cm³** and carbohydrate coefficient of **15 g / 100 g** to the recovered total volume in the fallback, tagged as a low-confidence, single-default-class estimate. (Provenance may still be recorded against `unknownFood`.)

### Rationale

The number is explicitly rough for MVP/TestFlight; a mid-range generic coefficient gives a believable order of magnitude for typical plated food. Accuracy comes from the real per-class model (Track 3), so precision here is not the goal.

### Alternatives Considered

- **Map to a specific real food class' DB density**: Rejected for v0 — picking one of the 24 classes is arbitrary and no better than a generic constant.
- **Per-pixel density from the dev-stub classes**: Rejected — the dev-stub classes are exactly what we cannot trust.

### Consequences

**Positive:** Deterministic, auditable, easy to tune; no dependency on DB completeness.
**Negative:** Carbs can be off by a large factor for atypical foods — acceptable only because the estimate is flagged low-confidence and superseded by Track 3.

---

## Decision 4: Device Evidence (2026-06-23) Confirms the Two-View `noFoodVolumeRecovered` Target

**Date**: 2026-06-23
**Status**: accepted

### Context

This smolspec was drafted from the inferred failure that the two-view path refuses `noFoodVolumeRecovered` on the dev-stub. A two-view device drive on 2026-06-23 captured the full trail and confirms it directly:

```
event=estimate.start capturePath=two_view_sfs
event=pipeline.stage.end name=CardDetection latencyMs=19
event=supportplane.end success=true residual_mm=2.876490
event=pipeline.stage.end name=MetricScale latencyMs=0
event=pipeline.stage.end name=Segmentation latencyMs=27596
event=pipeline.stage.start name=Volume capturePath=two_view_sfs
event=pipeline.stage.end name=Volume latencyMs=27209
event=estimate.end success=false failure=noFoodVolumeRecovered
```

The refusal lands at the **Volume** stage — CardDetection, SupportPlane (clean 2.876 mm fit), MetricScale and Segmentation all succeed first. So the gap is exactly where Decisions 1–2 place the fallback, not an earlier failure.

### Decision

Treat the smolspec target as device-validated and resume the interrupted `/starwave-smolspec` workflow: (a) design-critic review, (b) `tasks.md`, (c) approval gate. The open verification question stands — confirm `VoxelCarveEstimator`/`MaskMatcher`/`transform1To2` actually carve with the synthetic single class (Decision 2) before writing tasks. Decision 3 (default class + density) remains `proposed` pending user confirmation.

### Rationale

The device trail removes the main risk in the smolspec's premise: that the failure might occur before the Volume stage (which would invalidate the `preShutterFoodMask` carve approach). It reaches Volume cleanly, so the fallback seam in Decision 2 is the right insertion point.

### Alternatives Considered

- **Wait for more captures before resuming**: Rejected — the failure is deterministic across the run's captures; further trails would not change the seam.

### Consequences

**Positive:** The smolspec can proceed to tasks with its core assumption verified on-device.
**Negative:** The trail also shows ~27 s Segmentation + ~27 s Volume on the dev-stub Debug build (segmentation runs twice for two-view); see `pipeline-real-device-correctness` Decision 16 — a separate latency concern, not a blocker for this estimator's correctness.

---

# Decision Log: MVP Closeout Trail

## Decision 1: Tighten oblique arming window from ±30° to ±15° around 25°

**Date**: 2026-06-19
**Status**: accepted

### Context

Three on-device Double-mode trails (PhoneMax, build `903842a`) fired the oblique
stage at 7.6°, 52.0°, and 50.2° — never the ~25° target — and every estimate
refused with `noFoodVolumeRecovered`. The oblique shutter arms across the entire
`|Δθ − 25°| ≤ 30°` cap (UI Decision 18 / research Decision 43), i.e. roughly
−5°…55°, so a 50° tap is "in range" even though it sits at the far edge of the
Structure-from-Silhouette (SfS) envelope. At ~50° the visual hull carries almost
no top-down information; `VoxelCarveEstimator.carve` then carves below
`minVoxelCountForClass` and the pipeline refuses. The existing out-of-range hint
(`obliqueTiltOutOfRange.localisedMessage`) was present but only fires past the
±30° edge, so it never warned the user at 50°.

### Decision

Tighten `CaptureFlowModel.obliqueTiltOk` from `abs(degrees - 25) <= 30` to
`abs(degrees - 25) <= 15`. The oblique shutter now arms only for measured tilt in
roughly 10°…40°, centred on the 25° SfS target. The Pipeline-side hard cap in
`Pipeline.estimate` (the `delta > 30` refusal at the geometry-input boundary) is
left unchanged as a backstop; this decision narrows the *arming* gate only.

### Rationale

The arming gate is the right place to keep the user inside the SfS envelope,
because it acts before any capture and reuses the existing live hint and nadir
thumbnail to guide the user. Forcing taps into 10°…40° keeps geometry inside the
Dehais 2017 §III.B 20°–30° band the estimator was designed for, prevents the
off-envelope captures the three trails produced, and is the precondition for the
well-aimed disambiguation re-test the spec needs (a clean ~25° oblique). It is a
few lines and a prerequisite either way.

### Alternatives Considered

- **Keep ±30° and rely on the hint**: Leave the cap and lean on the
  `obliqueTiltOutOfRange` copy to nudge toward 25° — Rejected. Users overshot the
  target on all three trails despite the live indicator; a 50° tap was never
  flagged because it was inside the ±30° band. Guidance alone did not change
  behaviour.
- **Fix the volume estimator instead**: Make `VoxelGridSizer.size` /
  `VoxelCarveEstimator.carve` tolerate near-grazing oblique geometry — Deferred.
  This is materially more work, risks changing the volume numerics for in-envelope
  captures, and the gate tightening is a prerequisite to a clean re-test either
  way. Revisit only if a well-aimed ~25° oblique still refuses.

### Consequences

**Positive:**
- Oblique captures land inside the SfS envelope, improving recovered geometry.
- Fewer wasted captures that refuse downstream with `noFoodVolumeRecovered`.
- Enables the well-aimed re-test the closeout depends on.

**Negative:**
- Stricter arming may feel harder until the user finds the narrower band.
  Mitigated by the existing `obliqueTiltOutOfRange` hint (unchanged copy, "Tilt
  the camera closer to 25° for the angled view.") and the nadir confirmation
  thumbnail already shown while aiming the oblique view.

### Impact

Supersedes the `|Δθ − 25°| ≤ 30°` aspect of UI Decision 18 (oblique-stage hard
cap). Affects `App/CaptureFlowModel.swift` (`obliqueTiltOk`, `canShutter`,
`obliqueTiltMessage` doc comments) and the arming-window arguments in
`MeData/Tests/CaptureFlowModelTiltGateTests.swift`. The Pipeline-side
`obliqueTiltOutOfRange` refusal and its tests are unchanged.

---

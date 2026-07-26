# Decision Log: MVP Closeout Trail

## Decision 1: Tighten oblique arming window from ±30° to ±15° around 25°

**Date**: 2026-06-19
**Status**: accepted

### Context

Three on-device Double-mode trails (the iPhone 13 Pro Max, build `903842a`) fired the oblique
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

Related: `specs/bugfixes/two-view-carve-no-volume/report.md` root-caused the same
mis-aimed-oblique → `noFoodVolumeRecovered` failure (non-overlapping image-centred
silhouettes at 46–57° tilt) and wired the tilt aim guide as its remediation; this
arming-window tightening and that aim guide are complementary fixes for one defect.

---

## Decision 2: Parallelise the segmentation postprocess hot passes across CPU cores

**Date**: 2026-06-19
**Status**: accepted

### Context

`SegmenterPostProcessor.process` was the dominant pipeline cost in the device
trail. It runs softmax → crop → bilinear resize → argmax → silhouette/σ_seg →
FP16 encode over an original-resolution (1920×1440) × 27-class probability tensor
(~74.6M floats per full-tensor pass). A phase-by-phase microbench (Apple Silicon,
release) attributed the ~115 ms steady-state cost as: bilinear resize ~64 ms
(≈49%), argmax ~30 ms, softmax ~18 ms, FP16 encode ~10 ms, crop ~5 ms,
silhouette/σ_seg ~3 ms. The cost is memory-bandwidth-bound and intrinsic to the
fixed output contract (resolution, class count, FP16 tensor) — vectorising the
inner class run (vDSP at length-27, manual SIMD8) gave under 15% because the
bilinear gather is not contiguously vectorisable, and the contract forbids
reducing resolution or class count.

### Decision

Fan the two largest passes — the bilinear resize and the argmax scan — out across
CPU cores with `DispatchQueue.concurrentPerform` over whole-row stripes (helper
`parallelForRows`, with a serial fallback below a 64k-pixel threshold). Both
passes are per-output-element independent, so the result is bit-identical to the
serial computation regardless of stripe boundaries or worker scheduling. The
softmax, crop, silhouette/σ_seg reduction, and FP16 encode stay serial — the
reduction is kept serial specifically to preserve identical floating-point
accumulation order for σ_seg / perClassMeanProb.

### Rationale

Parallelism is the only lever that beats a memory-bandwidth-bound scalar pass
without touching the output contract or the numerics. Measured end-to-end on
Apple Silicon (release), the full `process` dropped from ~115 ms to ~31.5 ms
steady-state — a **73% cut** — with deterministic, bit-identical output (σ_seg
unchanged, argmax and FP16 bytes stable across runs). The full `swift test` suite
(313/313, 3 skipped) stays green, which is the correctness proof that the
contract and numerics are unchanged. On a ~6-core device the speedup is smaller
than on the 18-core dev Mac but still clears the ≥50% target comfortably for the
two parallelised passes.

### Alternatives Considered

- **Vectorise the class run (vDSP / SIMD8)**: Rejected — at 27 classes the vDSP
  call overhead erased the gain (62.9 ms vs 60.5 ms scalar), and manual SIMD8
  gave only ~14% because building the gather vectors is itself scalar.
- **Reduce resolution / class count, or fuse resize into FP16 encode**: Rejected —
  forbidden by the output contract; `resized` (FP32) is needed by argmax,
  silhouette and σ_seg, so it cannot be skipped.
- **Document the floor and defer (escape hatch)**: Not needed — a single
  targeted, contract-preserving change cleared ≥50%.

### Consequences

**Positive:**
- ~73% postprocess cut (dev Mac), bit-identical output, no contract change.
- Helper `parallelForRows` is reusable for any future per-pixel pass.

**Negative:**
- The dev-stub postprocess remains a CPU-bound floor; Phase 3's CoreML segmenter
  on the Neural Engine supersedes this dev-stub path entirely and is where the
  research §16 sub-second budget is met. This cut is a stepping-stone, not
  load-bearing.

### Impact

Affects `MedataCore/Sources/Segmentation/PostProcessing.swift`
(`bilinearResizeProbabilities`, the argmax pass, new `parallelForRows` helper).
No public-surface, contract, or numeric change.

---

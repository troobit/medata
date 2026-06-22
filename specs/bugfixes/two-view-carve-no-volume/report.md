# Bugfix Report: two-view-carve-no-volume

**Date:** 2026-06-23
**Status:** Investigated — not a carve defect; root cause is upstream (mis-aimed oblique capture / unwired tilt aim guide, Track 2). No `VoxelCarveEstimator` change.

## Description of the Issue

On the two-view (`twoViewSfS`) capture path, the pipeline refuses with
`event=estimate.end success=false failure=noFoodVolumeRecovered` at the **Volume**
stage, even though CardDetection, SupportPlane, MetricScale, and Segmentation all
succeed first (device trail, `specs/mv-volume-estimator/decision_log.md` Decision 4).
Single mode (LiDAR height-field path) is unaffected and persists records normally.

**Reproduction steps:**
1. Run a dev-stub build, select two-view (double) mode.
2. Capture a nadir frame, then an oblique frame.
3. If the oblique is **not** physically aimed at the food (tilted in place / outside
   the arming window), the Volume stage refuses `noFoodVolumeRecovered`.

**Impact:** The v0-priority two-view volume path produces no estimate. Single mode is
the only working spine for the first `main` commit.

## Investigation Summary

This started as a smolspec (`specs/mv-volume-estimator/`) premised on the dev-stub
producing "unusable per-class masks". That premise was wrong (see Decision 5 there),
which reframed it as a suspected geometry bug in the carve. The geometry was then
characterised with a synthetic two-view reproduction.

- **Symptoms examined:** Device trail showing Segmentation success then Volume refusal.
- **Code inspected:** `VoxelCarveEstimator.swift` (carve/ownership), `VoxelGridSizer.swift`,
  `MaskMatcher.swift`, `PipelineBridges.swift` (`transform1To2`), `CaptureResult.swift`,
  `StubInferenceEngine.swift`, `ClassPalette.swift`, `Pipeline.swift` `.twoViewSfS` branch.
- **Hypotheses tested and ruled out:**
  - *"Dev-stub masks have no surviving food class."* **False** — the stub paints
    `dominantClass = 0` = `white_rice` (a real food class) at ~0.99999 inside a centred
    ellipse (`StubInferenceEngine.swift:57-62`), in both views. `MaskMatcher` finds
    `{white_rice}` in both → `matchedClasses = {0}`.
  - *"`matchedClasses = {synthetic class}` would force a volume."* **False** — carve
    ownership is driven by the per-class probability product `q1[c]·q2[c] ≥ τ_v (0.04)`
    over the supplied tensors (`VoxelCarveEstimator.swift:142-157`), not by the class list.
  - *"The carve / projection / transform is defective."* **False** — proven by the
    synthetic reproduction below: the carve recovers volume correctly whenever the two
    views actually see the same food region.

## Discovered Root Cause

Two-view voxel carving is a **photo-consistency** operation: a voxel is owned only if
it projects to food in *both* views and survives the silhouette test in both
(`VoxelCarveEstimator.swift:131-157`). The dev-stub paints its food ellipse at the
**image centre in every view regardless of camera pose** — so the two silhouettes only
describe the same 3-D object when the oblique camera is physically **aimed at the food**.

Synthetic reproduction (`TwoViewObliqueCarveDiagnosticTests`), grid sized from a centred
ellipse over a plane at z=−400 mm:

| Oblique pose | Recovered volume |
|---|---|
| Identity (coincident views) | 167.9 cm³ |
| Aimed at food, orbit 10° / 25° / 40° | 121 / 72 / 53 cm³ — recovers |
| **Tilted in place 25° / 46° / 57° (no re-aim)** | **`noFoodVolumeRecovered`** |

The angles that fail (46°, 57°) match the device's documented stuck oblique tilt
(46–57°, outside the 10–40° arming window). When the oblique tilts without re-pointing
at the food, the image-centred ellipses correspond to non-overlapping world regions and
the carve correctly recovers nothing.

**Defect type:** Not a software defect in the volume module. Capture-geometry / UX gap.

**Why it occurred:** The oblique frame cannot be aimed correctly because the **tilt aim
guide is not wired** into `CaptureFlowView` on the shipping line (Track 2; it is built on
the `ui` worktree but unwired on research/main). With no on-screen cue, the oblique sits
outside the 10–40° window, so the two silhouettes never overlap.

**Contributing factors:** The dev-stub's image-centred mask is geometrically forgiving
only when the oblique is well-aimed; it does not label the *actual* food pixels the way a
real segmenter (Track 3) would, so it is less tolerant of framing error than the eventual
real model.

## Resolution for the Issue

**Changes made:** None to `VoxelCarveEstimator` or the volume path — the carve behaves
correctly. The fix lives upstream of the carve and is already-scoped work:

- **Track 2 — wire the tilt aim guide** (built on the `ui` worktree) into the capture
  flow so the oblique can be armed within the 10–40° window, then re-capture a
  well-aimed two-view trail and confirm `estimate.end success=true`.

**Approach rationale:** The investigation shows the carve recovers volume whenever the
views overlap; the missing piece is getting a well-aimed oblique, which is the oblique-aim
blocker tracked in `nextup.md`, not a carve change.

**Alternatives considered:**
- *Mask-extrusion fallback for the dev-stub* (bypass the carve, extrude the nadir mask) —
  rejected earlier (`mv-volume-estimator` Decision 5): a dev-stub-only crutch that would
  also have masked this genuine aiming problem.
- *Make the dev-stub world-consistent* (project a fixed world-space disk into each view
  using pose + plane, instead of an image-centred ellipse) — a dev-tooling improvement
  that would make two-view testable without precise aiming, but the stub does not currently
  receive camera pose / plane. Worth considering if two-view must be validated before
  Track 3, but out of scope for this investigation.

## Regression Test

**Test file:** `MedataCore/Tests/VolumeTests/TwoViewObliqueCarveDiagnosticTests.swift`
**Test names:** `testIdentityTransformRecoversVolume`, `testWellAimedObliqueRecoversVolume`,
`testMisAimedObliqueRecoversNoVolume`

**What it verifies:** That the two-view carve recovers a volume when the views overlap
(identity and well-aimed oblique) and correctly refuses `noFoodVolumeRecovered` when the
oblique is tilted in place — pinning the carve's photo-consistency behaviour and the true
cause of the device symptom.

**Run command:** `swift test --filter TwoViewObliqueCarveDiagnosticTests`

## Affected Files

| File | Change |
|------|--------|
| `MedataCore/Tests/VolumeTests/TwoViewObliqueCarveDiagnosticTests.swift` | New characterisation tests (no production change) |

## Verification

**Automated:**
- [x] Characterisation tests pass (3/3)
- [ ] Full test suite — not re-run (no production code changed)
- [x] No production code modified

**Manual verification:**
- Pending on-device: wire the tilt aim guide, capture a well-aimed two-view trail, confirm
  `estimate.end success=true` with a non-zero volume.

## Prevention

- A real two-view capture must keep the food in frame in **both** views; surface the tilt
  aim guide so the oblique arms only within the valid window.
- Consider upgrading `StubInferenceEngine` to paint a world-locked region so dev-stub
  two-view runs are not sensitive to precise aiming.

## Related

- `specs/mv-volume-estimator/decision_log.md` (Decisions 4–5) — the superseded smolspec
  and the misdiagnosis chain that led here.
- `specs/pipeline-real-device-correctness/` — device-correctness pipeline spec, Decision 16.
- `nextup.md` — oblique-aim blocker (Track 2 tilt aim guide), two-view collection.

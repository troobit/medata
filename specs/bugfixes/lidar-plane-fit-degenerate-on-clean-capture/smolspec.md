# LiDAR Plane Fit Degenerate on Clean Capture

## Overview

On iPhone 13 Pro Max iOS 26.5, every shutter tap surfaces the *"Unable to detect a flat surface. Please place the meal on a level surface."* modal even though the capture itself is clean (both stages succeed at 1920×1440 with live LiDAR coverage at 87.5 %). The pipeline construction that landed 2026‑05‑30 wires the real `Pipeline.makeForDevice` factory (Phase 1 dev‑stub) at `App/App.swift:41`, so the refusal now comes from a logic bug in `Pipeline.fitSupportPlane` rather than from the old `PendingPipeline` placeholder. This smolspec scopes the minimal fix to make the LiDAR plane fit succeed on a normal meal capture.

## Evidence

Device log captured 2026‑06‑03, archived at `nextup.md` (lines 82‑97):

```
event=fired state=ready tiltDegrees=5.1 distanceCm=32.8 lidarCoveragePercent=87.5
  supportsLiDAR=true canShutter=true mode=double stage=nadir
event=capture.start stage=nadir
event=capture.end   stage=nadir   success=true width=1920 height=1440
event=capture.start stage=oblique
event=capture.end   stage=oblique success=true width=1920 height=1440
event=estimate.start capturePath=two_view_sfs
event=estimate.end   success=false failure=lidarFitDegenerate
```

User also reports the modal fires in 2‑photo mode (which the log already confirms: `capturePath=two_view_sfs` *is* the 2‑photo path) and persists across bottom‑nav tab changes (tracked separately — see Out of Scope).

## Root cause

`Pipeline.fitSupportPlane` (`MedataCore/Sources/Pipeline/Pipeline.swift:372-391`) constructs a `roughMask` that is **all ones over the entire image** and passes it as `foodRegionMask` to `LiDARPlaneFitter.fit(_:)`:

```swift
let roughMask = BinaryMask(
    pixels: [UInt8](repeating: 1, count: nadir.imageWidth * nadir.imageHeight),
    width: nadir.imageWidth,
    height: nadir.imageHeight
)
```

`LiDARPlaneFitter.collectCandidatePoints` (`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift:85-129`) is designed to find **table** pixels in a lower‑edge band underneath the food bounding box. It computes `bbox = foodBBox(mask:)`, then scans `y ∈ [bbox.maxY, yScanMax]` and for each pixel skips it if the mask says it is food. With an all‑ones mask:

- `foodBBox` returns `(0, 0)‑(width‑1, height‑1)` — the whole image is "food".
- `yLowerEdge = bbox.maxY = height - 1`, the bottom row.
- `yScanMax = min(height - 1, yLowerEdge + bbox.heightPx) = height - 1`, so the y‑loop body executes for a single row.
- Inside that row, every pixel satisfies `mask.isFood(x:y:)`, so every pixel is skipped.

Result: `points == []`. `fit(_:)` then throws `SupportPlaneError.noLidarPoints` (`LiDARPlaneFitter.swift:46`), which the catch‑all at `Pipeline.swift:389-391` converts into `EstimationFailure.lidarFitDegenerate`, which the UI surfaces as the modal. The fit cannot succeed under any framing — this is a guaranteed failure for every shutter tap.

This is not the *path-decider's* fault (`twoViewSfS` is still selected because `foodRegionCoveragePercent` is never wired pre‑shutter — tracked separately), and not the launch‑time camera‑race fault (covered by `arview-session-config-race`). It is a wrong‑mask bug at the `LiDARPlaneFitter` call site in `Pipeline`.

## Requirements

- The system MUST produce a non‑empty candidate‑point set for `LiDARPlaneFitter.fit(_:)` on a normal meal capture on iPhone 13 Pro Max, so the LiDAR plane fit reaches the RANSAC + refinement steps instead of throwing `noLidarPoints`.
- The system MUST NOT throw `EstimationFailure.lidarFitDegenerate` on a clean capture where the supporting surface (plate-on-table) is visible in the LiDAR depth, both on the `.singleViewLidar` and the `.twoViewSfS` paths.
- The system MUST preserve the existing behaviour of `LiDARPlaneFitter` for callers that pass a real food‑region mask (e.g. post‑segmentation), so the fix is contained at the `Pipeline.fitSupportPlane` call site and does not change `LiDARPlaneFitter`'s contract.
- The fix SHOULD introduce a deterministic, depth‑independent approximation of the food region for Phase 1, so the LiDAR plane fit has a meaningful lower‑edge band to scan.
- The system SHOULD log the candidate‑point count and `SupportPlaneError` kind at the `Pipeline.fitSupportPlane` call site (DEBUG only) so future regressions surface a numeric trace instead of an opaque modal.

## Implementation Approach

### Chosen fix (see Decision 1 in `decision_log.md`)

Replace the all‑ones `roughMask` in `Pipeline.fitSupportPlane` with a **centre‑rectangle approximation** of the food region for Phase 1: a `BinaryMask` whose `1` pixels form a centred rectangle covering the middle of the image (proposed default: `fillFraction = 0.7`, i.e. inner rectangle is 70 % × 70 % of the image, centred), and whose `0` pixels form the surrounding border. This approximates the typical plate‑on‑table framing the user is gated into by the capture flow (centred, 30‑40 cm distance, tilt near 0° at the nadir stage).

Geometric justification for `0.7`: iPhone 13 Pro Max main wide camera has ~67° horizontal FOV; at the gating distance (~30 cm) the horizontal field is ~40 cm and a ~25 cm dinner plate fills ~63 % of image width/height. A 70 % rectangle contains the plate with a small margin, so the lower-edge band y ∈ [0.85, 1.0] sits *below* the plate on actual table pixels — exactly what `LiDARPlaneFitter.collectCandidatePoints` was designed to consume.

With this mask:

- `foodBBox` returns the inner rectangle `[0.15W, 0.85W] × [0.15H, 0.85H]`.
- `yLowerEdge` sits at `~0.85 × imageHeight`, with `yScanMax` clamping to `imageHeight - 1`.
- `mask.isFood(x:y:)` is *false* in the band below the rectangle (the bottom 15 % of the image).
- `collectCandidatePoints` collects depth samples from the *table* surrounding the plate — exactly what the fitter was designed to consume.

### Affected files

- **`MedataCore/Sources/Pipeline/Pipeline.swift`** (~25 LOC) — replace the all‑ones mask block at lines 373‑377 with a helper that constructs a centred‑rectangle `BinaryMask`. Add a private static helper `makeCentreRectangleMask(width:height:fillFraction:)` on `Pipeline` (or in a small extension file under the same module) so the construction is unit‑testable.
- **`MedataCore/Tests/PipelineTests/SupportPlaneRoughMaskTests.swift`** (new, ~50 LOC) — unit tests asserting (a) the all‑ones mask reproduces `SupportPlaneError.noLidarPoints` against a synthetic depth map, (b) the centre‑rectangle mask of the proposed dimensions yields ≥ `LiDARPlaneFitter.minPoints` candidates on the same synthetic input and produces a finite plane fit.
- **`App/CaptureFlowModel.swift`** *or* a small helper in `Pipeline.swift`, DEBUG only (~5 LOC) — surface the candidate‑point count via the existing `logger` used for the `estimate.start` / `estimate.end` events (see `nextup.md` for log shape). Use the existing log subsystem `ie.medata.app`, category `Shutter` so the trace fits the established channel.

### Patterns to follow

- The "centred crop fraction" pattern is already in use elsewhere — `App/LiveSampleObserver.swift:65-67` uses `cropFraction: Float = 0.2` for the live distance‑median crop. Reuse the same constant‑driven shape (named constant on the helper) so future readers can tie the two together.
- `LiDARPlaneFitter.Inputs` already accepts a `BinaryMask`; the helper produces one. No changes to `LiDARPlaneFitter` or `SupportPlane` types.
- Existing `BinaryMask` constructor at `MedataCore/Sources/SupportPlane/SupportPlane.swift:32` takes `pixels: [UInt8], width: Int, height: Int` and asserts `pixels.count == width * height`.

### Verification

1. Unit tests pass on simulator: `xcodebuild test -scheme MedataCore-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,arch=arm64' -only-testing:PipelineTests/SupportPlaneRoughMaskTests`.
2. Full `MedataCore` test suite still passes (no regression in existing `PipelineTests` or `SupportPlaneTests`).
3. On‑device verification on iPhone 13 Pro Max iOS 26.5: open the app, frame a meal on a flat table at ~30‑40 cm with the centring guide, tap the shutter. Expected: `estimate.end` logs `success=true` (or, on the dev‑stub segmenter, a different downstream failure like `noFoodVolumeRecovered` — the point is the modal no longer surfaces from `lidarFitDegenerate`). Capture the new device log and append it to the spec's `report.md` on resolution.

### Out of scope

- Replacing the centre‑rectangle approximation with a real food‑region mask derived from a pre‑shutter segmentation pass — tracked separately under the follow‑on full spec `specs/estimation/pipeline-real-device-correctness/` (not yet created).
- Wiring `foodRegionCoveragePercent` into `LiDARStatus` so `selectCapturePath` can pick `.singleViewLidar`. Same follow‑on spec.
- Replacing `NullCardDetector` with a Vision‑backed implementation. Same follow‑on spec.
- The "refusal modal persists across bottom‑nav tab change" UI bug. Separate concern; flag this as a follow‑up but do not address here.
- The launch‑time `FigCaptureSourceRemote` `-12784` / `-17281` errors. Covered by `specs/bugfixes/arview-session-config-race/`; a 2026‑06‑03 on‑device verification note will be appended to that spec's `report.md`.
- Refactoring `Pipeline.fitSupportPlane`'s path‑gated logic (e.g. skipping LiDAR fit when `capturePath == .twoViewSfS`). Out of scope because the design intent — *LiDAR fit takes precedence when depth is available* — is correct and should be preserved; only the mask passed to it is wrong.

## Risks and Assumptions

- **Risk**: The centre‑rectangle is a *spatial* approximation, not a *semantic* one. A user who frames the meal off‑centre or shoots the plate from an angle that puts the table outside the bottom border of the rectangle will still see the modal. **Mitigation**: the capture flow already gates the user into centred, near‑0° tilt, ~30‑40 cm framing at the nadir stage (see `App/CaptureFlowModel.swift` gating); the rectangle is calibrated to that envelope. The follow‑on full spec replaces the heuristic with the real food‑region mask.
- **Risk**: The chosen `fillFraction` (proposed 0.5) may be too large or too small. Too large → the lower‑edge band sits below the visible image edge; too small → the band covers the plate rim instead of the table. **Mitigation**: regression test uses a synthetic depth map where the "table" is known to occupy the outer border; the test asserts the candidate count and plane fit are stable under the chosen fraction. The constant lives in one place so a single tweak adjusts it.
- **Risk**: This change alters the behaviour of `Pipeline.fitSupportPlane` even on the `.singleViewLidar` path — where post‑segmentation the real food mask is *also* used by the volume estimator. **Mitigation**: the `roughMask` at this call site is *only* used for the plane fit; the segmentation result is consumed downstream by `HeightFieldEstimator` (`Pipeline.swift:194-220`) which has its own inputs. The two masks are independent.
- **Assumption**: `Pipeline.fitSupportPlane` is the only call site that constructs an all‑ones mask for `LiDARPlaneFitter`. **Validation**: grep `LiDARPlaneFitter` call sites in production code (not tests) before editing. The fitter's tests use synthetic masks designed for their assertions and are out of scope.
- **Assumption**: The capture frame's `nadir.imageWidth` and `nadir.imageHeight` are the same colour grid the `BinaryMask` is expressed against. **Validation**: confirmed by the existing all‑ones construction at `Pipeline.swift:373-377` already passing these dimensions to `BinaryMask`.
- **Prerequisite**: A reproducible synthetic depth + mask fixture for the regression test. The existing `MedataCore/Tests/SupportPlaneTests/` (or `PipelineTests/`) should already have similar fixtures to start from; the new test reuses or extends them.

## Re-open 2026-06-16 — real-mask path regresses the fit

**Status**: re-opened. The 2026-06-03 fix above is preserved as the all-ones-mask regression sentinel (`SupportPlaneRoughMaskTests` at `MedataCore/Tests/PipelineTests/SupportPlaneRoughMaskTests.swift`). The `CentreRectangleMask.swift` helper itself has been retired — the `specs/estimation/pipeline-real-device-correctness/` follow-on wired a real pre-shutter `BinaryMask` through `CaptureResult.preShutterFoodMask`, so `Pipeline.fitSupportPlane` no longer constructs any rough mask of its own. That migration is what re-exposes this bug.

### Evidence

PhoneMax (iPhone 13 Pro Max iOS 26.5), build HEAD `288c5a7` (no-food-pixels-on-fruit-plate-mvp cadence + lost-age fixes), mode=double, 2026-06-16 (see `nextup.md` `# LOGS`):

```
01:13:26.771  event=capture.end   stage=oblique success=true width=1920 height=1440
01:13:26.771  event=estimate.start capturePath=two_view_sfs
01:13:26.772  event=estimate.start maskAgeMs=170
01:13:26.804  event=pipeline.stage.start name=SupportPlane
01:13:26.804  event=supportplane.start width=1920 height=1440 source=pre_shutter
01:13:27.505  event=estimate.end success=false failure=lidarFitDegenerate
```

`source=pre_shutter` is the new — and correct — path: a real pre-shutter mask from `PreShutterSegmenter.latest` reaches `LiDARPlaneFitter.fit` instead of the centre-rectangle stand-in.

### Root cause (real-mask path)

`LiDARPlaneFitter.collectCandidatePoints` (`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift:100-144` pre-fix) only scans the band **below** the food bbox (`y ∈ [bbox.maxY, bbox.maxY + bbox.heightPx]`, `x ∈ [bbox.minX, bbox.maxX]`). On a centred capture envelope the plate fills the middle of the frame; on the Phase 1 dev-stub the bbox is the cropped ellipse cap at α=0.618 (`MedataCore/Sources/Segmentation/StubInferenceEngine.swift:43-62`) which post-letterbox-crop-and-resize occupies y ∈ [≈367, ≈1437] in a 1440-tall device frame. The below-bbox scan window collapses to 2-3 image rows. Either:

- `points.count < minPoints` (3) → `noLidarPoints` (mapped to `EstimationFailure.lidarFitDegenerate` at `Pipeline.swift:465-469`), OR
- the candidate set forms a near-collinear 3-D line (all points sharing image-y → constant camera-Y after back-projection) → singular covariance at `refine` (`LiDARPlaneFitter.swift:238`) → `SupportPlaneError.lidarFitDegenerate`.

The earlier centre-rectangle `roughMask` had been hiding the geometry by guaranteeing a wide scan window below its inner rectangle. With the real mask now in play, that buffer is gone.

### Fix (real-mask path)

`collectCandidatePoints` now scans **four** edge bands around the food bbox — top, bottom, left, right — each as thick as the bbox dimension perpendicular to it, clipped to image bounds. Preserves the fitter's design intent (collect table pixels around the plate); only widens which sides are considered, so that any side flush against an image edge no longer starves the candidate set. `LiDARPlaneFitter.Inputs` is unchanged; `Pipeline.fitSupportPlane` is unchanged; the `LiDARSupportPlaneFitter` protocol contract is unchanged. See `decision_log.md` Decision 2.

### Affected files

| File | Change |
|------|--------|
| `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` | `collectCandidatePoints` scans four edge bands instead of one; `BBox` gains a `widthPx` accessor mirroring `heightPx`. |
| `MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterTests.swift` | New regression `testFitsCentredMaskWithBboxAtImageBottomEdge` — bbox extending to the image's last row; pre-fix throws `noLidarPoints`, post-fix recovers a 5°-tilted plane within 2° and 5 mm. |

### Out of scope (real-mask re-open)

- Wiring `foodRegionCoveragePercent` into `LiDARStatus` so `selectCapturePath` picks `.singleViewLidar`. Tracked under `specs/estimation/pipeline-real-device-correctness/`.
- Replacing `NullCardDetector` with a Vision-backed implementation. Same.
- Single-mode on-device trail (the 2026-06-16 device run was Double-only). Folded into closeout verification.

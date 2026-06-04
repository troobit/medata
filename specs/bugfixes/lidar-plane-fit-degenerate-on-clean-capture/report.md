# Bugfix Report: LiDAR Plane Fit Degenerate on Clean Capture

**Date:** 2026-06-03
**Status:** Fixed (automated); on-device verification pending

## Description of the Issue

On iPhone 13 Pro Max iOS 26.5, every shutter tap surfaced the *"Unable to detect a flat surface. Please place the meal on a level surface."* refusal modal — even on clean captures where both stages succeeded at 1920×1440 with live LiDAR coverage at 87.5%. The wired Phase 1 `Pipeline.makeForDevice` factory (Decision 42 of the device-MVP work, landed 2026-05-30) replaced the prior `PendingPipeline` placeholder, so the refusal began coming from a real pipeline run rather than the placeholder's early return.

**Reproduction steps:**
1. Build the iOS app (Debug) and install on iPhone 13 Pro Max iOS 26.5.
2. Launch, grant camera + photo permissions.
3. Frame a meal on a flat table at ~30-40 cm with the centring guide; tilt ≈ 0° at the nadir stage.
4. Tap the shutter.

**Observed device log (2026-06-03, archived at `nextup.md` lines 82-97):**

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

**Impact:** the app was unusable end-to-end on a device under any framing — the refusal fired on every shutter tap, blocking the result view. Not a permanent data-loss bug, but a release-path failure of the primary user flow.

## Investigation Summary

- **Symptoms examined:** `estimate.end success=false failure=lidarFitDegenerate` on every shutter, regardless of framing, tilt, distance, or `capturePath` (`single_view_lidar` and `two_view_sfs` both failed).
- **Code inspected:**
  - `MedataCore/Sources/Pipeline/Pipeline.swift:fitSupportPlane` — wraps `LiDARPlaneFitter.fit(_:)` and converts `SupportPlaneError` cases to `EstimationFailure`.
  - `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift:collectCandidatePoints` — scans the band *below* the food bounding box for non-food pixels.
  - `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift:fit(_:)` — throws `noLidarPoints` when `< minPoints` candidates remain.
  - Git history: commit `0e77e94` and earlier `PendingPipeline` shape (placeholder, never reached `fitSupportPlane`); `4b67cbc` (camera-input fix, unrelated); the Phase 1 factory commit that wired the real pipeline (2026-05-30).
- **Hypotheses tested:**
  - Hypothesis A: tilt-out-of-range refusal misclassified as `lidarFitDegenerate`. **Ruled out** — the tilt-tolerant capture spec removed the nadir tilt gate; the log shows the failure firing at `tiltDegrees=5.1`, well inside any envelope.
  - Hypothesis B: the launch-time `FigCaptureSourceRemote` race (covered by `arview-session-config-race`) is still in play and the LiDAR session never starts. **Ruled out** — both `capture.end` lines show `success=true` with full 1920×1440 frames; LiDAR coverage is 87.5%.
  - Hypothesis C: the path-decider is picking `twoViewSfS` when `singleViewLidar` would be more appropriate. **Partially true but not the cause** — `foodRegionCoveragePercent` is unwired pre-shutter so `selectCapturePath` always returns `twoViewSfS`; but both paths run `fitSupportPlane`, and the bug fires on both.
  - Hypothesis D (confirmed): `Pipeline.fitSupportPlane` passes an **all-ones** `roughMask` to `LiDARPlaneFitter`, defeating the fitter's lower-edge scan and producing zero candidate points on every call.

## Discovered Root Cause

`Pipeline.fitSupportPlane` (`MedataCore/Sources/Pipeline/Pipeline.swift:373-377` pre-fix) constructed a `BinaryMask` of all-ones over the full image:

```swift
let roughMask = BinaryMask(
    pixels: [UInt8](repeating: 1, count: nadir.imageWidth * nadir.imageHeight),
    width: nadir.imageWidth,
    height: nadir.imageHeight
)
```

`LiDARPlaneFitter.collectCandidatePoints` (`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift:85-129`) interprets the mask as a *food* region and scans the band *below* its bounding box for *non-food* pixels (the table surrounding the plate):

```swift
let bbox = foodBBox(mask: mask)
let yLowerEdge = bbox.maxY
let yScanMax = min(mask.height - 1, yLowerEdge + bbox.heightPx)
for y in yLowerEdge..<yScanMax + 1 {
    for x in xMin...xMax {
        if mask.isFood(x: x, y: y) { continue }
        ...
    }
}
```

With an all-ones mask:

- `foodBBox` returns `(0, 0)-(width-1, height-1)` — the whole image is "food".
- `yLowerEdge = height - 1`, the bottom row.
- `yScanMax = min(height - 1, yLowerEdge + bbox.heightPx) = height - 1`, so the `y` loop body executes for a single row.
- Every pixel in that row satisfies `mask.isFood(x:y:)`, so every pixel is skipped.
- `points == []` → `fit(_:)` throws `SupportPlaneError.noLidarPoints` → `Pipeline.fitSupportPlane`'s catch-all converts it to `EstimationFailure.lidarFitDegenerate` → the modal.

**Defect type:** Wrong precondition. The placeholder mask satisfied `BinaryMask`'s row-major contract but violated `LiDARPlaneFitter`'s contract that the mask demarcates *food* (so the lower-edge band can find *non-food* table pixels).

**Why it occurred:** When `LiDARPlaneFitter` and `Pipeline.fitSupportPlane` were authored, there was no pre-shutter segmentation pass to produce a real food-region mask, and the placeholder fell back to "everything is food." The bug was masked while `PendingPipeline` short-circuited the pipeline (pre-2026-05-30) and surfaced as soon as the Phase 1 dev-stub factory wired the real `Pipeline` into the App.

**Contributing factors:** the catch-all at `Pipeline.swift:389-391` mapped any non-`lidarFitResidualTooHigh` `SupportPlaneError` to `EstimationFailure.lidarFitDegenerate`, hiding the more precise `noLidarPoints` cause from the device log. The new DEBUG-only structured logging closes that gap.

## Resolution for the Issue

**Changes made:**

- `MedataCore/Sources/Pipeline/CentreRectangleMask.swift` (new) — `makeCentreRectangleMask(width:height:fillFraction:)` builds a `BinaryMask` whose `1` pixels form the centred `fillFraction × fillFraction` rectangle and whose `0` pixels form the surrounding border. A named constant `centreRectangleFillFraction: Float = 0.7` is co-located so the value is discoverable and tunable in one place (Decision 1).
- `MedataCore/Sources/Pipeline/Pipeline.swift` — `fitSupportPlane` calls the helper instead of constructing an all-ones mask. Adds DEBUG-only `event=supportplane.start` and `event=supportplane.end` structured-log entries on the `ie.medata.app` / `Shutter` channel carrying mask dimensions, fillFraction, residual_mm, inlier count, candidate-point count, and `SupportPlaneError` case on failure.
- `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` — DEBUG-only `debugLastCandidatePointCount` and `debugLastInlierCount` static counters populated inside `fit(_:)` so the Pipeline-side log can report a numeric trace without changing the production API.

**Approach rationale:** the smallest surgical change that closes the root cause and preserves the LiDAR-fit-takes-precedence design intent. The capture flow already gates the user into a centred, near-0° tilt, ~30-40 cm framing (`App/LiveSampleObserver.swift:65-67`'s `cropFraction: Float = 0.2` for the live distance crop, plus the tilt-tolerant capture spec's nadir framing UX), so a 70%-fillFraction centred rectangle is calibrated to the documented capture envelope: a ~25 cm dinner plate at ~30 cm covers ~63% of the frame, so 70% contains it with a small margin and the bottom 15% of the frame lands on visible table pixels.

**Alternatives considered:** see `decision_log.md` Decision 1. Briefly: skipping the LiDAR fit on `.twoViewSfS` was rejected because the wired `NullCardDetector` then forces `noScaleAvailable`; a depth-based heuristic food region was rejected for adding a new failure mode (a hand or glass closer than the plate becomes "food") at greater implementation cost than the surgical fix; relaxing `LiDARPlaneFitter`'s `minPoints` was rejected because the proximate cause is zero candidate points, not too few; reordering pipeline stages so segmentation runs before the LiDAR fit was rejected as far out of scope for a Phase 1 bugfix.

## Regression Test

**Test files:**

- `MedataCore/Tests/PipelineTests/CentreRectangleMaskTests.swift` — Swift Testing suite pinning the helper's pixel layout (5 cases).
- `MedataCore/Tests/PipelineTests/SupportPlaneRoughMaskTests.swift` — Swift Testing regression suite (2 cases) over a shared synthetic depth fixture.

**What they verify:**

- `CentreRectangleMaskTests` pins (a) the `[2,8) × [2,8)` inner rectangle for `10×10` at `fillFraction = 0.7`, (b) the `pixels.count == width × height` invariant on non-square dimensions, (c) `fillFraction = 1.0` fills every pixel, (d) `fillFraction = 0.5` shrinks symmetrically to `[3,7) × [3,7)` on `10×10`, and (e) the `centreRectangleFillFraction` named constant is exactly `0.7`.
- `SupportPlaneRoughMaskTests`:
  - **Case (a) — regression sentinel:** with an all-ones `BinaryMask`, `LiDARPlaneFitter.fit` throws `SupportPlaneError.noLidarPoints`. This encodes the pre-fix behaviour so any future code path that re-introduces an all-ones mask trips the test.
  - **Case (b) — success path:** with the centre-rectangle mask from `makeCentreRectangleMask(width:height:fillFraction: 0.7)`, the fit returns a finite plane within `gravityAngleMaxRad` of the synthesised gravity vector and with `residualMm < LiDARPlaneFitter.residualMaxMm`.

**Run command:**

```
swift test --filter "CentreRectangleMaskTests|SupportPlaneRoughMaskTests"
```

Or equivalent Xcode-based test:

```
xcodebuild test \
  -scheme MedataCore-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,arch=arm64' \
  -only-testing:PipelineTests/CentreRectangleMaskTests \
  -only-testing:PipelineTests/SupportPlaneRoughMaskTests
```

## Affected Files

| File | Change |
|------|--------|
| `MedataCore/Sources/Pipeline/CentreRectangleMask.swift` | New file — `makeCentreRectangleMask` helper + `centreRectangleFillFraction` constant |
| `MedataCore/Sources/Pipeline/Pipeline.swift` | `fitSupportPlane` calls the helper instead of building an all-ones mask; DEBUG-only `supportplane.start` / `supportplane.end` Logger events on the existing `ie.medata.app` / `Shutter` channel |
| `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` | DEBUG-only `debugLastCandidatePointCount` and `debugLastInlierCount` static counters populated inside `fit(_:)` |
| `MedataCore/Tests/PipelineTests/CentreRectangleMaskTests.swift` | New file — 5 Swift Testing cases pinning the helper's pixel layout |
| `MedataCore/Tests/PipelineTests/SupportPlaneRoughMaskTests.swift` | New file — 2 Swift Testing cases: all-ones mask → `noLidarPoints`; centre-rectangle mask → finite gravity-aligned plane |
| `Package.swift` | `PipelineTests` target gains `SupportPlane` and `CaptureKit` dependencies for the regression fixture |
| `CHANGELOG.md` | New `Fixed (Bugfix spec — lidar-plane-fit-degenerate-on-clean-capture)` subsection under `[Unreleased]` |

## Verification

**Automated (complete):**

- [x] `swift build` — clean Debug build, no warnings introduced.
- [x] `swift build -c release` — clean Release build (confirms no DEBUG symbols leak into Release).
- [x] `swift test --filter CentreRectangleMaskTests` — 5/5 pass.
- [x] `swift test --filter SupportPlaneRoughMaskTests` — 2/2 pass.
- [x] `swift test` — full `MedataCore` package, all suites pass (no regressions in existing `PipelineTests`, `SupportPlaneTests`, `VolumeTests`, `ConfidenceTests`, `PersistenceTests`, etc.).

**Manual / on-device (pending):**

- [ ] Install the Debug build on iPhone 13 Pro Max iOS 26.5; tap the shutter on a normal meal capture; capture the device log via Xcode Console or `log stream --predicate 'subsystem == "ie.medata.app"'`.
- [ ] Expected log shape (Debug build):

  ```
  event=fired state=ready tiltDegrees=... distanceCm=... lidarCoveragePercent=...
    supportsLiDAR=true canShutter=true mode=double stage=nadir
  event=capture.start stage=nadir
  event=capture.end   stage=nadir   success=true width=1920 height=1440
  event=supportplane.start width=1920 height=1440 fillFraction=0.7
  event=supportplane.end   success=true residual_mm=... inliers=... candidates=...
  event=capture.start stage=oblique
  event=capture.end   stage=oblique success=true width=1920 height=1440
  event=estimate.end   success=true mealId=...
  ```

- [ ] The `event=estimate.end success=false failure=lidarFitDegenerate` line must NOT appear. (A different downstream failure such as `noFoodVolumeRecovered` is acceptable for Phase 1, since the dev-stub segmenter does not produce real food classes.)
- [ ] Append the captured on-device log block to this report's Verification section once the run is observed.

## Prevention

**Recommendations to avoid similar bugs:**

- When a module is added to a pipeline behind a placeholder (here: the all-ones mask), put a TODO at the call site referencing the spec that lifts the placeholder. The original all-ones construction had no comment explaining it was a stand-in for a real food-region mask, so the bug only surfaced when downstream code (`Pipeline.makeForDevice`) wired the placeholder into a live build.
- The catch-all at `Pipeline.fitSupportPlane` was mapping any non-`lidarFitResidualTooHigh` `SupportPlaneError` to `EstimationFailure.lidarFitDegenerate`, which masked the more precise `noLidarPoints` cause. The new DEBUG-only `event=supportplane.end success=false failure=<case>` log carries the exact `SupportPlaneError` case, so future regressions surface a numeric/structured trace rather than the opaque modal.
- Consider promoting `LiDARPlaneFitter.debugLastCandidatePointCount` to a Release-build telemetry counter if (when?) Phase 3 introduces remote observability. For now it is intentionally DEBUG-only to avoid leaking concurrency-unsafe statics into the production build.
- The follow-on full spec `specs/pipeline-real-device-correctness/` (not yet created) should replace the centre-rectangle approximation with a real food-region mask derived from a pre-shutter segmentation pass. Once that lands, the helper at `MedataCore/Sources/Pipeline/CentreRectangleMask.swift` is deleted and `fitSupportPlane` passes the real mask through.

# Bugfix Report: capture-no-flat-surface-gravity-frame

**Date:** 2026-07-06
**Status:** Fixed (device verification pending)

## Description of the Issue

On the deployed real-segmenter build (`0e5f46a-20260706-120508`, model `24e0b022241a`),
every on-device capture failed with "no flat surface" — in BOTH modes (1-view LiDAR and
2-view), on a genuinely flat table. A second defect compounded it: on the resulting
`CaptureErrorOverlay`, the Retry and 2-view buttons did nothing; only Cancel responded —
the same symptom commit 3429ddc had already tried to fix.

**Reproduction steps:**
1. Deploy the Release build to the iPhone 16 Pro and open Capture.
2. Frame a plate on a flat table and fire the shutter (either mode).
3. Estimation refuses with "no surface / Use a flat surface" (`lidarFitDegenerate`).
4. On the error overlay, tap Retry or 2-view — nothing happens; Cancel works.

**Impact:** Total loss of the capture→estimate path on device — the MVP's core flow.
Blocked the research→main v0.1.0 merge.

## Investigation Summary

Device logs (`/tmp/medata-device.log`, archive at `/private/tmp/medata-device.logarchive`)
provided the discriminating evidence.

- **Symptoms examined:** `event=segmenter.mask` showed plausible coverage (0–34 %,
  `topClass=34` background) — the letterbox retrain HAD fixed the full-frame mask, ruling
  out the segmenter branch. Both failures logged
  `event=supportplane.end success=false failure=noLidarPoints candidates=1298 inliers=0`
  (1425 on the single-view attempt): RANSAC had ~1.3 k candidate points and found **zero**
  inliers across 256 iterations.
- **Code inspected:** `LiDARPlaneFitter.fit/ransac`, `Pipeline.fitSupportPlane`,
  `ARKitCaptureEngine.buildRawFrame`, `CaptureErrorOverlay`, `CaptureFlowView`,
  `ARPreviewView`, `CaptureFlowModel` command guards.
- **Hypotheses tested:**
  - *Full-frame mask (pre-retrain fault)* — ruled out by the coverage log line.
  - *Specular/marble surface killing ToF depth* — ruled out: 1298 candidates passed the
    confidence + positive-depth filters.
  - *Genuinely degenerate geometry* — impossible: any RANSAC iteration that survives the
    gates counts its own 3 sampled points as inliers, so `inliers=0` means **every**
    iteration was rejected before inlier counting. The only full-kill gate is the
    gravity-angle gate (±15° from `gravityCamera`).
  - *Dead buttons: model-state guard failing* — ruled out: Cancel shares the same
    `.refused` guard and worked. The log shows no `capture.start` after either failure, so
    Retry taps never reached the model; the mask-producer resuming 3–5 s after each
    failure marks the Cancel taps landing.

## Discovered Root Cause

**Bug 1 — world-frame constant passed as camera-frame gravity.**
`ARKitCaptureEngine.buildRawFrame` set `gravity = Vec3(0, -1, 0)` — a world-frame
constant — but `RawFrame.gravity` must carry world-up **in the §6.0 camera frame**
(pose-dependent). For a nadir capture the table normal in that frame is `(0, 0, 1)`
(along the optical axis), ~90° from the constant, so the fitter's gravity gate rejected
every candidate plane → `noLidarPoints` → surfaced as `lidarFitDegenerate`. The identity
pose is the trap: there, world-up in the §6.0 frame evaluates to exactly `(0, −1, 0)`
(the §6.0 projection frame flips Y relative to ARKit's rendering frame), which made the
constant look correct and kept `MockCaptureEngine`'s identity/(0,−1,0) fixture pairing
green.

**Bug 2 — AR preview wins UIKit hit-testing over the overlay's buttons.**
RealityKit's `ARView` is a real `UIView` with its own gesture recognisers; UIKit resolves
touches to it in the platform layer, where SwiftUI's `allowsHitTesting(false)`/`zIndex`
on the representable (the 3429ddc fix) are not reliable. Retry/2-view sit over the AR
view; Cancel, lower, landed outside its effective region. Additionally the pills'
`.frame(maxWidth:)/.contentShape` were applied **outside** `Button(...)`, which does not
extend a Button's internal tap gesture — the tappable area was only the text label.

**Defect type:** Coordinate-frame convention error (bug 1); platform-layer hit-testing /
SwiftUI Button hit-area misuse (bug 2).

**Why it occurred:** The gravity contract comment ("unit vector, camera frame") was
satisfied numerically at the identity pose only; nothing on macOS compiles or exercises
`ARKitCaptureEngine`, and all fitter tests construct gravity and geometry in the same
synthetic frame, so the mismatch could only ever appear on device. The 3429ddc button fix
addressed the right symptom at the wrong layer (SwiftUI instead of UIKit) and was not
re-verified on device before the retrain round.

**Contributing factors:** Scattered false-positive food pixels (3–6 % coverage across
~15 classes) make the food bbox span the full frame, collapsing the fitter's four scan
bands to 1-px border strips (`bboxW=1919 bboxH=1439` in the log). Not fatal once gravity
is fixed — border pixels are table on a nadir shot — but it shrinks the candidate pool
from ~2.7 M pixels to ~1.3 k and is worth watching if residual-gate failures appear.

## Resolution for the Issue

**Changes made:**
- `MedataCore/Sources/CaptureKit/CameraGravity.swift` (new) —
  `CameraGravity.worldUpInCameraFrame(worldFromCamera:)`: rotates world-up into the
  camera frame (`Rᵀ·e_y` = the y-components of the rotation columns) and flips Y into the
  §6.0 back-projection frame. Pure, portable, macOS-testable.
- `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift:246` — derive `gravity` from
  `cam.transform` via `CameraGravity` instead of the constant.
- `MedataCore/Sources/CaptureKit/RawFrame.swift:71` — sharpened the `gravity` doc comment
  (world-up, §6.0 camera frame, pose-dependent).
- `App/ARPreviewView.swift` — `arView.isUserInteractionEnabled = false`: the preview is
  render-only; opting it out of UIKit interaction routes all touches to SwiftUI chrome.
- `App/CaptureErrorOverlay.swift` — moved pill sizing/background/`contentShape` inside
  each `Button` label so the whole pill is the button's tap target (all three buttons).

**Approach rationale:** Smallest change that makes the deployed failure impossible at
both layers. The gravity conversion is a pure function so the convention is pinned by
executable tests despite the engine being iOS-only. Disabling UIKit interaction on the
AR view is categorical — no dependency on SwiftUI/UIKit hit-testing interplay.

**Alternatives considered:**
- *Use `CMMotionManager.deviceMotion.gravity`* (the engine already starts it, unused) —
  rejected: CoreMotion reports in the device frame, needing a second orientation-dependent
  conversion; `cam.transform` under `worldAlignment = .gravity` is already per-frame and
  authoritative.
- *Relax/remove the fitter's gravity gate* — rejected: the gate is spec (§6.2) and
  correct; it was doing its job on bad input.
- *Keep 3429ddc's SwiftUI-level hit-testing fixes as the only measure* — rejected:
  demonstrated ineffective on device; `zIndex`/`allowsHitTesting` on the representable
  were left in place as harmless belt-and-braces.

## Regression Test

**Test file:** `MedataCore/Tests/SupportPlaneTests/GravityFrameTests.swift`
**Test names:** `testIdentityPoseMatchesLegacyConstant`, `testNadirPoseGivesOpticalAxisUp`,
`testObliquePoseTiltsTowardImageTop`, `testFitterAcceptsConvertedGravityAndRejectsLegacyConstant`

**What it verifies:** the conversion at the three poses that matter (identity, nadir,
25° oblique), and the end-to-end failure mode — on a synthetic near-fronto-parallel
table the fitter succeeds with the converted vector and throws `noLidarPoints` (zero
inliers) with the legacy constant, mirroring the device log exactly.

**Run command:** `swift test --filter GravityFrameTests` (part of `make test`)

Note on TDD ordering: a literally-failing-first test isn't possible here — the defective
line lives in iOS-only code that `make test` cannot compile, and per the MVP test gate no
app-target suite is executable. The legacy-constant assertion is the executable proof of
the failure mode. Bug 2 is UI and is verified by build + on-device check per the project
test gate.

## Affected Files

| File | Change |
|------|--------|
| `MedataCore/Sources/CaptureKit/CameraGravity.swift` | New — world-up → §6.0 camera-frame conversion |
| `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` | Pose-derived gravity instead of constant |
| `MedataCore/Sources/CaptureKit/RawFrame.swift` | `gravity` contract comment clarified |
| `MedataCore/Tests/SupportPlaneTests/GravityFrameTests.swift` | New — regression tests |
| `App/ARPreviewView.swift` | `isUserInteractionEnabled = false` on the ARView |
| `App/CaptureErrorOverlay.swift` | Pill sizing moved inside Button labels |

## Verification

**Automated:**
- [x] Regression tests pass (4/4)
- [x] Full suite passes — XCTest 381 (3 skipped, 0 failures) + swift-testing 114
- [x] `make spell` clean; `make build-app` (iphoneos Debug) compiles

**Manual verification:**
- Pending: on-device Release capture (`make deploy-release`) — expect `supportplane.end
  success=true` and, on a forced failure, working Retry/2-view buttons. Match the fresh
  `buildStamp` in the launch log before trusting results.

## Prevention

**Recommendations to avoid similar bugs:**
- Any value crossing the ARKit→§6.0 boundary should go through a named, tested
  conversion in `CaptureKit` (as `SimdAdapter` does for matrices) — never an inline
  constant, even one that "matches" at a reference pose.
- Treat `supportplane.end candidates=N inliers=0` with N ≫ 3 as a convention/input bug,
  never a scene problem — RANSAC cannot score zero on real coplanar geometry.
- UIKit-backed views layered under SwiftUI controls should opt out of interaction at the
  UIKit level (`isUserInteractionEnabled`) when render-only; do not rely on
  `allowsHitTesting`/`zIndex` across the representable boundary.
- SwiftUI Buttons: sizing/shape must live inside the label to define the tap target.

## Related

- `specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/` — earlier fitter-side
  fix (four-edge band scan) and the debug counters that made this diagnosis possible.
- Commit `3429ddc` — letterbox retrain + first (ineffective) dead-buttons fix.
- `docs/agent-notes/ui-capture-flow.md`, `docs/agent-notes/device-build-and-test.md`.
- Follow-up watch item: full-frame food bbox from scattered false positives collapses
  candidate bands to the image border (see Contributing factors).

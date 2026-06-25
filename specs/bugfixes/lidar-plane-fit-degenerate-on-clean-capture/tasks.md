---
references:
    - specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/smolspec.md
    - specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/decision_log.md
---
# LiDAR Plane Fit Degenerate on Clean Capture — Tasks

- [x] 1. Pipeline.fitSupportPlane builds a centred-rectangle roughMask via a tested helper <!-- id:yzh4wgt -->
  - **Outcome:** A private/internal helper `makeCentreRectangleMask(width:height:fillFraction:)` exists in the `Pipeline` module (either as a fileprivate function in `Pipeline.swift` or a small new file under `MedataCore/Sources/Pipeline/`), returns a `BinaryMask` with `1` pixels in the centred rectangle defined by `fillFraction` and `0` pixels in the surrounding border. The all-ones roughMask construction at `MedataCore/Sources/Pipeline/Pipeline.swift:373-377` is replaced with a call to this helper using `fillFraction = 0.7`. A named constant for the fill fraction lives on the helper so it is discoverable and tunable.
  - **Approach:** introduce a constant `centreRectangleFillFraction: Float = 0.7` co-located with the helper. The helper accepts width and height (Int) and the fillFraction, validates 0 < fillFraction <= 1, and returns a `BinaryMask` whose pixel buffer is laid out row-major. Keep `LiDARPlaneFitter.Inputs` and `BinaryMask` APIs unchanged.
  - **Verification:** build the MedataCore Swift package; the existing `MedataCore/Tests/PipelineTests` suite still passes on the iPhone 17 Pro simulator. A quick `grep "repeating: 1, count:" MedataCore/Sources/Pipeline/Pipeline.swift` returns no hits (the old construction is gone). Unit-test coverage for the helper itself lands in task 2.
  - **References:** smolspec.md (Implementation Approach > Chosen fix), decision_log.md (Decision 1).

- [x] 2. Unit test pins the centre-rectangle helper's pixel layout <!-- id:yzh4wgu -->
  - **Outcome:** A new test file `MedataCore/Tests/PipelineTests/CentreRectangleMaskTests.swift` exercises `makeCentreRectangleMask` and asserts: (a) for `width=10, height=10, fillFraction=0.7`, the returned mask has `1` pixels exactly in the rectangle `[ceil(0.15*10), floor(0.85*10))` in both axes and `0` elsewhere; (b) the pixel buffer length equals `width * height`; (c) invalid `fillFraction` values (0, negative, >1) either trap precondition or return an empty/all-ones mask per a documented contract chosen in implementation.
  - **Approach:** use Swift Testing (`@Test`, `#expect`); add the test alongside existing Pipeline tests. No production-code changes outside what task 1 already produced.
  - **Verification:** `xcodebuild test -scheme MedataCore-Package -destination 'platform=iOS Simulator,name=iPhone 17 Pro,arch=arm64' -only-testing:PipelineTests/CentreRectangleMaskTests` passes.
  - **References:** smolspec.md (Implementation Approach > Verification), decision_log.md (Decision 1).
  - Blocked-by: yzh4wgt (Pipeline.fitSupportPlane builds a centred-rectangle roughMask via a tested helper)

- [x] 3. Regression test reproduces noLidarPoints under an all-ones mask and a successful fit under the centre-rectangle mask <!-- id:yzh4wgv -->
  - **Outcome:** A new test file `MedataCore/Tests/PipelineTests/SupportPlaneRoughMaskTests.swift` (or an existing PipelineTests file if a better home exists) contains two test cases over the same synthetic depth fixture: (a) calling `LiDARPlaneFitter.fit(_:)` with an all-ones `BinaryMask` throws `SupportPlaneError.noLidarPoints`, encoding the pre-fix behaviour as a regression sentinel; (b) calling it with the centre-rectangle mask produced by `makeCentreRectangleMask(width:height:fillFraction: 0.7)` returns a finite `SupportPlane` whose normal is within `gravityAngleMaxRad` of the synthesised gravity vector and whose `residualMm` is finite and below `LiDARPlaneFitter.residualMaxMm`. The synthetic depth fixture represents a plate (closer to the camera) surrounded by a flat table (further from the camera), with both regions having high confidence values.
  - **Approach:** build the synthetic `DepthMap`, `CameraIntrinsics`, `BinaryMask`, and `Vec3` gravity in helpers private to the test file. Mirror the fixture style of existing SupportPlane tests under `MedataCore/Tests/SupportPlaneTests/` if helpful. Do not modify production `LiDARPlaneFitter` code.
  - **Verification:** both new test cases pass on the simulator. The existing full `MedataCore` test suite (`xcodebuild test -scheme MedataCore-Package`) still passes.
  - **References:** smolspec.md (Root cause, Implementation Approach > Verification), decision_log.md (Decision 1).
  - Blocked-by: yzh4wgt (Pipeline.fitSupportPlane builds a centred-rectangle roughMask via a tested helper)

- [x] 4. DEBUG-only instrumentation logs candidate-point count and SupportPlaneError kind at the fitSupportPlane call site <!-- id:yzh4wgw -->
  - **Outcome:** When the app is built in Debug, a call to `Pipeline.fitSupportPlane` emits two events through `os.Logger(subsystem: "ie.medata.app", category: "Shutter")` (the same channel already used for `estimate.start` / `estimate.end` in `nextup.md`): one `event=supportplane.start` carrying the mask dimensions and fillFraction, and one `event=supportplane.end` carrying either `success=true` with the residual_mm and inlier count OR `success=false failure=<SupportPlaneError case>` plus candidate-point-count when known. Release builds emit nothing new.
  - **Approach:** gate the logging behind `#if DEBUG`. Source the candidate-point count by exposing a lightweight DEBUG-only static `LiDARPlaneFitter.lastCandidatePointCount` (or by returning a debug record alongside the SupportPlane in a DEBUG-only overload) — pick the simplest seam that does not change the production API. Keep the log lines short and structured (key=value, matching the existing event format).
  - **Verification:** build in Debug for the simulator; run any test that exercises the support-plane fit path; confirm via console capture or `os.Logger`-backed tests that the events are emitted. Release build still compiles with no new symbols leaked.
  - **References:** smolspec.md (Requirements: candidate-point logging; Implementation Approach > Affected files), decision_log.md (Decision 1 — Consequences > Positive).
  - Blocked-by: yzh4wgt (Pipeline.fitSupportPlane builds a centred-rectangle roughMask via a tested helper)

- [x] 5. On-device verification on iPhone 13 Pro Max captures a clean run and the bugfix report.md is finalised <!-- id:yzh4wgy -->
  - **Outcome:** A fresh device-log capture on iPhone 13 Pro Max iOS 26.5 from a normal meal capture (centred plate on table at ~30-40 cm, tilt near 0° at nadir, tilt near 25° at oblique) shows the `estimate.end` event with either `success=true` OR a different failure (`noFoodVolumeRecovered`, `noFoodPixels`, etc. — anything other than `lidarFitDegenerate`). A new file `specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/report.md` exists mirroring the structure of `specs/bugfixes/arview-session-config-race/report.md` (Description / Investigation Summary / Discovered Root Cause / Resolution / Regression Test / Affected Files / Verification / Prevention sections), with the captured device log embedded under Verification.
  - **Approach:** build and install the Debug variant on the device. Capture the device log via Xcode's Console window or `log stream --predicate 'subsystem == "ie.medata.app"'`. Author `report.md` from the smolspec, decision_log entries, and the captured log.
  - **Verification:** `report.md` is committed alongside the code change; the on-device log block shows no `failure=lidarFitDegenerate` lines.
  - **References:** smolspec.md (Implementation Approach > Verification, item 3), decision_log.md (Decision 1).
  - Blocked-by: yzh4wgt (Pipeline.fitSupportPlane builds a centred-rectangle roughMask via a tested helper), yzh4wgu (Unit test pins the centre-rectangle helper's pixel layout), yzh4wgv (Regression test reproduces noLidarPoints under an all-ones mask and a successful fit under the centre-rectangle mask), yzh4wgw (DEBUG-only instrumentation logs candidate-point count and SupportPlaneError kind at the fitSupportPlane call site)

## Re-open 2026-06-16 — real-mask path regresses the fit

After Decision 1's centre-rectangle helper was retired by `specs/estimation/pipeline-real-device-correctness/` and the real `PreShutterSegmenter` mask was wired through `CaptureResult.preShutterFoodMask`, on-device verification on PhoneMax (Double mode, build `288c5a7`) surfaced `lidarFitDegenerate` immediately after `event=supportplane.start ... source=pre_shutter`. Root cause + fix in smolspec.md (`## Re-open 2026-06-16`); rationale in `decision_log.md` Decision 2.

- [x] 6. `LiDARPlaneFitter.collectCandidatePoints` scans four edge bands around the food bbox <!-- id:bb3f201 -->
  - **Outcome:** `collectCandidatePoints` collects candidates from four bands (bottom, top, left, right) around the food bbox, each as thick as the bbox dimension perpendicular to it, clipped to image bounds. `BBox` gains a `widthPx` accessor mirroring `heightPx`. `LiDARPlaneFitter.Inputs`, `LiDARSupportPlaneFitter`, and `Pipeline.fitSupportPlane` are unchanged.
  - **Approach:** restructure the candidate loop to iterate four `(xRange, yRange)` regions. Reuse the existing `mask.isFood`, depth-confidence, and `zMm > 0` filters per pixel.
  - **Verification:** see task 7.
  - **References:** smolspec.md (`## Re-open 2026-06-16`), decision_log.md (Decision 2).

- [x] 7. Failing regression test fixates the fix <!-- id:bb3f202 -->
  - **Outcome:** A new XCTest case `testFitsCentredMaskWithBboxAtImageBottomEdge` in `MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterTests.swift` uses a 5°-tilted synthetic plane fixture and a food mask whose bbox extends to the image's last row. Pre-fix the fit throws `noLidarPoints`; post-fix it recovers the plane within 2° and 5 mm. Confirms the four-band scan picks up table pixels on the sides when the below-bbox band is starved.
  - **Approach:** extend the existing `centredFoodMask` helper usage; reuse `syntheticPlaneDepthMap`. No production fixtures needed.
  - **Verification:** `swift test --filter testFitsCentredMaskWithBboxAtImageBottomEdge` passes. Full `swift test` still passes (313/313 with 3 skipped; one new test added on top of the prior 312 + skipped baseline; `SupportPlaneRoughMaskTests` all-ones-mask sentinel from Decision 1 still throws `noLidarPoints`).
  - **References:** smolspec.md (`## Re-open 2026-06-16`), decision_log.md (Decision 2).
  - Blocked-by: bb3f201 (`LiDARPlaneFitter.collectCandidatePoints` scans four edge bands around the food bbox)

- [ ] 8. On-device verification on PhoneMax in Single AND Double modes <!-- id:bb3f203 -->
  - **Outcome:** A fresh device-log capture on iPhone 13 Pro Max iOS 26.5 from a centred-plate meal capture at ~30-40 cm shows `event=estimate.end success=true` (or a different, non-`lidarFitDegenerate` downstream failure) in BOTH `single_view_lidar` and `two_view_sfs` capture paths. The Double-mode trail in `nextup.md` `# LOGS` (build `288c5a7`) is the pre-fix baseline; the post-fix trail covers both modes.
  - **Approach:** rebuild for device after the four-band fix; install via `xcrun devicectl device install app`; capture logs via Console.app with subsystem `ie.medata.app`, category `Shutter`. Drive a Single-mode tap first, then a Double-mode tap.
  - **Verification:** the captured logs show `event=supportplane.start ... source=pre_shutter` followed by `event=supportplane.end success=true` (or no `event=supportplane.end` plus a downstream stage like `Segmentation` / `Volume` failing) — and `event=estimate.end success=false failure=lidarFitDegenerate` does NOT appear.
  - **References:** smolspec.md (`## Re-open 2026-06-16` → Out of scope notes single-mode trail).
  - Blocked-by: bb3f202 (Failing regression test fixates the fix)

- [ ] 9. Finalise report.md with the re-open and the post-fix on-device trail <!-- id:bb3f204 -->
  - **Outcome:** `specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/report.md` gains a `## Re-open 2026-06-16` section mirroring the existing report structure (Description / Root Cause / Resolution / Regression Test / Affected Files / Verification), embedding the post-fix on-device log block from task 8 under Verification, and flipping Status from "Fixed (automated); on-device verification pending" to "Fixed (real-mask path)" with both verification dates noted.
  - **Verification:** `report.md` updated; the Verification block contains the new on-device trail.
  - **References:** smolspec.md (`## Re-open 2026-06-16`), decision_log.md (Decision 2).
  - Blocked-by: bb3f203 (On-device verification on PhoneMax in Single AND Double modes)

---
references:
    - specs/shutter-blocked-feedback/smolspec.md
    - specs/shutter-blocked-feedback/decision_log.md
---
# Shutter Blocked Feedback

- [x] 1. LiveIndicatorBadge visibility and auto-hide policy live on LiveIndicatorModel <!-- id:f4inr0n -->
  - Lift `visible: Bool` and the auto-hide `Task` from `App/LiveIndicatorBadge.swift` onto `App/LiveIndicatorModel.swift`.
  - Expose `reveal()` (set visible = true, re-arm 5s hide timer) and `scheduleHide()` (cancel pending, sleep 5s, set visible = false).
  - Update `LiveIndicatorBadge` to render `model.visible` directly and route its existing onChange/onTap/onAppear hooks through the model methods.
  - Existing in-range auto-hide behaviour and the 48pt hit slop (Req §20.4 / §20.10) MUST be preserved.
  - Verify: build cleanly; add a Swift Testing case on `LiveIndicatorModel` that `reveal()` after `scheduleHide()` keeps `visible == true` and re-arms the hide task; confirm on attached device that the badge still auto-hides 5s after gates are met.

- [x] 2. ShutterButton routes disabled taps to a callback with haptic and accessibility trait <!-- id:f4inr0o -->
  - In `App/ShutterButton.swift`, add `var onBlockedTap: (() -> Void)? = nil` and `@State private var blockedTapCount: Int = 0`.
  - Replace `.disabled(!state.isInteractive)` with branching inside the button action: invoke `action()` when `state == .ready`; increment `blockedTapCount` then invoke `onBlockedTap?()` when `state == .disabled`; do nothing when `state == .capturing`.
  - Add `.sensoryFeedback(.warning, trigger: blockedTapCount)` so iOS fires the haptic on counter bump.
  - Add `.accessibilityAddTraits(state == .ready ? [] : .isNotEnabled)` to restore the VoiceOver trait dropped with `.disabled()`.
  - Drop the `guard state.isInteractive` in the press gesture so the press animation plays on `.disabled` taps; keep the gesture inert for `.capturing`.
  - Update `MeData/Tests/ShutterButtonTests.swift` so existing state→accessibilityValue assertions still pass; add coverage that the blocked-tap callback fires only for `.disabled` (not `.capturing`).

- [x] 3. CaptureFlowModel emits gating diagnostic on blocked + fired + pipeline-stage boundaries <!-- id:f4inr0p -->
  - Add a single private `Logger` constant on `App/CaptureFlowModel.swift` (subsystem `ie.medata.app`, category `Shutter`) and route all five new log sites through it.
  - Add `@MainActor func shutterBlockedTapped()` — (1) calls `indicators.reveal()`; (2) logs one `.info` line with `event=blocked` plus fields: `state` (name), `tiltDegrees`, `targetTilt` (0 or 25 depending on `firstFrame`), `tiltInRange`, `distanceCm` (or `"nil"`), `lidarCoveragePercent`, `supportsLiDAR`, `canShutter`, `flowTaskActive` (= `flowTask != nil`), `startTaskActive` (= `startTask != nil`). MUST NOT mutate state.
  - In the existing `shutter()` method, immediately after the `.ready` guard succeeds and before `beginCapture(...)`, log one `.info` line with `event=fired` plus the same gating snapshot fields PLUS the resolved `CaptureMode` and `CaptureStage`.
  - In `performFlow(stage:frozen:mode:)`, log `event=capture.start` (with `stage`) before `try await capture(stage:)`; log `event=capture.end` after with `success=true` and frame `width`/`height` on the happy path, or `success=false` with the error type name inside each existing catch branch.
  - In `runEstimation(captureResult:mode:retryStage:)`, log `event=estimate.start` on entry; log `event=estimate.end` with `success=true` plus `mealId` and `capturePath` on the success branch, or `success=false` plus the `EstimationFailure` case name on the refusal/error branches.
  - Mirror the `os` import pattern in `MedataCore/Sources/Pipeline/Pipeline.swift:9` but without the `#if DEBUG` gate.
  - Add Swift Testing cases to `MeData/Tests/CaptureFlowModelTests.swift` verifying: (a) `shutterBlockedTapped()` leaves `state` unchanged across `.initialising`, `.trackingLost`, and `.ready(out-of-range)`; (b) it causes `indicators.visible` to flip true when previously false. (Log emission itself is not asserted in tests — verified on device in task 5.)

- [x] 4. Wire CaptureFlowView call site and verify blocked-tap feedback on device <!-- id:f4inr0q -->
  - In `App/CaptureFlowView.swift:85`, change `ShutterButton(state: shutterState) { model.shutter() }` to also pass `onBlockedTap: { model.shutterBlockedTapped() }`.
  - Build and run on the attached device.
  - Verify on a tap of the **disabled** shutter: (a) warning haptic is felt; (b) `LiveIndicatorBadge` re-reveals if previously auto-hidden; (c) exactly one `event=blocked` line appears in Console.app under `subsystem == "ie.medata.app"` and category `"Shutter"` containing all required fields.
  - Confirm the diagnostic identifies which gate is failing (e.g. `tiltInRange=false`, or `distanceCm=…` outside 25–50 cm).
  - Confirm taps during `.capturing` produce no haptic and no log entry.
  - Update `MeData/Tests/CaptureFlowModelTabSelectionTests.swift` only if an existing test broke from the new wiring; otherwise leave unchanged.
  - Blocked-by: f4inr0n (LiveIndicatorBadge visibility and auto-hide policy live on LiveIndicatorModel), f4inr0o (ShutterButton routes disabled taps to a callback with haptic and accessibility trait), f4inr0p (CaptureFlowModel emits gating diagnostic on blocked + fired + pipeline-stage boundaries)

- [ ] 5. On-device verify the success path: tap fires, baseline estimation completes, result view appears <!-- id:f4inr0r -->
  - Goal: confirm that when gates ARE satisfied, the dev-stub baseline estimation (`Pipeline.makeForDevice` under `DEV_STUB_SEGMENTER`, per `App/App.swift:41`) completes end-to-end and the `ResultView` renders for both `CaptureMode.single` (if LiDAR available) and `CaptureMode.double`.
  - Pre-conditions: tasks 1–3 landed; app built and running on the attached device.
  - In Console.app, subscribe with predicate `subsystem == "ie.medata.app" && category == "Shutter"`.
  - Drive the happy path: hold the device level (tilt within ±5°) and at a working distance (LiDAR-equipped: 25–50 cm; non-LiDAR: ~30–40 cm), wait for the indicator badge to go green and the shutter to enable, then tap.
  - Expected log trail in order: `event=fired` → `event=capture.start stage=nadir` → `event=capture.end success=true` → (Double mode only: a second `event=fired`/`capture.*` pair for `stage=oblique` after the second tap) → `event=estimate.start` → `event=estimate.end success=true mealId=… capturePath=…`.
  - Expected UI: navigation pushes to `ResultView` showing total carbs and a confidence pill.
  - If `event=estimate.end success=false` appears with an `EstimationFailure` case, capture the case name (e.g. `noScaleAvailable`, `coverageInsufficient`) — that is the **actionable diagnostic** the user wanted. Open a follow-up Transit bug with the captured log trail; do NOT attempt to fix the failure in this smolspec.
  - If `event=estimate.start` is logged but no `event=estimate.end` appears within ~30s, the pipeline is hanging downstream of capture (candidate root cause: the `RawFrame.imageBytes` YCbCr → RGB issue described in the prior `pipeline-factory-parked` memory). Capture the trail and open a follow-up; do NOT attempt to fix in this smolspec.
  - Document the observed log trail and UI outcome in a short note appended to `specs/shutter-blocked-feedback/decision_log.md` under a new `## Verification Notes` section. This is a one-off field report, not a permanent decision — keep it under 20 lines.
  - Blocked-by: f4inr0q (Wire CaptureFlowView call site and verify blocked-tap feedback on device)

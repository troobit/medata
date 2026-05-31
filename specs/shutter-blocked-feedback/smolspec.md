# Shutter Blocked Feedback

## Overview

When the Photo-tab shutter is disabled because a gate is not satisfied (tilt out of range, distance out of range, AR session initialising, tracking lost), tapping it currently produces no feedback — the button is wrapped in `.disabled()` so SwiftUI swallows the touch. On the attached device this makes it impossible to tell which gate is blocking. This change makes a tap on a `.disabled` shutter re-surface the existing on-screen diagnostics (`LiveIndicatorBadge`), fire a warning haptic, and emit an `OSLog` entry with the current gating snapshot. Taps during `.capturing` remain inert (no haptic, no log) so a legitimate in-flight capture is not buzzed/spammed.

This change also adds symmetric observability to the **success path** — when a tap proceeds (`state == .ready`), an `OSLog` entry records the tap and the same gating snapshot, and pipeline-stage boundaries (capture start/end, estimation start/end, outcome) are logged. This lets the on-device tester confirm via Console.app that the baseline estimation (`Pipeline.makeForDevice` with the dev-stub segmenter under `DEV_STUB_SEGMENTER` per `App/App.swift:41`) actually completes when a correct photo is collected, rather than silently hanging or failing in a stage the user cannot see.

## Requirements

- The system MUST register a tap on the shutter even when the shutter is in a non-interactive state (`.disabled` or `.capturing`), without starting a capture.
- The system MUST fire a system warning haptic via `.sensoryFeedback(.warning, trigger:)` on a tap of the `.disabled` shutter.
- The system MUST NOT fire a haptic on a tap of the `.capturing` shutter (the capture is already in flight; feedback would be misleading).
- The system MUST re-show the auto-hidden `LiveIndicatorBadge` on a `.disabled` tap and re-arm its 5-second auto-hide timer. (Re-showing is a no-op when the badge is already on screen; on `.initialising` / `.trackingLost` the badge is not shown — the existing `initialisingHint` capsule in `CaptureFlowView.swift` already covers that case, so no new visible chrome is added.)
- The system MUST emit exactly one `OSLog` entry per `.disabled` tap (no entry for `.capturing` taps) recording: `CaptureState` name, tilt degrees, target tilt, tilt-in-range bool, distance cm (or "nil"), LiDAR coverage percent, `supportsLiDAR` bool, `canShutter` bool, `flowTaskActive` bool, `startTaskActive` bool. The log message MUST be tagged so it can be distinguished from the success-path entry below (e.g. `event=blocked`).
- The system MUST emit one `OSLog` entry under the same subsystem/category when an interactive tap proceeds (`event=fired`), with the same gating-snapshot fields plus the resolved `CaptureMode` and `CaptureStage` (nadir or oblique) for that tap.
- The system MUST emit `OSLog` entries at pipeline-stage boundaries inside `CaptureFlowModel.performFlow` / `runEstimation` for `event=capture.start`, `event=capture.end` (with success/failure tag and frame dimensions on success), `event=estimate.start`, and `event=estimate.end` (with success/failure tag and on success the `MealRecord.id` / capture path). These entries log only on the success path; the blocked-tap path never reaches them.
- The shutter MUST NOT allow a second capture from a rapid double-tap on `.ready` (Req §7.4 must continue to hold). The existing `state == .ready` guard inside `CaptureFlowModel.shutter()` is sufficient because both taps are dispatched on the same `@MainActor` and the first tap sets `state = .capturing` synchronously before returning; the spec retains this contract and tests cover it (`MeData/Tests/CaptureFlowModelTests.swift`).
- The system MUST set the SwiftUI `.isNotEnabled` accessibility trait on the shutter when `state` is not `.ready`, so VoiceOver still announces the disabled trait now that the `.disabled()` modifier has been removed. The existing `accessibilityLabel`, `accessibilityHint`, `accessibilityValue`, and `accessibilityIdentifier` SHALL be unchanged.
- The system MUST NOT change `CaptureState` as a result of a blocked tap.
- The system MUST preserve the existing press animation behaviour on every tap regardless of state (press animation already triggers on `.ready`; the spec extends it to fire on `.disabled` taps as well so the user sees the touch landed — Req §20.6 governs the metrics, not the gating).

## Implementation Approach

**Files to modify:**

- `App/ShutterButton.swift`
  - Replace `.disabled(!state.isInteractive)` with branching inside the button action: invoke the existing `action` when `state == .ready`, invoke a new optional `onBlockedTap: (() -> Void)?` only when `state == .disabled`, and ignore `.capturing` taps entirely.
  - Drop the `guard state.isInteractive` early-return in the press gesture so the press animation also plays on `.disabled` taps. Keep the gesture guard for `.capturing` (no press animation during an in-flight capture, matching today's feel).
  - Add `.accessibilityAddTraits(state == .ready ? [] : [.isNotEnabled])` to restore the trait that `.disabled()` was supplying.
  - Add a `@State private var blockedTapCount: Int = 0` and `.sensoryFeedback(.warning, trigger: blockedTapCount)`. Increment the counter inside the `.disabled` branch of the action before calling `onBlockedTap?()`. This keeps haptics on the view side; `CaptureFlowModel` stays free of `UIKit` imports.

- `App/CaptureFlowView.swift` — At the existing `ShutterButton(state: shutterState) { model.shutter() }` call site (`CaptureFlowView.swift:85`), add `onBlockedTap: { model.shutterBlockedTapped() }`.

- `App/CaptureFlowModel.swift` —
  - Add `@MainActor func shutterBlockedTapped()` that (1) calls `indicators.reveal()`, (2) writes the `event=blocked` diagnostic to a `Logger` (subsystem `ie.medata.app`, category `Shutter`, level `.info`) with the fields enumerated in Requirements. No state mutation.
  - In the existing `shutter()` method, immediately after the guard succeeds and before `beginCapture(...)`, emit one `event=fired` log entry on the same logger with the gating snapshot plus the resolved `CaptureMode` and `CaptureStage`.
  - In `performFlow(stage:frozen:mode:)`, log `event=capture.start` (with `stage`) before `try await capture(stage:)`, log `event=capture.end` after with `success=true` (and frame width/height) or `success=false` (and error type) inside the existing catch branches.
  - In `runEstimation(captureResult:mode:retryStage:)`, log `event=estimate.start` on entry and `event=estimate.end` with the outcome — success carries `mealId` and `capturePath`; refusal carries the `EstimationFailure` case name.
  - Use one private `Logger` constant on the model (e.g. `private let log = Logger(subsystem: "ie.medata.app", category: "Shutter")`); reuse it across all five log sites.

- `App/LiveIndicatorModel.swift` — Lift the indicator badge's visibility state onto the model. Replace the badge's `@State private var visible: Bool` and `@State private var autoHideTask: Task<Void, Never>?` with `var visible: Bool = true` on `LiveIndicatorModel` plus a non-observed `private var autoHideTask: Task<Void, Never>?`. Add `func reveal()` (set `visible = true`, re-arm the hide timer) and `func scheduleHide()` (cancel any pending task, sleep 5 s, set `visible = false`). The reveal/hide policy is model state — `LiveIndicatorBadge` now only renders, it no longer owns timing.

- `App/LiveIndicatorBadge.swift` — Read `model.visible` instead of the local `@State`. Replace the three internal callers of `showAndScheduleHide()` / `scheduleHide()` with `model.reveal()` / `model.scheduleHide()`. The view's `.onChange(of: allInRange)`, `.onChange(of: isReady)`, and `.onTapGesture` hooks remain but now drive the model. Remove the `.onDisappear` task-cancel (the model owns the task).

**Existing patterns leveraged:**

- `MedataCore/Sources/Pipeline/Pipeline.swift:9` already imports `os`; the same pattern (subsystem `ie.medata.…`) is reused with a new category. No `#if DEBUG` gate — these are user-triggered point events, not per-frame instrumentation, and the diagnostic is the whole point of this change.
- `LiveIndicatorBadge` already centralises "reveal + re-arm hide" inside one private helper; this change just relocates the helper onto the model so other code paths (a blocked-shutter tap) can call it without a `Binding` ceremony.
- `CaptureFlowModel` is already the single owner of `indicators` and `CaptureState`; the new method belongs next to `shutter()`.

**Out of Scope:**

- Changing any gating thresholds (`canShutter`, tilt tolerance, distance window).
- Adding a new visible "reason" label/banner near the shutter (Req §7.3).
- Auto-capture / hands-free triggering.
- Modifying the refusal-sheet path (`.refused` state — that already has its own retry surface and is not reached via the shutter button).
- Adding haptics on any other control (capture-mode pill, retry button, etc.).
- Changes to shutter accessibility identifiers.
- Tracking elapsed-time-in-state on `CaptureFlowModel` to diagnose hung `flowTask` / `startTask` lifetimes. The `flowTaskActive` / `startTaskActive` booleans in the log payload distinguish "gated" from "in-flight"; an elapsed-time field would require routing every `state = …` assignment through a setter and is deferred to a follow-up if the booleans prove insufficient.
- **Fixing a broken baseline estimation pipeline.** This change only adds observability to the success path so the on-device tester can see where a tap ends up. If the new logging surfaces an estimation hang or refusal that masquerades as "shutter does not work," that is a separate bug (likely in `Pipeline.makeForDevice` / dev-stub segmenter / `RawFrame` YCbCr handling) to be filed and addressed in its own spec.
- Adding signposts or Instruments-visible intervals. The existing `Pipeline` `OSSignposter` (`MedataCore/Sources/Pipeline/Pipeline.swift:19`) covers Instruments; the new entries here are point-event logs for Console.app diagnosis only.

## Risks and Assumptions

- **Risk: Removing `.disabled()` changes VoiceOver behaviour.** Mitigation: explicit `.accessibilityAddTraits(.isNotEnabled)` when `state != .ready`. Validate the announcement ("Capture meal, dimmed") on device with VoiceOver before merging.
- **Risk: Lifting `visible` and `autoHideTask` onto `LiveIndicatorModel` widens the model's surface and forces a `@MainActor` annotation on the badge's lifecycle.** Mitigation: `LiveIndicatorModel` is already `@MainActor` and `@Observable`; adding a `Bool` and a `Task` field is type-safe and the existing tests for the badge (if any) read state machine helpers from `LiveIndicatorBadgeState` which are unchanged.
- **Risk: The new `Logger.info` line is too verbose if the user mashes the shutter.** Mitigation: `.info` is below the persistent-log threshold; a tester subscribes via `log stream --predicate 'subsystem == "ie.medata.app"'` during diagnosis. If subjective testing shows it's still noisy, debounce in `shutterBlockedTapped()` (≤ once per 500 ms) as a follow-up.
- **Assumption: The shutter-tap-to-busy-state-visible 100 ms latency budget (Req §14.3) is unaffected** — the blocked branch is additive and never runs on the `.ready` path.
- **Assumption: The user's reported "shutter not allowing photos" failure mode is gating-driven** (tilt, distance, or AR init). If the OSLog output shows `canShutter == true` but a tap still does nothing, that's a distinct bug (likely in `flowTask` / `startTask` lifecycle) — out of scope here, but the diagnostic this change adds is what will diagnose it.
- **Assumption: The baseline estimation path (`Pipeline.makeForDevice` with `DEV_STUB_SEGMENTER`) completes when given a real `RawFrame` from `ARKitCaptureEngine`.** The dev-stub segmenter does not require a `.mlpackage`; it stamps `segmenterSource = "dev_stub"`. If the success-path logs show `event=estimate.start` without a matching `event=estimate.end`, that indicates a hang somewhere downstream of capture (possibly the long-standing `RawFrame.imageBytes` YCbCr → RGB issue if the dev stub turns out to read pixels). That diagnostic outcome is the actionable signal; the fix is out of scope here.
- **Prerequisite: The Photo tab is reachable and the AR preview renders.** Already true on the attached device per the user's report.

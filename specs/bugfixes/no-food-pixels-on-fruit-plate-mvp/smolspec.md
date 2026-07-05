# No Food Pixels Refusal On Fruit Plate Double-Mode Capture

## Overview

On 2026-06-14, the `shutter-blocked-feedback` task-5 device verification (iPhone 13 Pro Max iOS 26.5, Debug-iphoneos build off `research` @ fdeab9d) produced an unexpected outcome: a double-mode capture of a fruit plate completed both nadir and oblique frames, but estimation refused with `failure=noFoodPixels` and `event=estimate.start maskAgeMs=-1`. The `maskAgeMs=-1` sentinel means no pre-shutter mask reached the pipeline, so the segmentation-derived food-pixel count was zero. This smolspec restores the contract that a non-nil `PreShutterSegmenter.latest` published before shutter-tap reaches `CaptureResult.preShutterFoodMask` at `Pipeline.estimate` time — closing the App-layer handoff gap surfaced by the diagnostic added by `shutter-blocked-feedback`.

Investigation across the 2026-06-14 and 2026-06-15 device sessions surfaced **two independent bugs** in the App-layer pre-shutter mask pipeline. Both must be fixed for the MVP closeout in Single AND Double modes:

1. **Lost-age across nadir → oblique stash** (`App/CaptureFlowModel.swift:481-484`) — fix applied 2026-06-15, proven by regression test, currently uncommitted on this branch.
2. **`PreShutterSegmenter` cadence stall** — the producer publishes ONE mask per `resume(frames:)` then idles for seconds. Every shutter tap consequently catches a mask older than 750 ms, `nadirMaskAgeMs` collapses to `nil` upstream of the lost-age propagation, and the lost-age fix has nothing to forward.

Bug 1's regression tests pass against an in-process spy; bug 2 only manifests with a live `ARSession` and is invisible to the SwiftPM test suite. Closing this spec therefore requires on-device verification of BOTH modes after bug 2 is fixed.

## Evidence — observed log trail

Captured 2026-06-14, iPhone 13 Pro Max iOS 26.5, Debug-iphoneos build off `research` @ fdeab9d, mode=double, fruit plate at ~40 cm.

```
event=fired state=ready tiltDegrees=4.6 targetTilt=0 tiltInRange=true distanceCm=39.5 lidarCoveragePercent=90.3 supportsLiDAR=true canShutter=true flowTaskActive=false startTaskActive=true mode=double stage=nadir
event=capture.start stage=nadir
event=capture.end stage=nadir success=true width=1920 height=1440
event=fired state=ready tiltDegrees=3.5 targetTilt=25 tiltInRange=false distanceCm=39.9 lidarCoveragePercent=88.7 supportsLiDAR=true canShutter=true flowTaskActive=true startTaskActive=true mode=double stage=oblique
event=capture.start stage=oblique
event=capture.end stage=oblique success=true width=1920 height=1440
event=estimate.start capturePath=two_view_sfs
event=estimate.start maskAgeMs=-1
event=pipeline.stage.start name=CardDetection
event=carddetect.end success=false cornerCount=0 latencyMs=29
event=pipeline.stage.start name=SupportPlane
event=supportplane.start width=1920 height=1440 source=pre_shutter
event=estimate.end success=false failure=noFoodPixels
```

Expected: `event=estimate.end success=true` and navigation to `ResultView`.
Observed: refusal with `failure=noFoodPixels`, preceded by `maskAgeMs=-1` despite a clearly food-bearing scene.

## Requirements

### Lost-age (bug 1)

- The system MUST cause `CaptureResult.preShutterFoodMask` to be non-nil when (a) the `PreShutterSegmenter` has published at least one mask before the shutter-tap, and (b) that publication is within the existing 750 ms staleness window at the nadir-capture instant.
- The system MUST emit `event=estimate.start maskAgeMs=N` with `N >= 0` whenever a mask is attached, for both single-view and double-mode captures.
- The system MUST propagate the nadir-instant mask age through the double-mode stash so the oblique-tap `CaptureResult` carries the same non-negative age recorded at the nadir tap, not a fresh-but-nil value.

### Cadence (bug 2)

- The `PreShutterSegmenter` MUST publish at a sustained cadence of ≥ 2 Hz from the moment `resume(frames:)` is called until `pause()` or `awaitPaused()` is called, as long as the underlying `ARKitCaptureEngine` is delivering frames at its normal ~60 Hz cadence.
- For a shutter tap arriving ≥ 1 second after the most recent state-entry into `.ready`, the system MUST find a `PreShutterSegmenter.latest` mask younger than 750 ms (i.e. the staleness gate at `App/CaptureFlowModel.swift:477` MUST pass).
- The fix MUST keep the public `PreShutterMaskSource` contract (`latest`, `pause`, `awaitPaused`, `resume`) byte-identical so the existing snapshot-atomicity tests (Decision 13) and the staleness-gate tests in `MeData/Tests/CaptureFlowModelPreShutterTests.swift` continue to pass unmodified.
- The fix MUST preserve "latest-wins" semantics: when the inference cycle takes longer than the inter-frame interval, intermediate frames are dropped rather than queued.

### Contract preservation (both bugs)

- The system MUST preserve the existing `PreShutterSegmenter.latest` "value survives `pause()`" contract (`App/PreShutterSegmenter.swift:66`) and the 750 ms staleness ceiling.
- The system MUST NOT change the `CaptureResult` shape (`MedataCore/Sources/Pipeline/CaptureResult.swift`), the `RawFrame` shape, or the Pipeline → `SupportPlaneFitter` routing (already covered by `MedataCore/Tests/PipelineTests/PreShutterMaskRoutingIntegrationTests.swift`).
- The system SHOULD remain compatible with both the `DEV_STUB_SEGMENTER` (Phase 1 Debug) and `CoreMLInferenceEngine` (Phase 3 Release) inference paths without per-engine special-casing.

## Implementation Approach

### Bug 1 (lost-age) — diagnosed and fixed

The bug lived in the App-target handoff between `App/PreShutterSegmenter.swift` and `App/CaptureFlowModel.swift`. The Pipeline-side routing from `CaptureResult.preShutterFoodMask` to `SupportPlaneFitter.fit` is byte-identically covered by the existing integration test (`MedataCore/Tests/PipelineTests/PreShutterMaskRoutingIntegrationTests.swift:18`), so the fix scope was the App layer only. See `## Root cause (lost-age)` and `## Fix (lost-age)` below for the diagnosed mechanism (lost age across the nadir → oblique stash) and the applied fix. Regression tests A (single-view) and B (double-mode oblique stash) in `MeData/Tests/CaptureFlowModelPreShutterTests.swift` lock the contract.

### Bug 2 (cadence) — three ranked hypotheses to disambiguate on-device

The producer's `for await frame in frames` loop publishes exactly one mask per `resume(frames:)` invocation, then goes silent until the next state transition triggers a fresh `resume()`. Observed pattern: ~1 publication per state-transition-into-`.ready` versus the design's ≥ 2 Hz sustained cadence. See `## Verification attempt 2026-06-15` for the trail and the cadence table.

The fix is App-layer only; investigation MUST distinguish the three hypotheses before any non-instrumentation code edit. Each is testable with `.info` log lines on a throwaway branch — rebuild, install, capture one trail, read the cadence, decide.

1. **`engine.frames` continuation registration races `session(_:didUpdate:)` callback.** `ARKitCaptureEngine.frames` (`MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift:111-125`) registers `frameContinuations[id] = cont` via `stateQueue.async`, returning the stream before registration completes. If `session(_:didUpdate:)` (line 182) fires on `stateQueue` BEFORE the registration block, that frame yields to an empty map. After registration completes, subsequent yields find the continuation — so this hypothesis explains a missed-first-frame, NOT a publishes-once-then-silent. Rule out cleanly by counting yields on the engine side and consume events on the segmenter side.
2. **`bufferingNewest(1)` + slow consumer interaction silently drops subsequent yields.** While the for-await is suspended awaiting the first frame's `segmenter.segment(_:)` call (~700 ms latency in the dev-stub), `ARKitCaptureEngine.session(_:didUpdate:)` fires ~42 times. Each yield with `bufferingNewest(1)` is documented to overwrite the buffered item, but if the continuation enters a "delivering" state where the producer holds the resumption point and overwrites are silently lost until the consumer next iterates, all 42 intermediate yields could be dropped AND no resumption ever happens. The fix would be to drop the buffering policy and roll a hand-managed "latest-frame" channel (a `Mutex<ARFrame?>` plus an explicit `Continuation` resume on every set), or to switch to a polling model that reads `engine.frames.first(where:)` each iteration.
3. **`makeRawFrame` silently returns nil for every frame after the first.** Lowest probability. `PixelBufferAdapter.convert` requires a valid `CVPixelBuffer`; ARKit owns the pool. If pool exhaustion under bufferingNewest(1) backpressure invalidates buffers, conversion returns nil and the loop falls into a silent `continue` cycle. Rule in/out by logging at `makeRawFrame` entry and at the post-convert guard.

Investigation order: instrument all three, capture one device trail, diagnose. Instrumentation MUST be removed before commit; the fix MUST keep the public `PreShutterMaskSource` contract byte-identical.

A `## Root cause (cadence)` paragraph and a `## Fix (cadence)` paragraph MUST be appended to this file once the device-trail investigation identifies which mechanism(s) fired.

## Out of scope

- Changes to `CaptureResult`, `RawFrame`, or `Pipeline.estimate` (Pipeline-side mask handling is already correct per the existing integration test).
- Changes to the 750 ms staleness threshold or the `PreShutterSegmenter.latest` "value survives `pause()`" contract. Bumping the threshold to "fix" the cadence symptom is explicitly forbidden — a stale mask reaching the pipeline degrades the food-region-coverage estimate silently; the cadence bug is the real fix.
- Changes to the dev-stub vs CoreML inference selection (`DEV_STUB_SEGMENTER`).
- Changes to the public `PreShutterMaskSource` protocol surface (`latest`, `pause`, `awaitPaused`).
- Downstream pipeline behaviour after the mask reaches `Pipeline.estimate` — including the `event=carddetect.end success=false cornerCount=0` line in the observed trail, which is the card-detection stage's expected behaviour for a fruit plate without a calibration card.
- Wording/format changes to the `event=estimate.start` log line beyond the contract that `maskAgeMs` reflects a real measurement when a mask is attached.
- Pre-existing diagnostic events listed in `pipeline-real-device-correctness/design.md` Logging table beyond their cadence guarantee; the cadence fix verifies the existing `event=preshutter.mask.update` line's emission rate, it does not redesign the event.

## Risks and Assumptions

- **Risk**: the `segmenter.substage.*` lines noted in the observation report may have come from the in-shutter `Pipeline.estimate` segmentation pass rather than the pre-shutter producer. If so, the producer may never have published in the failing session at all. **Mitigation**: the bug-1 unit-test investigation drove a `PreShutterMaskSource` spy whose `latest` was set to a known timestamped mask and asserted against the resulting `CaptureResult`, so the bug-1 fix is anchored to the contract that "a published mask reaches estimation" regardless of whether the field producer was publishing. The bug-2 investigation closes that gap by verifying real-world cadence on-device.
- **Risk**: the cadence-diagnostic instrumentation (task 4) emits `.info`-level log lines on a per-frame basis (60 lines/sec). On long sessions this can fill Console's buffer and slow log streaming. **Mitigation**: keep instrumentation on a throwaway branch within this PR's scope; remove it in task 6 before commit. Cap session length to ~30 s during diagnosis runs.
- **Risk**: if the cadence fix replaces `bufferingNewest(1)` with a hand-rolled latest-frame channel (H2 fix), the new code path is unique to `ARKitCaptureEngine.frames` and has no test harness (the SwiftPM target can't instantiate ARKit). **Mitigation**: keep the channel implementation small and inspect-only, with cross-references to the design's "PreShutterSegmenter — bufferingNewest(1)" rationale (`pipeline-real-device-correctness/design.md`); add an XCTest-free unit test that drives the channel directly with synchronous yields.
- **Risk**: if the chosen bug-1 fix changes `awaitPaused()` semantics from cancel-then-await to drain-then-await, downstream callers that rely on prompt cancellation (e.g. tab-switch / interruption paths) may stall longer than expected. **Mitigation**: bound any drain by the existing 750 ms staleness ceiling so the worst-case `awaitPaused()` latency cannot exceed it. (Bug 1 was diagnosed as the lost-age mechanism; `awaitPaused()` was not modified.)
- **Assumption**: under `DEV_STUB_SEGMENTER` (Phase 1 Debug — the build used on-device today), `StubInferenceEngine` reliably emits a centred-ellipse food region (`MedataCore/Tests/SegmentationTests/StubInferenceEngineTests.swift`), so an attached mask will have > 0 food pixels. If this is wrong, the fix won't change the refusal outcome.
- **Prerequisite**: the rerun of `shutter-blocked-feedback` task 5 per `nextup.md` step 7 will observe `event=estimate.start maskAgeMs=N` with `N >= 0` and `event=estimate.end success=true` in BOTH Single and Double modes. That two-mode observation is the closeout signal for this smolspec.

## Root cause (lost-age)

Suspect mechanism 2 of the bug-1 Implementation Approach — "Lost age across the nadir → oblique stash." A unit-test investigation against `App/CaptureFlowModel.swift:481-484` confirmed that on a double-mode oblique-stage tap, the `else` branch of the mask-snapshot block read `firstFrameMaskBox` back from the nadir stash but unconditionally set `nadirMaskAgeMs = nil`, because the age stamped at the original nadir tap was never paired with the mask box in the stash. Consequently every double-mode oblique `CaptureResult` arrived at `Pipeline.estimate` with `preShutterMaskAgeMs == nil`, which `Pipeline.swift:82` collapses to the `maskAgeMs=-1` sentinel. On the failing 2026-06-14 device run the segmentation-derived food-pixel count therefore short-circuited to zero before any food pixels could be counted, surfacing as `failure=noFoodPixels`. Suspect mechanism 1 (state-transition race in `pause()` / `awaitPaused()`) was not implicated: the unit-test spy keeps `latest` populated regardless of `pause()`, so the race contract (Decision 13) holds independently of this bug.

## Fix (lost-age)

Added a paired `firstFrameMaskAgeMs: Int?` field on `CaptureFlowModel` next to the existing `firstFrameMaskBox`. At the nadir-stash branch of `performFlow` (`stage == .nadir, mode == .double`), the age computed against the 750 ms staleness ceiling is stashed alongside the box. On the oblique tap, the snapshot block's third arm now reads the paired `firstFrameMaskAgeMs` back into `nadirMaskAgeMs` instead of resetting to `nil`. The field is cleared in lockstep with `firstFrameMaskBox` at every existing lifecycle site (`tryAgain` nadir-retry, `dismissResult`, `dismissRefusal`, `scenePhaseChanged(.background)`, `tabSelectionChanged(to: nonPhoto)` × 3 arms, `trackingDegraded`, `handleInterruption(.began)`, post-estimation cleanup) so the lifecycle table in Decision 11 stays internally consistent. No changes to `CaptureResult`, `RawFrame`, `Pipeline`, the staleness ceiling, or the `PreShutterSegmenter` contract.

## Verification attempt 2026-06-16 — H4 identified

Build: `aba6427` (cadence-diagnostic instrumentation on top of lost-age fix). Installed via `xcrun devicectl device install app` on iPhone 13 Pro Max iOS 26.5 (devicectl UDID `<device-udid>`). Mode tested: `double`, 6 nadir-oblique cycles over ~22 seconds (Console.app `Process: MeData` + `Category: Shutter`, Include Info + Debug enabled).

Observed evidence rules in H1, H2, H3 out and surfaces H4:

- `event=preshutter.engine.frames.registered count=N` and `event=preshutter.engine.session.yielded count=N` agreed on `N` after every registration — rules out **H1** (registration race).
- After every `frames.registered`, the producer logged ONE `event=preshutter.loop.iter` + `event=preshutter.makeRawFrame.convertOK` + the segmenter substage triplet (preprocess → inference → postprocess) — rules out **H2** (yields silently dropped: the producer iterated and consumed one frame fine) and **H3** (`makeRawFrame` nil after first frame: convertOK fired with `width=1920 height=1440`).
- No subsequent `event=preshutter.loop.segmentOK` nor `event=preshutter.loop.segmentNil` ever fired in any cycle. The loop body silently returned between `segmenter.segment(raw)` and the success/fail logs. The only path out is the `guard !Task.isCancelled` after segmenter return.
- `frames.registered count=N` grew monotonically across the session: 3 → 4 → 5 → 6 → 7 → 8, ending with ARKit emitting `delegate is retaining 11 ARFrames` at `00:40:44.384`.

## Root cause (cadence)

Two interacting App-layer bugs in `App/PreShutterSegmenter.swift`, taken together call them **H4**:

1. **Subscription leak**: `ARKitCaptureEngine.frames` returns a fresh per-subscriber `AsyncStream` on every access. `PreShutterSegmenter.resume(frames:)` is called from `CaptureFlowView.onChange(of: shouldProducePreShutter)` on every state-transition into a producing state, and `engine.frames` is invoked inline at each call — a brand-new AsyncStream + continuation each time. The continuations are registered in `engine.frameContinuations` keyed by UUID; the stream's `onTermination` (line 119 of `ARKitCaptureEngine.swift`) is the only path that removes them, and is not reliably triggered by `Task.cancel()` on the iterating Task. Result: continuations accumulate over the session. Each holds one buffered ARFrame via `bufferingNewest(1)`, eventually hitting ARKit's ~10-frame retention ceiling.
2. **Mid-segment cancel**: `pause()` (called on state-transition out of `.ready`) executes `inflight?.cancel()`. The inflight Task may be suspended inside `try? await segmenter.segment(raw)` (a ~1-second CoreML / dev-stub cycle on this device). Cancellation propagates to the segmenter which throws `CancellationError`; `try?` swallows to nil; the very next line is `guard !Task.isCancelled else { return }` — the Task returns silently. `publish()` never runs. `latest` stays nil for that whole resume cycle. Since every state-transition fires the cancel before the segmenter completes, the producer publishes **zero** masks per session, regardless of cycle count.

Together: every double-mode oblique tap reads `producer.latest == nil`, `nadirMaskAgeMs` collapses to nil, `Pipeline.estimate` sees `maskAgeMs=-1`, `SupportPlaneFitter` short-circuits to `noFoodPixels`. The lost-age fix from bug 1 is correct but had no published mask to forward.

## Fix (cadence)

Three structural changes in `App/PreShutterSegmenter.swift` only — public `PreShutterMaskSource` contract (`latest`, `pause`, `awaitPaused`, `resume`) byte-identical.

1. **Cache the ARFrame stream** on the first `resume(frames:)` call (`cachedStream: AsyncStream<ARFrame>?`); subsequent `resume()` calls reuse the cached stream rather than calling `engine.frames` for a fresh subscription. Net: at most one producer subscription per app lifetime, so `frameContinuations` count is bounded by `(UI overlays) + 1`. The leak is gone.
2. **Replace `inflight?.cancel()` with a fire-and-forget `isPaused = true` flag**. The for-await body checks `isPaused` AT THE TOP of each iteration on MainActor; if paused, the iteration drops the frame (no makeRawFrame, no segment, no publish) and goes back to await the next frame. The AsyncStream keeps draining at full cadence — no stale buffered frames — but no work is done while paused. The Task lives forever once started; pause/resume only toggles the gate.
3. **Drain-aware `awaitPaused()`**: an `inflightSegmentCycles` counter is incremented on MainActor before `segmenter.segment(raw)` and decremented on MainActor inside a new `finishSegmentCycle(result:latencyMs:)` method that ALSO performs the publish. If `awaitPaused()` is called while a cycle is in flight, it suspends on a `CheckedContinuation` that `finishSegmentCycle` resumes after the publish completes. Decision 13's "no writes after `awaitPaused()` returns" invariant is preserved exactly — and now the cycle's publish actually completes (no cancel cuts it off).

Result: each `.ready` window produces 1-2 published masks (one segmenter cycle ≈ 1.5 s on iPhone 13 Pro Max with the dev-stub). `producer.latest` is fresh before every shutter tap. Double-mode oblique stash sees `nadirMaskAgeMs` non-nil. `Pipeline.estimate` sees `maskAgeMs` in `[0, 750]`. `SupportPlaneFitter` sees a populated mask and proceeds past `noFoodPixels`.

## Verification attempt 2026-06-15 — BLOCKED on deeper bug

Build: `research` @ `a349118` + uncommitted lost-age fix on branch `no-food-pixels-on-fruit-plate-mvp`. Installed on iPhone 13 Pro Max iOS 26.5 (devicectl UDID `<device-udid>`, bundle `rtob.MeData`). Mode tested: `double` twice. Outcome: same refusal trail as the 2026-06-14 baseline — `event=estimate.start maskAgeMs=-1` followed by `event=estimate.end success=false failure=noFoodPixels`. Per nextup.md step 4 classification rule ("Same refusal ⇒ stop and report, do not iterate blind"), verification halted.

Observed trail (oblique tap from run 1, abbreviated):

```
11:12:41.686  event=fired ... mode=double stage=nadir
11:12:41.700  event=capture.start stage=nadir
11:12:41.782  event=capture.end stage=nadir success=true
11:12:45.390  event=fired ... mode=double stage=oblique
11:12:45.402  event=capture.start stage=oblique
11:12:45.475  event=capture.end stage=oblique success=true
11:12:45.476  event=estimate.start capturePath=two_view_sfs
11:12:45.476  event=estimate.start maskAgeMs=-1            ← still -1 with the fix applied
11:12:45.508  event=supportplane.start width=1920 height=1440 source=pre_shutter
11:12:45.510  event=estimate.end success=false failure=noFoodPixels
```

Diagnosis (from `event=segmenter.substage.start` cadence in the same trail): the lost-age fix is correct and necessary, but it is upstaged by a deeper bug — **`PreShutterSegmenter` publishes exactly one mask per `resume(frames:)` invocation, then goes idle until the next state-transition-into-`.ready` re-`resume()`s the producer**. Observed pattern across 4 producer cycles in the user's session:

| Cycle | Preprocess | Postprocess | Trigger |
| --- | --- | --- | --- |
| 1 | 11:12:35.667 | 11:12:36.359 | initial `onAppear` or post-launch resume |
| 2 | 11:12:41.819 | 11:12:42.834 | post-nadir-capture state → `.ready` |
| 3 | 11:12:48.448 | 11:12:49.837 | post-`estimate.end` (refused) → `.ready` |
| 4 | 11:12:52.948 | 11:12:54.562 | post-second-nadir-capture state → `.ready` |

Expected per `pipeline-real-device-correctness/design.md` Logging section: ≥ 2 publications per second sustained. Observed: ~1 publication per state transition. Between cycles 1 and 2, the producer was idle for 5.46 s; between cycle 4 and the second oblique tap (`11:12:59.407`), idle for 4.85 s. Every tap consequently misses the 750 ms staleness ceiling at `App/CaptureFlowModel.swift:477`, so `nadirMaskAgeMs` collapses to `nil` *before* the lost-age fix has anything to propagate.

Confirming evidence the lost-age fix code is on-device: the build at `a349118` + local changes was installed via `xcrun devicectl device install app --device <device-udid> …/Debug-iphoneos/MeData.app` and `xcodebuild` reported `** BUILD SUCCEEDED **` for the `iPhoneOS` destination. `swift test` baseline on `MedataCore` is unchanged (312 + 0 failures, 3 skipped + 16 swift-testing tests in 5 suites).

## Followups

(All cadence followups previously listed here have been pulled in-scope; the cadence work is now bug 2 of this spec, covered by tasks 4–7 of `tasks.md`. The single-mode-also verification requirement is folded into task 8.)

- **Decision-log entry for the cadence-fix mechanism** — once the on-device trail (task 5) identifies which of H1/H2/H3 fired, append a short ADR-format note to the appropriate decision log (this spec's directory has no `decision_log.md` today; if the fix touches `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift`, link it from `specs/estimation/pipeline-real-device-correctness/decision_log.md` as a Status: superseded clarification on the existing `bufferingNewest(1)` decision).

## Verification attempt 2026-06-16 — mask contract met, blocked on `lidarFitDegenerate`

**Build**: HEAD `288c5a7` (lost-age fix + cadence fix, diagnostics stripped). Device: iPhone 13 Pro Max (iOS 26.5, UDID `<device-udid>`). Mode: Double. Single-mode trail still owed.

Filtered Console trail (OS framework chatter removed; only the app's `event=` and `segmenter.substage` lines kept):

```
01:13:26.689  event=fired state=ready tiltDegrees=5.6 targetTilt=25 tiltInRange=false distanceCm=45.2 lidarCoveragePercent=87.9 supportsLiDAR=true canShutter=true mode=double stage=oblique
01:13:26.705  event=capture.start stage=oblique
01:13:26.771  event=capture.end   stage=oblique success=true width=1920 height=1440
01:13:26.771  event=estimate.start capturePath=two_view_sfs
01:13:26.772  event=estimate.start maskAgeMs=170
01:13:26.772  event=pipeline.stage.start name=CardDetection
01:13:26.804  event=pipeline.stage.start name=SupportPlane
01:13:26.804  event=supportplane.start width=1920 height=1440 source=pre_shutter
01:13:27.505  event=estimate.end success=false failure=lidarFitDegenerate
```

**This spec's contract is met**:
- `maskAgeMs=170` — fresh, well inside the 750 ms staleness gate (cadence fix [bug 2] holding).
- `noFoodPixels` refusal **resolved**: the pre-shutter mask now reaches `Pipeline.estimate` via `source=pre_shutter` (lost-age fix [bug 1] holding).

**Different-refusal blocker** per task 8's rule ("do not iterate blind"): `failure=lidarFitDegenerate`. This is out of scope for this smolspec — the spec's contract ends at "mask reaching `Pipeline.estimate`". The new refusal sits downstream in `Pipeline.fitSupportPlane` → `LiDARPlaneFitter.refine` (`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift:209,238`): the real `source=pre_shutter` mask's geometry yields a degenerate scatter matrix (near-collinear candidate points in the lower-edge band when the food bbox extends close to the image's bottom edge), where the centre-rectangle `roughMask` previously used by `specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/` (sealed 2026-06-14, commit `ecf0211`) had been hiding the geometry by giving the lower-edge band a guaranteed below-bbox strip on the table.

**Handed to** `specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/` (re-opened). Tasks 8–10 of this spec stay `[ ]` with a `BLOCKED 2026-06-16` annotation on task 8; their success criterion (`estimate.end success=true` in both modes) is gated on the lidar fix landing.

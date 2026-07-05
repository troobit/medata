# MVP Closeout Trail — Three Loose Ends From 2026-06-18 Verification

## Overview

The 2026-06-18 on-device verification of the no-food-pixels closeout (Single + Double on the iPhone 13 Pro Max, build `903842a`) succeeded against this branch's three target bugs (lost-age, cadence, lidar) but surfaced four downstream issues — one correctness, one latency, two UX — that together block `event=estimate.end success=true` and the atomic three-spec closeout. This smolspec scopes all four as one MVP-grade bugfix on the research branch — the intent being that this is the last loose-ends pass before the research line is ready to replace `main`.

The findings — in order they hit the user during the trail:

1. **Pipeline latency** — wall-clock from `estimate.start` to `estimate.end` was **141.7 s** in two-view SfS path (full trail in Evidence). Two unexplained gaps: 73 s between the nadir-segmentation log and the `Volume` stage log, and 62 s between the oblique segmentation and the final `estimate.end`. Either gap is on its own a UX-killing wait.
2. **`failure=noFoodVolumeRecovered`** in the same trail. The oblique was tapped at tilt **52.0°** vs. the 25° target — `tiltInRange=false` but the shutter still armed because Decision 18's hard cap is `|Δθ − 25°| ≤ 30°`. A 6°-nadir / 52°-oblique baseline is well outside the SfS geometry the volume estimator was designed for, and either `VoxelGridSizer.size` produced a degenerate grid or `VoxelCarveEstimator.carve` carved below `minVoxelCountForClass`. Whether the same refusal repeats at a well-aimed ~25° oblique is unknown; this spec calls for a single re-test to find out.
3. **RefusalSheet truncates long messages** — `App/RefusalSheet.swift:94` uses a single fixed detent `[.fraction(0.35)]`. The body `Text` has no `lineLimit` set, so when the sheet's fixed height is shorter than the content, SwiftUI tail-truncates with an ellipsis. There's no second detent to drag up to, and the body isn't in a `ScrollView`. The user hit this on the `noFoodVolumeRecovered` refusal.
4. **Live camera keeps running during estimation** — `App/CaptureFlowView.swift:67` renders `ARPreviewView(engine: engine).ignoresSafeArea()` unconditionally for the entire capture flow. During `.estimating` the AR preview keeps the live feed on-screen, so users feel they still need to keep the phone pointed at the food while the pipeline runs (a 30 s+ window in MVP). The captured frame(s) that the estimator is actually working from — the nadir `RawFrame`, plus the oblique `RawFrame` in two-view mode — are already available on `CaptureResult` carried by the `.estimating(captureResult:)` state but are never shown. The user-side affordance for "the photo is taken, you can put the phone down" doesn't exist.

The mask + lidar fix verification is folded into the closeout step of this spec — there's no separate verification needed for those, because the same final trail that closes this spec also closes `no-food-pixels-on-fruit-plate-mvp` tasks 8-10, `lidar-plane-fit-degenerate-on-clean-capture` tasks 8-9, and `shutter-blocked-feedback` task 5. The closeout is now gated on this spec instead of directly on a device re-test.

## Evidence — observed trail

Captured 2026-06-18 22:50-22:53, iPhone 13 Pro Max (iOS 26.5), build off `no-food-pixels-on-fruit-plate-mvp` @ `903842a` installed from the correct worktree DerivedData. Mode `double`, fruit plate ~40 cm.

```
22:50:19.829  event=fired stage=nadir tiltDegrees=6.2 tiltInRange=true canShutter=true
22:50:19.846  event=capture.start stage=nadir
22:50:19.901  event=capture.end   stage=nadir success=true 1920x1440
                  [ 41 s gap — pre-oblique producer idle / user preparing tilt ]
22:51:01.310  event=segmenter.substage.start name=preprocess (producer)
22:51:02.255  event=segmenter.substage.start name=inference
22:51:02.321  event=segmenter.substage.start name=postprocess
22:51:11.604  event=fired stage=oblique tiltDegrees=52.0 targetTilt=25 tiltInRange=false canShutter=true   ← user overshot tilt
22:51:11.620  event=capture.start stage=oblique
22:51:11.717  event=capture.end   stage=oblique success=true
22:51:11.718  event=estimate.start capturePath=two_view_sfs
22:51:11.718  event=estimate.start maskAgeMs=200        ← lost-age + cadence fixes holding
22:51:11.718  event=pipeline.stage.start name=CardDetection
22:51:11.752  event=pipeline.stage.start name=SupportPlane
22:51:11.752  event=supportplane.start source=pre_shutter
22:51:14.935  event=supportplane.end success=true residual_mm=2.884876   ← lidar four-edge-band fix holding
22:51:14.946  event=pipeline.stage.start name=MetricScale
22:51:14.946  event=pipeline.stage.start name=Segmentation 1920x1440
22:51:14.947  event=segmenter.substage.start name=preprocess
22:51:16.219  event=segmenter.substage.start name=inference
22:51:16.303  event=segmenter.substage.start name=postprocess
                  [ 73 s gap — postprocess + buildBeta + Volume prep ]
22:52:29.843  event=pipeline.stage.start name=Volume capturePath=two_view_sfs
22:52:29.843  event=segmenter.substage.start name=preprocess (oblique segmentation inside Volume)
22:52:30.957  event=segmenter.substage.start name=inference
22:52:31.038  event=segmenter.substage.start name=postprocess
                  [ 62 s gap — VoxelCarveEstimator.carve ]
22:53:33.416  event=estimate.end success=false failure=noFoodVolumeRecovered
```

Total wall-clock from `estimate.start` to `estimate.end`: **141.7 s**.

## Requirements

### Refusal sheet (UI)

- The system MUST allow the user to read the full refusal message regardless of message length, on supported devices in supported Dynamic Type sizes. The shipping pattern is two detents (`[.fraction(0.35), .large]`) so the user can drag the sheet up to a near-full-screen presentation; alternatively the message MAY be wrapped in a `ScrollView`. Pick whichever is fewer lines.
- The fix MUST NOT change the `RefusalSheet`'s default presentation height (still ~35% on first appearance) so the existing tests in `MeData/Tests/RefusalSheetTests.swift` continue to pass without test-side changes.
- The accessibility identifier `refusal.message` MUST remain queryable from XCUITests.

### Pipeline latency (correctness-of-MVP-experience)

- The system MUST surface `event=pipeline.stage.end name=<X> latencyMs=N` for every pipeline stage already emitting `pipeline.stage.start`, so the next device trail tells us which stage is slow without further instrumentation. The substage events inside `CoreMLSegmenter` already give us segment-level timing; the stage-level timing is the missing piece.
- The combined wall-clock from `estimate.start` to `estimate.end` SHOULD be ≤ **30 s** on the iPhone 13 Pro Max for the two-view SfS path with the dev-stub segmenter (Phase 1, Debug). The 30 s ceiling is an MVP comfort target, not the research §16 sub-second budget — Phase 3's CoreML segmenter on Neural Engine moves us toward that separately.
- Whichever stage the new `latencyMs` lines point at as the dominant cost MUST be optimised once if a single targeted change can cut it ≥ 50%. If the slow stage is intrinsic (e.g. `VoxelCarveEstimator.carve` at the current grid resolution) and no targeted cut exists, the work caps at one decision-log entry documenting the floor and noting the Phase 3 follow-up.

### Freeze viewfinder during estimation

- During `.estimating(captureResult:)` the system MUST replace the live `ARPreviewView` with a static rendering of the capture(s) the estimator is operating on. In Single mode this is the nadir `RawFrame` only. In Double mode (two-view SfS) it MUST show both the nadir and oblique frames stacked or side-by-side so the user sees that BOTH photos were taken — the affordance that distinguishes "I'm done" from "I still need to do something".
- The `Estimating…` hint and any other chrome (top bar, badges) MUST remain visible over the frozen image so the user understands the system is still working.
- The frozen image MUST be rendered from `captureResult.nadirFrame.imageBytes` (and `.obliqueFrame?.imageBytes` for two-view) — these are already in `BGRA8` after the rawframe-rgb-conversion fix, so a `CGImage` round-trip is sufficient. No new RawFrame → UIImage conversion utility is in scope; a single inline helper at the call site is fine.
- On exit from `.estimating` to either `.refused` or the result view, the system MUST restore the live `ARPreviewView` so the next capture starts from a live viewfinder. (`.refused` re-renders the live preview behind the refusal sheet; success transitions to `ResultView` which doesn't show the camera at all.)

### Volume refusal

- The system MUST not block MVP closeout on `noFoodVolumeRecovered` if a well-aimed oblique tap (live-indicator-badge green, tilt ~ 25 ± 10°) succeeds end-to-end. The re-test in this spec's verification step is the disambiguator.
- IF the well-aimed oblique still refuses with `noFoodVolumeRecovered`, the system MUST either (a) refuse earlier and faster at the geometry-input boundary (e.g. tilt-delta gate before Segmentation runs) with a clear retake hint, or (b) fix the underlying volume estimator regression. Choice between (a) and (b) is deferred until the re-test trail is in hand — both paths are documented in Implementation Approach.
- IF the well-aimed oblique succeeds, no code change to the volume path is required. The current Decision 18 hard cap stays. The pre-oblique tilt hint copy (`obliqueTiltMessage`) MAY be augmented to call out the recommended ~25° band more prominently if the trail shows the user surprised by the failure at 52°, but this is optional.

### Contract preservation

- The system MUST NOT change `CaptureResult`, `RawFrame`, the `Pipeline.estimate` public signature, or the `PreShutterMaskSource` protocol surface.
- The system MUST NOT regress the test baseline: `swift test` 313/313 green (3 skipped) MUST hold after every commit on this branch.

## Implementation Approach

Five phases, sequenced. Each phase ends with `swift build` clean. No on-device retest until Phase 5.

### Phase 1 — Refusal sheet + frozen viewfinder (no device needed)

Two UI-only fixes, bundled because both are state-driven view composition in the App target.

**Refusal sheet:** `App/RefusalSheet.swift:94` — change `[.fraction(0.35)]` to `[.fraction(0.35), .large]`. That's the whole code change. The `.large` detent gives the user a one-finger drag-up to read the full message. Default-on-first-appearance stays at 35% so the existing layout regression tests don't shift. If a layout regression test snapshots the sheet at the `.large` detent, adjust the snapshot; otherwise this is a one-line diff.

**Frozen viewfinder:** `App/CaptureFlowView.swift:67` — wrap `ARPreviewView(engine: engine)` in a state switch. During `.estimating(captureResult: let result)`, render the captured frame(s) as a `CapturedFramesView` (new small `View` in the same file or alongside `CaptureFlowView`) instead of `ARPreviewView`. Decode a `CGImage` from `RawFrame.imageBytes` + `RawFrame.pixelFormat` (BGRA8 after the rawframe-rgb-conversion fix) using `CGDataProvider` + `CGImage.init(width:height:bitsPerComponent:bitsPerPixel:bytesPerRow:space:bitmapInfo:provider:decode:shouldInterpolate:intent:)` — inline at the call site, no new utility module. Single mode shows just nadir; two-view mode shows nadir on top half, oblique on bottom half (or side-by-side — pick whichever reads better at the iPhone 13 Pro Max aspect). All other states render `ARPreviewView` as today. Restore happens automatically on state exit from `.estimating`.

### Phase 2 — Per-stage `pipeline.stage.end latencyMs=N` instrumentation

`MedataCore/Sources/Pipeline/Pipeline.swift` — wherever `pipelineStageLog.info("event=pipeline.stage.start name=<X>")` fires, also emit a paired `pipelineStageLog.info("event=pipeline.stage.end name=<X> latencyMs=\(ms)")` when the stage exits (success or refusal). Compute `ms` as `(ContinuousClock.now - stageStartedAt) / 1ms`. Stages to cover: `CardDetection`, `SupportPlane`, `MetricScale`, `Segmentation`, `Volume`, `Macros` (and any others currently emitting `stage.start`).

This is `#if DEBUG`-gated like the existing stage logs. Don't add a new logger — reuse `pipelineStageLog`. No public-surface changes; no test churn.

### Phase 3 — Re-test on device (one trail, both modes)

After Phases 1 and 2 land. Build off this spec's branch, install via `xcrun devicectl device install app`, drive Single mode first (one nadir tap on a fruit plate, ~30-40 cm, tilt ≈ 0°), then Double mode (nadir + oblique, oblique tilt 25 ± 10° — wait for the live-indicator badge to be green). Paste both trails, with `pipeline.stage.end latencyMs=N` lines visible.

### Phase 4 — Diagnose and apply targeted fixes

From the Phase 3 trail, identify the dominant slow stage by `latencyMs`. Most likely candidates and the targeted-fix shape for each:

- **`Segmentation` is the slow one.** `SegmenterPostProcessor.process` is doing per-pixel work over 1920×1440 × 27 classes (sigma_seg, perClassMeanProb). Single targeted cut: vectorise the inner loops, or reduce intermediate copies. If still slow, mark intrinsic and document.
- **`Volume` is the slow one.** `VoxelCarveEstimator.carve` is iterating a voxel grid. Single targeted cut: reduce grid resolution for MVP, or short-circuit empty class slabs earlier. If intrinsic, document.
- **`MetricScale` or `CardDetection` is unexpectedly slow.** Unlikely; investigate as a real bug if observed.

For the `noFoodVolumeRecovered` refusal: if the well-aimed Double-mode oblique succeeds, no fix needed. If it still fails, narrow on the trail's volume-stage signals and choose between an earlier geometry-input refusal vs. a volume-estimator fix.

This phase ends with one commit per targeted fix.

### Phase 5 — Closeout trail and atomic doc commit

Re-run the device verification (same script as Phase 3). Once both modes show `event=estimate.end success=true` and the total wall-clock is ≤ 30 s, land the atomic three-spec closeout commit described in `nextup.md` step 2 — `no-food-pixels-on-fruit-plate-mvp` tasks 8-10, `lidar-plane-fit-degenerate-on-clean-capture` tasks 8-9, `shutter-blocked-feedback` task 5 — plus this spec's own `## Verification` section.

## Out of scope

- The 41-second pre-oblique gap between nadir capture.end and the next producer preprocess in the Evidence trail. Likely user-pause (preparing to tilt), not a producer bug — the cadence fix from `288c5a7` was verified holding by `maskAgeMs=200`. If a future trail shows the producer silent for >10 s while the live indicator badge is updating normally, file a separate spec.
- Phase 3 CoreML segmenter weights, Neural Engine residency, the research §16 sub-second budget. The 30 s MVP ceiling is intentionally generous to keep the Phase 3 weights work out of MVP closeout.
- Decision 18's oblique tilt hard cap of `|Δθ − 25°| ≤ 30°`. Tightening the cap is one possible Phase 4 fix path but is gated on the re-test showing the failure repeats at well-aimed tilt.
- The `localisedMessage` copy for `noFoodVolumeRecovered`. The current "Unable to estimate the meal volume. Please retake the photo." is fine for MVP; if Phase 4 ends up changing the geometry-input refusal copy, that's the time to revise.
- Any UI work on the live-indicator badge or oblique-tilt hint beyond the existing copy. Live-indicator UX is its own spec.

## Risks and Assumptions

- **Risk**: Phase 2's `pipeline.stage.end` lines fire on every pipeline run, so production-Debug log volume grows by N lines per estimate. **Mitigation**: lines are `.info` not `.debug`, gated by `#if DEBUG`, and only one per stage per estimate (low single digits per run). No throwaway-instrumentation cleanup needed.
- **Risk**: Phase 1's `.large` detent introduces a layout regression on landscape or smaller devices. **Mitigation**: `.large` is a SwiftUI standard sheet detent with platform-correct behaviour across screen sizes; we are not setting a custom large-height value. If a specific device shows a regression, fall back to wrapping the body `Text` in a `ScrollView` inside the existing 35% sheet.
- **Risk**: Phase 1's frozen-viewfinder swap holds two `RawFrame` byte buffers (~5.3 MB each at BGRA8 1920×1440) for the estimation window, on top of whatever the pipeline is already holding. **Mitigation**: the buffers are already retained by `CaptureResult` on the `.estimating` state — rendering them as `CGImage`s is a copy of references, not bytes. Memory pressure is unchanged from today.
- **Risk**: Phase 1's frozen-viewfinder fix interacts with the `interruption`/`scenePhase` paths — backgrounding during `.estimating` already cancels the flow per Decision 12. **Mitigation**: nothing in the view-side swap changes state-machine behaviour; it's a pure render-time switch based on `model.state`. The interruption path stays as-is.
- **Risk**: Phase 4 latency optimisation needs a Phase 3 trail before scoping, so the work is not estimable up-front. **Mitigation**: Phase 4 is bounded by the requirements — "one targeted change cutting ≥ 50%, or document the floor." No open-ended performance work.
- **Assumption**: The Phase 3 re-test will be done by the user on the iPhone 13 Pro Max in one session, paste-back trails as in this spec's Evidence. No XCUITest automation for this verification — the AR-gated flow has no simulator path (see `docs/agent-notes/ui-capture-flow.md`).
- **Assumption**: The `noFoodVolumeRecovered` failure was caused by the 52° oblique tilt, not by a regression in the volume estimator. If the well-aimed re-test still fails, the assumption is wrong and Phase 4 expands.

## Follow-ups

- Phase 3 segmenter bundling — the dev-stub's postprocess CPU cost is a known pre-existing limitation; the real CoreML segmenter on Neural Engine will replace it. The 30 s MVP ceiling and any Phase 4 cut to the dev-stub are stepping-stones, not load-bearing.
- If the well-aimed Double-mode oblique still fails with `noFoodVolumeRecovered` post-Phase-4, consider an `obliqueTiltMessage` copy that nudges toward 25° more strongly (Decision 18 stays). Out of scope for this spec; file separately if needed.

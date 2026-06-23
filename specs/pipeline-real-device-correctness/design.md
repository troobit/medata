# Pipeline Real-Device Correctness — Design

**Version:** 0.2
**Date:** 2026-06-13
**Status:** Implemented — tasks 1–16 landed (see `tasks.md` and CHANGELOG: pre-shutter mask producer, `VisionCardDetector`, real `foodRegionCoveragePercent`, `SupportPlaneFitter`). The pre-implementation baseline-capture gate was **not formally recorded**: the "Baseline numbers to capture" table below was never filled, so the Req 6.1/6.2 memory/latency *deltas* were not quantified — the budgets were sanity-checked qualitatively during on-device single-view-LiDAR runs rather than measured against a recorded pre-spec baseline. End-to-end on-device verification of the **two-view SfS path** for this spec's mask routing is still open (tracked in `specs/bugfixes/closeout-trail-mvp-cleanup/` Phase 5 and `GAPS.md` Group D).
**Requirements:** `requirements.md` v0.2
**Decision log:** `decision_log.md` D1–D11

## Overview

Add a pre-shutter segmentation pass that publishes a latest-wins food-region `BinaryMask`, route that mask through `CaptureResult` into a new `SupportPlaneFitter` protocol, replace `NullCardDetector` with a Vision implementation in the App target, and have the LiDAR coverage value at shutter time computed against the same mask.

## Architecture

### Subsystem map

```
ARKitCaptureEngine.frames ──┬── LiveSampleObserver  (unchanged; tilt / distance / whole-frame coverage)
                            └── PreShutterSegmenter (new, App target)
                                       │ publishes
                                       ▼
                                CaptureFlowModel.latestPreShutterMask: TimestampedMask?
                                       │ at shutter-tap → CaptureResult.preShutterFoodMask
                                       ▼
Pipeline.estimate
   ├── cardDetector.detect           (VisionCardDetector in production)
   ├── supportPlaneFitter.fit        (LiDARSupportPlaneFitter in production; test seam)
   ├── coverage(mask, depth.confidence) → LiDARStatus.foodRegionCoveragePercent (recomputed here)
   ├── segmenter.segment             (unchanged, in-shutter at native res)
   ├── Volume / Macros / Confidence  (unchanged)
   └── store.save
```

Two independent `engine.frames` subscriptions. `ARKitCaptureEngine.frames` is documented as per-subscriber with `bufferingNewest(1)`; no fan-out logic is added.

### State-machine gating

Pre-shutter producer runs in states where Req 1.3 allows: `initialising`, `ready`, `trackingLost`, `armed`. It pauses in `capturing`, `estimating`, `result`, `refused`. `CaptureFlowModel.state.didSet`-equivalent (or the existing state-transition path) drives `producer.resume()` / `producer.pause()`.

### Mask threading at shutter

`CaptureResult` gains one optional field: `preShutterFoodMask: BinaryMask?`. The pipeline reads it inside `fitSupportPlane`; absence or empty mask is mapped to `EstimationFailure.noFoodPixels` per Req 3.1/3.2.

### Pattern-extension audit

The mask is consumed by `LiDARPlaneFitter` (existing) via `LiDARPlaneFitter.Inputs.foodRegionMask`. The card-only path inside `Pipeline.fitSupportPlane` does not use it. No other consumer of `BinaryMask` exists at this layer. `PipelineBridges.foodMask(from:palette:)` (used inside `Pipeline.estimate` for the in-shutter mask consumed by `VoxelGridSizer`) is reused by `PreShutterSegmenter` for the pre-shutter mask — same call site, different `ArgmaxMap` source.

| Site | Needs change? | Reason |
| --- | --- | --- |
| `LiDARPlaneFitter.Inputs.foodRegionMask` | no | already accepts a `BinaryMask`; we change the supplier, not the contract |
| `PipelineBridges.foodMask(from:palette:)` | no | reused by pre-shutter producer; pure function |
| `CardOnlyPlaneFitter.Inputs` | no | the card-only path does not consume the mask |
| `VoxelGridSizer.Inputs.foodMask` | no | in-shutter mask is unchanged; the pre-shutter mask is only the support-plane spatial prior |
| `CapturePathDispatch.LiDARStatus.foodRegionCoveragePercent` | yes | value is now computed at shutter-time from the pre-shutter mask + the captured nadir depth confidence |
| `CaptureResult.preShutterFoodMask` | new | the field that carries the mask from App to Pipeline |

## Components and Interfaces

### `PreShutterSegmenter` (App target — new file `App/PreShutterSegmenter.swift`)

```swift
// Reference wrapper so 2.7 MB mask buffers are not copied on every set/get at 2 Hz.
final class MaskBox: Sendable { let mask: BinaryMask; init(_ m: BinaryMask) { mask = m } }

@MainActor
final class PreShutterSegmenter {
    struct TimestampedMask: Sendable {
        let box: MaskBox                  // 1920×1440 mask, reference-wrapped
        let producedAt: ContinuousClock.Instant
        let source: Source
    }
    enum Source: String, Sendable { case preShutterStub = "pre_shutter_stub", preShutterCoreML = "pre_shutter_coreml" }

    private(set) var latest: TimestampedMask?       // published; CaptureFlowModel reads at shutter-tap
    private var inflight: Task<Void, Never>?

    /// Pre-shutter pass uses its OWN `CoreMLSegmenter` instance — same model file
    /// path as `Pipeline.estimate`'s in-shutter segmenter, but a separately
    /// constructed wrapper. `MLModel` is not documented as concurrent-safe; two
    /// instances let pre-shutter and in-shutter run without synchronisation.
    /// The model file is loaded twice from disk; the cost is < 50 ms once at
    /// app launch and zero at steady state. (Decision 12.)
    init(segmenter: CoreMLSegmenter, palette: ClassPalette, source: Source)

    func resume(frames: AsyncStream<ARFrame>)       // idempotent; starts inference loop
    func pause()                                    // fire-and-forget: cancels inflight, does NOT await
    func awaitPaused() async                        // explicit await for callers that need the in-flight task drained (see snapshot atomicity below)
}
```

**Behavioural contracts:**

- Inference loop iterates frames; for each frame, *if* no inference is in flight, calls a `nonisolated` helper that builds a `RawFrame` from `frame.capturedImage` off the MainActor (`PixelBufferAdapter` conversion is CPU-heavy and would jank the UI at 2 Hz), then `await segmenter.segment(rawFrame)` (this also runs off-actor), then hops back to MainActor to convert the `ArgmaxMap` via `PipelineBridges.foodMask(from:palette:)` and atomically replace `latest`. Frames that arrive while inference is in flight are dropped — latest-wins on the input side too.
- `pause()` is fire-and-forget so it is callable from `didSet` / non-async state-transition callsites. It calls `inflight?.cancel()` and clears the handle; the cancelled task observes `Task.isCancelled` at its next await and drops without publishing.
- `awaitPaused()` is the async variant. CaptureFlowModel's `performFlow` (already async) calls `await preShutterSegmenter.awaitPaused()` immediately after capturing the nadir frame so the snapshot-then-pause read of `latest` is atomic (TOCTOU fix per Decision 13).
- `latest` is NOT cleared on `pause()` so the user can tap shutter immediately after pausing (Req 1.2's 750 ms ceiling still applies).
- Throws are swallowed and logged (`event=preshutter.mask.update success=false`); the next frame retries. A persistent failure path is not a Phase-1 concern.
- **Cadence violation instrumentation.** A `@MainActor`-isolated `lastUpdateAt: ContinuousClock.Instant?` tracks publication times. On each `latest` write, if `now - lastUpdateAt > .milliseconds(500)`, fire `event=preshutter.cadence.miss expectedHz=2 actualMs=<int>` (DEBUG-only). The producer takes no automatic action — the log surfaces the violation so on-device verification (Req 1.3 manual check) is auditable rather than silent. If sustained violations are observed, the design's 960×720 downsampled-input fallback (sketched below) lands as a follow-up patch.

**Downsampled-input fallback (sketch, used only if 1920×1440 cadence fails on-device verification):** replace the per-frame `RawFrame` construction with a 960×720 nearest-downsampled copy of `frame.capturedImage`; segment that; nearest-upsample the resulting `BinaryMask` to 1920×1440 inside the producer before publishing. No change to `Pipeline.estimate` or downstream consumers.

### `CaptureFlowModel` (modified — `App/CaptureFlowModel.swift`)

```swift
private let preShutterSegmenter: PreShutterSegmenter
// state didSet equivalent:
//   resume: .initialising, .ready, .trackingLost, .armed
//   pause:  .capturing,    .estimating,           .showingResult, .refused
```

**Freeze-at-nadir invariant.** The pre-shutter mask is sampled at the moment `capture.end stage=nadir` fires, not at `CaptureResult` construction time. The two-view path captures the nadir frame, stashes it, waits for the user to take the oblique tap, then builds `CaptureResult` — by that point the original pre-shutter mask is many seconds old. The model already stashes `firstFrame` and `firstFrameTiltDeg` at nadir-capture time (`CaptureFlowModel.swift:447-448`); the pre-shutter mask joins that stash:

```swift
// At nadir-capture completion (`CaptureFlowModel.performFlow`, after `capture.end success=true`):
await preShutterSegmenter.awaitPaused()       // drain in-flight; snapshot atomicity (Decision 13 / TOCTOU fix)
let frozenMask = preShutterSegmenter.latest.flatMap { ts in
    let age = ContinuousClock.now - ts.producedAt
    return age <= .milliseconds(750) ? ts.box : nil      // `box: MaskBox`, reference-typed
}
if stage == .nadir, mode == .double {
    firstFrame = frame
    firstFrameTiltDeg = tiltAtShutterDeg
    firstFrameMaskBox = frozenMask                       // new — travels through the two-view dance
    state = .ready(frozen)
    return
}

// Later, when CaptureResult is constructed (either single-view or after oblique):
let captureResult = CaptureResult(
    capturePath: mode.capturePath,
    lidar: LiDARStatus(available: supportsLiDAR, foodRegionCoveragePercent: 0),  // recomputed inside Pipeline
    nadirFrame: …,
    obliqueFrame: …,
    preShutterFoodMask: (stage == .oblique ? firstFrameMaskBox : frozenMask)?.mask,
    …
)
```

For the single-view-LiDAR path, the mask is the one captured at the (single) nadir tap. For the two-view path, the mask captured at the nadir tap travels with `firstFrame` and is consumed at oblique-tap-time `CaptureResult` construction. The 750 ms staleness check applies at the nadir-capture instant, not at `CaptureResult` build time, so the oblique-tap delay is not a refusal trigger.

**`firstFrameMaskBox` lifecycle.** Mirrors `firstFrame` exactly. Cleared at the same sites:

| Site (existing `firstFrame` clear) | Action on `firstFrameMaskBox` | Rationale |
| --- | --- | --- |
| `cancelInFlight` callers (background, interrupt) | clear to `nil` | mask no longer paired with a valid frame |
| `handleInterruption(.began)` (`CaptureFlowModel.swift:387`) | clear to `nil` | session reset |
| `scenePhaseDidChange` to `.background` | clear to `nil` | user left the app; resume re-runs pre-shutter |
| `tabSelectionChanged` away from Photo tab | clear to `nil` | not in capture context |
| `trackingDegraded` while two-view in flight (`:362-371`) | clear to `nil` | nadir-frame coordinates no longer valid |
| State machine returns to `.initialising` for any reason | clear to `nil` | session restart |
| `.refused` state set | clear to `nil` | the refused capture is done |
| `.showingResult` state set | clear to `nil` | the completed capture is done |

The grep-discoverable rule for reviewers: every assignment to `firstFrame = nil` gets an adjacent `firstFrameMaskBox = nil`.

`foodRegionCoveragePercent` is set to 0 at construction; `Pipeline.estimate` recomputes the real value from `nadirFrame.depth.confidenceMap` restricted to `preShutterFoodMask`. `App/CaptureFlowModel.swift:464` (the existing `frozen.lidarCoveragePercent` wiring) is removed.

### `VisionCardDetector` (App target — new file `App/VisionCardDetector.swift`)

```swift
import Vision
import CardDetection
import CaptureKit

final class VisionCardDetector: CardDetector, @unchecked Sendable {
    private let warmRequest = VNDetectRectanglesRequest()  // re-used across calls; configured for ID-1 aspect

    init() { configure(warmRequest) }

    func warmup() async                                  // Req 5.7; runs an empty request to JIT the Vision pipeline
    func detect(in frame: RawFrame) async -> [PixelCorner]?
}
```

**Configuration of `VNDetectRectanglesRequest`:**

- `minimumAspectRatio = 0.55`, `maximumAspectRatio = 0.70` (ID-1 is 53.98/85.60 ≈ 0.631; ±10 % envelope absorbs perspective).
- `minimumSize = 0.05` (5 % of shorter edge — id-1 at ~30 cm on iPhone 13 Pro Max ≥ 8 %).
- `maximumObservations = 1`; the brightest / largest match wins. Multiple cards in frame is out of scope.
- `quadratureTolerance = 20`.

**`VNImageRequestHandler` orientation.** The `RawFrame.imageBytes` produced by `PixelBufferAdapter` (per the `rawframe-rgb-conversion` spec) is laid out in **already-rotated display orientation** — `RawFrame.imageWidth = 1920`, `imageHeight = 1440` is the landscape colour grid the rest of the pipeline consumes. The handler is constructed with `CGImagePropertyOrientation.up`:

```swift
let cg = CGImageFromBGRA8(rawFrame.imageBytes,
                          width: rawFrame.imageWidth,
                          height: rawFrame.imageHeight)
let handler = VNImageRequestHandler(cgImage: cg, orientation: .up, options: [:])
try handler.perform([warmRequest])
```

`.up` is correct because the `RawFrame` is already in image-display orientation; Vision's normalised corner coordinates are then relative to that grid directly. Test (Req 8.5) constructs the BGRA buffer in the same orientation so the algebra matches both directions.

**Corner order — Vision → `PixelCorner` swap:**

`VNRectangleObservation` provides `topLeft`, `topRight`, `bottomRight`, `bottomLeft` in **normalised image coordinates with origin at bottom-left, +y up** — relative to the handler's orientation, which here is `.up`. `CardPoseSolver.solve` expects TL→TR→BR→BL in **`RawFrame` pixel coordinates with origin at top-left, +y down**. The swap is only on the Y axis:

```
PixelCorner(u: obs.topLeft.x     * W, v: (1 - obs.topLeft.y)     * H)   // TL
PixelCorner(u: obs.topRight.x    * W, v: (1 - obs.topRight.y)    * H)   // TR
PixelCorner(u: obs.bottomRight.x * W, v: (1 - obs.bottomRight.y) * H)   // BR
PixelCorner(u: obs.bottomLeft.x  * W, v: (1 - obs.bottomLeft.y)  * H)   // BL
```

`W = frame.imageWidth`, `H = frame.imageHeight`. Vision's own corner labels are already in the canonical TL→TR→BR→BL order because Vision uses image-display orientation; the swap is only on the Y axis.

**Warmup (Req 5.7):** `warmup()` runs `VNImageRequestHandler` on a 64×64 blank pixel buffer once, awaits completion, drops the result. Called by `CaptureFlowModel` on entry to `.ready` via a fire-and-forget cancellable `Task`. The same `warmRequest` instance is then reused on shutter-path calls so the second invocation pays warm latency. Vision request reuse is documented as warm-cache-friendly.

### `SupportPlaneFitter` protocol (MedataCore — new file or added to `MedataCore/Sources/SupportPlane/`)

```swift
public protocol SupportPlaneFitter: Sendable {
    func fit(
        nadir: RawFrame,
        cardPose: CardPose?,
        corners: [PixelCorner]?,
        preShutterFoodMask: BinaryMask?
    ) throws -> SupportPlane
}

public struct LiDARSupportPlaneFitter: SupportPlaneFitter {
    public init() {}
    public func fit(nadir: RawFrame, cardPose: CardPose?, corners: [PixelCorner]?, preShutterFoodMask: BinaryMask?) throws -> SupportPlane {
        // Empty-mask check applies at the protocol entry — BEFORE the LiDAR / card
        // dispatch — so the card-only path also refuses with `noFoodPixels` instead
        // of silently ignoring an empty mask (peer-review fix).
        guard let mask = preShutterFoodMask, hasAnyOneBit(mask) else {
            throw EstimationFailure.noFoodPixels
        }
        if nadir.depth != nil {
            // LiDARPlaneFitter.fit with mask
        } else {
            // CardOnlyPlaneFitter via the existing branch
        }
    }
}
```

**Decision table for `LiDARSupportPlaneFitter.fit`:**

| depth | mask | result |
| --- | --- | --- |
| nil | nil | `throw EstimationFailure.noFoodPixels` (empty-mask check) |
| nil | empty | `throw EstimationFailure.noFoodPixels` |
| nil | non-empty | card-only branch (CardOnlyPlaneFitter) |
| present | nil | `throw EstimationFailure.noFoodPixels` |
| present | empty | `throw EstimationFailure.noFoodPixels` |
| present | non-empty | LiDAR branch (LiDARPlaneFitter) |

`Pipeline` stores `supportPlaneFitter: any SupportPlaneFitter` (injected via `Pipeline.init`). `Pipeline.fitSupportPlane` (the private helper) becomes a thin wrapper that delegates to `supportPlaneFitter.fit(...)` and maps thrown `SupportPlaneError` to `EstimationFailure` exactly as today. `CentreRectangleMask.swift` and `centreRectangleFillFraction` are deleted.

### `Pipeline` constructor change (MedataCore — `Pipeline.swift`)

```swift
public init(
    cardDetector: any CardDetector,
    segmenter: CoreMLSegmenter,
    database: any FoodDatabase,
    store: any PersistenceStore,
    supportPlaneFitter: any SupportPlaneFitter = LiDARSupportPlaneFitter(),
    segmenterSource: String = ""
)
```

Default value preserves the existing call sites in tests; production wires through `PipelineFactory`.

### `PipelineFactory` signature (MedataCore — `PipelineFactory.swift`)

```swift
public static func makeForDevice(
    store: any PersistenceStore,
    cardDetector: any CardDetector,                       // new — production passes VisionCardDetector; required (no default — see below)
    palette: ClassPalette = .v1Standard,
    supportPlaneFitter: any SupportPlaneFitter = LiDARSupportPlaneFitter()  // new — tests inject a probe
) throws -> Pipeline
```

**`cardDetector` is required and has no default.** Existing production call sites (currently `Pipeline.makeForDevice(store:palette:)` — there are 0 of them; `PipelineFactory` is wired only from `App.swift`) update once to pass `VisionCardDetector()`. Test call sites construct local mock conformances (the established pattern — see `EstimationFailureTests.swift` and `PipelinePerformanceTests.swift` which already define their own `NoOpCardDetector` / `NilCardDetector` for this purpose).

**`NullCardDetector` is moved out of `PipelineFactory.swift` into its own file** `MedataCore/Sources/Pipeline/NullCardDetector.swift` with `internal` visibility, so MedataCore tests that need a quick no-op detector can reuse it instead of redefining the same struct. App-target tests cannot import it (it's `internal` to MedataCore), which matches the Non-Goal "Removing NullCardDetector from the test surface" — test surfaces are the App-target tests, which use their own local mock conformances. Req 5.2's "removed from production builds" is satisfied because `makeForDevice` no longer constructs it; the only production callers must pass `VisionCardDetector`.

### `Pipeline.estimate` — coverage recompute (modified — `Pipeline.swift`)

After `fitSupportPlane` and before `MetricScale`, compute the real `LiDARStatus.foodRegionCoveragePercent` once.

**Resolution-reconciliation rule (Decision 14):** the food-region mask is at 1920×1440 colour resolution; the LiDAR confidence buffer (`ARFrame.sceneDepth.confidenceMap`) is at 256×192 LiDAR-native resolution. The computation runs **in confidence-buffer space** (256×192), not in mask space. For each confidence-buffer pixel `(cx, cy)`, the corresponding mask pixel is `(mx, my) = (cx · W_colour / W_conf, cy · H_colour / H_conf)` with floor rounding. The coverage percentage is:

```
numerator   = count of (cx, cy) where mask.isFood(mx, my) AND confidence[cx, cy] / maxLevel >= 0.66
denominator = count of (cx, cy) where mask.isFood(mx, my)
foodRegionCoveragePercent = denominator > 0 ? 100 * numerator / denominator : 0
```

This matches the existing `LiDARPlaneFitter.foodMaskHasFoodAt(dx:dy:)` projection pattern (`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift`) so reviewers can cross-check the algebra against an existing call site. `LiveSampleMath.confidenceThreshold` (currently 0.66) is the single source of truth. The recomputed value is **NOT** used to override the user-toggle `capturePath` per Decision 1.

```swift
let realCoverage: Float
if let depth = nadir.depth, let mask = captureResult.preShutterFoodMask {
    realCoverage = computeFoodRegionCoverage(
        confidenceMap: depth.confidenceMap,                  // 256×192 native
        confidenceThreshold: LiveSampleMath.confidenceThreshold,
        mask: mask,                                          // 1920×1440 native
        colourWidth: nadir.imageWidth, colourHeight: nadir.imageHeight
    )
} else {
    realCoverage = 0
}
// The corrected value is logged at `estimate.end` (NOT `estimate.start` —
// `estimate.start` fires at function entry, before realCoverage exists).
// See Logging section.
```

### `StubInferenceEngine` (modified — `MedataCore/Sources/Segmentation/StubInferenceEngine.swift`)

Replace the uniform-dominant write loop with a centred-ellipse predicate:

```swift
// Centred ellipse with semi-axes (α·targetSize/2, α·targetSize/2), α = 0.618 (Decision 8).
// Area = π·α²·targetSize²/4 ≈ 0.30·targetSize² → 30 % of frame.
let alpha: Float = 0.618
let cx = Float(targetSize) / 2
let cy = Float(targetSize) / 2
let rx = alpha * Float(targetSize) / 2
let ry = alpha * Float(targetSize) / 2
for y in 0..<targetSize {
    let dy = (Float(y) + 0.5 - cy) / ry
    for x in 0..<targetSize {
        let dx = (Float(x) + 0.5 - cx) / rx
        let inside = (dx * dx + dy * dy) <= 1
        let pixel = y * targetSize + x
        // Inside ellipse → dominant logit. Outside → background-class logit.
        if inside {
            logits[pixel * classes + dominantClass] = Self.dominantLogit
        } else {
            logits[pixel * classes + palette.background] = Self.dominantLogit
        }
    }
}
```

**Test impact (corrected from the v0.1 "one-line update" claim).** The existing `MedataCore/Tests/SegmentationTests/StubInferenceEngineTests.swift` has three test methods whose semantics change and must be rewritten:

| Test method | Pre-change assertion | Post-change rewrite |
| --- | --- | --- |
| `testArgmaxOfEveryPixelEqualsDominantClass_defaultDominantZero` | `unique(argmax) == [0]` over every pixel | `unique(argmax) == [0, background]`; food pixels form a centred ellipse covering 30 ± 2 % of area |
| `testArgmaxOfEveryPixelEqualsDominantClass_explicitDominantFive` | same with dominant = 5 | same shape; ellipse contains class 5, exterior is `background` |
| `testDominantClassProbabilityAtLeastZeroPointNineNine` | every pixel has `mDominant ≥ 0.99` | inside-ellipse pixels have `mDominant ≥ 0.99`; outside-ellipse pixels have `mBackground ≥ 0.99` |

Downstream consumers that read the stub's argmax — `PipelineBridges.foodMask(from:palette:)`, `HarnessCore/FixtureRunner.swift:153,221` — are not assertion sites but they DO consume the stub's spatial distribution. The harness's existing fixtures need a one-time refresh against the new ellipse shape. `VoxelCarveEstimator` / `HeightFieldEstimator` consume real masks and are agnostic to which spatial shape the stub produces.

### `CaptureResult` (modified — `CaptureResult.swift`)

Add one field:

```swift
public let preShutterFoodMask: BinaryMask?
```

Initialiser default `nil` so existing test sites that construct `CaptureResult` directly don't break.

## Data Models

| Type | File | Status | Notes |
| --- | --- | --- | --- |
| `PreShutterSegmenter.TimestampedMask` | `App/PreShutterSegmenter.swift` | new | App-internal |
| `PreShutterSegmenter.Source` | same | new | matches `source=` log field values |
| `CaptureResult.preShutterFoodMask` | `MedataCore/Sources/Pipeline/CaptureResult.swift` | new optional field | default `nil` |
| `SupportPlaneFitter` protocol | `MedataCore/Sources/SupportPlane/` (suggested `SupportPlaneFitter.swift`) | new | enables Req 8.7 test seam |
| `LiDARSupportPlaneFitter` | same | new | production conformance |

No new persisted types, no `MealRecord` shape change.

## Error Handling

| Condition | Surface |
| --- | --- |
| `captureResult.preShutterFoodMask == nil` at shutter time | `EstimationFailure.noFoodPixels` (Req 3.2) |
| Mask present but `pixels` all zero | `EstimationFailure.noFoodPixels` (Req 3.1) |
| `VisionCardDetector.detect` no match | returns `nil` — existing `noScaleAvailable` fallback applies (Req 5.4) |
| `VisionCardDetector` returns invalid corners | `degenerateCardPose` / `cardTooOblique` via existing `CardPoseSolver` mappings (Req 5.5) |
| `PreShutterSegmenter` inference throws | swallowed; logged; `latest` not updated; next frame retries |
| `PreShutterSegmenter` cancelled mid-inference | `Task.isCancelled` short-circuits; `latest` not updated |

No new `EstimationFailure` cases. No new refusal modal copy.

## Logging

| Event | Channel | Trigger | Format |
| --- | --- | --- | --- |
| `preshutter.mask.update` (DEBUG) | `ie.medata.app` / `Shutter` | each completed pre-shutter inference | `event=preshutter.mask.update foodPixels=<int> ageMs=<int> source=<pre_shutter_stub\|pre_shutter_coreml> latencyMs=<int>` |
| `preshutter.cadence.miss` (DEBUG, new) | same | each `latest` write where `now - previousUpdateAt > 500ms` | `event=preshutter.cadence.miss expectedHz=2 actualMs=<int>` |
| `supportplane.start` (DEBUG, augmented) | same | already exists | append `source=pre_shutter` (centre-rectangle source is removed alongside `CentreRectangleMask.swift`); existing `width/height` fields unchanged; `fillFraction` field removed in the same patch |
| `carddetect.end` (DEBUG, new) | same | each `VisionCardDetector.detect` completion | `event=carddetect.end success=<bool> cornerCount=<int> latencyMs=<int>` |
| `estimate.start` (DEBUG, augmented) | same | already exists | append `maskAgeMs=<int>` field only (mask age is known at function entry); `foodRegionCoveragePercent` cannot be logged here — see `estimate.end` |
| `estimate.end` (DEBUG, augmented) | same | already exists | append `foodRegionCoveragePercent=<float>` field — the recomputed value is only known after `fitSupportPlane` returns, so it logs at function exit alongside the existing `success`/`failure` fields per Req 4.5 |

All gated by `#if DEBUG` to match `Pipeline.swift`'s existing pattern (Req 7.4). **Req 4.5 amendment.** The requirement reads "`event=estimate.start` SHALL log the food-region coverage value". Since the value cannot exist at `estimate.start` (computed inside `Pipeline.estimate` after `fitSupportPlane`), the design routes Req 4.5's intent to `estimate.end`. Treat this as a Req 4.5 erratum captured in Decision 15.

## Concurrency Model

| Element | Isolation | Notes |
| --- | --- | --- |
| `PreShutterSegmenter` | `@MainActor` | publishes `latest` on MainActor; inference is async but the publication is serialised |
| `latest` write | `@MainActor` | atomic at the actor boundary |
| in-flight inference `Task<Void, Never>` | implicitly inherits `@MainActor` for the loop body, but `await segmenter.segment(_:)` jumps off MainActor (the engine wrapper handles its own isolation) | |
| `pause()` | `@MainActor` async | awaits the in-flight `Task.cancel()` then `await task.value` so the caller is guaranteed no further `latest` writes |
| `CaptureFlowModel.preShutterSegmenter` | `@MainActor` | already the model's domain |
| `VisionCardDetector` | non-isolated (`@unchecked Sendable`) | Vision is thread-safe; the warm request is reused; concurrent invocation is not contemplated |

## Integration Points

| Existing site | Modification |
| --- | --- |
| `App.swift` — `Pipeline.makeForDevice(store:palette:)` call | becomes `Pipeline.makeForDevice(store:cardDetector: VisionCardDetector(), palette:)` |
| `App/CaptureFlowView.swift:74-76` — `LiveSampleObserver.start(frames: engine.frames)` | adds `preShutterSegmenter.resume(frames: engine.frames)` alongside |
| `App/CaptureFlowModel.swift:464` — `LiDARStatus(... foodRegionCoveragePercent: frozen.lidarCoveragePercent)` | becomes `foodRegionCoveragePercent: 0` (recomputed inside `Pipeline`) |
| `App/CaptureFlowModel.swift` — state transitions | inject `preShutterSegmenter.pause()` / `.resume(frames:)` per Req 1.3/1.4 scope |
| `MedataCore/Sources/Pipeline/Pipeline.swift:387-494` (`fitSupportPlane`) | rewritten to delegate to `supportPlaneFitter.fit(...)`; the LiDAR-vs-card dispatch moves into `LiDARSupportPlaneFitter` |
| `MedataCore/Sources/Pipeline/CentreRectangleMask.swift` | deleted (Req 2.2) |

## Testing Strategy

### Unit tests (Swift Testing in `MedataCore/Tests/PipelineTests/` and a new `App/Tests/PreShutterSegmenterTests.swift`)

| Test | Requirement | Approach |
| --- | --- | --- |
| `LiDARSupportPlaneFitterTests.fitWithPreShutterMaskProducesFinitePlane` | Req 8.1 | reuses `SupportPlaneRoughMaskTests` fixture; pass mask built from a synthetic plate silhouette |
| `LiDARSupportPlaneFitterTests.emptyMaskThrowsNoFoodPixels` | Req 8.2 | mask with `pixels = [UInt8](repeating: 0, …)` → expect `EstimationFailure.noFoodPixels` |
| `PreShutterSegmenterTests.maskOlderThan750msIsUnavailable` | Req 8.3 | construct a `TimestampedMask` with `producedAt = now - .seconds(1)`; assert `CaptureFlowModel`'s shutter-tap gate treats it as unavailable |
| `CoverageComputationTests.maskAreaAbove10kPixels` | Req 8.4 | 256×256 ones mask + synthesized confidence buffer 50 % high-confidence → assert ≈ 50 % ± 1 % |
| `VisionCardDetectorTests.detectsId1Rectangle` | Req 8.5 | synthesised 1920×1440 BGRA buffer with a white ID-1 rectangle on black background; assert four corners in TL→TR→BR→BL pixel order |
| `SupportPlaneRoughMaskTests` (existing) | Req 8.6 | unchanged regression sentinel against all-ones masks |
| `StubInferenceEngineEllipseTests` | Decision 8 | run stub at `targetSize = 256`; count argmax pixels labelled `dominantClass`; assert 30 ± 2 % |

### Integration test (Req 8.7)

```swift
@Test func preShutterMaskReachesFoodRegionMaskInputs() async throws {
    final class ProbeFitter: SupportPlaneFitter {
        var lastFoodMask: BinaryMask?
        func fit(nadir: RawFrame, cardPose: CardPose?, corners: [PixelCorner]?, preShutterFoodMask: BinaryMask?) throws -> SupportPlane {
            lastFoodMask = preShutterFoodMask
            return SupportPlane(normal: …, distanceMm: 300, residualMm: 1, convergedIterations: nil)
        }
    }
    // Locally-defined no-op detector — matches the existing test pattern in
    // EstimationFailureTests.swift and PipelinePerformanceTests.swift.
    struct LocalNoOpCardDetector: CardDetector {
        func detect(in frame: RawFrame) async -> [PixelCorner]? { nil }
    }
    let probe = ProbeFitter()
    let pipeline = try Pipeline.makeForDevice(
        store: InMemoryPersistenceStore(),
        cardDetector: LocalNoOpCardDetector(),
        supportPlaneFitter: probe
    )
    let mask = makeSyntheticPlateMask(width: 1920, height: 1440)
    let captureResult = CaptureResult(… preShutterFoodMask: mask …)
    _ = try? await pipeline.estimate(captureResult: captureResult, mode: .singleViewLidar)
    #expect(probe.lastFoodMask?.pixels == mask.pixels)
}
```

The test confirms byte-identity of the mask between `CaptureResult.preShutterFoodMask` and `SupportPlaneFitter.fit`'s `preShutterFoodMask` parameter.

### Property-based testing

No new PBT candidates. The mask is a `[UInt8]` buffer with no algebraic invariants; the percentage computation is one arithmetic statement; the corner-order swap is a four-element transformation. Example-based tests cover all cases adequately.

### Manual on-device verification

| Item | Procedure | Acceptance |
| --- | --- | --- |
| Cadence (Req 1.3) | Console.app filter `subsystem == "ie.medata.pipeline"` (no, use `ie.medata.app`); read `preshutter.mask.update` inter-event spacing | ≥ 2 updates per second sustained for 30 s in `ready` |
| Staleness gate (Req 1.2) | Tap shutter, observe `estimate.start maskAgeMs` field | < 750 ms |
| Memory baseline (Req 6.1) | Run pre-spec build under Instruments → Allocations; record peak resident; then run new build; record peak resident | new ≤ pre-spec + 50 MB |
| Latency baseline (Req 6.2) | Run pre-spec build; measure shutter-tap-handler → `estimate.start` log line latency; then new build | new ≤ pre-spec + 100 ms |

**Baseline numbers to capture (Reqs 6.1, 6.2 — prerequisites.md "Baseline measurements"):**

| Metric | Pre-spec value | New value | Tolerance |
| --- | --- | --- | --- |
| Peak resident memory under fruit-plate flow | ___ MB | ___ MB | + 50 MB |
| Shutter-tap → `estimate.start` latency | ___ ms | ___ ms | + 100 ms |

**These rows were never formally captured.** Implementation (tasks 1–16) landed without the pre-spec baseline being recorded, so the Req 6.1/6.2 deltas are unquantified. The memory/latency budgets were not observed to regress during on-device runs, but the recorded-delta acceptance was not performed. If the formal baseline is needed (e.g. before a Phase 3 release), run the capture per `prerequisites.md` and fill these rows retroactively against the current build.

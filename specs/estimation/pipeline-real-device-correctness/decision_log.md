# Decision Log: Pipeline Real-Device Correctness

## Decision 1: Keep User CaptureMode Toggle Authoritative

**Date**: 2026-06-13
**Status**: accepted

### Context

`selectCapturePath` in `MedataCore/Sources/Pipeline/CapturePathDispatch.swift:40-50` returns `.singleViewLidar` only when LiDAR is available, a support plane is detected, and `foodRegionCoveragePercent >= 80`. The third clause has never been honest in production: `App/CaptureFlowModel.swift:461-465` feeds whole-frame LiDAR coverage into `LiDARStatus.foodRegionCoveragePercent`, so the value is always wrong and `selectCapturePath` is currently routed only through `App/CapturePathDecider.swift` behind the `AUTO_CAPTURE_MODE` compile flag. The production app instead honours the user's `CaptureMode` toggle per `specs/research/decision_log.md` Decision 35.

This spec must decide whether to re-enable auto-selection now that the coverage value will be honest, or to keep the v1 user-toggle contract and treat the corrected signal as future-proof telemetry.

### Decision

The user's `CaptureMode` toggle remains the v1 path-selection contract. `selectCapturePath` continues to be invoked only inside `#if AUTO_CAPTURE_MODE`. The corrected `foodRegionCoveragePercent` signal is still populated and logged so a future spec can re-enable auto-selection with calibrated telemetry.

### Rationale

Decision 35 was a UX decision (the user wants explicit, deterministic control over which capture path runs). Honest coverage data doesn't change that UX argument; it only removes one obstacle to a future re-litigation. Re-enabling auto-selection here would (a) overturn Decision 35 without UX evidence and (b) couple this spec's success to a path-decision behaviour change rather than to the three named correctness deliverables.

### Alternatives Considered

- **Re-enable `AUTO_CAPTURE_MODE` unconditionally**: Removes the compile flag and routes every capture through `selectCapturePath` — Rejected because it overturns Decision 35 without UX evidence and entangles this spec with a separable UX concern.
- **Add a `.auto` `CaptureMode` case**: Adds a third toggle position users opt into — Rejected because it expands UI scope (mode toggle visuals, settings, copy) and is out of scope for an MVP unblock spec.

### Consequences

**Positive:**

- The spec's success criteria stay scoped to the three correctness deliverables.
- Decision 35's UX contract is preserved.
- Honest coverage telemetry is available for a future auto-selection spec without changing user-visible behaviour now.

**Negative:**

- The corrected signal isn't user-visible in v1; it's measurable only via logs and tests until a follow-up spec consumes it.

---

## Decision 2: Empty / Stale Mask Surfaces via Existing Refusal Path

**Date**: 2026-06-13
**Status**: accepted

### Context

When the pre-shutter segmentation pass produces a mask with zero food pixels (or no mask is yet available at shutter-tap), the pipeline needs a defined behaviour. Options range from new pre-shutter UI (disable shutter, add a "no food" indicator state) to new refusal copy (a `noFoodInFrame` `EstimationFailure` case with bespoke modal text) to falling through to existing failures.

### Decision

Empty or unavailable masks at shutter-tap throw the existing `EstimationFailure.noFoodPixels` and surface via the existing refusal modal copy. The spec ships no new live-indicator state, no new badge, no new refusal copy, and no new `EstimationFailure` case.

### Rationale

The user's directive on 2026-06-13 was "nothing, just error. Don't add extra UI yet, we need MVP process first." Empty masks are a corner case once basic capture envelope (centred plate, in-range distance) is gated; chasing UX polish before the MVP capture-to-result path is proven would invert priorities. Reusing `noFoodPixels` is also semantically honest — the pre-shutter pass is a segmenter, just earlier in the timeline.

### Alternatives Considered

- **New `.noFoodInFrame` `EstimationFailure` case with bespoke refusal copy**: Distinguishes pre-shutter detection from in-shutter detection — Rejected as UX scope creep for MVP; both fail for the same underlying reason (segmenter sees no food).
- **Pre-shutter gate: disable shutter when no food detected**: Prevents the failure round-trip — Rejected because it requires a new live-indicator state and refusal-badge wiring that doesn't ship in MVP.

### Consequences

**Positive:**

- No new UI surface to design, implement, or test.
- Existing refusal-modal coverage applies unchanged.

**Negative:**

- Users who tap shutter on an empty frame see the existing `noFoodPixels` copy ("No food detected — try framing the plate"), which is generic rather than specific to a stale-mask edge case.
- A user can theoretically tap shutter during the first 500 ms of the pre-shutter pass starting up, get a `noFoodPixels` refusal, then retry and succeed. This is acceptable for MVP and revisitable post-MVP.

---

## Decision 3: Pre-Shutter Cadence Target — ≥ 2 Hz / ≤ 500 ms Latency

**Date**: 2026-06-13
**Status**: accepted

### Context

The pre-shutter segmentation pass needs a measurable cadence target so the requirements pin observable behaviour rather than "best effort". Options range from on-demand triggering (run inference only when other indicators say capture is imminent) to throttled steady-state (a fixed update rate) to unthrottled (let the engine run as fast as it can).

### Decision

The pre-shutter segmentation pass MUST produce an updated mask at least twice per second (≥ 2 Hz, ≤ 500 ms inter-update latency) on iPhone 13 Pro Max iOS 26.5 throughout the capture-ready states. The shutter-time staleness ceiling at [Requirement 1.2](requirements.md#1.2) is set to 750 ms — strictly greater than the cadence period — so cadence jitter does not produce deterministic refusals.

### Rationale

2 Hz is the slowest rate that still feels live: a user adjusting framing sees the mask follow within half a second. It is also a rate that downscaled inference on the iPhone 13 Pro Max ANE can comfortably sustain (the in-shutter segmenter at 1920×1440 reportedly completes in ~720 ms, so a downscaled pre-shutter at e.g. 513×385 will run faster). The 500 ms cap also defines the staleness threshold in [Requirement 1.2](#1.2): the mask is considered stale if older than the inter-update target.

### Alternatives Considered

- **On-demand: only when other indicators are simultaneously in range**: Lower CPU cost — Rejected because it adds latency at the moment the user is ready to shutter, exactly when freshness matters most.
- **No fixed target; defer to a tasks-phase performance test**: Avoids over-committing — Rejected because the requirements need a measurable target so reviewers can verify acceptance.

### Consequences

**Positive:**

- Measurable acceptance criterion for the pre-shutter cadence.
- Defines a clean staleness boundary that doubles as the mask-availability gate.

**Negative:**

- Sustained inference cadence consumes battery; will need throttling-down when capture-ready states are not active (already required by [Requirement 1.4](#1.4)).

---

## Decision 4: Vision Card Detector Runs on Every Nadir Capture

**Date**: 2026-06-13
**Status**: accepted

### Context

`Pipeline.fitSupportPlane` (`MedataCore/Sources/Pipeline/Pipeline.swift:387-494`) takes the LiDAR path when `nadir.depth != nil` and the card-only path otherwise. Vision card detection on a 1920×1440 frame has measurable cost. The spec must decide whether to always run detection (and ignore the result on the LiDAR-healthy happy path) or to gate detection on LiDAR availability.

### Decision

The Vision card detector runs unconditionally on every nadir frame reaching `Pipeline.estimate`. The pipeline's existing LiDAR-takes-precedence branch is unchanged: a healthy LiDAR fit continues to ignore the returned `CardPose`.

### Rationale

Conditional invocation moves a branch on LiDAR availability into the App layer (the `CardDetector` wiring) where today it cleanly belongs to the Pipeline. Always-running keeps the contract simple ("the detector tries; the pipeline decides what to do with the result") and matches the budget set in [Requirement 5.6](#5.6) (≤ 250 ms on iPhone 13 Pro Max). The card detector also produces a useful artefact for future telemetry (was the fixture card in frame?) that conditional invocation throws away.

### Alternatives Considered

- **Skip detection when LiDAR is healthy**: Saves ~250 ms on the LiDAR-healthy happy path — Rejected because it complicates the contract and the savings are below the [6.2](#6.2) latency budget.
- **Run pre-shutter too with a card-detected badge**: Surfaces detection state in the live indicators — Rejected because it expands UX scope beyond MVP and is covered by Non-Goals.

### Consequences

**Positive:**

- Simple contract: always run, pipeline decides usage.
- A future spec consuming card detections (e.g., calibration QA) has the data without changes here.

**Negative:**

- ~250 ms shutter-path overhead on the LiDAR-healthy happy path, accepted under [Requirement 6.2](#6.2).

---

## Decision 5: Latest-Wins Pre-Shutter Mask Publication with Cancellable In-Flight Inference

**Date**: 2026-06-13
**Status**: accepted

### Context

The pre-shutter inference task runs concurrently with the live-indicator stream and with state-machine transitions driven by user gestures, tab changes, and ARSession events. The design phase needs a concurrency contract pinned before tasks start, or it will be invented inconsistently across `CaptureFlowModel`, the new pre-shutter producer, and `Pipeline.estimate`.

### Decision

The pre-shutter producer SHALL use a latest-wins publication discipline. When the capture flow transitions out of a producing state ([Requirement 1.3](requirements.md#1.3)), the in-flight inference task SHALL be cancelled; a fresh task SHALL NOT begin until the previous cancellation completes. Shutter-tap consumers SHALL always observe the most recently completed mask via a `@MainActor`-isolated publisher.

### Rationale

Latest-wins matches the cadence rule's intent ("the mask reflects what the user sees within half a second"), is implementable with the existing `Task` cancellation primitives (already used elsewhere in `LiveSampleObserver`), and avoids the buffering / queueing complexity of FIFO publication. Cancelling on state-change-out keeps cost off the user when the result will be discarded.

### Alternatives Considered

- **Allow in-flight task to finish; publish only if state is still producing**: Simpler cancellation logic — Rejected because it can publish a mask to a stale `ready` snapshot after a `tabSelectionChanged` round-trip, contradicting [Requirement 1.4](requirements.md#1.4).
- **Drain queue of pending tasks**: FIFO semantics — Rejected because the producer is throttled to 2 Hz already; there is no queue to drain.

### Consequences

**Positive:**
- One concurrency contract for the design phase to honour.
- Predictable behaviour across all state-machine transitions.

**Negative:**
- Cancellation cost is non-zero (Vision and Core ML handles must tear down); the design phase must measure and stay inside [Requirement 6.2](requirements.md#6.2).

---

## Decision 6: Pre-Warm Vision Request on Entry to Ready State

**Date**: 2026-06-13
**Status**: accepted

### Context

Decision 4 mandates that the Vision card detector runs unconditionally on every nadir capture. The first `VNDetectRectanglesRequest` of a session pays a materially higher latency than steady-state (~300–600 ms typical cold-start versus ≤ 250 ms warm), risking the [Requirement 5.6](requirements.md#5.6) budget on the first shutter-tap of every session.

### Decision

The capture flow SHALL pre-warm the Vision request once on entry to `ready` state. The warmup is cancellable and SHALL NOT block the live indicator stream.

### Rationale

Moving the cold-start cost off the shutter path is the cheapest fix that preserves Decision 4's "always run" contract. The warmup runs against the same handler the production detector uses, so subsequent shutter-tap detections hit warm paths.

### Alternatives Considered

- **Restate Req 5.6 as warm-only with a documented cold-path exemption**: Spec change rather than implementation change — Rejected because it shifts the cost onto the user (first shutter-tap of every session sees a longer wait) instead of onto a quiet warmup.
- **Pre-warm at app launch**: Earlier, but the user may never reach the capture flow in a session — Rejected as wasteful.

### Consequences

**Positive:**
- First shutter-tap latency is bounded by [Requirement 5.6](requirements.md#5.6).
- Implementation cost is one cancellable `Task` started in `CaptureFlowModel.didEnterReady`.

**Negative:**
- A small amount of work runs on entry to `ready` that may be discarded if the user immediately changes tabs.

---

## Decision 7: Literal 250 000-Candidate-Point Ceiling

**Date**: 2026-06-13
**Status**: accepted

### Context

[Requirement 2.2](requirements.md#2.2) deletes `MedataCore/Sources/Pipeline/CentreRectangleMask.swift`. The OOM invariant from `lidar-plane-fit-oom-on-device-1920x1440` Decision 1 needs a concrete ceiling that survives the deletion. The original 2026-06-13 device log recorded 236 752 candidate points at `fillFraction = 0.7` on the fruit-plate fixture.

### Decision

[Requirement 2.3](requirements.md#2.3) pins the candidate-point ceiling at **250 000** — the historical measurement plus headroom — independent of any deleted code path.

### Rationale

A literal number is auditable from the spec alone, survives the deletion of the centred-rectangle helper, and is enforced by the existing `LiDARPlaneFitter.debugLastCandidatePointCount` counter introduced in the prior bugfix.

### Alternatives Considered

- **Keep `CentreRectangleMask` alive as a test-only fixture**: Allows live comparison — Rejected because it preserves a placeholder data path that future maintainers might re-wire into production by mistake.
- **Express the ceiling as a multiple of the fixture's depth-confidence-positive pixel count**: More portable across fixtures — Rejected as over-engineering for a single-fixture regression test.

### Consequences

**Positive:**
- Auditable, fixture-independent ceiling.
- No live coupling to deleted code.

**Negative:**
- The 250 000 number is calibrated to the iPhone 13 Pro Max 1920×1440 fruit-plate fixture; if Phase 3 introduces a higher-resolution capture format, the ceiling needs a revisit.

---

## Decision 8: Dev-Stub Pre-Shutter Mask Is a Centred Ellipse

**Date**: 2026-06-13
**Status**: accepted

### Context

`StubInferenceEngine` (`MedataCore/Sources/Segmentation/StubInferenceEngine.swift`) returns a canned palette label across the whole canonical-RGB8 buffer. If the pre-shutter pass simply takes the stub's output as the food-region mask, dev-stub builds get an all-ones mask — exactly the regression the `lidar-plane-fit-degenerate-on-clean-capture` bugfix removed.

### Decision

When `DEV_STUB_SEGMENTER` is defined, `StubInferenceEngine` SHALL return a deterministic centred-ellipse food region covering 30 ± 2 % of the input image area. The pre-shutter pass interprets the stub's output as a food region the same way it interprets the Core ML engine's output — no special-case downstream code is needed.

### Rationale

A centred ellipse matches the documented capture envelope (centred plate, ~30 cm distance) more honestly than the centred rectangle the prior bugfix shipped, while being deterministic enough to make the regression tests in [Requirements 8.1](requirements.md#8.1) and [8.3](requirements.md#8.3) reproducible. The 30 % area target reuses the calibration logic from `centreRectangleFillFraction = 0.7` (a centred 0.7 × 0.7 rectangle covers 49 % of frame; a centred ellipse with the same major / minor axes covers ~38 % — landing the stub in the same coverage neighbourhood).

### Alternatives Considered

- **Exempt dev-stub builds from [Requirement 2.3](requirements.md#2.3)'s OOM ceiling**: Avoids the stub change — Rejected because it produces silent on-device-Debug regressions when developers test against `iPhone 13 Pro Max` builds.
- **Have the pre-shutter pass synthesise a centred ellipse without modifying the stub**: Decouples — Rejected because it puts dev-only logic in production code paths.

### Consequences

**Positive:**
- Dev-stub on-device builds exercise a realistic mask shape.
- Phase 1 → Phase 3 swap (`StubInferenceEngine` → `CoreMLInferenceEngine`) is a drop-in: the pre-shutter pass interprets both outputs identically.

**Negative:**
- The stub now lies about food classes (it returns a fixed palette label inside the ellipse), which is unchanged from today; tests already account for this.

---

## Decision 9: Introduce `SupportPlaneFitter` Protocol with Injectable Production Conformance

**Date**: 2026-06-13
**Status**: accepted

### Context

`Pipeline.fitSupportPlane` is a private helper inside `Pipeline.swift` that dispatches LiDAR-vs-card paths to the existing `LiDARPlaneFitter` and `CardOnlyPlaneFitter`. [Requirement 8.7](requirements.md#8.7) demands an integration test asserting byte-identity of the pre-shutter mask reaching `LiDARPlaneFitter.Inputs.foodRegionMask`. Without a seam this can only be done via `@testable import` and an internal mutable static — both fragile.

### Decision

Introduce a `SupportPlaneFitter` protocol in `MedataCore/Sources/SupportPlane/` with a single production conformance `LiDARSupportPlaneFitter`. `Pipeline` stores a `supportPlaneFitter: any SupportPlaneFitter`, injected via the constructor with a default of `LiDARSupportPlaneFitter()`. `PipelineFactory.makeForDevice` exposes the parameter so tests can inject a probe.

### Rationale

A small protocol with one production type and a constructor default is the minimum surface that makes Req 8.7 testable without `@_spi` or test-only hooks on `Pipeline`. The same protocol is the natural extension point if Phase 3 introduces alternate plane fitters (e.g., a stereo-only fitter for non-LiDAR devices).

### Alternatives Considered

- **Static testHook on `Pipeline`**: A `Pipeline.testHook_supportPlaneInputs: ((BinaryMask) -> Void)?` set via `@testable import` — Rejected because it couples production code to test infrastructure and leaves a sharp edge (a forgotten hook value carries between test cases).
- **Closure-based injection** (`lidarPlaneFit: (LiDARPlaneFitter.Inputs) throws -> SupportPlane` parameter on `Pipeline.init`): Most flexible — Rejected because it makes the public `Pipeline.init` signature dramatically wider for a single use case and confuses readers about what depends on what.

### Consequences

**Positive:**
- Integration test in [Requirement 8.7](requirements.md#8.7) is straightforward.
- Cleanly extensible for Phase 3 alternate fitters.
- No new public API on `Pipeline` beyond the constructor parameter.

**Negative:**
- One more protocol to maintain in MedataCore. Conformance is intentionally simple, so maintenance is minimal.

---

## Decision 10: Pre-Shutter Inference Runs at Native 1920×1440 Resolution

**Date**: 2026-06-13
**Status**: accepted

### Context

The pre-shutter pass needs to hit ≥ 2 Hz on iPhone 13 Pro Max iOS 26.5 ([Requirement 1.3](requirements.md#1.3)). Two options exist for input resolution:
- Native 1920×1440 — `CoreMLSegmenter`'s `SegmenterPreProcessor` already downsamples internally to 513×385 before inference and upsamples the mask back to native, so the wrapper is reused unchanged.
- Downsampled 960×720 — the pre-shutter producer builds a smaller `RawFrame` before calling the segmenter; the pre-processor runs on 1/4 the pixel count; the resulting mask is then nearest-upsampled to 1920×1440 inside `PreShutterSegmenter`.

The in-shutter pass at 1920×1440 takes ~720 ms (dev-stub log on 2026-06-13). Most of that cost is pre-processing — colour-space conversion, letterbox, FP16 packing — not inference itself.

### Decision

The pre-shutter pass runs at native 1920×1440 resolution. The same `CoreMLSegmenter` instance and `PipelineBridges.foodMask(from:palette:)` produce the published `BinaryMask` at native colour-image resolution.

### Rationale

- Reuses the in-shutter `CoreMLSegmenter` wrapper unchanged — no new pre-/post-processing code, no upsample step in `PreShutterSegmenter`, no parallel pixel-buffer plumbing.
- Removes any spatial-alignment ambiguity at shutter time: the mask the LiDAR fitter consumes is at the same resolution as the depth confidence buffer LiveSampleObserver currently sees.
- The 720 ms dev-stub measurement was on the in-shutter path which includes Logger overhead; the production Core ML engine in Phase 3 is faster on the ANE. If 2 Hz cannot be sustained on iPhone 13 Pro Max, the fallback is the downsampled-input variant; the design records both code paths but ships the native path first.

### Alternatives Considered

- **960×720 downsampled input + nearest-upsample**: ~4× less pre-processing work — Rejected because it adds a downsample/upsample pair that no other code path in the project has, and the spatial alignment risk at shutter time is real (the pre-shutter mask at 960×720 nearest-upsampled to 1920×1440 has 4-pixel quantisation, on the order of the centred-rectangle mask's quantisation, which is acceptable but adds untested code).
- **Decide at tasks-phase via baseline capture**: Drafts both — Rejected because it leaves a fork in the design and complicates the tasks list. The fallback documented here is enough to derisk the cadence target.

### Consequences

**Positive:**
- Smaller code change.
- Native-resolution mask aligns trivially with the captured nadir depth confidence buffer.
- Same wrapper used in-shutter and pre-shutter — one path to optimise.

**Negative:**
- If the 720 ms in-shutter measurement is representative, the producer cannot sustain 2 Hz under dev-stub builds. The first task in the implementation list captures the actual on-device latency and gates the design on it.

---

## Decision 11: Freeze the Pre-Shutter Mask at Nadir-Capture Instant

**Date**: 2026-06-13
**Status**: accepted

### Context

[Requirement 1.2](requirements.md#1.2) caps the pre-shutter mask's staleness at 750 ms relative to "the shutter-tap instant". The two-view path complicates this: the user taps shutter for the nadir frame, the model goes back to `.ready`, the user reframes, then taps shutter for the oblique frame. The `CaptureResult` is built at oblique-tap time. If the staleness check is applied at `CaptureResult` build time, the mask captured during nadir-framing is many seconds old and the path deterministically refuses.

### Decision

The pre-shutter mask is sampled and frozen at the moment `capture.end stage=nadir` fires. The frozen mask travels with `firstFrame` and `firstFrameTiltDeg` through the two-view dance and is read at `CaptureResult` construction time without an additional staleness check.

### Rationale

The mask is a spatial prior for the nadir frame's food region. Pairing them at nadir-capture time is the only semantically correct moment — the mask should describe what the user pointed at when they tapped the nadir shutter, not what they were pointing at later. The 750 ms ceiling guarantees the nadir-instant pairing is fresh; the oblique-tap-time elapsed seconds are irrelevant to that pairing.

### Alternatives Considered

- **Apply staleness check at `CaptureResult` build time**: Simplest reading of the requirement — Rejected because it deterministically refuses every two-view capture where the user takes longer than 750 ms between nadir and oblique taps, which is every realistic capture.
- **Re-sample the mask between nadir and oblique**: Use the pre-shutter producer's live mask at the oblique-tap moment — Rejected because the relevant food region is the one the nadir frame sees, not what the oblique frame sees. The oblique frame is angled and shows a different silhouette.

### Consequences

**Positive:**
- Two-view path works end-to-end without redefining "shutter-tap instant".
- Semantic invariant — mask describes the nadir frame's food region — is preserved.

**Negative:**
- `CaptureFlowModel` needs one more piece of mutable state (`firstFrameMaskBox`) and its lifecycle must mirror `firstFrame`'s (cleared on cancellation, backgrounding, refusal).

---

## Decision 12: Pre-Shutter and In-Shutter Use Separate `CoreMLSegmenter` Instances

**Date**: 2026-06-13
**Status**: accepted

### Context

Peer review identified that `MLModel` is not documented as concurrent-safe. A shared `CoreMLSegmenter` between pre-shutter (2 Hz) and in-shutter (shutter-tap) paths can race when the shutter fires while a pre-shutter inference is still in flight. `awaitPaused()` mitigates this only if reliably called and awaited before every in-shutter `segmenter.segment(_:)`.

### Decision

The pre-shutter and in-shutter paths each construct their own `CoreMLSegmenter` instance. Both wrap the same `MLModel` file path; each wrapper loads its own `MLModel` instance at app launch. No actor, no synchronisation, no shared inference state.

### Rationale

- Eliminates race risk by construction.
- `MLModel` load cost is < 50 ms once at app launch and zero at steady state.
- Cleaner than an actor-wrapped shared model, which would add a `await` boundary on every shutter-path inference and entangle the pause/resume contract.

### Alternatives Considered

- **Single shared `CoreMLSegmenter`, serialised via an `actor SegmenterCoordinator`**: One model load — Rejected because every shutter-path call gains an actor hop and the `awaitPaused()` contract becomes load-bearing for correctness rather than for cleanup.
- **Single `CoreMLSegmenter` with `Pipeline.estimate` calling synchronous `preShutterSegmenter.pauseAndAwait()` first**: Lighter than an actor — Rejected because it imports an App-target dependency into `Pipeline.estimate`, breaking the MedataCore boundary.

### Consequences

**Positive:**
- Race-free by construction; no synchronisation primitives to maintain.
- Pre-shutter pause/resume becomes a cleanup concern (don't waste cycles) rather than a correctness one.

**Negative:**
- Two `MLModel` instances loaded; in Phase 3 this is a measurable memory cost (TBD by the baseline capture).

---

## Decision 13: Snapshot-Then-Pause Atomicity via `awaitPaused()`

**Date**: 2026-06-13
**Status**: accepted

### Context

Peer review identified a TOCTOU between `firstFrameMaskBox = preShutterSegmenter.latest` and `preShutterSegmenter.pause()`. An in-flight inference completing between the two writes can overwrite `latest` so the consumer sees a different mask than the one inspected.

### Decision

`PreShutterSegmenter` exposes both `pause()` (fire-and-forget, callable from `didSet` / non-async sites) and `awaitPaused()` async. `CaptureFlowModel.performFlow` calls `await preShutterSegmenter.awaitPaused()` immediately after `capture.end stage=nadir` and *before* reading `latest`, so the read is guaranteed atomic with respect to inference completion.

### Rationale

`performFlow` is already async; awaiting one drain at the nadir-capture instant is cheap and trivially correct. The `pause()` variant remains for non-async state-machine sites that don't have a snapshot to make.

### Alternatives Considered

- **Make `latest` immutable once `pause()` is called**: A pause flag inside the producer that rejects further publishes — Rejected because it bakes a state machine into the producer; `awaitPaused()` is simpler.
- **Snapshot via an explicit `snap() async -> TimestampedMask?` method that drains then returns**: Conflates two operations — Rejected because callers sometimes want the most recent value without pausing (e.g., a future telemetry probe).

### Consequences

**Positive:**
- Snapshot reads are deterministic.
- The non-async `pause()` is still available for `didSet` callsites.

**Negative:**
- `awaitPaused()` blocks `performFlow` for up to the inference latency (< 1 s on dev-stub). Acceptable inside the shutter-tap-to-`estimate.start` window.

---

## Decision 14: Coverage Computation Runs in Confidence-Buffer Space (256×192)

**Date**: 2026-06-13
**Status**: accepted

### Context

The food-region mask is at colour-image resolution (1920×1440). The LiDAR confidence buffer (`ARFrame.sceneDepth.confidenceMap`) is at LiDAR-native resolution (256×192 on iPhone 13 Pro Max). Decision 10's claim that "the mask aligns trivially with the depth confidence buffer" is wrong — there's a 7.5× horizontal mismatch. The design must pin which space the percentage is computed in.

### Decision

Coverage is computed in confidence-buffer space. For each `(cx, cy)` confidence-buffer pixel, the corresponding mask pixel is `(mx, my) = floor(cx · W_colour / W_conf, cy · H_colour / H_conf)`. The percentage is `100 · (count of food-and-high-confidence pixels) / (count of food pixels in confidence space)`.

### Rationale

- The confidence buffer is the smaller side; iterating 256·192 = 49,152 pixels is cheap. Iterating 1920·1440 = 2,764,800 pixels would be 56× more work for no additional signal — neighbouring 56-pixel blocks of the mask map to a single confidence value.
- The pattern matches `LiDARPlaneFitter.foodMaskHasFoodAt(dx:dy:)` in `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift`, so reviewers can cross-check the algebra against an existing call site.
- A future Phase 3 change to a higher-resolution depth source (e.g., upsampled depth from CoreML) drops in without changing the percentage semantics.

### Alternatives Considered

- **Upsample confidence to colour resolution (1920×1440) and iterate the mask**: 56× more work; introduces a choice of upsampling filter (nearest vs bilinear) that affects the result — Rejected as wasteful and arbitrarily filter-dependent.
- **Downsample mask to confidence resolution via majority-vote**: Pre-downsample once, then iterate — Rejected because the per-call iteration is cheap enough that pre-downsampling adds a code path for no benefit.

### Consequences

**Positive:**
- O(W_conf · H_conf) coverage compute = ~50 000 operations per shutter-tap.
- One algorithm, one space, no filter choice.

**Negative:**
- A 56-pixel mask block votes as a single bit through the floor-projection. Edge fidelity at the food/table boundary is lost in confidence space; for the coverage percentage (an aggregate, not a per-pixel result) this is irrelevant.

---

## Decision 15: Req 4.5 Logs `foodRegionCoveragePercent` at `estimate.end`, Not `estimate.start`

**Date**: 2026-06-13
**Status**: accepted

### Context

[Requirement 4.5](requirements.md#4.5) reads "`event=estimate.start` SHALL log the food-region coverage value alongside the existing `capturePath` field". But `foodRegionCoveragePercent` is computed inside `Pipeline.estimate`, after `fitSupportPlane` returns — the value does not exist when `estimate.start` fires at function entry. Peer review flagged this as a Req-vs-design contradiction.

### Decision

Req 4.5's intent is honoured by appending `foodRegionCoveragePercent=<float>` to the existing `event=estimate.end` log line, which fires at function exit alongside the existing `success` / `failure` fields. `event=estimate.start` is augmented only with `maskAgeMs=<int>` (which IS known at function entry).

### Rationale

The corrected coverage value is for telemetry/diagnostics, not for path selection (Decision 1). Diagnostic value is preserved whether the line fires at start or end. The end position is the only honest one — start can't see the value.

### Alternatives Considered

- **Carve a new event `event=estimate.coverage`**: Distinct line — Rejected because it splits the trail; existing readers tail `estimate.end` for success/failure and would have to read a second line.
- **Compute the value before `fitSupportPlane` (early)**: Would require lifting the LiDAR-confidence iteration out of the support-plane code path — Rejected as architecturally backwards.

### Consequences

**Positive:**
- One log line carries success/failure AND the corrected coverage value.
- No new event names to maintain or grep.

**Negative:**
- Req 4.5 wording becomes an erratum (intent honoured at a different line); update the spec text in a follow-up edit so future readers don't re-litigate.

---

## Decision 16: Dev-Stub Segmenter Latency Starves the AR Session — Measure in Release Before Treating as a Defect

**Date**: 2026-06-23
**Status**: accepted (Release measurement confirms Debug artifact — no code fix scheduled; see Update)

### Update (2026-06-23, Release measurement)

A Release-optimised dev-stub build (temporary unconditional `DEV_STUB_SEGMENTER`, reverted after build) was installed on the iPhone 13 Pro Max and re-captured in single mode (same segmentation code path as two-view):

- **Segmentation substages: preprocess 739 ms (Debug ~1668 ms), inference 52 ms (Debug ~92 ms).** Postprocess end line not yet captured (paste truncated at `postprocess start`) — but the estimate completed and persisted a record.
- **Zero `ARSession … retaining` warnings and zero `cadence.miss` lines across the entire run** (Debug had them continuously). The live gating loop streamed smoothly.

A second clean Release single-mode capture removed all doubt: the **full estimate (CardDetection→SupportPlane→Segmentation→Volume→Macros→Confidence→Persistence) ran start-to-finish in 827 ms** (`estimate.start` 01:11:18.243 → `estimate.end success=true` 01:11:19.070, persisted), and the `capture.end`→`estimate.start` gap collapsed from ~28 s (Debug) to **143 ms**. Segmentation is therefore sub-827 ms in Release vs **24,960 ms** in Debug — a ~30× swing, entirely the optimiser.

Conclusion: the AR-frame starvation and the 27–50 s latencies were a **Debug `-Onone` artifact**, not a code defect. The mitigations in the Decision below are **not scheduled**; the Track-3 real model is the permanent resolution. Re-open only if a Release build ever shows `retaining`/`cadence.miss` again.

### Context

A two-view device drive on 2026-06-23 (Debug `-Onone` build) surfaced a cluster of AR-session symptoms tied to the pre-shutter loop this spec designed (Decisions 10–13):

- `ARSession … is retaining 11–13 ARFrames … the camera will stop delivering camera images` — repeated.
- `event=preshutter.cadence.miss expectedHz=2 actualMs=36000–51000` — the 2 Hz pre-shutter cadence (Decision 10) collapsed to ~0.02 Hz.
- `event=preshutter.mask.update … source=pre_shutter_stub latencyMs≈35000–50000` — each dev-stub `segment()` cycle takes 35–50 s.
- Consequential media noise: `FigCaptureSourceRemote … err=-17281` and `(Fig) signalled err=-12710` clustered at SupportPlane (the camera stalling under frame-retention back-pressure), plus benign `Could not resolve material name 'engine:…/AR/*.rematerial'` RealityKit fallbacks.

Root cause: the dev-stub `CoreMLSegmenter` runs the full 27-class preprocess→inference→postprocess (513×385 upscaled to 1920×1440) on every pre-shutter cycle. In `PreShutterSegmenter.resume(frames:)` the bound `ARFrame` stays retained for the entire ~30–50 s `segment()` call, so frames pile up faster than the loop drains them and ARKit throttles the camera. The work is off-MainActor, so it does **not** block tab switching (the separately-reported stuck tab bar is a different issue).

### Decision

Do **not** treat the ARFrame retention as a code defect yet. First re-measure the same two-view trail on a **Release** build (the postprocess hot passes were already parallelised in `e425543`; the missing factor is the optimiser, expected ~10×). If the starvation persists in Release, the fix is, in order: (a) release/copy out of the `ARFrame` before calling `segment()` so it is not retained across the inference; (b) skip or throttle the full pre-shutter segmentation while `segmenterSource == "dev_stub"` (the stub mask is constant — `foodPixels=1052134` every cycle — so the expensive path buys nothing). The ultimate resolution is the Track-3 real model (tens of ms/inference), which dissolves the back-pressure entirely.

### Rationale

The headline latencies (27–50 s) are almost certainly a Debug `-Onone` artifact; optimising against them would be measuring a number that does not exist in a shippable build. Gating the fix on a Release measurement right-sizes the work before any code changes. The dev-stub gate keeps the mitigation out of App Store builds automatically.

### Alternatives Considered

- **Fix the retention immediately (restructure the loop now)**: Rejected for now — risks reworking the Decision 12/13 concurrency contract against a latency that Release may erase.
- **Cancel the inflight segment on back-pressure**: Rejected — Decision 13's snapshot-then-pause atomicity depends on the inflight cycle draining, not being cancelled (this was the smolspec H4 regression).

### Consequences

**Positive:** Avoids premature rework of a delicate concurrency contract; cheap to validate; self-retires with Track 3.

**Negative:** Live preview remains sluggish on dev-stub Debug builds until either the Release retest or Track 3; demos must use Release or accept the lag.

### Impact

`App/PreShutterSegmenter.swift` (the `resume(frames:)` inference loop and ARFrame lifetime), the dev-stub `CoreMLSegmenter`, and the pre-shutter cadence contract (Decisions 10–13). No change to the in-shutter pipeline path.

---

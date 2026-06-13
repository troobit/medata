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

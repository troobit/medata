# Decision Log: UI

## Decision 1: Manual shutter button (not auto-capture)

**Date**: 2026-05-20
**Status**: accepted

### Context

The research spec's capture flow (§3 of `specs/research/requirements.md`) describes conditions under which a capture is valid (tilt within ±5° of the target axis, distance 25–50 cm with LiDAR, working-distance guidance 30–40 cm without). It does not specify whether the system auto-fires when conditions are met or whether the user explicitly triggers each capture.

### Decision

The v1 UI uses a manual shutter button. The button is enabled only when all gating conditions are satisfied (tilt in range, distance OK, no in-flight estimation). The user explicitly taps to capture each view.

### Rationale

Manual capture is more predictable, easier to test (snapshot tests cover enabled vs disabled states; UI tests cover taps), and matches the iOS Camera app's mental model. Auto-capture would add a "shot fired without my intent" failure mode that's expensive to debug, and would require additional UX work (false-trigger guards, dwell-time tuning, an "I changed my mind" affordance).

### Alternatives Considered

- **Auto-capture when conditions met**: Hands-free, but harder to make feel right — false triggers, premature shots, no "I changed my mind" affordance. Rejected as research-app rather than product UX.
- **Hybrid green-light + tap**: Indicators light green when conditions are good but the user still taps. Functionally equivalent to manual shutter (the disabled-shutter state is the "red light"). Rejected as adding visual complexity without behavioural difference.

### Consequences

**Positive:**
- Simple state machine: idle → conditions-met → tap → captured → next-stage-or-estimate.
- Trivially testable with XCUITest / SwiftUI snapshot tests.
- Predictable user mental model.

**Negative:**
- One extra interaction step versus auto-capture.

---

## Decision 2: View-last-meal-only scope (no persistent history list in v1)

**Date**: 2026-05-20
**Status**: accepted

### Context

The persistence layer (research spec §14–§15) stores every meal as a row in `meals.sqlite` plus a per-meal artefact directory. The research spec is silent on whether the UI exposes browsing across persisted meals.

### Decision

v1 ends at the post-capture result view. The only persistent egress from the local store is the archive-export control in Settings (research Req 15.8) which produces a zip via the existing `ZIPFoundation`-backed export. No history-list UI, no detail-by-id navigation, no search/filter.

### Rationale

The persistence layer already does its job — meals are durably saved. A history-browsing UI is a substantial design problem in its own right (sorting, search, charts, deletion affordances, multi-day summaries) and would inflate this spec's scope without unblocking the demo path. Archive export is enough to bring data into other tooling for inspection.

### Alternatives Considered

- **Simple flat history list**: A 'History' tab with date + carb total + confidence per row. Rejected as scope creep — adds a navigation pattern, list-cell design, deletion UX, and a swipe-action layer that this spec doesn't need.
- **History with search / filter / charts**: Full product-app experience. Rejected as far too broad for v1.

### Consequences

**Positive:**
- Minimal screen count: capture → result → settings.
- Archive export is testable in isolation.
- A future `specs/history` spec can layer browsing in without rework here.

**Negative:**
- User cannot inspect past meals from inside the app — only via the exported archive.

---

## Decision 3: Carbs + confidence pill only on result view (no per-class breakdown, no clinical macros)

**Date**: 2026-05-20
**Status**: accepted

### Context

Research Req 12.4 displays the meal-total carbohydrate value to 1 g. Req 12.6 explicitly says clinical macros (energy, protein, fat, fibre) are *computed and persisted* but NOT surfaced to the user in v1. Per-class carb breakdown is not explicitly forbidden but is unspecified.

### Decision

The result view shows two things: total meal carbs in grams (rounded to 1 g), and a three-state `σ_meal` confidence pill ("High" / "Moderate" / "Low" with thresholds 0.75 / 0.60). When `σ_meal < 0.60` an uncertain-estimate prompt is also shown (research Req 13.5). No per-class breakdown, no clinical macros.

### Rationale

The spec's framing is diabetes-bolus-calculator: the user needs one number to decide on insulin dosing. Per-class breakdown is useful for engineers sanity-checking the segmenter, but irrelevant to the target user. Clinical macros are explicitly excluded by Req 12.6.

### Alternatives Considered

- **Carbs + per-class breakdown**: Adds engineering-grade information to a user-facing screen. Rejected for v1; better placed in a dev-mode diagnostic view if needed.
- **Carbs + per-class + clinical macros**: Crosses Req 12.6 ("computed but not surfaced"). Would require an amendment to the research spec. Rejected.

### Consequences

**Positive:**
- Smallest result view; aligns with the bolus-calculator use case.
- One less surface for the segmenter's per-class confidence to mislead users.

**Negative:**
- A user mis-classification (e.g. rice classified as bread) is harder to spot from carb total alone.

---

## Decision 4: Neutral SwiftUI / iOS 17 baseline (no Liquid Glass)

**Date**: 2026-05-20
**Status**: accepted

### Context

We're building on Xcode 26.5 with the iOS 26 SDK available, but research Req 1.2 sets the OS floor at iOS 17. The Xcode 26 SDK exposes new Liquid Glass materials, but they're only available on iOS 26+.

### Decision

UI targets the iOS 17 SwiftUI API surface only: `NavigationStack`, `Form`, `Picker`, `Toggle`, `Button`, etc. No Liquid Glass materials, no `if #available(iOS 26)` branches in v1. Brand colour (`#63ff00`) is set as the app accent colour and adapts naturally to light / dark mode via SwiftUI's standard semantics.

### Rationale

Minimum API surface = smallest code path = least visual QA per OS version. iOS 26 refinements can be added in a sibling spec once we know what the v1 layout actually looks like on real devices. There's no current product driver to adopt Liquid Glass; it would be cosmetic effort on top of solving the real UX problems.

### Alternatives Considered

- **iOS 26 Liquid Glass with iOS 17 fallback**: Two code paths per surface. Rejected as cosmetic at v1 stage.
- **iOS 26 only — raise OS floor**: Would amend research Req 1.2. Out of scope for this spec.

### Consequences

**Positive:**
- One code path per screen.
- Behaves identically on every supported device.

**Negative:**
- Doesn't take advantage of Xcode 26's newest design system. Easy to revisit later.

---

## Decision 5: Refusal handled inline with retry-in-place (camera stays live)

**Date**: 2026-05-20
**Status**: accepted

### Context

`Pipeline.estimate(_:)` throws `EstimationFailure` cases with localised Irish-English messages (research Req 19.1, task 52). The UI needs to surface these and let the user try again. Two patterns are reasonable: full-screen modal forcing a flow restart, or an inline banner.

### Decision

Refusal is surfaced as an inline banner on the capture view. The AR session stays live. A "Try again" control re-arms the shutter at the same capture stage and dismisses the banner.

### Rationale

The user is iterating — they got a refusal, they want to change something (move the card, level the device, get closer) and try again. Forcing a flow restart adds steps that don't help. Keeping the camera live means immediate retry; the banner overlay is dismissable without state loss.

### Alternatives Considered

- **Full-screen modal, force restart**: More 'final' feeling, bad for repeated retries during user learning. Rejected.
- **Inline + offer 'Use card-only path' suggestion when LiDAR refused**: Path-suggestion logic adds UI complexity. Rejected for v1; a later spec can add intelligent path suggestions.

### Consequences

**Positive:**
- One-tap recovery from refusals.
- Minimal new UI (a banner + a button).

**Negative:**
- Banner could be missed if dismissed by an accidental tap on the capture view; addressed by design choosing a non-dismissable banner or one that stays until "Try again" is tapped.

---

## Decision 6: Corrections UI out of scope for v1

**Date**: 2026-05-20
**Status**: accepted

### Context

Research Req 14.2 says the persistence layer supports user corrections (append-only, never mutates the original `MealRecord`). The UI could expose this as per-class numeric overrides or as a meal-total adjustment.

### Decision

No corrections UI in v1. The persistence support stays untouched; the result view simply shows the engine's estimate.

### Rationale

Corrections UI is a non-trivial design problem (which classes to allow editing, how to recompute the total client-side without re-running the pipeline, how to display "estimate vs corrected" history). Solving it here would inflate the spec by ~150 LOC of UI + state. A sibling spec can do it properly.

### Alternatives Considered

- **Simple per-class numeric override**: Tap a class, adjust mass / carbs, append a `UserCorrection`. Rejected as a separate UX problem.

### Consequences

**Positive:**
- v1 result view stays small (carb total + confidence pill).
- Persistence layer remains exercised by the auto-saved `MealRecord` from the engine.

**Negative:**
- Users can't override the engine's estimate from inside v1 of the app.

---

## Decision 7: Brand assets sourced from `static/` on `main` (logo + accent colour)

**Date**: 2026-05-20
**Status**: accepted

### Context

The repo's `main` branch carries the canonical brand assets in `static/` — `icon.svg` (1024×1024 logo, brand colour `#63ff00`) plus three favicon SVGs (`favicon-colour.svg`, `favicon-contrast.svg`, `favicon-default.svg`) and a `favicon.ico`. The current research branch retains only the three favicon SVGs (per commit `08641b0`); `icon.svg` and `favicon.ico` are not yet on this branch.

### Decision

The iOS app's brand identity (AppIcon, accent colour, in-app brand marks) is sourced from `static/` on `main`. Specifically: AppIcon is rendered from `static/icon.svg`; the app's accent colour is `#63ff00` (from the icon's `stroke` attribute); any in-app brand mark uses one of the existing `static/favicon-*.svg` files chosen by design. Brand assets missing from the research branch are ported from `main` as implementation tasks.

### Rationale

A single brand master prevents drift between web and iOS surfaces. The SVG sources are vector and re-render cleanly to all Apple-required AppIcon sizes. Sourcing from `main` rather than re-creating ensures iOS matches the existing favicon visuals that users will already have seen.

### Alternatives Considered

- **Generate iOS-specific brand assets**: Would create drift between platforms. Rejected.
- **Use Apple's default accent colour**: Loses brand identity. Rejected.

### Consequences

**Positive:**
- Single source of truth for brand.
- Vector source → all required Apple AppIcon sizes generated from one master.

**Negative:**
- `static/icon.svg` and `static/favicon.ico` need to be ported from `main` to the research branch as part of implementing this spec — captured as an implementation task in Phase 4.

---

## Decision 8: Confidence-pill thresholds and UI responsiveness floors

**Date**: 2026-05-20
**Status**: accepted

### Context

`requirements.md` §9.2 introduces a three-state confidence pill ("High" σ ≥ 0.75, "Moderate" 0.60 ≤ σ < 0.75, "Low" σ < 0.60). §15.1–§15.2 mandate a 30 fps camera-preview floor; §15.3 mandates a 100 ms shutter-tap-to-busy-state latency. None of these specific numbers come from `specs/research/`. The research spec gives one threshold (Req 13.5, σ < 0.60 triggers the uncertain-estimate affordance) and one performance figure (Req 16.1/16.7, P95 end-to-end pipeline budget ≤ 1000/1800 ms — a wall-clock figure, not a UI responsiveness floor).

### Decision

- The "Low" confidence boundary (σ < 0.60) matches research Req 13.5 verbatim.
- The "High" confidence boundary (σ ≥ 0.75) is introduced by this spec as the midpoint between Req 13.5's threshold and full confidence (1.0). The intent is a visually informative middle band: "estimate is acceptable but not bulletproof" sits between 0.60 and 0.75.
- The 30 fps camera-preview floor is the iOS-standard "smooth" baseline and is what `ARKitCaptureEngine` already publishes at on the iPhone 13 Pro test device.
- The 100 ms tap-to-busy-state latency is the Nielsen "instantaneous" perception threshold and a standard floor for one-shot UI actions.

### Rationale

Picking concrete numbers in the requirements document is necessary because "feels responsive" is not testable. The chosen values are conservative defaults backed by industry conventions and the existing capture engine's measured behaviour rather than by amendment to the research spec. They can be tightened later if testing on real devices shows headroom; the requirement is the floor, not the target.

### Alternatives Considered

- **Defer all numeric UI floors to design phase**: Rejected because §15 is a non-functional requirement and the skill checklist requires concrete measurable targets ("SHALL be performant" is not acceptable).
- **Add the 0.75 threshold to research spec via amendment**: Rejected as overreach — the research spec's job is the algorithm, and confidence-state visual mapping is a UI concern.
- **Use only the 0.60 threshold and a binary "OK / Low" pill**: Rejected because users will reasonably ask "is 0.8 the same as 0.62?". Three states convey gradient without exposing raw σ.

### Consequences

**Positive:**
- Performance ACs are concretely testable on the iPhone 13 Pro test device with Instruments or XCTClockMetric.
- The 0.75 boundary is documented as a UI-spec invention, not a research-spec leak.

**Negative:**
- The 0.75 threshold is an opinion, not data-driven. A future spec may revise it based on user feedback or fixture-set analysis.
- The 30 fps floor is conservative; iPhone 13 Pro typically does 60 fps preview. If a future requirement needs the headroom, this floor can be raised.

---

## Decision 9: Inter-class occlusion signal surfaced only via σ_meal (no separate UI element)

**Date**: 2026-05-20
**Status**: accepted

### Context

`CaptureFlowDelegate.didDetectInterClassOcclusion()` is published from inside `Pipeline.estimate(_:)` (research design §10, called from `Pipeline.swift:178`). The signal feeds the `σ_occl` sub-confidence per research Req 13.2. It also implicitly suggests a user-facing prompt (the research spec mentions a "two-view-opt-in" affordance triggered by occlusion). But occlusion is detected DURING the pipeline run, not before — the UI would be in its §8 busy state when the signal arrives.

### Decision

The v1 UI does not surface inter-class occlusion as a dedicated UI element. The signal flows into `σ_meal` per research Req 13.2 and reaches the user as a lower confidence pill on the result view — possibly tripping the §9.3 uncertain-estimate prompt if σ falls below 0.60.

### Rationale

A mid-busy-state informational toast would require a new UI pattern (background notification during a modal blocking state) that nothing else in this spec uses. The occlusion signal is already weighted into `σ_meal` algorithmically; users see the impact via the confidence pill. If users routinely see "Moderate" confidence in occlusion-prone scenes, a future spec can add an explicit "Use two views" prompt at the start of the next capture.

### Alternatives Considered

- **Mid-busy informational toast**: Adds a one-off pattern. Rejected for v1.
- **Pre-capture two-view suggestion on each shot**: Would require pre-capture occlusion detection, which the current pipeline doesn't do. Rejected as out of scope.
- **Result-view "occlusion detected" badge**: Adds a result-view element not specified in this spec; could be added later without rework if needed.

### Consequences

**Positive:**
- Avoids inventing a new UI pattern.
- Algorithm already handles occlusion via σ_occl per Req 13.2.

**Negative:**
- Users don't get explicit feedback that occlusion specifically was the reason for a low confidence — they just see "Low".

---

## Decision 10: Accessibility / VoiceOver work out of scope for v1

**Date**: 2026-05-20
**Status**: accepted

### Context

An earlier draft of `requirements.md` included §14 "Accessibility" with three acceptance criteria covering VoiceOver labels on live indicators, accessibility-announcement notifications on qualitative state changes, and VoiceOver focus-order requirements for the shutter. The research spec carries no accessibility requirement — Req 19 is about Irish/British English copy, not assistive technology.

### Decision

Accessibility work (VoiceOver labels, dynamic-type sizing, accessibility announcements, focus-order requirements, contrast checks beyond default SwiftUI behaviour) is out of scope for this UI spec. The section was removed from `requirements.md`; this decision documents the reasoning so a future spec can pick it up cleanly.

### Rationale

The research spec sets no accessibility floor. Adding three ACs purely on agent initiative would inflate testing scope (every state-change AC would need an accessibility-announcement variant), demand a parallel design pass to choose accessibility labels per indicator state, and complicate the test matrix without addressing a user need that has been raised. SwiftUI's default behaviour does the easy parts (Button gets a default accessibility label, navigation titles are announced, etc.) — so the floor is non-zero even without explicit requirements. When accessibility is in scope, it deserves its own dedicated spec covering VoiceOver, Voice Control, Dynamic Type, Switch Control, and reduced-motion in one consistent pass.

### Alternatives Considered

- **Keep §14 as-is**: Three ACs add measurable scope to both the design and tasks phases. Rejected — premature for MVP.
- **Keep one minimal AC ("indicators expose default SwiftUI accessibility labels")**: Rejected as either trivially true (free from SwiftUI) or a foot in the door that grows without clear ownership.
- **Add to a sibling spec immediately**: Rejected; no need to create a parallel-track spec without a current user need.

### Consequences

**Positive:**
- Removes three ACs of testing/design overhead from MVP.
- Cleaner scope: this spec is purely the capture flow.

**Negative:**
- The app's first release will rely on SwiftUI's default accessibility behaviour without a written contract for that floor. Users relying on assistive technology may encounter inconsistencies that a dedicated future spec will need to remediate.

---

## Decision 11: Live AR frames exposed via `AsyncStream<ARFrame>` from `ARKitCaptureEngine`; delegate stubs remain dormant

**Date**: 2026-05-21
**Status**: accepted

### Context

`MedataCore`'s `CaptureFlowDelegate` declares four methods: `didUpdateTilt(angleDegrees:)`, `didUpdateLiDARCoverage(percent:)`, `didDetectInterClassOcclusion()`, `didProduceEstimate(_:)`. Only the last two have producers in `Pipeline.estimate(_:)`. The UI needs live tilt + coverage + distance before `Pipeline.estimate` runs.

An earlier draft of this decision (rejected by review) proposed UI-side `Timer` polling of `arSession.currentFrame`. Both the design-critic and peer-review reviewers flagged that as wrong-shape: `currentFrame` updates per `ARSessionDelegate.session(_:didUpdate:)` and polling drifts off-frame, risking dropped UI updates and jank against the §14.2 30 fps preview floor.

### Decision

`ARKitCaptureEngine` exposes three additive accessors:

```swift
public extension ARKitCaptureEngine {
    var arSession: ARSession                                 // for ARView preview binding
    var frames: AsyncStream<ARFrame>                         // per-frame live observation
    enum InterruptionEvent: Sendable { case began, ended }
    var interruptions: AsyncStream<InterruptionEvent>        // sessionWasInterrupted/Ended
}
```

The UI's `LiveSampleObserver` iterates `frames` and computes tilt + distance + LiDAR coverage per frame, writing to a child `@Observable LiveIndicatorModel` (split from `CaptureFlowModel` to bound redraws). The two unproduced `CaptureFlowDelegate` methods (`didUpdateTilt`, `didUpdateLiDARCoverage`) stay on the protocol as forward-compat stubs; `CaptureFlowModel`'s conformance to them is no-op.

### Rationale

`AsyncStream` is structured-concurrency-native, back-pressured (`BufferingPolicy.bufferingNewest(1)` means slow consumers get the latest frame), and avoids the drift problem of polling. Implementation is ~25 lines per stream — the cost reviewer-cited "non-trivial Sendable plumbing" of an earlier draft is overstated for a per-subscriber continuation pattern. Streams are CaptureKit-internal and don't touch the existing `ARSessionDelegate` registration — the engine remains the sole session delegate.

### Alternatives Considered

- **UI-side `Timer` / `CADisplayLink` polling of `arSession.currentFrame`**: Polling drifts off-frame; rejected.
- **Add producers for the delegate methods inside `Pipeline.estimate`**: The delegate methods are pre-capture live signals, but `Pipeline.estimate` only runs at-capture-time. Wrong lifecycle. Rejected.
- **Remove the unproduced delegate methods**: Would break the shipped protocol and require Pipeline.swift changes for no functional benefit. Rejected for v1; a future spec can clean up.

### Consequences

**Positive:**
- Live observation runs at exactly ARKit's frame-delivery cadence, no drift.
- Structured concurrency throughout; cancelling iteration is the unsubscribe mechanism.
- The same `frames` stream can later feed multiple consumers (preview overlay, ML pre-detection, tracking-quality readouts) without re-engineering.

**Negative:**
- Three accessors on `ARKitCaptureEngine` widen the CaptureKit public surface area (~40 lines total).
- The two dormant delegate methods remain on the shipped protocol; future cleanup is a separate spec.
- Live observation duplicates depth+confidence statistics that `Pipeline.estimate` computes internally (research design §6.0). The live observer's centre-crop median is much cheaper than the full pipeline pass and won't dominate the per-frame budget.

---

## Decision 12: Pipeline cancellation deferred — req §8.3 enforced best-effort for v1

**Date**: 2026-05-21
**Status**: accepted

### Context

Requirements §8.3 says no partial `MealRecord` should be persisted from a cancelled estimation. But `MedataCore/Sources/Pipeline/Pipeline.swift` (verified by design-critic grep) contains zero `Task.checkCancellation()`, `Task.isCancelled` checks, or `withTaskCancellationHandler` wrappers. The eight signposted pipeline stages and the closing persistence `INSERT` run to completion regardless of `Task.cancel()` from the UI.

### Decision

Defer the underlying Pipeline-cancellation work to a future sibling spec. For v1: §8.3 is enforced **for UI state only** — backgrounding during in-flight estimation resets the UI to `.initialising` on foreground, and the model ignores the eventual `MealRecord` return. The persisted store may still contain the meal. The requirements doc carries a Known Limitation note pointing at this decision.

### Rationale

Adding cancellation checkpoints to Pipeline.swift is a small (~30 LOC) but cross-cutting change spanning eight stages plus the persistence boundary. It deserves its own spec where the cancellation contract — at-stage-boundary granularity, idempotent cleanup, GPU-buffer reclamation, persistence rollback semantics — can be designed properly. Punting it into this UI spec would expand scope and entangle two distinct contract changes.

### Alternatives Considered

- **Add the cancellation checkpoints as part of this spec**: Rejected — couples UI work to a cross-cutting Pipeline contract change; one of them blocks the other.
- **Weaken req §8.3 to remove the persistence guarantee entirely**: Rejected — the requirement captures real user expectation (a backgrounded capture shouldn't leave a ghost meal). Keeping it visible with a "known limitation" note flags the gap for the next spec rather than burying it.
- **UI-side cleanup that deletes any meal persisted within the cancellation window**: Rejected — racy (the meal-creation timestamp doesn't tell us "this was cancelled"); brittle and out of scope.

### Consequences

**Positive:**
- This spec stays focused on UI.
- The persisted-store gap is documented and discoverable from both the requirements doc and the decision log.

**Negative:**
- Until the sibling cancellation spec lands, users who background the app mid-estimation will see a ghost meal appear in their history (no UI to surface it in v1, but it'll be in the archive export and in any future history UI).

---

## Decision 13: `PipelineEstimator` test-injection protocol lives in MedataCore

**Date**: 2026-05-21
**Status**: accepted

### Context

`CaptureFlowModel` calls `Pipeline.estimate(captureResult:)`. For state-machine unit tests (~15–25 cases) we need to inject a mock pipeline that returns programmable `Result<MealRecord, Error>` without spinning up a real `Pipeline` (which would require the Core ML segmenter weights — currently not bundled, gated by a separate deferred smolspec — plus a real `FoodDatabase` and `PersistenceStore` with ~500 ms init cost).

### Decision

Add a 6-line `PipelineEstimator` protocol to MedataCore:

```swift
// MedataCore/Sources/Pipeline/PipelineEstimator.swift
public protocol PipelineEstimator: Sendable {
    func estimate(captureResult: CaptureResult) async throws -> MealRecord
}
extension Pipeline: PipelineEstimator {}
```

`CaptureFlowModel` holds `any PipelineEstimator`. Tests pass a `MockPipeline: PipelineEstimator` struct.

### Rationale

Placing the protocol in MedataCore (not in `App/`) is cleaner because the abstraction is API-shaped: it's the published "what does the pipeline do?" contract, and the UI's testability happens to be the immediate consumer. A protocol in `App/` would be a UI-shaped abstraction over a foreign concrete type — awkward inversion. The ~6-line addition is the smallest possible test seam; it lets the UI spec stand alone without depending on the deferred segmenter smolspec.

### Alternatives Considered

- **Protocol in `App/`**: Existential overhead is negligible (one `await` per capture), but the API-shaped abstraction lives in the wrong layer. Aesthetic but real.
- **No protocol; test against real `Pipeline` with fixture `CaptureResult` inputs**: Blocked on segmenter weights being bundled (deferred smolspec). Each test pays ~500 ms+ for real pipeline init. Tests become integration-flavoured rather than unit-flavoured. Rejected.

### Consequences

**Positive:**
- UI spec is independently shippable; segmenter smolspec is no longer a prerequisite.
- The seam is a single public protocol — minimal surface widening.
- Future non-UI consumers (alternate orchestrators, harness mocks) can use the same seam.

**Negative:**
- Adds one public protocol to MedataCore that exists primarily for testability today.

---

## Decision 14: Engine adopts the preview ARView's session (single-session correction)

**Date**: 2026-05-23
**Status**: accepted

### Context

Decision 11 specified that `ARKitCaptureEngine` owns the one `ARSession` and exposed `arSession` "for ARView preview binding". The implementation took that literally: the engine created its own `ARSession()` and the `ARPreviewView` created an `ARView` (which has its own internal session). `ARView.session` is get-only, so the engine's session could never be injected into the view — leaving two live `ARSession` instances. Two AR sessions contend for the single camera capture source, producing repeated `FigCaptureSourceRemote` failures (`err=-12784`, XPC `err=-17281`) and a `sessionWasInterrupted`/`sessionInterruptionEnded` loop that flashed the UI between `.initialising` and `.trackingLost`. The camera preview never stabilised.

### Decision

The engine adopts the ARView's session as the one authoritative `ARSession`. `ARKitCaptureEngine.bindPreviewSession(_:)` (called from `ARPreviewView.makeUIView`/`updateUIView`) takes ownership of the view's session: sets the engine as its sole delegate and runs the world-tracking config on it. The engine no longer runs its placeholder session; `start()` records intent and defers the `run` to bind time if the view is not yet up. A `isRunning` guard ensures repeated `updateUIView` binds re-assert the delegate without resetting tracking. All session access is on the main actor.

### Rationale

`ARView` always creates and renders from its own `ARSession` and never accepts an external one. The only way to have exactly one session while still using `ARView` for passthrough is to make that session the authoritative one and drive it from the engine. This preserves Decision 11's intent (one session, engine is sole owner/delegate) and removes the camera contention that was the root cause of the unstable preview.

### Alternatives Considered

- **Keep two sessions, only re-assert the engine delegate** (the prior code): Rejected — it cannot work; the view renders from a different session than the one the engine drives, and two sessions fight for the camera.
- **Drop `ARView`, render `engine.frames` (capturedImage) in a custom Metal/AVSampleBufferDisplayLayer view**: Truly single-session and removes the RealityKit material warnings, but requires a YCbCr renderer (more code/risk) and discards future RealityKit overlay capability. Rejected as heavier than necessary.

### Consequences

**Positive:**
- One camera capture source; the `FigCaptureSourceRemote` errors and interruption/flashing loop are eliminated.
- Still uses `ARView` for passthrough; no custom renderer.
- Honours Decision 11's single-session/sole-delegate intent.

**Negative:**
- The engine's session reference is now mutable and adopted lazily, so the engine has no running session until the preview view appears (acceptable: capture is gated behind `.ready`, which requires live frames from the bound session).
- The benign `engine:BuiltinRenderGraphResources/AR/*.rematerial` warnings from RealityKit remain.

### Impact

`MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift`, `App/ARPreviewView.swift`, `MeData/Tests/ARPreviewViewTests.swift`.

---

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
**Status**: superseded — research Req 1.2 / design §0 raised the OS floor to **iOS 26.5**, and Decision 15 (+ Req 18.4) adopt the system-default Liquid Glass `TabView` material. The "iOS 17 API surface only, no Liquid Glass" position no longer holds; the app targets iOS 26.5 and uses system Liquid Glass where the framework supplies it by default. The underlying principle (minimum custom chrome, no bespoke per-OS branches) is retained.

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
**Status**: superseded by Decision 17 (confidence-pill portion only — UI responsiveness floors remain accepted)

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

## Decision 15: Three-tab `TabView` shell (Photo / Meals / Settings); persistent meal history added to v1.1 UI scope

**Date**: 2026-05-29
**Status**: accepted

### Context

The v1.0 UI spec was framed as a single-screen capture flow with Out-of-Scope items for "Persistent meal-history list / browsing" and "Liquid Glass / iOS 26-specific styling". On 2026-05-29 the developer asked to add a tab bar at the bottom of the device, following Apple's "Organize your features" tutorial pattern (<https://developer.apple.com/tutorials/develop-in-swift/organize-your-features>): Photo (default), Meals (history), Settings. The Photo tab hosts the existing capture flow; the Meals tab is a new history screen; the Settings tab consolidates the previously buried settings affordance.

The trigger is concrete: with research Phase 1 (device MVP, decision 42) producing real meal records on the device — albeit with placeholder macros from the dev stub — the developer has no in-app way to confirm that meals are actually persisting, no way to delete a placeholder run, and the Settings entry point on the capture view is awkward in practice. The Apple tutorial's tab pattern is the standard answer.

### Decision

Revise `specs/ui` in place to v1.1. Replace the capture-view single-screen root with `AppRoot`, a `TabView` containing exactly three tabs: Photo (selected on first launch), Meals, Settings. Each tab is rooted in its own `NavigationStack`. Tab selection persists via `@AppStorage("selectedTab")`. The capture flow lives inside the Photo tab unchanged from v1.0 except for two new lifecycle rules:

1. When the user switches away from the Photo tab while not in `.estimating`, the engine is released within 200 ms (same ceiling as backgrounding).
2. When the user switches away during `.estimating`, the in-flight `Pipeline.estimate(_:mode:)` is NOT cancelled; on return to the Photo tab the model presents `.showingResult(record)`.

The Meals tab is a new screen: `List` of `MealRecord`s sorted by `capturedAt` desc, with thumbnail, timestamp, carbohydrate total, confidence pill, and a yellow "Placeholder" chip when `record.segmenterSource == "dev_stub"` (research Req §23.6 / §19.3). Row tap pushes `ResultView` in `.historyDetail` presentation mode. Trailing swipe action deletes the meal row and its artefact directory; the associated `PHAsset` is NOT deleted (the user owns their Photos library — research Req §17.3).

The Settings tab content is the v1.0 surface (CoFID + AFCD attribution, export archive button). Data import, model/inference info, and debug info are explicitly out of scope for v1.1.

Liquid Glass styling is in scope for the tab bar — the system-default `TabView` material on iOS 26.5 is used as-is, with no custom tab-bar appearance.

### Rationale

The Apple tutorial pattern is the conventional iOS answer for "three top-level surfaces with no inherent hierarchy." A custom navigation chrome would add iOS-specific code that does not advance any research-spec requirement and would diverge from the platform's tab-bar behaviours (re-tap to pop, automatic state preservation, Liquid Glass material). One `NavigationStack` per tab is required by SwiftUI's navigation rules — sharing a stack across tabs would make tab-tap-to-pop-to-root ambiguous and break the system's per-tab state preservation.

The estimating-survives-tab-switch carve-out (point 2 above) is important: a typical capture takes seconds, the user often wants to look at past meals while waiting, and cancelling the estimation on tab-switch would force a recapture for a behaviour that has no upside. The implementation cost is small — the model already handles state across `scenePhase` transitions; tab transitions reuse the same machinery with a different branch for `.estimating`.

Surfacing the placeholder chip on the meal-history row (read from the persisted `segmenterSource`, not the build flag) carries the dev-stub provenance into the history view, so a developer who comes back to inspect old meals after Phase 3 ships still sees which estimates were placeholders. This matches research Decision 42's reasoning for the result-view banner.

Settings tab content is intentionally minimal. The user explicitly excluded data import, model/inference info, and debug info from v1.1 when asked. Surfacing those would expand scope without an immediate use case; the placeholder banner already carries the dev-stub provenance, and the developer has Xcode for debug inspection.

### Alternatives Considered

- **Keep the v1.0 single-screen root; reach Meals via a `NavigationLink` from the capture view**: Rejected — would crowd the capture view with non-capture chrome, conflicts with §1.1's "live AR feed + indicators + shutter only" framing, and the capture view's `NavigationStack` is already used for `.navigationDestination(for: MealRecord.self) -> ResultView` after a fresh capture. Splitting "just captured" vs "history detail" presentation in the same stack creates ambiguity.
- **Split into separate specs (`specs/ui` for capture + `specs/navigation` for tabs + history)**: Rejected — the tab shell, history list, and settings tab are one cohesive UX concern; tracking them in three places adds coordination cost without separating real concerns.
- **Surface meal history as a sheet from the capture view rather than a tab**: Rejected — sheets are for one-shot modals; a history list is a persistent surface the user returns to. The Apple tutorial pattern explicitly contrasts sheets vs tabs along this axis.
- **Add model/inference and debug info panels to Settings now**: Rejected per user direction. The placeholder chip and result-view banner already carry dev-stub provenance; full diagnostic panels are scope-expansion without an immediate use case.

### Consequences

**Positive:**
- The developer can confirm meals are persisting and clean up placeholder runs from inside the app, removing a friction point during Phase 1 device-MVP work.
- Standard iOS navigation conventions (tab-tap pop-to-root, per-tab state preservation, Liquid Glass tab-bar material) are inherited from the framework with no custom code.
- The placeholder chip in the meal history carries the dev-stub provenance forward into Phase 3, matching the architecture established by research Decision 42.
- v1.1 work can proceed in parallel with research Phase 1: Phase 1 tasks touch `MedataCore` (Pipeline, Segmentation, Persistence); v1.1 tasks touch `App/`. The shared surface is the `segmenterSource` value from research task 82 (later reshaped by the event-log-schema spec to a field inside the event `metadata` JSON, not a SQL column) and the additive `PersistenceStore` methods (`allMeals`, `deleteMeal`, `eventsDidChange` — renamed from `mealsDidChange` by event-log-schema Decision 7), both of which Phase 1 and v1.1 can land without colliding.

**Negative:**
- The previously frozen v1.0 capture-only framing is no longer accurate; readers must read v1.1 to see what currently applies. The diff against v1.0 is preserved by git rather than by a separate spec.
- `PersistenceStore` gains three additive methods (`allMeals`, `deleteMeal`, `eventsDidChange` — the stream was named `mealsDidChange` here originally and renamed by event-log-schema Decision 7). The stream requires the GRDB conformer to emit on every write, which is a small but new coordination point.
- The `MealHistoryModel` uses `PHImageManager` to fetch thumbnails; a user who denies Photos access sees fork-knife placeholders in the list. This is the same fallback the result view uses (research task 73) but it is now visible in two places.

### Impact

- `specs/ui/iphone-experience/requirements.md` revised to v1.1: Out-of-Scope items for "Persistent meal-history list / browsing" and "Liquid Glass / iOS 26-specific styling" removed; replaced with "Data import", "Model / inference info panel", "Debug info panel". §1.1, §1.2, §1.3, §1.4 updated to reference the Photo tab; §1.7 added for tab-switch lifecycle. §11.1 updated to reference the Settings tab; §11.5 added to fence off the new Out-of-Scope items. §18 (Tab navigation shell) and §19 (Meals tab) added.
- `specs/ui/iphone-experience/design.md` revised to v1.1: new "Tab shell (`AppRoot`)" subsection in Architecture; new entries in the file-map table for `AppRoot.swift`, `MealsTabView.swift`, `MealListView.swift`, `MealRow.swift`, `MealHistoryModel.swift`, additive `PersistenceStore` methods; new "Meals tab" component subsection; testing-strategy additions for tab persistence, capture lifecycle across tab switches, history refresh, placeholder chip, delete, empty state, presentation-mode toggle on `ResultView`, and re-tap pop-to-root; Out-of-Scope consistency table revised.
- `specs/ui/iphone-experience/tasks.md` will gain a new "v1.1 — Tab navigation + Meals tab" phase with the implementation tasks.
- Cross-spec: research task 82 (segmenter_source persistence) and research task 83 (result-view placeholder banner) are pre-requisites for the Meals tab's placeholder chip rendering. The Meals tab is functional without them — the chip simply never renders — so the dependency is on display correctness, not on the tab shell itself.

---

## Decision 16: Clean capture aesthetic; tokens live in `design-system/MASTER.md`; v1.0 indicator and refusal layouts superseded

**Date**: 2026-05-29
**Status**: accepted

### Context

After Decision 15 introduced the tab shell, the visual design across the three tabs was still implicit: brand accent colour and a few iOS-defaults. On 2026-05-29 the developer asked for the camera capture screen to look "clean and professional" — chrome that stays out of the way of the AR preview. The UI/UX Pro Max design-intelligence skill surfaced three style layers that match that brief: Exaggerated Minimalism (oversized type, single accent), Dark Mode OLED (`#000000` background on camera/result), and Flat Design Mobile (zero shadow, instant press feedback, ≥48pt targets).

The v1.0 spec's three-corner live-indicator layout, top-anchored refusal banner, and standard segmented capture-mode control were appropriate for the v1.0 functional spec but visually busy: they compete with the AR preview for attention rather than letting the food in the viewfinder be the focal element.

### Decision

Adopt a three-layer visual style: OLED-black backgrounds on the Photo tab and ResultView, flat touch-first chrome everywhere, and exaggerated-minimal type on the carbohydrate total. All visual tokens (colour, type, spacing, motion) live in `design-system/MASTER.md` with per-screen overrides in `design-system/pages/<screen>.md`. The implementation consumes those tokens verbatim and does not introduce parallel inline values. New Req §20 (Visual design — clean capture aesthetic) carries the acceptance criteria.

Three v1.0 view components are superseded:

1. `LiveIndicatorView` (three-corner layout) → `LiveIndicatorBadge` (single consolidated chip with auto-hide).
2. `RefusalBanner` (top overlay) → `RefusalSheet` (bottom sheet with detents and drag indicator).
3. `CaptureModeToggle` segmented-control rendering → capsule pill with animated inner accent pill.

The shutter button is extracted into its own view (`ShutterButton`) with a 76pt diameter and 100ms-shrink-then-spring press feedback. The Meals tab is rendered as a photo-led list (full-width 4:3 photo per row with carb + confidence + timestamp caption below) rather than a 3-column thumbnail grid — the macro context (carbs, confidence) is essential and a grid would hide it. The ResultView places the carbohydrate total at 72pt heavy monospaced over a dimmed full-bleed photo, with the research-spec placeholder chip rendered as a small pill (not a full-width banner) when `segmenterSource == "dev_stub"`.

The tab bar uses the system-default Liquid Glass material on iOS 26.5 and is visible on all three tabs (Photo tab does not hide it during capture — keeping the standard tab-bar persistence avoids forcing a custom dismiss gesture).

### Rationale

Tokenising the design (rather than embedding colour and type values in views) is the standard answer to "make every screen feel like the same product" and is the only way the placeholder chip on the Meals row can stay visually identical to the ResultView placeholder chip without coordination — both read the same token. Putting overrides in `design-system/pages/<screen>.md` lets a single context-aware retrieval (per the UI/UX Pro Max skill's hierarchical pattern) pick up the right rules when implementing a specific screen.

Superseding the three v1.0 components is cheaper than retrofitting them: their interfaces were designed for the old layout (e.g. `RefusalBanner` is an `.overlay(alignment: .top)`-shaped view; converting it to a sheet means a different presentation API and a different state shape). A clean replacement keeps the supersession explicit in the spec and the file map, so a reader can trace what changed between v1.0 and v1.1.

The photo-led Meals list (versus a thumbnail grid) is a deliberate choice: the meal's carbohydrate value and confidence pill are first-order metadata, not decorations on the photo. A grid hides those; a photo-led list preserves them as immediate caption text. The photo remains the dominant element, but the data the user came to see is one glance away.

Keeping the tab bar visible during capture is the platform convention on iPhone. Hiding it would force a custom dismiss gesture to return to the other tabs, which would conflict with system gesture navigation. The cost is one chrome row at the bottom of the AR preview; the cost of hiding it would be a non-standard navigation model. Persistence wins.

### Alternatives Considered

- **Keep the v1.0 visual layout; only adopt the tab shell from Decision 15**: Rejected — the v1.0 layout is functional but visually busy; the three-corner indicators and top-anchored refusal banner compete with the AR preview.
- **Embed colour/type values inline in views, no design-system files**: Rejected — would force coordination via copy-paste between `ResultView` and `MealRow` for the placeholder chip, the confidence pill, and the OLED background. A token layer eliminates that coordination.
- **Glassmorphism on the Photo-tab chrome (translucent capsules over the AR feed)**: Rejected — re-blurs an already busy AR preview and reduces legibility of the indicator chip. Flat semi-transparent backgrounds (`captureChromeBG` at 0.10 opacity) preserve preview clarity.
- **3-column thumbnail grid for the Meals tab**: Rejected — hides the carbohydrate total and confidence pill, which are the use case. Photo-led row preserves them.
- **Hide the tab bar during capture**: Rejected — conflicts with iPhone platform convention and would require a custom dismiss gesture. The translucent system tab bar at the bottom is the smaller cost.

### Consequences

**Positive:**
- Visual language is centralised in a small set of files (`MASTER.md` + two page overrides), so a future addition of a new screen (e.g. a Trends tab in a later release) inherits the tokens for free.
- The placeholder chip in three places (ResultView, MealRow, MealsDetail) reads from one token pair (`placeholderBG` / `placeholderFG`); they cannot drift visually.
- Reducing chrome on the capture screen lets the AR preview be the focal element, which is what the user is actually looking at while framing the meal.
- Flat touch-first chrome plus ≥48pt targets meets the touch-and-interaction CRITICAL category in the UI/UX Pro Max quick-reference checklist without per-control review.

**Negative:**
- Three v1.0 views are superseded; their tests are obsolete and must be rewritten against the new components. The v1.0 tasks remain "Completed" in tasks.md (they were completed when written); new tasks supersede the corresponding work.
- The carb-total `display`-scale 72pt monospaced type forces a Dynamic Type clamp at AX5 to avoid running off-screen, which is a small accessibility compromise documented in Req §20.12.
- The persistent tab bar during capture means the shutter must sit ≥24pt above the tab-bar top edge, which marginally compresses the AR preview vertically. Acceptable given the platform-convention rationale.
- Future screens that need a non-token-aligned visual choice (e.g. a one-off marketing card) must either add a new token or document a deliberate page-specific override. The discipline this requires is real but is the point of having tokens at all.

### Impact

- `specs/ui/iphone-experience/requirements.md` v1.1 gains §20 (Visual design — clean capture aesthetic) with twelve acceptance criteria covering token discipline, OLED backgrounds, flat chrome, consolidated indicator chip, capsule capture-mode pill, shutter dimensions and feedback, bottom-sheet refusal, exaggerated-minimal carb total, photo-led Meals row, touch targets, reduced-motion fallback, and Dynamic Type clamp.
- `specs/ui/iphone-experience/design.md` v1.1: new "Visual design" paragraph in Overview pointing at the design-system files; file map adds `CaptureTopBar.swift`, `LiveIndicatorBadge.swift`, `ShutterButton.swift`, `ConfidencePill.swift`, `RefusalSheet.swift`; marks `LiveIndicatorView.swift` and `RefusalBanner.swift` as superseded; modifies `CaptureModeToggle.swift` to render the pill style.
- `design-system/MASTER.md` (new) carries the global tokens. `design-system/pages/photo-tab.md` and `design-system/pages/meals-tab.md` (new) carry per-screen overrides and layout diagrams.
- `specs/ui/iphone-experience/tasks.md` gains a "v1.1 — Visual design" phase with the implementation tasks. The previous v1.1 phase ("Tab navigation + Meals tab") remains the structural work; the visual phase depends on it for some tasks (e.g. `MealRow` styling depends on the row existing).
- No `MedataCore` changes. The supersession affects only the App target.

---

## Decision 17: Four-tier confidence pill; retake prompt at σ < 0.20

**Date**: 2026-06-01
**Status**: accepted (supersedes Decision 8 in this log)

### Context

Research Decision 43 (tilt-tolerant capture) reframes σ_meal so that low-confidence values are routine rather than exceptional — most off-axis captures now produce estimates in the 0.01–0.50 range. Under the prior three-tier pill (High ≥ 0.75, Moderate 0.60–0.75, Low < 0.60 from Decision 8), this would collapse the bulk of real captures into a single "Low" bucket and would fire the uncertain-estimate retake prompt (Req 13.5 old threshold 0.6) on most meals.

The user's framing (`nextup.md`): low-confidence estimates are still useful and should be reported honestly, not buried behind an undifferentiated warning. Retake should be prompted only when the estimate is essentially worthless.

### Decision

Replace the three-tier confidence pill with a four-tier scheme:

- **High**: σ ≥ 0.75
- **Moderate**: 0.50 ≤ σ < 0.75
- **Low**: 0.20 ≤ σ < 0.50
- **Very Low**: σ < 0.20

The retake prompt (UI Req 9.3) fires only at the Very Low tier (σ < 0.20). At Very Low the result view also surfaces an inline explanation including the per-stage angular error Δθ from the persisted record, and offers two side-by-side controls: "Retake" and "Keep as-is". The meal is persisted at capture time regardless of tier; "Keep as-is" simply dismisses the surface.

Research Req 13.5's threshold is updated to match (0.6 → 0.2) so the UI and research specs agree.

The pill colour token `confidenceVeryLow` is desaturated greyscale rather than a more alarming colour — red is already used by the Low tier, and the desaturated treatment draws the user's attention to the surrounding inline explanation rather than to the pill itself.

### Rationale

Four tiers give the user three meaningful gradient cuts where the prior three tiers gave two, and the Very Low tier carries the meaning that the prior Low bucket lost: "this is essentially a guess, not an estimate." The 0.50 boundary between Moderate and Low is chosen as the midpoint between the new Very Low threshold (0.20) and the High threshold (0.75); it gives Moderate enough breadth to land on most reasonable captures while still distinguishing the genuinely degraded ones.

Firing the retake prompt only at the Very Low tier prevents prompt fatigue. Most off-axis captures will land in the Low tier under soft acceptance; if every one of them triggered a modal, users would learn to dismiss it reflexively (and stop noticing when it matters).

### Alternatives Considered

- **Keep three tiers, widen Low to cover 0.01–0.60**: Rejected — collapses a meal at σ = 0.03 and a meal at σ = 0.55 into the same visual treatment, hiding the gradient that justifies persisting σ in the first place.
- **Five tiers including a separate Floor tier (σ < 0.05)**: Rejected as over-design — at two-decimal display precision the user cannot meaningfully distinguish a Floor tier from a Very Low tier. Decision 45 already lowered the ε floor to 0.01, so the bottom of the Very Low tier carries the "close to zero" meaning naturally.
- **Keep the retake prompt at σ < 0.60**: Rejected — under tilt tolerance this fires on the majority of captures, producing prompt fatigue.

### Consequences

**Positive:**
- The pill conveys the gradient that the soft-acceptance regime produces; users see "this was a careful capture" (High) versus "this was a rough capture" (Low) versus "this is essentially a guess" (Very Low).
- The retake prompt has signal value again — when it fires, the user knows something is meaningfully wrong.
- A meal at the Very Low tier still saves to history (no data loss); the user can come back and inspect why later via the persisted Δθ values.

**Negative:**
- `ConfidencePill` shared component and its tests need updating from three to four labels.
- Decision 8's 0.60 / 0.75 boundaries are superseded; any documentation referencing those specific numbers needs updating.
- The 0.50 Moderate/Low boundary is a UI-spec invention (the same status as Decision 8's old 0.75 boundary), not data-driven; Phase 2 user feedback may revise it.

---

## Decision 18: Shutter always armed when capture is otherwise possible

**Date**: 2026-06-01
**Status**: accepted

### Context

Prior UI Req 7.2 enabled the shutter only when the tilt indicator was in range (§2.4) AND the working-distance gate was satisfied AND no estimation was in flight. Research Decision 43 removes the nadir hard angular gate; tilt no longer has an "in-range" / "out-of-range" state to gate on.

### Decision

The shutter SHALL be enabled when:
- no `Pipeline.estimate` is in flight (existing constraint), AND
- ARSession tracking is `.normal` (existing constraint), AND
- the working-distance gate is satisfied (existing constraint, unchanged per research Decision 43 group B), AND
- the oblique-stage hard cap (research Req 3.3, |measured − 25°| ≤ 30°) is satisfied — but only when the active stage is the oblique view of a two-view capture.

Tilt no longer affects shutter arming for the nadir stage at all. UI Req 2.4 (the prior "disable shutter while tilt out of range" requirement) is removed.

### Rationale

The two remaining tilt-driven constraints — the oblique-stage hard cap and the tracking-normal gate — are not really tilt constraints in the user-precision sense. The oblique hard cap exists because the SfS algorithm produces silently-wrong volumes far outside the Dehais 2017 envelope (research Decision 43); the tracking gate exists because relative pose between views is undefined when tracking drops (research Req 3.7).

Always arming the nadir shutter removes the principal usability blocker from `nextup.md`. The user can now capture in moments of unsteadiness; the confidence pill carries the consequence.

### Alternatives Considered

- **Two-state armed (encouraged vs warning)**: Rejected as additional UX surface without changing the underlying behaviour. The continuous tilt readout from Decision 19 already communicates the impending confidence penalty before the user taps.
- **Long-press required for low-σ_tilt captures**: Rejected for discoverability — users would not know they can long-press, and the friction would re-introduce the very gate that Decision 43 removes.

### Consequences

**Positive:**
- Most usability blocker from `nextup.md` is addressed at the UI layer; a t1dm user with shaking hands can always capture.
- Removes a UI state-machine branch (tilt-in-range / out-of-range), simplifying `CaptureFlowModel.GatingSnapshot` and the tests.

**Negative:**
- Some users may capture more low-confidence meals than intended; the four-tier pill from Decision 17 is the only feedback mechanism telling them so.
- The legacy `LiveIndicatorBadge` tilt sub-element's green/white colour treatment (per `design-system/pages/photo-tab.md`) becomes inconsistent with the no-gate behaviour; Decision 19 supersedes it.

---

## Decision 19: Continuous tilt indicator — Δθ + live σ_tilt%, no binary state

**Date**: 2026-06-01
**Status**: accepted

### Context

The prior tilt indicator (UI Reqs 2.1–2.4, `design-system/pages/photo-tab.md` Indicator badge spec) used a binary colour state: green tint when the device tilt was within ±5° of the target axis, white otherwise. Under research Decision 43 this binary state has no meaning — there is no in-range / out-of-range distinction at the nadir stage, and at the oblique stage the only hard cap is at ±30° from 25°, well outside what a binary colour state would meaningfully encode.

### Decision

Replace the binary green/white tilt state with a continuous greyscale readout. The tilt sub-element of the indicator chip SHALL render two values per stage:

- `Δθ` in degrees (e.g. `17°`), monospaced, white.
- σ_tilt = cos(Δθ) as a percentage (e.g. `97%`), monospaced, white, slightly smaller weight.

No green tint. No red tint. The chip auto-hide rule (UI Req 20.4) is re-anchored from "in-range tilt" to "σ_tilt > 0.95 (≈Δθ < 18°) for 5 seconds AND other indicators in-range" — captures within roughly the old ±5° gate continue to auto-hide as before, but the colour change is gone.

### Rationale

The continuous readout teaches the user the trade-off they are making at the moment of capture: they see directly that a 17° tilt costs them about 3% confidence, and they can decide in real time whether to steady the device further or accept the cost. The greyscale treatment communicates that there is no longer a "wrong" state — every angle produces a usable capture; the user is choosing where on the confidence curve to land.

Showing both Δθ and σ_tilt is redundant by design: Δθ is the actionable lever (the user can adjust it), σ_tilt is the consequence (what they will see on the result view). The mapping between them — cos(Δθ) — is gentle enough that the user cannot intuit it from Δθ alone, especially in the 10°–30° range where σ_tilt remains surprisingly high.

### Alternatives Considered

- **Binary but never blocks shutter**: Rejected — keeps the colour-coded UI familiar but encodes a distinction (in/out of ±5°) that no longer has any consequence. Users would reasonably ask "what does the colour mean?" and the only honest answer would be "nothing actionable, just history."
- **Three-band traffic light (green ≤5°, amber 5°–15°, red >15°)**: Rejected — re-introduces discrete states under a continuous regime and obscures the actual σ_tilt curve. The bands would also have to be re-justified at each release; the cos curve is justified once and forever.

### Consequences

**Positive:**
- The user sees a direct, live preview of the σ_tilt sub-confidence that will appear on the result view — no surprise after capture.
- The chip auto-hide rule keeps the indicator out of the way for clean captures while always re-showing it when the user is degrading the capture.
- Greyscale treatment is consistent with the "clean capture aesthetic" theme established in Decision 16.

**Negative:**
- `LiveIndicatorBadge` and `design-system/pages/photo-tab.md` need updating; the green/white tilt treatment is superseded.
- Cognitive load per capture rises slightly for users who could meet ±5° easily — they now read two numbers where they previously read a colour. The auto-hide rule mitigates this for steady users by dismissing the chip entirely after 5 s.
- The display of σ_tilt as a percentage in the live preview may invite the user to confuse it with σ_meal — they look similar in the UI. The result-view pill remains the canonical σ_meal surface; only the live capture chip shows σ_tilt.

---

## Decision 20: RefusalSheet is dismissible by swipe-down; leaving the Photo tab clears `.refused`

**Date**: 2026-06-03
**Status**: accepted

### Context

The v1.1 `RefusalSheet` (Req §20.7 / Decision 16) is presented via SwiftUI `.sheet(item: $model.refusal)` in `CaptureFlowView`. Two pieces of behaviour, both originally intentional, combined to produce a UX dead-end the user could not exit without re-launching capture:

1. `model.refusal` was a derived read of `state == .refused`; its setter no-op'd on nil. A swipe-down on the sheet would write nil into the binding, the setter would ignore it, and on the next SwiftUI render the sheet would re-present because `state` was still `.refused`.
2. `tabSelectionChanged(to:)` excluded `.refused` from the "reset to `.initialising`" branch, on the principle that the user should "find the same surface when they come back". Combined with (1) this meant the refusal sheet popped back up on every return to the Photo tab.

The user reported the symptom on `lidarFitDegenerate` ("Surface not detected" in Irish-English) on flat camera mode, but the behaviour is uniform across all 14 `EstimationFailure` cases. Full investigation in `specs/bugfixes/surface-not-detected/report.md`.

### Decision

The RefusalSheet is dismissible by swipe-down. Two behavioural changes back this contract:

1. `CaptureFlowModel` exposes `func dismissRefusal()` that transitions `.refused → .ready(freshSnapshot())`, clearing `firstFrame`/`firstFrameTiltDeg`/`inFlightMode`. The `refusalBinding` in `CaptureFlowView` calls this on a nil write from `.sheet(item:)`.
2. `tabSelectionChanged(to: nonPhoto)` while `.refused` is treated the same as `.ready` or `.trackingLost` — reset to `.initialising`, release the engine, clear captured frames. `.permissionDenied` remains preserved (no engine to release; the surface is the same on return).

The explicit `tryAgain()` path is unchanged: it relaunches capture from the appropriate stage and preserves `firstFrame` when retrying the oblique view (Req §5.4).

### Rationale

A SwiftUI `.sheet(item:)` binding is a contract: when the framework writes nil into the binding (swipe-down, programmatic dismissal), the modal source of truth must clear. Wiring it to a get-only derivation breaks that contract silently — the sheet animates out and snaps back in with no diagnostic. There is no in-frame UI affordance that would tell the user "this sheet cannot be dismissed by swipe-down; tap Try again instead", so the silent re-presentation reads as a UI bug, not as intentional behaviour.

The tab-switch change follows from the same principle: if the user can dismiss the sheet by swiping it down, they can also dismiss it by walking away from the Photo tab. Preserving `.refused` across tab switches forces the user to re-encounter a sheet they have already decided to leave behind. The `.estimating` carve-out (Decision 15 rule 2) remains untouched — that's about not throwing away in-flight work, which is a different concern.

### Alternatives Considered

- **Make the sheet non-dismissible with `.interactiveDismissDisabled()`**: Rejected — the explicit "Try again" button works, but there is no "dismiss without re-capturing" affordance. The user has no way to put the refusal aside and inspect the viewfinder before re-attempting; they're forced into immediate recapture even when they want to re-frame the meal first. Inferior UX for a marginal gain in "explicitness".
- **Keep refusal across tab switches but make sheet dismissible**: Rejected — fixes Symptom 1 only. On return to Photo the user would see the sheet pop up again, having to dismiss it a second time. The carve-out's original rationale ("find the same surface when they come back") assumed the surface was useful to return to; with dismissal working, it isn't.
- **Make `model.refusal` a stored property and set it nil from the binding directly**: Rejected — splits the source of truth (the `.refused` state and a separate `refusal` field would need to stay in lockstep), and the existing Equatable conformance on `CaptureState` would no longer suffice. Single source of truth via state, with `refusal` derived and an explicit `dismissRefusal()` command, is simpler.

### Consequences

**Positive:**
- The `.sheet(item:)` dismissal contract is honoured; users have a working swipe-down to set the refusal aside.
- Leaving the Photo tab is now a uniform "reset to baseline" regardless of which non-terminal state the user was in (`.ready` / `.trackingLost` / `.refused`). One fewer special case to remember.
- The fix is symmetric across all `EstimationFailure` cases — no per-case branching, no risk of silently regressing on the cases the user didn't report.

**Negative:**
- Users who relied (consciously or not) on the refusal sheet being "sticky" across tab switches will no longer find it on return. The mitigation is that the underlying failure mode is usually transient — the user retakes the photo with the meal re-framed — so the refusal is rarely a thing the user wants to come back to.
- Decision 15 rule 1 (engine released within 200 ms on tab leave) now applies to `.refused` too; the engine stop is fire-and-forget but adds a small amount of work on the leave path. Existing `tabSelectionChanged` tests on `.ready` already cover this.
- Replaces one existing unit test (`CaptureFlowModelTabSelectionTests::refusedNoOp`) that encoded the now-superseded behaviour. The replacement (`refusedDismissedOnTabLeave` + `refusalDoesNotReappearOnPhotoReturn`) covers the new contract.

### Impact

- `App/CaptureFlowModel.swift` — `dismissRefusal()` added; `tabSelectionChanged` rewrites the `.refused` arm; `model.refusal` is now strictly derived (setter removed).
- `App/CaptureFlowView.swift` — `refusalBinding.set` delegates nil writes to `model.dismissRefusal()`.
- `MeData/Tests/CaptureFlowModelTests.swift` + `CaptureFlowModelTabSelectionTests.swift` — regression tests covering the new contract.
- `docs/agent-notes/ui-capture-flow.md` — gotcha updated to reflect dismissibility.
- `specs/bugfixes/surface-not-detected/report.md` — full investigation and verification trace.

---

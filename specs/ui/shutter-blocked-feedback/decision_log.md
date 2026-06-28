# Decision Log: Shutter Blocked Feedback

## Decision 1: Treat `.disabled` and `.capturing` shutter taps differently

**Date**: 2026-05-31
**Status**: accepted

### Context

The original draft of this smolspec routed any tap on a non-interactive shutter (i.e. `state.isInteractive == false`) into a single `onBlockedTap` callback that fired a haptic and logged a diagnostic. `ShutterButtonState.isInteractive` is `false` for both `.disabled` (gates not met) and `.capturing` (capture in flight). Design-critic review flagged that taps during `.capturing` are not "blocked" in any user-meaningful sense — the capture is already running — and that buzzing the device plus emitting log lines on every tap during a legitimate 1–2 s capture is the wrong feedback.

### Decision

Only `.disabled` taps trigger the new feedback (haptic + indicator reveal + OSLog). `.capturing` taps are silently dropped, matching today's feel for an in-flight capture.

### Rationale

The user's reported failure mode is "the shutter never enables, I can't tell why" — i.e. `.disabled`. Taps during `.capturing` already have a visible signal (the busy state per Req §8.1) and feedback for them would conflate "you tapped while busy" with "your gating is wrong," which is the opposite of the diagnostic we are trying to add.

### Alternatives Considered

- **Single `onBlockedTap` for all non-interactive states**: simpler call site, but produces haptic and log spam during legitimate captures. Rejected.
- **Different feedback per non-interactive state (e.g. quieter haptic during `.capturing`)**: more nuance than needed; the existing busy chrome is already the signal. Rejected as scope creep.

### Consequences

**Positive:**
- Diagnostic log lines map 1:1 to user-perceived "why won't this fire" events.
- No haptic spam during an in-flight capture.

**Negative:**
- `ShutterButton` now branches on `state == .disabled` explicitly rather than the existing `state.isInteractive` helper, splitting one bit of logic into two.

---

## Decision 2: Use `.sensoryFeedback(.warning, trigger:)` instead of `UINotificationFeedbackGenerator`

**Date**: 2026-05-31
**Status**: accepted

### Context

The original draft fired a haptic via `UINotificationFeedbackGenerator().notificationOccurred(.warning)` from inside `CaptureFlowModel.shutterBlockedTapped()`. `CaptureFlowModel` does not currently import `UIKit`; adding the import widens the model's dependency surface. The project's Swift rules file (`rules/language-rules/swift.md`) targets iOS 17+ and recommends modern declarative SwiftUI APIs over UIKit equivalents.

### Decision

Drive the haptic from the view layer using `.sensoryFeedback(.warning, trigger: blockedTapCount)` on `ShutterButton`, with the counter incremented in the button's action closure when `state == .disabled`.

### Rationale

`.sensoryFeedback` is the iOS 17+ idiomatic API: declarative, respects system haptic settings, no `prepare()` lifecycle dance, and confines haptics to the view layer where they belong. Keeping `UIKit` out of `CaptureFlowModel` preserves the model's testability — the model's existing test suite (`CaptureFlowModelTests`, `CaptureFlowModelTabSelectionTests`) does not need `UIKit` and should not start to.

### Alternatives Considered

- **`UINotificationFeedbackGenerator` in the model**: more direct from the call site, but couples the model to UIKit and bypasses the declarative API. Rejected.
- **`.sensoryFeedback` driven by a model-published counter (`@Observable var blockedTapNonce: Int`)**: works, but adds an observed field whose only consumer is the haptic. The `@State` counter in `ShutterButton` is sufficient and keeps the model surface narrower. Rejected.

### Consequences

**Positive:**
- `CaptureFlowModel` stays UIKit-free.
- Idiomatic for the iOS 17+ target.

**Negative:**
- Haptic firing is decoupled from logging (button increments the counter, model writes the log) — a future change that wants to suppress one without the other has two sites to edit.

---

## Decision 3: Move indicator badge visibility onto `LiveIndicatorModel`

**Date**: 2026-05-31
**Status**: accepted

### Context

`LiveIndicatorBadge` currently owns its own `visible: Bool` and `autoHideTask: Task` as `@State`. To re-reveal the badge from outside the view (when a `.disabled` shutter is tapped), the original draft proposed a `revealNonce: Int` on `LiveIndicatorModel` that the badge's `.onChange` would observe and pipe into the existing private `showAndScheduleHide()`. Design-critic review flagged this as using `@Observable` as a pub/sub bus rather than as state.

### Decision

Lift `visible` and `autoHideTask` onto `LiveIndicatorModel`. Expose `reveal()` and `scheduleHide()` as model methods. The view becomes a pure render of `model.visible`.

### Rationale

Auto-hide is a policy decision about model state ("am I currently being asked to be seen?"), not view state. The previous shape worked only because the badge was the only caller; the moment a second caller exists (the blocked-tap path), the right answer is to make visibility a first-class property of the model. The `revealNonce` shape would technically work but encodes a signal as a counter, which is exactly the pattern the critic correctly named as a smell.

### Alternatives Considered

- **`revealNonce: Int` on `LiveIndicatorModel`**: minimal diff to existing code, but encodes intent as counter increments. Rejected — the second caller is the canary.
- **`Binding<Bool>` passed into `LiveIndicatorBadge` from `CaptureFlowView`**: forces `CaptureFlowView` to own visibility, but the auto-hide timer would have to live somewhere too; the badge or the parent. Rejected because the model already owns the rest of the indicator state.

### Consequences

**Positive:**
- Single source of truth for badge visibility.
- The blocked-shutter path calls `model.indicators.reveal()` — clear intent, no plumbing.

**Negative:**
- Slightly wider `LiveIndicatorModel` surface (one `Bool`, one method-pair, one private `Task`).
- The badge view loses its `.onDisappear { autoHideTask?.cancel() }` — the model now owns the task lifetime and must cancel on dealloc. The model is `@MainActor` and `@Observable`; the `Task` is `@MainActor` too, so cancellation in a `deinit` is straightforward.

---

## Decision 4: Log the success path symmetrically with the blocked path

**Date**: 2026-05-31
**Status**: accepted

### Context

The original smolspec scope was "feedback when the shutter does not work." User feedback expanded the scope: also ensure that when a tap proceeds (gates satisfied), the baseline estimation actually completes. The dev-stub baseline (`Pipeline.makeForDevice` under `DEV_STUB_SEGMENTER`) is wired on the device per `App/App.swift:41` (commit `37a3118`, Phase 1), but there is no observable signal in Console.app today confirming each pipeline stage executed for a given tap. A user reporting "the shutter does not work" is ambiguous between (a) the shutter never enables, and (b) the shutter fires but estimation hangs or refuses silently.

### Decision

Emit `OSLog.info` entries on the success path symmetric with the blocked-tap entry: one `event=fired` log on shutter entry, one `event=capture.start` / `event=capture.end` pair around the AR-frame capture, and one `event=estimate.start` / `event=estimate.end` pair around the pipeline call. All five reuse the same `Logger(subsystem: "ie.medata.app", category: "Shutter")` so a single Console.app predicate captures the entire shutter→result trail. Disambiguation between blocked vs success entries is by an `event=` tag in the log message.

### Rationale

The blocked-path log alone answers "is the shutter gated?" but not "does the rest of the pipeline finish?" Symmetric logs at stage boundaries give the on-device tester a single trail showing exactly where a tap ends up. The cost is small (five additional log lines per successful tap, all `.info` so they stay off the persistent log) and the diagnostic value is high: a hung `flowTask` (memory entry on prior Photo-tab freezes) or a downstream estimation refusal masquerading as "shutter does not work" is immediately distinguishable from a gating failure.

### Alternatives Considered

- **Use the existing `OSSignposter` in `Pipeline.swift`**: signposts are Instruments-visible but require attaching Instruments to a device-tethered session; Console.app subscribers see nothing. Rejected — the goal is plain Console.app diagnosability.
- **Log only on failure / refusal**: would surface refusals but miss a hang (where no stage ever ends). Rejected — the start/end pairs are what diagnose hangs.
- **Log at `.default` level**: persists more aggressively but at the cost of noise across the audit/log database. Rejected — `.info` is the right level for high-frequency-but-rare diagnostic events.

### Consequences

**Positive:**
- A single Console.app predicate (`subsystem == "ie.medata.app" && category == "Shutter"`) captures every shutter tap's full lifecycle.
- Distinguishes "gated" / "fired-but-hung" / "fired-but-refused" / "fired-and-succeeded" in the field.

**Negative:**
- Five new log sites in `CaptureFlowModel.swift` — a small but real increase in surface area inside `performFlow` and `runEstimation`. Mitigated by funnelling them through one private `Logger` constant.
- Logging happens unconditionally in production (no `#if DEBUG`). Acceptable because the entries are user-triggered (≤ a few per minute even with mashing) and `.info` level.

---

## Decision 5: Drop the `.isNotEnabled` accessibility trait — `accessibilityValue` carries the disabled announcement

**Date**: 2026-05-31
**Status**: accepted

### Context

The smolspec's Requirements list called for the shutter to add the SwiftUI `.isNotEnabled` accessibility trait when `state != .ready`, to restore the VoiceOver "dimmed" announcement that `.disabled()` was supplying. During implementation it turned out `AccessibilityTraits.isNotEnabled` is not a public SwiftUI API (no such case exists in iOS 17–26 `AccessibilityTraits`). The pieces that do exist — `accessibilityRespondsToUserInteraction(_:)`, `accessibilityHidden(_:)` — change focus behaviour or remove the element entirely, neither of which is what the spec actually wants.

### Decision

Do not add an explicit not-enabled trait. The existing `.accessibilityValue(state.accessibilityValue)` modifier already announces "Disabled" (or "Capturing" / "Ready") to VoiceOver, which is the user-facing diagnostic the trait was meant to supply.

### Rationale

`AccessibilityTraits.isNotEnabled` does not exist as a public SwiftUI API; the spec's prescription cannot be implemented literally. The `accessibilityValue` already reads "Disabled" — a screen-reader user gets the same information they would have gotten from the trait. Re-adding `.disabled()` to recover the trait would re-swallow the tap and defeat the whole point of this change.

### Alternatives Considered

- **Use `accessibilityRespondsToUserInteraction(false)` to suppress Switch Control / Voice Control on the disabled shutter**: Rejected — that modifier changes interaction routing for assistive tech, which would also block the blocked-tap callback that is the whole point of the spec.
- **Re-introduce `.disabled(state != .ready)` to recover the trait, then handle blocked taps via a separate `onTapGesture`**: Rejected — adds an extra gesture recogniser and routing layer just to recover a string announcement that `accessibilityValue` already provides.

### Consequences

**Positive:**
- Shutter remains tappable in `.disabled`, so the blocked-tap diagnostic fires.
- No new gesture plumbing.

**Negative:**
- VoiceOver users get the disabled signal only via the spoken value ("Disabled"), not via the trait flag. Acceptable: the announcement is what users actually hear.

---

## Decision 6: Reconcile smolspec + tasks text with the dropped `.isNotEnabled` trait

**Date**: 2026-06-28
**Status**: accepted

### Context

A validation pass found the smolspec body and `tasks.md` still prescribed adding
`.accessibilityAddTraits(state == .ready ? [] : [.isNotEnabled])` — in Requirements, the
Implementation Approach, the Risks mitigation, and task 2's title and a sub-bullet — even
though Decision 5 (accepted 2026-05-31) records that this trait was dropped because
`AccessibilityTraits.isNotEnabled` is not a public SwiftUI API, and the shipped
`App/ShutterButton.swift` carries no such trait (it relies on
`.accessibilityValue(state.accessibilityValue)`). Per PROCESS §1, a spec that disagrees with
its own decision log and the code is a defect to be reconciled.

### Decision

Update the smolspec Requirement, Implementation Approach bullet, and Risk mitigation, plus
task 2's title and sub-bullet, to state that no explicit not-enabled trait is added and that
`.accessibilityValue` carries the disabled announcement, cross-referencing Decision 5. No
code or behaviour changes.

### Rationale

The decision log is the authoritative "why" (§2); Decision 5 already settled the choice, so
the body text and ledger must follow it rather than continue to prescribe an API that does
not exist. Leaving the contradiction would mislead a future reader into thinking the trait
is required and missing.

### Alternatives Considered

- **Leave the body text and re-point only via Decision 5**: rejected — readers hit the
  Requirement first; an unreconciled MUST that the code violates fails the SSOT gate (§8).
- **Re-introduce `.disabled()` to recover a trait**: rejected — already rejected in Decision
  5; it would re-swallow the blocked tap that is the point of this spec.

### Consequences

**Positive:**
- Smolspec, tasks, decision log, and code now agree on the accessibility approach.

**Negative:**
- The original intent (an explicit trait) survives only as historical context in Decisions 5
  and 6, not as a live requirement.

---

## Verification Notes

**Date**: 2026-05-31

### Code-side audit (complete)

- Device build (`xcodebuild -scheme MeData -destination 'generic/platform=iOS' -configuration Debug build`) succeeds for `Debug-iphoneos`.
- All five prescribed log sites are wired through one `Logger(subsystem: "ie.medata.app", category: "Shutter")` in `App/CaptureFlowModel.swift`:
  - `event=fired` — line 157 (in `shutter()`).
  - `event=capture.start` — line 379 (in `performFlow`, before `try await capture(stage:)`).
  - `event=capture.end success=true` — line 381; `success=false` branches — lines 408, 411, 414.
  - `event=estimate.start` — line 432 (in `runEstimation`).
  - `event=estimate.end success=true` — line 446; `success=false` branches — lines 452, 456.
- `event=blocked` — `shutterBlockedTapped()` line 167.

### On-device observation (complete)

**Date**: 2026-06-14
**Device**: iPhone 13 Pro Max iOS 26.5, Debug-iphoneos build off `research` @ fdeab9d
**Mode tested**: double
**Outcome**: refusal

Observed log trail:

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

UI outcome: Refusal modal title not captured in this session; ResultView did not appear.

Notes: `maskAgeMs=-1` on `estimate.start` despite pre-shutter `segmenter.substage.*` events firing — captured for triage in `specs/bugfixes/no-food-pixels-on-fruit-plate-mvp/`.

---

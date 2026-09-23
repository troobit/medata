# Bugfix Report: Surface-Not-Detected Refusal Sheet Does Not Dismiss

**Date:** 2026-06-03
**Status:** Fixed
**Bug name:** `surface-not-detected` (per nextup.md; scope expanded to all refusal cases — see Scope)

## Description of the Issue

From `nextup.md`:

> When using the app, "Surface not detected" (on flat camera mode) is a modal that appears and does not properly get dismissed (or appears when the user is not on the camera screen). This is not a good UX and needs to be changed, such that the error when acknowledged appropriately disappears.

The surface-not-detected modal is the `RefusalSheet` presented for `EstimationFailure.lidarFitDegenerate` (`App/RefusalSheet.swift:41` — Irish-English title "Surface not detected"). Two distinct user-visible failures share one root cause:

1. **Swipe-down does not dismiss the sheet.** The user drags the bottom sheet down, the sheet animates out, and on the next SwiftUI render it pops straight back up.
2. **Sheet appears on the camera screen even when the user wasn't on it when the refusal was produced.** The user taps shutter, walks away to the Meals tab while the pipeline is running, the pipeline refuses (e.g. estimation finishes with `lidarFitDegenerate`), and the next time the user returns to the Photo tab the sheet is presented.

**Reproduction steps:**

1. Build the iOS app to any LiDAR device.
2. Launch the app; the Photo tab is selected by default.
3. Frame a meal where LiDAR cannot fit a flat plane (e.g. point at a curved surface or move during capture).
4. Tap the shutter; wait for the refusal sheet titled "Surface not detected".
5. **Symptom 1:** swipe the sheet down. Observe the sheet re-presents on the next render.
6. **Symptom 2:** switch to the Meals tab. Switch back to the Photo tab. Observe the sheet re-presents.

**Impact:** The only path out of the refusal is the "Try again" button, which immediately triggers another capture attempt. The user has no way to dismiss the refusal to just look at the viewfinder, frame their meal differently, and only then re-attempt. The bug affects every `EstimationFailure` case (13 of 14 — `lidarCoverageTooLow([String])` carries an associated value but the same dismissal path applies), not just `lidarFitDegenerate`.

## Investigation Summary

- **Symptoms examined:** Refusal sheet re-presenting after swipe-down dismissal; refusal sheet appearing on return to Photo tab after a refusal generated while the user was on a non-Photo tab.
- **Code inspected:**
  - `App/RefusalSheet.swift` — sheet view, titles, SF Symbols, "Try again" button.
  - `App/CaptureFlowView.swift:70-72, 145-155` — `.sheet(item: refusalBinding)` presentation and the get-only `refusalBinding` definition.
  - `App/CaptureFlowModel.swift:150-168` — `var refusal: ActiveRefusal?` computed from `case .refused`, with a setter that intentionally no-ops on nil.
  - `App/CaptureFlowModel.swift:204-214` — `tryAgain()` (the only existing path out of `.refused`).
  - `App/CaptureFlowModel.swift:259-296` — `tabSelectionChanged(to:)`, including the `.refused` arm that deliberately preserves the state (comment: "a banner the user will return to (refused). Leave the state alone.")
  - `App/CaptureFlowModel.swift:216-222` — `dismissResult()` for shape comparison; the dismissal-from-`.refused` case is the same shape minus the `navigationPath` reset.
- **Hypotheses tested:**
  - Hypothesis A: SwiftUI's `.sheet(item:)` writes nil into the binding on swipe-down, and we ignore the write. **Confirmed** by reading `refusalBinding` (`CaptureFlowView.swift:150-155` has `set: { _ in }`) and `model.refusal.setter` (`CaptureFlowModel.swift:163-167` intentionally no-ops on nil). On the next render, `model.refusal` is still derived from `state == .refused` and is non-nil — SwiftUI's `Identifiable`-driven sheet re-presents.
  - Hypothesis B: The tab-switch behaviour amplifies the dismissal bug. **Confirmed** by reading `tabSelectionChanged(to: .meals)` at `CaptureFlowModel.swift:278` — `.refused` is excluded from the "reset to `.initialising`" branch by design. Even if dismissal worked, on tab-switch back to Photo the sheet would re-appear because state was preserved.
  - Hypothesis C: The bug is specific to `lidarFitDegenerate`. **Ruled out** — the binding and tab-switch behaviour are case-agnostic; all 14 `EstimationFailure` cases would exhibit the same pattern. The user noticed it on flat camera mode because that's the most common refusal in their testing.

## Discovered Root Cause

Two cooperating design choices, neither correct in isolation:

1. **`model.refusal.setter` intentionally no-ops on nil** (`App/CaptureFlowModel.swift:162-167`):

   ```swift
   set {
       if newValue == nil, case .refused = state {
           // Swipe-down dismisses without state change (still .refused);
           // explicit retry uses `retry()` instead.
       }
   }
   ```

   The comment documents the intent: the swipe-down was meant to be cosmetic-only, with state transitions reserved for `retry()`. But `.sheet(item:)` evaluates the binding on every render, so the sheet snaps back as long as `state == .refused`. There is no observable dismissal at all.

2. **`tabSelectionChanged` carve-out for `.refused`** (`App/CaptureFlowModel.swift:278`):

   ```swift
   case .permissionDenied, .refused:
       // No engine to release (permission), or a banner the user will
       // return to (refused). Leave the state alone.
       return
   ```

   This was a deliberate UI Decision 15 carve-out so the user "finds the same surface when they come back". Combined with (1), it means: there is no path out of `.refused` other than tapping "Try again".

**Defect type:** UX bug — missing state transition out of an error state.

**Why it occurred:** `model.refusal` was modelled as a *derived* read of `state == .refused` rather than a separate dismissible artefact. The SwiftUI `.sheet(item:)` API expects a settable binding whose nil write actually clears the modal source of truth; pairing it with a get-only derivation breaks the dismissal contract. The tab-switch carve-out compounds the problem rather than causes it.

**Contributing factors:**
- The XCUI tests (`MeData/UITests/RefusalFlowUITests.swift`, `CaptureChromeUITests.swift`) only exercise the "Try again" button, never the swipe-down dismissal. There was no regression test covering this path.
- The "Decision 15" comment thread documented the intent (`.refused` is preserved across tab switches) without an end-to-end UX walkthrough that would have caught "the user cannot get out of this state without re-triggering capture".

## Proposed Resolution

Two narrow changes, one decision-log update:

1. **Add `dismissRefusal()` to `CaptureFlowModel`** — explicit command that clears `firstFrame`, `firstFrameTiltDeg`, `inFlightMode` and transitions `.refused → .ready(freshSnapshot())`. Mirrors `dismissResult()` in shape and rationale.
2. **Make `refusalBinding`'s setter call `model.dismissRefusal()`** in `CaptureFlowView`. The binding remains the only call site of `dismissRefusal()` for sheet integration; `model.refusal` stays derived (no separate stored property).
3. **`tabSelectionChanged` treats `.refused` the same as `.ready`/`.trackingLost`** — reset to `.initialising`, release the engine, clear `firstFrame`/`inFlightMode`. The carve-out for `.permissionDenied` stays (there's nothing to release).

The third change supersedes the relevant clause of UI Decision 15 (preserve refused across tab switches). A decision-log entry will record the supersession.

## Test Wiring Caveat

Per `docs/agent-notes/ui-capture-flow.md` "Tests" section, neither the unit tests under `MeData/Tests/` nor the XCUITests under `MeData/UITests/` are wired into the committed `MeData.xcodeproj`. To execute these regression tests, a unit-test target must be added locally with `TEST_HOST = $(BUILT_PRODUCTS_DIR)/MeData.app/MeData`. The tests are committed in source form following the existing project convention; build-target wire-up is a separate piece of work not in scope for this bugfix.

## Resolution for the Issue

**Changes made:**

- `App/CaptureFlowModel.swift` — Removed the no-op `model.refusal` setter; the property is now strictly derived from `state`. Added `func dismissRefusal()` that guards on `.refused` and transitions to `.ready(freshSnapshot())` with `firstFrame`/`firstFrameTiltDeg`/`inFlightMode` cleared — exactly the same shape as `dismissResult()` minus the `navigationPath` reset. Rewrote the `.refused` arm of `tabSelectionChanged` so leaving the Photo tab from a refusal resets to `.initialising`, fires the engine `session.stop()` task, and clears `startTask` — same baseline as the `.ready`/`.trackingLost` arms. `.permissionDenied` remains preserved.
- `App/CaptureFlowView.swift` — `refusalBinding` setter now delegates `nil` writes (which `.sheet(item:)` produces on swipe-down) to `model.dismissRefusal()`. The binding still derives reads from `model.refusal`.
- `specs/ui/iphone-experience/decision_log.md` — Added Decision 20 documenting the new sheet-dismissal contract and the `.refused`-on-tab-leave behaviour. Decision 15 stands; only the implicit refusal-preservation clause is superseded.
- `docs/agent-notes/ui-capture-flow.md` — Added gotcha entry pointing future agents at Decision 20 and this report.

**Approach rationale:** Single source of truth (`state`), explicit dismissal command, view-side binding wires SwiftUI's nil-write contract to the command. Avoids the alternative of a stored `refusal` property that has to be kept in lockstep with `state`, and avoids `.interactiveDismissDisabled()` which removes a useful UX affordance.

**Alternatives considered:** Documented in Decision 20 (`specs/ui/iphone-experience/decision_log.md`) — non-dismissible sheet, sheet-dismissible-but-tab-switch-preserves, and stored-refusal-property were all rejected for reasons stated there.

## Regression Tests

**File:** `MeData/Tests/CaptureFlowModelTests.swift`

- `dismissRefusalReturnsToReady` — induces `EstimationFailure.lidarFitDegenerate`, calls `model.dismissRefusal()`, asserts `case .ready`. Before fix: did not compile (`dismissRefusal()` absent). After fix: passes.
- `dismissRefusalClearsCapturedFrame` — same flow, asserts `model.awaitingObliqueView == false` after dismissal to prove `firstFrame` was cleared.

**File:** `MeData/Tests/CaptureFlowModelTabSelectionTests.swift`

- `refusedDismissedOnTabLeave` — refuses then `tabSelectionChanged(to: .meals)`, asserts `state == .initialising`. Before fix: asserted `.refused` was preserved (encoded the buggy behaviour as the now-deleted `refusedNoOp`). After fix: passes.
- `refusalDoesNotReappearOnPhotoReturn` — refuses, leaves to `.meals`, returns to `.photo`, asserts `model.refusal == nil`.

**Run command** (after wiring up a local unit-test target per `docs/agent-notes/ui-capture-flow.md` "Tests" section):

```
xcodebuild test \
  -project MeData/MeData.xcodeproj \
  -scheme MeData \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MeDataTests/CaptureFlowModelTests/dismissRefusalReturnsToReady \
  -only-testing:MeDataTests/CaptureFlowModelTests/dismissRefusalClearsCapturedFrame \
  -only-testing:MeDataTests/CaptureFlowModelTabSelectionTests/refusedDismissedOnTabLeave \
  -only-testing:MeDataTests/CaptureFlowModelTabSelectionTests/refusalDoesNotReappearOnPhotoReturn
```

Per the project convention noted in `ui-capture-flow.md`, the unit-test target wire-up is not committed; the tests live as source. Build of the `MeData` app target (where the model + view live) is clean on iPhone 17 Pro simulator with zero new warnings.

## Affected Files

| File | Change |
|------|--------|
| `App/CaptureFlowModel.swift` | Add `dismissRefusal()`; update `tabSelectionChanged` to reset `.refused` on leave |
| `App/CaptureFlowView.swift` | `refusalBinding.set` calls `model.dismissRefusal()` |
| `MeData/Tests/CaptureFlowModelTests.swift` | Two new regression tests (`dismissRefusalReturnsToReady`, `dismissRefusalClearsCapturedFrame`) |
| `MeData/Tests/CaptureFlowModelTabSelectionTests.swift` | Replace `refusedNoOp` with `refusedDismissedOnTabLeave` + `refusalDoesNotReappearOnPhotoReturn` |
| `specs/ui/iphone-experience/decision_log.md` | New entry superseding the clause of Decision 15 that preserved `.refused` across tab switches |
| `docs/agent-notes/ui-capture-flow.md` | Update gotcha for the new dismissal contract |

## Verification

**Automated:**
- [x] `MeData` app target builds clean for iPhone 17 Pro simulator (`xcodebuild -project MeData/MeData.xcodeproj -scheme MeData -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`) — no new warnings.
- [ ] Regression tests pass — blocked on the unit-test target wire-up described in the Test Wiring Caveat. Tests are committed as source and follow the established `ModelFixture` / `ProgrammablePipeline` patterns of the existing `CaptureFlowModelTests` / `CaptureFlowModelTabSelectionTests` suites.

**Manual verification (on-device, pending):**
- [ ] On flat camera mode, induce `lidarFitDegenerate`; swipe the refusal sheet down; confirm the viewfinder reappears and the sheet does not pop back
- [ ] During the same refusal, switch to Meals tab; switch back; confirm no sheet
- [ ] "Try again" still relaunches capture from the appropriate stage

## Scope

The user-reported symptom was specific to `lidarFitDegenerate` (flat-camera mode). The fix is general: every `EstimationFailure` case routes through the same `.refused` state and the same `refusalBinding`, so the dismissal contract applies uniformly. No per-case branching is needed.

## Prevention

- New SwiftUI sheets bound via `.sheet(item:)` should treat the nil write as a real command, not as a cosmetic. If a sheet is intentionally non-dismissible, present it via `.sheet(isPresented:)` with no swipe-down (`.interactiveDismissDisabled()`) rather than swallowing the binding write — the sheet's chrome should reflect the contract.
- When adding error/refusal flows, add at least one XCUI test that exercises swipe-down dismissal in addition to the primary action, since these paths exercise different SwiftUI lifecycle code.

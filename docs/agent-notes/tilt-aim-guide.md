# Tilt aim guide

Persistent graphical aiming guide for the capture flow's tilt target, on the
`ui` worktree/branch. Replaces the reliance on the numeric `LiveIndicatorBadge`
for hitting the per-stage tilt angle.

## Why it exists

The numeric `LiveIndicatorBadge` auto-hides 5s after framing is in range
(`LiveIndicatorModel.scheduleHide`). That auto-hide is the "the guides disappear
at times" complaint: the angle target vanished mid-adjustment. The fix is a
*separate, persistent* graphical guide that never auto-hides; the badge keeps
doing distance/coverage.

## Shared logic — `TiltAimGuideState` (App/TiltAimGuide.swift)

Pure, host-free enum holding everything testable:

- `target(awaitingOblique:)` → 0° nadir, 25° oblique (matches
  `CaptureFlowModel.tiltInRange` / `obliqueTiltOk`).
- `toleranceDegrees(awaitingOblique:)` → ±12° nadir (advisory; no nadir shutter
  gate), ±15° oblique (mirrors the live shutter gate `obliqueTiltOk`,
  `abs(θ−25) ≤ 15`, closeout-trail Decision 1).
- `offsetFraction(tilt:target:)` → signed −1…1 over ±`halfSpanDegrees` (30°), clamped.
- `isAligned(tilt:target:tolerance:)` → inclusive at the band edge.
- `correction(tilt:target:tolerance:)` → 0 in-band, −1 over-tilted, +1 under-tilted.

Both guide designs read the same state, so colour/glyph semantics and the tested
maths are identical between them.

## Two designs — switch with one line

`CaptureFlowView.tiltGuideStyle` (`TiltGuideStyle` enum) selects which renders.
Default is `.gauge`. Both are wired identically in `CaptureFlowView.capture`:
leading-aligned, vertically centred over the viewfinder,
`allowsHitTesting(false)`, shown under the same condition as the badge
(`currentSnapshot != nil`, not estimating, not initialising).

| Style | File | Form | Notes |
|-------|------|------|-------|
| `.gauge` (attempt 1, default) | `App/TiltAimGuide.swift` | Vertical bar; a puck tracks tilt against a centred target band | Tilt→vertical mapping is the natural one for pitch |
| `.dial` (attempt 2) | `App/TiltDialGuide.swift` | Quarter-circle protractor; a needle rotates into a target wedge | "Rotate the needle into the band" reads more literally as an angle |

Tags `tilt-guide-attempt-1` and `tilt-guide-attempt-2` mark each design's commit
for `git checkout` comparison. Both compile; final visual choice needs the
user's eyes on a real capture (ARKit tilt isn't observable in the simulator).

### Shared visual rules (both designs)

- In-range snaps to `medataAccent` — the same accent the badge uses for in-range
  distance/coverage. NOT the green/red in/out scheme Decision 19 removed.
- The puck/needle hub carries a glyph: `checkmark` when aligned, `chevron.up` /
  `chevron.down` to show which way to tilt, so meaning is never colour-only.
- Reduce-motion (UX rule, High): the puck/needle animation is gated on
  `@Environment(\.accessibilityReduceMotion)` — it snaps instead of sliding.
- Contrast: black glyph on the green/white puck/hub is ~15.8:1 / 21:1. The white
  readout text reuses the already-shipped `captureChromeText`-on-`captureChromeBG`
  chrome pairing (no new risk).

## ⚠️ Test-target gotcha (important)

The Xcode project (`MeData/MeData.xcodeproj`) has **only one native target — the
app — and no unit-test target**. `xcodebuild -scheme MeData test` fails with
"Scheme MeData is not currently configured for the test action."

Consequences:
- Everything in `MeData/Tests/*.swift` (incl. pre-existing `CaptureFlowModelTiltGateTests`,
  `LiveIndicatorBadgeTests`, etc. **and** the new `TiltAimGuideTests.swift`) is
  **not compiled or run by any build-system gate.** These app-level Swift Testing
  suites are effectively orphaned source. A prior note claiming the Tests folder
  is "a synchronized group → auto-included" was wrong: the app target's
  `fileSystemSynchronizedGroup` resolves to `MeData/MeData/` (just
  `Assets.xcassets`); app sources in `App/` are explicit file refs.
- The only automated suite is the SwiftPM package `MedataCore`
  (`swift test`) → **313 XCTest + 16 Swift Testing, 0 failures** is the green
  baseline. It does not cover any app (`App/`) code.

So the real gate for an app-target change is **`xcodebuild build` succeeds** plus
the unchanged `swift test` baseline. `TiltAimGuideTests.swift` is kept because it
is convention-consistent with the other app-test files and will run the day a
test target is added — but it does not run today.

Recommendation (not done — out of this task's scope, and a structural change that
would affect everyone): add a unit-test target hosting the app so the ~24 app
test files actually run. Gate any such change on `xcodebuild test` passing.

## Verification status

- `xcodebuild -scheme MeData -destination 'generic/platform=iOS Simulator' build`
  → **BUILD SUCCEEDED** with both designs compiled.
- `swift test` → 313 XCTest + 16 Swift Testing, **0 failures** (baseline unchanged;
  no `MedataCore` code touched).
- Not yet done: on-device visual check of either guide (needs real ARKit tilt);
  pick the final `tiltGuideStyle`.

## Files

- `App/TiltAimGuide.swift` — `TiltAimGuideState` + `.gauge` view.
- `App/TiltDialGuide.swift` — `.dial` view (reuses the state).
- `App/CaptureFlowView.swift` — `TiltGuideStyle`, `tiltGuideStyle`, `tiltGuide`
  builder, and the wired-in overlay.
- `MeData/Tests/TiltAimGuideTests.swift` — pure-state tests (orphaned; see above).
- `MeData/MeData.xcodeproj/project.pbxproj` — explicit file refs for both views.

## Decision-log note

No `decision_log.md` entry was written (the user chose a direct edit, not a
smolspec). If a design is kept, consider an ADR alongside Decisions 16/18/19,
which govern the existing indicator/colour surface.

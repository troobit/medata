# Bugfix Report: First-Shot noFoodPixels Race

**Date:** 2026-06-23
**Status:** Fixed

## Description of the Issue

On the **first** shutter tap of a capture session the shutter could fire before
the pre-shutter segmenter had published any food mask. The capture path then
built a `CaptureResult` with no pre-shutter mask, the support-plane fitter's
empty-mask gate refused, and the tap mapped to `EstimationFailure.noFoodPixels`
— a failed estimate the user had to retry. The **second** tap (mask now ready)
succeeded.

**Reproduction steps:**
1. Cold-launch a capture session; let the viewfinder reach `.ready`.
2. Tap the shutter immediately, before the 2 Hz pre-shutter producer has
   published its first mask.
3. Observe (device log): `event=estimate.start maskAgeMs=-1` with
   `canShutter=true` -> support-plane `failure=emptyFoodMask` ->
   `EstimationFailure.noFoodPixels` -> refusal. The next tap succeeds.

**Impact:** Model-independent gating defect. Every fresh session's first tap was
at risk of a spurious "no food detected" refusal even with food perfectly framed.
Severity: user-facing correctness (false refusal on the most common first action).

## Investigation Summary

- **Symptoms examined:** `maskAgeMs=-1` (the `preShutterMaskAgeMs ?? -1` sentinel
  in `Pipeline.swift:82`) co-occurring with `canShutter=true`, only on the first
  tap; the immediate retry always succeeded.
- **Code inspected:**
  - `App/CaptureFlowModel.swift` — `canShutter` (the shutter arm gate) and the
    nadir capture path that snapshots `preShutterSegmenter.latest`.
  - `App/PreShutterSegmenter.swift` — the 2 Hz producer; `latest` is `nil` until
    the first inference cycle publishes, and survives `pause()`.
  - `MedataCore/Sources/Pipeline/Pipeline.swift:82` (the `maskAgeMs` log) and the
    `SupportPlaneError.emptyFoodMask -> EstimationFailure.noFoodPixels` mapping
    (lines 553-554).
- **Hypotheses tested / ruled out:**
  - *Staleness gate too aggressive* — ruled out; the 750 ms ceiling in
    `performFlow` is correct. The first-tap case has **no** mask at all, not a
    stale one.
  - *Oblique `maskAgeMs=nil` path* (prior bugfix `no-food-pixels-on-fruit-plate-mvp`)
    — ruled out; that was the two-view oblique stage dropping a *present*
    nadir-instant age. This bug is the nadir stage firing with no mask produced
    yet. The two fixes are independent and consistent.

## Discovered Root Cause

`canShutter` armed the nadir shutter whenever the state was `.ready` and the
distance gate passed — with no requirement that a pre-shutter food mask actually
exists yet. The pre-shutter producer publishes asynchronously at ~2 Hz and
`PreShutterSegmenter.latest` is `nil` until its first inference cycle completes,
so there is a window at the start of every `.ready` period where the shutter is
armed but no mask is available.

**Defect type:** Race condition / missing precondition in a UI gate.

**Why it occurred:** The shutter arm gate (`canShutter`) and the mask
availability (produced asynchronously off-MainActor) were never coupled. The
capture path tolerated a missing mask by emitting the `maskAgeMs=-1` sentinel and
delegating refusal to the pipeline, instead of preventing the tap.

**Contributing factors:** First-tap-of-session warm-path latency (Vision warmup,
first segmenter inference) widens the maskless window precisely when users are
most likely to tap quickly.

## Resolution for the Issue

**Changes made:**
- `App/CaptureFlowModel.swift` — `canShutter` now gates the nadir stage
  (`firstFrame == nil`) on `hasUsablePreShutterMask`. The oblique stage and the
  distance gate are unchanged.
- `App/CaptureFlowModel.swift` — new private computed property
  `hasUsablePreShutterMask`: true iff `preShutterSegmenter.latest` exists and is
  within the same **750 ms** freshness bound the capture path applies at the
  nadir-capture instant. When no segmenter is injected (legacy / unit-test
  callers; `App.swift` always passes one) the gate is bypassed so the shutter is
  never permanently disabled.
- `App/CaptureFlowModel.swift` — `shutter()` gains the matching command-side
  guard (`firstFrame == nil, !hasUsablePreShutterMask -> return`), consistent with
  the existing distance / oblique-tilt re-checks, so a programmatic or racing fire
  cannot begin a maskless nadir capture.

**Approach rationale:** Gating at the arm point is the minimal, model-independent
fix. Reusing the existing 750 ms ceiling means the shutter never arms on a mask
the capture path would then discard (no arm-then-refuse), and never double-refuses.
A `canShutter == false` nadir state already presents through the existing
disabled-shutter "waiting" UX (`ShutterButtonState.disabled` + the auto-hidden
indicator badge revealed on a blocked tap) — no new UI was needed. The fix never
permanently disables the shutter: as soon as the producer publishes a fresh mask
(every ~500 ms once running) the shutter arms.

**Alternatives considered:**
- *Block in the capture path until a mask arrives* — rejected; introduces an
  unbounded wait on the MainActor flow and risks the 22 s freeze class of bug.
- *Synthesize an empty mask when none exists* — rejected; pushes a meaningless
  all-zero mask into the pipeline and hides the real "not ready yet" condition.
- *Lower the staleness bound for the arm gate* — rejected; an inconsistent bound
  would create an arm-then-refuse gap.

## Regression Test

**Test file:** `MeData/Tests/CaptureFlowModelPreShutterTests.swift`
**Test names:**
- `nadirShutterDisarmedWithoutMask` — in `.ready` with the distance gate
  satisfied but `latest == nil`, `canShutter == false` and a `shutter()` call
  spawns no flow task (state stays `.ready`).
- `nadirShutterArmsWithFreshMask` — once a fresh (`ageMs: 0`) mask is published,
  `canShutter == true`.
- `nadirShutterDisarmedWithStaleMask` — a mask older than 750 ms does not arm the
  shutter (no arm-then-refuse).

**What they verify:** the nadir shutter is disarmed until a usable, fresh
pre-shutter mask is present, and arms exactly when one is.

**Run command:** `xcodebuild test -project MeData/MeData.xcodeproj -scheme MeDataTests -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
(requires a temporary unit-test target — the App test target is not wired into
the committed Xcode project by design; see `docs/agent-notes/ui-capture-flow.md`).

## Affected Files

| File | Change |
|------|--------|
| `App/CaptureFlowModel.swift` | `canShutter` + `shutter()` gate the nadir stage on `hasUsablePreShutterMask`; new private `hasUsablePreShutterMask` helper. |
| `MeData/Tests/CaptureFlowModelPreShutterTests.swift` | Three regression tests for the nadir arm gate. |

## Verification

**Automated:**
- [x] `swift test --package-path MedataCore` — 16 tests, 5 suites, all pass
      (baseline; the pipeline-layer empty-mask chain is unchanged).
- [x] App target builds clean: `xcodebuild build -project MeData/MeData.xcodeproj
      -scheme MeData -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
      -> `BUILD SUCCEEDED` (validates the production change compiles against the
      real types).
- [ ] App-layer unit tests (`MeData/Tests/`) — **not run.** The App test target
      is not part of the committed Xcode project (documented convention; only one
      `MeData` target exists, no test bundle). A temporary test target was
      scripted in this session, but `@testable import MeData` did not resolve
      App-defined symbols (`CaptureMode`, `CapturePathDecider`) under the ad-hoc
      target — the same fragility the agent note flags. The project was restored
      to pristine; the new tests follow the existing passing suite's fixtures and
      spies verbatim so they compile against the same module those tests do.

**Manual verification:** Not performed (no device session in this task). On-device
the expected behaviour is: cold-launch -> `.ready` -> the shutter reads as
disabled until the first `event=preshutter.mask.update` line, then arms; the
first tap can no longer emit `maskAgeMs=-1` / `noFoodPixels`.

## Prevention

**Recommendations to avoid similar bugs:**
- Couple UI arm gates to the asynchronous preconditions their downstream path
  requires, rather than relying on the downstream layer to refuse.
- When a value has a freshness contract (the 750 ms ceiling here), apply the same
  bound at every gate that consumes it to avoid arm-then-refuse gaps.
- Wire the App test target into the Xcode project (or a Package-based test target)
  so model-level regressions like this can be caught in CI rather than on device.

## Related

- `specs/bugfixes/no-food-pixels-on-fruit-plate-mvp/` — the adjacent (and
  independent) two-view oblique `maskAgeMs=nil` fix; this fix is consistent with it.
- `MedataCore/Sources/Pipeline/Pipeline.swift:82` — the `maskAgeMs` log line.
- `MedataCore/Sources/Pipeline/Pipeline.swift:553-554` — the
  `emptyFoodMask -> noFoodPixels` mapping (left unchanged; App-layer gate).
- `docs/agent-notes/ui-capture-flow.md` — App test target is not committed.

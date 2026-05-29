# Bugfix Report: ARView Session Config Race

**Date:** 2026-05-23
**Status:** Fixed

## Description of the Issue

On iPhone 13 Pro Max, the iOS system log emits paired errors at app launch:

```
(Fig) signalled err=-12710 at <>:601
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:276) - (err=-12784)
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:513) - (err=-12784)
```

These were the same errors that commit `0e77e94` claimed to fix. They returned after `4b67cbc` ("Fixes camera issues") refactored the engine to take ownership of `ARView.session` via a new `bindPreviewSession` method.

**Reproduction steps:**
1. Build the iOS app to an iPhone 13 Pro Max (or any LiDAR device).
2. Launch the app.
3. Observe the system log during the first second of launch.

**Impact:** Log noise (the session does eventually start once the async `start()` task fires, so capture is not permanently broken) plus a brief window where `ARView` renders a bound-but-unconfigured `ARSession` — the visible symptom is a blank or stuttering camera feed for the first frames after launch. Not a release blocker, but a regression against a previously closed bug.

## Investigation Summary

- **Symptoms examined:** Fig / FigCaptureSourceRemote -12710 / -12784 pairs at launch; transient blank preview.
- **Code inspected:**
  - `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` — current `bindPreviewSession` + `applyRunStateIfNeeded` + `start()` flow.
  - `App/ARPreviewView.swift` — `makeUIView` / `updateUIView` binding the engine to the view's session.
  - `App/CaptureFlowModel.swift` — `evaluatePermissions` fires `Task { try? await session.start() }` fire-and-forget.
  - Commit `0e77e94` diff — saw it added `ensureSessionConfigured()` in `ARPreviewView.makeUIView` for exactly this race.
  - Commit `4b67cbc` diff — saw the refactor replaced the synchronous configure with `bindPreviewSession` whose internal `applyRunStateIfNeeded` is guarded by `runRequested`.
- **Hypotheses tested:**
  - Hypothesis A: the errors are pure iOS noise from RealityKit. **Ruled out** — they recur deterministically at app launch and stop once frames start arriving; the `:276` / `:513` pair only fires while a session is being adopted but not running.
  - Hypothesis B: the engine never gets started. **Ruled out** — captures eventually work; the errors stop once `start()` flips `runRequested`.
  - Hypothesis C (confirmed): the binding-of-the-real-session happens *before* `start()` flips `runRequested`, so `applyRunStateIfNeeded` is a no-op on the first call. `ARView` then renders a bound-but-unconfigured session for the duration of the gap.

## Discovered Root Cause

`ARKitCaptureEngine.bindPreviewSession` calls `applyRunStateIfNeeded`, which only runs the world-tracking config when **all three** guards are true:

```swift
guard isBound, runRequested, !isRunning else { return }
```

`runRequested` is only set inside `start()`. At launch:

1. `MedataApp.init` constructs the model; the model's `evaluatePermissions` schedules a `Task { try? await session.start() }`. The task is *scheduled*, not yet executed.
2. SwiftUI builds the view tree; `ARPreviewView.makeUIView` runs synchronously on the main actor and calls `engine.bindPreviewSession(arView.session)`.
3. At that point `runRequested == false`, so `applyRunStateIfNeeded` early-exits.
4. `makeUIView` returns; `ARView` is now displayed with a non-running `ARSession`.
5. The scheduled task eventually runs, flips `runRequested` to `true`, calls `applyRunStateIfNeeded`, and finally runs the config.

The Fig / FigCaptureSourceRemote errors come from step 4 — `ARView` is trying to display from a session that has never had `run(_:options:)` called on it.

**Defect type:** Race condition / missed-precondition.

**Why it occurred:** The `runRequested` gate originally existed to prevent running the *placeholder* `ARSession()` that the engine creates in `init` (before the view hands over its real session). Once the refactor moved session ownership to the view, the same gate started blocking the only run path the new design has — the bind itself.

**Contributing factors:** `CaptureFlowModel`'s `start()` task is fire-and-forget, not awaited before view construction, so any timing dependence on it is implicit.

## Resolution for the Issue

**Changes made:**
- `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift:71-83` — `bindPreviewSession` sets `runRequested = true` before calling `applyRunStateIfNeeded`. Binding a real session is itself the run trigger; the placeholder is still protected by the `isBound` guard.

**Approach rationale:** Smallest change that closes the race without re-introducing per-view configuration logic in `ARPreviewView`. The single ARSession-ownership invariant from Decision 11 is preserved: the engine still runs the config, the view still hands its session over.

**Alternatives considered:**
- Restore `ensureSessionConfigured()` in `ARPreviewView.makeUIView` (the `0e77e94` shape) — rejected: duplicates run logic between the view and the engine, exactly what `4b67cbc` set out to centralise.
- Make `CaptureFlowModel`'s `start()` synchronous — rejected: pushes async-AVFoundation onto the main thread on the launch critical path.
- Remove the `runRequested` gate entirely — rejected: it still guards the placeholder session (e.g. if `start()` were called before any view binding existed, on a future code path).

## Regression Test

**Test file:** `MedataCore/Tests/CaptureKitTests/ARKitCaptureEngineStreamsTests.swift`
**Test name:** `testBindPreviewSessionRunsConfigImmediately`

**What it verifies:** After `engine.bindPreviewSession(external)` returns, `external.configuration` is non-nil. Before the fix this assertion failed because the configuration was deferred to the async `start()` task; after the fix it passes because the bind synchronously runs `session.run(config, options:)`.

**Run command:**
```
xcodebuild test \
  -scheme MedataCore-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,arch=arm64' \
  -only-testing:CaptureKitTests/ARKitCaptureEngineStreamsTests/testBindPreviewSessionRunsConfigImmediately
```

## Affected Files

| File | Change |
|------|--------|
| `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` | `bindPreviewSession` sets `runRequested = true` before `applyRunStateIfNeeded` |
| `MedataCore/Tests/CaptureKitTests/ARKitCaptureEngineStreamsTests.swift` | New regression test `testBindPreviewSessionRunsConfigImmediately` |
| `docs/agent-notes/camera-input-fix.md` | Added regression-and-fix section documenting the `bindPreviewSession` race |
| `CHANGELOG.md` | New `Fixed` entry under `[Unreleased]` |

## Verification

**Automated:**
- [x] Regression test passes (after fix)
- [x] Full `CaptureKitTests` suite passes
- [x] No build errors

**Manual verification:** Pending on-device re-run on iPhone 13 Pro Max — the test reproduces the configuration deferral on the simulator, but the FigCaptureSourceRemote logs only emit on a physical camera-equipped device.

## Prevention

**Recommendations to avoid similar bugs:**
- When refactoring multi-actor lifecycle logic, prefer one explicit precondition over multiple implicit guards (`isBound && runRequested && !isRunning`). The previous gate combination depended on a particular call order that wasn't documented at the call site.
- For racy launch sequences that produce visible system logs, add a regression test that asserts the *post-condition* directly (here: "session.configuration is non-nil after bind"). The FigCaptureSourceRemote logs are an effect, not the contract.

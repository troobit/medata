# Camera Input Fix for iPhone 13 Pro Max

## Problem

When running the MeData app on iPhone 13 Pro Max, the UI renders correctly but the camera feed appears blank. System logs show repeated FigCapture/CMCapture errors:

```
(Fig) signalled err=-12710 at <>:601
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:276) - (err=-12784)
<<<< FigXPCUtilities >>>> signalled err=-17281 at <>:308
```

## Root Cause

The camera input race condition occurred because:

1. **ARPreviewView** creates an `ARView` with `automaticallyConfigureSession: false`
2. ARView immediately attempts to render the camera feed before it's ready
3. The **ARSession configuration and startup** happens asynchronously in `CaptureFlowModel.evaluatePermissions()` via `session.start()`
4. This creates a timing gap where ARView tries to display camera input from an unconfigured, non-running session
5. ARKit's capture layer fails with the above errors when trying to access a camera session that isn't properly initialized

## Solution

### 1. Synchronous Session Configuration in ARPreviewView

Added `ensureSessionConfigured()` method in `ARPreviewView.makeUIView()`:

```swift
private func ensureSessionConfigured() {
    let session = engine.arSession
    if session.configuration == nil {
        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        config.worldAlignment = .gravity
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }
}
```

This guarantees that:

- The ARSession is configured and running **before** ARView attempts to display it
- LiDAR support is detected and enabled if available
- The session is ready for the camera capture layer to initialize

### 2. Idempotent Session Startup in ARKitCaptureEngine

Updated `ARKitCaptureEngine.start()` to avoid re-running an already-configured session:

```swift
if session.configuration == nil {
    session.run(config, options: [.resetTracking, .removeExistingAnchors])
} else if case let current as ARWorldTrackingConfiguration = session.configuration,
          !current.frameSemantics.contains(.sceneDepth) && supportsLiDAR {
    // Update frame semantics if LiDAR support was added after initial config
    session.run(config, options: [.resetTracking, .removeExistingAnchors])
}
```

This ensures:

- If ARPreviewView already configured the session, we don't duplicate the initialization
- If LiDAR frame semantics need to be added, we still update the running configuration
- The engine retains full lifecycle control while respecting view-layer initialization

## Testing

All existing tests pass:

- **ARKitCaptureEngineStreamsTests** — verifies delegate identity, interruption ordering, and stream cleanup
- **ARPreviewViewTests** — verifies delegate reassertion and recovery from foreign delegate takeovers
- Full test suite: 239 tests pass with 0 failures

## Architecture Notes

- **Engine owns session lifecycle**: `ARKitCaptureEngine` remains the authoritative `ARSession` owner and its sole `ARSessionDelegate`
- **View ensures display readiness**: `ARPreviewView` guarantees the session is ready for rendering before passing it to `ARView`
- **Idempotent design**: Both the view and engine can run configuration logic; the second call is a no-op (or updates LiDAR if needed)
- **No frame loss**: The synchronous configuration in `makeUIView()` runs before any frame updates, preventing missed captures

## Decision Points

1. **Synchronous vs. async configuration**: Chose synchronous in `makeUIView()` to eliminate the race condition. The configuration call is fast (milliseconds) and must complete before the view can display.

2. **Why check `session.configuration == nil`**: ARSession doesn't expose a "is running" flag; checking for `nil` configuration is the idiomatic way to detect if it's been started.

3. **LiDAR update logic**: The second branch in `start()` handles the edge case where LiDAR becomes available after initial configuration (e.g., device capability detection during startup).

## Related Code

- `App/ARPreviewView.swift` — camera preview view wrapper
- `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` — ARKit session orchestrator
- `App/CaptureFlowModel.swift` — flow state machine and async session startup

---

## 2026-05-23 — Regression and re-fix (`arview-session-config-race`)

The errors above returned after commit `4b67cbc` refactored `ARPreviewView.ensureSessionConfigured()` into engine-owned `ARKitCaptureEngine.bindPreviewSession`. Logged on iPhone 13 Pro Max:

```
(Fig) signalled err=-12710 at <>:601
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:276) - (err=-12784)
<<<< FigCaptureSourceRemote >>>> Fig assert: "err == 0 " at bail (FigCaptureSourceRemote.m:513) - (err=-12784)
```

### Why it regressed

The refactor introduced three internal flags on the engine: `runRequested`, `isBound`, `isRunning`. The session-run logic moved into:

```swift
private func applyRunStateIfNeeded() {
    guard isBound, runRequested, !isRunning else { return }
    // … session.run(config, options:) …
}
```

`bindPreviewSession` set `isBound = true` and called this helper, but **did not** set `runRequested`. `runRequested` was only flipped by `start()` (called fire-and-forget from `CaptureFlowModel.evaluatePermissions()` via `Task { try? await session.start() }`).

At launch, `ARPreviewView.makeUIView` (synchronous main-actor) ran before the scheduled `start()` task. Result: `bindPreviewSession` → `applyRunStateIfNeeded` early-exit → `ARView` displayed for milliseconds rendering a bound-but-not-running `ARSession`. The Fig / FigCaptureSourceRemote errors are emitted during that gap.

The `runRequested` flag had originally been added to prevent running the *placeholder* `ARSession()` the engine creates in its `init` before any view has bound a real session. That precondition is still needed, but it's already covered by `isBound`.

### Fix

In `bindPreviewSession`, set `runRequested = true` immediately before the call to `applyRunStateIfNeeded`:

```swift
@MainActor
public func bindPreviewSession(_ external: ARSession) {
    if external !== session {
        session.delegate = nil
        session.pause()
        session = external
        isRunning = false
    }
    session.delegate = self
    isBound = true
    // Binding a real session IS the run trigger — `CaptureFlowModel.start()`
    // runs fire-and-forget and may not have flipped `runRequested` yet.
    runRequested = true
    applyRunStateIfNeeded()
}
```

The placeholder session is still protected by the `isBound` guard inside `applyRunStateIfNeeded` — if `start()` is called before any `bindPreviewSession`, the helper still early-exits.

### Regression test

`MedataCore/Tests/CaptureKitTests/ARKitCaptureEngineStreamsTests.swift::testBindPreviewSessionRunsConfigImmediately` — asserts `engine.isRunning == true` immediately after `bindPreviewSession`. The test relies on `isRunning` being `internal` rather than `private`; `@testable import CaptureKit` reaches it.

The test asserts on the engine's `isRunning` flag rather than `ARSession.configuration`. The latter looks tempting (Apple docs say `run(_:options:)` updates `configuration` immediately) but in the iOS Simulator, without a real camera, `configuration` stays nil and a `configuration != nil` assertion is unreliable. `isRunning` is the engine-internal post-condition that proves `applyRunStateIfNeeded` cleared its guard and called `session.run`.

### Bug report

Full report: `specs/bugfixes/arview-session-config-race/report.md`.

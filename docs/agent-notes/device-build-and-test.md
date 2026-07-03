# Device build & test loop (and what's next)

How we get a build onto a physical iPhone, why the current process has friction,
and what removes that friction. Written 2026-06-24 after a device session where
no meal would record from an Xcode (Debug) build. Updated 2026-07-03: the loop
is now automated behind Make targets (below) — use those, not hand-typed
incantations.

## The canonical loop — Make targets

The repo-root `Makefile` is the one true way to run the loop (the same
xcodebuild/devicectl commands were previously retyped ~50 times):

- `make build` / `make test` — SwiftPM core. `make test` prints **both** test
  totals (XCTest ~323 + swift-testing 16). Never report only one framework's
  slice as "the" test count.
- `make deploy-device` — Debug build + install + launch on PhoneMax
  (override `DEVICE_UDID=` / `DEVICE_NAME=`). UI/non-capture work only.
- `make deploy-release-stub` — the automated Path B below (capture testing).
- `make logs-device` — pulls the last `LOG_LAST` (default 10m) of device logs
  filtered to `subsystem == "ie.medata.app"`, to stdout and
  `/tmp/medata-device.log`. **Post-hoc only** — macOS has no scriptable live
  stream for an iOS device (`log stream` is host-only, devicectl has no log
  subcommand); live viewing stays in Console.app (recipe below).
- `make spell` — Irish/British spelling lint.

Default device: PhoneMax, iPhone 13 Pro Max, devicectl identifier
`76A45E6D-C57E-5BA6-ABAD-205C3C668572`, bundle `rtob.MeData`. Note the
devicectl (CoreDevice) identifier is NOT the hardware UDID — `log collect
--device-udid` wants the hardware one, which is why the Makefile matches the
device by name instead.

(This automation does not contradict "Less is more" below: it scripts the
existing recipe verbatim and adds zero gating machinery to the codebase.)

## Build stamp — always check it before trusting a trail

Stale binaries on the device have silently invalidated 2–3 full capture
rounds. Every Make-built binary logs one line at launch on the
`ie.medata.app` / `Shutter` channel:

```
event=launch buildStamp=<git-sha>-<timestamp> segmenterSource=stub|coreml
```

The Make target prints the same stamp (`DEPLOYED BUILD STAMP: …`) at deploy
time. **Before trusting any captured trail, match the on-device stamp against
the deploy output**, and check `segmenterSource` is what you think you are
testing — days were lost debugging against the stub without realising. A plain
Xcode Run logs `buildStamp=unstamped` (the stamp comes from the
`MEDATA_BUILD_STAMP` build setting via `MeData/Info.plist`, which only the
Make targets set).

## Debug vs Release stub matrix

| Build | Segmenter | Capture-testable? |
|---|---|---|
| Debug (Xcode Run / `make deploy-device`) | stub at `-Onone`, ~20 s/mask | **No** — mask stale, `canShutter=false` ~19 s of every 20 |
| Release, plain | none (real model not shipped yet) | **No** — **crashes at launch**; the stub is Debug-only |
| Release + forced stub (`make deploy-release-stub`) | stub at ~2 Hz | **Yes** — the only capture-testable build until the real model lands |

The stub emits a mask roughly every ~20 s in Debug, so the sub-second arming
window is unhittable; details and the log tells are in the sections below.

## Console.app filter recipe (live viewing)

Re-derived at least four times — this is the recipe:

1. Console.app → select the iPhone in the sidebar → Start streaming.
2. Filter field: `subsystem: ie.medata.app` (add `category: Shutter` to narrow
   to the shutter/pipeline `event=…` lines). `process: MeData` also works but
   picks up ARKit/Fig noise.
3. **Action menu → Include Info Messages AND Include Debug Messages** — the
   `event=…` lines are `.info`/`.debug` level and invisible without this.
4. Do NOT hand-paste long trails into a chat session (one paste blew the
   context window; several were truncated). Use `make logs-device` and grep
   `/tmp/medata-device.log` for the relevant `event=` lines instead.

## What is next

**The real ML segmenter model (Track 3) is the next thing to build, and it is the
thing that dissolves every pain described below.** Today the capture pipeline runs
against `StubInferenceEngine` — a placeholder that paints a fixed food region. The
next milestone is to train and integrate the 27-class CoreML segmenter
(`MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage`, see `tools/segmenter/export.py`) and
drop the stub.

Why it is the priority, beyond accuracy:

1. **It makes estimates real.** The stub labels ~38%+ of the frame as food, which
   is why placeholder carb values are wild. The real model fixes that for free.
2. **It removes the Debug/Release split.** Release builds are meant to bind the
   real model (`CoreMLInferenceEngine`). It doesn't exist yet, so a plain Release
   build has no segmenter and crashes — which is the entire reason we hand-force
   the stub into Release to test (below). Once the model ships, Release builds run
   the real engine natively with no flag-flipping.
3. **It removes the speed friction.** The real model runs on the Neural Engine
   (sub-second target). Normal Xcode Run-and-test resumes.

So the friction below is **temporary and self-resolving** with Track 3. Do not
build process tooling to paper over it (see "Less is more").

## The process problem we keep hitting

The shutter will not arm in a Debug build, so you cannot record a meal from a plain
Xcode Run.

- The nadir shutter requires a pre-shutter food mask **≤ 750 ms old**
  (`App/CaptureFlowModel.swift` `hasUsablePreShutterMask`, ~L165). This gate is
  correct — it prevents the first-shot `noFoodPixels` race (firing before any mask
  exists).
- In a **Debug** build the stub segmenter runs at `-Onone` and takes **17–21 s per
  cycle** (`event=preshutter.mask.update … latencyMs≈20000`,
  `preshutter.cadence.miss actualMs≈20000`). So the latest mask is older than
  750 ms for ~19 of every 20 s → `canShutter=false` almost continuously. The arming
  window is a sub-second slice once every ~20 s, which is unhittable.
- In an optimised **Release** build the same stub runs ~2 Hz (~500–800 ms/cycle),
  the mask stays inside the 750 ms window, the shutter stays armed, and the
  single-mode meal records (~682–827 ms estimate, confirmed 2026-06-24).

**The tell:** in the logs, `event=blocked … tiltInRange=true distanceCm=… ok
lidarCoveragePercent=… ok … canShutter=false`. Everything green except
`canShutter`, plus `latencyMs` in the tens of thousands → it's a Debug build and
the mask is stale. Test on Release.

This means: **any device test of the capture/shutter flow has to be a Release build
until the real model lands.** That is the process impact — there is currently no
quick Xcode-Run loop for the capture flow.

## Getting a build onto the device — the two paths

### Path A — Xcode Run (Debug)
Tap Run in Xcode, or `xcodebuild -configuration Debug -destination 'id=<udid>'`.
Fine for UI/non-capture work. **Useless for capture testing** (stub too slow, per
above). A plain Release Run from Xcode **crashes** — the stub is Debug-only and the
real model doesn't exist, so the app launches with no segmenter.

### Path B — CLI Release with the stub forced on (what we use to test capture)

**Automated: `make deploy-release-stub`** (tools/deploy_release_stub.sh — does
all five steps below, reverts Package.swift via a trap even on failure, and
prints the build stamp). The manual recipe, for reference:

1. **Force the stub into Release.** In `Package.swift` (~L115) change
   `.define("DEV_STUB_SEGMENTER", .when(configuration: .debug))`
   → `.define("DEV_STUB_SEGMENTER")` (unconditional).
2. **Build Release, signed:**
   ```
   cd MeData
   xcodebuild build -project MeData.xcodeproj -scheme MeData \
     -configuration Release -destination 'id=<udid>' \
     -derivedDataPath /tmp/medata-release -allowProvisioningUpdates
   ```
3. **Install via devicectl:**
   ```
   xcrun devicectl list devices                       # find the udid (look for "connected")
   xcrun devicectl device install app --device <udid> \
     /tmp/medata-release/Build/Products/Release-iphoneos/MeData.app
   ```
   (A first attempt can fail with a transient `CoreDeviceError 4000`
   device-disconnect — just retry.)
4. **Revert `Package.swift`** immediately so the repo stays clean:
   `git checkout Package.swift`. The installed binary keeps the forced stub; the
   tree goes back to Debug-only.
5. **Launch from the HOME SCREEN, not Xcode.** An Xcode Run would reinstall the
   Debug build over it. Confirm you're on the Release build by checking
   `preshutter.mask.update … latencyMs` is **sub-second** with no `cadence.miss`.

devicectl installs survive — you re-run Path B only when the code changes.

### Console filtering
Filter Console.app on the **MeData** process for our `event=…` lines and the ARKit
`ARSession`/`Fig` lines. Subsystems: `ie.medata.app`, `ie.medata.captureflow`.
Benign noise to ignore: `Fig … err=-12710/-17281/-12784`, `AVHapticClient … -4805`,
`Could not resolve material name engine:…`, the CoreMotion.plist permission warning.
The `ARSession … retaining 11–13 ARFrames` warnings are the slow Debug
segmentation backing up the frame consumer; they should clear in Release — if they
persist on a confirmed Release build, that's a real frame-lifetime bug worth chasing.

## Less is more — rejected approach

A `specs/segmenter-export-source-gate/` spec was scaffolded to add compile-time
gating so a Release build could run without the manual stub-forcing. **Rejected and
the branch is being deleted (user, 2026-06-24).** Adding gating machinery to make a
placeholder runnable in Release is the opposite of the less-is-more ethos: it is
throwaway scaffolding around a stub that Track 3 deletes outright. The correct fix
is the real model, not more flags. When in doubt, do not add a gate — ship the
thing the gate was working around.

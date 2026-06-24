# Device build & test loop (and what's next)

How we get a build onto a physical iPhone, why the current process has friction,
and what removes that friction. Written 2026-06-24 after a device session where
no meal would record from an Xcode (Debug) build.

## What is next

**The real ML segmenter model (Track 3) is the next thing to build, and it is the
thing that dissolves every pain described below.** Today the capture pipeline runs
against `StubInferenceEngine` — a placeholder that paints a fixed food region. The
next milestone is to train and integrate the 27-class CoreML segmenter
(`MedataCore/Resources/segmenter.mlpackage`, see `tools/segmenter/export.py`) and
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
This is the working recipe to put optimised, capture-testable code on the device:

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

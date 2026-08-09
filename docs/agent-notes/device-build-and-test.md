# Device build & test loop

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
  - **Gotcha: the totals are grepped from a fixed shared log path**
    (`tee /tmp/medata-swift-test.log`, Makefile ~line 75). Two `make test` runs
    overlapping in time — e.g. in two worktrees — clobber each other's log, so
    the printed totals can belong to the *other* run (observed 2026-08-08: both
    orbit variant runs reported an identical XCTest line down to the timing
    stamp). Pass/fail from the live stream is per-run truth; only the grepped
    summary lines are unreliable under concurrency. Never run two `make test`
    invocations concurrently if the totals matter.
  - **Exit code**: fixed 2026-08-09 — the target sets `pipefail`, so
    `make test` now exits non-zero on a failing suite. Before the fix the exit
    status was tee's (always 0), so any gate that trusted the exit code alone
    proved nothing; a red test survived one such gate on 2026-08-09 and was
    caught only by reading the log's failure markers.
- `make deploy-device` — Debug build + install + launch. Makefile DEFAULTS point at `you` (iPhone 16 Pro, devicectl `6AD781BA-89FF-5A82-A2A1-B5EC9469F465`), the current primary device — no override needed. To target another device, override per invocation: `make deploy-device DEVICE_UDID=<devicectl-id> DEVICE_NAME=<name>` (same overrides for `deploy-release-stub` / `logs-device`; `logs-device` needs sudo for tethered collection). UI/non-capture work only.
- `make deploy-release-stub` — the automated Path B below (capture testing).
- `make logs-device` — pulls the last `LOG_LAST` (default 10m) of device logs
  filtered to `subsystem == "ie.medata.app"`, to stdout and
  `/tmp/medata-device.log`. **Post-hoc only** — macOS has no scriptable live
  stream for an iOS device (`log stream` is host-only, devicectl has no log
  subcommand); live viewing stays in Console.app (recipe below).
- `make spell` — spelling lint.

Default device (Makefile): `you`, iPhone 16 Pro, devicectl `6AD781BA-89FF-5A82-A2A1-B5EC9469F465`, bundle `rtob.MeData`. Note the
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
| Release, plain (`make deploy-release`) | real Core ML model (bundled since 2026-07-05) | **Yes** — the real path; confirm `segmenterSource=coreml_<sha12>` in the launch log |
| Release + forced stub (`make deploy-release-stub`) | stub at ~2 Hz | **Yes** — deterministic stub masks, when the real model's output would confound the test |

The stub emits a mask roughly every ~20 s in Debug, so the sub-second arming
window is unhittable; details and the log tells are in the sections below.

## Pulling app data off the device without sudo (field triage)

`make logs-device` needs sudo (tethered `log collect` requires root). The
outcome store + capture bundles cover most triage WITHOUT logs, no sudo:

```
xcrun devicectl device info files --device 6AD781BA-89FF-5A82-A2A1-B5EC9469F465 \
  --domain-type appDataContainer --domain-identifier rtob.MeData --subdirectory Documents
xcrun devicectl device copy from --device 6AD781BA-89FF-5A82-A2A1-B5EC9469F465 \
  --domain-type appDataContainer --domain-identifier rtob.MeData \
  --source Documents/meals.sqlite --destination meals.sqlite
```

`meals.sqlite` carries `estimation_outcomes` (per-attempt failure JSON +
stage measurements — query with `json_extract`); `Documents/captures/*.fixture`
replays offline. This chain (outcome rows → fixture argmax histograms →
palette/mapping cross-check) diagnosed both the stride bug and
unrecognised-food-estimated-as-residual-sliver without a single re-capture.
Launch (`devicectl device process launch`) fails with `BSErrorCode Locked`
when the phone is locked — install still succeeds; open from the home screen.

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

## The real model shipped (Track 3 — resolved)

**The real ML segmenter shipped 2026-07-05 (`coreml_0295ea61edd9`) and was
superseded 2026-07-06 by the letterbox retrain (`coreml_24e0b022241a`)** — see
`model-production.md`. A plain Release build now bundles the real Core ML model
(`MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage`); `make
deploy-release` is the deploy path. That dissolved the pains this note
predicted it would:

1. **Estimates are real** (uncalibrated β = 1.0, so over-estimating — see the
   model-production note), not painted by the stub's fixed food region.
2. **Plain Release no longer crashes.** Release binds `CoreMLInferenceEngine`
   natively; `make deploy-release-stub` remains only for stub-based capture
   testing.
3. **Speed friction gone on the real path** — the model runs via Core ML, not
   the `-Onone` Debug stub.

The friction sections below are kept as history and because the Debug-stub
slowness still applies to Debug builds; the "temporary and self-resolving"
prediction has come true — do not build process tooling around what remains
(see "Less is more").

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

This means: **any device test of the capture/shutter flow has to be a Release
build** (`make deploy-release` for the real model, `make deploy-release-stub`
for the stub). There is no quick Xcode-Run (Debug) loop for the capture flow —
the Debug stub is still too slow.

## Getting a build onto the device — the two paths

### Path A — Xcode Run (Debug)
Tap Run in Xcode, or `xcodebuild -configuration Debug -destination 'id=<udid>'`.
Fine for UI/non-capture work. **Useless for capture testing** (stub too slow, per
above). A plain Release Run from Xcode used to crash (no segmenter before
2026-07-05); it now runs the real model, but logs `buildStamp=unstamped` —
prefer `make deploy-release` so the stamp is checkable.

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

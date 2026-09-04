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
  - **Concurrency of the totals: fixed 2026-08-13.** The totals are grepped from
    `$(CURDIR)/.build/medata-swift-test.log` (`TEST_LOG` in the Makefile), which
    is per-checkout, so parallel worktree runs no longer share it. Before the
    fix the path was a fixed `/tmp/medata-swift-test.log`: two overlapping
    `make test` runs clobbered each other's log and the printed totals could
    belong to the *other* run (observed 2026-08-08 — both orbit variant runs
    reported an identical XCTest line down to the timing stamp). This mattered
    because `orbit run --variants N --parallel` runs `make test` in several
    worktrees simultaneously by design. Pass/fail from the live stream was
    always per-run truth; only the grepped summary lines were affected.
  - **Exit code**: fixed 2026-08-09 — the target sets `pipefail`, so
    `make test` now exits non-zero on a failing suite. Before the fix the exit
    status was tee's (always 0), so any gate that trusted the exit code alone
    proved nothing; a red test survived one such gate on 2026-08-09 and was
    caught only by reading the log's failure markers.
- `make deploy-device` — Debug build + install + launch. Makefile DEFAULTS point at `you` (iPhone 16 Pro, devicectl `6AD781BA-89FF-5A82-A2A1-B5EC9469F465`), the current primary device — no override needed. To target another device, override per invocation: `make deploy-device DEVICE_UDID=<devicectl-id> DEVICE_NAME=<name>` (same overrides for `deploy-release-stub` / `logs-device`; `logs-device` needs sudo for tethered collection). UI/non-capture work only.
- `make deploy-release-stub` — the automated Path B below (capture testing).
- `make build-product` / `make deploy-product` — the **ProductRelease**
  configuration (ml-feedback-loop Req 9): Release with `FIELD_LOOP` compiled
  out, so the field-note layer is absent at compile time rather than switched
  off at runtime. Both run the product gate (`tools/deploy_product.sh`);
  `build-product` needs no device. Debug and Release BOTH carry `FIELD_LOOP` —
  field is the daily default, matching the always-on capture recorder — so
  this is the only way to build a product-profile binary.
- `make field-notes` — reads the field notes back off the device in seconds
  (notes + the events DB, no capture bundles), where `make field-pull` carries
  the whole backlog and takes minutes to hours. Any Debug or Release build
  carries the note affordance, so this is the fastest way to get a written
  observation off the phone and onto the Mac during a session — including for
  UI work unrelated to captures. See `ml-feedback-loop.md`, "Day-to-day use".
- `make logs-device` — pulls the last `LOG_LAST` (default 10m) of device logs
  filtered to `subsystem == "ie.medata.app"`, to stdout and
  `/tmp/medata-device.log`. **Post-hoc only** — macOS has no scriptable live
  stream for an iOS device (`log stream` is host-only, devicectl has no log
  subcommand); live viewing stays in Console.app (recipe below).
- **Every build declares its profile in the launch line**:
  `event=launch buildStamp=… segmenterSource=… profile=field|product`
  (ml-feedback-loop Req 9.4). `profile=product` on a build you meant to take
  into the field means no note affordance will appear, and vice versa.
- **Log at `.notice`, never `.info`, for anything a device pull must show.**
  `log collect` reads the device's *persisted* store, and on iOS only notice
  and above is persisted — `.info` lives in a memory buffer that the tethered
  collect does not return, and `.debug` is off entirely. The `--info --debug`
  flags on `log show` widen what is *displayed* from the archive; they cannot
  recover what was never written. Verified 2026-08-13: an archive collected
  eight minutes after a launch contained thousands of `com.apple.*` lines from
  inside the MeData process and not one `ie.medata.app` line, because every one
  of ours was `.info`. Apple's own subsystems appear at Info/Debug level in the
  same archive — they carry log configurations we do not, so their presence is
  not evidence that ours would survive.
- Reading the archive needs no root, only the collect does: after one
  `sudo make logs-device`, query `/tmp/medata-device.logarchive` freely with
  `/usr/bin/log show … --predicate …`. Spell out `/usr/bin/log` — `log` is a
  zsh built-in in this shell and swallows the flags with "too many arguments".
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
event=launch buildStamp=<git-sha>[-dirty]-<timestamp> segmenterSource=stub|coreml
```

The Make target prints the same stamp (`DEPLOYED BUILD STAMP: …`) at deploy
time. **Before trusting any captured trail, match the on-device stamp against
the deploy output**, and check `segmenterSource` is what you think you are
testing — days were lost debugging against the stub without realising. A plain
Xcode Run logs `buildStamp=unstamped` (the stamp comes from the
`MEDATA_BUILD_STAMP` build setting via `MeData/Info.plist`, which only the
Make targets set).

`-dirty` sits with the sha it qualifies and means tracked files were modified
when the build was made: the sha names the commit the build was *based on*, not
the tree that was compiled, so that binary cannot be rebuilt from the commit
alone. It is measured with `git diff --quiet HEAD` — tracked files only, and
deliberately not `git status --porcelain`, whose extra sensitivity is to
untracked-but-not-ignored files (a new agent note, a scratch script) that say
nothing about whether the built sources differ from the commit. During
active UI work nearly every hand-driven deploy reads `-dirty`, so its presence
is unremarkable; the information is in its absence. A stamp *without* `-dirty`
is a checkable claim that the binary matches the named commit, which is what an
archived capture round or a tagged attempt needs to be reproducible. A dirty
build is fine for looking at a screen; it is not the build to cite as the
reference for a comparison you intend to repeat.

### `segmenterSource` has two forms — only one names the model

The launch line's `segmenterSource=stub|coreml` is a **compile-time** branch:
`App/App.swift:185` reads `Pipeline.preShutterSourceTag`, which is a
`#if DEV_STUB_SEGMENTER` switch and knows nothing about which `.mlpackage` was
bundled. The 12-hex form `coreml_<modelVersion>` comes from
`PipelineFactory.swift:124` and is stamped onto **captures**
(`MealRecord.segmenterSource`, surfaced in Settings → Estimation log), where
the id is read out of the loaded model's `medata.modelVersion` metadata.

So a launch log proves the stamp and stub-vs-real; it cannot prove *which*
model an install binds. That needs one capture on that install — or, for the
weaker claim, `strings`/`coremltools` on the `.mlpackage` the build compiled.
`myfoodrepo-bridge/tasks-training-and-export.md` task 6 asked for the 12-hex id
in the launch log for months; no build has ever emitted it there.

## Comparing UI attempts on the phone

The whole convention is git branches, git tags and the build stamp. Nothing
reads any of it, no tooling exists for it, and none should be built.

### The name

One tag per attempt: **`<surface>-attempt-N`**. `<surface>` is the screen or
control being tried, not the spec. `N` is only the order the attempts were tried
in — not a ranking, not a version, and no numbering is reserved. Everything stays
v0 until main (pipeline Decision 50).

In use today: `tilt-guide-attempt-1/2`, `insulin-dosing-ui-attempt-1/2/3`
(and their `-on-research`, `-on-research-2` and `-on-research-3` replays), `activity-sheet-attempt-1/2`,
`activity-graph-attempt-1/2`, `dose-schedule-ui-attempt-1/2`.

**Tag on a clean tree.** That is the load-bearing rule. A clean tree makes the
build stamp read `<sha>-<timestamp>` with no `-dirty`, which is what lets a sha
identify an attempt at all — see the build-stamp section above.

### The three shapes, in preference order

**1. Both on `research`, chosen at runtime.** When the variants can coexist in
one binary, merge both and put a developer-phase switch in Settings.
`dose-schedule` does this: Settings → Reminder → Surface flips between the
outstanding-dose card and the repurposed Dose route. One install, no rebuild
between looks, and the comparison is immediate. Prefer this whenever it is
possible — the switch is a handful of lines and it is deleted when the choice is
made.

**2. Both on `research`, one after the other, each tagged.** When the variants
cannot coexist but do not conflict with anything else, commit attempt 1, tag it,
then commit attempt 2 on top and tag that. `research` carries the last one;
earlier attempts are a `git checkout <tag>` away. `activity-events` does this —
`research` shows sheet attempt 2 and graph attempt 2, and attempt 1 of either is
one checkout back.

**3. Off to the side on a branch, nothing merged.** When the variants are
competing designs for the same screen and merging any of them would pre-empt the
choice. `insulin-dosing` is here: three whole App layers for one readout, on
`insulin-dosing-ui-{1,2,3}-on-research`, tagged
`insulin-dosing-ui-attempt-{1,2,3}-on-research` and, after the third replay,
`…-on-research-3` (`ff9d29f` / `e0373bd` / `26af5f9`, all built clean on
`a1618ee`). Nothing merges until a person looks at all three and picks one.
What each attempt actually is: `docs/agent-notes/insulin-dose-ui.md`.

### Getting the surface on screen without a capture

A comparison is only a comparison if every attempt shows the same numbers, and
the post-capture surfaces used to need a fresh plate of food per install. One
DEBUG-only affordance (`a1618ee`) removes that:

- **Settings → Seed demo meal** writes one fixed record — three foods, 56.0 g of
  carbohydrate — through the ordinary `save(_:artefacts:)` path. It appears in
  Records and Trends immediately. Its segmenter source is `demo_seed`, which is
  what keeps its correction-corpus rows separable from real captures.

The second affordance `a1618ee` carried — **Records → a meal → ⋯ → Review**
pushing `MealReviewView` (`MealRoute.review`) — is deleted along with the
overview hop (home-router Decision 16). It is no longer needed for the dose
surfaces: since insulin-dosing Decision 18 every surface recomputes the dose
live from recorded events + settings, so opening the seeded meal from history
(Records → meal → ResultView) proves the readout and its tap-through working
with zero extra navigation.

- **Settings → Review demo meal** saves that same fixed record and then pushes
  `MealReviewView` on it. Added 2026-09-04 for shared-meal-components task 8,
  because a device session found the capture-review line unjudgeable: the
  surface is constructed in exactly ONE place (`CaptureFlowView`'s `.result`
  route), so a build whose estimation refuses or drifts cannot reach it at all.
  This is the only non-capture path onto it. Two things it does not give you:
  with `artefacts: []` there is no photo and no mask outlines, so the surface
  shows the fallback it is specified to show without one (meal-review Req 1.6);
  and `onRecord`/`onRetake`/`onDelete` pop the Settings stack rather than
  driving `CaptureFlowModel`, so the post-capture *wiring* still needs a real
  capture. Everything below the photo — rows, totals, corrected markers,
  serving and scale controls, and correction persistence against a real meal id
  — behaves as it does after a capture.

Neither seed button exists in Release and does not touch MedataCore. Replay
the commit onto an attempt branch the same way any other research change is
replayed — without it, the attempt build has no seed button.

### Deploying each one

```sh
git checkout <tag-or-branch> && make deploy-device    # UI work; Debug is fine
git checkout research                                 # back to the line
```

`make deploy-device` prints `DEPLOYED BUILD STAMP: <sha>-<timestamp>`. Use
`deploy-release` instead if the attempt touches the capture flow, because the
Debug stub cannot arm the shutter (matrix below).

### Which attempt is on the phone right now

The build stamp is the version label, and `git describe` decodes it. Take the
sha from the deploy output, or from `event=launch buildStamp=…` in
`sudo make logs-device`:

```sh
git describe --tags 87443aa      # -> activity-sheet-attempt-1
git describe --tags 34b4d6c      # -> activity-graph-attempt-2-16-g34b4d6c
```

An exact tag name means the installed binary **is** that attempt. A
`<tag>-<n>-g<sha>` answer means it is not — it is `n` commits past the nearest
tag, i.e. an ordinary build. That distinction is the entire versioning story; a
`-dirty` in the stamp voids it, because the sha then names a commit whose content
is not what was compiled.

### Rebasing an attempt onto a moved `research`

Attempts go stale — the three `insulin-dosing` attempts were a month behind and
none of them still built, and a month later the same three were 32 commits
behind again. Rebuild them on the current line, but **never move the
original tag**: it is the record of what that attempt was. Make a new ref and
say so in its name. The `-on-research` suffix above is that, and the naming is
free — any suffix works as long as the original tag stays put.

A replay onto a moved `research` is a merge, not a transcription, and the
merge can be a decision in its own right: attempts 2 and 3 both carried their
own activity surfaces, written before `activity-events` existed, and research
has since merged a different implementation of exactly that. Both replays drop
their own copy and take research's — re-fighting a settled decision inside a UI
attempt makes the comparison about the wrong screen. Say in the commit message
which parts of an attempt did not survive the replay and why.

Deleting a tag once its attempt stops being interesting is fine; `git log` still
holds the commit, and `git switch -c <name> <tag>` still spins a variant out of
one while it exists.

## Debug vs Release stub matrix

| Build | Segmenter | Capture-testable? |
|---|---|---|
| Debug (Xcode Run / `make deploy-device`) | stub at `-Onone`, ~20 s/mask | **No** — mask stale, `canShutter=false` ~19 s of every 20 |
| Release, plain (`make deploy-release`) | real Core ML model (bundled since 2026-07-05) | **Yes** — the real path; the launch log reads a bare `segmenterSource=coreml` |
| Release + forced stub (`make deploy-release-stub`) | stub at ~2 Hz | **Yes** — deterministic stub masks, when the real model's output would confound the test |
| ProductRelease (`make deploy-product`) | real Core ML model | **Yes** — identical estimation path to Release; the only difference is the absent field-note layer |

The stub emits a mask roughly every ~20 s in Debug, so the sub-second arming
window is unhittable; details and the log tells are in the sections below.

### `#if DEBUG` symbols are invisible to the Debug loop

The daily loop is `make deploy-device` (Debug), and Debug compiles every
`#if DEBUG` block, so a helper declared inside one and called from code
*outside* one builds clean all day and fails only at `make deploy-release`:

    error: type 'SettingsView' has no member 'minutesLabel'
    make: *** [deploy-release] Error 65

Error 65 from a deploy target is the compiler, not the device, the model or
devicectl — read the `error:` line above it and ignore the install machinery.
`SettingsView.swift` hit exactly this: `minutesLabel` — a plain formatter used
by the always-compiled Blood-hold rows — was written next to the demo-seeding
helpers inside the file's `#if DEBUG` block (fixed 2026-08-28).

The rule when adding to a file that has a `#if DEBUG` block: a member is
debug-only if and only if **every** caller is. Anything reached from shipping
code goes above the `#if`. Only `make deploy-release` and `make build-product`
can catch a breach, so run one of them before claiming an app change is done.

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

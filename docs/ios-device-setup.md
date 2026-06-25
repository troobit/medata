# Run MeData on an iOS Device

Build, sign, and side-load the MeData iOS shell to a developer-owned iPhone for MVP testing. Written for engineers without prior Swift / Xcode experience.

## Table of contents

- [Run MeData on an iOS Device](#run-medata-on-an-ios-device)
  - [Table of contents](#table-of-contents)
  - [Device support](#device-support)
  - [Prerequisites](#prerequisites)
  - [1. Quick start — committed project](#1-quick-start--committed-project)
  - [2. SPM ↔ Xcode-project boundary (background)](#2-spm--xcode-project-boundary-background)
  - [3. Code signing on a fresh clone](#3-code-signing-on-a-fresh-clone)
  - [4. Info.plist privacy strings](#4-infoplist-privacy-strings)
  - [5. Trust the developer cert on the iPhone](#5-trust-the-developer-cert-on-the-iphone)
  - [6. Useful shortcuts and debug aids](#6-useful-shortcuts-and-debug-aids)
  - [Troubleshooting](#troubleshooting)
  - [Appendix A — Recreate the Xcode project from scratch](#appendix-a--recreate-the-xcode-project-from-scratch)
  - [References](#references)
    - [Xcode](#xcode)
    - [Swift / SwiftUI / ARKit](#swift--swiftui--arkit)
    - [Spec](#spec)

## Device support

The full pipeline relies on [ARKit `sceneDepth`](https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics/scenedepth), which is available **only on iPhones / iPads with a rear-facing LiDAR scanner**. Non-LiDAR devices are supported in **all builds** (Debug and Release): the iOS-shell engine in `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` starts the AR session without `.sceneDepth` when LiDAR is absent and the pipeline falls through to the two-view + ID-1 card path (Req 4.3, §7.4). Confidence is degraded (`noLidarConfidence` flag set on every meal). The spec's hardware floor (Req 1.2 / 1.3) remains the recommendation but is **not** enforced at the engine boundary, so older non-LiDAR devices can run the app provided the ID-1 reference card is present in every shot.

**Spec floor (Req 1.2):** iPhone 13 Pro Max + iOS 26.5. This is the canonical tethered-test device for this codebase and the target for the §16 performance bars. Older LiDAR devices (iPhone 12 Pro / Pro Max, iPhone 13 Pro non-Max) still run but are below spec floor and not part of the active test matrix; iPhone 13 mini is **not supported**.

| Device | LiDAR | Debug | Release | Notes |
|---|---|---|---|---|
| **iPhone 13 Pro Max** | Yes | Yes | Yes | **Spec floor (Req 1.2)** — tethered perf tests target this device (Req 16.7) |
| iPhone 13 Pro | Yes | Yes | Yes | Below spec floor (Req 1.2 raised to Pro Max for Phase 1) but runs fine |
| iPhone 14 Pro / Pro Max | Yes | Yes | Yes | Recommended |
| iPhone 15 Pro / Pro Max | Yes | Yes | Yes | Recommended |
| iPhone 16 Pro / Pro Max | Yes | Yes | Yes | Recommended |
| iPhone 17 Pro / Pro Max | Yes | Yes | Yes | Recommended |
| iPhone 12 Pro / Pro Max | Yes | Yes | Yes | Below spec floor (Req 1.2) but runs |
| iPad Pro (3rd gen, 2018) onwards | Yes | Yes | Yes | Supported |
| iPhone 13 / 14 / 14 Plus / 15 / 15 Plus / 16 / 16 Plus / 17 / Air | No | Yes | Yes | ID-1 reference card required in every shot; two views mandatory (no single-view shortcut). `noLidarConfidence` set on every meal. |
| Pre-iPhone 12 / iOS < 26.5 | n/a | No | No | Unsupported (Req 1.2 — OS floor is iOS 26.5) |

LiDAR availability is the canonical Apple matrix at [Tech Specs — iPhone](https://support.apple.com/en-gb/iphone/compare/). For the algorithmic background, see `specs/research/decision_log.md` Decision 9.

## Prerequisites

| Requirement | Why | Where |
|---|---|---|
| macOS 15.5+ (Sequoia) or macOS 26+ (Tahoe) | Build host for Xcode 26 | [Xcode 26 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes) |
| Xcode 26.0+ (26.5 verified) | iOS 18 / iOS 26 SDK, Swift 6, supports `Package.swift` `swift-tools-version: 5.9` and the project's MainActor-by-default isolation | [Apple Developer downloads](https://developer.apple.com/xcode/) |
| Apple ID (free or paid) | Code signing for personal device install | [developer.apple.com/account](https://developer.apple.com/account) |
| USB-C cable (Lightning for iPhone 13/14 non-Pro) | Wired install — faster and more reliable than wireless debugging | — |
| iPhone with iOS 26.5+ (iPhone 13 Pro Max for spec floor) | Runtime target — Req 1.2 OS + hardware floor | [Compatible iPhone models](https://support.apple.com/en-gb/guide/iphone/iphe3fa5df43/ios) |

A paid Apple Developer Program membership ($99/yr) is **not required** for installing on your own devices. A free Apple ID gives a 7-day developer cert that re-signs on the next Xcode build.

## 1. Quick start — committed project

The repo ships a working Xcode project at `MeData/MeData.xcodeproj` (proper-case `MeData/` directory at the repo root). It references the SPM `Package.swift` at the repo root via the relative path `../../medata` (resolves correctly as long as your local clone is in a directory named `medata`). It also references the SwiftUI views at `App/*.swift` via `../App/*.swift`. The two things that **cannot** be portable are the `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER` — both are Apple-account-specific.

| Step | Action |
|---|---|
| 1.1 | `git clone <repo>` and `cd` into it. The clone must land in a directory called `medata` (the default for `git clone <medata-url>`). |
| 1.2 | Open `MeData/MeData.xcodeproj` in Xcode (`open MeData/MeData.xcodeproj` from the shell, or double-click in Finder). |
| 1.3 | First-build packages resolve automatically — wait ~30–60 s while Xcode fetches `swift-protobuf`, `GRDB.swift`, and `ZIPFoundation` from GitHub. |
| 1.4 | Click the blue **MeData** project icon → **MeData** target → **Signing & Capabilities** tab. **Change `Team`** to your personal team (or click **Add an Account…** and sign in with your Apple ID first). |
| 1.5 | Same screen → **change `Bundle Identifier`** from `rtob.MeData` to something unique to your Apple ID, e.g. `com.<your-handle>.MeData`. |
| 1.6 | Plug in your iPhone, trust the Mac when prompted, pick the phone in Xcode's destination menu (top toolbar). |
| 1.7 | **⌘R** to build and run. First install triggers an "Untrusted Developer" dialog on the phone — see §5 below to clear it. After that, ⌘R again. |

You should see the capture flow: navigation title **"Capture"**, the AR camera preview, live tilt / distance / LiDAR-coverage indicators, and the shutter button. On first launch the OS will prompt for camera and motion permissions; grant both. On a non-LiDAR device the coverage indicator stays at 0% and the path hint locks to the two-view + ID-1 card route — place a credit-card-sized ID-1 reference card in shot and capture both nadir and oblique views when prompted.

Reference: [Adding capabilities to your app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app) · [Distributing your app to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).

## 2. SPM ↔ Xcode-project boundary (background)

The pipeline lives in the SPM at the repo root (`Package.swift`). The iOS app lives in `MeData/MeData.xcodeproj`, which depends on the SPM as a local package. This split is deliberate: the algorithm code is testable on macOS without an iPhone, and reusable from a future Android harness.

The SPM exposes one library product, `MedataCore`, which is the `Pipeline` target. `Pipeline` re-exports `Persistence`, `PortableContracts`, `Segmentation`, and `SupportPlane` via `@_exported import` so the app only needs `import Pipeline` to get `MealRecord`, `EstimationFailure`, the `Pb*` proto types, and those modules' public surfaces. Anything *not* re-exported (e.g. `CaptureKit`, `Foods`) requires the app to add the matching local package product first.

The SPM also defines a macOS-only `HarnessCLI` executable and a `HarnessCore` target (used only by `HarnessCLI` and the offline tests). Neither is exposed as a library *product*, so neither appears when adding the package to the app, and the shipping app links zero harness code (the `HARNESS_ENABLED` flag is defined only on the harness targets — see `Package.swift`).

## 3. Code signing on a fresh clone

If §1.4–1.5 didn't already cover everything:

| Step | Action |
|---|---|
| 3.1 | Project editor → target → **Signing & Capabilities** tab. |
| 3.2 | **Automatically manage signing** stays ticked. |
| 3.3 | **Team:** your personal Apple ID team. **Add an Account…** if it's empty. |
| 3.4 | **Bundle Identifier:** `com.<your-handle>.MeData` or similar. Globally unique on the App Store, unique-per-Apple-ID for free-tier sideloading. |
| 3.5 | If Xcode shows *"Failed to register bundle identifier"*, append a digit to the bundle id and retry. |

Free Apple-ID signing works for personal devices. The cert lasts 7 days; the next ⌘R re-signs.

## 4. Info.plist privacy strings

The project uses Xcode's generated Info.plist (`GENERATE_INFOPLIST_FILE = YES`); the
privacy strings live in the target build settings as `INFOPLIST_KEY_*` entries in
`MeData/MeData.xcodeproj/project.pbxproj`:

| Key | Value | Reference |
|---|---|---|
| `INFOPLIST_KEY_NSCameraUsageDescription` | "MeData uses the camera to capture a photo of your meal so it can estimate the carbohydrates on your plate." | [docs](https://developer.apple.com/documentation/bundleresources/information-property-list/nscamerausagedescription) |
| `INFOPLIST_KEY_NSMotionUsageDescription` | "MeData uses motion data to show how level the camera is while you capture your meal." | [docs](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmotionusagedescription) |
| `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone` | `UIInterfaceOrientationPortrait` (portrait-only per `specs/ui/iphone-experience/`) | [docs](https://developer.apple.com/documentation/bundleresources/information-property-list/uisupportedinterfaceorientations) |
| `INFOPLIST_KEY_LSApplicationCategoryType` | `public.app-category.medical` | [docs](https://developer.apple.com/documentation/bundleresources/information-property-list/lsapplicationcategorytype) |

To change a value, edit the target's **Build Settings** → search "INFOPLIST_KEY_" — Xcode
exposes each `INFOPLIST_KEY_*` as a first-class setting. Do not add a hand-written
`Info.plist` file alongside; the generated route is the source of truth.

Not yet configured (add when the relevant work lands):

- `BGTaskSchedulerPermittedIdentifiers` — needed once `RetentionScheduler` is registered
  for background sweeps. One array entry: `<your.bundle.id>.retention`.
- `UIRequiredDeviceCapabilities` containing `arkit` — restricts App Store delivery to
  ARKit-capable devices. **Do not** add a LiDAR key — it does not exist; the engine
  handles non-LiDAR devices at runtime via the two-view + ID-1 card path.

Reference: [Information Property List](https://developer.apple.com/documentation/bundleresources/information-property-list) · [Background Tasks framework](https://developer.apple.com/documentation/backgroundtasks).

## 5. Trust the developer cert on the iPhone

First-time installs from a personal team are quarantined until the user trusts the certificate.

| Step | On the iPhone |
|---|---|
| 5.1 | **Settings → General → VPN & Device Management** |
| 5.2 | Under *Developer App*, tap your Apple ID. |
| 5.3 | Tap **Trust "<your apple id>"** → confirm in the modal. |

Reference: [Install a configuration profile on iPhone](https://support.apple.com/en-gb/guide/iphone/iph6c493b19/ios).

## 6. Useful shortcuts and debug aids

To see the app's console output, open the debug area: **View → Debug Area → Show Debug
Area** (⇧⌘Y). The `Pipeline` target emits OSSignpost intervals around each stage in Debug
builds (subsystem `ie.medata.pipeline`, category `Stages`) — attach Instruments and pick
the **OSSignpost** template to inspect stage timings.

Both Debug and Release schemes run on non-LiDAR devices — the iOS-shell hardware-floor
refusal in `ARKitCaptureEngine` has been removed; non-LiDAR sessions degrade to the
two-view + ID-1 card path with `noLidarConfidence` set on every meal record.
**Product → Scheme → Edit Scheme…** to inspect.

### XCUITest harness

The capture flow is AR-gated and ARKit does not run on the simulator. To exercise the
flow without a real camera, launch with `-uitest` (and optionally `-uitestPipeline
refuse|stall`) — `App.swift` activates a `#if DEBUG` harness that injects a gated
`CaptureEngine`, a stub `PipelineEstimator`, and an interruption `AsyncStream`. Hidden
controls along the leading edge drive the model's commands; query them by accessibility
identifier (`uitest.driveToReady`, `uitest.releaseCapture`, etc.). See
[`docs/agent-notes/ui-capture-flow.md`](agent-notes/ui-capture-flow.md) for the full list.

Frequently-needed shortcuts:

| Shortcut | What |
|---|---|
| <kbd>⌘</kbd><kbd>R</kbd> | Build & run |
| <kbd>⌘</kbd><kbd>B</kbd> | Build without running |
| <kbd>⌘</kbd><kbd>.</kbd> | Stop the running app |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>K</kbd> | Clean Build Folder |
| <kbd>⇧</kbd><kbd>⌘</kbd><kbd>Y</kbd> | Toggle Debug Area |
| <kbd>⌃</kbd><kbd>0</kbd> | Open the destination picker |

Reference: [Running your app in Simulator or on a device](https://developer.apple.com/documentation/xcode/running-your-app-in-the-simulator-or-on-a-device).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Untrusted Developer` modal on first launch | Cert not yet trusted on device | [§5](#5-trust-the-developer-cert-on-the-iphone) |
| `Failed to register bundle identifier` in Xcode | Bundle ID collision in Apple's dev-portal cache | Append a digit to the bundle id and retry; or wait a few minutes |
| `Could not launch "MeData"` after 7 days | Free-tier cert expired | Rebuild (⌘R) — Xcode re-signs automatically |
| Signing-related red icon on **Signing & Capabilities** after fresh clone | `DEVELOPMENT_TEAM` baked into the committed `.pbxproj` is the original committer's team | Change **Team** + **Bundle Identifier** ([§1.4 / §1.5](#1-quick-start--committed-project)) |
| `No such module 'Pipeline'` after fresh clone | SPM cache stale or repo cloned into a directory not named `medata` (breaks the `../../medata` relative path) | **File → Packages → Reset Package Caches**; if that fails, re-clone into a directory named `medata` |
| `Cannot find type 'MealRecord' in scope` / `Cannot find 'EstimationFailure' in scope` | `Pipeline` is missing the `@_exported import Persistence` / `@_exported import PortableContracts` lines in `MedataCore/Sources/Pipeline/Pipeline.swift` (or they've been reverted) | Restore the `@_exported` declarations; rebuild |
| `Missing import of defining module 'Combine'` on `ObservableObject` / `@Published` / `@StateObject` | Xcode 16+ no longer auto-imports `Combine` via SwiftUI | Add `import Combine` at the top of the offending file |
| `Type 'MealRecord' does not conform to protocol 'Hashable'` | `MealRecord` in `Persistence/MealRecord.swift` is `Equatable` only | Add `Hashable` to its conformance list — synthesised because every field is Hashable |
| App crashes immediately on first sensor access | `INFOPLIST_KEY_NSCameraUsageDescription` / `INFOPLIST_KEY_NSMotionUsageDescription` removed from build settings | [§4](#4-infoplist-privacy-strings) — restore the keys in **Build Settings** |
| ARKit session never returns frames on a non-LiDAR iPhone | `.sceneDepth` was requested on a device that doesn't support it (stale build cache) | Clean Build Folder (⇧⌘K) and rebuild — the current engine only inserts `.sceneDepth` when `ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)` is true |
| Build error: `Sandbox: bash deny(1) file-write-create` for SPM build cache | Fresh checkout permissions | Clean Build Folder (⇧⌘K), retry |
| `App installation failed: Unable to install MeData` | Provisioning profile mismatch | Toggle **Automatically manage signing** off and on, or delete `~/Library/MobileDevice/Provisioning\ Profiles/` and rebuild |
| Capture works but every meal carries `noLidarConfidence` | Expected on non-LiDAR devices (Req 7.4) | Use a LiDAR device for spec-compliant captures |
| `BGTaskScheduler` errors in console on launch | `BGTaskSchedulerPermittedIdentifiers` missing or doesn't match the identifier registered in `RetentionScheduler` | [§4](#4-infoplist-privacy-strings) — add when wiring up retention |

## Appendix A — Recreate the Xcode project from scratch

Only needed if the committed `MeData/MeData.xcodeproj` is somehow broken beyond repair, or if you want to understand how it was assembled. Xcode 26.5 is the verified version.

| Step | Action |
|---|---|
| A.1 | Move/delete the existing `MeData/` directory at the repo root. |
| A.2 | Xcode → **File → New → Project…** (⇧⌘N). |
| A.3 | **iOS → App → Next**. Product Name: `MeData`. Interface: **SwiftUI**. Language: **Swift**. Storage: **None**. Testing System: **None**. Untick *Use Core Data*. |
| A.4 | Save inside the repo root. Xcode wraps the project in a folder named after the product → `<repo-root>/MeData/MeData.xcodeproj` plus a sibling `<repo-root>/MeData/MeData/` sources folder. Untick *Create Git repository* (the repo already exists). |
| A.5 | Project editor → target → **Signing & Capabilities** → tick **Automatically manage signing**, pick your **Team**, set **Bundle Identifier**. |
| A.6 | Project editor → target → **General** → **Minimum Deployments → iPhone**: set to **26.5** (Req 1.2 OS floor). |
| A.7 | **File → Add Package Dependencies… → Add Local…** and pick the repo root (the folder containing `Package.swift`). The dialog lists only the `MedataCore` library product (`HarnessCore` is an internal target, not a product, so it does not appear). Tick **MedataCore**. Ensure the **Add to Target** column shows **MeData**. Click **Add Package**. |
| A.8 | **File → Add Files to "MeData"…** → navigate to the repo's `App/` folder → select **all `*.swift` files** in it (the committed project references each `App/*.swift` individually via `../App/…`, so every Swift source must be added — do not add `README.md`). **Uncheck "Copy items if needed"** so they stay in `App/` and aren't duplicated. Tick **Add to targets: MeData**. Click **Add**. Note: Xcode 16+ may show the added files flat in the Project navigator rather than under a virtual `App/` group — they're still in the target. |
| A.9 | In the Project navigator, under `MeData/MeData/`, right-click and delete the auto-generated `MeDataApp.swift` and `ContentView.swift`. They conflict with `App/App.swift`'s `@main` declaration. Keep `Assets.xcassets`. |
| A.10 | ⌘B. Build should succeed. |
| A.11 | Connect iPhone, ⌘R to run. |

Reference: [Creating an Xcode project for an app](https://developer.apple.com/documentation/xcode/creating-an-xcode-project-for-an-app) · [Adding package dependencies to your app](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) · [Managing files and folders in your Xcode project](https://developer.apple.com/documentation/xcode/managing-files-and-folders-in-your-xcode-project).

## References

### Xcode

- [Xcode documentation root](https://developer.apple.com/documentation/xcode)
- [Creating an Xcode project for an app](https://developer.apple.com/documentation/xcode/creating-an-xcode-project-for-an-app)
- [Adding package dependencies to your app](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app)
- [Adding capabilities to your app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app)
- [Distributing your app to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
- [Running your app in Simulator or on a device](https://developer.apple.com/documentation/xcode/running-your-app-in-the-simulator-or-on-a-device)
- [Managing files and folders in your Xcode project](https://developer.apple.com/documentation/xcode/managing-files-and-folders-in-your-xcode-project)
- [Xcode 16 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes/)

### Swift / SwiftUI / ARKit

- [Swift documentation root](https://developer.apple.com/documentation/swift/)
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [Swift Packages](https://developer.apple.com/documentation/swift_packages)
- [ARKit](https://developer.apple.com/documentation/arkit)
- [`ARWorldTrackingConfiguration`](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration)
- [`ARFrameSemantics.sceneDepth`](https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics/scenedepth)
- [Background Tasks](https://developer.apple.com/documentation/backgroundtasks)

### Spec

| Topic | Location |
|---|---|
| LiDAR hardware floor (spec-level) | `specs/research/requirements.md` §1.2, §1.3 |
| Card-only support-plane recovery | `specs/research/requirements.md` §4.3 |
| Metric scale resolver (`noLidarConfidence`) | `specs/research/requirements.md` §7.4, §7.5 |
| Two-view-without-LiDAR algorithmic background | `specs/research/decision_log.md` Decision 9 |
| iOS-shell capture engine (LiDAR opt-in, not gated) | `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` |

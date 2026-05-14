# Run MeData on an iOS Device

Build, sign, and side-load the MeData iOS shell to a developer-owned iPhone for MVP testing. Written for engineers without prior Swift / Xcode experience.

## Table of contents

- [Device support](#device-support)
- [Prerequisites](#prerequisites)
- [1. Create the Xcode project](#1-create-the-xcode-project)
- [2. Wire up the local Swift Package](#2-wire-up-the-local-swift-package)
- [3. Add Info.plist privacy strings](#3-add-infoplist-privacy-strings)
- [4. Configure code signing](#4-configure-code-signing)
- [5. Trust the developer cert on the iPhone](#5-trust-the-developer-cert-on-the-iphone)
- [6. Build and run on the device](#6-build-and-run-on-the-device)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Device support

The full pipeline relies on [ARKit `sceneDepth`](https://developer.apple.com/documentation/arkit/arconfiguration/framesemantics/scenedepth), which is available **only on iPhones / iPads with a rear-facing LiDAR scanner**. Non-LiDAR devices (e.g. iPhone 13 mini) are supported in **DEBUG builds only**: the iOS-shell guard in `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift:34` is wrapped in `#if !DEBUG`, so dev builds fall through to the two-view + ID-1 card path (Req 4.3, §7.4). Confidence is degraded (`noLidarConfidence` flag set on every meal) and the spec's release-mode hardware floor (Req 1.2 / 1.3) is intentionally skipped.

| Device | LiDAR | DEBUG | RELEASE | Notes |
|---|---|---|---|---|
| iPhone 12 Pro / Pro Max | Yes | Yes | Yes | Spec hardware floor (Req 1.2) |
| iPhone 13 Pro / Pro Max | Yes | Yes | Yes | Recommended |
| iPhone 14 Pro / Pro Max | Yes | Yes | Yes | Recommended |
| iPhone 15 Pro / Pro Max | Yes | Yes | Yes | Recommended |
| iPhone 16 Pro / Pro Max | Yes | Yes | Yes | Recommended |
| iPad Pro (3rd gen, 2018) onwards | Yes | Yes | Yes | Supported |
| **iPhone 13 mini** | **No** | **Yes** (UI + card-only capture) | **No** (refuses to start) | ID-1 reference card required in every shot; two views mandatory (no single-view shortcut) |
| iPhone 13 / 14 / 14 Plus / 15 / 15 Plus / 16 / 16 Plus | No | Yes (same caveats) | No | — |
| Pre-iPhone 12 / iOS < 17 | n/a | No | No | Unsupported (Req 1.2) |

LiDAR availability is the canonical Apple matrix at [Tech Specs — iPhone](https://support.apple.com/en-gb/iphone/compare/). For the algorithmic background, see `specs/research/decision_log.md` Decision 9.

## Prerequisites

| Requirement | Why | Where |
|---|---|---|
| macOS 14.5+ (Sonoma) or 15+ (Sequoia) | Build host for Xcode 16 | [Xcode 16 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-16-release-notes/) |
| Xcode 16.0+ | iOS 17+ SDK, Swift 5.9+, supports `Package.swift` `swift-tools-version: 5.9` | [Apple Developer downloads](https://developer.apple.com/xcode/) |
| Apple ID (free or paid) | Code signing for personal device install | [developer.apple.com/account](https://developer.apple.com/account) |
| Lightning or USB-C cable | Wired install — faster, more reliable than wireless debugging | — |
| iPhone with iOS 17.0+ | Runtime target | [Compatible iPhone models](https://support.apple.com/en-gb/guide/iphone/iphe3fa5df43/ios) |

A paid Apple Developer Program membership ($99/yr) is **not required** for installing on your own devices. A free Apple ID gives a 7-day developer cert that re-signs on the next Xcode build.

## 1. Create the Xcode project

The repo ships only `App/*.swift` and the SPM `Package.swift`. The `.xcodeproj` is created locally and is **not committed** (treat it like a local virtualenv).

| Step | Action | Shortcut |
|---|---|---|
| 1.1 | Open Xcode → **File → New → Project…** | <kbd>⇧</kbd><kbd>⌘</kbd><kbd>N</kbd> |
| 1.2 | Choose **iOS → App** → **Next** | — |
| 1.3 | Product Name: `MeData`. Interface: **SwiftUI**. Language: **Swift**. Storage: **None**. Untick *Include Tests*. | — |
| 1.4 | Save inside the repo root (`/Users/r/repos/medata-orbit-0/`); name it `MeData.xcodeproj`. Untick *Create Git repository* (the repo already exists). | — |
| 1.5 | In the Project navigator (<kbd>⌘</kbd><kbd>1</kbd>) delete the auto-generated `MeDataApp.swift` and `ContentView.swift` (right-click → **Delete** → **Move to Trash**). Keep `Assets.xcassets` for the app icon. | <kbd>⌫</kbd> |
| 1.6 | Drag the four files from `App/` (`App.swift`, `CaptureFlowView.swift`, `ResultView.swift`, `SettingsView.swift`) into the Project navigator. In the prompt: **Create groups** (not folder references), tick **Add to target: MeData**. | — |

Reference: [Creating an Xcode project for an app](https://developer.apple.com/documentation/xcode/creating-an-xcode-project-for-an-app) · [Managing files and folders in your Xcode project](https://developer.apple.com/documentation/xcode/managing-files-and-folders-in-your-xcode-project).

## 2. Wire up the local Swift Package

The pipeline lives in `Package.swift` at the repo root. The iOS app target imports `Pipeline` only (per `App/README.md`).

| Step | Action |
|---|---|
| 2.1 | **File → Add Package Dependencies…** |
| 2.2 | In the dialog, click **Add Local…** and choose the repo root (`/Users/r/repos/medata-orbit-0/`). |
| 2.3 | Tick **Pipeline**. Click **Add Package**. |
| 2.4 | Verify in the Project editor: target `MeData` → **General** → *Frameworks, Libraries, and Embedded Content* lists `Pipeline`. |

Reference: [Adding package dependencies to your app](https://developer.apple.com/documentation/xcode/adding-package-dependencies-to-your-app) · [Swift Packages overview](https://developer.apple.com/documentation/swift_packages).

## 3. Add Info.plist privacy strings

ARKit, Core Motion, and `BackgroundTasks` all require declared usage strings. Without them iOS terminates the app on first sensor access.

In the Project editor (<kbd>⌘</kbd><kbd>1</kbd>, select the target, **Info** tab) add the following keys:

| Key | Type | Sample value (edit to taste) | Reference |
|---|---|---|---|
| `NSCameraUsageDescription` | String | `MeData uses the camera to photograph your meal for carbohydrate estimation.` | [docs](https://developer.apple.com/documentation/bundleresources/information-property-list/nscamerausagedescription) |
| `NSMotionUsageDescription` | String | `MeData uses motion sensors to keep the camera level during capture.` | [docs](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmotionusagedescription) |
| `BGTaskSchedulerPermittedIdentifiers` | Array of String | One entry: `<your.bundle.id>.retention` | [docs](https://developer.apple.com/documentation/bundleresources/information-property-list/bgtaskschedulerpermittedidentifiers) |
| `UIRequiredDeviceCapabilities` (release builds only) | Array of String | Add `arkit`. **Do not** add a LiDAR key — it does not exist; the runtime guard in `ARKitCaptureEngine` is the source of truth. | [docs](https://developer.apple.com/documentation/bundleresources/information-property-list/uirequireddevicecapabilities) |

Pick a bundle prefix once and reuse it everywhere. Suggested: `com.<your-handle>.medata`.

Reference: [Information Property List](https://developer.apple.com/documentation/bundleresources/information-property-list) · [Background Tasks framework](https://developer.apple.com/documentation/backgroundtasks).

## 4. Configure code signing

Free Apple-ID signing works for personal devices. The cert lasts 7 days; rebuild from Xcode to re-sign.

| Step | Action |
|---|---|
| 4.1 | Project editor (<kbd>⌘</kbd><kbd>1</kbd>, select target) → **Signing & Capabilities** |
| 4.2 | Tick **Automatically manage signing** |
| 4.3 | **Team:** choose your personal team. If empty: **Add an Account…**, sign in with your Apple ID, return to the project. |
| 4.4 | **Bundle Identifier:** `com.<your-handle>.medata`. Globally unique on the App Store, but free-tier sideloading only needs unique-per-Apple-ID. |
| 4.5 | If Xcode shows *"Failed to register bundle identifier"*, change the bundle ID slightly (append a digit) and retry. |

Reference: [Distributing your app to registered devices](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices) · [Adding capabilities to your app](https://developer.apple.com/documentation/xcode/adding-capabilities-to-your-app).

## 5. Trust the developer cert on the iPhone

First-time installs from a personal team are quarantined until the user trusts the certificate.

| Step | On the iPhone |
|---|---|
| 5.1 | **Settings → General → VPN & Device Management** |
| 5.2 | Under *Developer App*, tap your Apple ID. |
| 5.3 | Tap **Trust "<your apple id>"** → confirm in the modal. |

Reference: [Install a configuration profile on iPhone](https://support.apple.com/en-gb/guide/iphone/iph6c493b19/ios).

## 6. Build and run on the device

| Step | Action | Shortcut |
|---|---|---|
| 6.1 | Plug the iPhone into the Mac. Unlock the phone, tap **Trust** when iOS prompts. | — |
| 6.2 | Toggle the run-destination menu in Xcode's top toolbar; pick the device (not a simulator). | <kbd>⌃</kbd><kbd>0</kbd> |
| 6.3 | Confirm the **Debug** scheme is active (default). Release builds enforce Req 1.3 and refuse to start the capture flow on non-LiDAR devices. **Product → Scheme → Edit Scheme…** to inspect. | <kbd>⌘</kbd><kbd><</kbd> |
| 6.4 | Build & run. | <kbd>⌘</kbd><kbd>R</kbd> |
| 6.5 | First launch: grant camera + motion permissions. | — |
| 6.6 | Stop the session. | <kbd>⌘</kbd><kbd>.</kbd> |

Reference: [Running your app in Simulator or on a device](https://developer.apple.com/documentation/xcode/running-your-app-in-the-simulator-or-on-a-device).

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `Untrusted Developer` modal on first launch | Cert not yet trusted on device | [Step 5](#5-trust-the-developer-cert-on-the-iphone) |
| `Failed to register bundle identifier` in Xcode | Bundle ID collision in Apple's dev-portal cache | Append a digit to bundle ID; or wait a few minutes |
| `Could not launch "MeData"` after 7 days | Free-tier cert expired | Rebuild (<kbd>⌘</kbd><kbd>R</kbd>) — Xcode re-signs automatically |
| App crashes immediately on first sensor access | Missing `NSCameraUsageDescription` / `NSMotionUsageDescription` | [Step 3](#3-add-infoplist-privacy-strings) |
| `CaptureError.lidarUnavailable` thrown on capture | Release build on a non-LiDAR device | Switch to the Debug scheme (Step 6.3); see [Device support](#device-support) |
| ARKit session never returns frames on iPhone 13 mini | `.sceneDepth` was requested on a non-LiDAR device (stale build cache) | Clean (<kbd>⇧</kbd><kbd>⌘</kbd><kbd>K</kbd>) and rebuild |
| Build error: `No such module 'Pipeline'` | Local SPM not added or product not linked | [Step 2](#2-wire-up-the-local-swift-package); check **General → Frameworks, Libraries, and Embedded Content** |
| Build error: `Sandbox: bash deny(1) file-write-create` for SPM build cache | Fresh checkout permissions | Clean Build Folder (<kbd>⇧</kbd><kbd>⌘</kbd><kbd>K</kbd>), retry |
| `App installation failed: Unable to install MeData` | Provisioning profile mismatch | Toggle **Automatically manage signing** off and on, or delete `~/Library/MobileDevice/Provisioning\ Profiles/` and rebuild |
| Capture works but every meal carries `noLidarConfidence` | Expected on non-LiDAR devices (Req 7.4) | Use a LiDAR device for spec-compliant captures |
| `BGTaskScheduler` errors in console on launch | `BGTaskSchedulerPermittedIdentifiers` missing or doesn't match the identifier registered in `RetentionScheduler` | [Step 3](#3-add-infoplist-privacy-strings) |

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
| LiDAR hardware floor | `specs/research/requirements.md` §1.2, §1.3 |
| Card-only support-plane recovery | `specs/research/requirements.md` §4.3 |
| Metric scale resolver (`noLidarConfidence`) | `specs/research/requirements.md` §7.4, §7.5 |
| Two-view-without-LiDAR algorithmic background | `specs/research/decision_log.md` Decision 9 |
| iOS-shell `#if DEBUG` LiDAR-guard relaxation | `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift:34` |

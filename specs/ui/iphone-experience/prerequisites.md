# Prerequisites for UI

These tasks require manual configuration in Xcode (or Apple Developer portal) that the coding agent cannot perform reliably without UI access. Complete each at the noted point in the implementation timeline.

## Before starting (one-time)

- [ ] **Set personal Team and Bundle Identifier in `MeData/MeData.xcodeproj`.** After cloning, open the project, select the `MeData` target → **Signing & Capabilities** tab → change **Team** to your personal Apple ID team and **Bundle Identifier** to e.g. `com.<your-handle>.MeData`. Without this, build will fail with a code-signing error. See `docs/ios-device-setup.md` §1 for full walkthrough.
- [ ] **Confirm `MedataCore` SPM is wired into the `MeData` target.** Project navigator → blue project icon → `MeData` target → **General** → **Frameworks, Libraries, and Embedded Content** should list `MedataCore`. If empty, **File → Add Package Dependencies → Add Local** → pick repo root.

## During implementation

- [ ] **Add new `App/*.swift` source files to the `MeData` target** as tasks 5–24 in `tasks.md` create them. Drag each new file into Xcode's Project navigator with **Add to targets: MeData** ticked. (Direct `project.pbxproj` editing is possible but fragile across Xcode-side modifications; this step blocks tasks once each new source file lands and needs to build into the iOS app.)
- [ ] **Set Info.plist keys** in the `MeData` target → **Info** tab → **Custom iOS Target Properties** (or directly via `INFOPLIST_KEY_*` build settings). Required keys, covers requirements §1.5, §13.1, §13.2, §16.2:
  - `NSCameraUsageDescription` (String): `MeData uses the camera to photograph your meal for carbohydrate estimation.`
  - `NSMotionUsageDescription` (String): `MeData uses motion sensors to keep the camera level during capture.`
  - `UIRequiredDeviceCapabilities` (Array of String): `[arkit]`
  - `UISupportedInterfaceOrientations` (Array of String): `[UIInterfaceOrientationPortrait]` (iPhone)
- [ ] **Add `AccentColor` to `Assets.xcassets`** with value `#63ff00`. Asset Catalog editor → AccentColor entry → set Any/Light/Dark appearance values. Required by task 5 / requirement §15.1. (Alternative: the `.tint(.medataAccent)` in `App.swift` from task 24 sets it programmatically; the asset-catalog entry is what Xcode previews use.)

## Before testing on device

- [ ] **Trust the developer cert on the iPhone** the first time a build is installed. Settings → General → VPN & Device Management → tap your Apple ID under "Developer App" → **Trust**. One-time per cert per device.
- [ ] **Grant camera + motion permissions on first launch.** When the system dialog appears for each, tap **Allow**. Denial paths are tested by tasks 12 and 26 but you need to grant once to exercise the success paths.

## Out of band — sibling specs (referenced by tasks here but not blocking)

- **Core ML segmenter weights bundling** — deferred to a separate smolspec. Without `MedataCore/Resources/segmenter.mlpackage/`, `Pipeline.estimate(_:)` will throw at segmentation stage. Test seam (`PipelineEstimator` mock in task 12) lets unit tests run without it; on-device end-to-end work requires the weights bundled.
- **Pipeline cancellation contract** — deferred to a sibling spec per `decision_log.md` Decision 12. Until landed, requirement §8.3 is enforced best-effort (UI state only; persistence may retain ghost meals from cancelled estimations).

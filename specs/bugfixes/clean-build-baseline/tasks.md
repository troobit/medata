---
references:
    - specs/bugfixes/clean-build-baseline/smolspec.md
    - specs/bugfixes/clean-build-baseline/decision_log.md
---
# Clean Build Baseline Tasks

- [x] 1. iPhone-only device family eliminates iPad orientation and icon warnings <!-- id:tuly0qn -->
  - **Outcome:** MeData app target ships as iPhone-only. The orientation validator warning and the two App Icon validator warnings (76x76@2x, 83.5x83.5@2x) are gone.
  - **Approach:** in `MeData/MeData.xcodeproj/project.pbxproj`, change `TARGETED_DEVICE_FAMILY = "1,2";` to `TARGETED_DEVICE_FAMILY = "1";` in BOTH the Debug and Release build-configuration blocks of the MeData app target (currently lines ~394 and ~432). Leave the now-dead `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` key untouched per smolspec Out of Scope.
  - **Verification:** build the Debug configuration; the orientation warning and both AppIcon warnings no longer appear in the output.
  - **References:** smolspec.md, decision_log.md (Decision 1).

- [x] 2. `defaultCaptureModeReader` is `nonisolated` and the file-scope comment explains why <!-- id:tuly0qo -->
  - **Outcome:** Both Swift 6 diagnostics on `App/CaptureFlowModel.swift` (the `@Sendable`-on-MainActor-isolated-function error and the MainActor-loss-on-closure-conversion error at the `CaptureFlowModel.init` default-arg site) no longer occur. The free function `defaultCaptureModeReader` is callable from any context. The explanatory comment immediately above the function explains why `nonisolated` is required (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` inheritance) and why the UserDefaults read is thread-safe.
  - **Approach:** in `App/CaptureFlowModel.swift`, replace `@Sendable` above `defaultCaptureModeReader()` with `nonisolated`. Update the preceding multi-line comment (currently lines 10–12) to reflect the new declaration and rationale.
  - **Verification:** build the Debug configuration; neither diagnostic appears. Confirm `CaptureFlowModel.init` still compiles and the default-arg closure conversion works (no call-site changes anywhere).
  - **References:** smolspec.md, decision_log.md (Decision 2).

- [x] 3. `MealRow.loadThumbnail` uses the connected window scene instead of `UIScreen.main` <!-- id:tuly0qp -->
  - **Outcome:** The `UIScreen.main` deprecation warning on `App/MealRow.swift:123` is gone. Meal thumbnails continue to render at the same target size as before once a scene is active, and at a 393 pt fallback width during pre-scene early launch.
  - **Approach:** in `MealRow.loadThumbnail`, replace the `MainActor.run { UIScreen.main.bounds.width - 32 }` block with the scene-based read documented in smolspec.md Implementation Approach: `UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.width ?? 393` (then subtract 32). Preserve the surrounding `MainActor.run`, the `- 32` padding subtraction, and the call to `MealRowLayout.thumbnailTargetSize(rowWidth:)`.
  - **Verification:** build the Debug configuration; the deprecation warning no longer appears. Run the app and confirm meal-row thumbnails still load and display correctly in the Meals tab.
  - **References:** smolspec.md, decision_log.md (Decision 3).

- [x] 4. Zero-warning, zero-error build confirmed for Debug and Release <!-- id:tuly0qq -->
  - **Outcome:** The documented xcodebuild verification command from smolspec.md returns no `warning:` or `error:` lines for both the Debug and Release configurations.
  - **Approach:** from the repo root, run `xcodebuild -project MeData/MeData.xcodeproj -scheme MeData -destination 'generic/platform=iOS' -configuration Debug clean build 2>&1 | grep -E "warning:|error:" | grep -v "Asset Catalog Compiler Notice"`. Then repeat with `-configuration Release`. If either invocation surfaces package-target warnings (CaptureKit, Pipeline, Persistence, PortableContracts), surface them to the user before declaring the spec complete — they were in scope per smolspec.
  - **Verification:** both commands print nothing under the grep.
  - **References:** smolspec.md.
  - Blocked-by: tuly0qn (iPhone-only device family eliminates iPad orientation and icon warnings), tuly0qo (`defaultCaptureModeReader` is `nonisolated` and the file-scope comment explains why), tuly0qp (`MealRow.loadThumbnail` uses the connected window scene instead of `UIScreen.main`)

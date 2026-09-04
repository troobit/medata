# Clean Build Baseline

## Overview

The most recent `research` branch build (post-merge of `tilt-tolerant-capture-ui` in commit `2824d37`) emits five compiler/validator warnings that block our zero-warning goal. This smolspec eliminates them with the smallest viable changes and records the product decisions taken along the way.

## Requirements

- The system MUST produce zero warnings and zero errors when the `MeData` target is built with the documented verification command (see "Implementation Approach > Verification").
- The system MUST target iPhone only; the `MeData` app target SHALL drop iPad from `TARGETED_DEVICE_FAMILY`.
- The system MUST keep the `defaultCaptureModeReader` free function usable as the default value for the `captureModeReader: @Sendable () -> CaptureMode` parameter on `CaptureFlowModel.init` under Swift 6 strict concurrency with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- The system MUST replace the deprecated `UIScreen.main` access in `MealRow.loadThumbnail` with an iOS 26-compatible screen access that produces an equivalent row-width value for `MealRowLayout.thumbnailTargetSize(rowWidth:)`.
- The existing file-scope explanatory comment above `defaultCaptureModeReader` SHOULD be updated to reflect the new `nonisolated` declaration and the underlying default-isolation behaviour.
- Behavioural changes outside the build-cleanliness goal SHOULD be minimised (no thumbnail-quality regressions, no iPhone-orientation behaviour changes, no refactors of `MealRow` or `CaptureFlowModel` beyond the lines required to clear the diagnostics).

## Implementation Approach

### Affected files

- **`MeData/MeData.xcodeproj/project.pbxproj`** — change `TARGETED_DEVICE_FAMILY = "1,2";` to `TARGETED_DEVICE_FAMILY = "1";` in both the Debug and Release build-configuration blocks of the `MeData` app target. (Currently at lines 394 and 432; the iPad orientation key `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` becomes dead but does not need removal — Xcode tolerates it on iPhone-only targets and removing it is out of scope.)
- **`App/CaptureFlowModel.swift`** — replace the `@Sendable` attribute above `defaultCaptureModeReader` with `nonisolated`. Update the file-scope comment immediately above the function (currently lines 10–12) to note that `nonisolated` is required because the file inherits `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and UserDefaults reads are documented as thread-safe. This single edit also clears the second diagnostic at the `defaultCaptureModeReader` default-arg site inside `CaptureFlowModel.init` because the function reference is now nonisolated `@Sendable`-compatible.
- **`App/MealRow.swift`** — in `MealRow.loadThumbnail`, replace the deprecated `UIScreen.main` access with a scene-based read that falls back to a conservative iPhone-portrait width when no scene is connected (e.g. early app launch):

  ```swift
  let rowWidth = await MainActor.run {
      let scene = UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .first
      return (scene?.screen.bounds.width ?? 393) - 32
  }
  ```

  393 pt is the width of an iPhone 15 / 16 standard, used only as the no-scene fallback. The `- 32` horizontal-padding subtraction is preserved verbatim so `MealRowLayout.thumbnailTargetSize(rowWidth:)` produces the same target as before.

### Verification

After all three code edits, the build is considered clean iff:

```bash
xcodebuild \
  -project MeData/MeData.xcodeproj \
  -scheme MeData \
  -destination 'generic/platform=iOS' \
  -configuration Debug \
  clean build 2>&1 \
  | grep -E "warning:|error:" \
  | grep -v "Asset Catalog Compiler Notice"
```

…returns no lines. The verification is repeated for `-configuration Release`. Package-target warnings (`CaptureKit`, `Pipeline`, `Persistence`, `PortableContracts`) are in scope for this smolspec if they surface; bring them up before implementation if they appear.

### Patterns to follow

- `nonisolated` on free functions whose body only touches thread-safe APIs is the standard Swift 6 fix for "MainActor-isolated marked Sendable" diagnostics under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`.
- The `UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first` pattern for resolving the active scene is Apple's recommended replacement for `UIScreen.main` (per the iOS 26 deprecation note).

### Out of scope

- Bumping deployment targets, Swift version, or any other project build settings.
- Removing the now-dead `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` key from `project.pbxproj`.
- Refactoring `MealRow`'s `loadThumbnail` pipeline beyond the screen-source replacement.
- Adding or regenerating any app-icon assets (with iPad dropped, the existing iPhone + marketing icons are sufficient).
- Adding landscape support, rotation handling, or any UI work on iPhone.
- The two other nextup.md items (surface-detection-modal-dismissal, branch consolidation) — those are tracked under separate specs.

## Risks and Assumptions

- **Risk**: Existing TestFlight builds installed on iPads will keep running until uninstalled; new builds will not be installable on iPad and the App Store listing will need to be updated to reflect iPhone-only support. **Mitigation**: Acceptable because iPad has never been a real product target; the AR capture flow has only been designed and tested for iPhone. Coordinate with whoever manages the App Store listing before the next TestFlight push.
- **Risk**: The scene-based screen read returns `nil` on first launch before any scene activates, producing the 393 pt fallback for the very first row render. **Mitigation**: The fallback matches the dominant iPhone width and only affects a one-frame initial render; the next layout pass picks up the real scene.
- **Risk**: Future iPad support would have to re-add `TARGETED_DEVICE_FAMILY="2"`, re-instate the icon work, and address landscape behaviour. **Mitigation**: Captured in Decision 1 so the constraint is discoverable when iPad becomes a real product question.
- **Assumption**: The `MeData` app target is the only target with `TARGETED_DEVICE_FAMILY = "1,2"`; package targets do not declare device families. (Verified at `project.pbxproj` lines 394 and 432; package targets are SPM-managed.)
- **Assumption**: `MealRow` is consumed only as a list row in the Meals tab and no caller relies on a width-providing context, so changing the internal width source is non-breaking. (Verified by file inspection.)
- **Assumption**: `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is set on both Debug and Release configurations (verified at `project.pbxproj` lines 390 and 428), so `nonisolated` is the correct Swift 6 fix.

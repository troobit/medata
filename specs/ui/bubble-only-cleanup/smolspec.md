# Bubble-only Tilt Guide Cleanup

## Overview
Three persistent tilt-guide designs (`.gauge`, `.dial`, `.bubble`) were built to compare on device; the `.bubble` design was chosen and is device-confirmed working (axis fix `85f9ede`, merged to `research` as `41f72d7`). This change removes the two unused designs and the style-selection scaffolding so only the bubble remains, per the MVP intent "use the bubble UI config, not retaining any of the others, including stubs or demos."

## Requirements
- The capture flow MUST render the bubble tilt guide directly, with no design-selection indirection (the `TiltGuideStyle` enum and its `switch` are removed).
- The `.gauge` and `.dial` designs MUST NOT be compiled or reachable after this change.
- The shared per-stage tilt logic the bubble depends on (`target`, `toleranceDegrees`, `isAligned`) MUST remain available to `TiltBubbleGuide` and its tests, under a neutral name (`TiltGuideState`) that does not reference a removed design.
- Logic used only by the removed designs (`halfSpanDegrees`, `offsetFraction`, `correction`) SHOULD be removed as dead code.
- No surviving file (code or comment) MAY reference the removed designs or scaffolding (`TiltGuideStyle`, `tiltGuideStyle`, `.gauge`, `.dial`, `TiltAimGuide`, `TiltDialGuide`) after this change.
- The Xcode project MUST NOT reference the deleted files, and the app MUST build for the iOS Simulator.
- Existing bubble behaviour MUST be unchanged: per-stage targets/tolerances, the `tiltGuide` / `tiltGuide.puck` accessibility identifiers, and the `liveTiltVector` input.
- The `DEV_STUB_SEGMENTER` build configuration MUST be left unchanged (it is the Track-3 segmenter placeholder, not UI scaffolding).

## Implementation Approach
- **Relocate + rename shared state.** Move the state enum out of `App/TiltAimGuide.swift` into `App/TiltBubbleGuide.swift`, trimmed to the three members the bubble uses (`target`, `toleranceDegrees`, `isAligned`), and rename it `TiltAimGuideState` → `TiltGuideState`. This is the one departure from "just delete the gauge file": the gauge file currently *contains* the state enum the bubble and tests depend on. The neutral name avoids leaving a type named after a deleted design; the three call sites and the test file update with it.
- **Delete** `App/TiltAimGuide.swift` (`.gauge` view) and `App/TiltDialGuide.swift` (`.dial` view).
- **`App/CaptureFlowView.swift`** — remove the `TiltGuideStyle` enum (lines ~19-23) and the `static let tiltGuideStyle` (line ~27); rewrite the header comment block (lines ~14-18) so it no longer describes three competing designs; and replace the `tiltGuide` computed property's `switch` (lines ~234-253) with a direct `TiltBubbleGuide(tiltVector: model.indicators.liveTiltVector, awaitingOblique: model.awaitingObliqueView)` (with a comment that no longer mentions `tiltGuideStyle`). Follows the existing direct-composition pattern (e.g. `LiveIndicatorBadge`).
- **`App/TiltBubbleGuide.swift`** — beyond receiving the relocated `TiltGuideState`, rewrite the header comments (lines ~3-15) to drop the `.gauge`/`.dial`/`tiltGuideStyle` framing and describe the bubble as the sole tilt guide. No reference to a removed design may remain.
- **Tests** — rename `MeData/Tests/TiltAimGuideTests.swift` → `MeData/Tests/TiltGuideStateTests.swift` (the test folder is in a synchronized group, so no pbxproj edit), update the `TiltAimGuideState` → `TiltGuideState` references and the suite name/comments, and drop the `offsetFractionMapsAndClamps` and `correctionSign` cases (they cover the removed gauge/dial logic); keep `targetPerStage`, `tolerancePerStage`, `isAlignedAtEdges`.
- **`MeData/MeData.xcodeproj/project.pbxproj`** — the two deleted files are explicitly listed (not in a synchronized folder), so remove the `TiltAimGuide.swift` and `TiltDialGuide.swift` entries from all four sections (`PBXBuildFile`, `PBXFileReference`, the `PBXGroup` children list, and the `PBXSourcesBuildPhase` files list). Leave the `TiltBubbleGuide.swift` entries intact.
- **Dependencies:** `LiveIndicatorModel.liveTiltVector` (unchanged); `Color.captureChromeText` / `captureChromeBG` / `medataAccent` (unchanged).
- **Out of Scope:** any change to `DEV_STUB_SEGMENTER`; `LiveIndicatorModel` / `CaptureFlowModel` (`liveTiltDegrees` stays — still used by `LiveIndicatorBadge` and the oblique gate); bubble visual or behavioural changes; the device-only screen-y polarity check (tracked separately).

## Risks and Assumptions
- **Risk:** a hand-edit to `project.pbxproj` malforms the project and breaks the build. **Mitigation:** remove only the eight known gauge/dial lines across the four sections, keep the bubble entries, and verify with an iOS-Simulator build before completing.
- **Assumption:** the `ui` worktree's `CaptureFlowView.swift` and `TiltBubbleGuide.swift` are identical to `research` (verified 2026-06-24), so the later `ui → research --no-ff` merge of this cleanup stays conflict-free.
- **Assumption:** `MeData/Tests/TiltAimGuideTests.swift` is build-verified only (no wired App test bundle); verification is a clean App build for the iOS Simulator plus the green `MedataCore` suite, not an executed App-test run.
- **Prerequisite:** work happens on the `ui` branch (worktree `medata.worktrees/ui`); the bubble design is already merged to `research`, so this only removes the alternatives.

---
references:
    - specs/ui/bubble-only-cleanup/smolspec.md
    - specs/ui/bubble-only-cleanup/decision_log.md
---
# Bubble-only Tilt Guide Cleanup — Implementation Tasks

- [x] 1. Relocate and rename the shared tilt state into TiltBubbleGuide.swift <!-- id:9r1en60 -->
  - Move the three members the bubble uses — target(awaitingOblique:), toleranceDegrees(awaitingOblique:), isAligned(tilt:target:tolerance:) — out of App/TiltAimGuide.swift into App/TiltBubbleGuide.swift, renaming the enum TiltAimGuideState -> TiltGuideState.
  - Drop the gauge/dial-only members halfSpanDegrees, offsetFraction, correction as dead code (decision_log Decision 1).
  - Update TiltBubbleGuide's own three references (lines ~31-35) from TiltAimGuideState.* to TiltGuideState.*.
  - Rewrite TiltBubbleGuide.swift header comments (lines ~3-15) to describe the bubble as the sole tilt guide — no mention of .gauge, .dial, tiltGuideStyle, or TiltAimGuideState (decision_log Decision 2).
  - Behaviour of target/tolerance/isAligned must be byte-for-byte identical to the current values (0/25 deg targets, 12/15 deg tolerances).
  - Stream: 1
  - References: specs/ui/bubble-only-cleanup/smolspec.md, App/TiltBubbleGuide.swift, App/TiltAimGuide.swift

- [x] 2. Replace the TiltGuideStyle selector in CaptureFlowView with direct bubble composition <!-- id:9r1en61 -->
  - Remove the TiltGuideStyle enum (lines ~19-23) and the static let tiltGuideStyle (line ~27).
  - Rewrite the header comment block (lines ~14-18) so it no longer describes three competing designs or tiltGuideStyle.
  - Replace the tiltGuide computed property's switch (lines ~234-253) with a direct TiltBubbleGuide(tiltVector: model.indicators.liveTiltVector, awaitingOblique: model.awaitingObliqueView), and update its comment to not mention tiltGuideStyle/TiltAimGuideState.
  - Leave liveTiltDegrees in place — still used by LiveIndicatorBadge and the oblique gate (smolspec Out of Scope).
  - Stream: 1
  - References: specs/ui/bubble-only-cleanup/smolspec.md, App/CaptureFlowView.swift

- [x] 3. Delete the gauge and dial files and remove them from project.pbxproj <!-- id:9r1en62 -->
  - Delete App/TiltAimGuide.swift (.gauge view) and App/TiltDialGuide.swift (.dial view).
  - Remove the TiltAimGuide.swift and TiltDialGuide.swift entries from MeData/MeData.xcodeproj/project.pbxproj across all four sections: PBXBuildFile (lines 27-28), PBXFileReference (62-63), the PBXGroup children list (118-119), and PBXSourcesBuildPhase files (240-241).
  - Leave all three TiltBubbleGuide.swift entries (29, 64, 120, 242) intact.
  - Do not touch the DEV_STUB_SEGMENTER configuration (Track-3 placeholder, not UI scaffolding).
  - Blocked-by: 9r1en60 (Relocate and rename the shared tilt state into TiltBubbleGuide.swift), 9r1en61 (Replace the TiltGuideStyle selector in CaptureFlowView with direct bubble composition)
  - Stream: 1
  - References: specs/ui/bubble-only-cleanup/smolspec.md, MeData/MeData.xcodeproj/project.pbxproj

- [x] 4. Rename and trim the tilt state test file <!-- id:9r1en63 -->
  - Rename MeData/Tests/TiltAimGuideTests.swift -> MeData/Tests/TiltGuideStateTests.swift (synchronized group — no pbxproj edit needed).
  - Update all TiltAimGuideState references to TiltGuideState and update the @Suite name/comments to drop removed-design framing.
  - Drop the offsetFractionMapsAndClamps and correctionSign cases (they cover the removed gauge/dial logic); keep targetPerStage, tolerancePerStage, isAlignedAtEdges.
  - Blocked-by: 9r1en60 (Relocate and rename the shared tilt state into TiltBubbleGuide.swift)
  - Stream: 1
  - References: specs/ui/bubble-only-cleanup/smolspec.md, MeData/Tests/TiltAimGuideTests.swift

- [x] 5. Verify: clean Simulator build, no stale references, green MedataCore suite <!-- id:9r1en64 -->
  - Build the App target for the iOS Simulator (iPhone 17) and confirm it compiles — no wired App test bundle, so this is the build gate.
  - Grep every surviving file for TiltGuideStyle, tiltGuideStyle, TiltAimGuideState, TiltAimGuide, TiltDialGuide, '.gauge', '.dial' and confirm zero matches (smolspec: no surviving file may reference a removed design, in code or comment).
  - Run the MedataCore swift test suite and confirm it stays green.
  - Blocked-by: 9r1en60 (Relocate and rename the shared tilt state into TiltBubbleGuide.swift), 9r1en61 (Replace the TiltGuideStyle selector in CaptureFlowView with direct bubble composition), 9r1en62 (Delete the gauge and dial files and remove them from project.pbxproj), 9r1en63 (Rename and trim the tilt state test file)
  - Stream: 1
  - References: specs/ui/bubble-only-cleanup/smolspec.md

---
references:
    - specs/ui/loading-symbol-animation/smolspec.md
    - specs/ui/loading-symbol-animation/decision_log.md
---
# Loading Symbol Animation — Implementation Tasks

- [x] 1. Transcribe the icon.svg geometry into SwiftUI shapes <!-- id:ldsym01 -->
  - Add MedataSymbolGeometry (enum namespace) in App/MedataLoadingSymbol.swift with Bowl, Bar, and Dot shapes plus a map(_:in:) helper.
  - Transcribe the three subpaths verbatim from static/icon.svg: bowl M 24,24 C 130,24 130,104 24,104 L 24,64; bar M 104,64 L 104,104; dot M 64,64 L 64,64.
  - map scales the 128 canvas uniformly into the draw rect and insets by half the stroke width so round caps are not clipped (decision_log Decision 1).
  - Stream: 1
  - References: specs/ui/loading-symbol-animation/smolspec.md, static/icon.svg

- [x] 2. Build the MedataLoadingSymbol view with sequential draw-on <!-- id:ldsym02 -->
  - Single @State progress: Double driver split into windows [0,0.55] bowl, [0.55,0.80] bar, [0.80,1.0] dot via a pure segment(_:from:to:) helper (decision_log Decision 2).
  - Bowl and Bar draw via trim(from:0,to:window); Dot fills a Circle animated with scaleEffect+opacity because trim cannot render a zero-length subpath (decision_log Decision 4).
  - Stroke width = size * 24/128; stroke colour defaults to Color.medataAccent, overridable; round line cap/join.
  - Parameters: mode (.loop/.once), size, colour, cycleDuration.
  - Blocked-by: ldsym01 (Transcribe the icon.svg geometry into SwiftUI shapes)
  - Stream: 1
  - References: specs/ui/loading-symbol-animation/smolspec.md

- [x] 3. Add loop, once, and Reduce Motion behaviour <!-- id:ldsym03 -->
  - Loop: animate progress to 1 with easeInOut(duration:).repeatForever(autoreverses: true) for a draw-in/erase-out cycle (decision_log Decision 3).
  - Once: same ease, no repeat, holds the finished mark.
  - Reduce Motion (@Environment(\.accessibilityReduceMotion)): set progress = 1 with no animation.
  - Accessibility label "Loading", trait .updatesFrequently, identifier medata.loadingSymbol; #if DEBUG #Preview showing both modes on black.
  - Blocked-by: ldsym02 (Build the MedataLoadingSymbol view with sequential draw-on)
  - Stream: 1
  - References: specs/ui/loading-symbol-animation/smolspec.md

- [x] 4. Wire the new file into the Xcode project <!-- id:ldsym04 -->
  - Add App/MedataLoadingSymbol.swift to MeData/MeData.xcodeproj/project.pbxproj across all four sections (PBXBuildFile, PBXFileReference, App PBXGroup children, PBXSourcesBuildPhase) following the ShutterButton.swift pattern (App group is not synchronized).
  - Confirm the project still parses with xcodebuild -list.
  - Blocked-by: ldsym02 (Build the MedataLoadingSymbol view with sequential draw-on)
  - Stream: 1
  - References: MeData/MeData.xcodeproj/project.pbxproj

- [ ] 5. Verify on device <!-- id:ldsym05 -->
  - make deploy-device, then view the loader (via #Preview or a temporary placement) and confirm: strokes draw in order bowl -> bar -> dot; loop reads cleanly (not a jarring erase); mark is centred and uncropped at multiple sizes; colour matches the accent.
  - Toggle Reduce Motion and confirm the finished mark shows statically with no draw-on.
  - Confirm make spell passes on the new docs and comments; MedataCore swift suite stays green (make test).
  - Blocked-by: ldsym03 (Add loop, once, and Reduce Motion behaviour), ldsym04 (Wire the new file into the Xcode project)
  - Stream: 1
  - References: specs/ui/loading-symbol-animation/smolspec.md, docs/agent-notes/device-build-and-test.md

- [ ] 6. (Follow-up) Adopt the loader at the .estimating call site <!-- id:ldsym06 -->
  - Out of scope for this spec (decision_log Decision 5). Replace/augment the hourglass Estimating hint in App/CaptureFlowView.swift (~line 234) with MedataLoadingSymbol, reviewed independently on device.
  - Stream: 1
  - References: specs/ui/loading-symbol-animation/smolspec.md, App/CaptureFlowView.swift

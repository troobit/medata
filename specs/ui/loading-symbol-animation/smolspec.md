# Loading Symbol Animation

## Overview

The app has no branded busy indicator. During the `.estimating` state — which on
the current dev-stub build can freeze for many seconds — `CaptureFlowView` shows
a plain `Label("Estimating…", systemImage: "hourglass")` capsule
(`App/CaptureFlowView.swift:234`), and other indeterminate waits (a launch/splash
moment, a deliberate delay) have nothing branded at all.

This spec introduces a reusable SwiftUI loading indicator, `MedataLoadingSymbol`,
that draws the Medata brand mark stroke-by-stroke. The mark is the three-stroke
glyph in `static/icon.svg` (a 128×128 SVG, 24-unit round-capped stroke in the
brand accent `#63FF00`): the **bowl-and-stem**, the **right-hand bar**, and the
**centre dot**. The component animates those three strokes in sequence — bowl,
then bar, then dot — so the mark appears to be drawn by hand, and loops that as
an indeterminate spinner. It is deliberately decoupled from any single call site
so it can be dropped into loading screens or timed delays anywhere in the app.

## Requirements

- The system MUST provide a reusable SwiftUI view (`MedataLoadingSymbol`) that
  renders the Medata mark from `static/icon.svg` and can be placed in any view.
- The mark's three strokes MUST animate on in a fixed order — bowl, then bar,
  then dot — each stroke starting only after the previous one is drawn, so the
  effect reads as a hand-drawn sequence, not a simultaneous fade.
- The bowl and bar MUST draw on as a stroke growing from one end to the other
  (a `trim`-based reveal), not a whole-shape opacity fade.
- The component MUST support an indeterminate **loop** mode (draw in, then erase
  out, repeating) for use as a spinner, and a one-shot **once** mode (draw in and
  hold the finished mark) for a splash/launch moment.
- The component MUST be size-agnostic: a single `size` parameter drives the whole
  mark, and the stroke width MUST stay proportional to `size` at the same 24/128
  ratio as `icon.svg` so the mark reads identically at any scale.
- The stroke colour MUST default to `Color.medataAccent` and be overridable via a
  parameter, so the loader works on both the OLED capture chrome and light
  system-grouped surfaces.
- When **Reduce Motion** is enabled, the component MUST present the finished mark
  statically with no draw-on animation (accessibility — no essential information
  is lost, the mark is simply shown complete).
- The component MUST expose an accessibility label of "Loading" and a stable
  accessibility identifier (`medata.loadingSymbol`) so it is announced to
  VoiceOver and addressable from UI checks.
- The geometry MUST be authored in the same 128×128 canvas as `icon.svg` (one
  source of truth for the mark's shape), not re-drawn by eye.

## Implementation Approach

**New file:** `App/MedataLoadingSymbol.swift` (wired into
`MeData/MeData.xcodeproj/project.pbxproj` across the four sections — PBXBuildFile,
PBXFileReference, the App PBXGroup children, and PBXSourcesBuildPhase — following
the `ShutterButton.swift` pattern, since the App group is not a synchronized
folder).

- **Geometry (`MedataSymbolGeometry`).** An `enum` namespace holding the three
  strokes as `Shape`s (`Bowl`, `Bar`, `Dot`) plus a `map(_:in:)` helper. The
  canvas control points are transcribed directly from `icon.svg`'s path data
  (bowl: `M 24,24 C 130,24 130,104 24,104 L 24,64`; bar: `M 104,64 L 104,104`;
  dot: the degenerate `M 64,64 L 64,64`). `map` scales the 128-canvas uniformly
  into the draw rect and insets by half the stroke width so the round caps are
  never clipped.
- **The dot** is drawn as a filled `Circle` of diameter = stroke width (matching
  the SVG's round-capped degenerate segment), because a `trim` cannot render a
  zero-length subpath. The dot sits on the canvas centre, so a `scaleEffect`
  about the frame centre scales it in place.
- **Sequencing** uses a single `@State private var progress: Double` driven 0→1,
  split into three windows by a pure `segment(_:from:to:)` helper: bowl draws over
  `progress ∈ [0.0, 0.55]`, bar over `[0.55, 0.80]`, dot over `[0.80, 1.0]`. Each
  stroke's `trim(to:)` / the dot's scale+opacity reads its window's local 0→1.
  One driver keeps the timing deterministic and the loop a single animation.
- **Loop** mode animates `progress` to 1 with
  `.easeInOut(duration: cycleDuration).repeatForever(autoreverses: true)` — the
  autoreverse gives a draw-in / erase-out cycle with no timer. **Once** mode runs
  the same ease without repeat. **Reduce Motion** sets `progress = 1` with no
  animation.
- **Parameters:** `mode` (`.loop` / `.once`), `size` (default 64), `colour`
  (default `.medataAccent`), `cycleDuration` (default 1.3 s). A `#Preview` under
  `#if DEBUG` shows both modes on black.

**Dependencies:** `Color.medataAccent` (design-system/MASTER.md, unchanged);
`@Environment(\.accessibilityReduceMotion)` (same pattern as
`App/ShutterButton.swift`).

**Out of Scope:**

- Wiring the loader into the `.estimating` chrome (replacing/augmenting the
  `hourglass` hint in `App/CaptureFlowView.swift`). This spec delivers the
  component; adopting it at a call site is a follow-up so the visual swap can be
  reviewed on device on its own.
- A determinate/progress variant (0–100%). This is an indeterminate indicator.
- Any launch-screen storyboard change. The `.once` mode is available for an
  in-SwiftUI splash, but the static `LaunchScreen` is untouched.
- Exporting the animation as a Lottie/video asset. The mark is drawn natively in
  SwiftUI so it stays vector-crisp and carries no new dependency.
- Changing `static/icon.svg`, the app icon, or the accent token.

## Risks and Assumptions

- **Risk: `trim`-driven reveal on a shape derived from an animated `Double` may
  not interpolate smoothly.** Mitigation: `progress` is the animated state and
  every stroke's trim end is a pure function of it, so SwiftUI interpolates the
  driver and re-renders each frame — the standard trim-animation pattern. Verify
  the draw-on reads smoothly on device.
- **Risk: the autoreverse "erase-out" reads as the mark being rubbed out rather
  than a clean loop.** Mitigation: erase-out is the intended loop aesthetic; if it
  reads poorly on device, switch the loop to a hold-then-fade cycle (a `Task`
  resetting `progress` to 0 behind an opacity fade) — noted in the decision log as
  the considered alternative.
- **Assumption: the App target is verified by build + on-device look, not an
  executed App-test suite** (per CLAUDE.md test gate). Verification here is a
  clean device build (`make deploy-device`) plus a visual check of the `#Preview`
  / a temporary placement; no App test target runs.
- **Assumption: the bowl cubic's rightmost extent stays inside the 128 canvas.**
  The symmetric cubic's mid-point x ≈ 103.5 (well under 128), and `map`'s
  half-stroke inset covers the round caps, so the mark is not clipped at any size.
- **Prerequisite: `Color.medataAccent` remains the brand accent** (design-system
  MASTER.md). If the accent token is renamed, the default parameter updates with
  it.

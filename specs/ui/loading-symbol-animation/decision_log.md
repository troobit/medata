# Decision Log: Loading Symbol Animation

## Decision 1: Draw the mark natively in SwiftUI from the `icon.svg` geometry

**Date**: 2026-07-04
**Status**: accepted

### Context

The brand mark exists as `static/icon.svg` — a 128×128 stroked path. To animate it
being drawn on, the shape must be available to SwiftUI as an animatable `Shape`.
The options are to render the SVG at runtime, or to transcribe its path data into
native `Shape` geometry.

### Decision

Transcribe the three subpaths of `icon.svg` into a `MedataSymbolGeometry` enum of
native SwiftUI `Shape`s, authored in the same 128×128 canvas, and map that canvas
into the draw rect at render time.

### Rationale

SwiftUI has no built-in SVG renderer, and the estimation path forbids new runtime
dependencies for anything on-device. A native `Shape` is what `trim`-based draw-on
animation needs, stays vector-crisp at any size, and keeps the mark's control
points as the single source of truth alongside the SVG. The path data is small
(one cubic, two lines, one dot), so transcription is cheap and auditable.

### Alternatives Considered

- **Runtime SVG parsing (SVGKit / PocketSVG)**: Reuse `icon.svg` verbatim -
  rejected; adds a third-party dependency for one tiny glyph and still needs
  conversion to an animatable path.
- **Lottie / exported video**: Rich motion tooling - rejected; heavyweight
  dependency and a binary asset to keep in sync with the vector mark, for an
  effect SwiftUI `trim` does natively.

### Consequences

**Positive:**
- No new dependency; vector-crisp at every size.
- One canvas (128×128) shared with `icon.svg`.

**Negative:**
- If `icon.svg` changes, the transcribed control points must be updated by hand.

---

## Decision 2: Sequence the strokes with one 0→1 driver split into windows

**Date**: 2026-07-04
**Status**: accepted

### Context

The three strokes must draw in order (bowl → bar → dot), each starting only after
the previous finishes. That ordering can be built from three independent animations
with staggered delays, from a phased state machine, or from a single progress value
mapped into per-stroke windows.

### Decision

Drive one `@State var progress: Double` from 0 to 1 and map it into three windows
(`[0, 0.55]`, `[0.55, 0.80]`, `[0.80, 1.0]`) with a pure `segment(_:from:to:)`
helper; each stroke reads its window's local 0→1.

### Rationale

A single driver makes the whole sequence one animation — trivial to loop with
`repeatForever` and trivial to freeze for Reduce Motion (set `progress = 1`). The
window maths is pure and unit-reasonable without instantiating a view. Staggered
per-stroke animations would need three coordinated `withAnimation` calls plus
delay bookkeeping, and would complicate a clean loop.

### Alternatives Considered

- **Three delayed `withAnimation` blocks**: Direct per-stroke control - rejected;
  harder to loop coherently and to reverse for the erase-out cycle.
- **Timeline/phase state machine**: Explicit stages - rejected as over-built for a
  three-stroke sequence a piecewise map expresses in a few lines.

### Consequences

**Positive:**
- The loop is a single animation; Reduce Motion is a one-line freeze.
- Timing constants (the window bounds) live in one place.

**Negative:**
- The window bounds are hand-tuned; re-balancing the pace means editing the
  fractions rather than a per-stroke duration.

---

## Decision 3: Loop by autoreversing the draw (draw-in / erase-out)

**Date**: 2026-07-04
**Status**: accepted

### Context

The indeterminate spinner needs to repeat. A draw-in can loop by hard-resetting to
empty and redrawing, or by autoreversing so the mark erases back out before the
next draw.

### Decision

Loop with `.easeInOut(duration: cycleDuration).repeatForever(autoreverses: true)`,
giving a draw-in then erase-out cycle.

### Rationale

Autoreverse needs no timer or manual reset — one `withAnimation` covers the whole
repeating cycle, which keeps the component free of `Task`/timer lifecycle. The
erase-out is a coherent motion (the reverse of the draw) rather than a jarring
snap-to-empty.

### Alternatives Considered

- **Hard reset + redraw**: A pure "draw only" loop - rejected; a snap from full to
  empty at cycle end reads as a glitch without a fade to hide it.
- **Hold-then-fade cycle** (`Task` resets `progress` behind an opacity fade):
  Nicer "always drawing forward" feel - deferred; it reintroduces timer lifecycle.
  Held as the fallback if the erase-out reads poorly on device (smolspec Risks).

### Consequences

**Positive:**
- No timer/`Task` to manage; the loop is declarative.

**Negative:**
- The mark spends half each cycle erasing, so it is "complete" only briefly. If a
  persistent finished mark is wanted mid-loop, the fallback cycle is needed.

---

## Decision 4: Render the centre dot as a filled circle, not a trimmed stroke

**Date**: 2026-07-04
**Status**: accepted

### Context

In `icon.svg` the dot is a degenerate segment (`M 64,64 L 64,64`) shown only by the
round line cap. A `trim` reveal over total path length cannot render a zero-length
subpath — it would contribute no length and never appear.

### Decision

Draw the dot as a filled `Circle` of diameter equal to the stroke width, and
animate it in with `scaleEffect` + `opacity` over the final window instead of a
`trim`.

### Rationale

The dot must still animate on last, but `trim` is the wrong tool for a point. A
scale-and-fade over `[0.80, 1.0]` gives it a distinct "pop" that ends the sequence.
Because the dot lies on the canvas centre, `scaleEffect` about the frame centre
scales it in place with no offset maths.

### Alternatives Considered

- **A tiny real segment to trim**: Keep all three as trimmed strokes - rejected;
  it invents geometry not in `icon.svg` and a trimmed near-zero segment reveals
  awkwardly compared with a clean scale-in.

### Consequences

**Positive:**
- Faithful to the SVG's round-cap dot; a crisp final beat to the sequence.

**Negative:**
- The dot uses a different animation channel (scale/opacity) from the two strokes
  (trim), so its easing is tuned separately.

---

## Decision 5: Ship the component decoupled from any call site

**Date**: 2026-07-04
**Status**: accepted

### Context

The most immediate use is the `.estimating` state, where `CaptureFlowView` shows an
`hourglass` hint. The loader could be wired straight into that view, or delivered
as a standalone component adopted later.

### Decision

Deliver `MedataLoadingSymbol` as a standalone, parameterised component and leave
adoption at `.estimating` (and any splash/delay) to a follow-up change.

### Rationale

The visual swap in the capture chrome is a design decision that deserves its own
on-device review, and coupling it into this change would mix "build the indicator"
with "change the capture screen". A decoupled component is reusable across loading
screens and delays, matching the request. The MVP test gate (build + look right on
device) is cleanly met for the component in isolation via its `#Preview`.

### Alternatives Considered

- **Wire it into `.estimating` now**: One fewer follow-up - rejected; bundles an
  unreviewed capture-chrome change into a component spec and narrows reuse.

### Consequences

**Positive:**
- Reusable anywhere; the capture-chrome change stays independently reviewable.

**Negative:**
- Until a follow-up adopts it, the component ships unused in the shipping binary
  (compiled, `#Preview`-only). Acceptable for a small view.

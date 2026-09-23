# Decision Log: Unified Entry Sheet

## Decision 1: No stepper alongside the keypad

**Date**: 2026-08-28
**Status**: accepted

### Context

The two entry surfaces were to be unified, and the proposal carried up/down arrows sized for both —
0.1 for glucose, 1 U for insulin — replacing the insulin sheet's `+`/`−` circles. The arbitrating
question put to the UI/UX review was whether arrows plus a keypad is too cluttered.

### Decision

No relative-adjustment control — arrow, stepper, or `+`/`−` — appears on any surface that carries
the shared keypad. The keypad is the only thing that sets the value.

### Rationale

The objection that decided it is correctness, not clutter. The displayed numeral is a render of a
digit buffer with an implicit decimal place: `1`, `2`, `1` is 12.1. An arrow that adds 0.1 changes
the value but not the buffer. After `1`, `2` (1.2), one tap up (1.3), then `5`, the buffer says 12.5
and the value says 0.5, and every rule that reconciles them surprises someone. Absolute-set and
relative-adjust are incompatible models of the same number, and this is a medical input.

A stepper also has no job on glucose independently of the conflict: glucose entry is transcription
from a meter, so there is no starting value to nudge, and three keypad taps reach any value in range
where 0.1 steps would need up to 290.

### Alternatives Considered

- **Arrows plus keypad, with defined buffer-reset semantics**: Any reset rule is defensible and none
  is guessable; documenting the hazard is not removing it.
- **Arrows only, no keypad on glucose**: Rejected outright — it breaks
  `fingerprick-glucose` Req 2.3's four-interaction budget, which the stepper was already measured
  against and failed (51 taps for 7.0 → 12.1).
- **Keypad on glucose, steppers retained on insulin**: The status quo. Rejected because it is the
  divergence this spec exists to remove, and because the insulin sheet is the one that gains most
  from typing a two-digit number directly.

### Consequences

**Positive:**
- One input model per value; a whole class of wrong-value bug cannot occur.
- Roughly 136pt of control chrome leaves the upper half of a sheet whose lower two-fifths is keypad.
- The insulin hold-acceleration schedule and its timing tests are deleted, not maintained.

**Negative:**
- Adjusting a seeded suggestion by one unit costs typing the new value rather than one tap. Chips
  (Req 1.5) cover the named cases, not arbitrary ±1.
- Careful, working code is deleted. It is the right implementation of a control that should not
  exist here, which does not make deleting it free.

---

## Decision 2: Remembered dose defaults are scoped per kind, and must name themselves

**Date**: 2026-08-28
**Status**: accepted

### Context

The proposal was to default the dose to the last value entered, useful for a basal that repeats
nightly. The insulin sheet saves in two taps from opening, and until now opened at a fixed 10 U.

### Decision

Each kind remembers its own last saved value and opens at it; an armed meal suggestion outranks the
remembered value; a fixed 10 U applies where neither exists. The caption beneath the numeral always
names which of the three the opening value came from, and is mandatory rather than optional.

### Rationale

A fixed default is learnable — it is 10 U every time, so tapping straight through records a known
number. A last-value default is variable and, without a caption, invisible: the same two taps record
a different number depending on history the user may not recall, on a surface where over-delivery
causes acute hypoglycaemia. Scoping per kind removes the worst case, a 14 U basal becoming the
opening value for the next bolus. The caption removes the rest by making the default state its own
origin, and the mechanism already exists for seeded values.

### Alternatives Considered

- **One remembered value across both kinds**: The original proposal. Rejected on the cross-kind
  seeding hazard above.
- **Basal remembers, bolus does not**: The UI/UX review's recommendation, on the grounds that a
  bolus tracks carbohydrate and does not meaningfully repeat. Rejected by the developer: a bolus
  pattern repeats often enough to be worth the tap, and the per-kind scoping plus the mandatory
  caption already carry the safety argument.
- **Keep the fixed 10 U**: Safest and most predictable; loses the repeating-basal convenience that
  motivated the change.

### Consequences

**Positive:**
- A repeating dose of either kind is one tap.
- The opening value always states its own provenance, which the fixed default never did.
- Cross-kind seeding is impossible by construction rather than by care.

**Negative:**
- The opening value is no longer constant, so it cannot be learned once. The caption is the only
  thing standing between a variable default and a silent one, which puts real weight on a
  `subheadline` line.
- Two more persisted keys whose staleness has no expiry: a dose from six months ago is still "last".

---

## Decision 3: Glucose folds into `LogSheet` as a fourth mode

**Date**: 2026-08-28
**Status**: accepted

### Context

`GlucoseEntrySheet` was deliberately kept out of `LogSheet`, and its header records why: `LogSheet`
is a fixed-height composition at the medium detent, glucose is keyboard-first at the large one, and
folding it in would have made one sheet present at two heights depending on mode.

### Decision

Glucose becomes `LogSheet.Mode.glucose`; `GlucoseEntrySheet.swift` is deleted; every mode presents
at `.large`.

### Rationale

Giving insulin a keypad dissolves the original objection. Once insulin is keyboard-first too, the
mode that wanted the large detent is no longer the odd one out — every mode wants it, and the sheet
has one height again. `LogSheet`'s own header names "one place a fourth event type lands" as a
purpose of the consolidation; glucose is that fourth event type.

The four-interaction budget survives because the mode selector is the sheet's title and every entry
point already opens directly in its own mode — the mechanism `medata://insulin/add` has used since
`LogSheet` shipped. Nothing needs building for `medata://glucose/add` to do the same.

### Alternatives Considered

- **Shared control, two sheets**: Extract the keypad but leave glucose in its own file. Lower risk
  and most of the code sharing, but keeps two dismissal contracts, two detent decisions and two
  places a fifth event type could land.
- **Keypad on insulin only, defer the fold**: Smallest step. Rejected as deferral rather than
  decision — the fold gets cheaper the moment insulin is keypad-first, and postponing it means
  changing the insulin surface twice.

### Consequences

**Positive:**
- One manual-entry surface, one detent, one dismissal contract; a file is deleted rather than added.
- The next event type has an obvious home.

**Negative:**
- The activity mode gains empty space below its controls at the larger detent, having previously
  fitted the medium one exactly.
- A regression in `LogSheet` now reaches glucose entry, which was previously isolated from it.

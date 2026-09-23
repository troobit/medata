# Visual Design Direction: Dose Suggestion

**Feature:** insulin-dosing
**Scope:** the visual and typographic treatment of a suggested dose, everywhere it appears
**Companion:** [design.md](design.md) owns the module boundary, the no-persistence model and the
seam. *(Reworded by Decision 18; it read "the ledger schema" — nothing derived is stored.)*
This file owns only how the thing looks, reads and moves.

Tokens are quoted from `App/Colors.swift` and `design-system/MASTER.md`. No token is invented here;
where a value is not in the design system it is called out as a new token to add.

---

## 1. The core idea: three registers, and a number that never commits

Every number on this app's surfaces belongs to exactly one of three registers, and the register is
carried by size, weight and colour — never by a label explaining what kind of number it is.

| Register | What it means | Treatment | Examples |
|---|---|---|---|
| **Measured** | The app looked at the world and got this | Largest type on the screen, `captureChromeText` / `textPrimary` at full opacity | `60` g carbs, the 72pt dose numeral |
| **Derived** | The app divided a measured number by a parameter a human typed | `subheadline`, `monospacedDigit`, `captureChromeText.opacity(0.75)` / `textSecondary` | `≈ 214 g on plate`, `12 U` |
| **Committed** | Tapping this writes a row | `medataAccent` fill, `.body.weight(.semibold)`, height 48, radius 12 | `Record 60 g`, `Save 12 U bolus` |

A dose suggestion is **rendered as the meal's quality pill** — the capsule the confidence tier used
to occupy, on the same surface, at the same metrics. It writes nothing, and that is now the whole
of the "not an instruction" argument. The three earlier structural props — not filled, no glyph, no
mark of any kind — were each tried and each failed on device, in the same direction every time:
they made the dose recede until it was indistinguishable from the measurement beside it.

**Confidence became the pill's colour rather than its content.** The tier is something a person
reads off their own plate faster than the model computes it, so the most prominent chrome on the
surface was being spent on the model's self-assessment while the number actually acted on sat in
`subheadline` grey. Inverting that puts the accuracy signal *on the thing it qualifies*: the fill
says how much to trust this dose, and the tier is named in words in the working, one tap away
(§2.2). The raw σ stays recorded per capture on the meal record — it did not stop being data, it
stopped being chrome.

What still holds: the dose is never larger than the carbohydrate figure it came from, never takes
the screen's `Record` slot, and writes nothing on tap. What is explicitly given up is the claim
that a filled shape cannot be a suggestion — a filled shape that changes nothing is a label, and
three device sessions of an unfilled one proved the alternative costs more than it buys.

**Known collision, accepted.** At High confidence the fill is `confidenceHigh`, which is the app
accent (`iphone-experience` Req 15.1), so a high-confidence dose renders in the same green as
`Record`. This is inherited, not introduced: the confidence pill has always rendered High in the
accent on this same screen. It is the one place the one-accent-per-screen rule bends, and it bends
for a pill that writes nothing.

**Signature element — the middle-dot line, ordered by time.** The suggestion appends to the existing
second line of `totalRow` as a `·`-separated segment. The line's axis is **time**: what is on the
plate now, then what to inject now, and later (iteration 5+) what to inject at +90 minutes. Segments
accrete left to right in the order their moment arrives. That is a structural device that encodes
something true, and it is the reason the future second-spike suggestion needs no redesign — it is
the next segment on a line that was always a timeline.

```
≈ 214 g on plate · 12 U · 4 U at +90 min
└─ measured, now ─┘   └now┘  └── later ──┘
```

**The one risk taken.** The boldest move in this direction is that the feature adds **zero pixels of
height, zero controls and zero screens** to the primary path. It is a readout that a person who was
not looking for it will not notice. That is a deliberate bet: a first suggestion whose ratio is a
typed-in prior does not deserve chrome, and a design that shouts would have to be walked back once
the ratio starts moving on evidence. The restraint is the design.

**Provenance appears exactly where the source number is not visible.** On the review screen the
carbohydrate total `60 g` sits directly above `12 U` in the same block, so the relationship needs no
explaining — and adjusting the plate fraction makes both numbers tick together, which teaches the
divisor better than a caption would. In the dose sheet the carbohydrate figure is gone, so the sheet
restates it: `from 60 g at 5 g/U`. One rule, applied twice, in opposite directions.

The worked figure throughout is a 60 g-carbohydrate meal on a 214 g plate at breakfast:
`60 g ÷ 5.0 g/U = 12.0 U`. The large numeral and the mass segment are different quantities
(`pendingTotalCarbsG` and `pendingTotalMassG`) and are never the same number by construction.

---

## 2. Meal review — the primary surface

Layout order is fixed and must not change: photo (40%) / totalRow / primaryAction / scale control /
1px divider / scrolling rows. The suggestion lives inside `totalRow`'s second line. No new row, no
new stack entry, no change to what sits above the fold (`specs/ui/meal-review` Req 6.6).

### 2.1 With a suggestion

```
┌───────────────────────────────────────────────┐
│                                       [ ⋯ ]   │  toolbar
│  ┌─────────────────────────────────────────┐  │
│  │                                         │  │
│  │        photo + class outlines           │  │  40% of height
│  │                                         │  │
│  └─────────────────────────────────────────┘  │
│                                               │  spacing 12
│  60 g carbs                     (● Moderate)  │  44pt heavy mono / title3 / pill
│  ≈ 214 g on plate · 12 U                      │  subheadline mono, white @ 0.75
│                                               │  spacing 12
│  ┌─────────────────────────────────────────┐  │
│  │             Record 60 g                 │  │  h 48, medataAccent, r 12
│  └─────────────────────────────────────────┘  │
│                                               │
│  PLATE        (1/4)(1/3)(1/2)(2/3)( 1 )       │  44x34 capsules — still above fold
│  ─────────────────────────────────────────    │  1px, white @ 0.08
│  ⌄ uncalibrated                               │  scrolls
│  Pasta, cooked                    180 g  ›    │
└───────────────────────────────────────────────┘
```

Everything below `60 g carbs` is unchanged from what ships today except for the seven characters
` · 12 U`.

### 2.2 Line grammar

```
  60                                  ⎛ ⚕ 12 U ⎞   ← the pill: fill = confidence tier
  g carbs                             ⎝________⎠
  ≈ 214 g on plate
```

The dose is **not** a segment on the middle-dot line. It is the pill in the total row's trailing
slot — the one the confidence tier held — and the middle-dot line beneath carries only the plate
mass. A measured mass and a dose derived from it are no longer rendered as two peers on one line,
which is the defect the 2026-08-28 session named: `≈ 380 g on plate · 6 U` read as two
measurements of one meal rather than a measurement and its consequence.

Pill metrics are `ConfidencePill`'s exactly — `.body.weight(.semibold)` monospaced digits,
horizontal 12 / vertical 4, `minHeight: 28`, `Capsule()` filled at `level.colour.opacity(0.85)`,
dark-on-fill except Very Low. Identical because it *replaces* that view in place: nothing above the
scroll boundary moves, so `specs/ui/meal-review` Req 6.6 holds by construction rather than by
measurement.

The `syringe` glyph rides inside the pill as the `Label` icon. There is no underline anywhere — the
pill is the affordance, which is the whole reason the underline could go.

- The remaining line segments — plate mass, and `given N U` on the history surface — are joined by
  ` · ` (U+00B7, space either side) at `opacity(0.45)` of the line's own colour. The separator is a
  `Text` run, not a divider view.
- Every remaining segment is the same font and colour, and carries no glyph. A glyph that appears
  on every segment marks nothing; only the pill has one.
- The pill speaks as one element: `"12 U, estimate confidence High"`, with a `Shows the working`
  hint. VoiceOver cannot see a fill, so the tier that the colour carries has to be said.
- No verbs. Never *take*, *give*, *dose*, *inject*, *recommended*, *suggested*, *should*. The
  segment is a quantity and a unit symbol. `12 U`, and nothing else.
- No range, no plus-or-minus, no confidence qualifier on the dose. The confidence pill already
  reports what the app knows about the estimate; qualifying the dose separately would be counsel.

*(Amended by Decision 17, [Req 6.12](requirements.md#6.12): the readout is tappable — the tap
opens the working (`60 g ÷ 5.0 g/U = 12.0 U`, one `− x U, for <reason>` line per reduction, the
unrounded result, then the rounding step to the whole-unit dose: `12.0 − 1.4 = 10.6 → 11 U`,
lines summing exactly at every step — rounding step added by Decision 18, which also has every
surface recompute the same working live, history included). It reveals provenance; it does not
act, and nothing is written.*

*Decision 17 originally added that tap with no mark of any kind, on the reasoning that any
affordance was control chrome; a dotted underline replaced that, and the pill has now replaced the
underline. Each step in the same direction, and the last one settles it: the surface a person taps
should look like a surface a person taps. "Writes nothing" is the invariant that was doing the
safety work all along. "Carries no mark", "is not filled" and "has no glyph" were not, and each
cost the feature either its provenance route or its distinguishability.)*

### 2.3 Degradation order — shed words before numbers

One line, `lineLimit(1)`, `minimumScaleFactor(0.9)`. At Dynamic Type sizes where the line no longer
fits, shed in this order, so the line loses language before it loses information:

1. `on plate` → `≈ 214 g · 12 U`
2. the `≈` → `214 g · 12 U`
3. the mass segment entirely → `12 U`

The dose segment and its `U` are never shed and never abbreviated. Wrapping to a second line is
forbidden on this screen: it would push the plate-scale control toward the fold, which
`specs/ui/meal-review` Req 6.6 protects.

### 2.4 Motion

Identical to the numerals already on the line: `.contentTransition(.numericText())` and
`.animation(.smooth)`, both gated on `accessibilityReduceMotion`, with the ternary written the same
way as the four existing sites in the file.

The moment this design is built around: tapping `1/2` on the plate scale rolls `60 → 30`,
`214 g on plate → 107 g`, and `12 U → 6 U` in one synchronised numeric roll. The divisor is taught
by motion, and no sentence has to say it.

### 2.5 Absent means no carbohydrate total

There is no placeholder, no em dash, no explanation. The only absent segment is a subject with no
carbohydrate total ([Req 3.5](requirements.md#3.5)) — unreachable on this surface, where a captured
meal always has a total. A computed `0 U` is a result, not an absence:

```
  ≈ 214 g on plate · 0 U
```

and its reason is one tap away in the working ([Req 6.12](requirements.md#6.12)). An em dash is the
convention for a *slot that exists and has no value* (`HomeView` glucose, `TrendsView` stats); this
line never needs one. *(Redefined in place by Decision 17. Superseded wording: "A suggestion that
was suppressed has no slot — it is a segment that was not appended. Nothing on this screen
distinguishes 'below 0.5 U', 'no ratio in force' and 'IOB covers it'; the reason is a column in the
ledger, not a word on the capture screen.")*

### 2.6 Accessibility

`totalRow` combines its children into one element. The combined label gains a third clause naming
the quantity, because VoiceOver has no adjacency to read the relationship from:

```
"60 grams carbs. 214 grams on plate. 12 units."
```

The dose `Text` carries `accessibilityIdentifier("review.doseSuggestion")` and is not separately
focusable. Naming a number in a spoken label is labelling, not counsel — the rule bars reassurance
and instruction, not nouns.

The working of [Req 6.12](requirements.md#6.12) is reachable without focusing the segment: the
combined `totalRow` element carries a custom accessibility action, "Show working", that opens the
same calculation the tap does. *(Added by Decision 17, Req 6.12.)*

---

## 3. The dose sheet — seeded, and obviously still yours

The sheet is on `surfacePrimary`, so it uses `textPrimary` / `textSecondary`, not the capture
palette. The 72pt numeral, the two 68pt step circles, the segmented kind picker, the compact date
row and the accent `Save` button are all unchanged.

The only addition is **one line in a slot that already exists**: the `units` caption beneath the
numeral becomes the provenance caption while the seeded value is untouched.

### 3.1 Opened with a seed

```
┌─────────────────────────────────────────┐
│              Insulin                    │
│                                         │
│      [ Bolus  |  Basal ]                │  segmented
│                                         │  spacing 24
│    ( − )        12         ( + )        │  68pt circles, 72pt bold mono
│              from 60 g at 5 g/U         │  footnote, textSecondary
│                                         │
│    Time              14 Aug, 08:41      │
│                                         │
│  ┌───────────────────────────────────┐  │
│  │        Save 12 U bolus            │  │  medataAccent
│  └───────────────────────────────────┘  │
└─────────────────────────────────────────┘
```

### 3.2 After the first touch of `+` or `−`

```
│    ( − )        14         ( + )        │
│              units                      │  reverts to today's caption
```

**The caption is consumed by the first edit.** One press of either step control — or any change of
kind or time — replaces `from 60 g at 5 g/U` with the plain `units` label the sheet ships with
today, permanently for that presentation. The screen therefore can never describe a number as
derived once a human has overridden it. This costs one boolean and zero layout: both captions are a
single-line `.subheadline`/`.footnote` in the same slot, so nothing moves.

It also answers "obviously editable" without a word of copy. The step circles are the largest
controls on the sheet at 68pt, they sit either side of the numeral, and the caption visibly reacts
to the first press. Editability is demonstrated, not stated.

### 3.3 Opened without a seed — unchanged, byte for byte

```
│    ( − )        10         ( + )        │
│              units                      │
```

The home `Dose` control and `medata://insulin/add` open exactly as they do today. The two-tap happy
path (syringe → Save) is preserved because nothing was inserted into it; the seed only changes the
opening value, and the `Save 12 U bolus` label already names the value being written, so no
confirmation surface is added.

### 3.4 Both two-tap paths, stated

| Path | Today | With this design |
|---|---|---|
| Dose | Dose → Save (2 taps) | Dose → Save (2 taps) |
| Widget / deep link | tap → Save (2 taps) | tap → Save (2 taps) |
| Capture | shutter → Record (2 taps) | shutter → Record (2 taps) |

The capture path is untouched because the suggestion is a readout on a line that already exists.
No sheet is raised from inside the Capture cover, so `AppRoot`'s presentation sequencing is not
involved. A dose is still a separate, deliberate act — reading `12 U` on the review screen commits
nothing.

---

## 4. Manual carb entry

`CarbEntrySheet` has a secondary line under its numeral; the same `· N U` segment appends to it,
same font, same `textSecondary`, same grammar.

```
│              62                         │
│         g carbs · 12 U                  │
│  ┌───────────────────────────────────┐  │
│  │            Save 62 g              │  │
│  └───────────────────────────────────┘  │
```

The `· N U` segment is present whenever a carbohydrate amount is entered, `0 U` included
([Req 6.6](requirements.md#6.6)). Quick-add presets are single-tap buttons whose entire label is a
carbohydrate figure. Adding a second number to a 44pt preset pill would rewrite the control and
blunt its one job — a preset button is a control, not a readout line — so a preset tap shows
nothing on the button itself, and the number reaches the developer as the dose sheet's opening
value (when it is ≥ 1 U) and on the intake's history detail. *(Redefined in place by Decision 17.
Superseded wording: "Showing nothing is the specified empty treatment.")*

---

## 5. Settings — the ratio, in one direction, with its reciprocal in sight

Four rows inside the existing `Section("Insulin")`, in band order, each a trailing decimal field
suffixed `g/U` with the reciprocal beneath as read-only `footnote` `textSecondary`.

```
 Insulin
 ┌───────────────────────────────────────────────┐
 │ Bolus                            NovoRapid    │
 │ Basal                               Lantus    │
 │ Overnight        00:00–06:00   [ 10.0 ] g/U   │
 │                                = 1.0 U per 10 g│
 │ Breakfast        06:00–11:00   [  5.0 ] g/U   │
 │                                = 2.0 U per 10 g│
 │ Lunch            11:00–16:00   [ 10.0 ] g/U   │
 │                                = 1.0 U per 10 g│
 │ Dinner           16:00–24:00   [ 10.0 ] g/U   │
 │                                = 1.0 U per 10 g│
 │ Ratio source                ( Chosen | medreg)│
 │ medreg fit             [                   ]  │
 └───────────────────────────────────────────────┘
```

*(Redefined in place by Decision 17. Superseded wording:
"`│ Pen increment                 ( 0.5 | 1 U )   │`" — the increment is fixed at 1 U and the row
is deleted.)*

- The **stored** value is grams per unit, and the field is suffixed `g/U` so the direction is on
  screen at all times. The reciprocal is rendered, never stored, and its caption spells out the
  user's own phrasing — `= 2.0 U per 10 g` — so the two conventions are visibly the same number and
  no one has to hold the inversion in their head. A field labelled merely `Ratio` is the trap this
  layout exists to close.
- The local-hour window is secondary text in the row's leading column, at `footnote`
  `textSecondary`. It is a fact about which meals the row governs, and it makes "mornings" concrete
  without a sentence.
- A rejected entry reverts on commit and shows nothing. No validation copy.
- An unconfigured band shows its seed value in normal weight — the value in force is always the
  value on screen. If a design later needs to distinguish seed from typed, that is a `footnote`
  glyph in the reciprocal line, not colour.

---

## 6. Where the future lands, without a redesign

Each of these is a slot the current direction already leaves open. None requires re-laying out a
screen that ships in iteration 1.

### 6.1 The second spike — one more segment on the timeline

```
  ≈ 214 g on plate · 12 U · 4 U at +90 min
```

The line was always ordered by time, so a later dose is a right-hand append. It inherits the
register, the separator, the absence-is-absence rule and the shed order (it sheds first, being the
least certain and the furthest away). Its grammar is `<number> U at +<n> min` — still no verb.

At Dynamic Type sizes where three segments cannot fit, the future segment moves to the accessory
line below the divider rather than wrapping the total row, because the accessory line already
scrolls and already collapses.

### 6.2 The follow-up prompt

A local notification at the observed lag, deep-linking to the seeded sheet. Its body is the same
grammar and nothing else:

```
┌──────────────────────────────────┐
│ Medata                    now    │
│ 4 U · pizza, 90 min ago          │
└──────────────────────────────────┘
```

Tapping it opens the sheet already seeded, with `from 60 g at 5 g/U · fat` as the provenance
caption. The caption's job of naming the divisor extends to naming the rule, in the same slot.

### 6.3 The day view — suggested against given

`doseRow` on the Graph day view gains one trailing secondary line at `caption` `textSecondary`. This
is where a suggested-versus-given comparison reads naturally, because it is per-dose:

```
 Insulin
 08:41   Bolus                              12 U
         suggested 12 · 5 g/U · breakfast
 18:20   Bolus                               9 U
         suggested 11 · 10 g/U · dinner
```

Here the word *suggested* is permitted and necessary: this is a history readout where two numbers
sit side by side and the reader must know which is which. It is a column heading in prose, not
counsel about a future action. The rule is precise — **naming a past hypothesis is labelling;
qualifying a present number is counsel.**

Rows with no suggestion show no second line.

*(Decision 18 note: nothing is read back — the second line recomputes the suggestion for the
paired meal's instant, with the dose paired to its meal by the ±45-minute window of
[Req 4.8](requirements.md#4.8). A dose with no meal or intake inside its window is the row with
no second line, and per [Req 6.11](requirements.md#6.11) the "suggested" figure is the rule
applied now, not a stored quotation.)*

### 6.4 The dose log screen — recomputed, not read back

*(Retitled and redefined in place by Decision 18; §7's token-table label follows the retitle.
It was "The ledger screen", "Modelled on `EstimationLogView`: a plain list … one row per
suggestion", its sketch reading stored-row values — second lines
"`60 g · 5 g/U · seed · FPU 3.1 · IOB 0.0`" / "`108 g · 10 g/U · manual · FPU 5.4 · IOB 1.8`" /
"`3 g · 10 g/U · seed · IOB 0.0`" — and "the same middle-dot grammar, now carrying provenance".
No store exists: this future screen derives one row per recorded meal or intake, recomputing
the suggestion for each subject's own instant and pairing the given dose by the ±45-minute
window — the same computation every other surface runs.)*

```
 Dose log
 ┌───────────────────────────────────────────────┐
 │ 14 Aug 08:41   breakfast          12 → 12 U   │
 │ 60 g · 5 g/U                                  │
 ├───────────────────────────────────────────────┤
 │ 13 Aug 18:20   dinner              11 → 9 U   │
 │ 129 g · 10 g/U · − 1.8 U on board             │
 ├───────────────────────────────────────────────┤
 │ 13 Aug 12:02   lunch                0 → — U   │
 │ 3 g · 10 g/U                                  │
 └───────────────────────────────────────────────┘
```

`12 → 12 U` is suggested → given. The second line is the same middle-dot grammar, now carrying
the working's terms — grams, ratio, and any reduction — because on this screen every row is a
past event and the useful axis has changed. This is the one surface where the sole surviving
suppression — no carbohydrate total ([Req 3.5](requirements.md#3.5)) — would be rendered as
words, because the screen exists to explain rows. *(Redefined in place by Decision 17.
Superseded wording: "`│ 13 Aug 12:02   lunch          suppressed      │`" /
"`│ 3 g · 10 g/U · seed · below 0.5 U             │`" and "This is the one surface where a
suppression reason is rendered as words" — under [Req 3.4](requirements.md#3.4) the 3 g quick-add
is a `.suggested` `0 U` row with its working inspectable.)*

---

## 7. Tokens

Everything below is already in `App/Colors.swift`. No new colour is required for iteration 1.

| Use | Token |
|---|---|
| Capture-surface derived text | `captureChromeText.opacity(0.75)` |
| Middle-dot separator (capture) | `captureChromeText.opacity(0.45)` |
| Grouped-surface derived text | `textSecondary` |
| Committing controls | `medataAccent` on `captureBackground` foreground |
| Sheet surfaces | `surfacePrimary`, `surfaceElevated` (step circles) |
| Dose log / day-view insulin figures | `seriesInsulinBolus`, `seriesInsulinBasal` |

Type: `subheadline` monospacedDigit for capture-surface segments; `footnote` for the sheet
provenance caption and the Settings reciprocal; `caption` for the day-view second line; existing
72pt bold mono for the dose numeral. Spacing stays on 4 / 8 / 16 / 24; segment separator spacing is
part of the string, not a stack gap.

**Documentation debt, not a new token:** `design-system/MASTER.md`'s colour block omits
`seriesInsulinBolus` and `seriesInsulinBasal`, which ship in `Colors.swift`. Anyone designing insulin
surfaces from MASTER.md alone will miss the two colours insulin already owns. That block should be
brought level.

---

## 8. Forbidden

- **The orange card.** `confidenceModerate` rounded-12 banners are reserved for estimate-accuracy
  signals (uncalibrated, liquid over-estimate). It is also the idiom that invites disclaimer copy.
  A dose suggestion never uses it. *(The dose PILL is a capsule carrying that palette as a fill,
  which is a different idiom and carries no copy — the banner is what invites a sentence.)*
- **Accent on a suggestion.** One accent per screen, and it belongs to the control that writes a
  row.
- **A second primary control on meal review.** The two-button row on that screen is the very-low
  retake pair and stays that way, and nothing new writes a row. *(Redefined 2026-08-28: the dose
  pill is filled and is tapped, so this no longer reads as "nothing may be filled". It reads as
  what it always meant — nothing but `Record` may WRITE. The pill reveals the working and returns
  the surface untouched.)*
- **Any added height above the divider.** `specs/ui/meal-review` Req 6.6 protects the plate
  control's position.
- **Verbs, ranges, qualifiers, reasons, reassurance.** No *take*, *consider*, *approximately N to
  M*, *based on your settings*, *always confirm*, *this is an estimate*. The carve-out in CLAUDE.md
  for functional accuracy signals covers estimate accuracy; it does not extend to a dose.
- **A new screen or sheet on the capture path.** Nothing is presented from inside the Capture cover.
- **Emoji anywhere, and any glyph on a line segment.** The plate mass and the `given` figure carry
  no symbol. The `syringe` lives inside the pill and nowhere else — a glyph on every segment marks
  nothing.
- **Added height above the divider, and any growth of the pill beyond `ConfidencePill`'s metrics.**
  The pill replaces that view in place; the moment it is taller, `meal-review` Req 6.6 stops
  holding by construction.
- **A dose figure larger than the carbohydrate total it came from.** The 44pt carb numeral is the
  measured fact and stays the largest thing in the row.

  *(This list previously forbade first any glyph beside the dose figure — "not even a syringe
  glyph, an icon beside a number reads as a call to action" — and then, after that was reversed,
  "accent, fill, or added height on the dose segment". Both are withdrawn on device evidence. Each
  predicted that visual weight would read as a command; what actually happened at each step was
  that the dose receded into the measurement beside it, and the tap-through provenance went
  unfound. Fill and colour now carry the confidence tier, which is estimate-accuracy information
  and precisely what this palette is reserved for. The invariant that survived all three rounds,
  and the only one that was ever load-bearing, is that the dose writes nothing.)*

---

## 9. Checklist against `design-system/MASTER.md`

- [x] No emojis as icons — the dose glyph is an SF Symbol (`syringe`), the same one the Dose
      button and the Records row already use for this quantity; no emoji is used anywhere
- [x] Touch targets ≥48pt — the dose pill is `minHeight: 28` plus padding, below the bar. Accepted
      as inherited: it is the confidence pill's own geometry, and growing it would break
      `meal-review` Req 6.6. Revisit if the pill ever becomes the primary way to open the working
- [x] Press feedback within 100ms — no new pressable surfaces on the capture path
- [x] Contrast ≥4.5:1 — white at 0.75 opacity on pure black is ~11:1; `textSecondary` is a system
      semantic
- [x] Reduced motion respected — every numeral gated on `accessibilityReduceMotion`
- [x] Dynamic Type — explicit shed order in §2.3; wrapping forbidden on the total row
- [x] Safe areas — no change to the layout envelope
- [x] Single primary CTA per screen — `Record` on review, `Save` on the sheet; the dose pill is
      tappable but writes nothing, so it is a disclosure control, not a CTA
- [x] One accent colour per screen — bent, knowingly: at High confidence the dose pill's fill is
      `confidenceHigh`, which is the accent (`iphone-experience` Req 15.1). Inherited from the
      confidence pill this view replaces, which rendered High in the accent on this same screen.
      `Record` remains the only accent-coloured thing that writes anything

---

## 10. Settled on device — bare `12 U`

§2.2 keeps the review-screen segment to bare `12 U`, matching [design.md](design.md), and puts the
divisor in the working instead. The alternative was `· 12 U at 5 g/U` on the review line: visible
ratio convention at the moment of capture, at the cost of eleven characters on the tightest line in
the app and one more thing to read on a screen whose job is to be dismissed in seconds.

**Decided 2026-08-28, on device, against the seeded demo meal** — the terms this section asked for.
The build had shipped the data-forward branch (`≈ 380 g on plate · 6 U · 10 g/U`); with it on
screen the verdict was that the ratio is not needed on the line, because tapping the figure already
states it in the working. The ratio run is removed from every surface that renders a dose — the
review total line, the history line, and their spoken labels — leaving `design.md`'s form at every
width. The divisor is now stated in exactly one place per surface: the working.

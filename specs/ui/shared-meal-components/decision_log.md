# Decision Log: Shared Meal Components

## Decision 1: The multi-surface features are the requirement that clears the DRY bar

**Date**: 2026-08-25
**Status**: accepted

### Context

The repo has twice rejected extraction for its own sake.
`specs/ui/home-router/decision_log.md` Decision 13: "no requirement demanded the
shared-decoder DRY win"; `specs/ui/bubble-only-cleanup/decision_log.md` rejected "a new file
(and a new `project.pbxproj` entry) for ~15 lines of shared logic". The standing bar is that
duplication is removed when a requirement forces coordination, not because it offends.

Three features now land the same element on three-plus surfaces: the dose readout
(`specs/data/insulin-dosing` Req 6.1/6.10 — review line, manual entry line, overview,
result), the mass line (`specs/ui/mass-readout` — already on three), and save-as-quick-add
(`specs/data/manual-carb-intake` Req 8.1 — "both on the surface shown immediately after a
successful capture and on the surface reached from records"). Meanwhile the serving editor is
~160 lines duplicated twice, the carb form ~105 lines twice, and the precedent for
token-layer sharing is already accepted (`specs/ui/iphone-experience`: inline values
"would force coordination via copy-paste … A token layer eliminates that coordination").

### Decision

Extract the shared blocks named in requirements.md (serving editor, carb-amount form,
readout set, timeline row grammar, formatters, entry chrome adoption) into three shared
`App/` files, as a behaviour-preserving refactor sequenced after the insulin-dosing
Decision 16 synthesis merge and before `manual-carb-intake` tasks 12–18.

### Rationale

Every multi-surface element currently costs one edit per surface and diverges silently —
the four `corrected` capsules already differ (two on `surfaceElevated`, two on
`captureChromeBG`); `ResultView` and `MealReviewView` step buttons differ 36 pt vs 44 pt for
no recorded reason. The features about to land triple the coordination surface. Extracting
first means the dose segment and preset action are written once into shared components
rather than stitched three times and extracted later at higher risk.

### Alternatives Considered

- **Keep duplicating, land the features per-surface**: No refactor risk now - Rejected: the
  dose segment alone would add a fourth and fifth copy of the secondary-line grammar, and
  each future adjustment (design-direction.md §10's open question, the +90 min segment)
  would be a three-file edit with a silent-miss failure mode.
- **Extract everything including the Graph decoders and observation loops**: Maximum DRY -
  Rejected: reverses home-router Decision 13 against its still-valid rationale (perf-hang
  file; `Event.id` loss), and the observation loop shares task lifetime, not rendering.
- **One monolithic `App/SharedComponents.swift`**: One pbxproj registration instead of
  three - Rejected: a single file mixing row controls, readouts and formatters recreates the
  navigation problem inside one file; three files match the three consumer groups and keep
  each under ~200 lines.

### Consequences

**Positive:**

- The dose readout, mass line and preset action become one-edit changes.
- ~500 duplicated lines collapse; recorded divergences (marker backgrounds, step sizes)
  are resolved deliberately instead of persisting by accident.
- `MealHistoryModel` dead code is removed with its test file.

**Negative:**

- Extraction risk on the most-used surfaces; mitigated by callback seams that keep each
  surface's persistence code in place, and gated by the device look (Req 6.3).
- Three new pbxproj registrations, each a four-place manual edit.
- `git blame` over the moved bodies loses direct history at the new sites.

### Impact

`App/ServingRows.swift`, `App/MealReadouts.swift`, `App/SharedFormatting.swift` (new);
adoption edits in `MealReviewView`, `ResultView`, `MealOverviewView`, `RecordsView`,
`IntakeView`, `QuickPresetEditSheet`, `LogSheet`, `DoseScheduleSettingsSection`,
`GlucoseConnectionsView`, `EstimationLogView`, `TrendsView` (call sites only);
`MealHistoryModel.swift` removed.

---

## Decision 2: The corrections-overlay loop and Graph decoders stay duplicated

**Date**: 2026-08-25
**Status**: accepted

### Context

Beyond the rendering blocks, two logic duplications were candidates: the corrections
observation loop (`@State isCorrected` / `correctedTotal` / `correctedClassIds`, a `.task`
with a `for await _ in store.eventsDidChange` loop and the fold that "a later amount-only
correction never erases an earlier relabel") at three sites, and `TrendsModel`'s
glucose/insulin decoders, which `RecordsModel` deliberately re-implements.

### Decision

Both stay as they are. The extraction in this spec is rendering and formatting only.

### Rationale

The observation loop's lifetime is owned by each view's `.task` — sharing it shares
cancellation and re-subscription behaviour across screens with different lifecycles, which
is a behaviour change dressed as DRY, and `RecordsModel` documents the duplication as chosen
("reuses MealHistoryModel's corrections-overlay composition (Decision 13)"). The Graph file
is perf-protected by home-router Decision 13 and its cited hang bugfix.

### Alternatives Considered

- **An async-sequence helper returning folded corrections**: Removes the fold duplication -
  Rejected: the fold is ~10 lines; the helper's ownership/cancellation contract costs more
  to specify than the fold costs to repeat.
- **Move `RecordsModel` decoding into shared code with `TrendsModel`**: - Rejected verbatim
  per home-router Decision 13 ("drops `Event.id` (breaks the glucose tie-break) and churns a
  perf-hang-prone file for no required benefit").

### Consequences

**Positive:**

- The perf-sensitive file is untouched; no behaviour risk from shared task lifetimes.

**Negative:**

- The fold rule lives in three places; a change to correction-fold semantics still needs a
  three-site sweep (unchanged from today, now recorded).

---

## Decision 3: The shared unit is the content, not the container

**Date**: 2026-08-25
**Status**: accepted

### Context

Requirement 3.1 asks for one carb-total implementation across `MealOverviewView`,
`MealReviewView` and `ResultView`. In code the three blocks are structurally different
containers: the overview and review rows are leading-aligned baseline HStacks carrying a
trailing confidence pill, while the result hero is a centred VStack with an estimated-line
and the recorded-suggestion line, and each carries a different secondary stack. The photo
surfaces differ the same way — a 240 pt overlay card, a 64 pt thumbnail, and the review
photo layer share only their loading logic and fallback.

### Decision

Extract the CONTENT as the shared implementations — `CarbAmountText` (numeral + `g carbs`
pair, parameterised by palette, numeral size and suffix treatment), `CorrectedMarker`,
`RecordedSuggestion.line`, and the relocated `MealPhotoLoader` — and leave each surface
owning its container layout. `MealPhotoCard` from the design sketch is not built; the card
layouts stay per-surface and only the loader is shared.

### Rationale

Forcing the three containers through one block view would need slots for every difference
(pill placement, secondary stack, alignment, centring), leaving a component that is all
parameters and no shared substance — coordination cost without divergence protection. The
divergence that actually bit (four marker variants, two suffix opacities) lives in the
content, and that is what is now written once.

### Alternatives Considered

- **A slot-based `CarbTotalBlock` container**: One view for all three blocks - Rejected:
  its parameter surface would exceed the code it removes, and every future surface change
  would thread through slot plumbing.
- **Leave the totals duplicated, share only the marker**: Smaller change - Rejected: the
  numeral pair is where the dose segment and mass line attach, exactly the multi-surface
  coordination Decision 1 names.

### Consequences

**Positive:**

- The two accidental divergences (marker backgrounds, 0.7 vs 0.75 suffix opacity) resolve
  to one deliberate treatment.
- Each surface's layout remains readable in place.

**Negative:**

- Requirement 3.1's "carb-total block" reads wider than what shipped; this decision is the
  recorded narrowing (the pair + marker + suggestion line are shared, the container is not).

---

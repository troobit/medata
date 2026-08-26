# Requirements: Shared Meal Components

## Introduction

The meal surfaces were built in separate cycles and each carried its own copy of the same
blocks: the per-food serving editor is ~160 lines duplicated between `ResultView` and
`MealReviewView`; the carb-amount form is ~105 near-identical lines between `CarbEntrySheet`
and `QuickPresetEditSheet`; the carb-total readout exists three times; the "corrected"
capsule four times; the timeline row layout six times; the `en_IE` time formatter five
times. Until now no requirement demanded the extraction, and the repo's standing posture
(`specs/ui/home-router/decision_log.md` Decision 13: "no requirement demanded the
shared-decoder DRY win") correctly rejected it.

That requirement now exists. Three features land the same element on three-plus surfaces at
once: the dose readout segment (`specs/data/insulin-dosing` Req 6.1/6.10) renders on the
review line, the manual entry line and the result screen *(Redefined in place by
Decision 4 — `specs/ui/home-router` Decision 16 deletes the overview. Superseded wording:
"the review line, the manual entry line, the overview and the result screen".)*; the
estimated-mass
line (`specs/ui/mass-readout`) is already on three; save-as-quick-add
(`specs/data/manual-carb-intake` Req 8.1) lands on two. Every one of these currently means
the same edit made twice or three times, divergence-prone in exactly the way
`specs/ui/iphone-experience`'s token decision named when it rejected inline values: "would
force coordination via copy-paste". This spec extracts the shared blocks so a multi-surface
element is written once.

## Non-Goals

- **No visual redesign.** Each surface renders as it does today (under
  [`specs/ui/unified-dark-theme`](../unified-dark-theme/requirements.md)'s resolution);
  extraction is behaviour- and pixel-preserving except where a criterion below names a
  deliberate convergence.
- **No sharing of the Graph decoders or the correction-observation loop.** `TrendsModel` is
  the perf-hang-prone file home-router Decision 13 protected
  (`specs/bugfixes/graph-month-selection-hang/`); the corrections-overlay composition is a
  documented deliberate duplication (`RecordsModel` cites "MealHistoryModel's
  corrections-overlay composition (Decision 13)"). Both stand.
- **No correction affordances on history surfaces beyond what ships today.** `ResultView`
  keeps its serving/amount adjustment (landed by `specs/serving-adjust`) and does not gain
  relabel/reject/absent-food — `specs/ui/meal-review`'s Non-Goal ("Correcting a meal from
  Records or Graph after the capture session has ended") is not reversed by sharing the
  component that renders rows.

## Requirements

### 1. One Serving Editor

**User Story:** As the developer, I want the per-food amount row implemented once, so that a
change to how servings read cannot land on one surface and miss the other.

**Acceptance Criteria:**

1. <a name="1.1"></a>The per-food serving controls — the serving-first amount button, the
   gram editor with its clamping and live serving echo, the step buttons and step logic, and
   the plate-fraction control — SHALL be rendered by one shared implementation consumed by
   both `MealReviewView` and `ResultView`.
2. <a name="1.2"></a>The shared implementation SHALL take its state through bindings or
   callbacks so each surface keeps its existing backing (`MealReviewModel.setAmount` on
   review; the local pending-grams state and `PbUserCorrection` persistence on result), and
   each surface's persistence behaviour SHALL be unchanged.
3. <a name="1.3"></a>Per-surface accessibility identifier prefixes (`review.` / `result.`)
   SHALL be preserved exactly.
4. <a name="1.4"></a>The two surfaces' step-button hit targets MAY converge on the larger
   (44 pt) size; every other metric SHALL be preserved per surface.

### 2. One Carb-Amount Form

**User Story:** As the developer, I want the carb/macro entry body implemented once, so the
entry sheet and the preset editor cannot drift.

**Acceptance Criteria:**

1. <a name="2.1"></a>The carb field, macro disclosure group, macro rows, and macro
   string↔value conversion SHALL be one shared implementation consumed by the carb entry
   surface and `QuickPresetEditSheet`.
2. <a name="2.2"></a>Existing accessibility identifiers on both surfaces SHALL be preserved.
3. <a name="2.3"></a>The save-button treatment (accent fill, loading symbol, disabled logic)
   SHALL come from the shared entry chrome (Req 5) rather than a per-sheet copy.

### 3. One Readout Set

**User Story:** As the developer, I want the carb total, mass line, dose segment and
corrected marker to be single implementations, so the numbers that matter most read
identically everywhere they appear.

**Acceptance Criteria:**

1. <a name="3.1"></a>The carb-total block (big numeral + `g carbs` + corrected marker +
   confidence pill + secondary mass/dose line) SHALL be one shared implementation
   parameterised by palette and numeral size, consumed by `MealReviewView` and
   `ResultView`. *(Redefined in place by Decision 4: `MealOverviewView` is deleted by
   `specs/ui/home-router` Decision 16 and leaves the consumer set.)*
2. <a name="3.2"></a>The "corrected" capsule SHALL be one implementation consumed by all
   current sites (the two above plus the Records meal row). *(Redefined in place by
   Decision 4. Superseded wording: "all four current sites (the three above plus the
   Records meal row)".)*
3. <a name="3.3"></a>The dose segment SHALL enter these surfaces only through the shared
   readout line (`DoseReadoutLine` from the insulin-dosing synthesis), never as a per-view
   string.

### 4. One Timeline Row Grammar and One Formatter Set

**User Story:** As the developer, I want list rows and timestamps built from one grammar, so
a sixth copy of the same HStack is never written.

**Acceptance Criteria:**

1. <a name="4.1"></a>The timeline row layout (glyph in a fixed 20 pt frame, headline over
   caption stack, trailing figures) SHALL be one shared layout consumed by the five
   `RecordsView` row types and `IntakeView`'s entry row.
2. <a name="4.2"></a>The `en_IE` date/time string helpers SHALL be one shared implementation
   with cached formatters, replacing the five per-view `DateFormatter` allocations;
   rendered output SHALL be unchanged at every call site.
3. <a name="4.3"></a>The food-class `prettify` helper SHALL have one home consumed by its
   current three call sites.

### 5. One Entry-Sheet Chrome

**User Story:** As the developer, I want every manual-entry sheet built from the same chrome,
so a fourth copy of the back-dating row or save button is never written.

**Acceptance Criteria:**

1. <a name="5.1"></a>The shared entry chrome (`EntryTimeRow`, `EntrySaveButton`, `EntryChip`,
   `ChipFlow` — landing with the insulin-dosing Decision 16 synthesis) SHALL be the only
   implementation of the back-dating row and commit button across `LogSheet`'s three modes
   and `QuickPresetEditSheet`. (`DoseScheduleSettingsSection`'s time picker is excluded: it
   is a schedule time-of-day control — hour and minute only, no date, no future bound — not
   a back-dating row, and forcing it through `EntryTimeRow` would change its behaviour.)
2. <a name="5.2"></a>No standalone sheet SHALL retain a private copy of the sheet chrome
   (NavigationStack + background + detents + drag indicator) where the consolidated
   `LogSheet` already presents that mode.

### 6. Behaviour Preservation and Dead Code

**User Story:** As the developer, I want the extraction provably inert, so review can check
structure moved and nothing else.

**Acceptance Criteria:**

1. <a name="6.1"></a>No user-visible affordance SHALL be added or removed by this spec; every
   correction, save, and deletion path SHALL persist exactly what it persists today.
2. <a name="6.2"></a>`MealHistoryModel` (instantiated only by documentation-contract tests;
   superseded by `RecordsModel`) SHALL be removed, along with its pbxproj registration.
3. <a name="6.3"></a>`make build-app`, `make test` (both totals) and `make spell` SHALL pass;
   the on-device look confirming each surface renders as before is the closing human gate.

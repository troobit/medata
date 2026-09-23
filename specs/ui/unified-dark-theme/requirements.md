# Requirements: Unified Dark Theme

## Introduction

The app renders in two palettes that were specified as a deliberate split: the OLED capture
family (`captureBackground` pure black — Photo tab, `ResultView`, `MealReviewView`) and the
adaptive grouped family (`surfacePrimary` = `.systemGroupedBackground` — Home, Intake, Records,
Meal overview, Settings, every sheet). Nothing anywhere forces a colour scheme, so on a
device set to light appearance the grouped family resolves near-white, and one Records
navigation stack reads light-grey list → light-grey overview → black result, flipping palette
mid-push. This spec unifies the app on a single dark presentation.

The unification exploits a property the token set already has: under a dark scheme,
`.systemGroupedBackground` resolves to pure black and `.secondarySystemGroupedBackground` to
`#1C1C1E`, so the two palettes converge rather than needing to be merged. The grouped family
survives as *structure* (base vs elevated card), no longer as a light/dark split.

**Mode: iterative** (PROCESS.md §5) — the acceptance bar is a device look against the targets
below; the decision log carries convergence state. A small `tasks.md` exists because discrete,
separable steps do exist.

## Non-Goals

- **No per-view repainting onto the capture palette.** `surfacePrimary`/`surfaceElevated`/
  `textPrimary`/`textSecondary` remain the tokens of grouped surfaces; they simply always
  resolve dark. Views are not rewritten onto `captureChromeText`.
- **No new colour tokens.** The existing set covers every surface.
- **No light theme, and no appearance setting.** One presentation. If a light theme is ever
  wanted, the adaptive tokens make it a one-line revert, which is the reason they survive.
- **No layout changes.** This spec moves colour resolution only; layout parity is
  [`specs/ui/shared-meal-components`](../shared-meal-components/requirements.md).

## Requirements

### 1. One Dark Presentation

**User Story:** As the developer, I want every screen dark, so that moving between capture,
records and detail never flashes a white surface and the app reads as one product.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL present every surface in dark appearance regardless of
   the device's system appearance setting: no screen, cover, sheet, or pushed view SHALL
   render a light background in any flow.
2. <a name="1.2"></a>The Records navigation stack — list → meal overview → full result —
   SHALL present a single dark continuum with no palette flip at any push boundary.
3. <a name="1.3"></a>The OLED capture family (`captureBackground` and its chrome tokens)
   SHALL be unchanged: the capture flow, `MealReviewView`, and `ResultView` render
   byte-identically to today.
4. <a name="1.4"></a>The mechanism SHALL be a single declaration at the application root, not
   per-view modifiers, so a future surface cannot miss it.
5. <a name="1.5"></a>Adaptive tokens SHALL remain adaptive: no token defined via a UIKit
   semantic colour SHALL be replaced by a hard-coded dark value.

### 2. Contrast and Legibility

**User Story:** As the developer, I want the dark unification to hold the existing contrast
budget, so that nothing becomes less readable in the name of consistency.

**Acceptance Criteria:**

1. <a name="2.1"></a>All text SHALL meet a contrast ratio of at least 4.5:1 against its
   resolved dark background (`design-system/MASTER.md` contrast budget; system semantic
   colours satisfy this by construction).
2. <a name="2.2"></a>Components that hard-code capture-palette colours and also appear on
   grouped surfaces (`ConfidencePill`'s `captureChromeText` foreground) SHALL be legible on
   the resolved dark grouped surfaces without modification, and this SHALL be confirmed in
   the device look rather than assumed.
3. <a name="2.3"></a>The accent (`medataAccent` `#63FF00`) SHALL remain the single
   accent-per-screen and SHALL keep its `captureBackground` foreground treatment on filled
   controls.

### 3. Design-System Reconciliation

**User Story:** As the developer, I want the written design system to say what the app now
does, so that the next surface is designed against the real rule rather than the superseded
split.

**Acceptance Criteria:**

1. <a name="3.1"></a>`design-system/MASTER.md`'s style table SHALL be amended in place: the
   "Dark Mode (OLED)" row's scope becomes app-wide, and the grouped-token block SHALL be
   annotated as structural (base vs elevated), not as a light family.
2. <a name="3.2"></a>`design-system/pages/meal-overview.md` and `design-system/pages/data.md`
   SHALL be annotated where they specify light grouped surfaces, citing this spec's decision
   log, without deleting the original text.
3. <a name="3.3"></a>A `design-system/pages/records.md` page doc SHALL exist for
   `RecordsView`, which currently has no page doc — `data.md` still describes the retired
   Data screen.
4. <a name="3.4"></a>`design-system/MASTER.md`'s colour block SHALL be brought level with
   `App/Colors.swift` (it omits `seriesInsulinBolus`, `seriesInsulinBasal`, `seriesActivity`,
   `bandActivity`, `separatorSubtle` and the confidence very-low tone), discharging the
   documentation debt `specs/data/insulin-dosing/design-direction.md` §7 records: "That
   block should be brought level."

## Acceptance band (iterative target)

The loop stops when, on the iPhone 16 Pro: every route from Home (Capture, Intake, Dose,
Records, Graph, Settings, and each of their sheets and pushes) shows a dark background; the
Records → overview → result chain shows no flip; and the capture flow is visually unchanged.
Near enough is not good enough on Req 1.1 — a single light surface fails the bar — but
tonal differences between pure black and `#1C1C1E` cards are the intended structure, not a
defect.

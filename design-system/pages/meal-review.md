# Meal review — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The single post-capture review surface
(`MealReviewView` + `MealReviewModel`), pushed via `CaptureRoute.result` the
moment estimation completes — no interaction sits between the estimate finishing
and this surface appearing (meal-review Req 1.2). It replaces
`segmentation-review.md` (page retired) and the just-captured presentation of
`result.md`, which is now scoped to the Records/Graph history read path.

**Brief:** One screen that shows what was detected and lets you fix it. The
photo with its detected foods outlined, the live total, one editable row per
food, and a single-tap Record action. This page is the written target the
surface is iterated against (PROCESS §5): corrections must be cheap enough that
they happen — an unmodified estimate records in exactly one tap (Req 7.5), and
every correction is persisted the moment it is made, so the primary action only
dismisses.

---

## Layout zones

```
┌─────────────────────────────────────┐
│  ‹ back                        ⋯    │  Inline nav. ⋯ menu = Retake + Delete —
│  ┌───────────────────────────────┐  │  both discard the recorded meal (Req 1.3)
│  │    photo + outlines + ①②③     │  │  ~40% height, fixed. 4:3 .fit, rounded 16pt
│  └───────────────────────────────┘  │
│  47 g carbs  (corrected)  ▮ High ▮  │  Total + corrected marker + confidence pill,
│                                     │  one line (Req 1.4, 8.6)
│  ┌───────────────────────────────┐  │
│  │          Record 47 g          │  │  Primary action — records as displayed,
│  └───────────────────────────────┘  │  dismisses; figure tracks corrections live
│  PLATE      [All] [¾] [½] [¼]       │  Whole-meal scale — above the fold (Req 6.6)
│  ───────── scroll boundary ──────── │
│  ⚠ Uncalibrated · Unknown region ˅  │  Accessory signals, ONE expandable line
│  ① White rice        28 g carbs     │  Food rows — grouped-row metrics on the
│    ≈ 2 scoops · 70 g   − + ⇄ ✕      │  capture palette
│  ② R̶i̶c̶e̶ → Couscous    24 g carbs    │  Relabelled: predicted struck through,
│    180 g               − + ⇄ ✕      │  corrected name carries the row
│  ③ P̶l̶a̶t̶e̶ ̶r̶i̶m̶             Restore    │  Rejected remnant — de-emphasised, reversible
└─────────────────────────────────────┘
```

**The above-the-fold rule.** Photo, total, primary action and the scale control
never scroll; the accessory line and the food rows scroll below the boundary.
The accessory signals collapse to a single expandable line precisely so a meal
carrying all of them cannot push the scale control off-screen.

**The σ < 0.20 exception.** When meal confidence is very low, the very-low
surface replaces the scale control above the boundary and owns the fold: two
lines of copy ("This estimate may be wrong by orders of magnitude." + the
capture-angle line) and two 44 pt buttons, `Retake` (outline) and `Keep as-is`
(chip). A retake decision precedes any adjustment, so Req 6.6's guarantee is
suspended in this one state; `Keep as-is` restores the scale control for the
rest of the session. This is the sole exception `prerequisites.md` cannot treat
as a pure layout check.

---

## Photo, outlines and badges

- **Outline, not fill (Decision 7).** Each detected food's areas are stroked at
  2 pt in the class colour from the deterministic id→colour table — the pixels
  inside stay unobscured (Req 2.1). Contours are emitted only for classes
  present in `macros.perClass` (Req 2.8); the unknown-region and
  unsupported-liquid banners key off raster presence instead, so they survive
  the emission rule.
- **Numbered badge = the non-colour identity channel (Req 2.3).** A 22 pt
  circle at the largest contour's centroid, `caption2` bold monospaced digit on
  `captureScrim`, ringed in the class colour, matching the number on the food's
  row. This — not stroke colour — is what keeps adjacent foods distinguishable
  under Differentiate Without Colour (Req 2.2).
- **Selection (Req 2.4, 2.5).** Tapping a marked area selects the food and its
  row; tapping a row selects the food and all its areas. Selection dims outside
  the selected class with `captureScrim` via an even-odd path, leaving the
  selected areas the highest-contrast content. Selection alone never opens the
  relabel alternatives (Req 2.7). A miss deselects.
- **Rejected treatment (Req 4.2).** Stroke drops to 1 pt at 0.5 opacity, the
  badge is struck through, and the row moves to a de-emphasised remnant carrying
  the predicted name struck through and a `Restore` affordance (Req 4.3).
- **Relabelled treatment (Req 3.10).** The row shows predicted struck through →
  corrected in `.headline`; the badge keeps the outline join.
- **Fallbacks (Req 1.6).** No photo → `fork.knife` glyph on `captureChromeBG`;
  no mask → photo without outlines. Neither errors nor blocks recording.
- **Accessibility (Req 2.6, 10.4).** A shadow layer exposes one VoiceOver
  element per detected food (named, activation selects) with
  `.contentShape(.accessibility, …)` so the focus ring follows the contour, not
  a bounding box. Where a food's largest contour is under 44 pt, its row is the
  hit target.

---

## Specifics

- **Background:** `captureBackground` (OLED). Colour from `App/Colors.swift`
  tokens only (Req 10.2).
- **Total row:** 44 pt heavy `monospacedDigit` total + `g carbs` suffix at 0.7
  opacity, `.numericText()` transition (skipped under Reduce Motion). A small
  `corrected` capsule appears once any actual correction exists (Req 8.6);
  the four-tier `ConfidencePill` sits trailing on the same line.
- **Primary action (Req 7.1–7.3):** one prominent `medataAccent` button,
  48 pt, labelled `Record N g` where N reflects every correction live. No
  confirmation step, no log pill, no second action between it and the meal
  being recorded (Req 7.4) — corrections are already persisted, so it only
  dismisses.
- **Whole-meal scale (Req 6.3–6.5):** `PLATE` label + `PlateFraction` capsule
  stops (`All`, `¾`, `½`, `¼`) — fractions of the estimate at or below one, so
  the leftovers case is one tap. Applies to each row's currently derived
  amount (post-relabel), never compounds; a row carrying a user-set mass scales
  from that mass. Correcting upward goes through the per-food controls, which
  are not capped at the measured volume.
- **Accessory line (Req 1.4, 1.5):** calibration state, liquid over-estimate,
  unknown region and unsupported liquid collapse to one expandable
  `confidenceModerate`-at-0.85 line, icon + text, never colour alone.
  Expanding reveals one chip per signal with its full copy.
- **Food rows (Req 10.1):** `IntakeView`'s grouped-row metrics restated on the
  capture palette — `RoundedRectangle(cornerRadius: 12)` on `captureChromeBG`,
  12 pt vertical padding, `.headline` name over `.caption.monospacedDigit()`
  figures. Line one: badge, name, trailing `N g carbs`. Line two: the amount
  affordance (`≈ 2 scoops · 70 g`, tap to reveal the gram keypad — serving-adjust
  items 1 and 3 unchanged), then `−` / `+` steppers, relabel (`⇄`) and reject
  (`✕`), each a 44 pt circle. Row order is fixed at init and never re-sorts
  (Req 6.10).
- **Relabel sheet (Req 3, 5):** a system-grouped sheet, three sections in
  order: the prominent `Not in the database` action first (the common case on
  a 25-class palette — Req 5.1), then `Recent` — the recency shortlist, at most
  five, no scores or confidence tiers (Req 3.2) — then `All foods` behind a
  plain text filter (Req 3.4). Candidates are only foods with both a density
  and a coefficient; no solid↔liquid relabel.
- **⋯ menu:** `Retake` and `Delete` (destructive). Both discard the recorded
  meal and stamp `capture_abandoned` on every correction row first (Req 1.3).

---

## Anti-patterns

- Do NOT fill detected areas with a tinted raster — outline only; the pixels
  are the evidence (Decision 7).
- Do NOT show per-food confidence, scores or percentages anywhere, including
  the relabel shortlist (design-handoff-00 Decision 16; Req 3.2).
- Do NOT add a confirmation, log pill or satisfaction prompt between the
  primary action and the meal being recorded (Req 7.4).
- Do NOT carry the placeholder chip here — under `DEV_STUB_SEGMENTER` it would
  be permanently present in every Debug build; the segmenter source is already
  on each correction record (Req 9.8).
- Do NOT offer boundary editing — no brush, lasso or expand/contract; boundary
  error is absorbed by amount correction (Decision 4).
- Do NOT re-sort rows on relabel, rejection or amount change (Req 6.10).
- Do NOT add reassurance, disclaimer or data-preservation copy (Req 10.7).

---

## Pre-delivery checklist (meal review additions)

Device acceptance lives in `specs/ui/meal-review/prerequisites.md` (layout,
interaction cost, legibility, accessibility, durability, corpus). Before
handing over:

- [ ] Scale control visible without scrolling on a meal carrying all accessory
      signals and four or more foods (Req 6.6 worst case)
- [ ] Unmodified estimate records in exactly one tap (Req 7.5)
- [ ] Two foods distinguishable with Differentiate Without Colour enabled
- [ ] Push transition shows no dropped frames with the contour decode active
      (the `Canvas` fallback applies if it does)

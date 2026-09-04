# Result — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The §6 Result screen, scoped to the
Records/Graph **history read path only** (`ResultView`, pushed via
`MealRoute.result`). Supersedes the `photo-tab.md` §"ResultView" section. The
just-captured presentation is superseded by
[`meal-review.md`](meal-review.md) (specs/ui/meal-review, 2026-08-09): the
fresh-capture Retake action and the very-low retake surface moved there, and
`ResultPresentation` is gone from the view.

**Brief:** One number the user can act on, with the evidence beneath it. The hero
carb total dominates; a summary card and per-food breakdown make the estimate
checkable without leaving the screen.

---

## Layout

```
┌─────────────────────────────────────┐
│              47 g carbs              │  Hero — display weight number + `g carbs` suffix
│             ▮ High ▮                 │  Confidence pill (four-tier, Decision 5)
│      ╭─ Placeholder estimate ─╮      │  Placeholder chip — only when dev_stub
│                                      │  (calibration banner / liquid flag render
│                                      │   here when applicable)
│  ┌─────┐  3 foods                    │  Summary card
│  │ 🍽  │  128 g total                │  thumbnail · N foods · N g total · CoFID + AFCD
│  └─────┘  CoFID + AFCD               │
│                                      │
│  Per food                            │  Breakdown header
│  White rice     70 g · 90 cm³ · 28 g carbs
│  Chicken        58 g · 55 cm³ · 0 g carbs
│                                      │
│  ┌ Protein — soon ┐ ┌ Fat — soon ┐   │  Dashed disabled macro placeholders
│  └────────────────┘ └────────────┘   │
│  ┌──────────────────────┐  ┌───┐      │  Action row (pinned bottom)
│  │         Done         │  │ ⋯ │      │
│  └──────────────────────┘  └───┘      │
└─────────────────────────────────────┘
```

Content scrolls; the action row is pinned to the bottom.

---

## Specifics

- **Background:** `captureBackground` (OLED). The thumbnail lives in the summary
  card, not as a full-bleed backdrop.
- **Hero (§6.1):** carb total rounded to 1 g at the `display` scale
  (72pt, clamp 56–88), `monospacedDigit`, white, with a `g carbs` suffix in
  `title3` at 0.7 opacity, baseline-aligned. `.numericText()` transition (skipped
  under Reduce Motion). The value that matches what the user is eating (snaqui
  Req 1, superseding the original-only hero): a live preview while adjusting,
  else the corrected total when one is recorded — with the original estimate
  on the line beneath whenever they differ. Relabelled foods are named by their
  corrected class (meal-review Req 8.7).
- **Confidence pill (§6.2):** existing four-tier `ConfidencePill` (High / Moderate
  / Low / Very Low), icon + colour. The very-low retake surface (σ < 0.20) lives
  on the review surface (`meal-review.md`); here only the pill's Very Low tier
  shows — its retake button was already inert from history.
- **Summary card (§6.3):** `captureChromeBG` rounded rectangle. 64pt thumbnail
  (rounded 12pt) with the §6.8 fallback — a `fork.knife` glyph on `captureChromeBG`
  when the photo asset is unavailable. Beside it: `N foods` (headline),
  `N g total` (subheadline, monospaced — sum of per-class mass), `CoFID + AFCD`
  (caption).
- **Breakdown (§6.4):** `Per food` header, then one row per class sorted by carbs
  descending: prettified name (`white_rice` → `White rice`) and a monospaced
  `mass g · volume cm³ · carbs g carbs` trailing line. No σ (Decision 16).
- **Macro placeholders (§6.5):** two dashed, disabled capsules `Protein — soon` /
  `Fat — soon`, 0.5-opacity white text and a dashed 0.3 white border, holding
  layout space.
- **Action row (§6.6/6.7, Decision 17; revised by serving-adjust and
  meal-review):** `Done` (prominent `medataAccent`) plus a ⋯ `Menu` holding
  `Delete` only. `Adjust` was retired by the serving-adjust PRD — the per-food
  serving rows above are the adjustment surface — and the fresh-capture
  `Retake` lives on the review surface (`meal-review.md`), not here.
- **Safety surfaces:** calibration banner (full / softened), liquid
  over-estimate flag, placeholder chip — all reused from the
  research/model-production contracts. The very-low retake surface is on the
  review path only.

---

## Anti-patterns

- Do NOT hide the original estimate once a corrected total leads the hero — the
  estimated line beneath keeps the prediction visible (meal-review Req 8.1).
- Do NOT show per-class σ or per-class confidence (Decision 16).
- Do NOT render Protein/Fat with real numbers — placeholders only (out of scope).
- Do NOT hide the action row in history (deliberate change from tab era).
- Do NOT add correction affordances here — relabel, reject and absent-food live
  on the review surface only; correcting from Records is a meal-review Non-Goal.

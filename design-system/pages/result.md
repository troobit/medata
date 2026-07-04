# Result — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The §6 Result screen. Supersedes the
`photo-tab.md` §"ResultView" section.

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
│                                      │  (calibration banner / liquid flag / very-low
│                                      │   surface render here when applicable)
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
│  ┌────────┐ ┌────────┐  ┌───┐         │  Action row (pinned bottom)
│  │ Adjust │ │  Done  │  │ ⋯ │         │
│  └────────┘ └────────┘  └───┘         │
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
  under Reduce Motion). Always the **original** estimate — corrected totals
  surface in Data / Overview, not here (Req 7.3).
- **Confidence pill (§6.2):** existing four-tier `ConfidencePill` (High / Moderate
  / Low / Very Low), icon + colour. The very-low surface (σ < 0.20) is preserved.
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
- **Action row (§6.6/6.7, Decision 17):** `Adjust` (bordered, → Manual
  correction) and `Done` (prominent `medataAccent`), shown in **both**
  presentations (historyDetail showing the row is a deliberate change). A ⋯
  `Menu`:
  - `.justCaptured`: `Retake` + `Delete` (both discard the persisted meal via
    `model.deleteAndDismiss` and return to Capture).
  - `.historyDetail`: `Delete` only (no Retake).
- **Safety surfaces (unchanged):** calibration banner (full / softened), liquid
  over-estimate flag, very-low retake surface, placeholder chip — all reused
  from the research/model-production contracts.

---

## Anti-patterns

- Do NOT show a corrected total in the hero — the hero is the original estimate.
- Do NOT show per-class σ or per-class confidence (Decision 16).
- Do NOT render Protein/Fat with real numbers — placeholders only (out of scope).
- Do NOT hide the action row in historyDetail (deliberate change from tab era).

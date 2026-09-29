# Correction — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The §7 Manual correction screen, pushed
via `CaptureRoute.correction` (capture stack) or `MealRoute.correction`
(Data / Trends sheet stacks).

**Brief:** Correct an estimate without losing the original. The correction is
stored alongside the estimate (never overwrites it — Req 7.2); the record stays
honest and the original remains retrievable.

---

## Layout

```
┌─────────────────────────────────────┐
│  Adjust                       ‹ back │  Inline nav title
│                                      │
│  TOTAL CARBS                         │  Section label (caps)
│  47 g                    ‹  −  +  ›  │  Stepper (whole grams)
│  was 52 g                            │  Prior value being corrected from
│                                      │
│  White rice          28 g   ‹ − + › │  Per-food edits (grams)
│  Chicken              0 g   ‹ − + › │
│  Broccoli             4 g   ‹ − + › │
│                                      │
│  ┌───────────────────────────────┐   │  Note field (optional, multi-line)
│  │ Note                          │   │
│  └───────────────────────────────┘   │
│  Original kept · correction saved …  │  Preservation notice
│                                      │
│  ┌───────────────────────────────┐   │  Save (pinned bottom)
│  │             Save              │   │
│  └───────────────────────────────┘   │
└─────────────────────────────────────┘
```

Content scrolls; `Save` is pinned to the bottom.

---

## Specifics

- **Background:** `captureBackground` (OLED).
- **Total stepper (§7.1):** `TOTAL CARBS` caps label (0.6-opacity caption), a
  whole-gram `Stepper` (`title2` bold monospaced value, `medataAccent` tint,
  range 0–1000). Beneath it, `was N g` (0.6-opacity monospaced caption) — the
  value being corrected **from**: the latest stored correction's total if one
  exists, else the original estimate (`store.corrections(for:)`).
- **Per-food edits (§7.1):** one `Stepper` per detected class (sorted by carbs
  descending, matching Result / Review): prettified name + trailing `N g`, whole
  grams, range 0–1000. Seeded from the original per-class carbs, overridden by the
  latest correction's `correctedPerClass` where present.
- **Note (§7.1):** an optional multi-line `TextField` placeholdered `Note` on a
  `captureChromeBG` rounded field. Whitespace-only notes are dropped on save.
- **Preservation notice (§7.2):** `Original kept · correction saved alongside`
  (0.6-opacity caption). Minimised copy — no exemption; this is not safety copy.
- **Save (§7.3, Decision 18):** prominent `medataAccent` `Save`. Builds a
  `PbUserCorrection` (`createdAtMs`, `correctedTotalCarbsG`, `correctedPerClass`,
  optional `note`), calls `store.appendCorrection` — which now emits
  `eventsDidChange` so Data rows and Meal overview re-read the corrected total —
  then `onSave` pops one level back to whichever screen pushed it.

---

## Anti-patterns

- Do NOT overwrite or mutate the original estimate — corrections are additive
  (Req 7.2); the Result hero always shows the original.
- Do NOT block Save on a note or on changed values — a correction may confirm the
  estimate.
- Do NOT surface the corrected total in the Result hero — corrected totals appear
  in Data / Overview via the `corrected` marker (Req 7.3).

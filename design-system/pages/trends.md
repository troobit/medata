# Trends — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The §10 Trends screen. Uses the two new
tokens `seriesGlucose` (systemOrange) and `bandTarget` (medataAccent 10 %,
Decision 12).

**Brief:** Carb intake charted against the glucose curve on one chart, so a user
can see how meals move their levels. Day plots per-meal carb bars against the raw
glucose line; Week and Month aggregate to per-day totals and averages.

---

## Layout

```
┌─────────────────────────────────────┐
│  Trends                        ⇅    │  Inline title · options button
│  ┌ Day │ Week │ Month ┐             │  Range segmented control
│  ┌─────────────────────────────────┐ │
│ mmol/L        ░░ target band ░░   g │  Leading axis mmol/L · trailing axis grams
│  │  ╱╲   ▮   ╱╲                    │ │  Glucose line (orange) + carb bars (green)
│  └─────────────────────────────────┘ │
│  ▮Carbs▮ ▮Glucose▮ ┆Protein · Fat┆   │  Metric chips (Protein · Fat dashed/disabled)
│  ┌──────────┐ ┌──────────┐           │
│  │Total carbs│ │Avg/day   │          │  Stat cards
│  │In range   │ │Avg glucose│         │
│  └──────────┘ └──────────┘           │
│  Meals                              │  Day-view meal list (→ overview)
│  14:32                       47 g  › │
│                                      │
│  Glucose is read-only. Medata never │  Safety footer (verbatim)
│  writes to your glucose source.     │
└─────────────────────────────────────┘
```

---

## Specifics

- **Container:** `ScrollView` on `surfacePrimary`, own `NavigationStack`. Title
  `Trends`, inline. Options button (`slider.horizontal.3`) presents the options
  sheet.
- **Range control (§10.1):** segmented `Day` / `Week` / `Month`; changing it
  reloads the model.
- **Chart (§10.2/§10.3):** `import Charts` (target 26.5, no guards). One shared
  y-scale (single-scale workaround). The **leading** axis is glucose in mmol/L to
  one decimal (`seriesGlucose` `LineMark`, `catmullRom`). Carb `BarMark`s
  (`medataAccent`) are mapped onto the shared axis via
  `TrendsMath.mapCarbsToAxis`, and the **trailing** axis is relabelled to grams
  via `TrendsMath.mapAxisToCarbs`. `carbAxisMax = max(80, ceil(maxCarbs/20)*20)`
  so the tallest bar never clips (§10.2, no fixed cap). A translucent `bandTarget`
  `RectangleMark` marks 3.9–10.0 mmol/L. Day: per-meal bars + raw glucose line.
  Week/Month: per-day carb totals + per-day average glucose (empty days dropped
  from the line).
- **No-glucose state (§10.9):** an unobtrusive `no glucose data` label overlays
  the chart's top-trailing corner; the carb series still renders. Never an error.
- **Metric chips (§10.4):** `Carbs` and `Glucose` toggle their series (filled
  `medataAccent` when on). `Protein · Fat` is a dashed, disabled capsule.
- **Stat cards (§10.5):** `Total carbs`, `Avg carbs/day`, `In range`,
  `Avg glucose`. In range is `TrendsMath.timeInRange` (time-weighted, gaps > 60
  min excluded) shown as a percentage, `—` when nil. Avg glucose is one decimal
  mmol/L, `—` when there are no readings.
- **Day meal list (§10.6):** `Meals` header, rows `HH:mm · N g` opening
  `MealRoute.overview`; empty state `no meals`. Shown only in the Day range.
- **Footer (§10.7, ⚖):** exactly `Glucose is read-only. Medata never writes to
  your glucose source.` — safety copy, exempt from minimal wording.
- **Glucose source (§11):** read exclusively from `bsl` events, mmol/L, one
  decimal.

---

## Options sheet (§10.8)

Title `Options`; a `Done` button dismisses. Persists via `@AppStorage`
(`SettingsKeys.trends*`), so the sheet and the chart share one state.

- **Metrics:** `Carbs` (caption `bars · meals`) and `Glucose` (caption
  `line · glucose import`) toggles; a disabled `Protein · Fat` row (caption
  `soon`).
- **Target band:** a `Target band` toggle with the subtitle `3.9–10.0 mmol/L`.
- **Scale:** `Auto` / `Fixed` segmented control; when Fixed, a `Max` stepper
  (8–25 mmol/L) sets the glucose axis maximum.

---

## Anti-patterns

- Do NOT clip carbs at a fixed maximum — the carb axis is dynamic (§10.2).
- Do NOT surface an error when glucose is absent — render carbs with the
  `no glucose data` state.
- Do NOT reword the read-only footer — it is verbatim safety copy.
- Do NOT show mg/dL — glucose is mmol/L only (units invariant).

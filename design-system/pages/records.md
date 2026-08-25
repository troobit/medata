# Records — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The unified Records surface
(`App/RecordsView.swift`). Supersedes `data.md` for this surface: Records
replaced the retired Data screen (home-router: Records replaces Data) and
carries every event type, not only meals.

**Brief:** One chronological timeline of everything recorded — meals, insulin
doses, glucose readings, manual intakes, activity — most-recent-first, no
filtering or windowing. The list is also the primary deletion surface
(`specs/ui/records-deletion`). Meal rows open the Meal overview; every other
row type is a terminal instrument.

---

## Layout

```
┌─────────────────────────────────────┐
│  ✕                    Select    ⋯   │  Untitled, inline · edit toggle · menu
│                                      │
│  🍴 47 g carbs  ≈ 214 g   corrected  │  Meal row → Meal overview
│     25 Aug 2026, 14:32               │
│  💉 12 U  Bolus                      │  Insulin row (no navigation)
│     25 Aug 2026, 13:58               │
│  💧 6.2 mmol/L                       │  Glucose row (no navigation)
│     25 Aug 2026, 13:40               │
│  🥕 30 g  Quick add                  │  Intake row (no navigation)
│     25 Aug 2026, 11:05               │
│  🏃 Walk  45 min                     │  Activity row (no navigation)
│     25 Aug 2026, 09:20               │
└─────────────────────────────────────┘
```

(Glyphs shown as emoji only in this sketch — the rows use SF Symbols.)

---

## Specifics

- **Container:** a bare grouped `List` inside its own `NavigationStack`
  (one-stack-per-sheet rule). Deliberately untitled, inline display mode, so
  no large-title band is reserved. The list carries no background modifier:
  it resolves dark through `UIUserInterfaceStyle = Dark`
  (`specs/ui/unified-dark-theme` Decision 1) — black base, `#1C1C1E` cards.
- **Five row types**, each a leading 20pt-frame SF Symbol glyph, a headline
  value line, and a caption timestamp (`en_IE`, medium date + short time):
  - **Meal** — `fork.knife` in `textSecondary`. Value line is the corrected
    carb total plus the estimated plate mass: `47 g carbs · ≈ 214 g`
    (carbs headline monospaced, mass subheadline in `textSecondary` —
    `specs/ui/mass-readout`: the number a kitchen scale can validate beside
    the one it cannot). A `corrected` capsule trails when a correction
    exists.
  - **Insulin** — `syringe` tinted `seriesInsulinBolus` (teal) or
    `seriesInsulinBasal` (purple) by kind. `12 U` + `Bolus`/`Basal`.
  - **Glucose** — `drop.fill` in `seriesGlucose`. `6.2 mmol/L`
    (metric-only, one decimal).
  - **Intake** — `carrot` in `textSecondary`. Display value + type label
    (manual / quick add).
  - **Activity** — the kind's own symbol in `seriesActivity`. Kind label +
    duration `45 min`; an unrecorded duration shows nothing at all — absent
    and zero are different facts.
- **Deletion (`specs/ui/records-deletion`):** the list is the primary
  deletion surface, with the standard iOS patterns on every row type:
  - Swipe-to-delete on all five row types — the revealed Delete button is
    the confirmation, no extra dialogue. Glucose rows included: deletable
    since records-deletion ("This supersedes home-router Req 3.5 (glucose
    read-only)").
  - Edit-mode multi-select via a `Select`/`Done` toolbar button: selection
    checkmarks, a bottom bar with `Select All` / `Deselect All` and a
    destructive `Delete (n)` behind a count-naming confirmation dialogue.
  - `⋯` menu → `Delete by Date…`: a From/To picker sheet with a live
    in-range count and a confirmed destructive delete through the same
    batched store path.
  - `⋯` menu → `Delete All Records…`: one-tap full-history purge behind a
    total-count-naming confirmation ("Clearing debug-era records must not
    require picker work" — records-deletion smolspec).
- **Navigation:** a meal row pushes `MealRoute.overview` → Meal overview;
  its `Full result` action pushes `MealRoute.result` → the full ResultView
  (shared `mealRouteDestination`, `App/MealRouting.swift`). No other row
  type navigates. (A DEBUG-only `⋯ → Review` route on the overview reopens
  the review surface without a capture.)
- **Dose-suggestion line (history surfaces):** where a recorded suggestion
  exists for a meal, the overview and result screens pushed from here render
  it under the carb total as a zero-tap read-only line —
  `suggested 12 U · 5 g/U`, gaining `· given 14 U` once a dose is linked —
  per `specs/data/insulin-dosing` Req 6.10: "the meal detail surfaces
  reached from history … SHALL render it as a zero-tap read-only value
  alongside the carbohydrate total, in the same derived register and
  middle-dot grammar as the review surface". `textSecondary`, monospaced
  digits, never accent.

---

## Anti-patterns

- Do NOT navigate from insulin, glucose, intake, or activity rows — only
  meal rows push.
- Do NOT open the full Result from a meal row — the row opens the Meal
  overview; Result is one more push away.
- Do NOT add a confirmation dialogue to swipe-delete — the revealed Delete
  button is the confirmation. Bulk, date-range, and delete-all keep theirs.
- Do NOT render `0 min` for an activity with no recorded duration — absence
  renders nothing.
- Do NOT give the list a navigation title or a large-title band.
- Do NOT style the dose-suggestion line as a control or in accent — it is a
  derived readout, not a call to action (`specs/data/insulin-dosing`
  design-direction §8).

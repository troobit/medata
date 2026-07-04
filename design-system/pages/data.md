# Data — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The §8 Data (meal log) screen.
Supersedes `meals-tab.md` (feed-style photo cards → anonymous grouped rows).

**Brief:** A plain chronological log of every capture, grouped by day. Rows are
anonymous instruments — thumbnail, time, carbs, confidence — with no meal names.
A row opens the Meal overview, never the full Result.

---

## Layout

```
┌─────────────────────────────────────┐
│  Data                               │  Sheet title (own NavigationStack)
│                                      │
│  Today                              │  Day header — Today / Yesterday / date
│  ┌──┐ 14:32                          │  Row: thumbnail · time
│  │🍽│ 47 g  corrected      ▮ High ▮  │       carbs (corrected total + marker) · pill
│  └──┘                                │
│  ┌──┐ 08:10                          │
│  │🍽│ 31 g                ▮ Low ▮    │
│  └──┘                                │
│                                      │
│  Yesterday                          │
│  ┌──┐ 19:45                          │
│  │🍽│ 62 g             ▮ Moderate ▮  │
│  └──┘                                │
└─────────────────────────────────────┘
```

Empty state (no meals): a centred `fork.knife` glyph and `No meals yet`.

---

## Specifics

- **Container:** system grouped `List` (`.insetGrouped`) on `surfacePrimary`,
  inside the sheet's own `NavigationStack`. Title `Data`, inline.
- **Day grouping (§8.1):** one `Section` per calendar day, newest first. Header
  is `Today` / `Yesterday` / a medium-format date (`en_IE`). Rows within a day
  stay in store order (newest first).
- **Row (`DataRow`, §8.2):** 44pt rounded (10pt) thumbnail with the §6.8 fallback
  (`fork.knife` on `surfaceElevated`); time (`HH:mm`, subheadline); carbs as a
  monospaced headline in grams — the **corrected total** when a correction exists,
  otherwise the original estimate — with a small `corrected` marker capsule; the
  four-tier `ConfidencePill` trailing. No meal name (Req 8.2).
- **Correction composition (critic R2):** `MealHistoryModel.reload()` folds each
  meal's corrections into a `DisplayMeal` value (record + corrected total +
  corrected flag). A value-identical `MealRecord` refetch would diff as unchanged,
  so the composed struct is what makes `eventsDidChange` (which now fires on
  `appendCorrection` — Decision 18) invalidate the row.
- **Navigation (§8.3):** a row pushes `MealRoute.overview` → Meal overview, not
  the full Result.
- **Empty state (§8.5):** `No meals yet` — never a blank list.

---

## Anti-patterns

- Do NOT show a meal name or a photo-led card (that was the retired `meals-tab`).
- Do NOT open the full Result on a row tap — open the Meal overview.
- Do NOT refetch bare `MealRecord`s for the rows — compose corrections in, or
  landed corrections will not repaint the carbs.

# Meals tab — page-specific overrides

**Inherits:** `design-system/MASTER.md`. This file specifies deviations and additions for the Meals tab (history list).

**Brief:** Feed-style row — the photo is the focal element, with carb total / confidence / timestamp as a caption below. List, not grid: macronutrient context (carb total, confidence) is essential and would be lost in a 3-col thumbnail grid.

---

## Layout — photo-led row

```
┌─────────────────────────────────────┐
│  Meals                              │  Top: large title ("title" style, weight 700, 28pt),
│                                     │  16pt below safe area top, 16pt leading.
│                                     │
│  ┌─────────────────────────────┐    │
│  │                             │    │  Row 1 — photo (full-width inside list inset, aspect 4:3).
│  │      meal photo             │    │  Rounded corners 14pt. Falls back to fork.knife SF Symbol
│  │                             │    │  on `surfaceElevated` if PHImageManager returns nil.
│  └─────────────────────────────┘    │
│  47 g    ▮ High 87% ▮    Placeholder │  Caption row, 12pt below photo, 16pt horizontal padding.
│  29 May 2026, 18:42                  │  Top line: carb (display-mono 24pt), pill, placeholder chip.
│                                     │  Bottom line: timestamp ("caption" style, secondaryLabel).
│                                     │
│  ┌─────────────────────────────┐    │  Row 2 — 24pt gap between rows (more breathing space than
│  │      meal photo             │    │  standard List default).
│  │                             │    │
│  └─────────────────────────────┘    │
│  ...                                 │
│                                     │
├─────────────────────────────────────┤
│   📷         🍴         ⚙           │  Tab bar — Meals selected.
└─────────────────────────────────────┘
```

---

## Specifics

### `MealsTabView` root

- `NavigationStack` with `.navigationTitle("Meals")` and `.navigationBarTitleDisplayMode(.large)`.
- List style: `.listStyle(.plain)` to drop the iOS list-row inset; we control insets per row.
- Background: `surfacePrimary` (system grouped, follows light/dark).

### `MealRow`

| Element | Spec |
|---|---|
| Photo | `AspectRatio(4/3, contentMode: .fit)`. Full-width minus 16pt leading + trailing. `.clipShape(RoundedRectangle(cornerRadius: 14))`. Loaded via `PHImageManager.requestImage(for: photoAssetID, targetSize: <2× current row width>, contentMode: .aspectFill, ...)`. Fallback: `surfaceElevated` background + centred `fork.knife` SF Symbol 32pt, `textSecondary`. |
| Carb total | `Text("\(Int(record.macros.totalCarbsG.rounded())) g")` — `.font(.system(size: 24, weight: .heavy, design: .default).monospacedDigit())`. Colour `textPrimary`. |
| Confidence pill | Reused `ConfidencePill(sigmaMeal:)` component (extracted in v1.1 task 36). Inline-spaced 12pt right of the carb total. |
| Placeholder chip | Conditional on `record.segmenterSource == "dev_stub"`. Same small pill as ResultView's placeholder chip — `placeholderBG` background, `placeholderFG` text, 12pt height, 8pt horizontal padding, capsule corners. 12pt right of the confidence pill. |
| Timestamp | `dd MMM yyyy, HH:mm` in `en_IE` locale. `caption` style, `textSecondary`. 4pt below the carb/pill row. |
| Row tap target | The whole row is one `NavigationLink(value: record)`. No internal interactive elements. Press feedback: `.scale(0.98)` over 100ms. |

### Swipe action — Delete

- `swipeActions(edge: .trailing, allowsFullSwipe: false)` — single button "Delete", SF Symbol `trash`, tint `.systemRed`.
- On tap: confirmation dialog ("Delete meal?" + "Cancel" / "Delete") per `confirmation-dialogs` rule.
- Delete confirmed: `await model.delete(record)`. Row animates out with the system list-row removal animation.

### Empty state

```
┌─────────────────────────────────────┐
│                                     │
│                                     │
│                                     │
│              🍴                     │  64pt SF Symbol fork.knife, textSecondary.
│                                     │
│       No meals yet                  │  title style, weight 700.
│                                     │
│  Tap the Photo tab to capture       │  body style, textSecondary, centred.
│  your first meal.                   │
│                                     │
│                                     │
│                                     │
├─────────────────────────────────────┤
│   📷         🍴         ⚙           │
└─────────────────────────────────────┘
```

Both lines Irish-English. Vertically centred in the available area between the top safe area and the tab bar.

### Detail view — reuses `ResultView` in `historyDetail` mode

Pushed via `.navigationDestination(for: MealRecord.self) { ResultView(record: $0, mode: .historyDetail) }`. Per `photo-tab.md`, the action row is hidden in `.historyDetail`. The detail view inherits the same OLED background, dimmed photo, and large carb total — visually consistent with what the user saw immediately after capture.

A "Delete" trailing toolbar item (`trash` SF Symbol) on the detail view's navigation bar offers the same destructive action as the swipe — confirmation dialog, then pop back to list on confirm.

---

## Anti-patterns specific to Meals tab

- Do NOT use a 3-column thumbnail grid — it hides the carb total and confidence, which are the point of the list.
- Do NOT show per-class breakdown, search, filter, or multi-select (Req §19.8).
- Do NOT use Liquid Glass on the rows — flat `surfacePrimary` background, rows are visually separated by the 24pt gap and the photo's rounded corners, not by elevation.
- Do NOT include a "Date captured" header above each photo — the timestamp below the metadata is enough.

---

## Pre-delivery checklist (Meals tab additions)

- [ ] Photo aspect ratio is 4:3, identical across all rows even when the source asset is portrait/square
- [ ] Carb-total `monospacedDigit` so the digits don't shift width when scrolling reveals new rows
- [ ] Placeholder chip appears IFF `segmenterSource == "dev_stub"`, regardless of build flag (per research Req §23.6)
- [ ] Swipe-to-delete confirms before destructive action (`confirmation-dialogs` rule)
- [ ] List virtualises rows (use SwiftUI `List`, NOT `LazyVStack` inside `ScrollView`, so the system recycles row views)
- [ ] Photo thumbnail request uses `2×` row width as `targetSize` (not maximum) to avoid memory spikes
- [ ] Empty-state fork-knife icon and copy are reachable by VoiceOver as a single grouped element
- [ ] Detail view's Delete and the swipe Delete both call the same `model.delete(record)`

# Meal overview — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The §9 Meal overview screen.

**Brief:** A compact recap of one meal — photo with mask overlays, one carb
total, and the per-food numbers — so the full Result is rarely needed. Reached
by tapping a Data or Trends row (`MealRoute.overview`).

---

## Layout

```
┌─────────────────────────────────────┐
│  Meal                          ⋯    │  Inline title · ⋯ menu (Delete)
│  ┌─────────────────────────────────┐ │
│  │         photo + mask overlay    │ │  §6.8 fallback: photo-only, then placeholder
│  └─────────────────────────────────┘ │
│  47 g carbs  corrected      ▮ High ▮ │  Compact total (+ marker) · confidence pill
│  1-view · LiDAR · 4 Jul 2026, 14:32  │  Capture-metadata line
│                                      │
│  Foods (3)                          │  Class header
│  ▮ White rice   70 g · 90 cm³ · 28 g carbs
│  ▮ Chicken      58 g · 55 cm³ · 0 g carbs
│                                      │
│  ┌────────┐ ┌─────────────┐          │  Action row
│  │ Adjust │ │ Full result │          │
│  └────────┘ └─────────────┘          │
└─────────────────────────────────────┘
```

---

## Specifics

- **Container:** `ScrollView` on `surfacePrimary`, pushed inside the sheet's
  `NavigationStack`. Title `Meal`, inline.
  *Amendment (`specs/ui/unified-dark-theme` Decision 1):* `surfacePrimary` now
  always resolves dark — `UIUserInterfaceStyle = Dark` pins the process dark,
  so this surface is pure black (`#000000`), never the light grouped grey.
- **Photo + masks (§9.1):** a 240pt rounded (16pt) card. `MaskOverlayLoader`
  (store + mealId) tints the persisted mask over the captured photo; when the
  mask artefact is absent the loader renders nothing and the photo shows through,
  and when the photo asset is absent a `fork.knife` placeholder shows (§6.8).
  Neither case errors.
- **Total + pill (§9.1):** compact 40pt monospaced total with a `g carbs` suffix
  — the corrected total when a correction exists — plus a `corrected` marker and
  the four-tier `ConfidencePill`.
- **Metadata line (§9.1):** `{1-view · LiDAR / 2-view} · {date, time}` from
  `capturePath` and `createdAt` (`en_IE`).
- **Per-class rows (§9.2, Decision 16):** `Foods (N)` header, then one row per
  class sorted by carbs descending: a 14pt mask-colour swatch (from
  `ClassColourTable`, keyed by the class's palette id — the same colour source as
  the overlay), the prettified name, and a monospaced `mass g · volume cm³ ·
  carbs g` line. **No σ.**
- **Corrections live (Decision 18):** the view re-reads `corrections(for:)` on
  every `eventsDidChange` tick while visible, so the marker and corrected total
  update the moment a correction lands.
- **Actions (§9.3):** `Adjust` (bordered → `MealRoute.correction`) and
  `Full result` (prominent `medataAccent` → `MealRoute.result`, ResultView
  `.historyDetail`). Delete lives in a ⋯ menu with a `Delete meal?` confirmation
  (`Delete` / `Cancel`) → `store.deleteMeal` then pop.

---

## Anti-patterns

- Do NOT show per-class σ or per-class confidence (Decision 16).
- Do NOT error when the mask or photo is missing — fall back per §6.8.
- Do NOT delete without the `Delete meal?` confirmation.

> **Superseded by meal-review** — this page is superseded by [`design-system/pages/meal-review.md`](meal-review.md) (specs/ui/meal-review, 2026-08-09). `SegmentationReviewView` is deleted; the single review surface replaces it. Content is preserved for history only; do not implement against it.

# Segmentation review — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The §5 Segmentation review screen,
pushed via `CaptureRoute.review` after the estimate completes.

**Brief:** A post-hoc look at what the estimate saw. The pipeline is NOT split
(Decision 7) — the estimate already ran during `.estimating`; this screen only
displays its masks and advances to Result. The primary action must not imply
estimation is still pending (Req 5.3).

---

## Layout

```
┌─────────────────────────────────────┐
│  Foods                        ‹ back │  Inline nav title
│  ┌───────────────────────────────┐   │
│  │                               │   │  Captured photo + tinted mask overlay
│  │     [photo w/ mask tint]      │   │  (4:3, rounded 16pt)
│  │                               │   │
│  └───────────────────────────────┘   │
│  ⚠ Unknown region · counted as …     │  Amber banner — only when raster
│  ⚠ Liquid · not estimated            │  contains unknown / unsupported-liquid
│                                      │
│  Detected (3)                        │  Class-list header
│  ▮ White rice          28 g carbs    │  swatch · name · carbs
│  ▮ Chicken              0 g carbs    │
│  ▮ Broccoli             4 g carbs    │
│                                      │
│  ┌───────────────────────────────┐   │  Primary action (pinned bottom)
│  │             Carbs             │   │
│  └───────────────────────────────┘   │
└─────────────────────────────────────┘
```

Content scrolls; the `Carbs` action is pinned to the bottom.

---

## Specifics

- **Background:** `captureBackground` (OLED).
- **Photo + mask (§5.1):** the captured nadir photo (`PHAsset` load, same path as
  Result) at 4:3 `.fit`, rounded 16pt, with the `MaskOverlayLoader` overlay
  stacked on top in a `ZStack`. The overlay is the per-class label raster tinted
  by the deterministic id→colour table at 0.55 alpha (Decision 15); background
  pixels are transparent so the photo shows through. When the photo asset is
  unavailable a `fork.knife` placeholder fills the slot; when the mask artefact is
  unavailable the overlay renders nothing — photo-only, no error (Req 6.8).
- **Banners (§5.2):** amber (`systemOrange` at 0.85), icon + text (never colour
  alone — Req 14.4), rounded 12pt. Shown **only** when the mask raster actually
  contains the sentinel class:
  - unknown region (`unknown_food`, index 33) → `Unknown region · counted as
    unknown carbs`, `questionmark.circle.fill`.
  - unsupported liquid (`unsupported_liquid`, index 34) → `Liquid · not
    estimated`, `drop.fill`.
  These classes carry no per-class macro entry, so the raster is the only place
  they surface. No mask → no banners.
- **Class list (§5.1):** `Detected (N)` header (N = `perClass` count), then one
  row per detected class sorted by carbs descending: a 16pt rounded mask-colour
  swatch (from the id→colour table, keyed by the class' palette index), the
  prettified name (`white_rice` → `White rice`), and a trailing monospaced
  `N g carbs`. **No per-class confidence** (Decision 16).
- **Primary action (§5.3, Decision 7):** a single prominent `medataAccent`
  `Carbs` button that appends `CaptureRoute.result`. The estimate is already done
  — the label carries no "estimate now" implication.

---

## Anti-patterns

- Do NOT add per-class confidence chips or a σ column (Decision 16).
- Do NOT label the primary action anything that implies estimation is pending
  (`Estimate carbs` is wrong — Req 5.3).
- Do NOT error when the photo or mask is missing — fall back to photo-only /
  placeholder (Req 6.8).

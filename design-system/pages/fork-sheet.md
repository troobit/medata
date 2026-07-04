# Capture-path fork sheet — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The §3 capture-path fork sheet, opened
by long-pressing the bottom-row mode button on the Capture screen.

**Brief:** Let the user choose the capture method and whether to include a
reference card, without leaving the capture flow. Quick is recommended; two-view
is the fallback (and the only option without LiDAR).

---

## Layout

```
┌─────────────────────────────────────┐
│ ═══                                 │  Drag indicator (.medium detent)
│ ✓ LiDAR available                   │  Banner — medataAccent when LiDAR present
│                                     │
│ ┌─────────────────────────────────┐ │
│ │ Quick (1 photo) [Recommended] 1 photo│ Path card — tap = select + dismiss
│ │ ~1 s · LiDAR                     │ │  Selected card: medataAccent border
│ └─────────────────────────────────┘ │
│ ┌─────────────────────────────────┐ │
│ │ Two-view              2 photos   │ │
│ │ ~2 s · top-down + 25°            │ │
│ └─────────────────────────────────┘ │
│                                     │
│ Reference card                      │  Card section
│ Improves scale confidence           │
│ Include card              [ ●]      │  Toggle — seeds from alwaysIncludeCard
└─────────────────────────────────────┘
```

---

## Specifics

- **Presentation:** `.presentationDetents([.medium, .large])` with a drag
  indicator.
- **LiDAR banner (Req 3.1/3.3):** `LiDAR available` (`checkmark.circle.fill`,
  `medataAccent`) when the device has LiDAR; `LiDAR unavailable` (`xmark.circle`,
  `textSecondary`) otherwise.
- **Path cards (Req 3.1):** each card is the selector — tapping writes
  `SettingsKeys.captureMode` (`.single` / `.double`) and dismisses. The card
  matching the current mode carries a `medataAccent` 2pt border (preselection).
  On a `surfaceElevated` rounded rectangle:
  - Quick: title `Quick (1 photo)`, `Recommended` badge (`medataAccent` capsule,
    black text), action `1 photo`, subtitle `~1 s · LiDAR`. Disabled (0.5
    opacity, non-interactive) when `!supportsLiDAR`; its subtitle then reads
    `LiDAR unavailable`.
  - Two-view: title `Two-view`, action `2 photos`, subtitle `~2 s · top-down + 25°`.
    Preselected when `!supportsLiDAR`.
- **Reference card (Req 3.2):** header `Reference card`, caption
  `Improves scale confidence`, and a `Include card` toggle (`medataAccent`). The
  toggle seeds from `SettingsKeys.alwaysIncludeCard` on appear and writes a
  per-capture override on `CaptureFlowModel.includeCardThisCapture` — it does
  **not** change the stored default. Observable effect: card-placement guidance
  during two-view capture; card detection itself stays automatic in the pipeline.

---

## Anti-patterns

- Do NOT persist the per-capture card override — only Settings writes
  `alwaysIncludeCard`.
- Do NOT offer the quick path as tappable without LiDAR — it must be disabled,
  with two-view preselected.
- Do NOT add a separate confirm button — the path card is the action.

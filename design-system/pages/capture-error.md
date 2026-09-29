# Capture error — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The §4 capture-error state, a
full-screen overlay that replaces the v1 `RefusalSheet` bottom sheet.

**Brief:** When a capture fails a gate or estimation fails, the user gets a
terse status, a one-clause fix, and three ways out — never a dead end (Req 4.1).
The overlay sits over the frozen viewfinder so the phone can stay where it is
for a retry.

---

## Layout

```
┌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┐   Amber ghost outline (dashed, systemOrange 0.6)
╎                                     ╎   over a 0.72 captureBackground scrim
╎                                     ╎
╎          ⚠ too far                  ╎   Status chip — amber capsule, ≤3 words, title3 bold
╎                                     ╎
╎           30–40 cm                  ╎   Fix hint — one clause, callout, white 0.85
╎                                     ╎
╎         ┌─────────────┐             ╎
╎         │    Retry    │             ╎   Retry — prominent, medataAccent
╎         └─────────────┘             ╎
╎         ┌─────────────┐             ╎
╎         │   2-view    │             ╎   2-view — bordered (1.5pt white)
╎         └─────────────┘             ╎
╎            Cancel                   ╎   Cancel — plain text
╎                                     ╎
└╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┘
```

---

## Specifics

- **Ghost outline:** `RoundedRectangle` (28pt corner) stroked in `systemOrange`
  at 0.6 opacity with a dashed `StrokeStyle(lineWidth: 3, dash: [10, 8])`, inset
  16pt. Flat overlay — no shadow, no solid banner (MASTER.md).
- **Status chip:** amber (`systemOrange` 0.85) capsule, `exclamationmark.triangle.fill`
  + text, white. ≤ 3 words (Req 4.2). Colour is paired with the warning glyph
  (Req 14.4).
- **Fix hint:** one clause, `callout`, centred, white 0.85.
- **Actions (Req 4.1):** `Retry` (prominent `medataAccent`), `2-view` (bordered),
  `Cancel` (plain). `Retry` → `retry()` resumes at the failed stage with the AR
  session live (folds iphone-experience 10.2/10.3). `2-view` →
  `switchToTwoViewAndRetry()` (clears the frozen single attempt, persists
  `.double`, returns to a live `.ready`). `Cancel` → `dismissRefusal()`.

### Chip + hint per failure

Verbatim from the copy inventory where the failure maps to a listed row; the
rest follow the minimal-wording rule (Req 4.2).

| EstimationFailure | Chip | Hint |
|---|---|---|
| `obliqueTiltOutOfRange` | `too tilted` | `Target 25°` |
| `arWorldTrackingLost`, `lidarUnavailableMidCapture` | `tracking lost` | `Retake second photo` |
| `noLidarDevice` | `no LiDAR` | `2-view still works` |
| `noScaleAvailable`, `degenerateCardPose`, `cardTooOblique`, `iterationDiverged` | `card needed` | `Any bank card sets scale` |
| `lidarCoverageTooLow` | `low depth` | `Use two-view mode` |
| `lidarFitDegenerate` | `no surface` | `Use a flat surface` |
| `lidarFitResidualTooHigh` | `uneven surface` | `Use a flat surface` |
| `noFoodPixels` | `no food` | `Show the meal clearly` |
| `noFoodVolumeRecovered` | `no volume` | `Retake the photo` |
| `mealsDbCorrupt` | `history reset` | `Capture still works` |
| `internalError` | `error` | `Try again` |

The pre-shutter distance and low-light rows in the copy inventory (`too far` /
`30–40 cm`, `more light` / `Too dark for plate edge`) are surfaced by the
capture chrome's blocked-shutter chip (`capture.md`), not by this overlay —
those gates block the shutter rather than raising an `EstimationFailure`.

---

## Anti-patterns

- Do NOT re-introduce the bottom sheet or a swipe-to-dismiss gesture — the
  overlay's `Cancel` is the explicit dismissal.
- Do NOT show more than three words in the chip or more than one clause in the
  hint (Req 4.2).
- Do NOT rely on the amber colour alone — the warning glyph carries the meaning
  too (Req 14.4).

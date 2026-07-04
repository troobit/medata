> **Superseded by design-handoff-00** — this page is superseded by [`design-system/pages/capture.md`](capture.md) (design-handoff-00, 2026-07-04). Content is preserved for history only; do not implement against it.

# Photo tab — page-specific overrides

**Inherits:** `design-system/MASTER.md`. This file specifies deviations and additions for the Photo tab (camera capture screen + result view).

**Brief:** Clean, professional capture aesthetic. The AR preview is the content. Chrome is minimal, semi-transparent, and grouped to avoid cluttering the food in the viewfinder.

---

## Layout zones

```
┌─────────────────────────────────────┐
│  ╳                            ⚡    │  Top chrome (status-bar + 16pt safe gutter)
│                                     │  Close (xmark) — left;  flash/torch — right
│                                     │  Both 32pt SF Symbols, white on captureChromeBG capsule
│                                     │
│                                     │
│        ┌────────────────┐           │  Indicator badge stack (top-center, 80pt below top chrome)
│        │ ⊕ 32cm  ⌖ 0.5°  │           │  ONE chip combining tilt + distance + LiDAR coverage
│        │   ▓▓▓▓▓░░ 78%   │           │  Hides 5s after .ready entered if state stays .ready
│        └────────────────┘           │  Tap to re-show; auto-shows on out-of-range value
│                                     │
│                                     │
│         AR PREVIEW (full-bleed)     │
│                                     │
│                                     │
│                                     │
│                                     │
│                                     │
│                                     │
│           ┌─────────────┐           │  Capture-mode pill — capsule with two text labels and an
│           │ Single │Double│          │  animated inner accent pill. 24pt above shutter. Active = bold + medataAccent.
│           └─────────────┘           │  Single greyed if !supportsLiDAR.
│                                     │
│              ╭───╮                  │  Shutter — 76pt circle, white ring + inner white circle.
│              │   │                  │  On press: ring shrinks to inner-circle radius, then pulses
│              ╰───╯                  │  back. .scale(0.95) feedback.
│                                     │
├─────────────────────────────────────┤
│   📷         🍴         ⚙           │  System tab bar (Liquid Glass material). Photo selected.
└─────────────────────────────────────┘
```

---

## Specifics

### Top chrome — `CaptureTopBar`

| Element | Position | Spec |
|---|---|---|
| Close (`xmark`) | Top-left, 16pt from leading + safe area top | SF Symbol, 24pt, white, in a 40pt circular `captureChromeBG` capsule. Backs out of the tab (selects the tab the user came from, or no-op on cold launch from Photo). |
| Flash / torch (`bolt.fill` / `bolt.slash.fill`) | Top-right, 16pt from trailing + safe area top | Same capsule treatment. Toggles `AVCaptureDevice.torchMode`. Only shown when LiDAR torch is supported. Hidden if AR session is off. |

No screen title. No back button. No labels.

### Indicator badge — `LiveIndicatorBadge`

Replaces the v1.0 stacked indicators with one consolidated chip. Three sub-elements left-to-right, separated by 8pt vertical hairline (`Color.white.opacity(0.2)`):

1. Tilt — SF Symbol `level` + two-line greyscale readout: top `Δθ°` (e.g. `17°`), bottom `σ_tilt%` (e.g. `97%`). Both monospaced, both `captureChromeText` (white). No green / amber / red tint — every angle yields a valid capture (Decision 18); the user sees the σ_tilt cost they are about to pay before the shutter fires (Decision 19).
2. Distance — SF Symbol `ruler` + `cm`, monospaced. Green tint when 25–50 cm, white otherwise. Omitted if `!supportsLiDAR`.
3. LiDAR coverage — 4pt horizontal bar gauge, 32pt wide, filled to `coverage/100`. Omitted if `!supportsLiDAR`.

Whole chip uses `captureChromeBG` background, 14pt corner radius, `padding(.horizontal, 12)`, `padding(.vertical, 8)`. Auto-hide rule: after `.ready` has been the state for 5 s with `σ_tilt > 0.95` (≈ Δθ < 18°) AND distance and LiDAR coverage in range, the chip fades to 0.0 opacity (still tappable via 48pt `hitSlop`); tap or any predicate violation re-shows it (Decision 19; supersedes the prior ±5° tilt-in-range gate).

### Capture-mode pill — `CaptureModeToggle`

Replaces the v1.0 segmented control with a capsule-pill design that fits the slim chrome above the shutter:

- Pill background: `captureChromeBG`, 22pt corner radius (fully rounded), 44pt tall.
- Two text labels inside: "Single" / "Double" (Irish-English), `body` weight 600.
- Active label: solid `medataAccent`-on-`captureBackground` inner pill (8pt margin inside the outer pill). Inactive label: white text, no inner pill.
- Tap inactive label: spring (`.bouncy 200ms`) slide of the inner pill to the new position; UserDefaults write.
- Disabled state for "Single" when `!supportsLiDAR`: label opacity 0.4, no inner pill on tap; trying to tap it emits the existing Irish-English no-LiDAR refusal.
- Positioned 24pt above the shutter, horizontally centred.

### Shutter — `ShutterButton`

| Element | Spec |
|---|---|
| Outer ring | 76pt circle, 4pt stroke, white. |
| Inner fill | 60pt circle, white. |
| Press feedback | On `pressed`: inner shrinks to 52pt + ring stroke widens to 6pt over 100ms; on release: spring back, 150ms `.snappy`. |
| Disabled state | Inner fill opacity 0.4, no press animation, button non-interactive. |
| Position | Horizontally centred. Vertical position: 24pt above the tab bar's top edge + safe-area bottom. |
| Accessibility | `accessibilityLabel("Capture meal")`, `accessibilityHint("Double-tap to take a photo")`. |

### ResultView

```
┌─────────────────────────────────────┐
│  ╳                                  │  Close — top-left, same capsule treatment.
│                                     │
│                                     │
│            (food photo,             │  Full-bleed photo background.
│              full-bleed,            │  scrim: linear gradient
│              dimmed)                │  black 0.6 → black 0.0 → black 0.6
│                                     │
│              ╭──────╮               │
│              │ 47 g │               │  Carb total — display weight (72pt), white,
│              ╰──────╯               │  monospaced-digit, centred.
│                                     │
│            ▮ High 87% ▮             │  Confidence pill — small (28pt tall),
│                                     │  rounded 14pt, medataAccent / orange / red bg.
│                                     │
│      ╭─ Placeholder estimate ─╮     │  Placeholder chip — ONLY when segmenterSource == "dev_stub".
│      │                         │     │  systemYellow bg, black text, 28pt tall, 14pt corners.
│      ╰──────────────────────────╯    │  Beneath confidence pill, 16pt gap.
│                                     │
│                                     │
│                                     │
│         ┌────────┐ ┌────────┐       │  Action row (presentation: justCaptured).
│         │ Retake │ │  Done  │       │  Hidden in historyDetail mode.
│         └────────┘ └────────┘       │  Both 48pt tall, 120pt wide, 12pt radius.
│                                     │  Retake: outline (1.5pt white). Done: solid medataAccent.
└─────────────────────────────────────┘
```

Specifics:
- Photo fetched via `PHImageManager.requestImage(for: photoAssetID, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFill, ...)`. If Photos access denied, background is `captureBackground` and a small fork-knife SF Symbol replaces the photo.
- Carb total uses `.contentTransition(.numericText())` so the 47 g animates in.
- Confidence pill includes the SF Symbol `checkmark.seal.fill` (high) / `exclamationmark.triangle.fill` (moderate) / `xmark.octagon.fill` (low) per the `color-not-only` rule.

### Refusal banner — `RefusalSheet`

Replaces the v1.0 top banner with a bottom sheet so the refusal copy is anchored near the user's thumb on the shutter:

- Presented via `.presentationDetents([.fraction(0.35)])` with `.presentationDragIndicator(.visible)`.
- Sheet content: SF Symbol matching the failure (e.g. `nosign` for `noScaleAvailable`), large title (Irish-English), one-line explanation, single primary CTA "Try again" (matches `primary-action` rule).
- Background: `surfacePrimary` (system grouped). Dismiss by swipe-down or "Try again" tap returns the model to `.capturing(retryStage, ...)`.

---

## Anti-patterns specific to Photo tab

- Do NOT stack tilt / distance / coverage as three separate corners — consolidate them into one chip so the AR preview stays uncluttered.
- Do NOT add a "Settings" or "History" button to the capture view — those live on the tab bar.
- Do NOT show the capture-mode pill on devices without LiDAR (the "Single" option is the only one disabled there; the pill itself still shows with one option locked, so the user knows Double is the only available mode).
- Do NOT render the placeholder as a full-width yellow banner — use the small chip beneath the confidence pill.

---

## Pre-delivery checklist (Photo tab additions)

- [ ] AR preview reaches all four screen edges
- [ ] Top chrome capsules have 8pt clearance from status bar AND each other
- [ ] Shutter sits ≥24pt above the tab-bar top edge (so the tab bar doesn't obscure it)
- [ ] All chrome remains legible against a fully-white food photo (the chip backgrounds have ≥0.10 opacity scrim)
- [ ] Capture-mode pill is keyboard-accessible (focusable, switchable with ↑/↓)
- [ ] Shutter button announces a different `accessibilityValue` per state (Ready / Capturing / Disabled)
- [ ] No glassmorphism, no shadows, no gradients other than the result-view scrim

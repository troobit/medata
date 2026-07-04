# Medata — Design System (Master)

**Project:** Medata
**Platform:** iOS 26.5+, SwiftUI, iPhone-only, portrait-only
**Date:** 2026-05-29
**Brief:** Apple "Organize your features" tab pattern. Clean, professional capture screen — content-first; chrome shrinks when the AR feed or the food photo is the point.

Read this file first when implementing any new view. Then check `design-system/pages/<screen>.md` for screen-specific overrides; if present, the page file wins.

---

## Style — three layers, used together

| Layer | Used on | Reference style |
|---|---|---|
| **Dark Mode (OLED)** | Photo tab, ResultView | Pure black `#000000` AR-preview background, white-on-black chrome, minimal glow. |
| **Exaggerated Minimalism** | ResultView carb total, Meals row metadata | Oversized numeric type, extreme negative space, single accent (`#63FF00`). |
| **Flat Design Mobile (Touch-First)** | Tab bar, all interactive controls | Zero shadow, instant press feedback (`scale 0.97`), ≥48pt targets, solid colours over gradients. |

Glassmorphism / claymorphism / neumorphism are out (anti-pattern for this product: they obscure the AR feed and the food photo).

---

## Colour tokens

```swift
extension Color {
    // Brand
    static let medataAccent       = Color(red: 0x63/255, green: 0xFF/255, blue: 0x00/255) // #63FF00

    // Capture / Result (OLED)
    static let captureBackground  = Color.black
    static let captureChromeText  = Color.white
    static let captureChromeBG    = Color.white.opacity(0.10)   // chip / pill backgrounds over preview
    static let captureScrim       = Color.black.opacity(0.45)   // for top/bottom gradient overlays

    // Surfaces (Meals / Settings — system Grouped)
    static let surfacePrimary     = Color(uiColor: .systemGroupedBackground)
    static let surfaceElevated    = Color(uiColor: .secondarySystemGroupedBackground)
    static let textPrimary        = Color(uiColor: .label)
    static let textSecondary      = Color(uiColor: .secondaryLabel)
    static let separatorSubtle    = Color(uiColor: .separator)

    // Confidence pill (Decision 17 — four tiers)
    static let confidenceHigh     = medataAccent                  // σ ≥ 0.75
    static let confidenceModerate = Color(uiColor: .systemOrange) // 0.50 ≤ σ < 0.75
    static let confidenceLow      = Color(uiColor: .systemRed)    // 0.20 ≤ σ < 0.50
    static let confidenceVeryLow  = Color(white: 0.35)            // σ < 0.20 (desaturated; pairs with the inline retake surface)

    // Placeholder banner / chip (research Req 23.3)
    static let placeholderBG      = Color(uiColor: .systemYellow)
    static let placeholderFG      = Color.black

    // Trends chart (Decision 12, design-handoff-00)
    static let seriesGlucose      = Color(uiColor: .systemOrange) // glucose line series on the Trends chart
    static let bandTarget         = medataAccent.opacity(0.10)    // 3.9–10.0 mmol/L target range band fill
}
```

**Contrast budget:** all text on `captureBackground` is pure white = 21:1 ratio (AAA). Confidence pills carry the icon + text per `color-not-only` rule, never colour alone. The placeholder yellow chip's black text on `.systemYellow` exceeds 4.5:1 in both light and dark mode.

---

## Type scale

| Role | Font | Weight | Size | Used for |
|---|---|---|---|---|
| `display` | SF Pro Display | 800 | 72pt (clamp 56–88) | ResultView carb total |
| `title` | SF Pro Display | 700 | 28pt | Section headers on Meals / Settings |
| `body` | SF Pro Text | 400 | 17pt | Body copy |
| `caption` | SF Pro Text | 500 | 13pt | Indicator badge text on Photo tab |
| `mono-numeric` | SF Mono | 600 | inherits | Carb values in lists, timestamps — tabular figures, `letterSpacing: -0.5` |

All styles use Dynamic Type via `.font(.system(.<role>, design: <serif/mono>))`. Carb total uses `.monospacedDigit()` so the value doesn't shift as it animates in.

---

## Spacing

4 / 8 / 16 / 24 / 32 / 48pt scale. No arbitrary values. Generous: a Photo-tab chip is `padding(.horizontal, 12)` + `padding(.vertical, 8)`, then `spacing: 16` between chips. Whitespace is the design.

---

## Motion

| Trigger | Duration | Easing |
|---|---|---|
| Press feedback (button, chip, row) | 100ms | spring `.snappy(duration: 0.1)` |
| Capture-mode toggle slide | 200ms | spring `.bouncy(duration: 0.2)` |
| Shutter pulse on tap | 150ms | spring `.snappy` |
| ResultView present | 280ms enter / 180ms exit | spring `.smooth` |
| Reduced motion | crossfade only, no spring | system handles |

Animate `transform` + `opacity` only. Never `width`/`height`/`top`/`left`.

---

## Layout primitives

- **Shell:** Capture-rooted shell — no tab bar. `CaptureFlowView` fills the screen; Data, Trends, and Settings are sheets presented over it (Decision 2, design-handoff-00). Sheets are mutually exclusive via a single `ActiveSheet` optional.
- **Safe area:** Capture screen respects top safe area for status bar. AR preview is full-bleed; shutter and mode controls sit above the safe-area bottom. Sheet screens use standard system grouped surfaces.
- **Touch targets:** ≥48pt everywhere. The shutter is 76pt. Indicator chips are 32pt tall with `hitSlop` to 48pt total.

---

## Anti-patterns to avoid

- Glassmorphism on cards over the AR feed (re-blurs an already-busy preview)
- Multiple accent colours on one screen (one accent + system semantic colours is the budget)
- Emojis used as icons anywhere (SF Symbols only)
- Banners with shadow on the Photo tab — flat overlays only
- Animating layout properties (use `transform`/`opacity`)
- Showing the placeholder banner as a full-width bar on the Photo result — use a small pill chip below the carb total instead

---

## Pre-delivery checklist (applies to every screen)

- [ ] No emojis as icons (SF Symbols only)
- [ ] Touch targets ≥48pt (use `hitSlop` if visual ≥44pt is the goal)
- [ ] Press feedback within 100ms (`.scale 0.97`)
- [ ] Text contrast ≥4.5:1 in light and dark mode
- [ ] Reduced-motion respected (crossfade only)
- [ ] Dynamic Type respected up to AX5
- [ ] Safe areas respected (no content under notch / Dynamic Island / home indicator)
- [ ] Single primary CTA per screen
- [ ] One accent colour (`medataAccent`) per screen + system semantic colours only

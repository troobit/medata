# Capture — page-specific overrides

**Inherits:** `design-system/MASTER.md`. Deviations and additions for the
Capture screen (the navigation root under the handoff-00 Capture-rooted shell —
Decision 11). Supersedes `photo-tab.md`.

**Brief:** The AR preview is the content. Chrome is data-only, semi-transparent,
and grouped so nothing distracts from framing the plate. No instructions, no
titles — the screen reads like an instrument (Req 2).

---

## Layout zones

```
┌─────────────────────────────────────┐
│  ◎ ◎        1-VIEW · LiDAR      ┌──┐ │  Top bar (Req 2.1)
│  Trends/Data (leading)          │◉ │ │  • Trends + Data — 40pt captureChromeBG circles, leading
│                                 └──┘ │  • Mode capsule — top-centre, monospaced
│                                      │  • Bubble level — 76×76, top-right
│                                      │
│         AR PREVIEW (full-bleed)      │
│                                      │
│                                      │
│           hold steady                │  Transient surface (above telemetry)
│      ┌───────────────────────┐       │  Telemetry capsule — always visible
│      │ tilt 1.8° · dist 34 cm │       │  tilt° · dist cm (or 30–40 cm band)
│      │        · LiDAR ●       │       │  · LiDAR dot ● filled / ○ hollow
│      └───────────────────────┘       │
│   ┌──────┐        ╭───╮       ◎      │  Bottom row (Req 2.1)
│   │2-VIEW│        │   │       ⚙      │  mode button · shutter · settings
│   └──────┘        ╰───╯              │
└─────────────────────────────────────┘
```

No tab bar (the shell removed it — Decision 11). Data, Trends and Settings are
sheets opened from the chrome buttons.

---

## Specifics

### Top bar (Req 2.1)

| Element | Position | Spec |
|---|---|---|
| Trends button | Leading, 16pt gutter | `chart.xyaxis.line`, 16pt white in a 40pt `captureChromeBG` circle. Accessibility label `Trends`. Opens the Trends sheet. Stays usable while permission is denied (Req 1.6). |
| Data button | Leading, next to Trends | `square.stack.3d.up`, same capsule. Accessibility label `Data`. Opens the Data sheet. Usable while denied. |
| Mode capsule | Top-centre | Monospaced `caption`, white on `captureChromeBG` capsule. Reads `1-VIEW · LiDAR` / `2-VIEW · NADIR` / `2-VIEW · OBLIQUE` per stage (Req 2.2). Read-only status — the bottom-row mode button is the control. |
| Bubble level | Top-right | `MedataBubbleLevel`, 76×76 — see below. |

### Bubble level — `MedataBubbleLevel` (Req 2.3, Decision 8)

76×76 attitude level reusing the retired `TiltBubbleGuide` maths (`TiltGuideState`:
stage-relative target 0° nadir / 25° oblique, tolerance). The puck drifts
continuously with device tilt; its **position** (distance from centre = tilt
magnitude, direction = on-screen azimuth) is the non-colour cue. Tinted
`medataAccent` green within ±5° of the stage target, `systemOrange` amber
beyond. Nadir shows a centre disc target; oblique shows a ring at the 25°
radius. It gates nothing.

### Telemetry capsule — `TelemetryCapsule` (Req 2.4)

Always visible above the shutter (replaces the auto-hiding `LiveIndicatorBadge`).
`caption` monospaced, white on `captureChromeBG` capsule, sub-fields separated
by `·`:

1. `tilt` + live degrees (one decimal).
2. `dist` + live cm on LiDAR devices; the static band `30–40 cm` on non-LiDAR
   devices (guidance mode).
3. `LiDAR` + a dot pairing colour with shape (Req 14.4): green filled `●`
   (`circle.fill`, `medataAccent`) when depth is available; grey hollow `○`
   (`circle`) otherwise — the grey hollow dot is the non-LiDAR guidance-mode
   indicator.

### Transient surfaces (Req 2.1 clause; copy inventory)

Restyled status hints, above the telemetry capsule, on a `captureChromeBG`
capsule. One at a time, most-urgent-wins:

| State | Copy | Symbol |
|---|---|---|
| Initialising | `Initialising` | `hourglass` |
| Tracking lost | `hold steady` | `arrow.triangle.2.circlepath` |
| Capturing | `Capturing` | `camera` |
| Blocked-shutter tap (transient, 1.5 s) | failing gate: `too far` / `hold steady` / `wait` | `exclamationmark.circle` |
| Oblique stage, tilt off-target | `Target 25°` | `rotate.3d` |
| Nadir confirmation thumbnail | label `Nadir` | `checkmark.circle.fill` |

Blocked-shutter feedback keeps the existing shutter haptic (`.warning`); the old
badge reveal is gone.

### Bottom row (Req 2.1, 2.5)

| Element | Position | Spec |
|---|---|---|
| Mode button | Leading | 64×40 `captureChromeBG` capsule, monospaced `1-VIEW` / `2-VIEW`. Tap toggles 1-view/2-view (LiDAR only); long-press opens the fork sheet (`fork-sheet.md`). Disabled (0.4 opacity) while denied or busy. |
| Shutter | Centre | `ShutterButton`, 76pt, `bottomClearance` (24pt) above the safe-area bottom. |
| Settings button | Trailing | `gearshape.fill`, 40pt `captureChromeBG` circle. Accessibility label `Settings`. Opens the Settings sheet. Usable while denied (Req 1.6). |

Torch is removed (Decision 14); `more light` (`capture-error.md`) is the
dark-scene guidance.

### Estimating state (§1.3)

Frozen captured frame(s), blurred + dimmed, with `MedataLoadingSymbol(mode: .loop)`
centred over them (closes `ldsym06`). Accessibility label `Estimating`. Shutter
and mode are suppressed; telemetry is hidden.

### Permission denied (Req 1.6)

Not a takeover. The top bar (Trends/Data) and the settings button stay rendered
and usable; the shutter and mode button are disabled. Centred copy:
`Camera access denied` or `Motion access denied`, with an `Open Settings` button.

---

## Anti-patterns specific to Capture

- Do NOT reintroduce a tab bar or a torch control.
- Do NOT auto-hide the telemetry capsule — it is always visible now.
- Do NOT let the bubble level or telemetry dot rely on colour alone (pair with
  position / shape / text — Req 14.4).
- Do NOT gate the shutter on tilt beyond the existing oblique cap (Req 2.6).

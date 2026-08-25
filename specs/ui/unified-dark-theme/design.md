# Design: Unified Dark Theme

## The mechanism: one Info.plist key

`UIUserInterfaceStyle = Dark` in `MeData/Info.plist` (the partial plist that already carries
the build stamp and `CFBundleURLTypes`). UIKit resolves every dynamic colour in the process
dark from launch — SwiftUI views, sheets, covers, alerts, menus, the keyboard, and
system-hosted UI the app presents (photo picker, share sheet) — with no propagation
question and nothing a future view can forget to apply (Req 1.4).

Rejected mechanisms are in the decision log: `.preferredColorScheme(.dark)` at `AppRoot`
(SwiftUI-scope only, propagation to presented containers is an implementation detail to
verify per surface) and repainting the grouped views onto the capture palette (ten files of
churn that destroys the adaptivity Req 1.5 keeps).

## Why the palettes converge instead of merging

Resolved values under dark appearance:

| Token | Light resolution | Dark resolution |
|---|---|---|
| `surfacePrimary` (`.systemGroupedBackground`) | `#F2F2F7` | `#000000` |
| `surfaceElevated` (`.secondarySystemGroupedBackground`) | `#FFFFFF` | `#1C1C1E` |
| `textPrimary` (`.label`) | near-black | `#FFFFFF` |
| `textSecondary` (`.secondaryLabel`) | grey | light grey (AA on both surfaces) |
| `captureBackground` | `#000000` | `#000000` |

Dark `surfacePrimary` **is** `captureBackground`. The Records list, the meal overview and the
result screen therefore sit on the same black without a single view changing its tokens
(Req 1.2), and the grouped family's remaining job is elevation: flat black base, `#1C1C1E`
cards. That is the signature of the unified look — the OLED continuity of the capture flow
extended to the whole app, with the meal photo and the acid-green accent as the only bright
objects on screen.

`ConfidencePill` hard-codes `captureChromeText` (white) and appears on `MealOverviewView`'s
grouped surface, where it was visually mispitched on light; under the unified scheme white on
`#1C1C1E` is ~15:1 and the mispitch dissolves (Req 2.2). The white-on-black budget for
capture chrome (21:1, MASTER.md) is untouched (Req 1.3).

Views with **no** background modifier (`RecordsView`'s bare `List`, `SettingsView`'s bare
`Form`) resolve dark through the same mechanism; they need no edit and get none (Non-Goal:
no per-view repainting).

## Code changes

1. `MeData/Info.plist`: add `UIUserInterfaceStyle` = `Dark`.
2. `App/Colors.swift`: comment amendment only — the "Surfaces (Meals / Settings — system
   Grouped)" header becomes "Surfaces (grouped structure — always resolved dark, see
   specs/ui/unified-dark-theme)". No token value changes.

Nothing else. The whole feature is one plist line; everything further is documentation
reconciliation (Req 3) and the device look.

## Documentation changes

- `design-system/MASTER.md`: style-table row scope amendment; grouped block annotation;
  colour block brought level with `App/Colors.swift` (Req 3.1, 3.4).
- `design-system/pages/meal-overview.md`, `design-system/pages/data.md`: in-place amendment
  notes where light grouped surfaces are specified (Req 3.2).
- `design-system/pages/records.md`: new page doc for `RecordsView` (Req 3.3) — grouped dark
  `List`, the five row types, swipe/edit-mode deletion surface per
  `specs/ui/records-deletion`, `MealRoute` pushes.

## What could go wrong, and where it is caught

- A view that read `colorScheme` to branch would keep its dark branch permanently — grep
  shows zero `colorScheme` reads in `App/`, so no such branch exists.
- An image asset with light/dark variants would pin to dark — the asset catalogue carries no
  appearance-variant assets today.
- System UI presented by the app (share sheet, photo picker) renders dark; that is the
  intended reading of Req 1.1, not leakage.
- The two placeholder-chip tokens (`placeholderBG` `.systemYellow`, `placeholderFG` black)
  resolve yellow-on-black-text in dark; MASTER.md's contrast note already covers both modes.

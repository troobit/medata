# Decision Log: Unified Dark Theme

## Decision 1: Force dark at the process level via `UIUserInterfaceStyle`, keeping adaptive tokens

**Date**: 2026-08-25
**Status**: accepted

### Context

The two-palette split — OLED capture family vs adaptive grouped family — was specified
deliberately (`design-system/MASTER.md` style table: "**Dark Mode (OLED)** | Photo tab,
ResultView") and implemented faithfully: nothing forces a scheme, so grouped surfaces follow
the device setting and render near-white in light appearance. Opening a meal from Records
walks light list → light overview → black result inside one navigation stack. The product
direction is a single dark presentation across every meal surface.
`specs/ui/design-handoff-00` Decision 12 sets the bar for amending MASTER.md: the handoff's
scaffold palette was rejected there because "it would retire the OLED capture aesthetic
without a stated reason" — this decision extends that aesthetic rather than retiring it, and
states the reason.

### Decision

Add `UIUserInterfaceStyle = Dark` to `MeData/Info.plist`. Every dynamic colour in the process
resolves dark from launch. Token definitions in `App/Colors.swift` are unchanged; the grouped
family's semantics shift from "adaptive light family" to "grouped structure, always resolved
dark", recorded as a comment amendment and a MASTER.md reconciliation.

### Rationale

Under dark resolution `.systemGroupedBackground` is `#000000` — identical to
`captureBackground` — and `.secondarySystemGroupedBackground` is `#1C1C1E`. The palettes
converge by construction, so the cheapest possible mechanism (one plist line) delivers the
whole visible outcome, and every view keeps its existing tokens. A process-level key also
covers surfaces SwiftUI modifiers reach unreliably or not at all: UIKit-hosted pickers,
share sheets, alerts, and any future view that would otherwise need to remember a modifier.

### Alternatives Considered

- **`.preferredColorScheme(.dark)` on `AppRoot`**: SwiftUI-native, revertible per-preview -
  Rejected: its scope is the SwiftUI presentation it is attached to; whether every
  `fullScreenCover`, `sheet` and UIKit-hosted container inherits it is a per-surface
  verification burden, exactly the class of leak Req 1.4 exists to preclude.
- **Repaint grouped views onto the capture palette** (`surfacePrimary` → `captureBackground`,
  `textPrimary` → `captureChromeText` across ~10 files): Makes the unification explicit in
  every view - Rejected: large churn for a visually identical result, destroys the
  adaptivity that makes a future light theme a one-line revert, and demonstrably incomplete
  on day one (`MealOverviewView` alone uses `textPrimary`/`textSecondary` at seven sites).
- **A Settings appearance switch (dark / follow system)**: Preserves user choice - Rejected:
  developer-phase app with one user whose direction is one dark presentation; a switch is a
  second code path to keep dark-correct for nobody.

### Consequences

**Positive:**

- The white-flash defect class is closed structurally: no surface can render light, present
  or future.
- Zero view churn; `git diff` for the whole visual outcome is one plist line plus comments.
- The OLED continuity becomes the app's signature — black base everywhere, the meal photo
  and one acid-green accent as the only bright objects.

**Negative:**

- The device's light-appearance setting is ignored inside this app; system-presented UI
  (share sheet, photo picker) renders dark even when the OS is light. Accepted as the
  intended reading of one presentation.
- Tokens named for adaptivity (`textPrimary` as `.label`) now always resolve one way; the
  indirection is kept for revertibility but reads as unused generality until a light theme
  exists.
- Screenshot-based docs showing light surfaces (design-system page docs) go stale and must
  be annotated (Req 3.2), not regenerated.

### Impact

`MeData/Info.plist`, `App/Colors.swift` (comment), `design-system/MASTER.md`,
`design-system/pages/meal-overview.md`, `design-system/pages/data.md`, new
`design-system/pages/records.md`. `specs/ui/iphone-experience` Req 20.2's OLED scope
("The Photo tab and ResultView SHALL use a pure-black (`#000000`) full-bleed background")
is extended, not contradicted — those surfaces are unchanged and the rest of the app joins
them.

---

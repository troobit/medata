# The design layer — where to change how the app looks and feels

Everything in this folder exists so that a change you can *feel* is one line in
one file, rather than the same edit repeated across a dozen screens.

If you are new to Swift and Xcode, start here. Each knob below is a single
value; change it, run `make deploy-device`, and look at the phone.

## The five knobs worth meeting first

| Want to change | Edit | What moves |
|---|---|---|
| **The app's one colour** | `Color.medataAccent` in `../Shared/Colors.swift` | Every prominent button, the target band, the loading symbol, every toggle |
| **How round everything is** | `Metrics.cornerCard` in `Metrics.swift` | Cards, pills and primary buttons on every screen at once |
| **How numbers roll** | `Animation.numeral` in `Motion.swift` | Every changing figure in the app. Try `.bouncy` |
| **What saving feels like** | `.success` in `Feedback.swift` | The haptic on every Save button. Try `.impact(weight: .heavy)` |
| **How big the main buttons are** | `Metrics.controlLarge` in `Metrics.swift` | Record, Save, Done. 48 → 56 is the fastest way to feel the difference |

## The files

- **`Metrics.swift`** — the numbers: corner radii, control heights, the opacity
  ladder. Named so that a global change is one edit, and so an odd value stands
  out as deliberate rather than blending into a pile of literals.
- **`Motion.swift`** — animation curves, and `.animatedNumeral(value:)`.
- **`Feedback.swift`** — haptics: `.commitFeedback(trigger:)` for "a row was
  written", `.blockedFeedback(trigger:)` for "that did not work".

## Two rules the code enforces so you do not have to

**Reduce Motion.** Some people get motion sick from animation, and iOS lets
them ask apps to stop. Every rolling number must honour that. Rather than
trusting each screen to remember, `.animatedNumeral(value:)` contains the check
— so use it, and the rule keeps itself:

```swift
Text("\(units) U")
    .animatedNumeral(value: units)      // rolls, unless the phone says don't
```

An audit on 2026-08-28 found three screens that had written the check by hand
and got it wrong. That is why the modifier exists.

**One accent per screen.** `Color.medataAccent` means *this button writes
something*. If two things on a screen are accent-coloured, neither reads as the
action any more. Before making something accent, check what already is.

## Haptics: why a trigger is a counter, not a Bool

`.sensoryFeedback` fires when the value you give it *changes*. A `Bool` that is
already `true` never changes again, so the vibration happens once and never
returns. Pass a counter that increments on each success:

```swift
@State private var commits = 0
// ...
.commitFeedback(trigger: commits)
.onChange(of: isSaving) { wasSaving, nowSaving in
    if wasSaving, !nowSaving { commits += 1 }   // a save just finished
}
```

That pattern is already in `EntrySaveButton`, so every entry sheet vibrates on
save without doing anything. It is the shape to copy for a new one.

## Alerts and confirmations

Destructive actions ask first, with `.confirmationDialog` rather than `.alert`
— it rises from the bottom, within thumb reach, and the destructive button is
marked `role: .destructive` so iOS colours it red for us. The existing examples
are in `../Pages/Records/RecordsView.swift` and
`../Pages/MealDetail/ResultView.swift`.

Nothing else in the app should interrupt with a dialog. This is a
developer-phase tool: it does not reassure, warn or disclaim.

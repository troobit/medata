# Design: Unified Entry Sheet

## The shape of the change

Three pieces, in dependency order.

1. **`DigitEntry`** — a pure value type holding the digit-shifting rule that
   `GlucoseEntryModel` already implements, generalised by a decimal-place count and a range. It is
   the whole of Req 1.1 and 1.3, and it is torch-free of SwiftUI so the rule is testable on its own.
2. **`NumericEntryPad`** — the SwiftUI view `GlucoseEntrySheet` already contains: a clear
   `TextField` at 72pt under a drawn numeral, with a unit caption beneath. Lifted verbatim and
   parameterised (Req 1.2).
3. **`LogSheet.Mode.glucose`** — a fourth mode, and the deletion of `GlucoseEntrySheet.swift`
   (Req 2.1).

## `DigitEntry`

```swift
struct DigitEntry {
    let decimals: Int
    let range: ClosedRange<Double>
    private(set) var digits = ""

    var value: Double        // (Double(digits) ?? 0) / 10^decimals
    var displayValue: String // formatted to `decimals` places
    var isInRange: Bool
    mutating func setDigits(_ raw: String)
    mutating func set(value: Double)   // seeds the buffer from a number
}
```

`setDigits` keeps `GlucoseEntryModel`'s three rules unchanged and in order: digits only; strip
leading zeros so `0`,`8`,`4` and `8`,`4` both read 8.4; and discard anything that would exceed the
range, which caps the length without a separate check.

`set(value:)` is new and is what the dose needs: a remembered or suggested value has to become a
digit buffer so the first keystroke replaces it rather than appending to it. Seeding writes the
digits that would have produced that value.

Glucose is `DigitEntry(decimals: 1, range: 1.0...30.0)`; insulin is
`DigitEntry(decimals: 0, range: 1...60)`. The insulin range is the model's existing floor and hard
stop, so two digits is the natural cap there exactly as three is for glucose.

## `NumericEntryPad`

Parameters: a `Binding<String>` for the digits, the formatted display string, an `isComplete` flag
driving the numeral's colour, a unit caption, and accessibility label plus identifier. It owns the
`ZStack`, the 72pt monospaced treatment, the `numericText` content transition and the clear tint.

Focus stays with the caller: the 60 ms hop after presentation exists because a focus request in the
sheet's own run loop is dropped, and that timing is a property of the sheet, not the pad.

## The insulin surface after the change

The stepper row, `stepControl`, `beginHold`/`endHold`/`repeatSteps` and the hold-acceleration
schedule are **deleted**. They are the best available implementation of a control that should not
coexist with a keypad (Req 1.4), and leaving them behind the keypad would reintroduce exactly the
buffer-versus-value disagreement Decision 1 rejects.

What replaces the nudge affordance is a chip row built from the existing `EntryChip` and `ChipFlow`
(Req 1.5): the armed suggestion where one exists, and the kind's remembered value. Chips set
absolutely through `DigitEntry.set(value:)`, so they share the keypad's state model.

The bolus/basal picker stays and becomes load-bearing — it now selects which remembered value
applies (Req 3.5).

## Remembered defaults

`UserDefaults`, one key per kind (`dose.lastUnits.bolus`, `dose.lastUnits.basal`), written on a
successful save and read at init (Req 3.1, 3.6). Precedence at open, highest first:

| Source | Caption |
|---|---|
| Armed meal suggestion | the seed's own provenance string |
| Remembered value for the kind | `last bolus` / `last basal` |
| Fixed 10 U | `units` |

The caption slot is the one `InsulinDoseModel.unitsCaption` already owns, and its existing
consume-on-first-edit rule is unchanged — it is promoted from optional to mandatory (Req 3.4)
rather than redesigned.

## Detent

Every mode moves to `.large` (Req 2.3). Insulin and glucose are keypad-first and cannot fit the
medium detent with a keypad up; carbohydrate already raises a keypad; activity does not, and gains
empty space below its controls rather than a second sheet height. That is the trade `LogSheet`
already made when it chose one detent for three modes.

## Routing

`AppRoot`'s `glucoseSheet` case presents `LogSheet(store:mode:.glucose)` instead of
`GlucoseEntrySheet`. No deep link, widget URL or home control changes its target — only what the
target builds — so Req 2.2 holds by the mechanism `medata://insulin/add` already proves.

## What this does not change

The glucose save path, its `manual` route provenance, its no-deduplication rule, and the store's own
range guard are untouched: `GlucoseEntryModel` keeps its `save()` verbatim and swaps only its digit
handling for `DigitEntry`.

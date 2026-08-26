# Design: Insulin Dosing

## Overview

A suggested bolus is `carbs ÷ ratio − unoffset insulin-on-board`
([3.1](requirements.md#3.1), [4.8](requirements.md#4.8)), chosen by the local time band of the
meal, rounded to whole units, shown as a read-only figure whose tap opens the working
([6.12](requirements.md#6.12)), and **never stored**: every surface recomputes it live from
recorded events and the settings in force, for the subject meal's own instant
([6.11](requirements.md#6.11)). *(Redefined in place by Decision 18. Superseded wording: "and
recorded — with every input that produced it — in a derived side table the event log never
sees" — itself a Decision 17 redefinition of "`carbs ÷ ratio − insulin-on-board` … rounded to
the pen's increment, shown as a read-only figure".)*

Three pieces, in three places:

- **`Dosing`** — a new SwiftPM target with **no dependencies at all** (Foundation only). It holds
  the band classifier, the ratio type, the insulin-on-board curve, and the suggester. Pure
  functions over supplied values; no store, no UI, no clock of its own
  ([10.2](requirements.md#10.2)).
- **`Persistence`** — one migration that DROPS `dose_suggestions`, with the version stamp bumped
  once. No table, no DTO, no store method survives; the only reads this feature makes go through
  the existing `events(in:type:)`. Persistence does **not** import `Dosing` and `Dosing` does
  **not** import Persistence ([10.3](requirements.md#10.3)). *(Redefined in place by
  Decision 18. Superseded wording: "one new table `dose_suggestions`, one DTO, three methods,
  and a guarded-ALTER migration adding `reduction_u` (Decision 17); each schema step lands with
  its own version-stamp bump.")*
- **App** — `DoseComputation` is the only place the two meet: a pure helper that reads
  Settings, pulls the bolus, meal, and intake history it needs from the store, and calls the
  pure suggester; each surface computes its own readout on appearance, and a minimal
  `DoseSeedHolder` carries the dose sheet's seed. Nothing is written. *(Redefined in place by
  Decision 19; Decision 18's wording had `DoseSuggestionModel` publishing a shared readout —
  the class is dissolved. Decision 17-era wording ended "… arms a seed for the dose sheet, and
  writes the ledger row.")*

Requirements traced: [1](requirements.md#1-carbohydrate-ratio-convention-storage-and-configuration)
ratio, [2](requirements.md#2-time-bands-and-local-time-determination) bands,
[3](requirements.md#3-suggested-dose-computation) computation,
[4](requirements.md#4-insulin-on-board-subtraction) insulin-on-board,
[5](requirements.md#5-dosable-increment-rounding-and-boundaries) rounding,
[6](requirements.md#6-presentation-and-interaction) presentation,
[7](requirements.md#7-suggestion-ledger) superseded in full — nothing derived is stored
(Decision 18),
[8](requirements.md#8-fat-and-the-delayed-second-spike--record-and-iterate) fat,
[9](requirements.md#9-the-medreg-boundary) medreg boundary,
[10](requirements.md#10-determinism-offline-operation-and-data-safety) invariants,
[11](requirements.md#11-evidence-gate-before-outcome-scoring) evidence gate.

```
Dosing (SwiftPM target, zero dependencies)          Persistence
  DoseBand.band(at:calendar:)                         events(in:type:) — the only reads
  CarbRatio (g/U) · CarbRatioTable                    (one migration DROPS dose_suggestions)
  InsulinActivityModel.remainingFraction(after:)
  DoseSuggester.suggest(DoseInputs) -> DoseOutcome
          ▲                                                   ▲
          └── App: DoseComputation (+ DoseSeedHolder) ────────┘
           MealReviewView mass line · IntakeView · ResultView · Settings · InsulinDoseSheet seed
```

*(Diagram redefined in place by Decision 18. The Persistence column previously listed
"`dose_suggestions` (new table, v8)", "`DoseSuggestionRecord` (DTO)", and
"`saveDoseSuggestion / linkDose / doseSuggestions`".)*

## Module layout and the firewall (Req 10.3)

Added to `Package.swift` beside `GlucoseWidgetShared`, the existing zero-dependency leaf:

```swift
// Pure dose arithmetic (specs/data/insulin-dosing). Foundation only — the
// dependency list MUST stay empty. Persistence must not depend on it and it
// must not depend on Persistence: the App consumes the pure result directly
// (nothing derived is stored, Decision 18), so no estimation target can reach
// this code even transitively (Req 10.3).
.target(name: "Dosing", path: "MedataCore/Sources/Dosing"),
.testTarget(name: "DosingTests", dependencies: ["Dosing"], path: "MedataCore/Tests/DosingTests"),
```

The firewall here is **structural, not asserted by a graph test**. `GlucoseIngestion` needed a
`dump-package` test because it depends on `Persistence`, which `Pipeline` also depends on, so a
transitive path was possible. `Dosing` has an empty dependency list and nothing but the app target
and its own tests depend on it, so there is no edge for a path to run along. Adding a graph test
would assert a property the package file makes unrepresentable.

*(Superseded by Decision 18: with nothing derived stored, no persisted row type exists on either
side of the firewall — `DoseSuggestionRecord` is deleted with its table, and the question of
where such a type could live is moot. The package comment above is redefined in place with it;
it read "the App composes the persisted row from the pure result". Superseded wording: "The
consequence is that the persisted row type cannot live in `Dosing` (Persistence would have to
import it, and `Pipeline → Persistence` would then reach it). `DoseSuggestionRecord` therefore
lives in `Persistence` and is composed in the app layer from the pure `SuggestedDose` result.
This is the `EstimationOutcome` precedent: Persistence stores the row, the caller supplies the
domain knowledge.")*

## The ratio: one direction, named in the type (Req 1)

```swift
/// Grams of carbohydrate covered by one unit of insulin — the clinical
/// carbohydrate ratio, and the direction medreg fits in. The reciprocal
/// (units per gram) is NEVER stored; `unitsPerTenGrams` is a display
/// derivation only (Req 1.1, 1.2).
public struct CarbRatio: Sendable, Equatable, Hashable {
    public static let permitted: ClosedRange<Double> = 1.0...60.0   // Req 1.5

    public let gramsPerUnit: Double

    /// nil for a value outside `permitted` or a non-finite value; the caller
    /// keeps whatever was previously in force (Req 1.5).
    public init?(gramsPerUnit: Double)

    /// Display only. 5.0 g/U renders "= 2.0 U per 10 g" (Req 1.2).
    public var unitsPerTenGrams: Double { 10.0 / gramsPerUnit }
}
```

There is no type called `Ratio` and no field called `ratio` holding a bare number. Every settings
key, label, and parameter carries `gPerU` / `gramsPerUnit` in its name *(Decision 18: "every
column" — the ratio no longer lands in one)*. The reciprocal exists only as a computed property
whose name states its own direction.

```swift
public struct CarbRatioTable: Sendable, Equatable {
    /// Seeds reproducing the developer's stated rule — 2 U per 10 g at
    /// breakfast, 1 U per 10 g otherwise (Req 1.4).
    public static let seed: [DoseBand: CarbRatio] = [
        .overnight: CarbRatio(gramsPerUnit: 10.0)!,
        .breakfast: CarbRatio(gramsPerUnit: 5.0)!,
        .lunch:     CarbRatio(gramsPerUnit: 10.0)!,
        .dinner:    CarbRatio(gramsPerUnit: 10.0)!
    ]

    public init(configured: [DoseBand: CarbRatio])

    /// Falls back to the seed for an unconfigured band and reports which
    /// applied (Req 1.6).
    public func ratio(for band: DoseBand) -> (value: CarbRatio, isSeed: Bool)
}
```

*(Comment redefined in place by Decision 18. Superseded wording: "and reports which applied, so
the row can record it (Req 1.6, 1.7, 9.4)". The row is gone; the flag remains the explicit
report of Req 1.6's fallback and keeps call sites stable, though no surface renders it in
iteration 1 — the working and the dose sheet caption state the ratio's value, not its
provenance.)*

## Bands: medreg's boundaries, the device's clock (Req 2)

```swift
public enum DoseBand: String, Sendable, Equatable, CaseIterable {
    case overnight, breakfast, lunch, dinner

    /// Half-open local-hour ranges; the boundary hour opens the band it
    /// starts (Req 2.3). 0..<6, 6..<11, 11..<16, 16..<24.
    public var localHours: Range<Int> { ... }

    /// Calendar (and therefore time zone) is injected, never reached for
    /// (Req 2.2, 10.2). `DoseBand.band(at: mealInstant, calendar: .current)`
    /// at the call site.
    public static func band(at instant: Date, calendar: Calendar) -> DoseBand
}
```

The hours are exactly medreg's `TimeOfDaySegment` boundaries (`OVERNIGHT 0–6`, `BREAKFAST 6–11`,
`LUNCH 11–16`, `DINNER 16–24`), evaluated against `calendar.component(.hour, from:)` rather than
`datetime.fromtimestamp(..., tz=UTC).hour`. A value fitted for medreg's `BREAKFAST` therefore
transcribes into this table's `breakfast` field with no conversion of unit or of meaning
([9.5](requirements.md#9.5)) — the only difference is which clock decides which meals were
breakfasts. *(Redefined in place by Decision 18. Superseded wording: "and that difference is
what the recorded `utc_hour` / `utc_offset_s` pair measures ([2.5](requirements.md#2.5))."
Nothing is recorded; the retrospective measurement (Req 11) derives both bandings from the
exported event timestamps and its own declared time zone, so the disagreement stays a
measurable quantity without a stored pair.)*

Band selection needs only the local hour:

```swift
let localHour = calendar.component(.hour, from: mealInstant)
```

*(Redefined in place by Decision 18. Superseded wording computed `utcOffsetS` and `utcHour`
from the same instant, "Both hours come from the same instant" — they existed to fill the row's
pair and leave with it.)*

Daylight-saving transitions need no special handling: `Calendar.component(.hour:)` already returns
the wall-clock hour that was displayed at that instant, which is exactly what "my morning" means.

## Insulin-on-board: medreg's curve, transcribed (Req 4)

The oref0 / LoopKit exponential model, ported from
`~/repos/medreg/src/medreg/models/insulin.py::ExponentialInsulinModel` term for term. Only the
`iob` branch is needed; the `activity` branch is not ported because nothing in the app consumes an
action rate.

```swift
public struct InsulinActivityModel: Sendable, Equatable {
    public let peakMinutes: Double
    public let durationMinutes: Double

    /// medreg's RAPID_ACTING preset (peak 75 min, DIA 360 min), Req 4.1.
    public static let rapidActing = InsulinActivityModel(peakMinutes: 75, durationMinutes: 360)

    /// Fraction of one unit still on board after `minutes`. 1.0 at or before
    /// delivery, 0.0 at or beyond the duration of action (Req 4.3).
    public func remainingFraction(after minutes: Double) -> Double
}
```

Derivation constants, computed once per model instance:

```
tau = tp · (1 − tp/td) / (1 − 2·tp/td)
a   = 2·tau / td
S   = 1 / (1 − a + (1 + a)·e^(−td/tau))

IOB(t) = 1 − S·(1 − a)·[ (t² / (tau·td·(1 − a)) − t/tau − 1)·e^(−t/tau) + 1 ]
         with IOB(t ≤ 0) = 1 and IOB(t ≥ td) = 0
```

For the rapid-acting preset: `tau = 101.785714`, `a = 0.565476`, `S = 2.082955`.

The shared fixture set required by [4.6](requirements.md#4.6) — these values are produced by the
Python model above and are the assertions `DosingTests` checks to `1e-4`, well inside the `0.01 U`
tolerance the requirement sets:

| elapsed (min) | remaining fraction |
|---|---|
| 0 | 1.000000 |
| 30 | 0.929521 |
| 75 | 0.694263 |
| 120 | 0.449752 |
| 180 | 0.208171 |
| 240 | 0.072666 |
| 300 | 0.013918 |
| 360 | 0.000000 |

Summation matches `history.py::bolus_iob` exactly — bolus doses only, basal skipped, a dose counted
only while `0 ≤ elapsed < duration`:

```swift
public struct BolusHistoryEntry: Sendable, Equatable {
    public let minutesBefore: Double   // positive = in the past
    public let units: Double
}

/// Σ units · remainingFraction(elapsed) over prior boluses (Req 4.1–4.4).
/// Empty history is not an error: it yields 0 and the caller proceeds.
public func insulinOnBoard(
    _ boluses: [BolusHistoryEntry],
    model: InsulinActivityModel = .rapidActing
) -> Double
```

The curve was reassessed against a linear decay and an undecayed face-value rule when the
working made legibility a requirement (Decision 19): the exponential stays — it is the one
verified part of the medreg transcription (the fixture parity above), the unoffset set it now
applies to is small, and the working's visible lines still sum because they name each dose,
its time, and its decayed remainder rather than the curve's derivation. Classification of an
insulin event as bolus or basal fails loud ([4.9](requirements.md#4.9)): the shipped
computation `compactMap`ped an unparseable event out of the sum silently — a development-build
assertion replaces that, because the app writes its own insulin events and an unclassifiable
one is a bug, not data. *(Added by Decision 19.)*

**Unoffset membership (Req 4.8).** The curve and the summation above are unchanged — medreg
parity holds ([4.6](requirements.md#4.6)) — but the suggester consumes only the **unoffset**
sum. A bolus is **offset by food** when its timestamp falls within a symmetric ±45-minute
window of any logged meal or carbohydrate intake other than the subject meal itself — the
symmetric window deliberately covers pre-bolusing, insulin taken up to 45 minutes before
eating. There is no stored link and no association table: the window query over recorded events
is the whole mechanism, and the constant is deliberately the same 45 minutes as the seed
lifetime and the [11.2](requirements.md#11.2) pairing window — one association rule, not three.
Offset boluses are excluded from the subtraction; only boluses with no meal or intake in their
window (a correction or freestanding dose) contribute the **unoffset insulin-on-board** the
suggester subtracts ([3.1](requirements.md#3.1), [4.8](requirements.md#4.8)). The membership
test is a pure predicate; the event data it needs is queried by `DoseComputation` (see Data
flow):

```swift
/// True when food stands behind the bolus (Req 4.8): a recorded meal or
/// carbohydrate intake within 45 minutes either side of it, boundary
/// inclusive (|delta| <= 45 min). The symmetric window covers pre-bolusing.
/// Offset boluses never reduce a later meal's coverage.
public func isOffsetByFood(
    bolusInstant: Date,
    mealOrIntakeInstants: [Date],
    window: TimeInterval = 45 * 60
) -> Bool
```

*(Redefined in place by Decision 18. Superseded wording (Decision 17 drafting): membership was
"either the Req 7.5 association already links it to a suggestion row, or its timestamp falls
inside the 45 minutes following a logged meal or intake", and the predicate took an
`isLinkedToSuggestion: Bool`. The stored link went with the `dose_suggestions` store, and the
forward-only window becomes symmetric so a pre-bolus counts as offset.)*

Only the unoffset sum is computed. The physiological total — every bolus, offset or not — was
computed alongside it solely to fill the row's `iob_u`; with nothing recorded no surface
consumes it, so it is no longer computed anywhere. The retrospective measurement (Req 11) can
still derive it off-device from the exported boluses whenever a question needs it. *(Redefined
in place by Decision 18. Superseded wording: "Both figures are computed on every refresh:
`insulinOnBoard` over **all** boluses — the physiological total the ledger's `iob_u` records,
the field meaning what its name says (Req 7.2) — and the same sum over the unoffset subset,
which is what the suggester receives." (Added by Decision 17.))*

Insulin-on-board is an input only *(Decision 18: "and a recorded covariate" is gone with the
row)*. It drives no alert, gate, or refusal
([4.7](requirements.md#4.7)) — a large unoffset standing dose simply produces a smaller number,
`0 U` at the floor, with the reduction visible as its own line in the working
([6.12](requirements.md#6.12)). *(Redefined in place by Decision 17. Superseded wording: "a
large standing dose simply produces a smaller number, or a suppressed one under the 0.5 U
rule.")*

## The suggester (Req 3, 5)

```swift
public struct DoseControlBounds: Sendable, Equatable {
    /// What the dose sheet's stepper can represent: 1...60 U today.
    public let minimumUnits: Double
    public let maximumUnits: Double
}

public struct DosableIncrement: Sendable, Equatable {
    public static let permitted: [Double] = [1.0]                // Req 5.1
    public static let standard = DosableIncrement(units: 1.0)
    public let units: Double
    public init?(units: Double)   // nil for anything outside `permitted`
}

public struct DoseInputs: Sendable {
    public let carbsG: Double?          // nil → suppressed, never defaulted (Req 3.5)
    public let mealInstant: Date
    public let calendar: Calendar       // supplied, never ambient (Req 10.2)
    public let ratios: CarbRatioTable
    public let unoffsetIOBUnits: Double // the Req 4.8 remainder, not the physiological total
    public let increment: DosableIncrement
    public let bounds: DoseControlBounds
}

public enum DoseOutcome: Sendable, Equatable {
    case suggested(SuggestedDose)
    case suppressed(SuppressionReason)
}

public enum SuppressionReason: String, Sendable {
    case noCarbTotal          // Req 3.5 — the sole remaining case
}
```

*(Redefined in place by Decision 17. Superseded wording: `permitted: [Double] = [0.5, 1.0] //
Req 5.6`, `public let iobUnits: Double`, and the cases `belowMeaningfulDose  // exact < 0.5 U,
Req 3.4` and `belowControlMinimum  // rounded < bounds.minimumUnits, Req 5.4`.)* Two shape
decisions here, both taken for call-site stability: **`DosableIncrement` survives with one
permitted value** — `DoseInputs` and the tests keep their shape *(Decision 18: "the ledger's
`increment_u`" is no longer among the keepers — the column is deleted with its table)* while
the 0.5 U pen option is deleted — rather than being replaced by a bare constant; and
**`.suppressed(.noCarbTotal)` survives inside the suggester** rather than moving the nil-carbs
check upstream, so every caller gets the same typed answer for the one absent case
([3.5](requirements.md#3.5)). *(Rationale redefined in place by Decision 18. Superseded
wording: "so the no-carb case keeps producing a ledger row (Req 7.1) through the unchanged
write path" — there is no write path.)* When a carbohydrate total exists, `suggest` always
returns `.suggested` ([3.4](requirements.md#3.4)).

`SuggestionContext` carries the band and the ratio (with its seed/configured flag) that were in
force — exactly what the working's base line and the dose sheet's provenance caption render
([6.12](requirements.md#6.12), design-direction §3.1). *(Redefined in place by Decision 18.
Superseded wording (Decision 17 drafting): "carries the band, hours, offset, ratio and the
physiological insulin-on-board total (the ledger's `iob_u`, Req 7.2) that were in force even
when nothing is suggested, because Req 7.1 records the no-carb-total case as fully as a
suggestion." Nothing is recorded: the hour/offset bookkeeping and the total leave with the row,
and the no-carb case needs no context beyond its typed reason — `.suppressed` carries only its
`SuppressionReason`, the `context:` payload of Decision 17's drafting deleted with them.)*

```swift
public struct SuggestedDose: Sendable, Equatable {
    public let baseUnits: Double          // carbs ÷ ratio, unrounded
    public let reductionUnits: Double     // min(unoffset IOB, baseUnits) — the cap keeps the working summing (Req 6.12)
    public let exactUnits: Double         // baseUnits − reductionUnits, ≥ 0; ≥ 1 dp rendered (Req 5.3)
    public let roundedUnits: Double       // whole multiple of 1 U (Req 5.1)
    public let seedUnits: Int             // what the stepper opens at (Req 6.4); 0 = nothing to seed
    public let seedWasClamped: Bool       // rounded exceeded bounds.maximum (Req 5.5)
    public let context: SuggestionContext
}

public enum DoseSuggester {
    public static func suggest(_ inputs: DoseInputs) -> DoseOutcome
}
```

*(Redefined in place by Decision 18. Superseded wording (Decision 17 drafting):
"`public static let ruleID = "cr-v0"    // Req 7.9`" and "`public static let ruleVersion = 2`",
with "Version-2 rows never pool with version-1 rows (Req 7.9)". Rule identity existed to keep
recorded populations separable; with nothing recorded there are no populations to pool, and the
bookkeeping is deleted. `baseUnits` and the capped `reductionUnits` stay — the working needs
both so its lines sum exactly at every step ([6.12](requirements.md#6.12)). `exactUnits` was
"≥ 2 dp retained (Req 5.3)" for the row; Req 5.3 now asks one decimal place in the rendered
working.)*

The whole rule, in order — and the order matters:

1. `carbsG` absent → `.suppressed(.noCarbTotal)` — the only outcome that is not a number
   ([3.5](requirements.md#3.5)). Every input with a carbohydrate total returns `.suggested`,
   `0 U` included ([3.4](requirements.md#3.4)).
2. `band = DoseBand.band(at: mealInstant, calendar:)`; `(ratio, isSeed) = ratios.ratio(for: band)`.
3. `base = carbsG / ratio.gramsPerUnit`.
4. `reduction = min(unoffsetIOBUnits, base)` — capped at the base so the working's lines sum
   exactly at every step ([6.12](requirements.md#6.12)); `exact = base − reduction` is then ≥ 0
   by construction, which is [3.1](requirements.md#3.1)'s zero floor. *(Citation moved from
   Req 7.2 to Req 6.12 by Decision 18: the cap now serves the rendered working, its only
   consumer.)*
5. `rounded = exact.roundedHalfAwayFromZero` to a whole unit — applied **once**, to the final
   value, never to the carb term or the reduction separately ([5.1](requirements.md#5.1),
   [5.2](requirements.md#5.2)). A `rounded` of 0 is a result to render, not a refusal
   ([3.4](requirements.md#3.4)).
6. `seedUnits = rounded == 0 ? 0 : Int(min(rounded, bounds.maximumUnits).rounded())`, with
   `seedWasClamped` set when `rounded > bounds.maximumUnits`. A `seedUnits` of 0 sits outside the
   control's `1...60` by design — it means no seed is armed, never a clamp upward
   ([5.4](requirements.md#5.4)) — and `exactUnits` passes to the working unchanged either way
   ([5.5](requirements.md#5.5)). *(Decision 18: "recorded unchanged" becomes "passes to the
   working unchanged" — the working is where the unrounded value stays visible now.)*

*(Redefined in place by Decision 17. Superseded steps: "4. `exact < 0.5` →
`.suppressed(.belowMeaningfulDose, …)`. Tested on the **unrounded** value, so a 3 g quick-add at
10 g/U (0.30 U) is suppressed rather than becoming a 1 U dose invented by the stepper's floor"
and "6. `rounded < bounds.minimumUnits` → `.suppressed(.belowControlMinimum, …)`. Reachable only
at a 0.5 U increment". Both suppressions are deleted with the 0.5 U increment; the 3 g quick-add
now reads `0 U` with its working inspectable.)*

Nothing else enters the arithmetic. No fat term, no correction term, no confidence gate
([3.8](requirements.md#3.8)) — that is the point, not an omission: while the dose is exactly
`carbs ÷ ratio − unoffset iob`, an observed outcome attributes to the ratio. The moment a
variable uplift joins it, every outcome becomes `carbs ÷ ratio + unknown` and neither term is
measurable afterwards. *(Decision 18: "a recorded outcome" / "every row" reworded — outcomes
are observed in the event log, not recorded as rows.)*

## Settings: six flat keys, no new shape (Req 1.3, 6.9, 9.4)

`SettingsKeys` has no precedent for a structured or array-valued setting, and this feature does not
introduce one. Six plain keys of the same kind as `insulinTypeBolus` — four ratios, the provenance
and the fit reference:

```swift
// Per-band carbohydrate ratios in GRAMS PER UNIT (Req 1.1). An absent key
// means the seed default is in force (Req 1.6). Never store the reciprocal.
// (Decision 18: "and the suggestion row records that" deleted with the row.)
static let ratioOvernightGPerU = "medata.insulin.ratio.overnight"
static let ratioBreakfastGPerU = "medata.insulin.ratio.breakfast"
static let ratioLunchGPerU     = "medata.insulin.ratio.lunch"
static let ratioDinnerGPerU    = "medata.insulin.ratio.dinner"
// Provenance of the configured ratios: "manual" | "medreg" (Req 9.4); a band
// with an absent per-band key runs on its seed default regardless. (Decision
// 18: "overrides this with 'seed' on that band's rows" — there are no rows.)
static let ratioSource         = "medata.insulin.ratioSource"
// Free text naming the medreg fit the values came from, e.g. an export date
// or run label. Recorded verbatim, never parsed (Req 9.4).
static let ratioFitRef         = "medata.insulin.ratioFitRef"
```

*(Redefined in place by Decision 17. Superseded wording: "Seven plain keys … four ratios, the
increment, the provenance and the fit reference", including the key `// Pen increment in units:
0.5 or 1.0 (Req 5.1, 5.6). static let dosableIncrementU = "medata.insulin.dosableIncrement"`.
The increment is fixed at 1 U, so the key is deleted; a stale stored
`medata.insulin.dosableIncrement` value is simply never read again — no code references the key
and no migration removes it.)*

The existing `Section("Insulin")` in `SettingsView` gains four `LabeledContent` rows in band order,
each a trailing-aligned decimal `TextField` suffixed `g/U`, with the reciprocal rendered beneath as
read-only secondary text:

```
Insulin
  Bolus                                    NovoRapid
  Basal                                       Lantus
  Overnight                            [10.0]  g/U
      = 1.0 U per 10 g
  Breakfast                             [5.0]  g/U
      = 2.0 U per 10 g
  Lunch                                [10.0]  g/U
      = 1.0 U per 10 g
  Dinner                               [10.0]  g/U
      = 1.0 U per 10 g
  Ratio source                    ( Chosen | medreg )
  medreg fit                        [           ]
```

Entry validation is `CarbRatio.init?`: a rejected value leaves the stored value in force and the
field reverts on commit — no error copy, consistent with the developer-phase rule
([6.8](requirements.md#6.8)). *(Redefined in place by Decision 17. Superseded wording: "Entry
validation is `CarbRatio.init?` and `DosableIncrement.init?`" — with the Pen increment row gone,
nothing user-facing constructs a `DosableIncrement`.)*

## Data flow: estimate to suggestion to seed

There is no suggestion model class. Each surface computes its own readout where it renders:
a pure App-layer helper fetches the event window and calls the suggester, and the view holds
the result as local state. The only shared object is the seed holder — the dose sheet's
45-minute seed ([6.4](requirements.md#6.4)) is genuinely cross-surface (armed inside the
Capture cover, consumed by a sheet presented from `AppRoot` after that cover is gone), and
nothing else is.

```swift
/// Pure App-layer computation — no state, no observation. Fetches the
/// 6 h 45 m event window through the store and calls DoseSuggester.
enum DoseComputation {
    static func outcome(for subject: DoseSubject, store: any PersistenceStore) async -> DoseOutcome
}

/// The one shared object: the dose sheet's seed. Owned by AppRoot.
@MainActor @Observable
final class DoseSeedHolder {
    func arm(_ seed: DoseSeed)
    func take() -> DoseSeed?   // nil once consumed or past the 45-minute lifetime
}

struct DoseSeed: Sendable { let units: Int; let armedAt: Date }
```

*(Redefined in place by Decision 19. Superseded: the `@Observable DoseSuggestionModel` with
its published `readout`, `refresh(for:)`/`clear()` choreography and environment injection —
after Decision 18 that class only moved a pure function's result between views, and shared
readout state is where stale-display bugs live; a surface that computes on appearance cannot
show another surface's leftovers. Decision 18's earlier redefinition had already deleted
`noteSavedDose` and `DoseSeed.suggestionID`, which existed to link a saved dose back to a
stored row.)*

`DoseSubject` is the one input shape both paths produce:

```swift
struct DoseSubject {
    let carbsG: Double?
    let instant: Date            // the meal's own timestamp (Req 2.4)
    let sourceEventID: UUID?     // excluded from the offset query when recorded (see below)
}
```

*(Redefined in place by Decision 18. Superseded fields (Decision 17-era): `source:
CarbsSource`, `fatG`, `proteinG`, `sigmaMeal`, `fatStale` — every one existed to fill a row
column. With nothing recorded the subject is its carbohydrate total, its instant, and its own
event id, which the offset query must know so a recorded meal never offsets its own
pre-bolus.)*

`DoseComputation.outcome(for:store:)`:

1. Read the four ratios and the provenance keys from `UserDefaults`; build the `CarbRatioTable`.
   The increment is the fixed `DosableIncrement.standard` (Decision 17).
2. Three queries, all through the existing `events(in:type:)` — no new store API exists or is
   needed. Boluses: `store.events(in: instant.addingTimeInterval(-360*60)...instant, type:
   EventType.insulin)`, decode each row's metadata `kind`, keep `bolus`. The window is exactly
   the duration of action, so the query returns only doses that can contribute
   ([4.3](requirements.md#4.3)). Meals and intakes are two event types, so two further queries —
   `type: EventType.meal` and `type: EventType.intake` — each over
   `instant.addingTimeInterval(-(360+45)*60)...instant.addingTimeInterval(45*60)`: the bolus
   window widened by the association window at **both** ends, because the ±45-minute test is
   symmetric ([4.8](requirements.md#4.8)). Where the subject is already a recorded event
   (history recompute), its own id is dropped from the offset set — a meal never offsets its own
   pre-bolus, so the live computation (subject not yet recorded) and the history recompute agree
   by construction. Classify each bolus with `isOffsetByFood` and sum the unoffset remainder
   into `DoseInputs.unoffsetIOBUnits`. *(Redefined in place by Decision 18. Superseded wording
   (Decision 17 drafting): "the linked ids come from the store's `dose_suggestions` rows over
   the same window, the meal and intake instants from one further `store.events(in:type:)` query
   over `instant.addingTimeInterval(-(360+45)*60)...instant` … then compute both sums: the
   physiological total for the row's `iob_u`, the unoffset remainder …" — no linked ids exist,
   the window reaches forward as well as back, and only the unoffset sum is computed.)*
3. `DoseSuggester.suggest(...)`, publish `readout` — present whenever a carbohydrate total
   exists, `"0 U"` included; nil only for `.suppressed(.noCarbTotal)`
   ([6.6](requirements.md#6.6)). *(Redefined in place by Decision 18. Superseded steps
   (Decision 17 drafting): a `EventType.bsl` query whose last reading was "**Recorded only** —
   no correction term consumes it" — it filled the row's `start_bg_mmol` / `start_bg_age_s`,
   and glucose already lives in the event log for the retrospective measurement to read — and
   "compose a `DoseSuggestionRecord`, and write it in a detached
   `Task { try? await store.saveDoseSuggestion(…) }` so a persistence failure cannot block or
   delay the meal (Req 7.7)". Nothing is composed and nothing is written.)*

The readout refreshes as the review screen's corrections change `pendingTotalCarbsG` — the
suggestion is computed from the total the user will actually record
([3.2](requirements.md#3.2)). Intermediate refreshes update `readout` and nothing else.
*(Redefined in place by Decision 18. Superseded wording: "Only the row for the **recorded**
state is what later analysis reads: intermediate refreshes update `readout` and rewrite the
same row id rather than appending a row per keystroke." There is no row to rewrite.)*

`arm(from:)` runs on `onRecord` (meal) and on save (intake, quick preset) and sets `seed` with a
**45-minute lifetime**. That number is deliberately the same 45 minutes
[11.2](requirements.md#11.2) uses to pair a meal with a bolus retrospectively — and, since
Decision 17, the same window [4.8](requirements.md#4.8) uses to mark a bolus offset by food — so
the live association rule and the measurement's association rule are one constant, not two that
drift. It arms only when `seedUnits >= 1`: a `0 U` result renders its readout but never seeds
the dose control ([3.4](requirements.md#3.4)). *(Arming gate added by Decision 17.)*

## The seam: where 10 U becomes a suggestion (Req 6.3, 6.4)

`InsulinDoseModel.units = 10` and `InsulinDoseSheet.init(store:)` have exactly one construction
site. One optional parameter, defaulted, changes nothing that does not opt in:

```swift
// InsulinDoseModel
init(store: any PersistenceStore, seed: DoseSeed? = nil) {
    self.store = store
    if let seed { units = min(max(seed.units, Self.minUnits), Self.maxUnits) }
}
// (Decision 18: the superseded init also kept `self.suggestionID = seed?.suggestionID`
// for the linkDose write-back; both are deleted.)

// InsulinDoseSheet
init(store: any PersistenceStore, seed: DoseSeed? = nil)

// AppRoot.swift:166 — the sole call site
InsulinDoseSheet(store: store, seed: doseSuggestions.takeSeed())
```

`takeSeed()` returns nil when no seed is armed or the armed seed is older than 45 minutes — and a
`0 U` result never armed one (`arm(from:)` requires `seedUnits >= 1`, Decision 17) — so the home
Dose control and `medata://insulin/add` open at 10 U exactly as today and the two-tap dose path
is byte-for-byte unchanged ([6.3](requirements.md#6.3)). No sheet is presented from inside the
Capture cover, so `AppRoot`'s `pendingDeepLink` sequencing is untouched — the seed is state the
sheet reads when it next opens through the existing route, not a new presentation path.

On a successful save the insulin event's metadata JSON is written exactly as it is today —
`kind`, `insulin_type`, `schema_version`, and `note` when present; no key is added
([9.7](requirements.md#9.7)) — and nothing else happens. The later suggested-versus-given
comparison pairs a dose with its meal by the ±45-minute window over recorded events
([6.10](requirements.md#6.10)), not by a stored link. *(Redefined in place by Decision 18.
Superseded wording: "the model calls `noteSavedDose(eventID:units:)`, which issues
`store.linkDose(suggestionID:insulinEventID:givenUnits:)` — an `UPDATE` on the side table
only." The link went with the table; the Req 7.3 citation goes with superseded Requirement 7.)*

## Presentation (Req 6)

**Meal review.** The suggestion appends to the *existing* second line of `totalRow` — the mass
readout at `MealReviewView.swift:342` — as a middle-dot segment in the same `subheadline
monospacedDigit` at `captureChromeText.opacity(0.75)`:

```
60
g carbs                       [confidence pill]
≈ 214 g on plate · 12 U
```

The worked figure throughout this spec is a 60 g-carbohydrate meal on a 214 g plate at breakfast:
`60 g ÷ 5.0 g/U = 12.0 U`. The large numeral is `pendingTotalCarbsG` and the second line's mass is
`pendingTotalMassG` — two different quantities, never the same number by construction.

Implemented as an `HStack(spacing: 6)` of two `Text`s at identical font, so the line's height is
unchanged and `specs/ui/meal-review` Req 6.6 — the scale control is visible without scrolling when
the surface first appears — is untouched ([6.2](requirements.md#6.2)). The mass `Text` keeps `review.massLine`; the appended one
takes `review.doseSuggestion`. Same `numericText` content transition and `.smooth` animation, both
gated on `accessibilityReduceMotion`, as every other animated numeral on that screen. No accent
colour, no banner card, no second primary control ([6.7](requirements.md#6.7)).

**Manual intake.** `CarbEntrySheet` shows the same `· N U` segment in its existing secondary
line, present whenever a carbohydrate amount is entered, `0 U` included
([6.6](requirements.md#6.6)). Quick-add presets are single-tap buttons whose label is the
carbohydrate figure; adding a second number to that label would rewrite the control, so a preset
tap shows nothing on the button itself and arms the seed *(Decision 18: "and writes its ledger
row" deleted — the intake's history detail recomputes instead)* — the number reaches the
developer one tap later, as the sheet's opening value, and on the intake's history detail. *(Redefined in place by Decision 17. Superseded wording: "Showing nothing is the
specified empty treatment ([6.6](requirements.md#6.6))" — Req 6.6 now governs readout lines,
which always show their number where a carbohydrate total exists; a preset button is a control,
not a readout line.)*

**History detail.** `ResultView` — the single meal-detail surface after `specs/ui/home-router`
Decision 16 deleted `MealOverviewView`, `MealRoute.overview`, and the DEBUG `MealRoute.review`
push — recomputes the suggestion for the meal's own instant (its band, its window) from
recorded events and the settings in force at read time, and renders it beside the carbohydrate
total in the same derived register and middle-dot grammar ([6.10](requirements.md#6.10),
[6.11](requirements.md#6.11)). WHERE a bolus falls within the meal's ±45-minute window
([4.8](requirements.md#4.8)), its given units render beside the suggested ones. A later ratio
change re-renders past meals at the new ratio — accepted: the readout is a present-tense
statement of the rule applied to that meal. *(Redefined in place by Decision 18; navigation per
home-router Decision 16, the Decision 17 addition. Superseded wording: "renders the recorded
suggestion … with the given units alongside once a dose is linked. The values are the recorded
row's own, verbatim; nothing is recomputed for a past meal. A meal with no recorded row shows
no segment." No rows exist; every meal with a carbohydrate total shows its segment.)*

**The working, one tap away (Req 6.12).** On every surface that renders the readout — the review
line, the manual-entry line, the history detail — tapping the dose segment opens the calculation
behind it, in the readout's own grammar (design-direction §2.2, annotated there). The spec's
worked 60 g breakfast, here with a 1.4 U unoffset correction bolus on board:

```
60 g ÷ 5.0 g/U = 12.0 U
− 1.4 U, for insulin on board
= 10.6 U
→ 11 U
```

The base line, one line per reduction in the form `− x U, for <reason>` — unoffset
insulin-on-board is the only reason in this iteration, and a zero reduction renders no line —
then the **unrounded result**, then the **rounding step** to the whole-unit dose. Because the
reduction is capped at the base, the lines sum exactly at every step
(`12.0 − 1.4 = 10.6 → 11 U`, never a hidden jump — [6.12](requirements.md#6.12)). The base,
reduction, and unrounded-result lines state their terms to at least one decimal place
([5.3](requirements.md#5.3)); the whole-unit rule ([5.1](requirements.md#5.1)) governs the dose
figure, which is the working's last line. The working is the same computation on every surface:
live surfaces render the `SuggestedDose` just computed, and history recomputes it identically
for the meal's own instant ([6.11](requirements.md#6.11)) — one code path, so live and history
cannot disagree. The tap reveals provenance, it does not act: nothing is written, no control
appears, and dismissal returns the untouched surface. Arithmetic labelling only — no advice, no
range, no confidence ([6.8](requirements.md#6.8)). *(Added by Decision 17; redefined in place
by Decision 18. Superseded wording: the example ended `= 11 U` with no rounding step, the lines
summed "([7.2](requirements.md#7.2))", and "on history they are reconstructed from the recorded
row's `carbs_g`, `cr_g_per_u`, `reduction_u`, and `rounded_units` — never a recompute".)*

**Nowhere else.** No new screen, no dose-log view (design-direction §6.4 stays future work), no
graph annotation in iteration 1. No
disclaimer, no uncertainty range, no advisory sentence is rendered anywhere
([6.8](requirements.md#6.8)); the only absent segment is a subject with no carbohydrate total
([3.5](requirements.md#3.5)). *(Redefined in place by Decision 17. Superseded wording: "no
refusal reason is rendered anywhere … a suppressed suggestion is simply an absent segment."
Suppressed outcomes no longer exist. Decision 18 removes the second absence, "or a history meal
with no recorded row" — recompute means every history meal with a total has its segment.)*

## Nothing derived is stored (formerly "The ledger", Req 7 — superseded)

*(Section retitled and its substance replaced by Decision 18. It was "The ledger (Req 7)" and
specified the `dose_suggestions` table and its full DDL, the `DoseSuggestionRecord` DTO, three
store methods (`saveDoseSuggestion` INSERT OR REPLACE by id / `linkDose` /
`doseSuggestions(limit:)`), the Decision 17 `reduction_u` guarded-ALTER migration and
`rule_version` 2 stamping, the demo-seeder `carbs_source = 'demo_seed'` row write, a
store-computed `fpu`, a `build_stamp` column, and a no-eviction policy. Requirement 7 is
superseded in full; nothing in this section stores anything.)*

The dose is a pure function of recorded events and stated settings, computable for any instant —
including or excluding any meal. A stored copy of its output is therefore a cache with migration
obligations, not a record: every rule change would need a version bump, every surface a read
path, every association a link column. What matters is already recorded — the meals, intakes,
boluses, and glucose in the event log, and the ratio keys in Settings. Every surface recomputes
from those ([6.11](requirements.md#6.11)); the retrospective measurement recomputes from their
export (Req 11).

One schema migration remains: **DROP `dose_suggestions`**, with the version stamp bumped once.
The version literal lives in **three** places in `GRDBPersistenceStore.swift` — `createSchema`'s
`INSERT OR IGNORE`, `migrate`'s `INSERT OR REPLACE`, and the changelog comment between them;
bump all three together or `migrate` silently re-stamps the database down on every launch
(`docs/agent-notes/persistence.md`). The `saveDoseSuggestion` / `linkDose` /
`doseSuggestions(limit:)` / `doseSuggestion(forSourceEventID:)` API, the `DoseSuggestionRecord`
DTO, and every write path in the App layer are deleted with the table.

The drop discards the rows already written on the developer device. Accepted (Decision 18
consequences): they were computed under the superseded full-subtraction rule, so their
measurement value was already compromised, and everything they were derived from — the events —
survives untouched ([10.5](requirements.md#10.5)).

Export needs no work in the opposite direction to before: `exportArchive` still copies the whole
SQLite file verbatim as `meals.sqlite`, and after the drop there are simply no suggestion rows
in it — medreg reads the events and recomputes, exactly as the app does.

The DEBUG demo-meal seeder (Settings → Seed demo meal) writes nothing dose-related: a seeded
meal is an ordinary meal event, and recompute-at-read shows its dose line and its working on
every surface with zero plumbing. This closes the original invisible-estimate defect outright —
there is no row to be missing.

## Fat: the staged plan (Req 8)

Iteration 1 changes **no number**, and the fat covariates already live where the pipeline writes
them — the meal record's `clinicalTotals` — with `fpu = (fat_g × 9 + protein_g × 4) / 100` a
derivation over them, computed wherever a question needs it, and staleness readable at any time
from `record.userCorrection != nil` ([8.3](requirements.md#8.3)). *(Redefined in place by
Decision 18. Superseded wording: "Iteration 1 records `fat_g`, `protein_g`, `fpu`, and
`fat_stale` on every row and changes no number. What follows is the plan those columns exist to
serve." There are no rows; the fat programme reads the meal's own record.)* What follows is the
plan that evidence exists to serve.

### The four candidate strategies (Req 8.4)

Each is a distinct, identified rule, implemented one at a time so outcomes are attributable to
exactly one ([8.5](requirements.md#8.5)). *(Decision 18 note: "stamped on every row it produces
so outcomes are never pooled across rules (Req 7.9)" described the ledger; nothing is recorded
in iteration 1, so a fat stage that changes numbers must bring its own identification mechanism
with it — Req 8.5's demand stands, the store it stamped does not.)* Sources are the studies
catalogued in `~/repos/medreg/docs/research/carb-absorption.md` §3–4.

| `fat_rule_id` | Trigger | Size | Timing | Source |
|---|---|---|---|---|
| `fat-uplift-v1` | material fat/protein load | +30–35% of the carbohydrate dose | all at meal time | Bell 2015, DOI 10.2337/dc15-0100 |
| `fat-split-v1` | material fat/protein load | +30–35%, delivered 50% now / 50% later | follow-up at ~2.5–3 h | Bell 2015; second-bolus RCT Bell 2016, DOI 10.2337/dc16-0709 |
| `fat-protein-v1` | protein ≥ 75 g alone | a material extra dose | acts 3–5 h post-meal | Paterson, per medreg §3 |
| `fat-fpu-v1` | FPU ≥ threshold | +1 carbohydrate-ratio dose per 100 kcal of fat+protein | extended 3 h (1 FPU) → 6–8 h (large) | Pankowska / Warsaw, DOI 10.1089/dia.2011.0083 |

Two departures from the sources are deliberate and are decisions, not transcription errors:

- **The gate is disjunctive.** Bell's rule fires on `fat > 40 g AND protein > 25 g`, which is
  silent on a 50 g fat / 20 g protein pizza — the exact meal that motivated this work. The gate here
  is `FPU ≥ threshold OR protein ≥ 75 g` ([8.6](requirements.md#8.6)).
- **The threshold is measured, not cited.** It is set at the knee of *this* user's own recorded FPU
  distribution against observed late excursions ([8.7](requirements.md#8.7)). A population constant
  from a paediatric pump study is a starting hypothesis, not a parameter.

Wolpert's ~+42% at ~60 g fat is not a separate rule; it is the upper end of `fat-uplift-v1`'s size
and informs where the size parameter can go, not a fifth implementation.

### Stage gates

| Stage | What ships | Cannot start until |
|---|---|---|
| **F0** (iteration 1) | fat and protein on the meal record (pipeline, unchanged); FPU and staleness derivable at read; nothing dosed | — |
| **F1** | `PbUserCorrection` gains `corrected_fat_g` / `corrected_protein_g`, written from `Macros.reDerive`, which already computes both | nothing — this is independent cleanup and is the cheapest gate to clear |
| **F2** | exactly one rule from the table, default **off**, refusing where the meal's fat is stale ([8.3](requirements.md#8.3)) | all three of [8.8](requirements.md#8.8): F1 done; a late glucose rise associated with high FPU visible in this user's own recorded data; the pipeline's `fat_g` compared against at least one weighed reference meal, since `benchmark_meals` holds `truth_carbs_g` and nothing else |
| **F3** | a delayed follow-up suggestion, with the **actual** elapsed time of the follow-up recorded ([8.9](requirements.md#8.9)) | F2 showing the rule moves the late excursion; plus a notification surface, which the app does not have at all today |
| **F4** | a second rule, arbitrated against the first, stratified by FPU band with n reported per cell | F3 producing follow-ups actually taken |

The honest outcome to plan for: if no late rise is visible in this user's data at F2's gate, the fat
programme stops there and that is a result. Nothing downstream of F0 is scheduled work.

## The evidence gate before any scoring (Req 11)

Iteration 1 scores nothing. Before scoring is even specified, one host-side script runs over an
exported copy of the live database — `tools/dosing/retrospective.py`, emitting compact `key=value`
lines and no narration, like the repository's other tools:

- the `sigma_meal` distribution across existing meal rows (medreg refuses below 0.5 and treats
  `1 − confidence` as the relative carbohydrate standard deviation; adopting either blind is
  meaningless until the real distribution is known);
- the FPU distribution over existing meals — does a fat feature fire weekly or twice a year;
- meal-or-intake to bolus pairing yield inside 45 minutes;
- glucose coverage across the 6 hours after each such dose;
- the rate at which a further bolus lands inside that window;
- **the combined surviving fraction under all the confounding filters** — the single number that
  decides whether an outcome scorer is viable at all.

With three meals a day and a 6-hour window, a low surviving fraction is the likely result, and
[11.3](requirements.md#11.3) makes that an acceptable answer: ratios stay configured values for
longer. The filters are not loosened to improve the number ([11.4](requirements.md#11.4)).

The script takes the ratio table as an explicit declared input ([11.5](requirements.md#11.5)),
so runs before and after a ratio change are distinguishable by their inputs and never silently
pooled. *(Redefined in place by Decision 18. Superseded wording: "The same script is the
backfill if scoring is ever built: run over history, it seeds the ledger with months of rows
scored by identical rules, marked `cr_source = 'backfill'`." There is no ledger to seed; the
script recomputes over the exported event log on every run, which is what makes a backfill
concept unnecessary.)*

## Testing

`DosingTests`, in the executed `make test` surface, over pure functions only:

- band boundaries at 00:00, 05:59, 06:00, 10:59, 11:00, 15:59, 16:00, 23:59, plus a daylight-saving
  transition day and a non-UTC time zone at an instant whose UTC hour falls in a different band
  from its local hour, asserting the local band is chosen ([2.2](requirements.md#2.2));
- `CarbRatio.init?` rejecting 0.9, 60.1, NaN, and infinity, and accepting both interval endpoints;
- rounding: half away from zero at the fixed whole-unit increment, applied once, to the final
  value — [5.2](requirements.md#5.2)'s own examples: `3.5 → 4`, `3.4 → 3`, and `0.6 → 1` (which
  renders AND seeds — the round-up at small carb loads is deliberate), plus a case where
  rounding the carb term and the reduction separately would give a different answer;
- window membership ([4.8](requirements.md#4.8)): a pre-bolus — a bolus up to 45 minutes
  **before** a logged meal or intake — excluded from the unoffset sum; a bolus inside the
  45 minutes after one excluded; a freestanding bolus counted; and the boundary at exactly
  ±45 minutes is **inclusive** (`|Δ| = 45 min` is offset — "within 45 minutes either side",
  read closed), asserted at both edges;
- the subject-meal exclusion: recomputing for a recorded meal never lets that meal offset its
  own pre-bolus, so the history recompute equals the live computation for the same events;
- the working sums at every step: `base − reduction = exact → rounded`
  (`12.0 − 1.4 = 10.6 → 11`), including the cap case — unoffset insulin-on-board exceeding the
  base gives `reduction = base`, `exact = 0`, `rounded = 0`, terms still summing exactly
  ([6.12](requirements.md#6.12));
- the `0 U` outcome: `.suggested` with `roundedUnits == 0` and `seedUnits == 0` — rendered,
  never seeded, never `.suppressed` ([3.4](requirements.md#3.4), [6.4](requirements.md#6.4));
- clamping above 60 U preserving `exactUnits`;
- the insulin-on-board fixture table above, to `1e-4`, plus basal exclusion and a dose at exactly
  360 minutes contributing zero.

*(Redefined in place by Decision 17. Superseded cases: "rounding: half away from zero at both
increments" and "suppression: `exact = 0.49` suppressed, `0.50` suggested, and the
0.5 U-increment case that rounds below the stepper floor". The fixture table is untouched.)*

*(Redefined in place by Decision 18. Superseded cases (Decision 17 drafting): "a bolus linked to
a suggestion row excluded" — no link exists — and the reduction-cap terms as "recorded",
summing per Req 7.2. The non-UTC case asserted "the `utc_hour` / `local_hour` pair asserted
distinct" — nothing computes a UTC hour any more (see Bands), so the case now asserts the band
choice itself. Removed with the machinery: the `PersistenceTests` round-trip through
`saveDoseSuggestion` / `doseSuggestions`, the `linkDose` update, and the assertion that neither
fires `eventsDidChange`. `PersistenceTests` instead covers the one surviving migration: after
`migrate()` on a database that has the table, `dose_suggestions` is absent and the version
stamp reads the new literal.)*

Per the project test gate, the app-target files under `MeData/Tests/` are documentation contracts
and no new ones are written here; the app-side check is that it builds and looks right on device.

## Risks and known gaps

- **The fat figure has never been validated.** `clinicalTotals.fat_g` is computed and persisted but
  read by no app surface, and `benchmark_meals` carries `truth_carbs_g` only. F2's gate exists
  because of this, and iteration 1 dosing off fat would have no way to know it was wrong.
- **A corrected meal's fat goes stale.** `PbUserCorrection` carries carbohydrate only, so the fat
  figure is least trustworthy on exactly the meals that got the most human attention.
  `record.userCorrection != nil` marks the case at read; F1 fixes it. *(Redefined in place by
  Decision 18. Superseded wording: "`fat_stale` flags it in iteration 1" — the flag was a row
  column; the fact it flagged remains readable from the record.)*
- **`sigma_meal` means something slightly different to each repository.** medata's is a geometric
  mean of sub-confidences floored at 0.01; medreg reads it as `1 −` the relative carbohydrate
  standard deviation and refuses below 0.5. It lives on the meal's own estimation record and
  gates nothing until the retrospective measurement shows what its real distribution is.
  *(Reworded by Decision 18: "it is recorded here" claimed the suggestion row; the figure was
  always the estimation record's.)*
- **Local versus UTC banding will disagree whenever the developer is not on UTC.** That
  disagreement is derivable rather than resolved: the retrospective script recomputes both
  bandings from the exported event timestamps and its own declared time zone, and the size of
  the disagreement becomes measurable. *(Redefined in place by Decision 18. Superseded wording:
  "recorded rather than resolved: `utc_hour` and `utc_offset_s` on every row let medreg
  re-derive either banding from the same data".)*
- **The seed is time-boxed, not tied.** A dose sheet opened 46 minutes after a meal opens at 10 U
  with no explanation. That is the intended behaviour of a 45-minute association window, but it will
  occasionally look like the suggestion vanished.
- **A correction bolus inside a meal's ±45-minute window reads as offset.** The
  [4.8](requirements.md#4.8) membership rule cannot tell a correction given just before or just
  after eating from the meal's own bolus, so that insulin is wrongly excluded from the
  subtraction and the next suggestion runs higher than the full-subtraction rule would give —
  with no reduction line in the working to show it. Accepted by Decisions 17 and 18: the window
  is the same constant the seed and the [11.2](requirements.md#11.2) pairing already trust, and
  every event needed to surface the case is in the log for the retrospective measurement to
  find. *(Ending redefined by Decision 18. Superseded wording: "the recorded `iob_u` total
  keeps the case measurable" — no total is recorded; the boluses themselves are.)*
- **A bolus for an unlogged meal counts as unoffset.** Insulin with unrecorded food behind it is
  treated as freestanding and reduces the next suggestion. Accepted by Decision 17 — the model is
  only as good as what is logged, and the reduction appears as its own line in the working
  ([6.12](requirements.md#6.12)), so the mis-attribution is visible at the moment it happens
  rather than silent.
- **A ratio change re-renders history.** Every surface recomputes with the settings in force, so
  changing a band's ratio changes what past meals display, and the number once shown is not
  recoverable anywhere. Accepted by Decision 18 ([6.11](requirements.md#6.11)): the readout is a
  present-tense statement of the rule applied to that meal, and any measurement declares its
  ratio table as an explicit input ([11.5](requirements.md#11.5)) instead of trusting stored
  rows of unstated provenance. *(Added by Decision 18.)*

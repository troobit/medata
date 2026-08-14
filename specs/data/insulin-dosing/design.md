# Design: Insulin Dosing

## Overview

A suggested bolus is `carbs ÷ ratio − insulin-on-board`, chosen by the local time band of the
meal, rounded to the pen's increment, shown as a read-only figure, and recorded — with every
input that produced it — in a derived side table the event log never sees.

Three pieces, in three places:

- **`Dosing`** — a new SwiftPM target with **no dependencies at all** (Foundation only). It holds
  the band classifier, the ratio type, the insulin-on-board curve, and the suggester. Pure
  functions over supplied values; no store, no UI, no clock of its own
  ([10.2](requirements.md#10.2)).
- **`Persistence`** — one new table `dose_suggestions`, one DTO, three methods, `schema_version`
  7 → 8. Persistence does **not** import `Dosing` and `Dosing` does **not** import Persistence
  ([10.3](requirements.md#10.3)).
- **App** — `DoseSuggestionModel` is the only place the two meet: it reads Settings, pulls the
  bolus and glucose history it needs from the store, calls the pure suggester, publishes a
  readout, arms a seed for the dose sheet, and writes the ledger row.

Requirements traced: [1](requirements.md#1-carbohydrate-ratio-convention-storage-and-configuration)
ratio, [2](requirements.md#2-time-bands-and-local-time-determination) bands,
[3](requirements.md#3-suggested-dose-computation) computation,
[4](requirements.md#4-insulin-on-board-subtraction) insulin-on-board,
[5](requirements.md#5-dosable-increment-rounding-and-boundaries) rounding,
[6](requirements.md#6-presentation-and-interaction) presentation,
[7](requirements.md#7-suggestion-ledger) ledger,
[8](requirements.md#8-fat-and-the-delayed-second-spike--record-and-iterate) fat,
[9](requirements.md#9-the-medreg-boundary) medreg boundary,
[10](requirements.md#10-determinism-offline-operation-and-data-safety) invariants,
[11](requirements.md#11-evidence-gate-before-outcome-scoring) evidence gate.

```
Dosing (SwiftPM target, zero dependencies)          Persistence
  DoseBand.band(at:calendar:)                         dose_suggestions (new table, v8)
  CarbRatio (g/U) · CarbRatioTable                    DoseSuggestionRecord (DTO)
  InsulinActivityModel.remainingFraction(after:)      saveDoseSuggestion / linkDose / doseSuggestions
  DoseSuggester.suggest(DoseInputs) -> DoseOutcome
          ▲                                                   ▲
          └───────────── App: DoseSuggestionModel ────────────┘
                 MealReviewView mass line · IntakeView · Settings · InsulinDoseSheet seed
```

## Module layout and the firewall (Req 10.3)

Added to `Package.swift` beside `GlucoseWidgetShared`, the existing zero-dependency leaf:

```swift
// Pure dose arithmetic (specs/data/insulin-dosing). Foundation only — the
// dependency list MUST stay empty. Persistence must not depend on it and it
// must not depend on Persistence: the App composes the persisted row from the
// pure result, so no estimation target can reach this code even transitively
// (Req 10.3).
.target(name: "Dosing", path: "MedataCore/Sources/Dosing"),
.testTarget(name: "DosingTests", dependencies: ["Dosing"], path: "MedataCore/Tests/DosingTests"),
```

The firewall here is **structural, not asserted by a graph test**. `GlucoseIngestion` needed a
`dump-package` test because it depends on `Persistence`, which `Pipeline` also depends on, so a
transitive path was possible. `Dosing` has an empty dependency list and nothing but the app target
and its own tests depend on it, so there is no edge for a path to run along. Adding a graph test
would assert a property the package file makes unrepresentable.

The consequence is that the persisted row type cannot live in `Dosing` (Persistence would have to
import it, and `Pipeline → Persistence` would then reach it). `DoseSuggestionRecord` therefore
lives in `Persistence` and is composed in the app layer from the pure `SuggestedDose` result.
This is the `EstimationOutcome` precedent: Persistence stores the row, the caller supplies the
domain knowledge.

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

There is no type called `Ratio` and no field called `ratio` holding a bare number. Every column,
label, and parameter carries `gPerU` / `gramsPerUnit` in its name. The reciprocal exists only as a
computed property whose name states its own direction.

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
    /// applied, so the row can record it (Req 1.6, 1.7, 9.4).
    public func ratio(for band: DoseBand) -> (value: CarbRatio, isSeed: Bool)
}
```

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
breakfasts, and that difference is what the recorded `utc_hour` / `utc_offset_s` pair measures
([2.5](requirements.md#2.5)).

Both hours come from the same instant:

```swift
let localHour   = calendar.component(.hour, from: mealInstant)
let utcOffsetS  = calendar.timeZone.secondsFromGMT(for: mealInstant)
let utcHour     = Calendar(identifier: .gregorian) /* tz = UTC */ .component(.hour, from: mealInstant)
```

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

Insulin-on-board is an input and a recorded covariate only. It drives no alert, gate, or refusal
([4.7](requirements.md#4.7)) — a large standing dose simply produces a smaller number, or a
suppressed one under the 0.5 U rule.

## The suggester (Req 3, 5)

```swift
public struct DoseControlBounds: Sendable, Equatable {
    /// What the dose sheet's stepper can represent: 1...60 U today.
    public let minimumUnits: Double
    public let maximumUnits: Double
}

public struct DosableIncrement: Sendable, Equatable {
    public static let permitted: [Double] = [0.5, 1.0]           // Req 5.6
    public static let standard = DosableIncrement(units: 1.0)    // Req 5.1
    public let units: Double
    public init?(units: Double)   // nil for anything outside `permitted`
}

public struct DoseInputs: Sendable {
    public let carbsG: Double?          // nil → suppressed, never defaulted (Req 3.5)
    public let mealInstant: Date
    public let calendar: Calendar       // supplied, never ambient (Req 10.2)
    public let ratios: CarbRatioTable
    public let iobUnits: Double
    public let increment: DosableIncrement
    public let bounds: DoseControlBounds
}

public enum DoseOutcome: Sendable, Equatable {
    case suggested(SuggestedDose)
    case suppressed(SuppressionReason, context: SuggestionContext)
}

public enum SuppressionReason: String, Sendable {
    case noCarbTotal          // Req 3.5
    case belowMeaningfulDose  // exact < 0.5 U, Req 3.4
    case belowControlMinimum  // rounded < bounds.minimumUnits, Req 5.4
}
```

`SuggestionContext` carries the band, hours, offset, ratio and insulin-on-board that were in force
even when nothing is suggested, because [7.1](requirements.md#7.1) records suppressions as fully as
suggestions — a band whose ratio suppresses everything is a finding, not an absence.

```swift
public struct SuggestedDose: Sendable, Equatable {
    public let exactUnits: Double         // unrounded, ≥ 2 dp retained (Req 5.3)
    public let roundedUnits: Double       // multiple of the increment (Req 5.1)
    public let seedUnits: Int             // what the stepper opens at (Req 6.4)
    public let seedWasClamped: Bool       // rounded exceeded bounds.maximum (Req 5.5)
    public let context: SuggestionContext
    public static let ruleID = "cr-v0"    // Req 7.9
    public static let ruleVersion = 1
}

public enum DoseSuggester {
    public static func suggest(_ inputs: DoseInputs) -> DoseOutcome
}
```

The whole rule, in order — and the order matters:

1. `carbsG` absent → `.suppressed(.noCarbTotal, …)`.
2. `band = DoseBand.band(at: mealInstant, calendar:)`; `(ratio, isSeed) = ratios.ratio(for: band)`.
3. `exact = max(0, carbsG / ratio.gramsPerUnit − iobUnits)` ([3.1](requirements.md#3.1)).
4. `exact < 0.5` → `.suppressed(.belowMeaningfulDose, …)`. Tested on the **unrounded** value, so a
   3 g quick-add at 10 g/U (0.30 U) is suppressed rather than becoming a 1 U dose invented by the
   stepper's floor ([3.4](requirements.md#3.4)).
5. `rounded = (exact / increment).roundedHalfAwayFromZero * increment` — applied **once**, to the
   final value, never to the carb term or the insulin-on-board term separately
   ([5.2](requirements.md#5.2)).
6. `rounded < bounds.minimumUnits` → `.suppressed(.belowControlMinimum, …)`. Reachable only at a
   0.5 U increment (exact 0.5–0.74 rounds to 0.5, below the stepper's 1 U floor).
7. `seedUnits = Int(min(rounded, bounds.maximumUnits).rounded())`, with `seedWasClamped` set when
   `rounded > bounds.maximumUnits`. `exactUnits` is recorded unchanged either way
   ([5.5](requirements.md#5.5), [5.7](requirements.md#5.7)).

Nothing else enters the arithmetic. No fat term, no correction term, no confidence gate
([3.8](requirements.md#3.8)) — that is the point, not an omission: while the dose is exactly
`carbs ÷ ratio − iob`, a recorded outcome attributes to the ratio. The moment a variable uplift
joins it, every row becomes `carbs ÷ ratio + unknown` and neither term is measurable afterwards.

## Settings: seven flat keys, no new shape (Req 1.3, 6.9, 9.4)

`SettingsKeys` has no precedent for a structured or array-valued setting, and this feature does not
introduce one. Seven plain keys of the same kind as `insulinTypeBolus` — four ratios, the increment,
the provenance and the fit reference:

```swift
// Per-band carbohydrate ratios in GRAMS PER UNIT (Req 1.1). An absent key
// means the seed default is in force and the suggestion row records that
// (Req 1.6). Never store the reciprocal.
static let ratioOvernightGPerU = "medata.insulin.ratio.overnight"
static let ratioBreakfastGPerU = "medata.insulin.ratio.breakfast"
static let ratioLunchGPerU     = "medata.insulin.ratio.lunch"
static let ratioDinnerGPerU    = "medata.insulin.ratio.dinner"
// Pen increment in units: 0.5 or 1.0 (Req 5.1, 5.6).
static let dosableIncrementU   = "medata.insulin.dosableIncrement"
// Provenance of the configured ratios: "manual" | "medreg" (Req 9.4); an
// absent per-band key overrides this with "seed" on that band's rows.
static let ratioSource         = "medata.insulin.ratioSource"
// Free text naming the medreg fit the values came from, e.g. an export date
// or run label. Recorded verbatim, never parsed (Req 9.4).
static let ratioFitRef         = "medata.insulin.ratioFitRef"
```

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
  Pen increment                     ( 0.5 | 1 U )
  Ratio source                    ( Chosen | medreg )
  medreg fit                        [           ]
```

Entry validation is `CarbRatio.init?` and `DosableIncrement.init?`: a rejected value leaves the
stored value in force and the field reverts on commit — no error copy, consistent with the
developer-phase rule ([6.8](requirements.md#6.8)).

## Data flow: estimate to suggestion to seed

`DoseSuggestionModel` is `@MainActor @Observable`, owned by `AppRoot` so a seed armed in the
Capture cover survives that cover's dismissal.

```swift
@MainActor @Observable
final class DoseSuggestionModel {
    /// Live readout for the current pending meal, or nil. Formatted "12 U".
    private(set) var readout: String?
    /// Armed after a meal or intake is recorded; consumed by the dose sheet.
    private(set) var seed: DoseSeed?

    func refresh(for subject: DoseSubject) async
    func arm(from subject: DoseSubject) async
    func takeSeed() -> DoseSeed?
    func noteSavedDose(eventID: UUID, units: Double) async
}

struct DoseSeed: Sendable { let units: Int; let suggestionID: UUID; let armedAt: Date }
```

`DoseSubject` is the one input shape both paths produce:

```swift
struct DoseSubject {
    let carbsG: Double?
    let instant: Date            // the meal's own timestamp (Req 2.4)
    let source: CarbsSource      // .meal | .mealCorrected | .intake | .quickPreset
    let sourceEventID: UUID?
    let fatG: Double?            // clinicalTotals.fat_g
    let proteinG: Double?        // clinicalTotals.protein_g
    let sigmaMeal: Double?       // confidence.sigma_meal
    let fatStale: Bool           // record.userCorrection != nil (Req 8.3)
}
```

`refresh(for:)`:

1. Read the four ratios, the increment, and the provenance keys from `UserDefaults`; build the
   `CarbRatioTable`.
2. `store.events(in: instant.addingTimeInterval(-360*60)...instant, type: EventType.insulin)`,
   decode each row's metadata `kind`, keep `bolus`, map to `BolusHistoryEntry` → `insulinOnBoard`.
   The window is exactly the duration of action, so the query returns only doses that can
   contribute ([4.3](requirements.md#4.3)).
3. `store.events(in: instant.addingTimeInterval(-6*3600)...instant, type: EventType.bsl)`, take the
   last, record its value and age. **Recorded only** — no correction term consumes it
   ([Non-Goals](requirements.md#non-goals)).
4. `DoseSuggester.suggest(...)`, publish `readout` (nil on every suppression), compose a
   `DoseSuggestionRecord`, and write it in a detached `Task { try? await store.saveDoseSuggestion(…) }`
   so a persistence failure cannot block or delay the meal ([7.7](requirements.md#7.7)).

The readout refreshes as the review screen's corrections change `pendingTotalCarbsG` — the
suggestion is computed from the total the user will actually record
([3.2](requirements.md#3.2)). Only the row for the **recorded** state is what later analysis reads:
intermediate refreshes update `readout` and rewrite the same row id rather than appending a row per
keystroke.

`arm(from:)` runs on `onRecord` (meal) and on save (intake, quick preset) and sets `seed` with a
**45-minute lifetime**. That number is deliberately the same 45 minutes
[11.2](requirements.md#11.2) uses to pair a meal with a bolus retrospectively, so the live
association rule and the measurement's association rule are one constant, not two that drift.

## The seam: where 10 U becomes a suggestion (Req 6.3, 6.4)

`InsulinDoseModel.units = 10` and `InsulinDoseSheet.init(store:)` have exactly one construction
site. One optional parameter, defaulted, changes nothing that does not opt in:

```swift
// InsulinDoseModel
init(store: any PersistenceStore, seed: DoseSeed? = nil) {
    self.store = store
    self.suggestionID = seed?.suggestionID
    if let seed { units = min(max(seed.units, Self.minUnits), Self.maxUnits) }
}

// InsulinDoseSheet
init(store: any PersistenceStore, seed: DoseSeed? = nil)

// AppRoot.swift:166 — the sole call site
InsulinDoseSheet(store: store, seed: doseSuggestions.takeSeed())
```

`takeSeed()` returns nil when no seed is armed or the armed seed is older than 45 minutes, so the
home Dose control and `medata://insulin/add` open at 10 U exactly as today and the two-tap dose path
is byte-for-byte unchanged ([6.3](requirements.md#6.3)). No sheet is presented from inside the
Capture cover, so `AppRoot`'s `pendingDeepLink` sequencing is untouched — the seed is state the
sheet reads when it next opens through the existing route, not a new presentation path.

On a successful save the model calls `noteSavedDose(eventID:units:)`, which issues
`store.linkDose(suggestionID:insulinEventID:givenUnits:)` — an `UPDATE` on the side table only. The
insulin event's metadata JSON is written exactly as it is today: `kind`, `insulin_type`,
`schema_version`, and `note` when present. No key is added ([7.3](requirements.md#7.3),
[9.7](requirements.md#9.7)).

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

**Manual intake.** `CarbEntrySheet` shows the same `· N U` segment in its existing secondary line.
Quick-add presets are single-tap buttons whose label is the carbohydrate figure; adding a second
number to that label would rewrite the control, so a preset tap shows **nothing**, arms the seed,
and writes its ledger row. Showing nothing is the specified empty treatment
([6.6](requirements.md#6.6)) and the suggestion still reaches the developer — one tap later, as the
sheet's opening value.

**Nowhere else.** No new screen, no ledger view, no graph annotation in iteration 1. No disclaimer,
no uncertainty range, no refusal reason is rendered anywhere ([6.8](requirements.md#6.8)); a
suppressed suggestion is simply an absent segment.

## The ledger (Req 7)

New table, retrofitted into the existing `createSchema` DDL block with `CREATE TABLE IF NOT EXISTS`
and the version stamp moved 7 → 8 — the `quick_presets` / `estimation_outcomes` /
`correction_records` pattern, applied unchanged.

```sql
CREATE TABLE IF NOT EXISTS dose_suggestions (
    id                TEXT    PRIMARY KEY,
    timestamp         INTEGER NOT NULL,   -- when computed, UTC ms
    meal_timestamp    INTEGER NOT NULL,   -- the instant that selected the band
    row_version       INTEGER NOT NULL,   -- Req 7.8
    rule_id           TEXT    NOT NULL,   -- 'cr-v0'; Req 7.9
    rule_version      INTEGER NOT NULL,
    fat_rule_id       TEXT,               -- null until a fat strategy ships; Req 8.5
    fat_rule_version  INTEGER,
    outcome           TEXT    NOT NULL,   -- 'suggested' | 'suppressed'
    suppression       TEXT,               -- SuppressionReason raw value
    carbs_g           REAL,
    carbs_source      TEXT    NOT NULL,   -- meal | meal_corrected | intake | quick_preset
    source_event_id   TEXT,
    exact_units       REAL,               -- unrounded; Req 5.3
    rounded_units     REAL,
    increment_u       REAL    NOT NULL,
    seed_clamped      INTEGER NOT NULL,
    cr_g_per_u        REAL    NOT NULL,   -- Req 1.7
    cr_source         TEXT    NOT NULL,   -- seed | manual | medreg; Req 9.4
    cr_fit_ref        TEXT,
    band              TEXT    NOT NULL,
    local_hour        INTEGER NOT NULL,
    utc_hour          INTEGER NOT NULL,
    utc_offset_s      INTEGER NOT NULL,   -- Req 2.5
    iob_u             REAL    NOT NULL,   -- Req 4.5
    sigma_meal        REAL,
    start_bg_mmol     REAL,
    start_bg_age_s    INTEGER,
    fat_g             REAL,               -- Req 8.1
    protein_g         REAL,
    fpu               REAL,
    fat_stale         INTEGER NOT NULL,   -- Req 8.3
    given_units       REAL,               -- filled by linkDose; Req 7.5
    insulin_event_id  TEXT,
    build_stamp       TEXT    NOT NULL
);
CREATE INDEX IF NOT EXISTS dose_suggestions_timestamp ON dose_suggestions(timestamp);
```

`fpu = (fat_g × 9 + protein_g × 4) / 100`, computed at write time and stored rather than derived on
read, so a later change to the formula cannot silently reinterpret old rows.

Three store methods, none of which touches `eventsDidChange` ([7.4](requirements.md#7.4)) — the
`quick_presets` and `estimation_outcomes` convention:

```swift
func saveDoseSuggestion(_ row: DoseSuggestionRecord) async throws     // INSERT OR REPLACE by id
func linkDose(suggestionID: UUID, insulinEventID: UUID, givenUnits: Double) async throws
func doseSuggestions(limit: Int) async throws -> [DoseSuggestionRecord]  // newest first
```

**No eviction bound.** `estimation_outcomes` caps at 500 rows because attempts are cheap and
repetitive; suggestions are three to five a day and the entire purpose of the table is longitudinal
evidence, so evicting them would delete the feature's product. Five years is under 10,000 rows.

Export needs no work: `exportArchive` copies the whole SQLite file verbatim as `meals.sqlite`, so
these rows reach medreg with no adapter ([7.6](requirements.md#7.6)).

`build_stamp` reads `MedataBuildStamp` from the bundle, the same lookup `App.swift` and
`MealReviewModel` already make; a plain Xcode Run records `unstamped`, as it does everywhere else.

## Fat: the staged plan (Req 8)

Iteration 1 records `fat_g`, `protein_g`, `fpu`, and `fat_stale` on every row and changes **no
number**. What follows is the plan those columns exist to serve.

### The four candidate strategies (Req 8.4)

Each is a distinct `fat_rule_id`, implemented one at a time and stamped on every row it produces so
outcomes are never pooled across rules ([7.9](requirements.md#7.9), [8.5](requirements.md#8.5)).
Sources are the studies catalogued in `~/repos/medreg/docs/research/carb-absorption.md` §3–4.

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
| **F0** (iteration 1) | fat, protein, FPU, `fat_stale` recorded; nothing dosed | — |
| **F1** | `PbUserCorrection` gains `corrected_fat_g` / `corrected_protein_g`, written from `Macros.reDerive`, which already computes both | nothing — this is independent cleanup and is the cheapest gate to clear |
| **F2** | exactly one rule from the table, default **off**, refusing on `fat_stale` rows | all three of [8.8](requirements.md#8.8): F1 done; a late glucose rise associated with high FPU visible in this user's own recorded data; the pipeline's `fat_g` compared against at least one weighed reference meal, since `benchmark_meals` holds `truth_carbs_g` and nothing else |
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

The same script is the backfill if scoring is ever built: run over history, it seeds the ledger with
months of rows scored by identical rules, marked `cr_source = 'backfill'`.

## Testing

`DosingTests`, in the executed `make test` surface, over pure functions only:

- band boundaries at 00:00, 05:59, 06:00, 10:59, 11:00, 15:59, 16:00, 23:59, plus a daylight-saving
  transition day and a non-UTC time zone with the `utc_hour` / `local_hour` pair asserted distinct;
- `CarbRatio.init?` rejecting 0.9, 60.1, NaN, and infinity, and accepting both interval endpoints;
- rounding: half away from zero at both increments; applied once (a case where rounding the carb
  term and the insulin-on-board term separately would give a different answer);
- suppression: `exact = 0.49` suppressed, `0.50` suggested, and the 0.5 U-increment case that rounds
  below the stepper floor;
- clamping above 60 U preserving `exactUnits`;
- the insulin-on-board fixture table above, to `1e-4`, plus basal exclusion and a dose at exactly
  360 minutes contributing zero.

`PersistenceTests` gains a round-trip through `saveDoseSuggestion` / `doseSuggestions`, a `linkDose`
update, and an assertion that neither fires `eventsDidChange`.

Per the project test gate, the app-target files under `MeData/Tests/` are documentation contracts
and no new ones are written here; the app-side check is that it builds and looks right on device.

## Risks and known gaps

- **The fat figure has never been validated.** `clinicalTotals.fat_g` is computed and persisted but
  read by no app surface, and `benchmark_meals` carries `truth_carbs_g` only. F2's gate exists
  because of this, and iteration 1 dosing off fat would have no way to know it was wrong.
- **A corrected meal's fat goes stale.** `PbUserCorrection` carries carbohydrate only, so the fat
  figure is least trustworthy on exactly the meals that got the most human attention. `fat_stale`
  flags it in iteration 1; F1 fixes it.
- **`sigma_meal` means something slightly different to each repository.** medata's is a geometric
  mean of sub-confidences floored at 0.01; medreg reads it as `1 −` the relative carbohydrate
  standard deviation and refuses below 0.5. It is recorded here and gates nothing until the
  retrospective measurement shows what its real distribution is.
- **Local versus UTC banding will disagree whenever the developer is not on UTC.** That disagreement
  is recorded rather than resolved: `utc_hour` and `utc_offset_s` on every row let medreg re-derive
  either banding from the same data, and the size of the disagreement becomes measurable.
- **The seed is time-boxed, not tied.** A dose sheet opened 46 minutes after a meal opens at 10 U
  with no explanation. That is the intended behaviour of a 45-minute association window, but it will
  occasionally look like the suggestion vanished.

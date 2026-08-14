# Dosing — the pure calculator

`MedataCore/Sources/Dosing` is the zero-dependency SwiftPM target holding the
carbohydrate-ratio type, the band classifier, the insulin-on-board curve and the
suggester. Spec: `specs/data/insulin-dosing` (Phase 1 of `tasks.md`).

## The firewall is the empty dependency list

`Dosing` imports Foundation and nothing else. `Persistence` must not depend on
it and it must not depend on `Persistence` (Req 10.3, Decision 11). There is no
`dump-package` graph test, unlike `GlucoseIngestion`: that target needed one
because it depends on `Persistence`, which `Pipeline` also depends on, so a
transitive path was possible. Here there is no edge for a path to run along, so
a graph test would assert a property the package file already makes
unrepresentable.

The consequence, and it is easy to get wrong: **`DoseSuggestionRecord` cannot
live in `Dosing`.** Persistence would have to import the target, and
`Pipeline → Persistence` would then reach dose arithmetic from the estimation
path. The row type lives in `Persistence` and the App layer composes it from the
pure `SuggestedDose` result — the `EstimationOutcome` precedent.

## `Dosing` needs a library product, not just a target

`design.md` shows only `.target(name: "Dosing", …)`. That is not enough. The iOS
app links SwiftPM code by **product** name (`packageProductDependencies` in
`project.pbxproj` lists products), so `import Dosing` from `App/` cannot resolve
without `.library(name: "Dosing", targets: ["Dosing"])` in the `products` array.
`GlucoseWidgetShared` is the precedent: a zero-dependency leaf that still needed
its own library product to be linkable. The failure mode is nasty — `make test`
passes, because SwiftPM builds targets and test targets regardless, and only
`make build-app` fails. The product line is in `Package.swift` as of Phase 1.

## The ratio direction is the thing to protect

Canonical storage is **`g/U` — grams of carbohydrate covered by one unit**. The
developer's phrasing "2 U per 10 g in the morning" IS 5.0 g/U. A 60 g breakfast
on the breakfast seed is `60 ÷ 5.0 = 12 U`.

The reciprocal is a computed property (`CarbRatio.unitsPerTenGrams`) that exists
for display only and is never stored, never persisted, never a parameter. There
is deliberately no type named `Ratio` and no field named `ratio` holding a bare
number — every name carries `gramsPerUnit` or `gPerU`.
`DoseSuggesterTests.breakfastArithmetic` is the regression guard: if it ever
reads 300 rather than 12, the direction has been inverted somewhere.

## Bands are medreg's hours on the device's clock

`DoseBand` uses medreg's `TimeOfDaySegment` boundaries exactly — 0..<6, 6..<11,
11..<16, 16..<24 — so a value fitted in medreg transcribes with no conversion.
The one difference is the clock: medreg segments in UTC, this segments in local
wall-clock time, because "my morning" is a wall-clock fact.

`BandReading` records `localHour`, `utcHour` and `utcOffsetSeconds` from the
same instant, which turns any local-versus-UTC banding disagreement into a
number the ledger can carry rather than a silent discrepancy.

The `Calendar` is always a parameter. Nothing in this target reaches for
`.current`, `Date()`, `TimeZone.current` or any other ambient value — that is
Req 10.2 and it is what makes every test reproducible.

Daylight saving needs no special case: `Calendar.component(.hour:)` already
returns the wall-clock hour that was displayed at that instant.

## The insulin curve is a cross-repository contract

`InsulinActivityModel` is the oref0 / LoopKit exponential model ported term for
term from `~/repos/medreg/src/medreg/models/insulin.py`
(`ExponentialInsulinModel.iob`), with medreg's `RAPID_ACTING` preset — peak 75
min, DIA 360 min. Derived constants: `tau = 101.785714`, `a = 0.565476`,
`S = 2.082955`.

The fixture table at 0/30/75/120/180/240/300/360 minutes in `design.md` and in
`InsulinActivityModelTests` is a **contract with medreg**, not a local
convenience: Req 4.6 sets a 0.01 U tolerance and the test asserts 1e-4. If it
ever fails, one of the two implementations has a defect — do not widen the
tolerance.

Only the `iob` branch is ported. The `activity` branch is deliberately absent
because nothing in the app consumes an action rate.

Summation copies `history.py::bolus_iob`: boluses only (the caller filters basal
out before building the array), and a dose counted only while
`0 ≤ elapsed < duration`. Empty history yields 0 and is not an error.

## Rounding — the one rule that must not be relaxed

Read `Decision 7` before touching `DoseSuggester.suggest`. Three points do real
safety work:

1. The 0.5 U test is on the **unrounded** value. A 3 g quick-add at 10 g/U is
   0.30 U and must produce **nothing**. Clamping it up to the stepper's floor of
   1 U would be a threefold overdose invented by a user-interface constraint.
2. Rounding is applied **once**, to the final value. Rounding the carbohydrate
   term and the insulin-on-board term separately changes the answer — 27 g at
   10 g/U with 1.4 U on board is 1 U applied once and 2 U applied separately,
   and `roundingAppliedOnce` asserts exactly that difference.
3. Half rounds **away from zero**, not down. Flooring would bias every recorded
   suggestion low by up to a full unit, which is a systematic error in the
   evidence rather than a safety margin.

`SuggestionContext` is carried on a **suppression** as fully as on a suggestion
(Req 7.1). A band whose ratio suppresses everything is a finding, not an
absence, so the band, hours, offset, ratio and insulin-on-board are all recorded
either way.

## What this target must never grow

No fat, protein, glucose-correction, confidence or activity term enters the
arithmetic in iteration 1 (Req 3.8, Decision 6). This is the experimental
control: while the dose is exactly `carbs ÷ ratio − iob`, a recorded outcome
attributes to the ratio. The moment a variable uplift joins it, every row
becomes `carbs ÷ ratio + unknown` and neither term is measurable afterwards.

No fitting, ever. `~/repos/medreg` is the only place parameters are estimated
from history (Req 9.1, 9.2).

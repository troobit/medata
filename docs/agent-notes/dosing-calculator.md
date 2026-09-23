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

The same firewall is why the food-offset membership rule (`FoodOffset.swift`) is
a pure function over `[Date]` and `[DatedBolus]` rather than a query: the caller
reads the events and hands over plain instants, so no store type crosses the
boundary (Req 10.3). `FoodOffsetWindow.bolusSpan` / `.mealOrIntakeSpan` declare
the spans the caller must cover, so the ±45-minute constant lives in one place
rather than being re-derived at each call site.

*(Historical: `DoseSuggestionRecord` used to live in `Persistence` for the same
reason — it could not live in `Dosing` without `Pipeline → Persistence` reaching
dose arithmetic from the estimation path. The DTO and its table are gone as of
insulin-dosing Decision 18; nothing derived is stored.)*

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

Band selection needs only the local hour, and `DoseBand.localHour(at:calendar:)`
is all that remains of the clock bookkeeping. `BandReading` — which carried
`utcHour` and `utcOffsetSeconds` beside it — existed to fill the ledger's hour
pair and left with the ledger (Decision 18). Any local-versus-UTC banding
disagreement stays measurable: the retrospective measurement derives both
bandings off-device from the exported event timestamps and its own declared
time zone (Req 2.5).

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

## Only the unoffset insulin-on-board reaches the subtraction

Read `Decision 17` before touching this. Insulin dosed for food already consumed
is spoken for by that food; counting it against the next meal under-dosed every
meal that followed another inside the duration of action. `isOffsetByFood` is
the whole rule: a bolus with a logged meal or intake within **45 minutes either
side** of it is offset and excluded. The window is symmetric on purpose — a
pre-bolus taken 20 minutes before eating is covered by the meal that follows it,
not freestanding.

Only the unoffset sum is computed. The physiological total over every bolus was
computed alongside it to fill the ledger's `iob_u`; with nothing stored, no
surface consumes it and it is computed nowhere (Decision 18).

The curve and the summation are untouched by any of this, so medreg parity
(Req 4.6) still holds: membership only decides which boluses reach them.

**An unclassifiable insulin event is COUNTED, never dropped** (Req 4.9).
`DoseComputation.classify` returning `nil` means "cannot be classified", not
"ignore" — the caller turns it into a `DatedBolus` anyway. Dropping it is the
tempting shape (`compactMap` invites it, and `assertionFailure` makes it feel
handled) and it is the dangerous one twice over: `assertionFailure` compiles
to nothing in Release, which is the profile the developer actually carries,
and a missing bolus understates insulin already given, so the suggestion comes
back too HIGH. Counting an unknown event can only lower the suggestion. This
exact defect has now been written twice — Decision 19 added Req 4.9 after the
first, and the task-34 rewrite reintroduced it — so treat `compactMap` over
insulin rows as a smell in this file.

## Rounding — the one rule that must not be relaxed

Read `Decision 17` before touching `DoseSuggester.suggest`. Three points do real
work:

1. **There is no floor and no suppression.** A meal with a carbohydrate total
   always renders its number, `0 U` included — a 3 g quick-add at 10 g/U reads
   `0 U` with its working inspectable, and arms no seed (`seedUnits == 0`). An
   absent number is indistinguishable from breakage; `0 U` says what happened.
   `.suppressed(.noCarbTotal)` is the only non-number outcome that exists.
2. Rounding is applied **once**, to the final value. Rounding the carbohydrate
   term and the reduction separately changes the answer — 27 g at 10 g/U with
   1.4 U unoffset on board is 1 U applied once and 2 U applied separately, and
   `roundingAppliedOnce` asserts exactly that difference.
3. Half rounds **away from zero**, not down. Flooring would bias every
   suggestion low by up to a full unit, which is a systematic error rather than
   a safety margin. The increment is fixed at 1 U; `DosableIncrement.permitted`
   holds one value and the type survives only for call-site stability.

`reductionUnits` is **capped at `baseUnits`**, and that cap is load-bearing
rather than defensive: it is what makes `base − reduction == exact` true at
every input, so the tap-through working's lines sum exactly at each step
(Req 6.12) instead of showing `2.0 − 9.0` rendered as `0`.

## What this target must never grow

No fat, protein, glucose-correction, confidence or activity term enters the
arithmetic in iteration 1 (Req 3.8, Decision 6). This is the experimental
control: while the dose is exactly `carbs ÷ ratio − unoffset iob`, an observed
outcome attributes to the ratio. The moment a variable uplift joins it, every
outcome becomes `carbs ÷ ratio + unknown` and neither term is measurable
afterwards.

No fitting, ever. `~/repos/medreg` is the only place parameters are estimated
from history (Req 9.1, 9.2).

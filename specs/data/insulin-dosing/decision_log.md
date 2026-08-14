# Decision Log: Insulin Dosing

## Decision 1: Reverse the "no dose suggestion in the app" non-goal, narrowly

**Date**: 2026-08-14
**Status**: accepted

### Context

`specs/regression-suggestion-integration/prd.md` shipped insulin dose *recording* — the `insulin`
event type, the dose sheet, the chart band, the deep link — and recorded a flat non-goal beside it:

> "No dose suggestion, insulin-on-board, or regression maths in the app — medreg owns all
> modelling, off-device, against exported data."

That non-goal was correct for what it scoped. It kept one model of one person in one place, and it
kept a shipped recording feature small. What changed is not the argument but the use: the developer
wants the number his own rule implies *at the moment he doses*, on the phone, in front of the meal.
An estimate that arrives on a Mac after an export is a post-mortem, not a suggestion. That is a
different feature, and it cannot be delivered without moving some arithmetic on-device.

The non-goal contains three clauses that are separable, and the reversal has to say which fall.

### Decision

Reverse the non-goal **narrowly**: dose-suggestion arithmetic and insulin-on-board move on-device;
parameter fitting and regression maths do **not**. medreg remains the only place any parameter is
estimated from history. The neighbouring non-goal in the same PRD — "No confidence scores, gating,
warnings, reassurance, or disclaimer copy" — is **not** reversed and constrains how the suggestion
may be presented.

A one-line cross-reference is added under that PRD's non-goals pointing at this decision. The PRD
is not otherwise reopened.

### Rationale

The suggestion clause and the fitting clause protect different things. The suggestion clause was
protecting *simplicity* — and a suggestion computed from four numbers a human typed into Settings is
about ten lines of arithmetic, which is not the complexity the clause was defending against. The
fitting clause was protecting *singularity of the model*, and that concern is entirely intact: two
implementations of bounded trust-region least squares over one person's data would drift, and there
is no committed cross-repository agreement test to catch it.

Insulin-on-board is the clause that needs the most justification, because the non-goal names it
explicitly. It is included for a reason that is not safety logic: without it, two boluses inside six
hours make every later outcome unattributable, which destroys the recording this feature exists to
do. It is a confound control and a recorded covariate, not an alarm — Req 4.7 forbids it driving any
gate or refusal presented to the user. It is also a closed-form curve of about forty lines whose
constants medreg publishes, and Req 4.6 pins the two implementations to each other on a shared
fixture set, so "one model" survives it.

### Alternatives Considered

- **Keep the non-goal intact; run `medreg-suggest` against an export**: Zero new code, zero
  divergence, exactly one model — Rejected because the number arrives on a laptop minutes to hours
  after the meal. The feature the developer asked for is a number before the dose, and this does not
  produce one.
- **Reverse the whole non-goal, fitting included**: Port least-squares and the SVD covariance into
  Swift so the app learns its own ratios — Rejected: the heaviest numerical port in the project into
  the language with the weakest numerical-library story, producing two fits over one dataset that
  will drift, with no cross-repository agreement test in existence to notice.
- **Reverse suggestion but not insulin-on-board**, using a "carbohydrates logged after the last
  bolus within 60 minutes" proxy: Cheaper and avoids naming the clause — Rejected because the proxy
  cannot honestly be called insulin-on-board, and without the real thing a stacked bolus makes every
  recorded outcome uninterpretable. That is a false economy in a design whose entire premise is
  future measurability.

### Consequences

**Positive:**

- The suggestion exists where and when it is useful, computed offline and deterministically.
- The reversal is auditable: exactly two named quantities crossed, both verifiable against medreg.
- medreg's identity as the sole fitter is untouched, so the two repositories still cannot produce
  two competing sets of parameters.

**Negative:**

- A shipped PRD's stated non-goal is now partially false, and a reader must follow a cross-reference
  to learn that. Cross-repository documentation drift becomes possible.
- Insulin-on-board now exists twice and must be kept in agreement by a test that has to be
  maintained by hand across two languages.

### Impact

`specs/regression-suggestion-integration/prd.md` (one cross-reference line), `specs/OVERVIEW.md`,
and everything in this spec.

---

## Decision 2: medreg fits, medata transcribes — with provenance on every row

**Date**: 2026-08-14
**Status**: accepted

### Context

medreg already implements almost all of what a serious suggester needs: per-segment carbohydrate
ratio, insulin sensitivity and carbohydrate peak time fitted by bounded least squares with standard
errors and a joint covariance, a time-of-day segmentation, insulin-on-board, a dead-band correction
term, and Monte-Carlo predictive intervals. It also has no export surface whatsoever — its fitted
parameters exist only as in-memory Python dataclasses, and its sole output is formatted text from a
command-line tool. medata, correspondingly, has no import surface: there is no `fileImporter`
anywhere in the app.

So the question is not "reimplement or consume" in the abstract. It is: what contract is worth
building, now, to deliver parameters that have not yet been shown to beat 5 and 10 g/U?

### Decision

The developer runs `medreg-suggest` against an export, reads the printed ratios, and types them into
Settings. Every suggestion the app produces stamps `cr_source` (`seed` | `manual` | `medreg`) and a
free-text `cr_fit_ref` naming the fit they came from. No parameter file format, no importer, no
staleness policy in iteration 1.

### Rationale

This is the cheapest option that is still measurable. Human transcription's only real defect is that
it records no provenance — the app's numbers become unattributable, and nobody can later ask whether
medreg-fitted values did better than the seeds. Stamping the source and the fit reference on every
row removes exactly that defect, for the cost of two Settings fields and two columns.

It also makes the wider contract *earnable* rather than assumed. Once enough rows exist under each
source, seed-prior cohorts and medreg-fitted cohorts can be compared on the same outcome metric. If
fitted parameters win, that comparison is the justification for building a serialiser in medreg and
an importer in the app. If they do not, the most valuable outcome is documented evidence that four
transcribed numbers were sufficient and the pipe was never worth building.

The transcription is safe because the two repositories were made unit-compatible on purpose:
Decision 3 pins the direction to grams per unit, which is what medreg fits in, and Decision 4 pins
the band boundaries to medreg's segment hours. A value moves between them with no arithmetic.

### Alternatives Considered

- **App-local constants only, medreg untouched**: Simplest possible — Rejected because the app would
  then own a second, competing notion of "the right ratio" with no path for medreg's fit to ever
  improve it, and no record of where any value came from.
- **Import a medreg-fitted parameter profile**: Requires a versioned JSON serialiser in medreg
  (nothing in its source serialises a fit result today), the app's first file-import surface, and a
  staleness policy — Rejected for iteration 1: real new contracts in both repositories to deliver
  parameters nobody has yet shown beat the seeds. Revisited once the cohort comparison exists.
- **Port medreg's suggester wholesale to Swift** (dead-band correction, Monte-Carlo interval, both
  refusal paths), parameters still fitted off-device: ~450 lines of dependency-free maths —
  Rejected: it obliges two implementations of the bolus equation to stay bit-comparable, and it
  imports medreg's `MIN_PLATE_CONFIDENCE = 0.5` abstain rule against a `sigma_meal` distribution
  nobody has measured, which could refuse every meal.
- **medreg precomputes a dose lookup table the app interpolates**: No equation in the app at all —
  Rejected: insulin-on-board is continuous and history-dependent and cannot be tabulated, so either
  it is dropped (diverging from the bolus equation) or the app implements it anyway, which is most
  of the port.
- **Port the fitter too, medreg becomes a validation twin**: Rejected as Decision 1 records.

### Consequences

**Positive:**

- No new contract in either repository; medreg stays a strictly read-only consumer.
- Every number the app produces is attributable to a source, which is what makes the later
  comparison possible at all.
- The decision to widen the channel later is made on evidence rather than on architecture taste.

**Negative:**

- Transcription is manual and can be mistyped; the bounds check (1–60 g/U) catches gross errors only.
- Parameters go stale silently — there is no mechanism to notice that a fit is six months old.
- Standard errors, the covariance, and the per-segment refusal reasons medreg holds are all
  discarded at the boundary; only the point estimate crosses.

---

## Decision 3: Ratios are stored in grams per unit, and the reciprocal is display only

**Date**: 2026-08-14
**Status**: accepted

### Context

The developer stated his rule as "2 units per 10 g of carbohydrate in the mornings, reducing to
1 unit per 10 g later in the day". The clinical convention, and medreg's fitted parameter, is the
reciprocal: grams of carbohydrate covered by one unit. `2 U per 10 g` is `5 g/U`; `1 U per 10 g` is
`10 g/U`.

These are inverses, and both are small numbers in overlapping ranges. A field named `ratio` holding
`5` is ambiguous, and reading it in the wrong direction is not a small error — a `5` read as
`5 U per 10 g` instead of `5 g/U` dispenses `0.5 U/g` where `0.2 U/g` was meant, a factor-of-2.5
mistake in the direction that produces an overdose. A `10` misread the same way is a factor of ten.

### Decision

Store grams per unit only. The type is `CarbRatio { gramsPerUnit: Double }`, the column is
`cr_g_per_u`, the Settings field is suffixed `g/U`, and the user's own phrasing is rendered beneath
each field as a read-only derivation: `5.0 g/U` shown with `= 2.0 U per 10 g`. The reciprocal is
never persisted and there is no type or field named `ratio`.

### Rationale

Direction has to live in a name, not in a comment, because comments are not read at the point of a
mistake. `gramsPerUnit` and `cr_g_per_u` cannot be misread; `ratio: 5.0` can.

Choosing medreg's direction means transcription is copy-and-paste with no conversion step, and a
conversion step is exactly where an inversion would hide. Rendering the reciprocal keeps the
developer's mental model on screen without giving it a storage location where it could disagree with
the canonical value.

### Alternatives Considered

- **Store units per 10 g, as the developer phrased it**: Matches his mental model exactly — Rejected
  because every medreg value would need inverting at the boundary, and an inversion that happens
  invisibly at a boundary is the single most dangerous failure mode available here.
- **Store both directions**: Renders either without conversion — Rejected: two fields that must
  agree will eventually disagree. Derive, never duplicate.
- **Store units per gram (not per 10 g)**: Dimensionally cleaner than per-10 g — Rejected for the
  same inversion reason, and it matches neither the developer's phrasing nor medreg's.

### Consequences

**Positive:**

- One direction, stated in every name a developer or a reader will encounter.
- Values move between the repositories unchanged, so transcription cannot introduce an inversion.
- The developer's phrasing stays visible without being authoritative.

**Negative:**

- A larger number means *less* insulin, which is counter-intuitive at a glance and will need the
  reciprocal caption forever.
- Editing Settings means thinking in a direction the developer does not naturally use.

---

## Decision 4: Four bands at medreg's boundary hours, evaluated in local time

**Date**: 2026-08-14
**Status**: accepted

### Context

The developer described a two-level rule: stronger in the morning, weaker later. medreg segments the
day into four — overnight 0–6, breakfast 6–11, lunch 11–16, dinner 16–24 — and keys them on the
event's **UTC** hour, with its own source calling local-time handling a deferred refinement rather
than a solved problem. The app has no time-of-day bucketing at all today.

Two questions therefore have to be answered together: how many bands, and in whose clock.

### Decision

Four bands at medreg's exact boundary hours, evaluated against the **device's local wall-clock
hour**. Seed ratios of overnight 10.0, breakfast 5.0, lunch 10.0, dinner 10.0 g/U reproduce the
developer's two-level rule, the stronger 5.0 g/U applying across 06:00–10:59 only, so the steps are
at 06:00 and 11:00. Boundaries are fixed and not
user-configurable in iteration 1. Every suggestion records the band, the local hour, the UTC hour,
and the local UTC offset in seconds.

### Rationale

Four bands with those seeds *behave* as the developer's two-level rule while *storing* in the shape a
medreg fit produces. Two bands would be closer to what he said and strictly worse as a container: a
transcribed lunch and dinner ratio would have to be collapsed into one number, discarding a fitted
distinction for no benefit.

Local time wins on correctness of meaning. A person's breakfast is a local wall-clock event; UTC
segmentation is simply wrong for this user whenever he is not on UTC, and medreg itself intends to
fix that. But rather than assert the app is right and leave a silent discrepancy, recording both
hours and the offset turns the disagreement into a measurable quantity: medreg can re-derive either
banding from the same rows, and the size of any mis-segmentation is countable rather than suspected.

### Alternatives Considered

- **Two local bands, morning and everything else**: Closest to what the developer said, smallest
  Settings surface — Rejected as a storage shape: it cannot hold a transcribed four-segment fit
  without collapsing two fitted values into one.
- **Four segments in UTC, matching medreg bit for bit**: Guarantees identical banding across the two
  repositories — Rejected: it is wrong for the user whenever he is not on UTC, and it copies a
  shortcut medreg's own source flags as temporary.
- **A continuous taper across the day rather than a step**: Physiologically plausible — Rejected:
  nothing in the literature or in the developer's description supports a particular curve, and a
  taper cannot be transcribed from a segment fit.
- **User-configurable boundary hours**: Rejected for iteration 1: four more Settings fields for a
  parameter nobody has yet wanted to change, and it would break transcription compatibility the
  moment it was used.

### Consequences

**Positive:**

- Observed behaviour is exactly the rule the developer stated, with no extra concepts to learn.
- Storage is already medreg-shaped, so a four-segment fit transcribes field for field.
- The local-versus-UTC divergence is quantified from the first release rather than discovered later.

**Negative:**

- The app and medreg will assign some meals to different bands whenever the offset is non-zero, and
  reconciling that is deferred work in both repositories.
- Four Settings fields exist to express what the developer thinks of as two numbers.
- The 06:00 and 11:00 steps are guesses; nothing yet says the developer's morning resistance starts
  and ends there, and in particular the overnight band is seeded at the weaker 10.0 g/U on the
  assumption that "mornings" begins at 06:00 rather than at midnight.

---

## Decision 5: Suggestions are recorded in a derived side table, not in insulin event metadata

**Date**: 2026-08-14
**Status**: accepted

### Context

A suggestion is worthless as evidence unless the inputs that produced it are recorded with it —
covariates not captured at suggestion time cannot be reconstructed afterwards. Two places could hold
them, and the repository's own documentation points in opposite directions.

medreg's `insulin-event-convention.md` explicitly reserves room for future metadata keys, mandates
that consumers ignore unknown ones, and even pre-names `linked_meal_id` as an anticipated addition —
so extra keys on the insulin row would be technically safe. But `docs/agent-notes/persistence.md:96`
says flatly: "Do not add metadata keys beyond the convention." Something has to give.

### Decision

A new `dose_suggestions` table in the same SQLite database, retrofitted with
`CREATE TABLE IF NOT EXISTS` in the existing DDL block, `schema_version` 7 → 8, writes never firing
`eventsDidChange`. The insulin event's metadata contract is left exactly as it is. A saved dose is
associated by writing the insulin event's id **into the side table**, never the reverse.

### Rationale

The repository already has three precedents for exactly this shape — `estimation_outcomes`,
`correction_records`, `quick_presets` — all derived rows in their own tables, all retrofitted the
same way, none of them touching the event-change notification, and all of them reaching medreg for
free because the export copies the whole database file verbatim. No cross-repository negotiation is
needed and `persistence.md:96` stands unamended.

The deciding argument is capacity, not politeness. Even if extending the insulin metadata were
permitted, a suggestion needs roughly thirty fields — carbohydrate source, fat, protein, fat-protein
units, `sigma_meal`, starting glucose and its age, insulin-on-board, the ratio and its provenance,
the band and three time fields, the increment, the rule id and version, the build stamp. Putting
that in a cross-repository contract that another tool parses would bloat a schema medreg owns, to
hold data medreg does not need in order to read a dose. A side table is where derived analysis data
belongs.

Recording suppressions as rows, not as absences, falls out of the same reasoning: a band whose ratio
suppresses every small meal is a finding.

### Alternatives Considered

- **Extend insulin event metadata with `suggested_units` / `carb_ratio_used` / `suggestion_band`**:
  Technically safe — medreg's parser validates only `kind`, `insulin_type` and `note` and never
  rejects extras — Rejected: it contradicts a recorded rule, widens a schema another repository
  owns, and still cannot carry the covariates without bloating that contract.
- **Compute live and persist nothing**: Cheapest, and it is what both repositories do today —
  Rejected: it forecloses the entire ask. Iterations that are never recorded can never be compared,
  and the covariates cannot be backfilled.
- **Take only the reserved `linked_meal_id` key, side table for the rest**: The one extension that
  needs no negotiation — Rejected as unnecessary: the side table can hold the back-reference itself,
  so no event row needs modifying at all.
- **A separate database file for analysis rows**: Cleaner isolation — Rejected: the export copies one
  file, so a second one would need export plumbing for no gain.

### Consequences

**Positive:**

- The cross-repository contract is untouched; medreg needs no change to keep working.
- Rows are as wide as the analysis needs, and reach medreg verbatim through the existing export.
- Follows three existing precedents exactly, so the retrofit is a known-safe pattern.

**Negative:**

- A schema version bump and a new table for a feature whose analysis consumer does not exist yet.
- Suggestion and dose live in different tables and are joined by a 45-minute association window
  (Decision 12), so the link is heuristic rather than structural.
- Nothing in the app reads the table in iteration 1, so a write bug could go unnoticed until the
  first export is examined.

---

## Decision 6: Fat is recorded from the first release and changes no number

**Date**: 2026-08-14
**Status**: accepted

### Context

The fat double-spike is half of what the developer asked for, and it is the half nobody has a rule
for. A high-fat meal produces a delayed second glucose rise from roughly 3 to 8 hours, while
rapid-acting insulin is largely gone by 4–5. At least four published strategies address it and they
disagree on size, timing and trigger. Fat can also *lower* glucose in the first 2–3 hours, so
front-loading extra insulin risks an early low followed by a late high.

Fat is not blocked on data capture: `ClinicalMacros.fat_g` and `PerClassMacros.fat_g` are computed
from the same corrected mass as carbohydrate and written into every meal's metadata today. A fat
rule could be built this week. Whether it should be is a different question.

### Decision

Record fat grams, protein grams and fat-protein units on every suggestion from the first release.
Let none of them alter the suggested number. Enumerate the four candidate strategies in the design
as identified, versioned iterations, each with its trigger, size, timing and source, so a later
release implements exactly one at a time. Gate any fat strategy that changes a number behind three
verifiable prerequisites (Req 8.8).

### Rationale

Two arguments, and the second is the load-bearing one.

The suggestion arithmetic is the experimental control. While the dose is exactly
`carbs ÷ ratio − insulin-on-board`, a recorded outcome is attributable to the ratio. Fold in a
variable fat uplift and every row becomes `carbs ÷ ratio + unknown`; neither the ratio nor the fat
rule can then be evaluated, and the first thing the fat feature would destroy is the evidence needed
to tune it.

More seriously, the fat figure has no ground truth anywhere in this repository. `benchmark_meals`
carries `truth_carbs_g` and nothing else. No app surface has ever read `clinicalTotals`, so the
number a fat rule would dose off has never been checked against anything. Injecting insulin off an
unvalidated estimate, at a delay, where the error mode is a nocturnal low, is the least defensible
thing this design could do.

Recording costs one copy from data already in the meal's metadata, and it is the only part that
cannot be done retroactively — a covariate absent from a row written last month cannot be recovered.

### Alternatives Considered

- **Ship a fat term in the first release** (a Warsaw-style fat-protein-unit dose, or a Bell uplift):
  Physiologically literate and the developer asked for fat — Rejected on three counts: the fat
  estimate has no ground truth; a variable uplift destroys the carbohydrate term's measurability;
  and a delayed dose depends on a glucose feed whose on-device verification is still open.
- **Defer fat entirely and record nothing**: Smallest first release — Rejected: the covariates cannot
  be backfilled, and the developer explicitly asked for fat to be specified and recorded now.
- **Implement all four strategies behind a switch and alternate between them**: Gathers evidence
  fastest — Rejected: deterministic alternation is not randomisation, a rule that lands
  systematically on Friday pizza is confounded, and four unvalidated rules produce four unattributable
  outcome sets.

### Consequences

**Positive:**

- The carbohydrate ratio stays measurable, which is the precondition for everything downstream.
- Fat-protein-unit evidence begins accumulating immediately, at negligible cost.
- When a fat rule is finally chosen, its threshold can be set at this user's own observed knee
  instead of a paediatric pump study's constant.

**Negative:**

- The developer's motivating problem — the pizza — is not solved in the first release, and the
  suggestion will be visibly wrong for exactly those meals.
- The staged plan has real prerequisites that may never be met, in which case fat is never dosed and
  the recorded columns are only ever evidence of absence.
- Four candidate strategies documented but unimplemented is an invitation to implement two at once
  later; the rule-id stamping exists to make that visible if it happens.

### Impact

Requirement 8, the design's stage-gate table (F0–F4), the `fat_g` / `protein_g` / `fpu` /
`fat_stale` / `fat_rule_id` columns, and Decision 9's correction-schema gap.

---

## Decision 7: Round at the boundary, suppress below half a unit, make the increment a setting

**Date**: 2026-08-14
**Status**: accepted

### Context

`InsulinDoseModel` holds units as an `Int`, clamped 1–60, stepping by 1. The persistence layer
accepts a `Double`. A 62 g meal at 5 g/U is 12.4 U, which the stepper cannot represent; a 3 g
quick-add at 10 g/U is 0.3 U, which is below its floor entirely.

### Decision

Keep the stepper an `Int` and round the seeded value to the configured dosable increment, half away
from zero, applied once to the final value. Record the exact unrounded value on the suggestion row.
Make the increment a Settings choice of 0.5 or 1.0 U, defaulting to 1.0. Suppress the suggestion
entirely below 0.5 U rather than clamping up to the stepper's floor.

### Rationale

The ledger keeps full precision, so nothing about the rounding is lost to later analysis — the
rounding error itself becomes a measurable quantity. The user interface stays exactly as it is,
which matters because the two-tap dose path is a documented property.

The suppression rule is the important half. Clamping 0.3 U up to the stepper's floor of 1 U would be
a threefold overdose *invented by a user-interface constraint*, which is the worst class of bug this
feature could ship. Showing nothing is both safer and honest, and it mirrors medreg's own minimum
meaningful dose.

Making the increment a setting rather than a constant means a half-unit pen becomes a Settings change
instead of a rewrite of the stepper, its hold-repeat schedule and its 72-point numeral — for the cost
of one key and one picker.

### Alternatives Considered

- **Make the stepper fractional at 0.5 U now**: Correct if the developer's pen is half-unit —
  Rejected: it rewrites a shipped control for a device characteristic nobody has confirmed, and the
  setting makes the change cheap later if it turns out to matter.
- **Round down (floor) as the conservative choice**: Never suggests more than the rule implies —
  Rejected: it biases every suggestion low by up to a full unit, which is a systematic error in the
  recorded evidence, not a safety margin.
- **Clamp small doses up to the stepper's minimum of 1 U**: Always produces a number — Rejected: it
  is an overdose created by the control's floor, with no basis in the arithmetic.
- **Round only for display and seed the sheet with the exact value**: Rejected: the sheet cannot
  represent it, so the rounding would just move to a less visible place.

### Consequences

**Positive:**

- No change to a shipped control; the two-tap dose path is bit-identical.
- Full precision survives in the ledger, so rounding error is measurable rather than lost.
- The dangerous boundary case produces nothing instead of producing an invented dose.

**Negative:**

- A 3.4 U suggestion seeds as 3 U — a 12% error, larger than most of the refinements downstream of
  it — and the developer must adjust manually if he cares.
- Small carbohydrate entries produce no suggestion at all, which will read as the feature being
  broken until the rule is remembered.

---

## Decision 8: No outcome scoring until a retrospective measurement says it is possible

**Date**: 2026-08-14
**Status**: accepted

### Context

The point of recording suggestions is eventually to score them: did the dose land the glucose where
it should have? Scoring needs a roughly 6-hour post-dose glucose window with adequate coverage, no
second bolus inside it, and no intervening meal. Nobody knows what fraction of this developer's real
windows survive those filters.

Two facts make the question sharper. With three meals a day, a 6-hour window is confounded by the
next meal most of the time by construction. And the glucose feed itself is not proven: the live
ingestion spec's on-device verification has not closed, historical readings are largely screenshot
extractions rather than a 5-minute feed, and the widget work already demonstrated the feed going
stale under suspension.

### Decision

Iteration 1 scores nothing. Before outcome scoring is specified or built, one host-side script runs
over an exported copy of the live database and reports the confidence distribution, the fat-protein
unit distribution, meal-to-bolus pairing yield inside 45 minutes, glucose coverage across the
following 6 hours, the stacking rate, and — combining these — the fraction of past windows that would
survive the confounding filters. If that fraction is too small to distinguish one ratio from another,
scoring is not built and the ratios stay configured values for longer. The filters are not loosened
to raise the number.

### Rationale

This converts the largest risk in the design from a shipping risk into a measurement, for the cost of
one script. Building the scorer first and finding out afterwards means shipping a feature that
renders empty, which is worse than not shipping it.

The same script is the backfill if scoring is ever built: run over history it produces months of
scored rows on day one, which both seeds the evidence base and validates the refusal rules against
real data rather than against an assumption.

Refusing to loosen the filters matters more than it sounds. A filter tuned until it yields data
yields data that means nothing — and it would do so invisibly, because the output would look
healthier, not worse.

### Alternatives Considered

- **Ship the scorer with the first release and find out**: One fewer step — Rejected: the plausible
  outcome is a table full of unscored windows and a feature that looks broken, on a glucose feed
  whose reliability is not established.
- **Loosen the confounding filters until the yield is acceptable**: Guarantees data — Rejected: it
  guarantees data that cannot support a conclusion, and hides that fact behind a healthy-looking
  number.
- **Score only meals with no other meal for 6 hours** (in practice, dinner): Would raise the
  surviving fraction honestly — Rejected as a decision to make *after* the measurement, not before;
  it also restricts all evidence to one band, which is the band the developer's rule cares least
  about.

### Consequences

**Positive:**

- The riskiest assumption in the design is tested before any code depends on it.
- The measurement script doubles as the backfill, so the work is not throwaway.
- "Not enough clean windows" is an available answer, recorded in the requirements as legitimate.

**Negative:**

- The first release produces evidence it cannot yet evaluate, which is unsatisfying and looks
  incomplete.
- If the answer is negative, ratios remain asserted indefinitely and the ledger's main purpose is
  deferred without a date.

---

## Decision 9: Corrected meals are flagged as stale now, and the correction schema is fixed before any fat rule

**Date**: 2026-08-14
**Status**: accepted

### Context

`PbUserCorrection` carries `corrected_total_carbs_g`, `corrected_per_class` and
`corrected_class_ids` — carbohydrate only. There is no corrected fat and no corrected protein. A meal
the developer relabels or rescales therefore keeps its original pipeline fat and protein forever.

The fat figure is consequently least trustworthy on exactly the meals that received the most human
attention. `Macros.reDerive` already returns a full macro result including protein and fat for the
new class, so the arithmetic exists; only the correction schema and the write path drop it.

### Decision

Iteration 1 records `fat_stale = 1` on any suggestion whose meal carries a user correction. Extending
`PbUserCorrection` with `corrected_fat_g` and `corrected_protein_g`, written from `Macros.reDerive`,
is a hard prerequisite (stage F1) of any fat strategy that changes a number — not a later cleanup.

### Rationale

Splitting it this way keeps iteration 1 small while making the gap impossible to forget. In iteration
1 fat changes nothing, so a stale fat figure costs only some analysis quality, and flagging it is a
one-line write. The moment fat drives a dose, a stale figure becomes a wrong dose, so the schema fix
has to land first — and naming it as a gate in the requirements is what stops it being quietly
skipped when the fat work finally starts.

Flagging alone would not be acceptable as a permanent answer: refusing to run a fat rule on flagged
rows would bias the fat evidence set toward meals the developer did not care enough to correct,
which is precisely the wrong sample.

### Alternatives Considered

- **Fix the correction schema now, in iteration 1**: The maths already exists and it is not a large
  change — Rejected as scope: it touches a protobuf contract, the correction write path and the app
  readers, for a benefit that only materialises when fat drives a number, which is at least two
  validation steps away.
- **Flag stale rows and leave it there permanently**: Cheap and honest — Rejected: it permanently
  biases the fat evidence toward uncorrected meals.
- **Ignore the gap**: Rejected: it silently produces a fat model that is wrongest on the meals with
  the most human attention on them.

### Consequences

**Positive:**

- The gap is recorded on every affected row from the first release, so its prevalence is measurable
  rather than estimated.
- The fix is named as a gate with a specific implementation path, not left as a known issue.

**Negative:**

- Rows written before the schema fix carry stale fat permanently; that history cannot be repaired.
- A protobuf contract change is deferred, and deferred schema changes tend to grow more callers.

---

## Decision 10: A new spec at `specs/data/insulin-dosing`, not an extension of the shipped PRD

**Date**: 2026-08-14
**Status**: accepted

### Context

`specs/regression-suggestion-integration` is the natural-looking home: same insulin surface, same
event stream, same dose sheet. The process guidance prefers extending an existing spec over opening a
new one. But that folder is a PRD-lane spec — `prd.md` plus three task files — marked Done with all
its tasks closed, and it contains no `decision_log.md`.

### Decision

A new full spec at `specs/data/insulin-dosing/` with requirements, design, decision log,
prerequisites and tasks. Two small accompanying edits that do not reopen the old spec: a one-line
cross-reference under its non-goals pointing at Decision 1, and a row plus section in
`specs/OVERVIEW.md`.

### Rationale

Three facts override the preference for extension. The old folder is a *record of what shipped*;
reopening a closed PRD to negate its own non-goal destroys it as a record rather than extending it.
It has no decision-log convention, so the reversal ADR — the one thing that must not happen as a
silent edit — would have nowhere to live. And the surfaces differ more than they appear: that spec
was about *recording* doses to a convention another repository owns; this one is about *suggesting*
them, and its deliverables are a new pure package target, a derived table at schema version 8, and a
renegotiated cross-repository boundary.

`specs/data/` is the right domain — sibling to `cgm-connect`, `event-log-schema`, `libre-ingestion`
and `manual-carb-intake` — because the substance is persistence and boundary. The user-interface
footprint is three lines across existing screens and a handful of Settings rows.

### Alternatives Considered

- **Extend `regression-suggestion-integration`**: Honours the preference and keeps insulin work in
  one folder — Rejected: it is a closed record with no decision-log convention, and the reversal
  would be invisible.
- **A new spec under `specs/ui/`**: The developer sees this as a screen change — Rejected: the
  user-interface footprint is a few lines; the substance is a table, a pure module and a
  cross-repository boundary.
- **A smolspec**: Smaller ceremony for what is arguably a small feature — Rejected: a reversal of a
  recorded non-goal and a schema change both need a decision log, which a smolspec does not carry.

### Consequences

**Positive:**

- The shipped PRD survives intact as a record of what shipped.
- The reversal, the boundary and the fat plan all have a documented home.
- Placement matches the domain siblings, so the overview stays coherent.

**Negative:**

- Insulin work is now described in two spec folders and a reader must follow a cross-reference.
- A full five-document spec for a feature whose first release is modest.

---

## Decision 11: `Dosing` is a zero-dependency target and the persisted row lives in `Persistence`

**Date**: 2026-08-14
**Status**: accepted

### Context

Requirement 10.3 says the dose computation must not be reachable from, or depended on by, the
carbohydrate-estimation modules. The obvious layout — one `Dosing` target holding both the maths and
the persisted row type — fails that test: `Persistence` would have to depend on `Dosing` to store the
row, and `Pipeline` depends on `Persistence`, so every estimation target would reach the dose code
transitively.

`GlucoseIngestion` faced the same shape and solved it with a package-graph test that walks the
transitive closure from `swift package dump-package`.

### Decision

`Dosing` is a SwiftPM target with an **empty dependency list** (Foundation only), holding the band
classifier, the ratio type, the insulin-on-board curve and the suggester. The persisted
`DoseSuggestionRecord` lives in `Persistence`, which does not import `Dosing`. The app layer is the
only place the two meet: it composes the row from the pure result. No graph test is added.

### Rationale

An empty dependency list makes the violation unrepresentable rather than detectable. `GlucoseIngestion`
needed a test because it genuinely depends on `Persistence`, so a transitive path existed and had to
be policed; here there is no edge for a path to run along. Adding a test would assert a property the
package manifest already makes impossible, which is ceremony rather than protection.

The cost is that the pure result and the persisted row are two types with overlapping fields, mapped
in the app. That mapping is exactly the `EstimationOutcome` precedent, where `Persistence` stores the
row and the caller supplies the domain knowledge — including, there, an injected food lookup for the
same layering reason.

### Alternatives Considered

- **One `Dosing` target holding the maths and the row, with `Persistence` depending on it**: Fewer
  types, no mapping — Rejected: it puts dose code inside every estimation target's link closure,
  violating Req 10.3 as written.
- **Put the maths in `Persistence` directly**: No new target at all — Rejected: it buries pure,
  heavily tested arithmetic inside a GRDB-dependent module and makes the same reachability problem
  worse.
- **Keep the empty dependency list but add the graph test anyway**: Belt and braces — Rejected: the
  test would assert what the manifest already guarantees, and a test that cannot fail is noise.

### Consequences

**Positive:**

- The firewall is structural: no estimation target can reach dose code, transitively or otherwise.
- The maths is pure, Foundation-only and fast to test, with no store or user-interface dependency.
- No new test scaffolding, consistent with the project's test gate.

**Negative:**

- Two types describing one suggestion, with a hand-written mapping in the app that can drift.
- If `Dosing` ever needs a dependency, the structural guarantee evaporates and the graph test becomes
  necessary after all.

---

## Decision 12: Suggestion and dose are joined by a 45-minute association window

**Date**: 2026-08-14
**Status**: accepted

### Context

The suggestion is produced on the meal review screen; the dose is recorded later, through a sheet
reached from the home control or a deep link. Nothing structurally connects them — the dose sheet has
no meal context at all, and the insulin event carries no meal back-reference. Requirement 7.5 asks
that a suggestion and the dose it plausibly refers to be associated so the two amounts can be
compared.

### Decision

Recording a meal or an intake arms a seed carrying the suggestion's identifier, with a **45-minute**
lifetime. The next dose sheet opened within that window opens at the suggested amount and, on save,
writes the saved event's identifier and the amount actually given back onto the suggestion row. After
45 minutes the seed expires and the sheet opens at the standing 10 U default. The same 45 minutes is
the pairing window the retrospective measurement uses.

### Rationale

One constant, used by both the live association and the retrospective measurement, cannot drift apart
into two different definitions of "the dose for this meal". That matters more than the specific value:
if the live rule paired at 45 minutes and the measurement at 30, the two would disagree about the same
history.

Forty-five minutes is long enough to cover capture, review, plating and sitting down, and short enough
that an unrelated dose taken hours later is not silently attributed to a meal. medreg pairs at 30
minutes; the wider window here is deliberate, because a missed association loses a row of evidence
whereas the association itself is recorded and can be filtered more strictly later.

The alternative shapes all require the dose sheet to know about meals, which would either add a
presentation path from inside the Capture cover or add a meal picker to a sheet whose entire premise
is two taps.

### Alternatives Considered

- **Present the dose sheet directly from the meal review screen**: A structural link, no window
  needed — Rejected: it adds a second presentation path from inside a full-screen cover, outside the
  root's existing deep-link sequencing, and it turns the two-tap capture path into three taps by
  coupling meal logging to dosing.
- **Add a meal picker to the dose sheet**: Explicit and unambiguous — Rejected: it defeats the sheet's
  two-tap premise for a link the developer would have to make by hand every time.
- **Do not associate at all; compare suggested and given only in retrospect**: Simplest — Rejected:
  the retrospective join would be the only one, with no record of what the developer actually saw
  when he dosed.
- **A 30-minute window, matching medreg**: Rejected: a missed association costs a row of evidence, and
  the window can always be tightened during analysis, never loosened after the fact.

### Consequences

**Positive:**

- The suggested and given amounts are paired at the moment they happen, with the pairing rule stated
  once and shared with the measurement.
- No new presentation path, and both documented two-tap paths are unchanged.

**Negative:**

- The association is heuristic: a dose taken 46 minutes after a meal is unlinked, and a dose taken
  within 45 minutes for an unrelated reason is mislinked.
- A sheet opened just outside the window silently shows 10 U with no explanation of why the suggestion
  disappeared.

---

## Decision 13: Basal is scheduled and paired with activity, but never adjusted in iteration 1

**Date**: 2026-08-14
**Status**: accepted

### Context

The spec as first authored covered bolus only — a carbohydrate ratio applied to
an estimated meal. The developer subsequently supplied the other half of the
regime: a standing basal of a nominal 15 U at 07:30 and a nominal 15 U at 19:30,
where activity moves the evening dose **down**, more cardiovascular work moves it
further down, and the effect carries a tail into the following morning's dose.

Basal is already recordable — `InsulinKind.basal` ships, with the bolus/basal
toggle, its own chart glyph, and a Lantus default. What was missing is the
*schedule* and the *covariate*: nothing in the app knows what the standing doses
are, and nothing records what the developer did that day.

The temptation is to close the loop immediately, since the relationship is
described confidently and the arithmetic would be trivial. The developer's own
framing forecloses that: the relationship is "infinitely fine tunable" but
"should not overcomplicate", with the key being "simplicity in UI/UX to get good
quality data".

### Decision

Record the standing schedule as configurable seeded values (Req 12.1, 12.2), and
pair every recorded basal dose with the activity preceding it (Req 12.4, 12.5).
Compute no adjustment (Req 12.3). The lookback must span an evening session
through to the following morning's dose (Req 12.6), because the stated tail
crosses that boundary.

The direction of the relationship is **not** restated here. It is recorded once
in `specs/data/activity-events` Decision 1, and Req 12.8 requires any future
adjustment to cite that rather than re-derive it.

### Rationale

The magnitude is unknown, and a magnitude invented to express a known direction
becomes indistinguishable from a fitted one the moment it is in the codebase.
Pairing dose to activity from the first release is what makes the magnitude
fittable later; it is also the only part that cannot be reconstructed
retrospectively, since activity that was never logged leaves no trace.

Deferring the adjustment costs nothing that is recoverable later, and shipping it
early costs the ability to attribute any observed change to the ratio rather than
to the activity term — the same attribution argument that keeps fat out of the
bolus in iteration 1.

Not restating the direction is a deliberate guard. The relationship was very
nearly recorded inverted, and prose restatements of a signed quantity are how
sign errors propagate.

### Alternatives Considered

- **Ship a seed reduction per active day**: for example, a fixed 2 U off the
  evening dose after any logged activity — Rejected: no measured magnitude
  exists, the correct value plainly differs between a gentle walk and a waterpolo
  match, and a seeded number in an insulin path is acted on regardless of the
  label attached to it.
- **Scale the reduction by cardiovascular character**: a larger reduction for
  `aerobic` than for `anaerobic` — Rejected for the same reason one step further
  on: it invents a whole coefficient table rather than a single number, and
  Decision 1 of the activity spec already records that an anaerobic session may
  not reduce requirement at all.
- **Leave basal out of this spec entirely**: keep the spec bolus-only and open a
  third one later — Rejected: the covariate pairing has to exist at write time or
  the data is not recoverable, and basal doses are already being recorded today,
  so every day this is deferred is a day of unpaired rows.
- **Prompt for the basal dose at its scheduled time**: use the schedule as a
  reminder — Rejected explicitly in Req 12.7. There is no notification surface in
  the app, adherence prompting is a behaviour-change feature rather than a
  measurement one, and it is adjacent to the reassurance copy the developer-phase
  rule forbids.

### Consequences

**Positive:**

- The activity-to-basal relationship becomes measurable from the first release
  rather than after a later spec lands.
- No invented coefficient enters an insulin path.
- The schedule is configurable, so the seeded 15 U values carry no more authority
  than the carbohydrate ratios do.
- One authoritative statement of the relationship's direction, cited rather than
  copied.

**Negative:**

- The developer logs activity and takes basal doses for some period with no
  visible benefit from the pairing, which is the condition under which logging
  discipline lapses — and lapsed logging biases exactly the corpus this exists to
  build.
- A nominal schedule that is never enforced or reminded will drift from what is
  actually taken, so the recorded schedule is a statement of intent and the
  recorded doses are the truth; anything fitting on the two must prefer the
  latter.
- Req 12.4's pairing depends on `specs/data/activity-events` shipping first,
  which makes this spec's basal half blocked on another spec's completion.

### Impact

Adds Requirement 12 to this spec. Creates a dependency on
`specs/data/activity-events` (Req 5.1's lookback query). No change to the insulin
event's metadata contract, which medreg owns — the pairing is recorded on the
suggestion row, not on the dose.

---

## Decision 14: A shared dose is a fourth confounding filter, alongside the intervening meal

**Date**: 2026-08-14
**Status**: accepted

### Context

Decision 8 named three confounding filters for the D0 retrospective measurement: adequate glucose
coverage, no second bolus inside the 6-hour window, and no intervening meal. The instrument built for
that measurement — `tools/dosing/retrospective.py` — implemented the intervening-meal filter as a
time span opening at the paired dose.

Reviewing it found that a span anchored on the dose cannot express the confound it is meant to catch.
A manual intake at 12:00, one dose at 12:05, and a plate at 12:20 is an ordinary pattern: one dose
covers two carbohydrate events. Neither event sits inside a span that opens at the other's dose, so
both windows read as clean, and each attributes the whole trajectory to its own carbohydrates. That
inflates the surviving fraction — the single number Req 11.2 exists to produce and Req 11.4 exists to
protect.

### Decision

Sharing a dose is a distinct confounding filter with its own name, `no_shared_bolus`, applied
between the stacking filter and the intervening-carbohydrate filter. A window is confounded when
another carbohydrate event is paired to the same bolus, whatever their spacing. The
intervening-carbohydrate span is separately widened to open at the earlier of the carbohydrate event
and its dose, so a pre-bolus no longer hides an event that precedes the meal.

### Rationale

Whether two carbohydrate events share a dose is a fact about pairing, not about elapsed time, and no
interval anchored on one of them is guaranteed to contain the other. Expressing it as a span was the
category error; expressing it as a pairing test makes it exact and makes the widened span an
independent improvement rather than a patch over the same hole.

Keeping the two filters separate, rather than folding sharing into `intervening_carb`, preserves what
the attrition waterfall is for. Decision 8 requires each filter to print its own attrition so a
reader can see which one consumed the windows; a merged flag would report a number without saying
which confound produced it.

This is a tightening. Req 11.4 forbids loosening a filter to raise the surviving fraction and says
nothing against correcting one that was too loose to be true — the surviving fraction can only fall.

### Alternatives Considered

- **Widen the intervening-carbohydrate span alone**: One filter instead of two — Rejected: it does
  not work. Where the dose precedes the meal, an event before that dose is outside any span anchored
  on either the meal or the dose, and that is precisely the pattern found.
- **Fold the shared-dose test into `intervening_carb`**: Fewer lines in the waterfall — Rejected:
  the waterfall exists so each filter's attrition is separately visible, and two different confounds
  under one name defeat that.
- **Leave it and note the bias in the write-up**: No code change — Rejected: the surviving fraction
  is the number that decides whether outcome scoring is built at all, and a known upward bias in it
  is not something a footnote repairs.

### Consequences

**Positive:**

- The headline surviving fraction is no longer inflated by dose-sharing, which is common with manual
  intakes recorded near a meal.
- The waterfall attributes each lost window to the specific confound that consumed it.

**Negative:**

- The surviving fraction will be lower than the pre-fix instrument would have reported, making the
  Req 11.3 outcome — that scoring is not viable on this history — more likely.
- Two filters where Decision 8 named one, so anyone reading that decision alone will see a filter
  set that no longer matches the instrument.

### Impact

`tools/dosing/retrospective.py` and its tests. No change to any requirement: Req 11.2 names the
filters only as "the confounding filters". Task 16's measurement is unaffected in kind — it remains
blocked on a human-produced export.

---

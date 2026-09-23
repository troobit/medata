# Decision Log: Activity Events

## Decision 1: Record the activity-to-insulin direction once, as a stated fact

**Date**: 2026-08-14
**Status**: accepted

### Context

The developer's dosing rule couples activity to basal insulin: the nominal 19:30
dose of 15 U goes **down** on active days, more cardiovascular work reduces it
further, and the effect carries a tail that reaches the following morning's dose.

This direction was very nearly recorded backwards. The originating note read
"≥ 15 U ... based on exercise or activity", which reads naturally as *activity
raises the dose*. It does not. Direct clarification established the inverse.
There is also a genuine physiological reason the wrong reading is plausible:
anaerobic, intermittent-intensity work such as waterpolo can raise glucose
acutely through catecholamine release, so a rule of "exercise means less insulin"
is not universally true and an author reasoning from first principles can talk
themselves into either sign.

A sign error in an insulin relationship is the highest-severity defect this
project can produce. It must be written down once, in one place, and cited rather
than re-derived.

### Decision

Record the direction in this decision, as the single authoritative statement:
**activity reduces insulin requirement; more cardiovascular work reduces it
further; the effect decays over roughly a day.** Requirement 5.4 points here.
Any model, document or code comment that consumes activity cites this decision
rather than restating the relationship in its own words.

### Rationale

Restating a signed relationship in prose at every site is how sign errors get
introduced — each restatement is a fresh chance to invert it, and no single
restatement is authoritative enough to correct the others. One citable source
makes an inversion a contradiction against a named decision rather than a
plausible alternative reading.

Recording it as a *fact to consume* rather than as a *formula to apply* also
keeps this spec honestly scoped: the magnitude is unknown and is to be fitted
from data, so committing to a coefficient here would be inventing a number.

### Alternatives Considered

- **State the direction in the requirements only**: Put it in Req 5.4 and omit
  the decision — Rejected because requirements get amended in place and this
  project has no internal versioning pre-release, so the reasoning behind the
  sign (and the fact that it was nearly recorded backwards) would be lost at the
  first edit.
- **Encode the direction as a signed coefficient in code**: Ship a constant such
  as a per-character reduction factor — Rejected because no measured magnitude
  exists. A coefficient invented to express a direction reads as a fitted value
  to every later reader and would be trusted as one.
- **Defer the direction until the dosing spec needs it**: Record only that
  activity matters — Rejected because the covariate's whole justification is the
  relationship; a reader encountering the event type with no stated direction has
  no way to tell whether a later model got the sign right.

### Consequences

**Positive:**

- One place to check when auditing any activity-driven adjustment for sign.
- The near-miss is preserved, so a future reader understands why the statement is
  emphatic rather than incidental.
- No invented magnitude enters the codebase.

**Negative:**

- A stated direction with no magnitude cannot be tested, so nothing in CI defends
  it — the protection is editorial, not mechanical.
- The anaerobic exception noted in Context is real and this decision flattens it
  into "more cardiovascular reduces it further"; a kind whose character is
  `anaerobic` may not reduce requirement at all, and that only surfaces once
  there is data.

---

## Decision 2: Carry a cardiovascular character per kind, not a numeric intensity

**Date**: 2026-08-14
**Status**: accepted

### Context

The stated relationship scales with how cardiovascular the work is. That
suggests capturing intensity. But the governing constraint on this spec is
capture simplicity — the sibling PRD already recorded that dose logging which is
not fast and easy produces worthless regression data, and the same applies here.

Asking for an effort rating on every save adds a decision to every log, and
self-rated intensity is noisy across days and moods in a way that a kind label is
not. Meanwhile the kinds themselves already carry most of the signal: swimming
laps and playing waterpolo are reliably different activities.

### Decision

Each activity kind carries a fixed `aerobic` / `anaerobic` / `mixed` character.
No per-event intensity, effort rating, or calorie figure is collected
(Req 2.4).

### Rationale

The character is a property of the activity, not of the session, so it costs
nothing at entry time — it is looked up from the kind the developer already
picked. It gives a regression a way to pool sparse kinds (`run` and `cycle`
share `aerobic`) without collapsing them, which matters when a single-user corpus
has very few events per kind. It also gives a later model a defensible way to
handle a kind it has never seen.

Duration remains available and optional, which is the one intensity-adjacent
quantity that is objective and that a watch will later fill in automatically.

### Alternatives Considered

- **Per-event intensity slider (1–10)**: Ask on every save — Rejected: adds a
  decision to every entry against an explicit simplicity constraint, and
  self-rating drifts, so the axis would be noisy exactly where it needs to be
  comparable across months.
- **Derive intensity from heart rate**: Wait for watch data — Rejected: that data
  does not exist yet, and this spec's whole purpose is to have the covariate
  before it does.
- **No character at all, kind only**: Let the regression learn each kind
  independently — Rejected: a single-user corpus will hold too few events per
  kind to fit them independently, and a brand-new kind would start from nothing.
- **METs value per kind**: Use published metabolic equivalents — Rejected as
  false precision: a MET figure implies a calibrated energy expenditure this
  application never measures, and it would be trusted as measured.

### Consequences

**Positive:**

- Entry stays two taps; nothing is asked that the kind does not already answer.
- Sparse kinds pool sensibly for fitting.
- No fabricated numeric precision enters the data.

**Negative:**

- A hard day and an easy day of the same kind are indistinguishable unless
  duration differs, so within-kind variance is unmodelled and will show up as
  residual noise.
- The three-way character is a coarse instrument; `mixed` in particular will
  absorb activities that behave quite differently.

---

## Decision 3: Default the activity lookback to 36 hours

**Date**: 2026-08-14
**Status**: accepted

### Context

The developer states the effect of activity has "a long tail effect on morning
doses as well" — an evening session changes not only that evening's basal but the
next morning's. A dosing model therefore cannot treat activity as a same-session
flag; it needs a window.

Published insulin-sensitivity effects after exercise are commonly described as
persisting somewhere between several hours and two days, which is too wide a
range to pick a number from directly.

### Decision

Requirement 5.1's lookback is configurable, defaulting to **36 hours**.

### Rationale

36 hours is chosen structurally rather than clinically: it is the shortest window
that always spans an evening activity through to the following morning's dose,
which is precisely the relationship the developer described. A 24-hour window
would clip that pairing whenever the morning dose falls more than 24 hours after
the activity started, which is the common case for an evening session followed by
a 07:30 dose.

It is configurable because it is a guess, and because once the ledger holds real
pairs the decay can be measured and the window set from data rather than from
this reasoning.

### Alternatives Considered

- **24 hours**: The obvious round number — Rejected: it clips exactly the
  evening-to-next-morning pairing that motivated the requirement.
- **48 hours**: The upper end of the published range — Rejected: it drags in the
  previous evening's activity as well, so a model fitting on it cannot separate
  two sessions without extra machinery, and the developer's stated effect is
  about one night's tail.
- **An exponential decay weight with no cutoff**: Weight every past activity —
  Rejected as premature: the decay shape is unmeasured, so choosing one now
  invents the very thing the ledger exists to discover. A window is the honest
  primitive until there is data.

### Consequences

**Positive:**

- The window matches the stated relationship rather than a round number.
- Configurable, so the measured decay can replace the guess without a schema or
  interface change.

**Negative:**

- 36 hours will sometimes capture two sessions, and this spec offers no way to
  attribute an effect between them.
- The number is reasoned, not measured, and will read as authoritative to anyone
  who does not open this entry.

---

## Decision 4: Stamp provenance on every activity event from the start

**Date**: 2026-08-14
**Status**: accepted

### Context

HealthKit workout ingestion is anticipated and deferred (Req 6.2). When it
arrives, every activity row written before it will be manual, and every row after
may be either. A model fitting on mixed-provenance data needs to tell them
apart: a manual entry carries a remembered timestamp and a guessed duration, a
HealthKit workout carries measured ones.

### Decision

Every activity event carries a provenance field, seeded `manual` for every event
this spec creates.

### Rationale

Adding the column now costs one field and makes the later HealthKit source a
pure addition. Adding it later means either a migration or a cohort of rows whose
provenance has to be inferred from their creation date — which is exactly the
kind of reconstruct-it-afterwards problem the dosing spec's ledger design
already avoids by recording covariates at write time.

### Alternatives Considered

- **Add the field when HealthKit lands**: Defer it — Rejected: historical rows
  would then need a backfill or an inference rule, and the inference ("written
  before date X, therefore manual") breaks the moment the two sources overlap.
- **Infer provenance from whether duration is present**: Use a proxy — Rejected:
  manual entries may carry a duration and the proxy would be silently wrong, in a
  field whose only purpose is to be trusted.

### Consequences

**Positive:**

- The HealthKit source becomes an addition rather than a migration.
- Mixed-provenance fitting is possible from the first HealthKit row.

**Negative:**

- One field carrying a single constant value until HealthKit ships, which reads
  as dead weight to anyone who has not read Req 6.1.

---

## Decision 5: This spec records the covariate and applies nothing

**Date**: 2026-08-14
**Status**: accepted

### Context

The motivation for activity events is entirely about insulin dosing. It is
tempting to close the loop here — record the activity and adjust the basal
suggestion in one spec.

The magnitude of the adjustment is unknown. The developer describes it as
"infinitely fine tunable" and immediately warns against overcomplicating, with
the key being simplicity to get good quality data. That is a direct instruction
to build the measurement before the model.

### Decision

This spec adds the event type, its entry surface, its display, and a lookback
query (Req 5.1). It computes no adjustment and suggests no dose (Req 5.3). The
adjustment belongs to `specs/data/insulin-dosing`, gated behind the same
measure-first discipline that spec already applies to carbohydrate ratios.

### Rationale

An adjustment shipped now would have an invented coefficient, and an invented
coefficient in a dosing path is indistinguishable from a fitted one to every
later reader. Recording the covariate first means the coefficient can be fitted
against real paired data — which is the only route to a number anyone should act
on.

It also keeps the two specs' scopes clean: this one owns a data type, that one
owns a suggestion.

### Alternatives Considered

- **Ship a seed adjustment now**: A fixed reduction per active day — Rejected: no
  measured magnitude exists, and a seeded number in an insulin path gets trusted
  regardless of how it is labelled.
- **Fold activity into the insulin-dosing spec entirely**: One spec, no new
  folder — Rejected: activity is a general covariate whose later sources
  (HealthKit, heart rate) have nothing to do with dosing, and burying a new event
  type inside a dosing spec hides it from anything else that wants it.

### Consequences

**Positive:**

- Data collection starts immediately, which is the long-pole item — a coefficient
  cannot be fitted until pairs exist.
- No invented dosing number ships.
- Each spec owns one thing.

**Negative:**

- The developer logs activity for some period with no visible benefit, which is
  exactly the condition under which logging discipline lapses — and lapsed
  logging produces the biased corpus this spec exists to avoid.
- The payoff depends on a second spec being carried through.

---

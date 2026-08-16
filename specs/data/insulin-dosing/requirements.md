# Requirements: Insulin Dosing

## Introduction

This feature gives the app a **guess at a bolus dose** for a meal it has just estimated, computed on-device from a time-banded carbohydrate ratio the developer configures, and records that guess — with the inputs that produced it — so later ratios and later fat rules can be judged against evidence rather than assertion.

Two things motivate it, and only the first is solved here.

**The carbohydrate half is arithmetic.** The developer's own working rule is that insulin is least effective in the morning: roughly *2 units per 10 g of carbohydrate at breakfast, falling to 1 unit per 10 g later in the day*. That is a ratio and a clock, and the app already holds both halves of the input — an estimated carbohydrate total and the time the meal was recorded. Iteration 1 delivers exactly that: a number, shown before the dose is logged, seeded into the existing dose sheet.

**The fat half is not arithmetic, and nobody has the rule yet.** A fatty pizza produces a *double spike*: the carbohydrate rises first, then hours later the fat and protein drive a second, slower rise as they are converted and as free fatty acids blunt insulin sensitivity. Rapid-acting insulin peaks around 60–90 minutes and is largely gone by 4–5 hours; the second rise runs 3–8 hours. A single bolus sized for the carbohydrate is therefore right at hour one and wrong at hour four. Several published strategies exist for this and they disagree with each other. This spec does **not** pick one. It requires that every fat-relevant covariate be **recorded from the first release**, that candidate strategies be **enumerated and identified** so a later release can try them one at a time and attribute the outcome, and that fat change **no number** until its prerequisites are met. Covariates not captured at suggestion time cannot be reconstructed afterwards; that is the whole reason recording comes first.

**This reverses a recorded non-goal.** `specs/regression-suggestion-integration/prd.md` states: *"No dose suggestion, insulin-on-board, or regression maths in the app — medreg owns all modelling, off-device, against exported data."* The reversal here is deliberately narrow — suggestion arithmetic and insulin-on-board move on-device; **fitting does not**. `~/repos/medreg` remains the only place parameters are estimated from history. The reversal, its exact scope, and everything that survives it are recorded in `decision_log.md`.

Estimation stays untouched: this feature consumes a meal's already-computed macros and the existing event log. It adds no capture work, no model, and no network call.

## Non-Goals

Out of scope for **iteration 1**, each named so the omission reads as a decision rather than an oversight:

- **No fat term in the suggested dose.** Fat and protein are recorded on every suggestion; they change nothing. A variable fat uplift folded into the carb term would make every recorded dose `carbs / ratio + unknown`, and neither the ratio nor the fat rule could be attributed afterwards.
- **No correction term.** The suggestion does not adjust for the current glucose reading, and there is no insulin-sensitivity factor. The starting glucose is recorded so a correction term can be evaluated later.
- **No parameter fitting on-device.** No least-squares, no covariance, no Monte Carlo. medreg keeps every fitted quantity.
- **No parameter import surface.** Ratios are typed into Settings by a human. There is no file import, no profile format, and no staleness policy in iteration 1.
- **No outcome scoring, no verdicts, no ledger screen, no automatic ratio proposals.** These are gated on a measured result (Requirement 11).
- **No scheduled follow-up doses or extended/square-wave boluses.** Both remain out of scope here and in [`specs/data/dose-schedule`](../dose-schedule/requirements.md).
  - **Amended by [`specs/data/dose-schedule`](../dose-schedule/decision_log.md) Decision 1.** This non-goal originally read "No notifications, timers, scheduled follow-up doses, or extended/square-wave boluses. There is no scheduling surface in the app today and none is added here." Notifications and timers FOR THE PURPOSE OF CAPTURING A SCHEDULED DOSE are now in scope, and `specs/data/dose-schedule` builds them. The factual premise was also stale when written: `App/GlucoseConnectionsModel.swift` already registers a `BGAppRefreshTask` for the CGM poll. What genuinely did not exist was `UNUserNotificationCenter`, which `specs/data/dose-schedule` introduces as a general local-reminder capability — the machinery [task 22](tasks.md) records the delayed fat follow-up as blocked on.
- **No automatic dose delivery or automatic dose recording.** The suggestion seeds a control; a human always taps Save.
- **No confidence score, predictive interval, or uncertainty display in the UI.** The uncertainty inputs are recorded, not rendered.
- **No change to the insulin event's metadata contract**, which medreg owns and parses.
- **No change to the estimation pipeline, the food databases, or capture.**
- **Not a medical device, not prescriptive, not shared.** The output is one developer's guess at his own dose, recorded so it can be checked.

## Requirements

### 1. Carbohydrate Ratio: Convention, Storage, and Configuration

**User Story:** As the developer-user, I want the ratio stored in one unambiguous direction and editable, so that it can never be silently inverted against medreg and is never a hard-coded constant.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL express every carbohydrate ratio in exactly one canonical direction — **grams of carbohydrate covered by one unit of insulin, `g/U`** — and SHALL use that direction in storage, in computation, in every recorded row, and in every label the user sees. The reciprocal direction (units per gram) SHALL NOT be stored anywhere.
2. <a name="1.2"></a>Wherever a ratio is presented to the user, the system SHALL state its unit as `g/U` and SHALL render the reciprocal alongside it as a derived, read-only value (for example, `5.0 g/U` shown with `= 2.0 U per 10 g`), so that the developer's own phrasing and the canonical direction are visible together and cannot be confused.
3. <a name="1.3"></a>The system SHALL hold one ratio per time band (Requirement 2), each independently editable in Settings, and SHALL treat the shipped values as **defaults, not constants**.
4. <a name="1.4"></a>The system SHALL ship the following seed defaults, which reproduce the developer's stated rule of 2 U per 10 g in the morning and 1 U per 10 g later: overnight `10.0 g/U`, breakfast `5.0 g/U`, lunch `10.0 g/U`, dinner `10.0 g/U`.
5. <a name="1.5"></a>The system SHALL accept a configured ratio only in the closed interval `1.0` to `60.0 g/U` inclusive, and SHALL reject a value outside that interval or a non-numeric entry by leaving the previously stored value in force.
6. <a name="1.6"></a>WHERE a band has no stored ratio (first launch, or a value cleared), the system SHALL use that band's seed default (Req 1.4) and SHALL record on any suggestion it produces that the default rather than a configured value was in force.
7. <a name="1.7"></a>The system SHALL record the ratio actually used, in `g/U`, on every suggestion it produces (Requirement 7), so that a suggestion remains interpretable after the setting is changed.

### 2. Time Bands and Local-Time Determination

**User Story:** As the developer-user, I want the ratio chosen by the time of day the meal was eaten in my own local clock, so that "morning" means my morning.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL classify a meal into exactly one of four bands by the **local wall-clock hour** of the meal's own timestamp: `overnight` 00:00–05:59, `breakfast` 06:00–10:59, `lunch` 11:00–15:59, `dinner` 16:00–23:59. The bands SHALL be contiguous, non-overlapping, and cover all 24 hours.
2. <a name="2.2"></a>The system SHALL determine local time from the device's current calendar and time zone at the moment the suggestion is computed, and SHALL NOT use UTC hours for band selection.
3. <a name="2.3"></a>WHEN a meal's local timestamp falls exactly on a band boundary hour, the system SHALL assign it to the band the boundary opens (06:00 is `breakfast`, 11:00 is `lunch`, 16:00 is `dinner`, 00:00 is `overnight`).
4. <a name="2.4"></a>The system SHALL select the band from the timestamp of the meal or intake the suggestion is for, not from the moment the dose sheet is opened.
5. <a name="2.5"></a>The system SHALL record on every suggestion the band identifier, the local hour, the UTC hour, and the local UTC offset in seconds, so that a band assignment can be re-derived off-device and any disagreement between local-clock and UTC-clock banding is a measurable quantity rather than a silent discrepancy.
6. <a name="2.6"></a>The band boundaries SHALL be fixed in iteration 1 and SHALL NOT be user-configurable; they SHALL match the four segment boundaries medreg fits against, differing from it only in being evaluated in local rather than UTC time.

### 3. Suggested Dose Computation

**User Story:** As the developer-user, I want one number suggested for the meal in front of me, computed the same way every time, so that I can see what my own rule implies before I dose.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN a meal estimate completes, THE SYSTEM SHALL compute a suggested bolus in units as the meal's total carbohydrate in grams divided by the band's ratio in `g/U`, less the insulin-on-board at that instant (Requirement 4), floored at zero.
2. <a name="3.2"></a>The system SHALL compute the suggestion from the carbohydrate total the user would see and record for that meal — that is, from the corrected total WHERE a user correction is in force, and from the pipeline total otherwise.
3. <a name="3.3"></a>The system SHALL produce a suggestion for a manually entered carbohydrate amount (typed entry or quick-add preset) on the same terms as a captured meal, so that the suggestion is not silently absent for carbohydrates that did not arrive through the camera.
4. <a name="3.4"></a>IF the computed dose is below `0.5 U`, THEN the system SHALL present no suggestion and SHALL NOT seed any control, rather than raising the value to the smallest dosable increment.
5. <a name="3.5"></a>IF no carbohydrate total is available for the meal, THEN the system SHALL present no suggestion and SHALL NOT substitute a default.
6. <a name="3.6"></a>The system SHALL compute the suggestion deterministically: the same carbohydrate total, band, ratio, and insulin-on-board SHALL always yield the same number.
7. <a name="3.7"></a>The system SHALL NOT write an insulin event as a consequence of producing a suggestion; recording a dose SHALL remain an explicit user action.
8. <a name="3.8"></a>The system SHALL NOT apply any fat, protein, glucose-correction, or activity term to the suggested number in iteration 1 (see Requirement 8 and Non-Goals).

### 4. Insulin-on-Board Subtraction

**User Story:** As the developer-user, I want insulin I have already taken subtracted from the guess, so that a dose given an hour ago is not silently given twice — and so that a later outcome can be attributed to one dose rather than to an unknown overlap.

**Acceptance Criteria:**

1. <a name="4.1"></a>The system SHALL compute insulin-on-board at a given instant as the sum, over prior bolus doses, of each dose's units multiplied by the fraction of that dose remaining after the elapsed time, using the same insulin activity model and the same rapid-acting constants medreg uses (peak 75 minutes, duration of action 360 minutes).
2. <a name="4.2"></a>The system SHALL exclude basal doses from insulin-on-board entirely.
3. <a name="4.3"></a>The system SHALL treat a dose older than the duration of action as contributing zero.
4. <a name="4.4"></a>WHERE no prior bolus falls inside the duration of action, the system SHALL use an insulin-on-board of zero and SHALL proceed normally.
5. <a name="4.5"></a>The system SHALL record the insulin-on-board value used on every suggestion (Requirement 7).
6. <a name="4.6"></a>The insulin-on-board result SHALL agree with medreg's implementation to within `0.01 U` on a shared fixture set covering at least the elapsed times 0, 30, 75, 180, and 360 minutes; a disagreement beyond that tolerance SHALL be treated as a defect in one of the two implementations.
7. <a name="4.7"></a>Insulin-on-board SHALL be used only as an input to the suggested number and as a recorded covariate; it SHALL NOT drive any alert, gate, or refusal presented to the user.

### 5. Dosable Increment, Rounding, and Boundaries

**User Story:** As the developer-user, I want the suggestion expressed in an amount my pen can actually deliver, without the rounding quietly inventing insulin.

**Acceptance Criteria:**

1. <a name="5.1"></a>The system SHALL hold a configurable **dosable increment** in units, defaulting to `1.0 U`, and SHALL round every presented or seeded suggestion to a whole multiple of it.
2. <a name="5.2"></a>The system SHALL round half away from zero: a value exactly midway between two increments SHALL round to the larger. Rounding SHALL be applied once, to the final computed value, never to intermediate terms.
3. <a name="5.3"></a>The system SHALL retain the exact unrounded value, to at least two decimal places, on the recorded suggestion (Requirement 7), so that the rounding error remains visible for later measurement.
4. <a name="5.4"></a>IF the rounded value is below the smallest amount the dose control can represent, THEN the system SHALL present no suggestion (per Req 3.4) rather than clamping upward.
5. <a name="5.5"></a>IF the rounded value exceeds the largest amount the dose control can represent, THEN the system SHALL seed that control with its maximum, SHALL record the exact unrounded value unchanged, and SHALL record that the seed was clamped.
6. <a name="5.6"></a>The system SHALL accept a configured dosable increment only from a fixed set of pen increments — `0.5 U` and `1.0 U` — and SHALL leave the previously stored value in force for any other entry.
7. <a name="5.7"></a>WHERE the configured dosable increment is finer than the dose control can represent, the system SHALL round the seeded value to what the control can represent and SHALL still record the exact unrounded value per Req 5.3.

### 6. Presentation and Interaction

**User Story:** As the developer-user, I want the guess in front of me at the moment I would act on it, without it costing me a tap or pushing anything else off the screen.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN a suggestion exists for a meal awaiting recording, the system SHALL display it on the meal review surface as a zero-tap read-only value, alongside the carbohydrate total, stated in units.
2. <a name="6.2"></a>The suggestion display SHALL NOT increase the height of the content above the review screen's scroll boundary, so that the existing guarantee that the amount control stays visible without scrolling is preserved.
3. <a name="6.3"></a>The system SHALL preserve the existing two-tap paths unchanged: capturing and recording a meal SHALL still take two taps, and logging a dose from the home control or the dose deep link SHALL still take two taps.
4. <a name="6.4"></a>WHERE a suggestion is in force for a just-recorded meal, the system SHALL seed the dose sheet's amount with the rounded suggestion instead of the standing default; WHERE no suggestion is in force, the sheet SHALL open at the standing default exactly as it does today.
5. <a name="6.5"></a>The seeded amount SHALL be freely adjustable by the user before saving, and the system SHALL record the amount actually saved as the dose, unmodified.
6. <a name="6.6"></a>WHERE no suggestion is available, the system SHALL show nothing in its place, or a bare em dash where the layout requires a value, and SHALL NOT show explanatory text.
7. <a name="6.7"></a>The suggestion SHALL be presented as a plain number in the screen's existing secondary type treatment; it SHALL NOT use the accuracy-flag banner treatment reserved for estimate-quality signals, and it SHALL NOT introduce a second accent-coloured control on a screen that already has one.
8. <a name="6.8"></a>The system SHALL NOT present any disclaimer, warning, reassurance, medical-safety, consent, or confidence copy alongside the suggestion, on any screen (project developer-phase rule). No uncertainty range, refusal reason, or advisory sentence SHALL be rendered.
9. <a name="6.9"></a>The ratio and dosable-increment controls SHALL live in the existing Settings insulin section; no new screen SHALL be added in iteration 1.

### 7. Suggestion Ledger

**User Story:** As the developer-user, I want every suggestion recorded with the inputs that produced it, so that a future ratio or fat rule can be judged against what actually happened instead of against an argument.

**Acceptance Criteria:**

1. <a name="7.1"></a>WHEN the system produces a suggestion, it SHALL persist one row describing it, including WHEN the suggestion was suppressed under Req 3.4, so that suppressions are as visible as suggestions.
2. <a name="7.2"></a>Each recorded suggestion SHALL carry, at minimum: the carbohydrate total used and whether it came from a captured meal, a corrected meal, or a manual entry; the meal or intake it refers to; the exact unrounded suggested units and the rounded value; the ratio in `g/U`; whether that ratio was a configured value or a seed default; the band, local hour, UTC hour, and local UTC offset (Req 2.5); the insulin-on-board used; the meal's carbohydrate confidence figure; the most recent glucose reading before the meal and its age, WHERE one exists; the estimated fat grams, protein grams, and fat-protein units (Requirement 8); the dosable increment in force; and the app build identifier.
3. <a name="7.3"></a>The system SHALL record these rows in a **derived side store, separate from the event log**, and SHALL NOT add, alter, or extend any key of the insulin event's metadata contract, which medreg owns and parses.
4. <a name="7.4"></a>Writing a suggestion row SHALL NOT modify, reorder, or delete any event of any type, and SHALL NOT trigger the event-log change notification that refreshes user-facing history.
5. <a name="7.5"></a>WHERE a dose is subsequently recorded that the suggestion plausibly refers to, the system SHALL associate the two, so that suggested and given amounts can be compared later.
6. <a name="7.6"></a>The recorded rows SHALL be carried verbatim in the existing data export, so that medreg can read them without an adapter.
7. <a name="7.7"></a>IF persisting a suggestion row fails, THEN the system SHALL still present the suggestion and SHALL NOT block, delay, or alter meal recording or dose recording.
8. <a name="7.8"></a>The system SHALL version the recorded row's shape, so that a row written by an earlier release remains identifiable after the shape changes.
9. <a name="7.9"></a>The system SHALL record the dose rule that produced the number by identifier and version, so that suggestions produced by different rules are never pooled by accident.

### 8. Fat and the Delayed Second Spike — Record and Iterate

**User Story:** As the developer-user, I want the fat problem set up so it can be solved later with evidence, because nobody — in this repo, in medreg, or in the literature — currently agrees on the rule.

**Context.** A high-fat, high-protein meal (the motivating case is a fatty pizza) produces two glucose rises: the carbohydrate rise within the first hour or two, and a second, delayed, prolonged rise from roughly 3 to 8 hours as fat slows gastric emptying, free fatty acids reduce insulin sensitivity, and protein contributes through gluconeogenesis. Rapid-acting insulin cannot cover both with one dose at one time. At least four published strategies address this and they differ in size, timing, and trigger. Fat can also *lower* glucose in the first 2–3 hours, so front-loading the extra insulin risks an early low followed by a late high — which is why no rule is adopted here on the strength of a citation alone.

**Acceptance Criteria:**

1. <a name="8.1"></a>The system SHALL record, on every suggestion, the meal's estimated fat grams, estimated protein grams, and the derived fat-protein units computed as `(fat_g × 9 + protein_g × 4) / 100`, from the macros the estimation pipeline already produces, **where the pipeline produced them**. A quick-add preset or a typed carbohydrate entry has no pipeline behind it and no macros to record; those subjects SHALL record the fat, protein and fat-protein-unit columns as absent rather than as zero, so a missing macro is never read as a fat-free meal.
2. <a name="8.2"></a>The system SHALL NOT let fat, protein, or fat-protein units alter the suggested number in iteration 1 (restating Req 3.8 as the fat programme's baseline: the carbohydrate term is the experimental control).
3. <a name="8.3"></a>The system SHALL flag a recorded suggestion WHERE its fat and protein figures are known to be stale — specifically WHERE the meal carries a user correction, because a correction adjusts carbohydrate only and leaves the original pipeline fat and protein in place.
4. <a name="8.4"></a>The design SHALL enumerate the candidate fat strategies as distinct, identified iterations — at minimum: a proportional uplift on the carbohydrate dose; a split of the total between an immediate and a delayed portion; a protein-only delayed contribution; and a fat-protein-unit dose extended over a duration — each with its trigger condition, size, timing, and its source, so that a later release can implement exactly one at a time and attribute its outcome.
5. <a name="8.5"></a>Any fat strategy adopted later SHALL be identified and versioned on every suggestion it produces (Req 7.9), SHALL ship disabled by default, and SHALL refuse to run on suggestions flagged stale under Req 8.3.
6. <a name="8.6"></a>Any materiality threshold that gates a fat strategy SHALL be **disjunctive** — a meal SHALL qualify on high fat-protein units *or* on high protein alone — and SHALL NOT require both a fat and a protein threshold to be exceeded together, because a high-fat, moderate-protein meal (the motivating pizza) is exactly the case a conjunctive gate misses.
7. <a name="8.7"></a>Any materiality threshold SHALL be set from the distribution observed in this user's own recorded meals rather than adopted from a published constant.
8. <a name="8.8"></a>No fat strategy SHALL change a suggested number until all of the following hold, each verifiable: user corrections carry corrected fat and protein so Req 8.3 no longer flags most corrected meals; the recorded data show a delayed glucose rise associated with high fat-protein units for this user; and the pipeline's fat estimate has been compared against at least one weighed reference meal, the repository holding ground truth for carbohydrate only.
9. <a name="8.9"></a>WHERE a delayed follow-up dose is ever suggested, the system SHALL record the actual elapsed time at which the follow-up dose was given, not merely that one was given.

### 9. The medreg Boundary

**User Story:** As the system owner, I want exactly one place where parameters are estimated from history, so that the two repositories cannot drift into two competing models of the same person.

**Acceptance Criteria:**

1. <a name="9.1"></a>The system SHALL NOT fit, estimate, or infer any parameter from historical data on-device. Ratios are configured values; they are never learned by the app in iteration 1.
2. <a name="9.2"></a>The system SHALL treat medreg as the sole owner of parameter fitting, sensitivity estimation, and any regression over the event log.
3. <a name="9.3"></a>The system SHALL obtain configured ratios only through Settings entry by a human; there SHALL be no import surface, profile file format, or automated parameter transfer in iteration 1.
4. <a name="9.4"></a>The system SHALL record, on every suggestion, the **provenance of the ratio used** — at minimum whether it was a shipped seed default, a hand-chosen value, or a value transcribed from a medreg fit, together with a free-text reference identifying that fit WHERE one was given.
5. <a name="9.5"></a>The system SHALL express its ratios in the same unit and direction medreg fits in (`g/U`, Req 1.1), and its band boundaries at the same hours medreg segments at (Req 2.1), so that a value can be transcribed between the two without conversion.
6. <a name="9.6"></a>The system SHALL NOT modify medreg, and SHALL NOT depend on medreg being present, installed, or run; the app SHALL behave identically whether or not medreg has ever been used.
7. <a name="9.7"></a>The system SHALL leave the insulin event's metadata contract exactly as medreg documents and parses it (Req 7.3), so that the one-way export path continues to work with no adapter and no negotiation.
8. <a name="9.8"></a>Where this feature computes a quantity medreg also computes — insulin-on-board today — the two SHALL be verifiable against each other on a shared fixture set (Req 4.6) rather than left to diverge.

### 10. Determinism, Offline Operation, and Data Safety

**User Story:** As the system owner, I want dose suggestion held to the same hard invariants as estimation, so that adding it cannot compromise what already works.

**Acceptance Criteria:**

1. <a name="10.1"></a>The suggestion SHALL be computed with no network call and no language model, on-device, in every code path.
2. <a name="10.2"></a>The dose computation SHALL be a pure function of its stated inputs — carbohydrate grams, ratio, band, insulin-on-board, and dosable increment — with no dependence on ambient state beyond the current date and time zone, which are supplied to it explicitly.
3. <a name="10.3"></a>The dose computation SHALL NOT be reachable from, and SHALL NOT be depended on by, the carbohydrate-estimation modules; a failure or absence of dose suggestion SHALL leave capture, estimation, and meal recording unaffected.
4. <a name="10.4"></a>The system SHALL express and store every insulin quantity in units (U) and every carbohydrate quantity in grams (g), and SHALL express glucose in mmol/L only, consistent with the rest of the app.
5. <a name="10.5"></a>Introducing this feature SHALL NOT alter the meaning, shape, or contents of any existing stored event, and an install upgraded from a release without this feature SHALL retain all existing data.

### 11. Evidence Gate Before Outcome Scoring

**User Story:** As the developer-user, I want to know whether measuring a dose's outcome is even possible on my data before any code is written to do it, so that I do not ship a feature that renders empty.

**Acceptance Criteria:**

1. <a name="11.1"></a>The system SHALL NOT score, grade, or assign a verdict to any recorded suggestion in iteration 1.
2. <a name="11.2"></a>Before any outcome scoring is specified or built, a retrospective measurement SHALL be run over the existing recorded history, off-device, reporting at minimum: the distribution of the meal carbohydrate confidence figure; the distribution of fat-protein units across recorded meals; the fraction of meals and manual intakes pairable with a bolus inside 45 minutes; glucose coverage across the 6 hours following each such dose; the rate at which a further bolus falls inside that window; and, combining these, the fraction of past windows that would survive the confounding filters.
3. <a name="11.3"></a>IF that measurement shows too few unconfounded windows to distinguish one ratio from another, THEN outcome scoring SHALL NOT be built, and the ratios SHALL remain configured values for longer; this is an acceptable result, not a failure.
4. <a name="11.4"></a>The confounding filters SHALL NOT be loosened in order to raise the surviving fraction.
5. <a name="11.5"></a>Any ratio adjustment ever proposed from recorded outcomes SHALL be applied only by an explicit user action, never automatically, and the recorded suggestions either side of such a change SHALL be distinguishable so that no comparison pools rows from before and after it.

### 12. Basal Dosing and the Activity Covariate

**User Story:** As the developer-user, I want my standing basal schedule recorded and my activity carried alongside it, so that the relationship I already manage by feel becomes measurable rather than remaining in my head.

**Context:** The developer's standing schedule is a nominal 15 U at 07:30 and a nominal 15 U at 19:30. Activity moves the evening dose **down**, more cardiovascular work moves it further down, and the effect carries a tail that reaches the following morning's dose. The direction of that relationship is recorded once, in [`specs/data/activity-events`](../activity-events/decision_log.md) Decision 1, and is not restated as a formula anywhere here.

**Acceptance Criteria:**

1. <a name="12.1"></a>The system SHALL allow the standing basal schedule to be configured as a set of nominal doses each carrying a time of day, seeded with 15 U at 07:30 and 15 U at 19:30.
2. <a name="12.2"></a>The seeded schedule SHALL be user-configurable in the same way the carbohydrate ratios are; the seeded values are a starting point, not a constant.
3. <a name="12.3"></a>The system SHALL NOT compute, apply, or suggest any adjustment to a basal dose from recorded activity in iteration 1.
   - Rationale: no measured magnitude exists. The developer describes the relationship as "infinitely fine tunable" while warning against overcomplicating it, so the measurement precedes the model exactly as it does for the carbohydrate ratios ([Req 11](#11.1), and [`specs/data/activity-events`](../activity-events/decision_log.md) Decision 5).
4. <a name="12.4"></a>WHERE a basal dose is recorded, the system SHALL record alongside it the activity events falling within the configured lookback preceding that dose, using the query [`specs/data/activity-events`](../activity-events/requirements.md#5.1) provides, so the pairing needed to fit the relationship exists from the first dose onward.
5. <a name="12.5"></a>The recorded covariate SHALL carry each activity's kind, its cardiovascular character, and its duration where given, so a later fit can separate an aerobic session from an anaerobic one rather than pooling them as "exercised".
6. <a name="12.6"></a>The activity lookback applied to a basal dose SHALL span at least from the preceding evening through to the following morning's dose, so an evening session is paired with both the dose that follows it and the morning dose that follows that.
7. <a name="12.7"></a>The system SHALL NOT display an adherence figure, streak, or missed-dose indicator.
   - **Amended by [`specs/data/dose-schedule`](../dose-schedule/decision_log.md) Decision 1 (2026-08-14).** This requirement originally also read "SHALL NOT prompt, remind, nudge, or notify the developer to take a basal dose". That clause is REVERSED: a recurring dose may be scheduled, a repeating local reminder may be delivered while it is outstanding, and the dose may be recorded from the notification in one tap. The reasoning that produced the original clause conflated a prompt intended to change what the developer does with a prompt that exists because it is the cheapest available place to RECORD an event; the second is a capture surface, not behaviour change.
   - The clause above **survives untouched**, and that is the point of the amendment being partial. Outstanding state is tracked because the reminder cannot function without it; the developer is never scored on it ([`specs/data/dose-schedule`](../dose-schedule/requirements.md#2.5) Req 2.5).
8. <a name="12.8"></a>Any future basal adjustment derived from activity SHALL cite [`specs/data/activity-events`](../activity-events/decision_log.md) Decision 1 for the direction of the relationship rather than restating it, and SHALL be gated behind the same evidence requirement that governs the carbohydrate ratios ([Req 11.3](#11.3)).

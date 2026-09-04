# Requirements: Activity Events

Manual activity logging as a first-class event type, so exercise becomes a
recorded covariate for insulin dosing long before HealthKit workout data or
heart-rate telemetry is wired up.

**Domain**: `data` · **Mode**: full (the data model is touched — [PROCESS.md §5](../../PROCESS.md#5-choosing-the-mode-full-spec-smolspec-or-iterative))

## Context

MeData records meals, glucose, insulin doses and manual intake in one SQLite
`events` table. It records nothing about physical activity. The developer's own
dosing rule depends on it: the nominal 19:30 basal of 15 U goes **down** on
active days, with more cardiovascular work meaning a larger reduction, and the
effect carries a tail that reaches the following morning's dose.

That relationship cannot be fitted, checked, or even described from the data the
app holds today. This spec adds the missing covariate.

The governing constraint is the same one
[`specs/regression-suggestion-integration/prd.md`](../../regression-suggestion-integration/prd.md)
recorded for dose entry: **if logging is not fast and easy the developer will not
do it, and the regression data is worthless.** Simplicity of capture outranks
richness of capture everywhere in this spec.

Heart rate, workout duration from a watch, and HealthKit `HKWorkout` ingestion
are all anticipated and all deferred. This spec's job is to make the manual
record land in a shape those sources can later fill in without a migration.

---

## 1. The activity event

1. <a name="1.1"></a>The system SHALL define `EventType.activity = "activity"`
   alongside the existing `meal`, `bsl`, `insulin` and `intake` constants, stored
   in the same `events` table with the same timestamp and metadata-JSON
   conventions.
2. <a name="1.2"></a>An activity event SHALL carry an identifier, a timestamp, an
   activity kind, and an optional duration in minutes.
3. <a name="1.3"></a>An activity event SHALL carry an optional free-text note,
   consistent with the existing insulin and intake events.
4. <a name="1.4"></a>The system SHALL record the activity kind as a stable
   machine key, never as the display label, so renaming a label in the UI never
   orphans historical rows.
5. <a name="1.5"></a>Where an activity event carries no duration, the system
   SHALL record the duration as absent rather than as zero, so an unrecorded
   duration is never read as an instantaneous activity.
6. <a name="1.6"></a>The system SHALL record the provenance of every activity
   event as one of `manual` or `healthkit`, seeded `manual` for every event this
   spec creates, so a later HealthKit source is distinguishable without a
   migration ([Decision 4](decision_log.md)).

## 2. Activity kinds

1. <a name="2.1"></a>The system SHALL ship a defined set of activity kinds
   covering at minimum: `swim`, `waterpolo`, `cycle`, `run`, `walk`, `gym`, and
   `other`.
2. <a name="2.2"></a>Each activity kind SHALL carry a recorded **cardiovascular
   character** of `aerobic`, `anaerobic`, or `mixed`.
   - Rationale: the developer's stated relationship is that *more
     cardiovascular* work means a larger reduction in insulin requirement. The
     character is what lets a regression pool sparse kinds without collapsing
     them, and it is what a later model uses to generalise to a kind it has not
     seen ([Decision 2](decision_log.md)).
3. <a name="2.3"></a>The activity kind set SHALL be extensible by adding a case
   without altering stored rows or requiring a schema migration.
4. <a name="2.4"></a>The system SHALL NOT require the developer to state an
   intensity, an effort rating, or a calorie figure. Intensity is carried by the
   kind and its character, and by duration where given.

## 3. Entry

1. <a name="3.1"></a>Logging an activity SHALL take no more taps than logging an
   insulin dose does today: open the sheet, pick the kind, save.
2. <a name="3.2"></a>The entry surface SHALL default its timestamp to now, and
   SHALL allow that timestamp to be moved, because activity is routinely logged
   after the fact.
3. <a name="3.3"></a>The entry surface SHALL preselect the most recently used
   activity kind, so a repeated activity is a two-tap save.
4. <a name="3.4"></a>Duration SHALL be optional and SHALL NOT block a save.
5. <a name="3.5"></a>The system SHALL provide a deep link that opens the activity
   entry surface directly, consistent with the existing `medata://insulin/add`
   and `medata://capture` links.
6. <a name="3.6"></a>Activity events SHALL be deletable by the same gesture that
   deletes insulin events today.

## 4. Display

1. <a name="4.1"></a>Recorded activity SHALL be visible on the Graph day view
   without obscuring the glucose trace, the carbohydrate bars, or the insulin
   band.
2. <a name="4.2"></a>An activity spanning a duration SHALL read as spanning that
   duration rather than as a point event.
3. <a name="4.3"></a>Activity SHALL appear in the Records list alongside the
   other event types.
4. <a name="4.4"></a>The display SHALL carry no reassurance, disclaimer, warning
   or coaching copy — the developer-phase copy rule
   ([CLAUDE.md](../../../CLAUDE.md)) applies unchanged.

## 5. The dosing covariate

This spec **records** the covariate. It does not adjust any dose — that belongs
to [`specs/data/insulin-dosing`](../insulin-dosing/requirements.md).

1. <a name="5.1"></a>The system SHALL expose a query returning the activity
   events within a stated interval preceding a given instant, so a dosing model
   can ask "what has this person done recently" without reimplementing the
   lookup.
2. <a name="5.2"></a>The lookback interval SHALL be configurable and SHALL
   default to **36 hours**, chosen to span the developer's stated overnight tail
   from an evening activity through to the following morning's dose
   ([Decision 3](decision_log.md)).
3. <a name="5.3"></a>The system SHALL NOT compute, apply, or suggest any insulin
   adjustment from activity within this spec. The direction of the relationship
   is recorded here as a stated fact for the dosing spec to consume, and is not
   implemented as a formula anywhere in this one.
4. <a name="5.4"></a>The recorded direction of the relationship SHALL be stated
   once, in [Decision 1](decision_log.md), in the form: **activity reduces
   insulin requirement; more cardiovascular work reduces it further; the effect
   decays over roughly a day.** Any later model that consumes activity SHALL
   cite that decision rather than restating the direction.

## 6. Later sources

1. <a name="6.1"></a>The stored shape SHALL accommodate a HealthKit `HKWorkout`
   without a schema migration: kind, start, duration and provenance map directly.
2. <a name="6.2"></a>The system SHALL NOT request HealthKit workout authorisation
   within this spec. HealthKit is already wired for glucose only
   (`HealthKitGlucoseSource`, [cgm-connect](../cgm-connect/requirements.md)) and
   widening that permission is its own decision.
3. <a name="6.3"></a>Where a later source supplies heart-rate or effort data, it
   SHALL extend the metadata JSON rather than replace the kind, so the kind stays
   the stable regression key across sources.
4. <a name="6.4"></a>Where both a manual and a HealthKit record describe the same
   activity, deduplication is **out of scope** for this spec and SHALL be decided
   when the HealthKit source is specified.

## 7. Out of scope

- Any insulin adjustment, suggestion or formula driven by activity (Req 5.3).
- HealthKit workout ingestion, heart rate, calorie estimates (Req 6.2).
- Deduplication between sources (Req 6.4).
- Retrospective backfill of activity the developer did before this ships.
- Any notion of a training plan, goal, streak, or coaching surface.

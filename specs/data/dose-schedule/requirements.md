# Requirements: Dose Schedule

A recurring-dose schedule with a reminder that persists until the dose is logged,
and a logging path short enough that recording a dose costs one tap.

**Domain**: `data` · **Mode**: full (touches the data model and adds a notification
surface — [PROCESS.md §5](../../PROCESS.md#5-choosing-the-mode-full-spec-smolspec-or-iterative))

## Context

The developer takes a standing basal dose twice a day — a nominal 15 U at 07:30 and
a nominal 15 U at 19:30. `specs/data/insulin-dosing`
[Requirement 12](../insulin-dosing/requirements.md#12.1) makes that schedule
configurable, but nothing prompts for it and nothing records whether it happened.

The governing problem is not motivation. It is **friction**. A dose logged through
the existing sheet costs: unlock, find the app, open the Graph, open the dose sheet,
set the units, pick bolus or basal, save. That is enough work that a twice-daily
record will not survive contact with real life, and an intermittent record is worse
than none — it biases every fit that consumes it toward the days the developer
happened to feel like logging.

The dose itself is a fixed, known quantity at a known time. Everything needed to
record it already exists before the developer touches the phone. The only thing the
system genuinely does not know is **whether it happened, and exactly when**. So the
input should ask for that and nothing else.

**This reverses a requirement in a sibling spec.** `specs/data/insulin-dosing`
Req 12.7 states: "The system SHALL NOT prompt, remind, nudge, or notify the developer
to take a basal dose, and SHALL NOT display an adherence figure, streak, or
missed-dose indicator." The reasoning was that prompting is behaviour change rather
than measurement. That reasoning does not survive the framing here: the reminder is
not there to make the developer adherent, it is the **capture surface** — the
cheapest available place to record an event that is otherwise lost. The reversal is
partial, and its exact scope is [Decision 1](decision_log.md).

## 1. The schedule

1. <a name="1.1"></a>The system SHALL allow one or more **scheduled doses** to be
   defined, each carrying a time of day, a nominal amount in units, an insulin kind
   (`bolus` or `basal`), and an enabled flag.
2. <a name="1.2"></a>The system SHALL seed two scheduled doses on first use, matching
   the developer's standing regime: 15 U basal at 07:30 and 15 U basal at 19:30.
3. <a name="1.3"></a>Every field of a scheduled dose SHALL be editable after
   creation, and a scheduled dose SHALL be deletable.
4. <a name="1.4"></a>A scheduled dose SHALL be disableable without being deleted, so
   a regime change can be reversed without re-entering it.
5. <a name="1.5"></a>Editing a scheduled dose SHALL NOT alter, retract, or
   retrospectively reinterpret any dose already recorded against it.
6. <a name="1.6"></a>The schedule SHALL be expressed in local wall-clock time and
   SHALL follow the device's time zone, so 07:30 remains 07:30 after travel or a
   daylight-saving transition.
7. <a name="1.7"></a>The system SHALL NOT require the developer to define a schedule.
   With no scheduled doses defined, the system behaves exactly as it does today.

## 2. Due and done

1. <a name="2.1"></a>A scheduled dose SHALL become **due** at its scheduled time on
   each day it is enabled.
2. <a name="2.2"></a>A due dose SHALL remain **outstanding** until it is either
   logged (Requirement 4) or explicitly skipped (Requirement 6).
3. <a name="2.3"></a>The system SHALL hold at most one outstanding occurrence per
   scheduled dose. WHEN a scheduled dose becomes due while its previous occurrence is
   still outstanding, the previous occurrence SHALL be closed as missed
   (Requirement 6) rather than accumulating.
4. <a name="2.4"></a>The outstanding state SHALL be visible inside the app without
   depending on a notification having been delivered or seen.
5. <a name="2.5"></a>The system SHALL NOT display an adherence percentage, a streak,
   a compliance score, or any comparison of the developer against a target. Tracking
   whether a dose is outstanding is required for the reminder to function; scoring
   the developer on it is not, and remains out of scope
   ([Decision 1](decision_log.md)).

## 3. The reminder

1. <a name="3.1"></a>WHEN a scheduled dose becomes due, the system SHALL deliver a
   local notification stating the kind and the nominal amount.
2. <a name="3.2"></a>The reminder SHALL repeat at a configurable interval while the
   dose remains outstanding, so a dismissed or missed notification does not end the
   prompt.
3. <a name="3.3"></a>The repeat SHALL stop when the dose is logged or skipped, and
   SHALL stop unconditionally after a configurable cutoff, so a forgotten dose does
   not prompt indefinitely.
4. <a name="3.4"></a>The reminder SHALL carry no reassurance, encouragement,
   warning, or coaching text. Its content is a kind, a quantity, and a time — the
   developer-phase copy rule ([CLAUDE.md](../../../CLAUDE.md)) applies unchanged and
   is not softened by the notification being outside the app.
5. <a name="3.5"></a>All notification scheduling SHALL be local to the device. No
   push service, no server, no network call.
6. <a name="3.6"></a>The system SHALL NOT use a notification interruption level that
   requires Apple entitlement review, and SHALL NOT present the reminder as a medical
   alert.

## 4. Logging in one tap

This is the requirement the spec exists for. Every other requirement serves it.

1. <a name="4.1"></a>The reminder SHALL carry an action that records the dose at its
   nominal amount **without opening the app**, so the common case costs one tap from
   the lock screen.
2. <a name="4.2"></a>A dose recorded that way SHALL be written as an ordinary
   `insulin` event, byte-identical in shape to one entered through the existing dose
   sheet, so medreg's convention
   (`~/repos/medreg/docs/insulin-event-convention.md`) is unaffected and no consumer
   learns a new row type.
3. <a name="4.3"></a>The recorded timestamp SHALL be **the moment the dose was
   logged**, not the scheduled time, because when a dose was actually taken is the
   quantity every downstream fit needs and the two routinely differ.
4. <a name="4.4"></a>The system SHALL additionally record, on the event, the
   scheduled dose it discharges and the scheduled time it was due, so lateness is
   recoverable without inferring it.
5. <a name="4.5"></a>WHERE the developer took the dose without the reminder, the
   system SHALL offer the same one-tap discharge from inside the app.
6. <a name="4.6"></a>Logging SHALL be idempotent per occurrence: acting twice on the
   same reminder SHALL record one dose, not two.

## 5. Adjusting the amount

The nominal amount is right most days and wrong on active ones —
`specs/data/activity-events` [Decision 1](../activity-events/decision_log.md) records
that activity reduces insulin requirement. A schedule that can only log the nominal
figure would quietly record a fiction on exactly the days that carry the most signal.

1. <a name="5.1"></a>The reminder SHALL offer a second action that opens the existing
   dose sheet **pre-seeded** with the nominal amount and kind, so a changed dose is
   an adjustment rather than a fresh entry.
2. <a name="5.2"></a>The system SHALL record whether the logged amount was the
   nominal one or an adjusted one, so a fit can tell a default-accepted dose from a
   deliberately chosen one.
3. <a name="5.3"></a>The system SHALL NOT suggest, compute, or pre-adjust the amount
   from recorded activity. Requirement 12.3 of
   [`specs/data/insulin-dosing`](../insulin-dosing/requirements.md#12.3) holds: the
   magnitude of the activity relationship is unmeasured, and this spec does not
   invent one.

## 6. Missed and skipped

1. <a name="6.1"></a>The developer SHALL be able to mark an outstanding dose as
   **skipped**, ending its reminder without recording an insulin event.
2. <a name="6.2"></a>An occurrence closed as missed (Req 2.3) or skipped SHALL be
   recorded as such, because a dose not taken is data and inferring it later from an
   absent event is not equivalent — an absent event is indistinguishable from an
   unlogged one.
3. <a name="6.3"></a>A missed or skipped occurrence SHALL NOT write an `insulin`
   event of any amount, including zero.
4. <a name="6.4"></a>The system SHALL NOT ask the developer why a dose was skipped.

## 7. Permission and degradation

1. <a name="7.1"></a>The system SHALL request notification authorisation only when
   the developer first enables a scheduled dose, never at launch.
2. <a name="7.2"></a>WHERE notification authorisation is refused or later revoked,
   the schedule SHALL continue to function as an in-app outstanding-dose surface
   (Req 2.4) with one-tap discharge (Req 4.5), and the system SHALL NOT re-prompt for
   authorisation or degrade any other feature.
3. <a name="7.3"></a>The system SHALL NOT depend on the app being running,
   foregrounded, or recently opened for a reminder to fire.

## 8. What this unblocks

1. <a name="8.1"></a>The notification surface introduced here SHALL be built as a
   general local-reminder capability rather than a basal-specific one, because
   [`specs/data/insulin-dosing`](../insulin-dosing/tasks.md) task 22 records the
   delayed fat follow-up as "blocked on machinery that does not exist: the app has no
   notification, timer or scheduling surface at all today". This spec removes that
   blocker; it does not implement the follow-up.

## 9. Out of scope

- Any dose amount computed, suggested, or adjusted by the system (Req 5.3).
- The delayed fat follow-up suggestion itself — this spec supplies its machinery
  only (Req 8.1).
- Adherence scoring, streaks, or compliance display (Req 2.5).
- Asking why a dose was skipped (Req 6.4).
- Push notifications, any server component, any network call (Req 3.5).
- Reminders for meals, glucose checks, or activity.
- Multiple independent schedules per insulin type, dose titration, or sick-day rules.

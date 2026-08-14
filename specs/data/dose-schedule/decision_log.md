# Decision Log: Dose Schedule

## Decision 1: Reverse the no-reminder requirement, because the reminder is the input

**Date**: 2026-08-14
**Status**: accepted

### Context

`specs/data/insulin-dosing` Requirement 12.7 states: "The system SHALL NOT prompt,
remind, nudge, or notify the developer to take a basal dose, and SHALL NOT display an
adherence figure, streak, or missed-dose indicator." Decision 13 of that spec gave
the reasoning: "adherence prompting is a behaviour-change feature rather than a
measurement one, and it is adjacent to the reassurance copy the developer-phase rule
forbids".

That reasoning conflated two different things under the word "prompt". A prompt
intended to change what the developer does is behaviour change. A prompt that exists
because it is the cheapest available place to *record* an event is a capture surface.
The developer's own framing is explicit that this is the second: the aim is "to
minimise the effort for data input, so it doesn't become burdensome", and "even
tracking doses would be immensely useful".

The friction argument is decisive. A basal dose is a fixed amount at a fixed time —
every quantity is known before the developer picks up the phone. The only unknown is
whether it happened and exactly when. Routing that one bit through unlock, app,
Graph, sheet, stepper, kind toggle and save guarantees an intermittent record, and an
intermittent record is worse than none: it biases every fit toward the days logging
felt easy.

### Decision

Reverse Req 12.7 **in part**. The system may schedule a recurring dose, may deliver a
repeating local reminder while it is outstanding, and may record it from the
notification in one tap.

The clause forbidding an **adherence figure, streak, or missed-dose indicator
survives untouched** (this spec's Req 2.5). Outstanding state is tracked because the
reminder cannot function without it; the developer is never scored on it.

The related non-goal in the same spec — "No notifications, timers, scheduled
follow-up doses, or extended/square-wave boluses. There is no scheduling surface in
the app today and none is added here." — falls only as to notifications and timers
for *this* purpose. Scheduled follow-up doses and extended boluses remain out of
scope there and here.

### Rationale

The distinction that makes the reversal safe is between prompting to change behaviour
and prompting to capture it. This spec's requirements enforce that line rather than
merely asserting it: no adherence display (Req 2.5), no reason asked for a skip
(Req 6.4), no encouragement text (Req 3.4), and no computed or pre-adjusted amount
(Req 5.3). Strip those away and the reminder is a keyboard shortcut with a clock.

The factual premise of the original non-goal is also already stale. It claims "there
is no scheduling surface in the app today", but `App/GlucoseConnectionsModel.swift`
registers and submits `BGAppRefreshTask` through `BGTaskScheduler` for the CGM poll.
What genuinely does not exist is `UNUserNotificationCenter`, which appears nowhere in
the tree.

### Alternatives Considered

- **Keep Req 12.7 and rely on the existing dose sheet**: the developer logs manually
  when they remember — Rejected: this is the status quo that produces the
  intermittent record. It also fails silently, because a missing event is
  indistinguishable from an unlogged one, so the gap is invisible in the data.
- **Surface outstanding doses in the lock-screen widget only, with no notification**:
  no permission prompt, no interruption, reuses shipped machinery — Rejected as
  insufficient on its own, and measurement says so: `specs/ui/glucose-lock-widget`
  task 16.7 measured WidgetKit granting ~20-minute wakes against a booked 5 minutes.
  A surface the developer must remember to look at, which may be up to 22 minutes
  stale, is not a reminder. Retained as the degraded mode when notification
  authorisation is refused (Req 7.2).
- **Reverse Req 12.7 entirely, including the adherence clause**: allow a streak or
  completion figure as motivation — Rejected: that is unambiguously behaviour change,
  it is the part of the original reasoning that was correct, and a compliance score
  is exactly the reassurance-adjacent copy the developer-phase rule exists to keep
  out.
- **Log the dose automatically at the scheduled time unless cancelled**: zero taps —
  Rejected outright. It would fabricate an insulin event that may not have happened,
  and every downstream fit would consume the fabrication as measurement. A record
  that is sometimes invented is worse than one that is sometimes missing, because
  nothing marks which is which.

### Consequences

**Positive:**

- The twice-daily basal record becomes plausible to sustain, which is the
  precondition for `specs/data/insulin-dosing` Req 12.4's activity pairing ever
  having data to pair.
- The one-tap path removes essentially all input cost in the common case.
- Skipped and missed doses become recorded facts rather than absences.

**Negative:**

- A sibling spec's requirement now contradicts this one until Req 12.7 is amended in
  place, which is owed work and is tracked as such.
- Notification authorisation introduces a permission the app has never asked for, and
  a refusal path that must be built and kept working (Req 7.2).
- A repeating reminder is intrinsically closer to nagging than anything shipped so
  far; the copy and cutoff rules are what keep it on the right side, and they are
  editorial constraints rather than mechanical ones.

### Impact

`specs/data/insulin-dosing/requirements.md` Req 12.7 and the notifications non-goal
both need amending in place to point here. Neither edit is made yet, because that
file is being modified concurrently by other work; both are owed.

---

## Decision 2: One tap means recording from the notification, not opening the app

**Date**: 2026-08-14
**Status**: accepted

### Context

"Minimise the effort for data input" admits several readings, and they differ by an
order of magnitude in cost. A reminder that deep-links into a pre-seeded sheet still
costs unlock, launch, wait, confirm. A reminder carrying its own action records the
dose from the lock screen without the app becoming visible at all.

The dose is a known quantity. Presenting a form to confirm a number the system
already holds is asking the developer to do work the system could do itself.

### Decision

The primary path is a notification action that writes the `insulin` event directly at
the nominal amount, without foregrounding the app (Req 4.1). A second action opens
the pre-seeded dose sheet for the days the amount differs (Req 5.1). Opening the app
is the exception, not the route.

### Rationale

This is the entire value of the feature. If recording still costs a launch, the
friction that produces the intermittent record has been reduced but not removed, and
the twice-daily discipline is still a matter of willpower rather than of cost.

Two actions rather than one is the minimum that stays honest, because the amount
genuinely varies: activity reduces the evening dose
(`specs/data/activity-events` Decision 1). A single nominal-only action would make the
easy path record a fiction on precisely the days that carry the most signal.

### Alternatives Considered

- **Deep link into a pre-seeded sheet as the only path**: simpler, no background
  write path, reuses the existing sheet — Rejected: it keeps the launch cost that
  this feature exists to remove, and the sheet would be confirming a number nothing
  is uncertain about.
- **A single action recording the nominal amount, with corrections made later**:
  simplest possible — Rejected: a correction made later is a second interaction with
  worse recall, and in practice the adjusted days would go unrecorded or be recorded
  wrongly. The days the amount changes are the ones a fit most needs.
- **An interactive control on the lock-screen widget instead of a notification**:
  no permission needed — Rejected: WidgetKit's measured ~20-minute wake budget
  (`specs/ui/glucose-lock-widget` task 16.7) makes the surface unreliable as a prompt,
  though it remains viable as the degraded display.

### Consequences

**Positive:**

- The common case is genuinely one tap, from the lock screen, app never opened.
- The uncommon case is one tap plus an adjustment, still cheaper than today's path.

**Negative:**

- Writing to the database from a notification-action handler is a code path with no
  precedent in this app, and it must be correct while the app is not running.
- Idempotency (Req 4.6) becomes load-bearing in a way it is not for sheet entry,
  since the action can be triggered from a stale notification.

---

## Decision 3: Persistence is a repeating reminder, not a Live Activity — for now

**Date**: 2026-08-14
**Status**: proposed

### Context

"A persistent reminder until DONE" has no exact iOS primitive. A delivered
notification can be swiped away and is then gone. The candidates are a repeating
notification that re-fires while the dose is outstanding, or an ActivityKit Live
Activity that occupies the lock screen and Dynamic Island until it is ended.

The Live Activity is the closer literal match, and the app is not starting from
nothing: `MeData/MeDataWidgets/` is an existing widget extension with its own
entitlements and a shared App Group. Live Activities are nevertheless bounded — the
system ends them after a number of hours — and they add a target, a state model, and
a second surface to keep correct.

### Decision

Implement persistence as a repeating local notification with a configurable interval
and a hard cutoff (Reqs 3.2, 3.3). Do not build a Live Activity in the first
iteration. Revisit only if the repeating reminder is observed in use to be
dismissable past the point of usefulness.

Status is `proposed` rather than `accepted` because the choice rests on an
expectation about how the developer will actually respond to a repeating
notification, and that has not been observed.

### Rationale

The repeating notification satisfies the stated need — a prompt that does not vanish
after one dismissal — at a fraction of the cost, and it carries the one-tap action
(Decision 2) natively, which is where the value is. A Live Activity's advantage is
presence, not capability, and presence is the part that can be added later without
rework if the cheaper mechanism proves insufficient.

The bounded lifetime also matters: a twice-daily schedule at 07:30 and 19:30 has
twelve-hour gaps, which exceeds the window a Live Activity is guaranteed to survive.
The mechanism that best matches "persistent" would still need the notification path
underneath it as a fallback.

### Alternatives Considered

- **Live Activity from the first iteration**: the closest literal match to
  "persistent until DONE" — Rejected for now on cost and on the twelve-hour gap
  exceeding its guaranteed lifetime; it would need the notification path built
  anyway.
- **A single non-repeating notification**: the simplest thing — Rejected: it fails
  the stated requirement directly. One swipe and the dose is unrecorded with nothing
  to recover it.
- **Escalating interruption levels, ending in a critical alert**: guarantees the
  prompt is seen — Rejected: critical alerts require Apple entitlement review, and
  presenting insulin timing as a medical alert is a posture this developer-phase
  build should not adopt (Req 3.6).

### Consequences

**Positive:**

- Smallest mechanism that meets the requirement, and the one that carries the one-tap
  action natively.
- No new target, no Live Activity state model, no second surface to keep consistent.

**Negative:**

- Not literally persistent: a determined dismissal at every repeat still loses the
  dose, and only the cutoff bounds it.
- Repeating notifications are the mechanism most likely to feel like nagging, so the
  default interval and cutoff carry more weight than their apparent triviality.
- If the mechanism does prove insufficient, the Live Activity work is additional
  rather than instead — this decision spends a little to defer a lot.

---

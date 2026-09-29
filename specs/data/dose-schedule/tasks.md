---
references:
    - specs/data/dose-schedule/requirements.md
    - specs/data/dose-schedule/design.md
    - specs/data/dose-schedule/decision_log.md
metadata:
    ledger_note: |-
        Phases 1 and 2 are pure Foundation and MedataCore work: free functions taking a
        Calendar and a Date explicitly, plus one side table. They are macOS-testable and
        agent-executable end to end.

        Phases 3 and 4 touch UNUserNotificationCenter, which appears nowhere in the tree
        today. They can be built without a device but they cannot be VERIFIED without one:
        notification delivery, repeat cadence, cutoff, and the background-launch action
        handler have no simulator-faithful equivalent.

        Tasks whose title contains STOP need a physical iPhone 16 Pro, an export of the
        live database, or a human verdict. They are never run autonomously.

        Test gate: MedataCore maths and transitions get tests (PersistenceTests). No
        app-target test scaffolding is written — MeData/Tests/ and MeData/UITests/ are
        documentation contracts, not an executable suite, and no committed target runs
        them.
---
# Tasks: Dose Schedule

## Phase 1 — Schedule model and occurrence arithmetic (Foundation-only, macOS-testable)

- [x] 1. Define ScheduledDose, OccurrenceOutcome and DoseOccurrence <!-- id:ds1kq4a -->
  - Shapes exactly as design.md section 4, in MedataCore/Sources/Persistence/ beside InsulinDose; Foundation only, no store dependency
  - ScheduledDose carries hour, minute, nominalUnits, kind (the shipped InsulinKind enum, reused not redeclared), isEnabled — wall-clock hour and minute, never a stored Date, so the schedule follows the device time zone by construction
  - DoseOccurrence carries scheduleID, dueAt, outcome, closedAt, insulinEventID, wasNominal; insulinEventID stays nil unless the outcome is logged, and wasNominal stays nil unless a dose was recorded
  - The occurrence, not the ScheduledDose, is the historical record: a scheduled dose is configuration and holds no history, which is what makes Req 1.5 mechanical rather than a rule to remember
  - Requirements: [1.1](requirements.md#1.1), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [5.2](requirements.md#5.2), [6.2](requirements.md#6.2)

- [x] 2. Persist the schedule as settings, with the two seeded entries <!-- id:ds2mv7b -->
  - ScheduledDose list lives in settings (a Codable array behind a new SettingsKeys entry), not a table — giving it a table would imply a history it does not have
  - Seed on first use only: 15 U basal at 07:30 and 15 U basal at 19:30; a developer who deletes both must not have them return on next launch
  - An empty schedule is a valid state and the whole feature is inert in it — no notification plan, no in-app row, no authorisation request
  - Blocked-by: ds1kq4a (Define ScheduledDose, OccurrenceOutcome and DoseOccurrence)
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.7](requirements.md#1.7)

- [x] 3. Pure next-occurrence function over a Calendar and a Date <!-- id:ds3rn8c -->
  - nextDueDate(for schedule: ScheduledDose, after instant: Date, calendar: Calendar) -> Date, a free function; the Calendar and the Date are both parameters, never Calendar.current or Date() read inside
  - Resolves hour and minute against the calendar's time zone so 07:30 stays 07:30 across travel and across a daylight-saving transition, including the spring-forward case where the wall-clock time does not exist and the autumn case where it occurs twice
  - Disabled schedules produce no occurrence; the function returns nil rather than a sentinel date
  - Blocked-by: ds1kq4a (Define ScheduledDose, OccurrenceOutcome and DoseOccurrence)
  - Requirements: [1.6](requirements.md#1.6), [2.1](requirements.md#2.1)

- [x] 4. Pure missed-successor rule <!-- id:ds4tp2d -->
  - A free function taking the outstanding occurrences, a Calendar and a now Date, returning the occurrence ids to close as missed
  - Req 2.3 caps outstanding occurrences at one per schedule: an outstanding row whose successor is already due closes as missed, and closes exactly one, not a backlog of every skipped day since the schedule was created
  - Evaluated lazily at read time — app foreground, or a notification handler resolving its occurrence — never on a timer or a background task, because App/GlucoseConnectionsModel.swift already spends the app's background budget on the CGM BGAppRefreshTask
  - Nothing acts on a missed outcome beyond recording it, so the latency of lazy marking is harmless and must not be engineered away
  - Blocked-by: ds3rn8c (Pure next-occurrence function over a Calendar and a Date)
  - Requirements: [2.3](requirements.md#2.3), [6.2](requirements.md#6.2)

- [x] 5. Pure notification identifier derivation <!-- id:ds5wj6e -->
  - dose.SCHEDULEID.yyyy-MM-dd.n where n is 0 for the due notification and 1 to K for the follow-ups, per design.md section 1
  - Derived from schedule id and local date, never stored, so a cancellation never depends on having persisted a notification handle — an app killed between delivery and discharge can still cancel the tail
  - The date component is formatted against the same Calendar passed in, so the identifier and the fire date cannot disagree about which day it is
  - Blocked-by: ds1kq4a (Define ScheduledDose, OccurrenceOutcome and DoseOccurrence)
  - Requirements: [3.2](requirements.md#3.2), [3.3](requirements.md#3.3)

- [x] 6. MedataCore tests for the pure arithmetic <!-- id:ds6xz3f -->
  - Next occurrence across a daylight-saving transition stays at 07:30 local, in both directions
  - The missed-successor rule closes exactly one occurrence, not a backlog
  - Identifiers derive deterministically from schedule id and local date, and the same inputs give the same string
  - Every case constructs its own Calendar and Date — no test may read the host clock or the host time zone
  - MVP test gate: MedataCore only. Do NOT add app-target test scaffolding
  - Blocked-by: ds3rn8c (Pure next-occurrence function over a Calendar and a Date), ds4tp2d (Pure missed-successor rule), ds5wj6e (Pure notification identifier derivation)
  - Requirements: [1.6](requirements.md#1.6), [2.3](requirements.md#2.3), [3.3](requirements.md#3.3)

## Phase 2 — The occurrence ledger

- [x] 7. dose_occurrences table and migration <!-- id:ds7cl9g -->
  - Follows estimation_outcomes and dose_suggestions: a derived side table in the same database, created by a new schema version in GRDBPersistenceStore
  - Writes to this table MUST NOT call changeBroadcaster.notify() — only the insulin event fires eventsDidChange, so history refreshes exactly once per logged dose rather than twice
  - Index on (schedule_id, due_at) — the hot read is "the outstanding occurrence for this schedule"
  - Blocked-by: ds1kq4a (Define ScheduledDose, OccurrenceOutcome and DoseOccurrence)
  - Requirements: [6.2](requirements.md#6.2)

- [x] 8. Store surface: open an occurrence, and closeOccurrence as a compare-and-set <!-- id:ds8hb5h -->
  - closeOccurrence(id:outcome:closedAt:insulinEventID:wasNominal:) records an outcome ONLY if the row is still outstanding, and returns whether it transitioned; the caller writes the insulin event only when it did
  - This is a genuine compare-and-set inside the write transaction, not the advisory guard the widget snapshot publisher uses — single process, single writer, so it can be exact and Req 4.6 depends on it being exact
  - The insulin event written on a logged occurrence goes through the existing saveInsulinDose unchanged: byte-identical metadata to sheet entry, nothing added to insulinMetadataJSON, so medreg's convention is untouched
  - Req 4.4's link therefore lives on the OCCURRENCE row, not on the event: insulinEventID joins them, and dueAt minus closedAt gives lateness by subtraction with no new column
  - closedAt is the moment the dose was logged, never the scheduled time (Req 4.3) — the two routinely differ and the difference is the measurement
  - Blocked-by: ds7cl9g (dose_occurrences table and migration), ds4tp2d (Pure missed-successor rule)
  - Requirements: [2.2](requirements.md#2.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.6](requirements.md#4.6)

- [x] 9. MedataCore tests for the ledger transitions <!-- id:ds9fd1j -->
  - closeOccurrence is idempotent: the second call reports no transition, and the test asserts the event count is unchanged — the assertion is on what was NOT written
  - A skipped or missed occurrence writes no insulin event of any amount, including zero
  - Editing a ScheduledDose leaves already-closed occurrences byte-identical (Req 1.5)
  - Blocked-by: ds8hb5h (Store surface: open an occurrence, and closeOccurrence as a compare-and-set)
  - Requirements: [1.5](requirements.md#1.5), [4.6](requirements.md#4.6), [6.3](requirements.md#6.3)

## Phase 3 — A general local-reminder capability

- [x] 10. LocalReminderScheduler in App/, knowing nothing about insulin <!-- id:dsa0gk2 -->
  - Req 8.1 is structural, not aspirational: the scheduler takes a reminder description — identifier prefix, fire date, category, payload — and contains no reference to doses, units or InsulinKind. The fat follow-up (specs/data/insulin-dosing tasks.md task 22, "blocked on machinery that does not exist") adopts this type as-is or the requirement was not met
  - One UNCalendarNotificationTrigger at the fire time with repeats true, plus K UNTimeIntervalNotificationTrigger follow-ups at interval I, identifiers from task 5
  - Cancellation takes an identifier set: removePendingNotificationRequests for the unfired tail and removeDeliveredNotifications for anything already shown
  - No background execution, no timer keeping anything alive — the cutoff of Req 3.3 is K times I and falls out of scheduling the whole sequence up front
  - All scheduling is local; no push service, no server, no network call anywhere in this file
  - Register the new file in project.pbxproj (four sections — see the checklist in docs/agent-notes/ui-capture-flow.md)
  - Blocked-by: ds5wj6e (Pure notification identifier derivation)
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.5](requirements.md#3.5), [8.1](requirements.md#8.1)

- [x] 11. Authorisation requested at first enable, never at launch <!-- id:dsb1hn4 -->
  - requestAuthorization fires when the developer first enables a scheduled dose and at no other moment; nothing in App.swift or AppRoot triggers it
  - A refusal is recorded and never re-prompted; a later revocation is detected on foreground via notificationSettings and handled the same way
  - Refusal degrades nothing else — no other feature reads this state, and the app is fully functional with the permission denied
  - Blocked-by: dsa0gk2 (LocalReminderScheduler in App/, knowing nothing about insulin)
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2)

- [x] 12. Notification category with the two actions <!-- id:dsc2jp6 -->
  - LOG_NOMINAL carries NO options — deliberately omitting .foreground is the whole mechanism (Decision 2): iOS launches the app in the background, the delegate runs, nothing appears on screen
  - ADJUST carries .foreground and opens the pre-seeded dose sheet
  - Body text is a kind, a quantity and a time. No reassurance, encouragement, warning or coaching text — the developer-phase copy rule is not softened by the notification being outside the app
  - Interruption level stays at the default active/time-sensitive band; critical alerts require Apple entitlement review and would present insulin timing as a medical alert
  - Blocked-by: dsa0gk2 (LocalReminderScheduler in App/, knowing nothing about insulin)
  - Requirements: [3.4](requirements.md#3.4), [3.6](requirements.md#3.6), [4.1](requirements.md#4.1), [5.1](requirements.md#5.1)

- [x] 13. The delegate: the background write path, shortest possible body <!-- id:dsd3lr8 -->
  - userNotificationCenter(_:didReceive:withCompletionHandler:) runs with the app NOT running, under a short system deadline, and it must reach GRDB. There is no precedent for this path in the tree
  - Body is exactly: resolve the occurrence, closeOccurrence (compare-and-set), write the insulin event only if it transitioned, cancel the tail, call the completion handler. Nothing else
  - Explicitly forbidden in this handler: any UI, any migration work, any CGM poll, any widget publish, any work that can be deferred to the next foreground
  - A stale follow-up delivered before the dose was logged elsewhere must write NOTHING — the compare-and-set from task 8 is the only thing standing between this and a duplicate dose in the record
  - The completion handler must fire on every path, including the failure paths, or iOS records the extension as having hung
  - Buildable and reviewable without a device; verification is task 21
  - Blocked-by: dsc2jp6 (Notification category with the two actions), ds8hb5h (Store surface: open an occurrence, and closeOccurrence as a compare-and-set)
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.6](requirements.md#4.6), [7.3](requirements.md#7.3)

- [x] 14. Reconcile the notification plan against the ledger <!-- id:dse4mt0 -->
  - The plan is derived, never authoritative: rebuild it from the enabled schedules plus the outstanding occurrences on foreground, on schedule edit, on enable and disable, and on a time-zone change
  - Cancel the tail the moment an occurrence closes, by whichever route closed it — notification action, in-app discharge, skip, or the missed rule
  - A schedule deleted or disabled leaves no pending requests behind; a stale identifier surviving a delete is the defect this task exists to prevent
  - Blocked-by: dsa0gk2 (LocalReminderScheduler in App/, knowing nothing about insulin), ds8hb5h (Store surface: open an occurrence, and closeOccurrence as a compare-and-set)
  - Requirements: [1.6](requirements.md#1.6), [3.1](requirements.md#3.1), [3.3](requirements.md#3.3)

## Phase 4 — In-app surface

- [x] 15. Outstanding-dose row with one-tap discharge <!-- id:dsf5nv3 -->
  - Reads the ledger directly and renders whenever an occurrence is outstanding, with no dependence on a notification having been delivered or seen — the ledger is the source of truth and notifications are a view onto it
  - Carries the same one-tap discharge as LOG_NOMINAL, sharing the exact code path from task 13 rather than a parallel copy of it
  - No adherence percentage, no streak, no compliance score, no comparison against a target. Outstanding state is tracked because the reminder cannot function without it; scoring the developer on it stays out of scope
  - Register any new file in project.pbxproj (four sections)
  - Blocked-by: ds8hb5h (Store surface: open an occurrence, and closeOccurrence as a compare-and-set), ds2mv7b (Persist the schedule as settings, with the two seeded entries)
  - Requirements: [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [4.5](requirements.md#4.5)

- [x] 16. ADJUST opens the dose sheet pre-seeded, and records that the amount was adjusted <!-- id:dsg6qw5 -->
  - Reuses InsulinDoseSheet and InsulinDoseModel with kind and nominal units pre-set; the sheet is not rebuilt and gains no schedule-specific controls
  - Arrives through the existing AppRoot pendingDeepLink resume, so landing during a dismissing presentation is not silently dropped (see docs/agent-notes/insulin-dose-ui.md)
  - Saving through the sheet closes the occurrence with wasNominal false; the one-tap path closes it with wasNominal true. A fit can then tell a default-accepted dose from a deliberately chosen one
  - The system does not suggest, compute or pre-adjust the amount from recorded activity — the magnitude of that relationship is unmeasured and this spec does not invent one
  - Blocked-by: dsc2jp6 (Notification category with the two actions), ds8hb5h (Store surface: open an occurrence, and closeOccurrence as a compare-and-set)
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3)

- [x] 17. Skip an outstanding dose <!-- id:dsh7rx7 -->
  - Ends the reminder and closes the occurrence as skipped, writing no insulin event of any amount including zero
  - Does not ask why. There is no reason field, no picker, no free-text prompt
  - Available from the in-app row; the notification carries only the two actions from task 12
  - Superseded (Decision 5): the per-occurrence Skip affordance is removed from both surfaces — the outstanding-dose surface routes to the schedule's settings instead; DoseDischarge.skip survives for the schedule-delete path
  - Blocked-by: dsf5nv3 (Outstanding-dose row with one-tap discharge)
  - Requirements: [6.1](requirements.md#6.1), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)

- [x] 18. Schedule editing in Settings, including the interval and the cutoff <!-- id:dsj8sy9 -->
  - Add, edit, delete and disable a scheduled dose; disable is distinct from delete so a regime change is reversible without re-entering it
  - Interval I and follow-up count K are editable, seeded at 30 minutes and 4 for a two-hour tail. They are a starting point, not a finding, and the UI must not present them as recommended values
  - Editing a schedule alters no already-recorded dose and closes no open occurrence retrospectively
  - Follows the existing settings-row pattern; functional copy only
  - Blocked-by: ds2mv7b (Persist the schedule as settings, with the two seeded entries), dsb1hn4 (Authorisation requested at first enable, never at launch)
  - Requirements: [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3)

- [x] 19. Degraded mode with notification authorisation refused or revoked <!-- id:dsk9tz1 -->
  - Not an afterthought and not an error state: the same feature with the notification plan skipped. The ledger is written and read identically, and the in-app row plus its one-tap discharge carry the whole feature
  - Occurrences still open at their due time and still close as missed under the successor rule with no notification involved anywhere
  - No re-prompt, no banner asking the developer to reconsider, no reduced function in any other part of the app
  - Blocked-by: dsf5nv3 (Outstanding-dose row with one-tap discharge), dsb1hn4 (Authorisation requested at first enable, never at launch), dse4mt0 (Reconcile the notification plan against the ledger)
  - Requirements: [7.2](requirements.md#7.2), [2.4](requirements.md#2.4), [4.5](requirements.md#4.5)

## Phase 5 — Verify

- [x] 20. make test green, make build, make spell clean <!-- id:dsm0ub4 -->
  - Report BOTH totals — XCTest and swift-testing; the swift-testing slice alone is not the test count
  - Blocked-by: ds6xz3f (MedataCore tests for the pure arithmetic), ds9fd1j (MedataCore tests for the ledger transitions), dsj8sy9 (Schedule editing in Settings, including the interval and the cutoff), dsk9tz1 (Degraded mode with notification authorisation refused or revoked), dsg6qw5 (ADJUST opens the dose sheet pre-seeded, and records that the amount was adjusted), dsh7rx7 (Skip an outstanding dose)

- [ ] 21. STOP — on-device: the reminder fires, repeats, and stops <!-- id:dsn1vc6 -->
  - Physical iPhone 16 Pro. Notification delivery, repeat cadence and cutoff have no simulator-faithful equivalent and cannot be verified any other way
  - Confirm the due notification arrives at the scheduled time with the app not running, that follow-ups arrive at I, and that the sequence stops at K times I with the dose left outstanding
  - Confirm the daily UNCalendarNotificationTrigger re-fires the following day without the app having been opened in between
  - Match event=launch buildStamp=… before trusting any device output
  - Blocked-by: dsm0ub4 (make test green, make build, make spell clean)
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [7.3](requirements.md#7.3)

- [ ] 22. STOP — on-device: one tap from the lock screen, app never appears <!-- id:dsp2wd8 -->
  - Physical iPhone 16 Pro, human verdict. Force-quit the app first: the whole claim is that the handler works with the app NOT running
  - Confirm the tap writes the insulin row, that no screen appears at any point, and that the row is byte-identical in shape to one entered through the dose sheet
  - Confirm the occurrence closes, the tail is cancelled, and the delivered notifications are cleared
  - Watch specifically for the completion handler missing the system deadline — a write that lands late or not at all is the failure mode this path introduces
  - Blocked-by: dsn1vc6 (STOP — on-device: the reminder fires, repeats, and stops)
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [7.3](requirements.md#7.3)

- [ ] 23. STOP — on-device: a stale follow-up after the dose was logged elsewhere writes nothing <!-- id:dsq3xe0 -->
  - Physical iPhone 16 Pro. Log the dose from the in-app row while a follow-up notification is already delivered and sitting in Notification Centre, then tap that stale notification
  - Confirm exactly one insulin event exists for the occurrence, not two, and that the second action wrote nothing at all
  - This is the only test of Req 4.6 that exercises the real delivery timing; the MedataCore test in task 9 covers the transition, not the race that produces it
  - Blocked-by: dsp2wd8 (STOP — on-device: one tap from the lock screen, app never appears)
  - Requirements: [4.6](requirements.md#4.6)

- [ ] 24. STOP — on-device: degraded mode with authorisation refused <!-- id:dsr4yf2 -->
  - Physical iPhone 16 Pro. Refuse notification authorisation, then revoke it in system Settings after having granted it, and check both paths
  - Confirm occurrences still open and close, the in-app row still discharges in one tap, nothing re-prompts, and no other feature changes behaviour
  - Blocked-by: dsn1vc6 (STOP — on-device: the reminder fires, repeats, and stops)
  - Requirements: [7.2](requirements.md#7.2), [2.4](requirements.md#2.4), [4.5](requirements.md#4.5)

- [ ] 25. STOP — close Decision 3: is the repeating reminder actually enough <!-- id:dss5zg5 -->
  - Decision 3 is proposed, not accepted, and says so explicitly: the choice of a repeating notification over a Live Activity rests on an expectation about how the developer responds to a repeating reminder, and that has not been observed
  - After a sustained period of real use, record the verdict: how often a dose was dismissed at every repeat and lost to the cutoff, and whether the prompt was ever felt as nagging
  - Then either promote Decision 3 to accepted with the observation quoted, or supersede it with a Live Activity decision. Leaving it proposed after the evidence exists is the outcome this task forbids
  - Human verdict, not a measurement a tool can produce
  - Blocked-by: dsq3xe0 (STOP — on-device: a stale follow-up after the dose was logged elsewhere writes nothing), dsr4yf2 (STOP — on-device: degraded mode with authorisation refused)

- [ ] 26. STOP — set I and K from the measured outstanding distribution <!-- id:dst6ah7 -->
  - 30 minutes times 4 is reasoned, not measured — design.md open question 1 says so
  - Once occurrences carry dueAt and closedAt over real use, the distribution of how long a dose actually stays outstanding is directly measurable from an exported database. Set both values from it and record the figures
  - Needs an export of the live database, so it cannot run autonomously
  - Blocked-by: dsq3xe0 (STOP — on-device: a stale follow-up after the dose was logged elsewhere writes nothing)
  - Requirements: [3.2](requirements.md#3.2), [3.3](requirements.md#3.3)

- [x] 27. Amend the sibling spec that this one contradicts <!-- id:dsu7bj9 -->
  - Decision 1 Impact records this as owed: specs/data/insulin-dosing/requirements.md Req 12.7 and the notifications non-goal both need amending in place to point here
  - The reversal is partial — the clause forbidding an adherence figure, streak or missed-dose indicator survives untouched, and the amendment must say so rather than deleting Req 12.7 wholesale
  - Deferred because that file was being modified concurrently when this spec was written; check it is free before editing
  - Blocked-by: dsm0ub4 (make test green, make build, make spell clean)

- [ ] 28. Regenerate the specs index <!-- id:dsv8ck1 -->
  - /specs-overview so specs/OVERVIEW.md carries this spec
  - Blocked-by: dss5zg5 (STOP — close Decision 3: is the repeating reminder actually enough), dsu7bj9 (Amend the sibling spec that this one contradicts)

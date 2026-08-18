# Dose schedule — the reminder and the one-tap log

`specs/data/dose-schedule`. A recurring-dose schedule, a repeating local
reminder while the dose is outstanding, and a one-tap log from the lock screen.
Store side is in `docs/agent-notes/persistence.md` under "Dose occurrences".

## The shape, in one paragraph

Three separable pieces. **Configuration** (`ScheduledDose`) lives in settings.
The **occurrence ledger** (`dose_occurrences`, schema v9) is the only new
persisted state and the only source of truth for whether a dose is outstanding.
The **notification plan** is derived from the two and is never authoritative —
it is torn down and rebuilt on every foreground, edit, enable, disable and
close.

## Where things live

| Piece | File |
|---|---|
| Types (`ScheduledDose`, `DoseOccurrence`, `OccurrenceOutcome`) | `MedataCore/Sources/Persistence/DoseSchedule.swift` |
| Pure arithmetic (`nextDueDate`, missed rule, identifiers, `ReminderPlan`) | `MedataCore/Sources/Persistence/DoseScheduleMath.swift` |
| Store surface | `GRDBPersistenceStore.swift`, "Dose occurrences" MARK |
| Settings storage + seed + surface switch | `App/DoseScheduleSettings.swift` |
| General reminder capability | `App/LocalReminderScheduler.swift` |
| Dose-specific orchestration, category, discharge | `App/DoseScheduleModel.swift` |
| Background write path | `App/DoseNotificationDelegate.swift` |
| UI attempt 1 (banner) | `App/OutstandingDoseBanner.swift` |
| Schedule editing | `App/DoseScheduleSettingsSection.swift` |

## Gotchas

**Notifications are dated one-shots, never repeating.** See Decision 4. A
repeating trigger cannot be cancelled for one day only, so discharging Monday's
dose would end Tuesday's reminder. The plan therefore has a **horizon** —
`min(7, 64 / (enabledSchedules x (K+1)))` days, six with the developer's two
schedules — and the app must be opened inside it or the prompts stop. The
ledger keeps working regardless; only the prompt is lost.

**`LocalReminderScheduler` must stay insulin-free.** Req 8.1 is structural: the
delayed fat follow-up (`specs/data/insulin-dosing` task 22) adopts this type
as-is. If a `ScheduledDose`, a unit or an `InsulinKind` ever appears in that
file, the requirement has been broken. Everything dose-shaped belongs in
`DoseScheduleModel`.

**There is exactly one discharge path.** `DoseDischarge.log` is called by the
notification action, the in-app row and (via `recordAdjusted`) the sheet. A
parallel copy is how a duplicate dose gets into the record. The event id is
minted BEFORE the compare-and-set so a process death between the two writes
leaves a named inconsistency rather than an anonymous one.

**The notification handler's body is fixed by task 13.** Resolve, compare-and-set,
write only on transition, cancel the tail, return. No UI, no migration, no CGM
poll, no widget publish, and nothing deferrable. It runs with the app not
running under a short system deadline. `openOccurrence` doubles as the resolve
step precisely because it is one round trip that cannot manufacture a second
row.

**The tail identifiers travel in `userInfo`.** They could be re-derived, but
carrying them makes it impossible for what is cancelled to disagree with what
was armed, and it keeps the handler at the five permitted steps. `userInfo` is
`[String: String]` because the system archives it while the app is not running.

**The missed rule is lazy and must stay lazy.** It runs when something looks —
foreground, or a schedule edit. Never a timer, never a background task: the CGM
`BGAppRefreshTask` already spends that budget. Nothing acts on a `missed`
outcome beyond recording it, so the latency is harmless.

**An orphaned occurrence is the delete path's problem, not the rule's.**
`occurrencesToCloseAsMissed` leaves an occurrence whose schedule is gone alone —
it has no successor to compare against. `DoseScheduleModel.delete(scheduleID:)`
closes it as skipped instead, because that path knows the intent.

**There is no per-occurrence Skip in the UI** (Decision 5). Both surfaces
carry a gear routing to the schedule's settings where Skip used to be — a
dose one would skip every time means the schedule is wrong, and the fix is
editing or removing it. `DoseDischarge.skip` remains live: it is the
schedule-delete path above, and historical `skipped` rows keep decoding.
The `OccurrenceOutcome` enum, the store, and the MedataCore tests are
untouched.

**`I` and `K` are guesses.** 30 minutes x 4 is reasoned, not measured
(design.md open question 1, task 26). Once `dueAt`/`closedAt` pairs accumulate,
set both from the distribution. The Settings copy must not present them as
recommended values.

## Test surface

`MedataCore/Tests/PersistenceTests/DoseScheduleMathTests.swift` (the pure
arithmetic — every case builds its own `Calendar` and `Date`, none reads the
host clock or zone) and `DoseOccurrenceTests.swift` (the ledger transitions —
the load-bearing assertions are on what was NOT written). No app-target
scaffolding: `MeData/Tests/` is a documentation contract, not an executable
suite.

## Two UI attempts

Tagged `dose-schedule-ui-attempt-1` and `dose-schedule-ui-attempt-2`, and both
reachable on the tip through the `medata.doseSchedule.surfaceStyle` switch in
Settings. Attempt 1 gives the outstanding dose its own card on Home with Log
and Adjust visible plus the schedule-settings gear; attempt 2 overloads the
existing Dose route control so nothing new appears on screen, with Adjust and
the gear route behind a long press. See the commit messages on the two tags
for what each trades away.

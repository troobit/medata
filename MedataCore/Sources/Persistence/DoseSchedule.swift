import Foundation

// The dose schedule and its occurrence ledger (specs/data/dose-schedule,
// design.md section 4). Foundation only — nothing here touches the store, and
// nothing here reads an ambient clock, calendar or time zone.
//
// The split is the point. `ScheduledDose` is CONFIGURATION: it lives in
// settings, it holds no history, and editing it can therefore not alter a dose
// already recorded (Req 1.5 is mechanical rather than a rule to remember).
// `DoseOccurrence` is the historical record: one row per due instance,
// carrying its outcome, because a dose not taken is data and an absent event
// is indistinguishable from an unlogged one (Req 6.2).

// One recurring dose in the developer's regime (Req 1.1). The time of day is a
// wall-clock `hour` and `minute`, never a stored `Date`: that is what makes the
// schedule follow the device's time zone by construction, so 07:30 stays 07:30
// after travel and across a daylight-saving transition (Req 1.6).
public struct ScheduledDose: Sendable, Equatable, Identifiable, Codable {
    public let id: UUID
    public var hour: Int  // local wall clock, 0...23
    public var minute: Int  // local wall clock, 0...59
    public var nominalUnits: Double
    public var kind: InsulinKind  // the shipped enum, reused not redeclared
    public var isEnabled: Bool  // disable without deleting (Req 1.4)

    public init(
        id: UUID = UUID(),
        hour: Int,
        minute: Int,
        nominalUnits: Double,
        kind: InsulinKind,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.nominalUnits = nominalUnits
        self.kind = kind
        self.isEnabled = isEnabled
    }

    // The developer's standing regime (Req 1.2): 15 U basal at 07:30 and 15 U
    // basal at 19:30. Seeded on FIRST USE ONLY — a developer who deletes both
    // must not have them return on the next launch, so the caller gates this
    // on a persisted "seeded" flag rather than on the list being empty.
    public static func seedSchedules() -> [ScheduledDose] {
        [
            ScheduledDose(hour: 7, minute: 30, nominalUnits: 15, kind: .basal),
            ScheduledDose(hour: 19, minute: 30, nominalUnits: 15, kind: .basal)
        ]
    }
}

// How a due occurrence ended. `outstanding` is the open state; the other three
// are terminal, and `closeOccurrence` only ever moves outstanding → terminal.
public enum OccurrenceOutcome: String, Sendable, Equatable, CaseIterable, Codable {
    case outstanding
    // A dose was recorded. `insulinEventID` names the `events` row.
    case logged
    // The developer ended the reminder deliberately without taking the dose
    // (Req 6.1). No insulin event of any amount, including zero (Req 6.3).
    case skipped
    // The next occurrence became due while this one was still outstanding
    // (Req 2.3). Closed by the missed-successor rule, never by a timer.
    case missed
}

// One due instance of a scheduled dose. This is the only new persisted state
// the feature introduces, and it is the source of truth for whether a dose is
// outstanding — notifications are a view onto it, never the other way round
// (Req 2.4, design.md section 6).
//
// Req 4.4's lateness data needs no column of its own: `dueAt` and `closedAt`
// on the same row give it by subtraction.
public struct DoseOccurrence: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let scheduleID: UUID
    public let dueAt: Date  // the scheduled instant
    public var outcome: OccurrenceOutcome
    // The moment the outcome was recorded — for a logged dose, the moment it
    // was LOGGED, never the scheduled time (Req 4.3). The two routinely differ
    // and the difference is the measurement.
    public var closedAt: Date?
    // Nil unless the outcome is `logged` (Req 6.3).
    public var insulinEventID: UUID?
    // Whether the recorded amount was the schedule's nominal one (Req 5.2).
    // Nil unless a dose was recorded, so "no dose" and "nominal dose" cannot
    // be confused.
    public var wasNominal: Bool?

    public init(
        id: UUID = UUID(),
        scheduleID: UUID,
        dueAt: Date,
        outcome: OccurrenceOutcome = .outstanding,
        closedAt: Date? = nil,
        insulinEventID: UUID? = nil,
        wasNominal: Bool? = nil
    ) {
        self.id = id
        self.scheduleID = scheduleID
        self.dueAt = dueAt
        self.outcome = outcome
        self.closedAt = closedAt
        self.insulinEventID = insulinEventID
        self.wasNominal = wasNominal
    }
}

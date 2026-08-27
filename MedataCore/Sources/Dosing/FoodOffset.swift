// Unoffset membership (specs/data/insulin-dosing Req 4.8, Decisions 17/18).
//
// Insulin dosed for food already consumed is spoken for by that food. Counting
// it against the next meal under-dosed every meal that followed another inside
// the duration of action, so only boluses with no food behind them — a
// correction or a freestanding dose — reduce a meal's coverage.
//
// Everything here is a pure function of instants and units. No store type
// crosses this boundary (Req 10.3): the caller queries the events and hands
// over plain dates.
import Foundation

/// One prior bolus at its own instant. `BolusHistoryEntry` expresses a dose
/// relative to the instant insulin-on-board is wanted at; membership needs the
/// absolute instant, because the food that offsets a bolus may itself be later
/// than the bolus (a pre-bolus) and later than the subject meal.
public struct DatedBolus: Sendable, Equatable {

    public let instant: Date
    public let units: Double

    public init(instant: Date, units: Double) {
        self.instant = instant
        self.units = units
    }
}

/// The association window, and the event spans a caller must cover to apply it.
public enum FoodOffsetWindow {

    /// 45 minutes, deliberately the same constant as the dose seed's lifetime
    /// and the Req 11.2 pairing window — one association rule, not three.
    public static let window: TimeInterval = 45 * 60

    /// The boluses that can contribute: exactly the duration of action back
    /// from the subject instant, so the query returns only doses with a
    /// non-zero remainder (Req 4.3).
    public static func bolusSpan(
        at instant: Date, model: InsulinActivityModel = .rapidActing
    ) -> ClosedRange<Date> {
        instant.addingTimeInterval(-model.durationMinutes * 60)...instant
    }

    /// The meals and intakes that can offset one of those boluses: the bolus
    /// span widened by the association window at **both** ends, because the
    /// ±45-minute test is symmetric (Req 4.8). A meal recorded after the
    /// subject instant can still offset a bolus that fell before it.
    public static func mealOrIntakeSpan(
        at instant: Date, model: InsulinActivityModel = .rapidActing
    ) -> ClosedRange<Date> {
        let lower = instant.addingTimeInterval(-model.durationMinutes * 60 - window)
        return lower...instant.addingTimeInterval(window)
    }
}

/// True when food stands behind the bolus (Req 4.8): a recorded meal or
/// carbohydrate intake within 45 minutes either side of it, boundary inclusive
/// (`|delta| <= 45 min`). The symmetric window covers pre-bolusing — insulin
/// taken up to 45 minutes before eating. Offset boluses never reduce a later
/// meal's coverage.
public func isOffsetByFood(
    bolusInstant: Date,
    mealOrIntakeInstants: [Date],
    window: TimeInterval = FoodOffsetWindow.window
) -> Bool {
    mealOrIntakeInstants.contains { instant in
        abs(instant.timeIntervalSince(bolusInstant)) <= window
    }
}

/// The unoffset insulin-on-board at `instant` (Req 4.8) — the only insulin
/// figure the suggester consumes (Req 3.1). The physiological total over every
/// bolus is not computed: no surface consumes it, and the retrospective
/// measurement derives it off-device from the exported boluses (Decision 18).
///
/// The curve and the summation are unchanged, so medreg parity holds
/// (Req 4.6); membership only decides which boluses reach them.
public func unoffsetInsulinOnBoard(
    _ boluses: [DatedBolus],
    mealOrIntakeInstants: [Date],
    at instant: Date,
    window: TimeInterval = FoodOffsetWindow.window,
    model: InsulinActivityModel = .rapidActing
) -> Double {
    let unoffset = boluses.filter { bolus in
        !isOffsetByFood(
            bolusInstant: bolus.instant,
            mealOrIntakeInstants: mealOrIntakeInstants,
            window: window)
    }
    return insulinOnBoard(
        unoffset.map {
            BolusHistoryEntry(
                minutesBefore: instant.timeIntervalSince($0.instant) / 60, units: $0.units)
        },
        model: model)
}

import Foundation

/// The oref0 / LoopKit exponential insulin-activity model, ported term for
/// term from medreg's `ExponentialInsulinModel` (specs/data/insulin-dosing
/// Req 4). Only the `iob` branch is ported — nothing in the app consumes an
/// action rate.
public struct InsulinActivityModel: Sendable, Equatable {
    public let peakMinutes: Double
    public let durationMinutes: Double

    /// medreg's RAPID_ACTING preset (peak 75 min, DIA 360 min), Req 4.1.
    public static let rapidActing = InsulinActivityModel(peakMinutes: 75, durationMinutes: 360)

    public init(peakMinutes: Double, durationMinutes: Double) {
        self.peakMinutes = peakMinutes
        self.durationMinutes = durationMinutes
    }

    /// Fraction of one unit still on board after `minutes`. 1.0 at or before
    /// delivery, 0.0 at or beyond the duration of action (Req 4.3).
    ///
    ///     tau = tp · (1 − tp/td) / (1 − 2·tp/td)
    ///     a   = 2·tau / td
    ///     S   = 1 / (1 − a + (1 + a)·e^(−td/tau))
    ///     IOB(t) = 1 − S·(1 − a)·[ (t²/(tau·td·(1 − a)) − t/tau − 1)·e^(−t/tau) + 1 ]
    ///
    /// For the rapid-acting preset: tau = 101.785714, a = 0.565476,
    /// S = 2.082955.
    public func remainingFraction(after minutes: Double) -> Double {
        guard minutes.isFinite else { return 0 }
        if minutes <= 0 { return 1 }
        if minutes >= durationMinutes { return 0 }
        let tp = peakMinutes
        let td = durationMinutes
        let tau = tp * (1 - tp / td) / (1 - 2 * tp / td)
        let a = 2 * tau / td
        let s = 1 / (1 - a + (1 + a) * exp(-td / tau))
        let t = minutes
        let bracket = (t * t / (tau * td * (1 - a)) - t / tau - 1) * exp(-t / tau) + 1
        return 1 - s * (1 - a) * bracket
    }
}

/// One prior bolus, expressed relative to the instant the suggestion is being
/// computed for. `minutesBefore` is positive into the past.
public struct BolusHistoryEntry: Sendable, Equatable {
    public let minutesBefore: Double
    public let units: Double

    public init(minutesBefore: Double, units: Double) {
        self.minutesBefore = minutesBefore
        self.units = units
    }
}

/// Σ units · remainingFraction(elapsed) over prior boluses (Req 4.1–4.4),
/// matching medreg's `history.py::bolus_iob` exactly — bolus doses only
/// (basal is the caller's job to exclude), a dose counted only while
/// `0 ≤ elapsed < duration`. Empty history is not an error: it yields 0 and
/// the caller proceeds.
public func insulinOnBoard(
    _ boluses: [BolusHistoryEntry],
    model: InsulinActivityModel = .rapidActing
) -> Double {
    boluses.reduce(0.0) { total, entry in
        guard entry.minutesBefore >= 0, entry.minutesBefore < model.durationMinutes else {
            return total
        }
        return total + entry.units * model.remainingFraction(after: entry.minutesBefore)
    }
}

// Insulin-on-board: medreg's curve, transcribed (specs/data/insulin-dosing
// Req 4).
//
// Ported term for term from `~/repos/medreg/src/medreg/models/insulin.py`
// (`ExponentialInsulinModel`, the oref0 / LoopKit exponential-activity model)
// and `~/repos/medreg/src/medreg/suggest/history.py` (`bolus_iob`). Only the
// `iob` branch is ported; nothing in the app consumes an action rate, so the
// `activity` branch is deliberately absent.
//
// Req 4.6 makes the fixture table in design.md a cross-repository contract:
// this implementation and medreg's must agree to within 0.01 U, and
// `DosingTests` asserts the same eight elapsed times to 1e-4.
import Foundation

/// A two-parameter insulin curve. `peakMinutes` must be strictly less than
/// half `durationMinutes` for `tau` to be well defined, which medreg enforces
/// in `InsulinModelParams.__post_init__`; the only preset used here satisfies
/// it comfortably.
public struct InsulinActivityModel: Sendable, Equatable {

    public let peakMinutes: Double
    public let durationMinutes: Double

    /// medreg's `RAPID_ACTING` preset — lispro / aspart / glulisine, peak 75
    /// minutes, duration of action 360 minutes (Req 4.1).
    public static let rapidActing = InsulinActivityModel(peakMinutes: 75, durationMinutes: 360)

    public init(peakMinutes: Double, durationMinutes: Double) {
        self.peakMinutes = peakMinutes
        self.durationMinutes = durationMinutes
    }

    // tau = tp · (1 − tp/td) / (1 − 2·tp/td)
    // For the rapid-acting preset: 101.785714.
    private var tau: Double {
        let tp = peakMinutes
        let td = durationMinutes
        return tp * (1.0 - tp / td) / (1.0 - 2.0 * tp / td)
    }

    // a = 2·tau / td. For the rapid-acting preset: 0.565476.
    private var a: Double { 2.0 * tau / durationMinutes }

    // S = 1 / (1 − a + (1 + a)·e^(−td/tau)). For the preset: 2.082955.
    private var s: Double {
        let td = durationMinutes
        return 1.0 / (1.0 - a + (1.0 + a) * exp(-td / tau))
    }

    /// Fraction of one unit still on board `minutes` after delivery.
    ///
    /// 1.0 at or before delivery and 0.0 at or beyond the duration of action,
    /// so a dose older than the duration contributes nothing (Req 4.3).
    public func remainingFraction(after minutes: Double) -> Double {
        guard minutes > 0 else { return 1.0 }
        guard minutes < durationMinutes else { return 0.0 }

        let td = durationMinutes
        let tau = self.tau
        let a = self.a
        let inner =
            (minutes * minutes / (tau * td * (1.0 - a)) - minutes / tau - 1.0)
            * exp(-minutes / tau) + 1.0
        return 1.0 - s * (1.0 - a) * inner
    }
}

/// One prior bolus, expressed relative to the instant insulin-on-board is
/// wanted at. Basal doses are never represented here: the caller filters them
/// out before building the array, exactly as `bolus_iob` skips any dose whose
/// kind is not `BOLUS` (Req 4.2).
public struct BolusHistoryEntry: Sendable, Equatable {

    /// Positive means in the past. A negative value describes a dose in the
    /// future of the reference instant and contributes nothing.
    public let minutesBefore: Double
    public let units: Double

    public init(minutesBefore: Double, units: Double) {
        self.minutesBefore = minutesBefore
        self.units = units
    }
}

/// Σ units · remainingFraction(elapsed) over prior boluses (Req 4.1–4.4).
///
/// Counts a dose only while `0 ≤ elapsed < duration`, which is `bolus_iob`'s
/// own guard. An empty history is not an error: it yields 0 and the caller
/// proceeds normally (Req 4.4).
public func insulinOnBoard(
    _ boluses: [BolusHistoryEntry],
    model: InsulinActivityModel = .rapidActing
) -> Double {
    var total = 0.0
    for bolus in boluses {
        let elapsed = bolus.minutesBefore
        guard elapsed >= 0, elapsed < model.durationMinutes else { continue }
        total += bolus.units * model.remainingFraction(after: elapsed)
    }
    return total
}

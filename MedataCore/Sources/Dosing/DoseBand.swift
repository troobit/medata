// Time-of-day bands at medreg's boundary hours, decided by the device's own
// wall clock (specs/data/insulin-dosing Req 2, Decision 4).
import Foundation

/// The four bands, at exactly medreg's `TimeOfDaySegment` boundaries
/// (OVERNIGHT 0–6, BREAKFAST 6–11, LUNCH 11–16, DINNER 16–24), so a value
/// fitted there transcribes into this table with no conversion of unit or of
/// meaning (Req 2.6, 9.5). The one difference is which clock decides: medreg
/// segments in UTC, this segments in local time, which is what "my morning"
/// means (Req 2.2).
public enum DoseBand: String, Sendable, Equatable, Hashable, CaseIterable {
    case overnight
    case breakfast
    case lunch
    case dinner

    /// Half-open local-hour ranges. The boundary hour opens the band it starts:
    /// 06:00 is breakfast, 11:00 is lunch, 16:00 is dinner, 00:00 is overnight
    /// (Req 2.3). Contiguous, non-overlapping, covering all 24 hours (Req 2.1).
    public var localHours: Range<Int> {
        switch self {
        case .overnight: return 0..<6
        case .breakfast: return 6..<11
        case .lunch: return 11..<16
        case .dinner: return 16..<24
        }
    }

    /// The band containing a local wall-clock hour.
    public static func band(forLocalHour hour: Int) -> DoseBand {
        for candidate in DoseBand.allCases where candidate.localHours.contains(hour) {
            return candidate
        }
        // Unreachable for a Calendar hour component, which is 0...23; the
        // bands cover that range exactly.
        return .overnight
    }

    /// The calendar — and therefore the time zone — is injected, never reached
    /// for (Req 2.2, 10.2). Call sites pass `.current`.
    public static func band(at instant: Date, calendar: Calendar) -> DoseBand {
        band(forLocalHour: calendar.component(.hour, from: instant))
    }

    /// Band plus the three clock quantities the ledger records, all derived
    /// from the same instant (Req 2.5).
    public static func reading(at instant: Date, calendar: Calendar) -> BandReading {
        BandReading(instant: instant, calendar: calendar)
    }
}

/// The band and the clock facts behind it. `localHour` and `utcHour` come from
/// the same instant read through two calendars, so any disagreement between
/// local-clock and UTC-clock banding is a measurable quantity off-device rather
/// than a silent discrepancy (Req 2.5).
public struct BandReading: Sendable, Equatable {

    public let band: DoseBand
    public let localHour: Int
    public let utcHour: Int
    public let utcOffsetSeconds: Int

    /// Daylight-saving transitions need no special handling:
    /// `Calendar.component(.hour:)` already returns the wall-clock hour that
    /// was displayed at that instant.
    public init(instant: Date, calendar: Calendar) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!

        self.localHour = calendar.component(.hour, from: instant)
        self.utcHour = utc.component(.hour, from: instant)
        self.utcOffsetSeconds = calendar.timeZone.secondsFromGMT(for: instant)
        self.band = DoseBand.band(forLocalHour: localHour)
    }

    public init(band: DoseBand, localHour: Int, utcHour: Int, utcOffsetSeconds: Int) {
        self.band = band
        self.localHour = localHour
        self.utcHour = utcHour
        self.utcOffsetSeconds = utcOffsetSeconds
    }
}

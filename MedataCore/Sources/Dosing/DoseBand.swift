import Foundation

// Time bands (specs/data/insulin-dosing Req 2). The hours are exactly
// medreg's `TimeOfDaySegment` boundaries — OVERNIGHT 0–6, BREAKFAST 6–11,
// LUNCH 11–16, DINNER 16–24 — so a value fitted for medreg's BREAKFAST
// transcribes into this table's `breakfast` field with no conversion of unit
// or of meaning (Req 9.5). The only difference is which clock decides which
// meals were breakfasts, and that difference is what the recorded
// `utc_hour` / `utc_offset_s` pair measures (Req 2.5).
public enum DoseBand: String, Sendable, Equatable, CaseIterable {
    case overnight, breakfast, lunch, dinner

    // Half-open local-hour ranges; the boundary hour opens the band it starts
    // (Req 2.3).
    public var localHours: Range<Int> {
        switch self {
        case .overnight: 0..<6
        case .breakfast: 6..<11
        case .lunch: 11..<16
        case .dinner: 16..<24
        }
    }

    // The calendar (and therefore the time zone) is injected, never reached
    // for (Req 2.2, 10.2). Daylight-saving transitions need no special
    // handling: `Calendar.component(.hour:)` already returns the wall-clock
    // hour that was displayed at that instant, which is exactly what "my
    // morning" means.
    public static func band(at instant: Date, calendar: Calendar) -> DoseBand {
        let hour = calendar.component(.hour, from: instant)
        return allCases.first { $0.localHours.contains(hour) } ?? .dinner
    }
}

// The local/UTC hour pair recorded on every ledger row (Req 2.5), so medreg
// can re-derive either banding from the same data and the size of the
// disagreement becomes measurable.
public struct BandClock: Sendable, Equatable {
    public let localHour: Int
    public let utcHour: Int
    public let utcOffsetSeconds: Int

    public init(instant: Date, calendar: Calendar) {
        localHour = calendar.component(.hour, from: instant)
        utcOffsetSeconds = calendar.timeZone.secondsFromGMT(for: instant)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
        utcHour = utc.component(.hour, from: instant)
    }
}

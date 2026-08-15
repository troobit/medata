import Foundation

/// The four time bands a carbohydrate ratio is configured against
/// (specs/data/insulin-dosing Req 2). The hours are exactly medreg's
/// `TimeOfDaySegment` boundaries, so a value fitted for medreg's `BREAKFAST`
/// transcribes into this table's `breakfast` field with no conversion of unit
/// or of meaning (Req 9.5).
public enum DoseBand: String, Sendable, Equatable, Hashable, CaseIterable {
    case overnight, breakfast, lunch, dinner

    /// Half-open local-hour ranges; the boundary hour opens the band it
    /// starts (Req 2.3).
    public var localHours: Range<Int> {
        switch self {
        case .overnight: 0..<6
        case .breakfast: 6..<11
        case .lunch: 11..<16
        case .dinner: 16..<24
        }
    }

    /// Calendar (and therefore time zone) is injected, never reached for
    /// (Req 2.2, 10.2). Daylight-saving transitions need no special handling:
    /// `Calendar.component(.hour:)` already returns the wall-clock hour that
    /// was displayed at that instant, which is exactly what "my morning" means.
    public static func band(at instant: Date, calendar: Calendar) -> DoseBand {
        let hour = calendar.component(.hour, from: instant)
        return DoseBand.allCases.first { $0.localHours.contains(hour) } ?? .dinner
    }
}

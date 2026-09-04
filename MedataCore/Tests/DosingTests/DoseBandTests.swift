import Foundation
import Testing

@testable import Dosing

// Band selection on the device's own wall clock (specs/data/insulin-dosing
// Req 2.1, 2.3, 2.5, Decision 4). Every instant here is built from an explicit
// calendar, because the whole point of Req 10.2 is that nothing reaches for
// `.current` on its own.
@Suite("DoseBand")
struct DoseBandTests {

    private func calendar(_ zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func instant(
        _ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    // MARK: - Boundaries (Req 2.1, 2.3)

    // The boundary hour opens the band it starts, and the four bands cover all
    // 24 hours without overlapping.
    @Test(
        "Band boundaries",
        arguments: [
            (0, 0, DoseBand.overnight),
            (5, 59, DoseBand.overnight),
            (6, 0, DoseBand.breakfast),
            (10, 59, DoseBand.breakfast),
            (11, 0, DoseBand.lunch),
            (15, 59, DoseBand.lunch),
            (16, 0, DoseBand.dinner),
            (23, 59, DoseBand.dinner)
        ])
    func boundaryHours(hour: Int, minute: Int, expected: DoseBand) {
        let calendar = utc
        let meal = instant(calendar, 2026, 8, 14, hour, minute)
        #expect(DoseBand.band(at: meal, calendar: calendar) == expected)
    }

    @Test("The four bands are contiguous, non-overlapping and cover all 24 hours")
    func bandsPartitionTheDay() {
        var covered: [Int: DoseBand] = [:]
        for band in DoseBand.allCases {
            for hour in band.localHours {
                #expect(covered[hour] == nil)
                covered[hour] = band
            }
        }
        #expect(covered.count == 24)
        #expect(Set(covered.keys) == Set(0..<24))
    }

    // MARK: - A daylight-saving transition day (Req 2.2)

    // 29 March 2026: London moves 01:00 GMT to 02:00 BST. The wall-clock hour
    // that was actually displayed is what decides the band.
    @Test("The hour displayed before the spring transition bands on that hour")
    func beforeSpringTransition() {
        let london = calendar("Europe/London")
        let meal = instant(utc, 2026, 3, 29, 0, 30)

        #expect(DoseBand.localHour(at: meal, calendar: london) == 0)
        #expect(DoseBand.band(at: meal, calendar: london) == .overnight)
    }

    @Test("The hour displayed after the spring transition bands on that hour")
    func afterSpringTransition() {
        let london = calendar("Europe/London")
        // 01:30 UTC is 02:30 BST: the clock jumped, and 02 is the hour that
        // was displayed.
        let meal = instant(utc, 2026, 3, 29, 1, 30)

        #expect(DoseBand.localHour(at: meal, calendar: london) == 2)
        #expect(DoseBand.band(at: meal, calendar: london) == .overnight)
    }

    // MARK: - Local time decides, not UTC (Req 2.2)

    @Test("An hour that bands differently in local and UTC time bands locally")
    func localAndUTCDisagree() {
        let london = calendar("Europe/London")
        // 05:30 UTC is 06:30 BST — breakfast on the developer's clock, and
        // still an overnight hour on medreg's. The band follows the local
        // clock, which is what "my morning" means.
        let meal = instant(utc, 2026, 3, 29, 5, 30)

        #expect(DoseBand.localHour(at: meal, calendar: london) == 6)
        #expect(DoseBand.band(at: meal, calendar: london) == .breakfast)
        #expect(DoseBand.band(at: meal, calendar: utc) == .overnight)
    }

    @Test("A far-from-UTC zone bands on its own wall clock")
    func nonUTCZone() {
        let sydney = calendar("Australia/Sydney")
        // 21:30 UTC on 15 January is 08:30 the next morning in Sydney (+11):
        // breakfast there, dinner on the UTC clock.
        let meal = instant(utc, 2026, 1, 15, 21, 30)

        #expect(DoseBand.localHour(at: meal, calendar: sydney) == 8)
        #expect(DoseBand.band(at: meal, calendar: sydney) == .breakfast)

        #expect(DoseBand.localHour(at: meal, calendar: utc) == 21)
        #expect(DoseBand.band(at: meal, calendar: utc) == .dinner)
    }
}

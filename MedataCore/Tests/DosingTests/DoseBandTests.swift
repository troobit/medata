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
        let reading = DoseBand.reading(at: meal, calendar: london)

        #expect(reading.localHour == 0)
        #expect(reading.utcHour == 0)
        #expect(reading.utcOffsetSeconds == 0)
        #expect(reading.band == .overnight)
    }

    @Test("The hour displayed after the spring transition bands on that hour")
    func afterSpringTransition() {
        let london = calendar("Europe/London")
        let meal = instant(utc, 2026, 3, 29, 1, 30)
        let reading = DoseBand.reading(at: meal, calendar: london)

        #expect(reading.localHour == 2)
        #expect(reading.utcHour == 1)
        #expect(reading.utcOffsetSeconds == 3600)
        #expect(reading.band == .overnight)
    }

    @Test("An hour that bands differently in local and UTC time records both")
    func localAndUTCDisagree() {
        let london = calendar("Europe/London")
        // 05:30 UTC is 06:30 BST — breakfast on the developer's clock, and
        // still an overnight hour on medreg's. The disagreement is exactly
        // what the recorded hour pair measures (Req 2.5).
        let meal = instant(utc, 2026, 3, 29, 5, 30)
        let reading = DoseBand.reading(at: meal, calendar: london)

        #expect(reading.localHour == 6)
        #expect(reading.utcHour == 5)
        #expect(reading.band == .breakfast)
        #expect(DoseBand.band(forLocalHour: reading.utcHour) == .overnight)
    }

    // MARK: - A non-UTC zone (Req 2.5)

    @Test("A far-from-UTC zone records differing hours and a matching offset")
    func nonUTCZone() {
        let sydney = calendar("Australia/Sydney")
        // 21:30 UTC on 15 January is 08:30 the next morning in Sydney (+11).
        let meal = instant(utc, 2026, 1, 15, 21, 30)
        let reading = DoseBand.reading(at: meal, calendar: sydney)

        #expect(reading.localHour == 8)
        #expect(reading.utcHour == 21)
        #expect(reading.localHour != reading.utcHour)
        #expect(reading.utcOffsetSeconds == 11 * 3600)
        #expect(reading.band == .breakfast)

        // The offset is the one that reconciles the two hours.
        let shifted = (reading.utcHour + reading.utcOffsetSeconds / 3600) % 24
        #expect(shifted == reading.localHour)
    }
}

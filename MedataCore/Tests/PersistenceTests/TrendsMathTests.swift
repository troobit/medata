import Foundation
import Testing
@testable import Persistence

// Pure-maths tests for the Trends surface (UI Design Handoff 00, Reqs 10.2/10.3/
// 10.5). TrendsMath lives in the Persistence module so the existing MedataCore
// suite covers it and the App can import it alongside the store.
@Suite("TrendsMath")
struct TrendsMathTests {

    // Fixed UTC gregorian calendar so bucket boundaries are deterministic.
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")!
        return f.date(from: iso)!
    }

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Time in range (Req 10.5)

    @Test("Both readings inside the band give full time in range")
    func tirFullyInRange() {
        let readings = [
            GlucoseReading(timestamp: base, mmolL: 5.0),
            GlucoseReading(timestamp: base.addingTimeInterval(1800), mmolL: 6.0)
        ]
        let tir = TrendsMath.timeInRange(readings)
        #expect(tir != nil)
        #expect(abs(tir! - 1.0) < 1e-9)
    }

    @Test("Exact crossing into the band is interpolated, not all-or-nothing")
    func tirCrossingInterpolated() {
        // 3.0 -> 5.0 over 20 minutes. Crosses 3.9 at fraction 0.45,
        // so 55% of the interval sits in [3.9, 10.0].
        let readings = [
            GlucoseReading(timestamp: base, mmolL: 3.0),
            GlucoseReading(timestamp: base.addingTimeInterval(1200), mmolL: 5.0)
        ]
        let tir = TrendsMath.timeInRange(readings)
        #expect(tir != nil)
        #expect(abs(tir! - 0.55) < 1e-9)
    }

    @Test("Crossing out of the top of the band is interpolated")
    func tirCrossingHigh() {
        // 8.0 -> 12.0 over 10 minutes. Crosses 10.0 at fraction 0.5,
        // so 50% sits in range.
        let readings = [
            GlucoseReading(timestamp: base, mmolL: 8.0),
            GlucoseReading(timestamp: base.addingTimeInterval(600), mmolL: 12.0)
        ]
        let tir = TrendsMath.timeInRange(readings)
        #expect(tir != nil)
        #expect(abs(tir! - 0.5) < 1e-9)
    }

    @Test("Gaps longer than 60 minutes are excluded from numerator and denominator")
    func tirExcludesLongGaps() {
        // A->B: 30 min fully in range (numerator + denominator).
        // B->C: 90 min gap, excluded entirely.
        // C->D: 30 min fully out of range (denominator only).
        // Expected TIR = 30 / 60 = 0.5.
        let a = base
        let b = base.addingTimeInterval(30 * 60)
        let c = b.addingTimeInterval(90 * 60)
        let d = c.addingTimeInterval(30 * 60)
        let readings = [
            GlucoseReading(timestamp: a, mmolL: 6.0),
            GlucoseReading(timestamp: b, mmolL: 6.0),
            GlucoseReading(timestamp: c, mmolL: 15.0),
            GlucoseReading(timestamp: d, mmolL: 15.0)
        ]
        let tir = TrendsMath.timeInRange(readings)
        #expect(tir != nil)
        #expect(abs(tir! - 0.5) < 1e-9)
    }

    @Test("Nil when nothing qualifies (single reading)")
    func tirNilSingleReading() {
        let readings = [GlucoseReading(timestamp: base, mmolL: 5.0)]
        #expect(TrendsMath.timeInRange(readings) == nil)
    }

    @Test("Nil when every interval is a long gap")
    func tirNilAllGaps() {
        let readings = [
            GlucoseReading(timestamp: base, mmolL: 5.0),
            GlucoseReading(timestamp: base.addingTimeInterval(2 * 3600), mmolL: 6.0)
        ]
        #expect(TrendsMath.timeInRange(readings) == nil)
    }

    // MARK: - Bucketing (Req 10.3)

    @Test("Day range interval spans exactly one calendar day")
    func rangeIntervalDay() {
        let cal = utcCalendar
        let d = date("2024-03-15T13:45:00Z")
        let interval = TrendsMath.rangeInterval(for: .day, containing: d, calendar: cal)
        #expect(interval.start == date("2024-03-15T00:00:00Z"))
        #expect(interval.duration == 24 * 3600)
    }

    @Test("Month range interval spans the calendar month")
    func rangeIntervalMonth() {
        let cal = utcCalendar
        let d = date("2024-03-15T13:45:00Z")
        let interval = TrendsMath.rangeInterval(for: .month, containing: d, calendar: cal)
        #expect(interval.start == date("2024-03-01T00:00:00Z"))
        #expect(interval.end == date("2024-04-01T00:00:00Z"))
    }

    @Test("Daily buckets cover every day in the interval with per-day totals and averages")
    func dailyBucketsAggregate() {
        let cal = utcCalendar
        let interval = DateInterval(
            start: date("2024-03-11T00:00:00Z"),
            end: date("2024-03-18T00:00:00Z")
        )
        let samples = [
            DatedValue(date: date("2024-03-11T08:00:00Z"), value: 20),
            DatedValue(date: date("2024-03-11T12:00:00Z"), value: 40),
            DatedValue(date: date("2024-03-13T09:00:00Z"), value: 10)
        ]
        let buckets = TrendsMath.dailyBuckets(samples, in: interval, calendar: cal)
        #expect(buckets.count == 7)
        // Day 0 (11th): two samples, total 60, average 30.
        #expect(buckets[0].start == date("2024-03-11T00:00:00Z"))
        #expect(abs(buckets[0].total - 60) < 1e-9)
        #expect(buckets[0].average != nil && abs(buckets[0].average! - 30) < 1e-9)
        #expect(buckets[0].count == 2)
        // Day 1 (12th): empty.
        #expect(abs(buckets[1].total - 0) < 1e-9)
        #expect(buckets[1].average == nil)
        #expect(buckets[1].count == 0)
        // Day 2 (13th): single sample.
        #expect(abs(buckets[2].total - 10) < 1e-9)
        #expect(buckets[2].average != nil && abs(buckets[2].average! - 10) < 1e-9)
    }

    // MARK: - Carb axis mapping (Req 10.2)

    @Test("Dynamic carb axis max floors at 80 and rounds up to the next 20")
    func carbAxisMaxDynamic() {
        #expect(TrendsMath.carbAxisMax(forMaxCarbs: 0) == 80)
        #expect(TrendsMath.carbAxisMax(forMaxCarbs: 55) == 80)
        #expect(TrendsMath.carbAxisMax(forMaxCarbs: 80) == 80)
        #expect(TrendsMath.carbAxisMax(forMaxCarbs: 81) == 100)
        #expect(TrendsMath.carbAxisMax(forMaxCarbs: 100) == 100)
        #expect(TrendsMath.carbAxisMax(forMaxCarbs: 145) == 160)
    }

    @Test("Carb-to-axis mapping round-trips exactly")
    func carbAxisRoundTrip() {
        let carbMax = TrendsMath.carbAxisMax(forMaxCarbs: 145) // 160
        let glucoseAxisMax = 14.0
        for carbs in [0.0, 12.5, 60.0, 160.0] {
            let axis = TrendsMath.mapCarbsToAxis(carbs, carbAxisMax: carbMax, glucoseAxisMax: glucoseAxisMax)
            let back = TrendsMath.mapAxisToCarbs(axis, carbAxisMax: carbMax, glucoseAxisMax: glucoseAxisMax)
            #expect(abs(back - carbs) < 1e-9)
        }
        // Full-scale carb value maps to the top of the glucose axis.
        let top = TrendsMath.mapCarbsToAxis(carbMax, carbAxisMax: carbMax, glucoseAxisMax: glucoseAxisMax)
        #expect(abs(top - glucoseAxisMax) < 1e-9)
    }
}

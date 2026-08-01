import Foundation
import Testing
import GlucoseWidgetShared
@testable import Persistence

// Trend derivation and band classification for the Lock Screen widget
// (specs/ui/glucose-lock-widget Reqs 3.1–3.5, 4.1; Decision 4).
@Suite("TrendsMath glucose trend")
struct TrendsMathGlucoseTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // Two readings `span` apart ending at `now`, rising at `rate` mmol/L per
    // minute. With exactly two points the least-squares slope IS the secant
    // slope, so the rate is what the caller asked for.
    private func readings(
        rate: Double, span: TimeInterval = 600, endingAt end: Date, from start: Double = 6.0
    ) -> [GlucoseReading] {
        [
            GlucoseReading(timestamp: end.addingTimeInterval(-span), mmolL: start),
            GlucoseReading(timestamp: end, mmolL: start + rate * span / 60)
        ]
    }

    // MARK: - Rate (Req 3.1)

    @Test("Two readings ten minutes apart give the secant slope")
    func rateFromTwoReadings() {
        let rate = TrendsMath.glucoseRate(readings(rate: 0.08, endingAt: now), now: now)
        #expect(rate != nil)
        #expect(abs(rate! - 0.08) < 1e-9)
    }

    @Test("A falling series gives a negative rate")
    func rateIsSignedByDirection() {
        let rate = TrendsMath.glucoseRate(readings(rate: -0.12, endingAt: now), now: now)
        #expect(rate != nil)
        #expect(abs(rate! + 0.12) < 1e-9)
    }

    @Test("Collinear readings regress to the exact slope")
    func rateRegressesOverManyPoints() {
        // Five points on a straight line across the full window.
        let series = (0...4).map { step in
            GlucoseReading(
                timestamp: now.addingTimeInterval(-900 + Double(step) * 225),
                mmolL: 5.0 + Double(step) * 0.5625)   // 0.15 mmol/L per minute
        }
        let rate = TrendsMath.glucoseRate(series, now: now)
        #expect(rate != nil)
        #expect(abs(rate! - 0.15) < 1e-9)
    }

    @Test("Unordered input gives the same rate as sorted input")
    func rateIgnoresInputOrder() {
        let series = readings(rate: 0.09, endingAt: now)
        let forward = TrendsMath.glucoseRate(series, now: now)
        let reversed = TrendsMath.glucoseRate(series.reversed(), now: now)
        #expect(forward == reversed)
    }

    // MARK: - Rate guards (Reqs 3.3, 3.4)

    @Test("Fewer than two in-window readings gives no rate")
    func rateNeedsTwoReadings() {
        #expect(TrendsMath.glucoseRate([], now: now) == nil)
        #expect(TrendsMath.glucoseRate(
            [GlucoseReading(timestamp: now, mmolL: 6.0)], now: now) == nil)
    }

    @Test("A span shorter than ten minutes gives no rate")
    func rateNeedsTenMinuteSpan() {
        // Nine minutes apart: two near-simultaneous readings must not amplify
        // into a spurious fast arrow.
        #expect(TrendsMath.glucoseRate(
            readings(rate: 0.2, span: 540, endingAt: now), now: now) == nil)
    }

    @Test("A ten-minute span is exactly enough")
    func tenMinuteSpanQualifies() {
        #expect(TrendsMath.glucoseRate(readings(rate: 0.2, span: 600, endingAt: now), now: now) != nil)
    }

    @Test("A latest reading older than fifteen minutes gives no rate")
    func rateNeedsARecentReading() {
        // The whole series sits before the window, so nothing is in scope.
        let stale = readings(rate: 0.1, endingAt: now.addingTimeInterval(-16 * 60))
        #expect(TrendsMath.glucoseRate(stale, now: now) == nil)
    }

    @Test("Readings outside the window are excluded from the fit")
    func rateExcludesOutOfWindowReadings() {
        // A far-out outlier would wreck the slope if it were included.
        let series = readings(rate: 0.08, endingAt: now) + [
            GlucoseReading(timestamp: now.addingTimeInterval(-3600), mmolL: 25.0)
        ]
        let rate = TrendsMath.glucoseRate(series, now: now)
        #expect(rate != nil)
        #expect(abs(rate! - 0.08) < 1e-9)
    }

    @Test("The window is closed at both bounds")
    func windowBoundsAreInclusive() {
        // Earliest exactly at now − 15m, latest exactly at now.
        let series = [
            GlucoseReading(timestamp: now.addingTimeInterval(-900), mmolL: 5.0),
            GlucoseReading(timestamp: now, mmolL: 6.0)
        ]
        #expect(TrendsMath.glucoseRate(series, now: now) != nil)
        // One second earlier and the older reading falls out, leaving one.
        let series2 = [
            GlucoseReading(timestamp: now.addingTimeInterval(-901), mmolL: 5.0),
            GlucoseReading(timestamp: now, mmolL: 6.0)
        ]
        #expect(TrendsMath.glucoseRate(series2, now: now) == nil)
    }

    @Test("A future reading is outside the window")
    func futureReadingsAreExcluded() {
        let series = [
            GlucoseReading(timestamp: now.addingTimeInterval(-600), mmolL: 5.0),
            GlucoseReading(timestamp: now.addingTimeInterval(60), mmolL: 6.0)
        ]
        // Only the older reading is in the closed window, so no rate.
        #expect(TrendsMath.glucoseRate(series, now: now) == nil)
    }

    // MARK: - Threshold map (Req 3.2, Decision 4)

    // Half-open bands on |r|: <0.056 steady, 0.056–0.111 slow, 0.111–0.166
    // medium, ≥0.166 fast. Exercised on the rate directly so the boundaries are
    // exact and no floating-point reconstruction sits in between.
    @Test(
        "Each band boundary belongs to the faster state",
        arguments: [
            (0.0, GlucoseTrend.steady),
            (0.0559, .steady),
            (0.056, .risingSlow),
            (0.1109, .risingSlow),
            (0.111, .rising),
            (0.1659, .rising),
            (0.166, .risingFast),
            (2.0, .risingFast)
        ] as [(Double, GlucoseTrend)])
    func risingBands(_ rate: Double, _ expected: GlucoseTrend) {
        #expect(TrendsMath.trend(forRate: rate) == expected)
    }

    @Test(
        "Negative rates mirror the rising bands",
        arguments: [
            (-0.0559, GlucoseTrend.steady),
            (-0.056, .fallingSlow),
            (-0.111, .falling),
            (-0.166, .fallingFast)
        ] as [(Double, GlucoseTrend)])
    func fallingBands(_ rate: Double, _ expected: GlucoseTrend) {
        #expect(TrendsMath.trend(forRate: rate) == expected)
    }

    // MARK: - Trend from readings (Reqs 3.3, 3.4)

    @Test("A qualifying series yields the mapped trend")
    func trendFromReadings() {
        #expect(TrendsMath.trend(readings(rate: 0.2, endingAt: now), now: now) == .risingFast)
        #expect(TrendsMath.trend(readings(rate: -0.07, endingAt: now), now: now) == .fallingSlow)
        #expect(TrendsMath.trend(readings(rate: 0.0, endingAt: now), now: now) == .steady)
    }

    @Test("No rate means no trend")
    func trendIsNilWithoutARate() {
        #expect(TrendsMath.trend([], now: now) == nil)
        #expect(TrendsMath.trend(readings(rate: 0.2, span: 540, endingAt: now), now: now) == nil)
        #expect(TrendsMath.trend(
            readings(rate: 0.2, endingAt: now.addingTimeInterval(-16 * 60)), now: now) == nil)
    }

    // MARK: - Band status (Req 4.1)

    @Test(
        "The target band is inclusive at 3.9 and 10.0",
        arguments: [
            (3.89, GlucoseBandStatus.low),
            (3.9, .inRange),
            (7.0, .inRange),
            (10.0, .inRange),
            (10.01, .high)
        ] as [(Double, GlucoseBandStatus)])
    func bandStatusBoundaries(_ mmolL: Double, _ expected: GlucoseBandStatus) {
        #expect(TrendsMath.bandStatus(mmolL) == expected)
    }

    @Test("Band status reads the existing target constants")
    func bandStatusReusesTargets() {
        #expect(TrendsMath.bandStatus(TrendsMath.targetLowMmolL) == .inRange)
        #expect(TrendsMath.bandStatus(TrendsMath.targetHighMmolL) == .inRange)
    }
}

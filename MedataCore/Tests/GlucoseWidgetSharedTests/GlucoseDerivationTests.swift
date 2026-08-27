import Foundation
import Testing

@testable import GlucoseWidgetShared

// Precedence and the single-provenance trend (specs/data/fingerprick-glucose
// Reqs 3.1, 3.3, 3.4, 3.5, 3.9, 5.1, 5.2; Decisions 7 and 8).
//
// Everything here is a pure function over readings, which is the whole point of
// putting it in `GlucoseDerivation`: the home header and the widget resolve
// "the current value" through the same code, so they cannot disagree.
@Suite("GlucoseDerivation")
struct GlucoseDerivationTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)
    private let holdWindow: TimeInterval = 15 * 60

    private func minutesAgo(_ minutes: Double) -> Date {
        now.addingTimeInterval(-minutes * 60)
    }

    private func sensor(_ minutes: Double, _ mmolL: Double) -> GlucoseReading {
        GlucoseReading(timestamp: minutesAgo(minutes), mmolL: mmolL, provenance: .sensor)
    }

    private func blood(_ minutes: Double, _ mmolL: Double) -> GlucoseReading {
        GlucoseReading(timestamp: minutesAgo(minutes), mmolL: mmolL, provenance: .blood)
    }

    // The store hands readings over in ascending timestamp order; the callers
    // that build them by hand must too.
    private func ascending(_ readings: [GlucoseReading]) -> [GlucoseReading] {
        readings.sorted { $0.timestamp < $1.timestamp }
    }

    // A flat sensor trace across the whole trend window, so any arrow other
    // than steady can only have come from a blood reading leaking into the
    // regression.
    private var flatSensorTrace: [GlucoseReading] {
        stride(from: 30.0, through: 0.0, by: -5.0).map { sensor($0, 6.0) }
    }

    // MARK: - Displayed reading (Reqs 3.1, 3.3, 3.4, 3.9)

    @Test("A blood reading inside the window is displayed over a newer sensor reading")
    func bloodInsideWindowWins() {
        let readings = ascending(flatSensorTrace + [blood(5, 9.0)])
        let snapshot = GlucoseDerivation.snapshot(
            from: readings, now: now, holdWindow: holdWindow)

        #expect(snapshot.mmolL == 9.0)
        #expect(snapshot.readingDate == minutesAgo(5))
        #expect(snapshot.provenance == .blood)
        #expect(snapshot.status == .inRange)
    }

    @Test("A blood reading outside the window loses to the latest reading of any provenance")
    func bloodOutsideWindowLoses() {
        let readings = ascending(flatSensorTrace + [blood(16, 9.0)])
        let snapshot = GlucoseDerivation.snapshot(
            from: readings, now: now, holdWindow: holdWindow)

        #expect(snapshot.mmolL == 6.0)
        #expect(snapshot.readingDate == now)
        #expect(snapshot.provenance == .sensor)
        #expect(snapshot.holdsUntil == nil)
    }

    // The window is open at its far edge: Req 3.3 resumes the sensor reading
    // WHEN the window has elapsed, so a reading exactly `holdWindow` old is
    // already past holding.
    @Test("The hold expires exactly at the window boundary")
    func windowBoundaryIsExclusive() {
        let readings = ascending(flatSensorTrace + [blood(15, 9.0)])
        let snapshot = GlucoseDerivation.snapshot(
            from: readings, now: now, holdWindow: holdWindow)

        #expect(snapshot.provenance == .sensor)
        #expect(snapshot.mmolL == 6.0)
    }

    @Test("The later of two in-window blood readings is displayed")
    func laterBloodReadingWins() {
        let readings = ascending(flatSensorTrace + [blood(10, 8.0), blood(3, 9.5)])
        let snapshot = GlucoseDerivation.snapshot(
            from: readings, now: now, holdWindow: holdWindow)

        #expect(snapshot.mmolL == 9.5)
        #expect(snapshot.readingDate == minutesAgo(3))
        #expect(snapshot.holdsUntil == minutesAgo(3).addingTimeInterval(holdWindow))
    }

    // Req 3.9. A reading back-dated an hour is recorded like any other, and is
    // simply never inside the window — the same comparison the hold uses, not a
    // branch of its own.
    @Test("A reading back-dated beyond the window never becomes the current value")
    func backDatedBloodNeverDisplays() {
        let readings = ascending([sensor(5, 6.0), blood(60, 9.0)])
        let snapshot = GlucoseDerivation.snapshot(
            from: readings, now: now, holdWindow: holdWindow)

        #expect(snapshot.mmolL == 6.0)
        #expect(snapshot.provenance == .sensor)
        #expect(snapshot.holdsUntil == nil)
    }

    // MARK: - holdsUntil (Decision 8)

    @Test("holdsUntil is the blood instant plus the window while a blood reading holds")
    func holdsUntilIsBloodInstantPlusWindow() {
        let readings = ascending(flatSensorTrace + [blood(5, 9.0)])
        let snapshot = GlucoseDerivation.snapshot(
            from: readings, now: now, holdWindow: holdWindow)

        #expect(snapshot.holdsUntil == minutesAgo(5).addingTimeInterval(holdWindow))
    }

    // A blood reading can be the latest reading there is without holding
    // anything: with nothing newer to outrank there is no clobber to prevent.
    @Test("A stale blood reading displayed for want of anything newer carries no hold")
    func staleBloodDisplaysWithoutHolding() {
        let snapshot = GlucoseDerivation.snapshot(
            from: [blood(90, 7.2)], now: now, holdWindow: holdWindow)

        #expect(snapshot.mmolL == 7.2)
        #expect(snapshot.provenance == .blood)
        #expect(snapshot.holdsUntil == nil)
    }

    @Test("A zero hold window disables the blood branch entirely")
    func zeroWindowNeverHolds() {
        let readings = ascending(flatSensorTrace + [blood(1, 9.0)])
        let snapshot = GlucoseDerivation.snapshot(from: readings, now: now, holdWindow: 0)

        #expect(snapshot.mmolL == 6.0)
        #expect(snapshot.provenance == .sensor)
        #expect(snapshot.holdsUntil == nil)
    }

    // MARK: - Trend exclusion (Req 5.1, Decision 7)

    // The defect the exclusion exists to prevent: a fingerstick a whole
    // millimole above a flat sensor trace measures the gap between two
    // modalities, and a mixed regression would report that gap as a rate.
    @Test("A blood reading offset from a flat sensor trace leaves the sensor rate unchanged")
    func bloodDoesNotMoveTheSensorTrend() {
        let sensorOnly = GlucoseDerivation.snapshot(
            from: ascending(flatSensorTrace), now: now, holdWindow: holdWindow)
        let withBlood = GlucoseDerivation.snapshot(
            from: ascending(flatSensorTrace + [blood(5, 9.0)]), now: now,
            holdWindow: holdWindow)

        #expect(sensorOnly.trend == .steady)
        #expect(withBlood.trend == .steady, "the displayed value is blood; the arrow is not")
    }

    // Req 5.1's fallback: fingersticks regressed against fingersticks carry no
    // between-modality step, so the same arithmetic describes a real direction.
    @Test("A blood-only series satisfying the count-and-span rules yields a trend")
    func bloodOnlySeriesYieldsATrend() {
        let readings = ascending([blood(20, 5.0), blood(5, 6.0)])
        let snapshot = GlucoseDerivation.snapshot(
            from: readings, now: now, holdWindow: holdWindow)

        // 1.0 mmol/L over 15 minutes = 0.0667/min, inside the slow-rise band.
        #expect(snapshot.trend == .risingSlow)
    }

    @Test("A blood-only series failing the span rule yields no trend")
    func bloodOnlySeriesTooShortYieldsNoTrend() {
        let readings = ascending([blood(6, 5.0), blood(1, 6.0)])
        let snapshot = GlucoseDerivation.snapshot(
            from: readings, now: now, holdWindow: holdWindow)

        #expect(snapshot.trend == nil)
    }

    @Test("A lone blood reading yields no trend")
    func loneBloodReadingYieldsNoTrend() {
        let snapshot = GlucoseDerivation.snapshot(
            from: [blood(2, 5.0)], now: now, holdWindow: holdWindow)

        #expect(snapshot.trend == nil)
    }

    // Req 5.2 and the never-regress-a-mixed-series rule together: the sensor
    // series is present but short of the count rule, so the blood series takes
    // over — and the answer is the blood-only rate, not the mixed one, which
    // here even points the other way.
    @Test("With the sensor series short of the rules, qualifying blood readings take over")
    func bloodTakesOverWhenTheSensorSeriesDoesNotQualify() {
        let readings = ascending([blood(20, 5.0), blood(5, 6.0), sensor(1, 3.0)])
        let snapshot = GlucoseDerivation.snapshot(
            from: readings, now: now, holdWindow: holdWindow)

        let mixedRate = GlucoseTrendMath.glucoseRate(readings, now: now)
        #expect(mixedRate ?? 0 < 0, "the mixed regression falls; the blood-only one rises")
        #expect(snapshot.trend == .risingSlow)
        // The lone sensor reading is still the latest of any provenance, but
        // the blood reading at 5 minutes is inside the window and outranks it.
        #expect(snapshot.provenance == .blood)
    }

    @Test("Neither provenance qualifying yields no trend rather than a mixed one")
    func neitherProvenanceQualifiesYieldsNoTrend() {
        let readings = ascending([blood(2, 5.0), sensor(1, 9.0)])
        let snapshot = GlucoseDerivation.snapshot(
            from: readings, now: now, holdWindow: holdWindow)

        #expect(snapshot.trend == nil)
    }

    // MARK: - Unchanged behaviour (Req 7.1)

    @Test("Empty input stays never-recorded")
    func emptyInputIsNeverRecorded() {
        #expect(
            GlucoseDerivation.snapshot(from: [], now: now, holdWindow: holdWindow)
                == .neverRecorded)
    }

    @Test("A sensor-only input derives exactly as it does today")
    func sensorOnlyIsUnchanged() {
        let readings = ascending(flatSensorTrace)
        let snapshot = GlucoseDerivation.snapshot(
            from: readings, now: now, holdWindow: holdWindow)

        #expect(snapshot.mmolL == 6.0)
        #expect(snapshot.readingDate == now)
        #expect(snapshot.trend == GlucoseTrendMath.trend(readings, now: now))
        #expect(snapshot.status == GlucoseTrendMath.bandStatus(6.0))
        #expect(snapshot.provenance == .sensor)
        #expect(snapshot.holdsUntil == nil)
    }
}

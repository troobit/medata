import Foundation
import XCTest

@testable import GlucoseGraph

// Unit tests for the pure date/time and sampling layers (Reqs 2.1–2.3, 2.6,
// 3.3–3.5), ported from the reference `test_time.py` / `test_trace.py`
// behaviours that do not need an image.
final class TimeAndSamplingTests: XCTestCase {

    private let dublin = TimeZone(identifier: "Europe/Dublin")!

    // MARK: - GraphDate

    func testGraphDateArithmeticAndWeekday() {
        let date = GraphDate(year: 2026, month: 7, day: 2)
        XCTAssertEqual(date.adding(days: -1), GraphDate(year: 2026, month: 7, day: 1))
        XCTAssertEqual(
            GraphDate(year: 2026, month: 1, day: 1).adding(days: -1),
            GraphDate(year: 2025, month: 12, day: 31))
        // 2026-07-02 is a Thursday (Monday = 0 → 3).
        XCTAssertEqual(date.weekdayMondayZero, 3)
        XCTAssertEqual(date.isoString, "2026-07-02")
    }

    // MARK: - Date establishment (Req 2.1, 2.2, 2.6)

    func testDaily24hUsesPrintedDate() throws {
        let printed = GraphDate(year: 2026, month: 7, day: 2)
        let (date, source, warnings) = try establishDate(
            printed: printed, asset: GraphDate(year: 2026, month: 7, day: 3),
            view: .daily24h)
        XCTAssertEqual(date, printed)
        XCTAssertEqual(source, "ocr")
        XCTAssertTrue(warnings.isEmpty)
    }

    func testDaily24hWithoutPrintedDateRejects() {
        XCTAssertThrowsError(
            try establishDate(
                printed: nil, asset: GraphDate(year: 2026, month: 7, day: 3),
                view: .daily24h)
        ) { error in
            let reject = error as? RejectImage
            XCTAssertTrue(reject?.reason.contains("date") ?? false)
        }
    }

    func testDaily24hAssetBeforePrintedWarns() throws {
        let (_, _, warnings) = try establishDate(
            printed: GraphDate(year: 2026, month: 7, day: 2),
            asset: GraphDate(year: 2026, month: 7, day: 1),
            view: .daily24h)
        XCTAssertEqual(warnings.count, 1)
        XCTAssertTrue(warnings[0].contains("precedes"))
    }

    func testHome8hUsesAssetDate() throws {
        let asset = GraphDate(year: 2026, month: 7, day: 2)
        let (date, source, warnings) = try establishDate(
            printed: nil, asset: asset, view: .home8h)
        XCTAssertEqual(date, asset)
        XCTAssertEqual(source, "asset")
        XCTAssertTrue(warnings.isEmpty)
    }

    func testHome8hWithoutAssetDateRejects() {
        XCTAssertThrowsError(
            try establishDate(printed: nil, asset: nil, view: .home8h)
        ) { error in
            let reject = error as? RejectImage
            XCTAssertTrue(reject?.reason.contains("creation date") ?? false)
        }
    }

    // MARK: - Wall-clock -> UTC (Req 2.3, 3.5)

    func testMidnightCrossingAttribution() {
        let established = GraphDate(year: 2026, month: 7, day: 3)
        // Hour 23.5 on a crossing window = 23:30 on 2 July (Dublin, UTC+1).
        let beforeMidnight = hoursToUtcMs(
            23.5, established: established, crossesMidnight: true, timeZone: dublin)
        // Hour 24 = exactly midnight of the established date.
        let midnight = hoursToUtcMs(
            24, established: established, crossesMidnight: true, timeZone: dublin)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = dublin
        let beforeComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date(timeIntervalSince1970: Double(beforeMidnight) / 1000))
        XCTAssertEqual(beforeComponents.day, 2)
        XCTAssertEqual(beforeComponents.hour, 23)
        XCTAssertEqual(beforeComponents.minute, 30)
        let midnightComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: Date(timeIntervalSince1970: Double(midnight) / 1000))
        XCTAssertEqual(midnightComponents.day, 3)
        XCTAssertEqual(midnightComponents.hour, 0)
    }

    func testNonCrossingWindowStaysOnEstablishedDay() {
        let established = GraphDate(year: 2026, month: 7, day: 2)
        let ms = hoursToUtcMs(
            12, established: established, crossesMidnight: false, timeZone: dublin)
        // 2026-07-02 12:00 Dublin (UTC+1) = 2026-07-02T11:00Z.
        XCTAssertEqual(ms, 1_782_990_000_000)
    }

    func testDstWarningFiresOnTransitionDayOnly() {
        // Europe/Dublin springs forward on 2026-03-29.
        let transition = dstWarnings(
            established: GraphDate(year: 2026, month: 3, day: 29),
            crossesMidnight: false, timeZone: dublin)
        XCTAssertEqual(transition.count, 1)
        XCTAssertTrue(transition[0].contains("DST"))

        let normal = dstWarnings(
            established: GraphDate(year: 2026, month: 7, day: 2),
            crossesMidnight: false, timeZone: dublin)
        XCTAssertTrue(normal.isEmpty)

        // A crossing window covers the preceding day too.
        let crossing = dstWarnings(
            established: GraphDate(year: 2026, month: 3, day: 30),
            crossesMidnight: true, timeZone: dublin)
        XCTAssertEqual(crossing.count, 1)
    }

    // MARK: - Marks (Req 3.4)

    func testDaily24hYields288HalfOpenMarks() {
        let marks = markHours(view: .daily24h)
        XCTAssertEqual(marks.count, 288)
        XCTAssertEqual(marks.first, 0)
        XCTAssertEqual(marks.last!, 23 + 55.0 / 60, accuracy: 1e-9)
    }

    func testHome8hMarksSpanObservedExtent() {
        let marks = markHours(view: .home8h, traceExtent: (first: 18.02, last: 24.51))
        XCTAssertEqual(marks.first!, 18.0 + 5.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(marks.last!, 24.5, accuracy: 1e-9)
    }

    // MARK: - Column runs and sampling (Req 3.2, 3.3)

    func testColumnRunsRejoinAcrossDashGap() {
        // A stroke split by dashed-row removal: gap of `rejoinGap` rows.
        let ys = Array(100...110) + Array(123...130)
        XCTAssertEqual(columnRuns(ys).count, 1)
        // A genuinely disjoint pair stays split.
        let disjoint = Array(100...110) + Array(160...170)
        XCTAssertEqual(columnRuns(disjoint).count, 2)
    }

    func testChooseRunCenterTakesLocalExtremum() {
        let runs = [(start: 100, end: 110), (start: 200, end: 210)]
        // Neighbours below the midpoint -> topmost run (spike apex).
        XCTAssertEqual(chooseRunCentre(runs, neighbourY: 180), 105)
        // Neighbours above the midpoint -> bottommost run (dip).
        XCTAssertEqual(chooseRunCentre(runs, neighbourY: 120), 205)
    }

    func testSampleTraceBridgesShortGapsAndOmitsWideOnes() {
        // Identity-ish fit: 720 px per hour -> 60 px per 5-minute mark.
        let fit = LinearFit(slope: 1.0 / 720, intercept: 0)
        var columns: [Int: Double] = [:]
        // Trace from hour 0 to hour 0.25 (x 0...180), absent for a 10-minute
        // span (x 181...300 minus), then resumes at hour 0.5 (x 360...420).
        for x in 0...180 { columns[x] = 5.0 }
        for x in 360...420 { columns[x] = 7.0 }

        let marks = (0...8).map { Double($0) / 12 }  // 0h .. 40min
        let samples = sampleTrace(columns: columns, occluded: nil, xFit: fit, marks: marks)
        let sampledHours = samples.map(\.hour)

        // Marks at 0, 5, 10, 15 minutes hit trace; 20 min sits in a
        // 15-minute absence (181...359 px = 14.9 min) -> omitted; 25 min
        // (x=300) also inside -> omitted; 30+ hit the resumed trace.
        XCTAssertTrue(sampledHours.contains(0))
        XCTAssertTrue(sampledHours.contains(0.25))
        XCTAssertFalse(sampledHours.contains(4.0 / 12))
        XCTAssertTrue(sampledHours.contains(0.5))
    }

    func testSampleTraceOmitsOccludedMarks() {
        let fit = LinearFit(slope: 1.0 / 720, intercept: 0)
        var columns: [Int: Double] = [:]
        for x in 0...720 { columns[x] = 5.0 }
        for x in 300...420 { columns.removeValue(forKey: x) }

        // Occluded columns cover the absence: the mark inside it is omitted,
        // NOT bridged, even though the absence is short enough to bridge.
        let marks = (0...12).map { Double($0) / 12 }
        let samples = sampleTrace(
            columns: columns, occluded: (lo: 300, hi: 420), xFit: fit, marks: marks)
        let sampledHours = samples.map(\.hour)
        XCTAssertFalse(sampledHours.contains(0.5))  // x=360, under the dot
        XCTAssertTrue(sampledHours.contains(0))
        XCTAssertTrue(sampledHours.contains(1))
    }

    func testValuesRoundToOneDecimalBankers() {
        XCTAssertEqual(pythonRound1(9.44999), 9.4)
        XCTAssertEqual(pythonRound1(9.45001), 9.5)
        // Banker's on exactly-representable halves, matching Python.
        XCTAssertEqual(pythonRound1(0.25), 0.2)
        XCTAssertEqual(pythonRound1(0.75), 0.8)
    }

    // MARK: - View classification without an image (Req 2.5)

    func testNoTimeLabelsRejects() {
        XCTAssertThrowsError(
            try classifyAndCalibrate([], width: 1170, height: 2532, bitmap: nil)
        ) { error in
            let reject = error as? RejectImage
            XCTAssertTrue(reject?.reason.contains("no time axis labels") ?? false)
        }
    }
}

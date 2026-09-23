import Foundation
import LibreLinkUpKit
import XCTest

@testable import GlucoseIngestion

// Adaptive poll interval (cgm-connect Decision 12), DORMANT since Decision 13.
//
// This governs how often the app hits a vendor that has banned accounts for
// polling too fast, so every branch is pinned: the baseline must be the
// baseline whenever glucose is unremarkable, and the tightened rate must never
// go below the 5-minute floor.
//
// Decision 13 made the baseline 5 minutes — the one shared app+widget interval
// — so every branch below now returns the same number. The branch tests are
// kept as the rollback contract: they are what proves the adaptive scheme still
// works if `LibreLinkUpPolling.interval` goes back to 15 minutes. See
// `testAdaptiveMachineryIsDormantAtTheSharedInterval` at the foot of the file.
//
// The motivating case is `lowReadingTightensTheInterval` — on 2026-08-05 the
// Abbott app alarmed on a low while MeData displayed a value measured eight
// minutes earlier, recent enough to render as fresh and above the target low.
final class LibreLinkUpPollIntervalTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // Readings `spacingMin` apart ending at `now`, walking from `start` by
    // `stepPerReading` mmol/L.
    private func samples(
        count: Int, start: Double, stepPerReading: Double, spacingMin: Double = 5
    ) -> [GlucoseSample] {
        (0..<count).map { i in
            GlucoseSample(
                nativeInstant: now.addingTimeInterval(-Double(count - 1 - i) * spacingMin * 60),
                mmolL: start + Double(i) * stepPerReading
            )
        }
    }

    func testNoReadingsKeepsTheBaseline() {
        XCTAssertEqual(
            LibreLinkUpGlucoseSource.nextPollInterval(after: [], now: now),
            LibreLinkUpGlucoseSource.pollInterval)
    }

    func testUnremarkableGlucoseKeepsTheBaseline() {
        // Flat at 7.0 — the common case, and the one that must not spend the
        // rate-limit budget.
        let readings = samples(count: 4, start: 7.0, stepPerReading: 0)
        XCTAssertEqual(
            LibreLinkUpGlucoseSource.nextPollInterval(after: readings, now: now),
            LibreLinkUpGlucoseSource.pollInterval)
    }

    func testLowReadingTightensTheInterval() {
        // 4.2 — exactly the value displayed during the 2026-08-05 alarm. Above
        // the 3.9 target low, so the band status alone would call it in-range;
        // the threshold sits above the band deliberately.
        let readings = samples(count: 2, start: 4.4, stepPerReading: -0.2)
        XCTAssertEqual(
            LibreLinkUpGlucoseSource.nextPollInterval(after: readings, now: now),
            LibreLinkUpGlucoseSource.urgentPollInterval)
    }

    func testThresholdBoundaryBelongsToTheBaseline() {
        // The threshold is strict `<`, so a reading exactly at it is not
        // urgent — one place, one direction, stated.
        let atThreshold = [GlucoseSample(
            nativeInstant: now, mmolL: LibreLinkUpGlucoseSource.urgentThresholdMmolL)]
        XCTAssertEqual(
            LibreLinkUpGlucoseSource.nextPollInterval(after: atThreshold, now: now),
            LibreLinkUpGlucoseSource.pollInterval)

        let justBelow = [GlucoseSample(
            nativeInstant: now,
            mmolL: LibreLinkUpGlucoseSource.urgentThresholdMmolL - 0.1)]
        XCTAssertEqual(
            LibreLinkUpGlucoseSource.nextPollInterval(after: justBelow, now: now),
            LibreLinkUpGlucoseSource.urgentPollInterval)
    }

    func testFastFallTightensEvenFromAComfortableLevel() {
        // 9.0 → 7.2 over 15 minutes = −0.12 mmol/L per minute, past the
        // −0.111 edge. High enough that the level test alone would not fire,
        // which is the point: the baseline interval would show a comfortable
        // number while the real one crossed the band.
        let readings = samples(count: 4, start: 9.0, stepPerReading: -0.6)
        XCTAssertEqual(
            LibreLinkUpGlucoseSource.nextPollInterval(after: readings, now: now),
            LibreLinkUpGlucoseSource.urgentPollInterval)
    }

    func testGentleFallFromAComfortableLevelKeepsTheBaseline() {
        // −0.02 mmol/L per minute: falling, but nowhere near the band.
        let readings = samples(count: 4, start: 9.0, stepPerReading: -0.1)
        XCTAssertEqual(
            LibreLinkUpGlucoseSource.nextPollInterval(after: readings, now: now),
            LibreLinkUpGlucoseSource.pollInterval)
    }

    func testRisingFastKeepsTheBaseline() {
        // Only a FALL is urgent — a spike is not a reason to spend requests.
        let readings = samples(count: 4, start: 7.0, stepPerReading: 0.8)
        XCTAssertEqual(
            LibreLinkUpGlucoseSource.nextPollInterval(after: readings, now: now),
            LibreLinkUpGlucoseSource.pollInterval)
    }

    func testUnorderedInputGivesTheSameAnswer() {
        let readings = samples(count: 4, start: 9.0, stepPerReading: -0.6)
        XCTAssertEqual(
            LibreLinkUpGlucoseSource.nextPollInterval(after: readings.reversed(), now: now),
            LibreLinkUpGlucoseSource.nextPollInterval(after: readings, now: now))
    }

    // The ban guard. 3-minute polling is the rate that has cost accounts, so
    // NEITHER interval may drop below 5 minutes, whichever governs.
    func testIntervalsStayWithinTheVendorRateLimit() {
        XCTAssertGreaterThanOrEqual(LibreLinkUpGlucoseSource.urgentPollInterval, 5 * 60)
        XCTAssertGreaterThanOrEqual(LibreLinkUpGlucoseSource.pollInterval, 5 * 60)
        XCTAssertLessThanOrEqual(
            LibreLinkUpGlucoseSource.urgentPollInterval, LibreLinkUpGlucoseSource.pollInterval)
    }

    // cgm-connect Decision 13: the baseline is the ONE shared vendor interval,
    // and it now equals the urgent floor — so every branch exercised above
    // returns the same number and the adaptive scheme is dormant rather than
    // deleted. That is deliberate: it is the recorded rollback position, and
    // raising `LibreLinkUpPolling.interval` back to 15 minutes re-arms
    // Decision 12's tightening with no other code change. These two assertions
    // are what would fail first if someone "tidied up" the dormant machinery or
    // let the two intervals drift apart again.
    func testAdaptiveMachineryIsDormantAtTheSharedInterval() {
        XCTAssertEqual(LibreLinkUpGlucoseSource.pollInterval, LibreLinkUpPolling.interval)
        XCTAssertEqual(
            LibreLinkUpGlucoseSource.pollInterval, LibreLinkUpGlucoseSource.urgentPollInterval,
            "baseline and urgent interval have diverged — Decision 12 is live again, "
                + "which is the rollback state and needs a decision-log entry")
    }
}

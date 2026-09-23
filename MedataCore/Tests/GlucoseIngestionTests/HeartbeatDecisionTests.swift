import Foundation
import Testing

@testable import GlucoseIngestion

// Phase A heartbeat decision logic (specs/data/cgm-direct Decision 6): the
// CoreBluetooth delegate is device-verified only, so the three pure decisions
// — the 30 s debounce, the 70 s stale window, and the sensor-name match — are
// what carry the timing requirements, pinned here by example tables on the
// macOS test host. No property-based testing: this is boundary checking, not
// an invariant (design Testing Strategy).
@Suite("Libre3 heartbeat decision logic (Reqs 2.1, 2.5, 5.2)")
struct HeartbeatDecisionTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - shouldFire (Req 2.5 debounce)

    @Test("the first beat, with no prior beat recorded, fires")
    func firstBeatFires() {
        #expect(Libre3Heartbeat.shouldFire(
            now: now, lastBeatAt: nil, minInterval: Libre3Heartbeat.Constants.minInterval))
    }

    @Test("beats under the minimum interval apart yield one fire, not two")
    func closeBeatsAreDebounced() {
        // A burst of BLE callbacks — didConnect immediately followed by a
        // notify, or several notifies — must spend one trigger per interval.
        for gap: TimeInterval in [0, 1, 29, Libre3Heartbeat.Constants.minInterval - 0.001] {
            #expect(!Libre3Heartbeat.shouldFire(
                now: now.addingTimeInterval(gap), lastBeatAt: now,
                minInterval: Libre3Heartbeat.Constants.minInterval),
                "a beat \(gap) s after the last must be suppressed")
        }
    }

    @Test("beats the minimum interval or more apart yield two fires")
    func spacedBeatsBothFire() {
        // The boundary belongs to firing: "a minimum interval of NO LESS THAN
        // 30 seconds" (Req 2.5) — exactly 30 s apart is a legal second fire.
        for gap: TimeInterval in [Libre3Heartbeat.Constants.minInterval, 31, 60] {
            #expect(Libre3Heartbeat.shouldFire(
                now: now.addingTimeInterval(gap), lastBeatAt: now,
                minInterval: Libre3Heartbeat.Constants.minInterval),
                "a beat \(gap) s after the last must fire")
        }
    }

    // MARK: - isStale (Req 5.2)

    @Test("a beat within the stale window is not stale")
    func recentBeatIsFresh() {
        for age: TimeInterval in [0, 10, Libre3Heartbeat.Constants.staleWindow - 1] {
            #expect(!Libre3Heartbeat.isStale(
                now: now.addingTimeInterval(age), lastBeatAt: now,
                staleWindow: Libre3Heartbeat.Constants.staleWindow),
                "a beat \(age) s old is within the window")
        }
    }

    @Test("the boundary belongs to fresh: exactly staleWindow old is not stale")
    func staleBoundaryIsFresh() {
        // Req 5.2 reads "no heartbeat for LONGER than the window" — strictly
        // greater, one place, one direction, stated.
        #expect(!Libre3Heartbeat.isStale(
            now: now.addingTimeInterval(Libre3Heartbeat.Constants.staleWindow), lastBeatAt: now,
            staleWindow: Libre3Heartbeat.Constants.staleWindow))
    }

    @Test("just past the stale window is stale")
    func pastWindowIsStale() {
        #expect(Libre3Heartbeat.isStale(
            now: now.addingTimeInterval(Libre3Heartbeat.Constants.staleWindow + 0.001),
            lastBeatAt: now,
            staleWindow: Libre3Heartbeat.Constants.staleWindow))
    }

    @Test("no beat ever received reads as stale")
    func nilLastBeatIsStale() {
        // lastBeatAt persists across relaunches (Req 5.7), so nil genuinely
        // means no beat since the heartbeat was enabled — trivially longer
        // than any window. A healthy connection replaces nil within a minute
        // (the first beat fires on connect), so this cannot linger.
        #expect(Libre3Heartbeat.isStale(
            now: now, lastBeatAt: nil, staleWindow: Libre3Heartbeat.Constants.staleWindow))
    }

    // MARK: - matchesSensor (Req 2.1)

    @Test("advertised names beginning with the Abbott prefix match", arguments: [
        "ABBOTT3XYZ123", "ABBOTT", "ABBOTTanything"
    ])
    func abbottNamesMatch(name: String) {
        #expect(Libre3Heartbeat.matchesSensor(
            advertisedName: name, prefix: Libre3Heartbeat.Constants.namePrefix))
    }

    @Test("other prefixes, casing drift, and empty names do not match", arguments: [
        "abbott3xyz", "Abbott3", "DEXCOM123", "XABBOTT", ""
    ])
    func otherNamesDoNotMatch(name: String) {
        #expect(!Libre3Heartbeat.matchesSensor(
            advertisedName: name, prefix: Libre3Heartbeat.Constants.namePrefix))
    }

    @Test("a peripheral advertising no name does not match")
    func nilNameDoesNotMatch() {
        #expect(!Libre3Heartbeat.matchesSensor(
            advertisedName: nil, prefix: Libre3Heartbeat.Constants.namePrefix))
    }

    // MARK: - Constants (the proven-client values)

    @Test("the timing constants hold the proven-client values")
    func constantsMatchTheProvenClient() {
        // 30 s is xdripswift's minimumTimeBetweenTwoHeartBeats (Req 2.5 floor:
        // "no less than 30 seconds"); 70 s is one missed minute-tick plus
        // margin, the proven disconnect-warning threshold (Req 5.2).
        #expect(Libre3Heartbeat.Constants.minInterval == 30)
        #expect(Libre3Heartbeat.Constants.staleWindow == 70)
        #expect(Libre3Heartbeat.Constants.preFetchDelay == 1)
    }
}

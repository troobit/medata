import Foundation
import GRDB
import XCTest

@testable import Persistence

// The blood write path (specs/data/fingerprick-glucose Reqs 1.3, 1.4, 2.5, 2.6,
// 4.1, 4.4, 4.5; Decisions 6, 10, 12).
//
// Sibling to LiveBslIngestTests, and deliberately not folded into it: this path
// shares no code with the keep-first merge. A blood reading is stored at its
// true instant with no grid, no cross-source dedup and no UPDATE anywhere, and
// those are the properties worth pinning.
final class BloodBslRecordTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BloodBslRecordTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        store = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // Base 2026-07-02T13:00Z — on the 5-minute grid, so anything off it is
    // visibly unsnapped.
    private let baseMs: Int64 = 1_782_997_200_000

    private func instant(msFromBase offset: Int64) -> Date {
        Date(timeIntervalSince1970: Double(baseMs + offset) / 1000)
    }

    private func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    private func bslEvents() async throws -> [Event] {
        let start = Date(timeIntervalSince1970: Double(baseMs) / 1000)
        return try await store.events(
            in: start.addingTimeInterval(-3600)...start.addingTimeInterval(3600),
            type: EventType.bsl)
    }

    private func metadata(of event: Event) throws -> [String: Any] {
        try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(event.metadata.utf8)) as? [String: Any])
    }

    // MARK: - The instant is stored as measured (Req 1.3, Decision 6)

    func testInstantIsStoredUnsnapped() async throws {
        // 13:02:37 — 2 minutes 37 seconds past the mark.
        let measured = instant(msFromBase: 157_000)
        let id = try await store.recordBloodBsl(
            BloodBslReading(instant: measured, mmolL: 9.4, sourceID: "manual", nativeID: nil))
        XCTAssertNotNil(id)

        let events = try await bslEvents()
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(ms(events[0].timestamp), baseMs + 157_000)
        XCTAssertEqual(events[0].value, 9.4)
        XCTAssertEqual(events[0].id, id)
    }

    // MARK: - Metadata shape (Reqs 2.5, 2.6)

    func testMetadataCarriesProvenanceAndOmitsNativeIDWhenNil() async throws {
        _ = try await store.recordBloodBsl(
            BloodBslReading(
                instant: instant(msFromBase: 60_000), mmolL: 9.4, sourceID: "manual",
                nativeID: nil))

        let events = try await bslEvents()
        let json = try metadata(of: events[0])
        XCTAssertEqual(json["provenance"] as? String, "blood")
        XCTAssertEqual(json["source_id"] as? String, "manual")
        XCTAssertFalse(
            json.keys.contains("native_id"),
            "native_id must be absent, never null, when nil — the liveBslMetadataJSON convention")
    }

    func testMetadataCarriesNativeIDWhenPresent() async throws {
        _ = try await store.recordBloodBsl(
            BloodBslReading(
                instant: instant(msFromBase: 60_000), mmolL: 9.4, sourceID: "healthkit",
                nativeID: "hk-uuid-1"))

        let events = try await bslEvents()
        let json = try metadata(of: events[0])
        XCTAssertEqual(json["source_id"] as? String, "healthkit")
        XCTAssertEqual(json["native_id"] as? String, "hk-uuid-1")
    }

    // MARK: - Idempotence (Req 1.4, Decision 10)

    func testRedeliveredNativeIDWritesNoSecondRowAndDoesNotNotify() async throws {
        let reading = BloodBslReading(
            instant: instant(msFromBase: 157_000), mmolL: 9.4, sourceID: "healthkit",
            nativeID: "hk-uuid-1")
        let first = try await store.recordBloodBsl(reading)
        XCTAssertNotNil(first)

        let counter = TickCounter()
        let stream = store.eventsDidChange
        let observer = Task { for await _ in stream { await counter.bump() } }
        await Task.yield()

        let second = try await store.recordBloodBsl(reading)
        XCTAssertNil(second, "a re-delivered sample is a no-op, not a new row")

        try await Task.sleep(nanoseconds: 200_000_000)
        let ticks = await counter.get()
        observer.cancel()
        XCTAssertEqual(ticks, 0, "a no-op write emits no eventsDidChange")

        let events = try await bslEvents()
        XCTAssertEqual(events.count, 1)
    }

    // Two fingersticks a minute apart are two measurements; so are two at the
    // same instant. A value-and-instant heuristic would silently discard one.
    func testTwoHandEntriesAtTheSameInstantBothPersist() async throws {
        let measured = instant(msFromBase: 157_000)
        let first = try await store.recordBloodBsl(
            BloodBslReading(instant: measured, mmolL: 9.4, sourceID: "manual", nativeID: nil))
        let second = try await store.recordBloodBsl(
            BloodBslReading(instant: measured, mmolL: 9.4, sourceID: "manual", nativeID: nil))

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertNotEqual(first, second)
        let events = try await bslEvents()
        XCTAssertEqual(events.count, 2)
    }

    // MARK: - Sensor data preserved (Reqs 4.1, 4.4)

    func testBloodRowAtASensorInstantLeavesTheSensorRowRetrievable() async throws {
        _ = try await store.ingestLiveBsl([
            LiveBslReading(
                timestampMs: baseMs, mmolL: 6.1, sourceID: "librelinkup",
                nativeInstantMs: baseMs, nativeID: nil)
        ])
        let sensorRow = try await bslEvents()[0]

        let bloodID = try await store.recordBloodBsl(
            BloodBslReading(
                instant: Date(timeIntervalSince1970: Double(baseMs) / 1000), mmolL: 9.4,
                sourceID: "manual", nativeID: nil))

        let events = try await bslEvents()
        XCTAssertEqual(events.count, 2, "both readings survive at one instant")
        XCTAssertTrue(events.contains { $0.id == sensorRow.id && $0.value == 6.1 })
        XCTAssertTrue(events.contains { $0.id == bloodID && $0.value == 9.4 })
    }

    // MARK: - Range guard

    func testOutOfRangeValueIsRejectedAtTheStore() async throws {
        // The pad cannot express any of these; the guard is what stops a deep
        // link or a future caller doing so.
        for value in [0.9, 30.1] {
            do {
                _ = try await store.recordBloodBsl(
                    BloodBslReading(
                        instant: instant(msFromBase: 0), mmolL: value, sourceID: "manual",
                        nativeID: nil))
                XCTFail("expected bloodGlucoseOutOfRange for \(value)")
            } catch {
                XCTAssertEqual(
                    error as? Persistence.PersistenceError, .bloodGlucoseOutOfRange(value))
            }
        }

        do {
            _ = try await store.recordBloodBsl(
                BloodBslReading(
                    instant: instant(msFromBase: 0), mmolL: .nan, sourceID: "manual",
                    nativeID: nil))
            XCTFail("expected bloodGlucoseOutOfRange for NaN")
        } catch {
            // NaN compares equal to nothing, so the case is checked, not the payload.
            guard case .bloodGlucoseOutOfRange = error as? Persistence.PersistenceError else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }

        let events = try await bslEvents()
        XCTAssertTrue(events.isEmpty)
    }

    func testRangeBoundsAreAccepted() async throws {
        for (offset, value) in [(Int64(0), 1.0), (60_000, 30.0)] {
            let id = try await store.recordBloodBsl(
                BloodBslReading(
                    instant: instant(msFromBase: offset), mmolL: value, sourceID: "manual",
                    nativeID: nil))
            XCTAssertNotNil(id)
        }
    }

    // MARK: - The pairing stamp (Req 4.5, Decision 12)

    func testPairingStampRecordsTheLatestInWindowSensorReading() async throws {
        // Two sensor rows inside the 15 minutes before the blood instant, and
        // one outside it, so "latest in window" is actually tested.
        _ = try await store.ingestLiveBsl([
            LiveBslReading(
                timestampMs: baseMs - 20 * 60_000, mmolL: 4.0, sourceID: "librelinkup",
                nativeInstantMs: baseMs - 20 * 60_000, nativeID: nil),
            LiveBslReading(
                timestampMs: baseMs - 10 * 60_000, mmolL: 6.0, sourceID: "librelinkup",
                nativeInstantMs: baseMs - 10 * 60_000, nativeID: nil),
            LiveBslReading(
                timestampMs: baseMs - 5 * 60_000, mmolL: 6.5, sourceID: "librelinkup",
                nativeInstantMs: baseMs - 5 * 60_000, nativeID: nil),
        ])

        _ = try await store.recordBloodBsl(
            BloodBslReading(
                instant: instant(msFromBase: 0), mmolL: 9.4, sourceID: "manual", nativeID: nil))

        let afterBlood = try await bslEvents()
        let blood = try XCTUnwrap(afterBlood.first { $0.value == 9.4 })
        let json = try metadata(of: blood)
        XCTAssertEqual(json["paired_sensor_value"] as? Double, 6.5)
        XCTAssertEqual(json["paired_sensor_instant"] as? Int64, baseMs - 5 * 60_000)
        XCTAssertEqual(try XCTUnwrap(json["sensor_delta"] as? Double), 2.9, accuracy: 1e-9)

        // The sensor row is read, never touched.
        let sensor = try XCTUnwrap(afterBlood.first { $0.value == 6.5 })
        let sensorJSON = try metadata(of: sensor)
        XCTAssertNil(sensorJSON["provenance"])
        XCTAssertEqual(sensorJSON["source_id"] as? String, "librelinkup")
    }

    func testPairingKeysAreAbsentWithNoSensorReadingInTheWindow() async throws {
        // 16 minutes before the blood instant — outside the window.
        _ = try await store.ingestLiveBsl([
            LiveBslReading(
                timestampMs: baseMs - 16 * 60_000, mmolL: 6.0, sourceID: "librelinkup",
                nativeInstantMs: baseMs - 16 * 60_000, nativeID: nil)
        ])

        _ = try await store.recordBloodBsl(
            BloodBslReading(
                instant: instant(msFromBase: 0), mmolL: 9.4, sourceID: "manual", nativeID: nil))

        let events = try await bslEvents()
        let blood = try XCTUnwrap(events.first { $0.value == 9.4 })
        let json = try metadata(of: blood)
        for key in ["paired_sensor_value", "paired_sensor_instant", "sensor_delta"] {
            XCTAssertFalse(json.keys.contains(key), "\(key) must be absent, never null")
        }
    }

    // An earlier blood reading is not a sensor reading: pairing a fingerstick
    // against a fingerstick would measure nothing.
    func testAnEarlierBloodReadingIsNotPairedAgainst() async throws {
        _ = try await store.recordBloodBsl(
            BloodBslReading(
                instant: instant(msFromBase: -5 * 60_000), mmolL: 8.0, sourceID: "manual",
                nativeID: nil))
        _ = try await store.recordBloodBsl(
            BloodBslReading(
                instant: instant(msFromBase: 0), mmolL: 9.4, sourceID: "manual", nativeID: nil))

        let events = try await bslEvents()
        let blood = try XCTUnwrap(events.first { $0.value == 9.4 })
        let json = try metadata(of: blood)
        XCTAssertFalse(json.keys.contains("paired_sensor_value"))
    }

    // MARK: - Notification (one tick, only on a real write)

    func testASuccessfulWriteNotifiesExactlyOnce() async throws {
        let counter = TickCounter()
        let stream = store.eventsDidChange
        let observer = Task { for await _ in stream { await counter.bump() } }
        await Task.yield()

        _ = try await store.recordBloodBsl(
            BloodBslReading(
                instant: instant(msFromBase: 0), mmolL: 9.4, sourceID: "manual", nativeID: nil))

        try await Task.sleep(nanoseconds: 200_000_000)
        let ticks = await counter.get()
        observer.cancel()
        XCTAssertEqual(ticks, 1)
    }
}

// MARK: - Helpers

private actor TickCounter {
    private(set) var count = 0
    func bump() { count += 1 }
    func get() -> Int { count }
}

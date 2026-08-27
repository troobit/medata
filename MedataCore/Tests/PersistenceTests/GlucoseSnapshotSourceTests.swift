import Foundation
import GlucoseWidgetShared
import XCTest

@testable import Persistence

// The store → snapshot step (specs/data/fingerprick-glucose Reqs 3.7, 7.1).
//
// `GlucoseDerivationTests` already pins the precedence rule over synthesised
// readings. What is unpinned until here is the STEP BEFORE it: turning stored
// `bsl` rows back into `GlucoseReading`s carrying the provenance they were
// written with, and forwarding the hold window the caller configured. Both
// were placeholders — every reading read back as `.sensor` and the window was
// hard-coded to zero — so the whole feature was inert app-side no matter how
// correct the pure function was.
final class GlucoseSnapshotSourceTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlucoseSnapshotSourceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = try GRDBPersistenceStore(
            dbURL: tempDir.appendingPathComponent("meals.sqlite"), artefactsBaseURL: tempDir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // Base 2026-07-02T13:00Z, on the 5-minute grid.
    private let baseMs: Int64 = 1_782_997_200_000

    private func instant(minutes: Double) -> Date {
        Date(timeIntervalSince1970: Double(baseMs) / 1000 + minutes * 60)
    }

    private func ms(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 * 1000).rounded()) }

    private func event(metadata: String, value: Double? = 7.0) -> Event {
        Event(
            id: UUID(), timestamp: instant(minutes: 0), eventType: EventType.bsl,
            value: value, metadata: metadata)
    }

    // MARK: - The provenance decode (Req 7.1)

    func testBloodProvenanceIsDecoded() throws {
        let reading = try XCTUnwrap(
            GlucoseSnapshotSource.reading(from: event(metadata: #"{"provenance":"blood"}"#)))
        XCTAssertEqual(reading.provenance, .blood)
        XCTAssertEqual(reading.mmolL, 7.0)
    }

    // Req 7.1 in its entirety: absence IS sensor, so every reading recorded
    // before this feature reads back correctly with nothing rewritten. This is
    // the shape `ingestLiveBsl` writes.
    func testAbsentProvenanceKeyIsSensor() throws {
        let reading = try XCTUnwrap(
            GlucoseSnapshotSource.reading(
                from: event(metadata: #"{"source_id":"librelinkup","native_instant_ms":1}"#)))
        XCTAssertEqual(reading.provenance, .sensor)
    }

    // Fail-safe direction: a value this build does not know must not earn the
    // 15-minute hold a blood reading gets.
    func testUnrecognisedProvenanceIsSensor() throws {
        let reading = try XCTUnwrap(
            GlucoseSnapshotSource.reading(from: event(metadata: #"{"provenance":"plasma"}"#)))
        XCTAssertEqual(reading.provenance, .sensor)
    }

    func testUndecodableMetadataIsSensor() throws {
        let reading = try XCTUnwrap(GlucoseSnapshotSource.reading(from: event(metadata: "")))
        XCTAssertEqual(reading.provenance, .sensor)
    }

    // A `bsl` row with no value carries no reading; it is dropped rather than
    // fabricating one, exactly as the previous `compactMap` did.
    func testValuelessRowIsDropped() {
        XCTAssertNil(GlucoseSnapshotSource.reading(from: event(metadata: "{}", value: nil)))
    }

    // MARK: - End to end over a real store (Req 3.7)

    // The two write paths, read back through one query: `ingestLiveBsl` stamps
    // no provenance key and `recordBloodBsl` stamps "blood", and the snapshot
    // source must tell them apart without either row being rewritten.
    private func seed() async throws {
        _ = try await store.ingestLiveBsl(
            [-10.0, -5.0, 0.0, 5.0].enumerated().map { index, offset in
                LiveBslReading(
                    timestampMs: ms(instant(minutes: offset)), mmolL: 7.0 + Double(index) * 0.2,
                    sourceID: "librelinkup", nativeInstantMs: ms(instant(minutes: offset)))
            })
        _ = try await store.recordBloodBsl(
            BloodBslReading(instant: instant(minutes: 2), mmolL: 9.1, sourceID: "manual"))
    }

    // Inside the window the blood reading is displayed even though a sensor
    // reading three minutes NEWER than it exists (Req 3.1 through the store).
    func testBloodReadingHoldsInsideTheWindow() async throws {
        try await seed()
        let snapshot = await GlucoseSnapshotSource.current(
            store: store, now: instant(minutes: 6), holdWindow: 15 * 60)
        XCTAssertEqual(snapshot.mmolL, 9.1)
        XCTAssertEqual(snapshot.provenance, .blood)
        XCTAssertEqual(snapshot.readingDate, instant(minutes: 2))
        XCTAssertEqual(snapshot.holdsUntil, instant(minutes: 17))
    }

    // Once the window has elapsed the latest reading of any provenance
    // resumes (Req 3.3) — here the 13:05 sensor row.
    func testBloodReadingReleasesAfterTheWindow() async throws {
        try await seed()
        let snapshot = await GlucoseSnapshotSource.current(
            store: store, now: instant(minutes: 18), holdWindow: 15 * 60)
        XCTAssertEqual(snapshot.mmolL, 7.6)
        XCTAssertEqual(snapshot.provenance, .sensor)
        XCTAssertEqual(snapshot.readingDate, instant(minutes: 5))
        XCTAssertNil(snapshot.holdsUntil)
    }

    // The window is genuinely forwarded, not defaulted: at the same instant as
    // the holding case, a zero window resolves the sensor reading instead.
    func testZeroHoldWindowResolvesTheLatestReading() async throws {
        try await seed()
        let snapshot = await GlucoseSnapshotSource.current(
            store: store, now: instant(minutes: 6), holdWindow: 0)
        XCTAssertEqual(snapshot.mmolL, 7.6)
        XCTAssertEqual(snapshot.provenance, .sensor)
    }
}

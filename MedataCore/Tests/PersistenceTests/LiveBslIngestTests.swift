import Foundation
import GRDB
import XCTest

@testable import Persistence

// Tests for the live-ingestion sibling to ingestBsl (specs/data/cgm-connect
// Reqs 4, 5): keep-first merge shared with the screenshot importer, per-row
// metadata, intra-batch collision protection, and the notify-once-per-batch
// contract.
final class LiveBslIngestTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LiveBslIngestTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        store = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private let screenshotMetadataJSON = #"{"source_hash":"sha256:abc","source_file":"IMG_0570.PNG","view":"home8h","date":"2026-07-02","date_source":"asset","timezone":"Europe/Dublin","axis_range":[3,21]}"#

    // Base 2026-07-02T00:00Z, 5-minute grid.
    private let baseMs: Int64 = 1_782_950_400_000

    private func gridMs(_ minute: Int) -> Int64 { baseMs + Int64(minute) * 60_000 }

    private func liveReading(
        _ minute: Int, _ mmolL: Double, sourceID: String = "healthkit",
        nativeOffsetMs: Int64 = 0, nativeID: String? = nil
    ) -> LiveBslReading {
        LiveBslReading(
            timestampMs: gridMs(minute), mmolL: mmolL, sourceID: sourceID,
            nativeInstantMs: gridMs(minute) + nativeOffsetMs, nativeID: nativeID)
    }

    // MARK: - Keep-first across sources (Req 5.1, 5.2)

    func testKeepFirstAcrossSourcesScreenshotWins() async throws {
        // Pre-seed a screenshot bsl row at a grid instant.
        _ = try await store.ingestBsl(
            readings: [BslReading(timestampMs: gridMs(0), value: 5.4)],
            metadataJSON: screenshotMetadataJSON, sourceHash: "shot1", filename: "a.PNG")

        // A live reading at the SAME grid instant, differing value.
        let summary = try await store.ingestLiveBsl([
            liveReading(0, 6.0, sourceID: "healthkit")
        ])

        XCTAssertEqual(summary.stored, 0, "screenshot row wins keep-first")
        XCTAssertEqual(summary.discrepant.count, 1)
        XCTAssertEqual(summary.discrepant[0].kept, 5.4)
        XCTAssertEqual(summary.discrepant[0].new, 6.0)

        let start = Date(timeIntervalSince1970: Double(baseMs) / 1000)
        let events = try await store.events(
            in: start...start.addingTimeInterval(3600), type: EventType.bsl)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].value, 5.4, "pre-existing value unchanged")
    }

    // MARK: - Single notification per batch (Req 4.4)

    func testIngestLiveBslNotifiesOnceWhenRowsStored() async throws {
        let counter = TickBox()
        let stream = store.eventsDidChange
        let observer = Task {
            for await _ in stream { await counter.bump() }
        }
        await Task.yield()

        let summary = try await store.ingestLiveBsl([
            liveReading(0, 5.4), liveReading(5, 5.6), liveReading(10, 5.9),
        ])
        XCTAssertEqual(summary.stored, 3)
        try await Task.sleep(nanoseconds: 200_000_000)
        let afterStore = await counter.get()
        XCTAssertEqual(afterStore, 1, "one tick per batch, not per row")

        // Fully-overlapping batch stores nothing -> no tick.
        _ = try await store.ingestLiveBsl([liveReading(0, 5.4)])
        try await Task.sleep(nanoseconds: 200_000_000)
        let afterOverlap = await counter.get()
        observer.cancel()
        XCTAssertEqual(afterOverlap, 1, "no tick when nothing was stored")
    }

    // MARK: - Intra-batch collision protection (Task 1's mergeBslKeepFirst change)

    func testTwoLiveRowsAtSameTimestampInOneBatchStoreExactlyOne() async throws {
        let summary = try await store.ingestLiveBsl([
            liveReading(0, 5.4, sourceID: "healthkit"),
            liveReading(0, 5.5, sourceID: "librelinkup"),
        ])

        XCTAssertEqual(summary.stored, 1, "only the first of two same-mark rows inserts")

        let start = Date(timeIntervalSince1970: Double(baseMs) / 1000)
        let events = try await store.events(
            in: start...start.addingTimeInterval(3600), type: EventType.bsl)
        XCTAssertEqual(events.count, 1)
    }

    // MARK: - Round-trip metadata (Req 4.2)

    func testMetadataOmitsNativeIDWhenNilAndIncludesWhenPresent() async throws {
        _ = try await store.ingestLiveBsl([
            liveReading(0, 5.4, sourceID: "healthkit", nativeOffsetMs: -47_000, nativeID: "hk-uuid-123"),
            liveReading(5, 5.6, sourceID: "librelinkup", nativeOffsetMs: 12_000, nativeID: nil),
        ])

        let start = Date(timeIntervalSince1970: Double(baseMs) / 1000)
        let events = try await store.events(
            in: start...start.addingTimeInterval(3600), type: EventType.bsl)
        XCTAssertEqual(events.count, 2)

        let withID = events[0]
        let withoutID = events[1]

        let withIDJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(withID.metadata.utf8)) as? [String: Any])
        XCTAssertEqual(withIDJSON["source_id"] as? String, "healthkit")
        XCTAssertEqual(withIDJSON["native_instant_ms"] as? Int64, gridMs(0) - 47_000)
        XCTAssertEqual(withIDJSON["native_id"] as? String, "hk-uuid-123")

        let withoutIDJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(withoutID.metadata.utf8)) as? [String: Any])
        XCTAssertEqual(withoutIDJSON["source_id"] as? String, "librelinkup")
        XCTAssertEqual(withoutIDJSON["native_instant_ms"] as? Int64, gridMs(5) + 12_000)
        XCTAssertNil(withoutIDJSON["native_id"], "native_id key must be absent, not null, when nil")
        XCTAssertFalse(
            withoutIDJSON.keys.contains("native_id"),
            "key must be omitted entirely, not present with a null value")
    }
}

// MARK: - Helpers

private actor TickBox {
    private(set) var count = 0
    func bump() { count += 1 }
    func get() -> Int { count }
}

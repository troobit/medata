import Foundation
import Testing
@testable import GlucoseWidgetShared

// The app→widget contract (Reqs 1.1, 1.5–1.7, 2.7). The store is exercised
// against an injected UserDefaults suite: the real App Group suite is not
// available to a macOS test host, and the entitlement round-trip is
// human-gated anyway (prerequisites.md) because a mis-provisioned App Group
// still yields a non-nil private store.
@Suite("GlucoseSnapshot")
struct GlucoseSnapshotTests {

    private let reading = Date(timeIntervalSince1970: 1_700_000_000)

    // A throwaway suite per test; the caller removes it afterwards.
    private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "GlucoseWidgetSharedTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { UserDefaults().removePersistentDomain(forName: name) }
        try body(defaults)
    }

    // MARK: - Round trip (Req 1.1)

    @Test("A written snapshot reads back identically")
    func roundTripIdentity() {
        withSuite { defaults in
            let snapshot = GlucoseSnapshot.make(
                mmolL: 6.4, readingDate: reading, trend: .risingSlow, status: .inRange)
            GlucoseSnapshotStore.write(snapshot, to: defaults)
            #expect(GlucoseSnapshotStore.read(from: defaults) == snapshot)
        }
    }

    @Test("A never-recorded snapshot round-trips as never-recorded")
    func roundTripNeverRecorded() {
        withSuite { defaults in
            GlucoseSnapshotStore.write(.neverRecorded, to: defaults)
            #expect(GlucoseSnapshotStore.read(from: defaults) == .neverRecorded)
        }
    }

    @Test("A trendless snapshot keeps its nil trend")
    func roundTripWithoutTrend() {
        withSuite { defaults in
            let snapshot = GlucoseSnapshot.make(
                mmolL: 11.2, readingDate: reading, trend: nil, status: .high)
            GlucoseSnapshotStore.write(snapshot, to: defaults)
            let read = GlucoseSnapshotStore.read(from: defaults)
            #expect(read == snapshot)
            #expect(read.trend == nil)
        }
    }

    // MARK: - Unreadable snapshots (Req 1.7)

    @Test("No stored snapshot reads as never-recorded")
    func missingReadsNeverRecorded() {
        withSuite { defaults in
            #expect(GlucoseSnapshotStore.read(from: defaults) == .neverRecorded)
        }
    }

    @Test("An unknown schema version reads as never-recorded")
    func unknownVersionReadsNeverRecorded() throws {
        try withSuite { defaults in
            let blob = try JSONSerialization.data(withJSONObject: [
                "version": GlucoseSnapshot.schemaVersion + 1,
                "mmolL": 5.5,
                "readingDate": reading.timeIntervalSinceReferenceDate,
                "status": "inRange"
            ])
            defaults.set(blob, forKey: GlucoseSnapshotStore.snapshotKey)
            #expect(GlucoseSnapshotStore.read(from: defaults) == .neverRecorded)
        }
    }

    @Test("An undecodable blob reads as never-recorded")
    func corruptBlobReadsNeverRecorded() {
        withSuite { defaults in
            defaults.set(Data("not a snapshot".utf8), forKey: GlucoseSnapshotStore.snapshotKey)
            #expect(GlucoseSnapshotStore.read(from: defaults) == .neverRecorded)
        }
    }

    // MARK: - Nil suite (Req 1.6)

    @Test("A nil suite makes the write a no-op and the read never-recorded")
    func nilSuiteIsInert() {
        GlucoseSnapshotStore.write(
            .make(mmolL: 5.0, readingDate: reading, trend: .steady, status: .inRange), to: nil)
        #expect(GlucoseSnapshotStore.read(from: nil) == .neverRecorded)
    }

    // MARK: - Value sanity guard (Req 2.7)

    @Test("A plausible reading builds a value-carrying snapshot")
    func plausibleValueBuilds() {
        let snapshot = GlucoseSnapshot.make(
            mmolL: 5.5, readingDate: reading, trend: .steady, status: .inRange)
        #expect(snapshot.mmolL == 5.5)
        #expect(snapshot.readingDate == reading)
        #expect(snapshot.version == GlucoseSnapshot.schemaVersion)
    }

    @Test("The plausible range is inclusive at both bounds", arguments: [1.0, 35.0])
    func rangeBoundsAreInclusive(_ mmolL: Double) {
        let snapshot = GlucoseSnapshot.make(
            mmolL: mmolL, readingDate: reading, trend: nil, status: .inRange)
        #expect(snapshot.mmolL == mmolL)
    }

    @Test(
        "A non-finite or out-of-range reading builds never-recorded",
        arguments: [Double.nan, .infinity, -.infinity, 0.9, 35.1, 0, -5])
    func implausibleValueBuildsNeverRecorded(_ mmolL: Double) {
        let snapshot = GlucoseSnapshot.make(
            mmolL: mmolL, readingDate: reading, trend: .risingFast, status: .high)
        #expect(snapshot == .neverRecorded)
    }

    // MARK: - Identifiers

    @Test("The widget kind follows the existing launcher convention")
    func identifiersArePinned() {
        #expect(GlucoseSnapshotStore.appGroupID == "group.rtob.MeData")
        #expect(GlucoseSnapshotStore.widgetKind == "ie.medata.widget.glucose")
    }

    @Test("Every trend state carries a distinct arrow glyph")
    func trendArrowsAreDistinct() {
        let arrows = GlucoseTrend.allCases.map(\.arrow)
        #expect(Set(arrows).count == GlucoseTrend.allCases.count)
        #expect(GlucoseTrend.steady.arrow == "→")
    }
}

import Foundation
import Testing

@testable import GlucoseWidgetShared

// The two-writer write policy (specs/data/fingerprick-glucose Reqs 3.7, 3.8,
// 6.2; Decisions 9 and 11), extending glucose-lock-widget Decision 19.
//
// The app publishes what the database holds; the widget extension publishes
// what it fetched for itself while the app was suspended. Neither can see the
// other's data, so the rule that reconciles them lives in the store — any
// future writer inherits it by construction.
@Suite("GlucoseSnapshotStore.merged")
struct GlucoseSnapshotMergeTests {

    // Anchored to the real clock, whole seconds, because `write` judges a hold
    // against `Date()` — a fixed historical base would leave every hold expired
    // and case 1 unreachable through the public entry point. Whole seconds so
    // the `replacingDeleted` instants compare exactly after a JSON round trip.
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded())

    private func at(_ offset: TimeInterval) -> Date { now.addingTimeInterval(offset) }

    private func snapshot(
        _ mmolL: Double, _ readingDate: Date, trend: GlucoseTrend? = .steady,
        provenance: GlucoseProvenance = .sensor, holdsUntil: Date? = nil
    ) -> GlucoseSnapshot {
        GlucoseSnapshot.make(
            mmolL: mmolL, readingDate: readingDate, trend: trend, status: .inRange,
            provenance: provenance, holdsUntil: holdsUntil)
    }

    // A throwaway suite per test; the caller removes it afterwards.
    private func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "GlucoseWidgetSharedTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { UserDefaults().removePersistentDomain(forName: name) }
        try body(defaults)
    }

    // MARK: - Case 1: a sensor write during a hold contributes trend only

    // Req 3.8, and the reason the case exists at all: the extension fetches a
    // 13:05 sensor reading knowing nothing of the 13:02 blood reading holding
    // the display, and case 3 alone would accept the clobber.
    @Test("A sensor candidate during a hold keeps the held reading and adopts its trend")
    func sensorCandidateDuringHoldContributesTrendOnly() {
        let stored = snapshot(
            9.4, at(-180), trend: .steady, provenance: .blood, holdsUntil: at(720))
        let candidate = snapshot(6.1, at(0), trend: .risingFast, provenance: .sensor)

        let merged = GlucoseSnapshotStore.merged(candidate, into: stored, now: now)

        #expect(merged?.mmolL == 9.4)
        #expect(merged?.readingDate == at(-180))
        #expect(merged?.provenance == .blood)
        #expect(merged?.holdsUntil == at(720))
        #expect(merged?.trend == .risingFast, "the arrow stays live while the value is held")
    }

    @Test("An expired hold no longer protects the stored reading")
    func expiredHoldStopsProtecting() {
        let stored = snapshot(
            9.4, at(-1800), trend: .steady, provenance: .blood, holdsUntil: at(-900))
        let candidate = snapshot(6.1, at(0), trend: .falling, provenance: .sensor)

        let merged = GlucoseSnapshotStore.merged(candidate, into: stored, now: now)

        #expect(merged == candidate)
    }

    // A blood candidate is the app speaking about data the extension cannot
    // see, so it is never held off by a hold — it goes through the ordinary
    // ordering rule.
    @Test("A blood candidate during a hold is judged by the ordinary rule")
    func bloodCandidateDuringHoldUsesTheOrdinaryRule() {
        let stored = snapshot(
            9.4, at(-180), trend: .steady, provenance: .blood, holdsUntil: at(720))
        let newer = snapshot(
            5.2, at(-30), trend: .falling, provenance: .blood, holdsUntil: at(870))

        #expect(GlucoseSnapshotStore.merged(newer, into: stored, now: now) == newer)
    }

    // The history emptying is not an older reading; the app must still be able
    // to clear the tile mid-hold.
    @Test("Never-recorded clears a held reading")
    func neverRecordedClearsAHold() {
        let stored = snapshot(
            9.4, at(-180), trend: .steady, provenance: .blood, holdsUntil: at(720))

        #expect(
            GlucoseSnapshotStore.merged(.neverRecorded, into: stored, now: now)
                == .neverRecorded)
    }

    // MARK: - Case 2: an equal-dated republish refreshes the trend

    // Without this the arrow freezes for the whole window — in the foreground
    // as readily as in the background — because the app republishes the SAME
    // displayed reading with a freshly derived trend and a strictly-newer rule
    // refuses it.
    @Test("An equal-dated candidate is admitted when its trend differs")
    func equalDatedCandidateWithNewTrendIsAdmitted() {
        let stored = snapshot(6.4, at(-300), trend: .steady)
        let candidate = snapshot(6.4, at(-300), trend: .risingSlow)

        #expect(GlucoseSnapshotStore.merged(candidate, into: stored, now: now) == candidate)
    }

    @Test("An equal-dated candidate carrying the same trend is not written")
    func equalDatedCandidateWithSameTrendIsRefused() {
        let stored = snapshot(6.4, at(-300), trend: .steady)
        let candidate = snapshot(6.4, at(-300), trend: .steady)

        #expect(GlucoseSnapshotStore.merged(candidate, into: stored, now: now) == nil)
    }

    // Same instant, different provenance: a blood reading recorded at the very
    // instant of a sensor row is a different reading, not a trend refresh.
    @Test("An equal-dated candidate of a different provenance is not a trend refresh")
    func equalDatedDifferentProvenanceIsNotCaseTwo() {
        let stored = snapshot(6.4, at(-300), trend: .steady, provenance: .sensor)
        let candidate = snapshot(
            9.1, at(-300), trend: .steady, provenance: .blood, holdsUntil: at(600))

        // Not strictly newer, so case 3 refuses it; the app's next publish,
        // carrying a later instant, lands it.
        #expect(GlucoseSnapshotStore.merged(candidate, into: stored, now: now) == nil)
    }

    // MARK: - Case 3: Decision 19 unchanged

    @Test("A strictly newer candidate replaces the stored snapshot")
    func newerCandidateWins() {
        let stored = snapshot(6.4, at(-300))
        let candidate = snapshot(7.1, at(0), trend: .rising)

        #expect(GlucoseSnapshotStore.merged(candidate, into: stored, now: now) == candidate)
    }

    @Test("An older candidate is refused", arguments: [-3600.0, -300.0])
    func olderCandidateIsRefused(_ offset: TimeInterval) {
        let stored = snapshot(6.4, at(0))
        let candidate = snapshot(9.1, at(offset), trend: .rising)

        #expect(GlucoseSnapshotStore.merged(candidate, into: stored, now: now) == nil)
    }

    @Test("A candidate carrying no reading always writes")
    func neverRecordedAlwaysWrites() {
        let stored = snapshot(6.4, at(0))

        #expect(
            GlucoseSnapshotStore.merged(.neverRecorded, into: stored, now: now)
                == .neverRecorded)
    }

    @Test("Any candidate writes over a never-recorded store")
    func anythingWritesOverNeverRecorded() {
        let candidate = snapshot(6.4, at(-3600))

        #expect(
            GlucoseSnapshotStore.merged(candidate, into: .neverRecorded, now: now) == candidate)
    }

    // MARK: - The invariant

    // The substance of Decision 19, preserved across the two new cases: no
    // ordinary write ever moves the displayed reading backwards. Cases 1 and 2
    // do not move it at all.
    @Test("The displayed reading's date never decreases across a sequence of writes")
    func displayedDateNeverDecreases() throws {
        try withSuite { defaults in
            let candidates = [
                snapshot(6.4, at(-1800), trend: .steady),
                snapshot(9.4, at(-180), trend: .steady, provenance: .blood, holdsUntil: at(720)),
                snapshot(6.1, at(0), trend: .risingFast),
                snapshot(5.0, at(-3600), trend: .falling),
                snapshot(6.1, at(0), trend: .steady),
                snapshot(7.7, at(300), trend: .rising),
            ]
            var high = Date.distantPast
            for candidate in candidates {
                GlucoseSnapshotStore.write(candidate, to: defaults)
                let readingDate = GlucoseSnapshotStore.read(from: defaults).readingDate
                let current = try #require(readingDate)
                #expect(current >= high)
                high = current
            }
        }
    }

    // MARK: - Deletion-authorised rollback (Req 6.2, Decision 11)

    @Test("Deleting the displayed reading rolls the snapshot back to an older one")
    func deletionRollsBackOverTheRemovedReading() {
        withSuite { defaults in
            let displayed = snapshot(9.4, at(0), trend: .steady)
            #expect(GlucoseSnapshotStore.write(displayed, to: defaults))

            let fallback = snapshot(6.1, at(-600), trend: .falling)
            #expect(
                GlucoseSnapshotStore.write(
                    fallback, replacingDeleted: [at(0)], to: defaults))
            #expect(GlucoseSnapshotStore.read(from: defaults) == fallback)
        }
    }

    // The narrowing is the whole point: an unconditional force-write would
    // reinstate the Decision 19 regression, where a stale app-side recompute
    // rolled the snapshot back over a newer reading the extension had fetched
    // while the app was suspended.
    @Test("A removed instant that is not the displayed one authorises nothing")
    func deletionOfAnotherReadingDoesNotAuthoriseRollback() {
        withSuite { defaults in
            let displayed = snapshot(9.4, at(0), trend: .steady)
            #expect(GlucoseSnapshotStore.write(displayed, to: defaults))

            let older = snapshot(6.1, at(-600), trend: .falling)
            #expect(
                GlucoseSnapshotStore.write(
                    older, replacingDeleted: [at(-1200), at(-1800)], to: defaults) == false)
            #expect(GlucoseSnapshotStore.read(from: defaults) == displayed)
        }
    }

    @Test("An empty removed list leaves the ordinary rule in force")
    func emptyRemovedListChangesNothing() {
        withSuite { defaults in
            let displayed = snapshot(9.4, at(0), trend: .steady)
            #expect(GlucoseSnapshotStore.write(displayed, to: defaults))
            #expect(
                GlucoseSnapshotStore.write(
                    snapshot(6.1, at(-600), trend: .falling), replacingDeleted: [],
                    to: defaults) == false)
            #expect(GlucoseSnapshotStore.read(from: defaults) == displayed)
        }
    }
}

import Foundation
import Testing
@testable import GlucoseWidgetShared

// The staleness ladder (Reqs 5.1-5.5, 8.1; Decisions 5, 9, 13). Pure functions
// of (snapshot, reference date) — the WidgetKit adapter in the extension is a
// struct declaration and a two-case mapping, covered by the device pass.
@Suite("GlucoseTimeline")
struct GlucoseTimelineTests {

    private let readingDate = Date(timeIntervalSince1970: 1_700_000_000)

    private var snapshot: GlucoseSnapshot {
        .make(mmolL: 6.4, readingDate: readingDate, trend: .risingSlow, status: .inRange)
    }

    private func at(_ age: TimeInterval) -> Date { readingDate.addingTimeInterval(age) }

    // MARK: - render (Reqs 5.1-5.3)

    @Test("A reading fifteen minutes old or less renders fresh", arguments: [0.0, 60, 899, 900])
    func freshBand(_ age: TimeInterval) {
        #expect(
            GlucoseTimeline.render(snapshot, at: at(age))
                == .fresh(value: "6.4", status: .inRange, trend: .risingSlow, provenance: .sensor))
    }

    @Test("Past fifteen minutes and up to thirty the value is stale")
    func staleBand() {
        #expect(
            GlucoseTimeline.render(snapshot, at: at(901))
                == .stale(value: "6.4", age: "15m", provenance: .sensor))
        #expect(
            GlucoseTimeline.render(snapshot, at: at(1800))
                == .stale(value: "6.4", age: "30m", provenance: .sensor))
    }

    @Test("Past thirty minutes the value is dropped for a last-reading label")
    func lastReadingBand() {
        #expect(GlucoseTimeline.render(snapshot, at: at(1801)) == .lastReading(age: "30m"))
        #expect(GlucoseTimeline.render(snapshot, at: at(7200)) == .lastReading(age: "2h"))
    }

    @Test("Never-recorded is distinct from last-reading at every age", arguments: [0.0, 900, 5000])
    func neverRecordedIsDistinct(_ age: TimeInterval) {
        let render = GlucoseTimeline.render(.neverRecorded, at: at(age))
        #expect(render == .neverRecorded)
        #expect(render != .lastReading(age: "0m"))
    }

    @Test("A fresh render carries no trend when the snapshot has none")
    func freshWithoutTrend() {
        let trendless = GlucoseSnapshot.make(
            mmolL: 11.2, readingDate: readingDate, trend: nil, status: .high)
        #expect(
            GlucoseTimeline.render(trendless, at: readingDate)
                == .fresh(value: "11.2", status: .high, trend: nil, provenance: .sensor))
    }

    @Test("The value is rendered to one decimal place")
    func valueFormatting() {
        let whole = GlucoseSnapshot.make(
            mmolL: 6, readingDate: readingDate, trend: nil, status: .inRange)
        #expect(
            GlucoseTimeline.render(whole, at: readingDate)
                == .fresh(value: "6.0", status: .inRange, trend: nil, provenance: .sensor))
    }

    // MARK: - Age string (Req 5.5)

    @Test(
        "Age reads in whole minutes for the first hour and whole hours beyond",
        arguments: [
            (1801.0, "30m"), (3540.0, "59m"), (3599.0, "59m"),
            (3600.0, "1h"), (7199.0, "1h"), (86_400.0, "24h")
        ] as [(TimeInterval, String)])
    func ageStrings(_ age: TimeInterval, _ expected: String) {
        #expect(GlucoseTimeline.render(snapshot, at: at(age)) == .lastReading(age: expected))
    }

    @Test("A future reading clamps to zero age and renders fresh")
    func futureReadingClampsToFresh() {
        #expect(
            GlucoseTimeline.render(snapshot, at: at(-600))
                == .fresh(value: "6.4", status: .inRange, trend: .risingSlow, provenance: .sensor))
    }

    // MARK: - renderPoints (Req 5.4)

    @Test("A fresh reading pre-bakes all three ladder steps")
    func renderPointsFromFresh() {
        let points = GlucoseTimeline.renderPoints(snapshot, from: readingDate)
        #expect(points.map(\.date) == [readingDate, at(901), at(1801)])
        #expect(points.map(\.render) == [
            .fresh(value: "6.4", status: .inRange, trend: .risingSlow, provenance: .sensor),
            .stale(value: "6.4", age: "15m", provenance: .sensor),
            .lastReading(age: "30m")
        ])
    }

    @Test("Boundaries already behind the reference are dropped, not repeated")
    func renderPointsFromStale() {
        let reference = at(1000)
        let points = GlucoseTimeline.renderPoints(snapshot, from: reference)
        #expect(points.map(\.date) == [reference, at(1801)])
        #expect(points.map(\.render) == [
            .stale(value: "6.4", age: "16m", provenance: .sensor),
            .lastReading(age: "30m")
        ])
    }

    @Test("A reading already past thirty minutes yields a single point")
    func renderPointsFromLastReading() {
        let reference = at(4000)
        let points = GlucoseTimeline.renderPoints(snapshot, from: reference)
        #expect(points.map(\.date) == [reference])
        #expect(points.map(\.render) == [.lastReading(age: "1h")])
    }

    @Test("Never-recorded yields a single point")
    func renderPointsFromNeverRecorded() {
        let points = GlucoseTimeline.renderPoints(.neverRecorded, from: readingDate)
        #expect(points.map(\.date) == [readingDate])
        #expect(points.map(\.render) == [.neverRecorded])
    }

    @Test("Points are strictly ascending in time")
    func renderPointsAreOrdered() {
        for offset in [-600.0, 0, 900, 901, 1500, 1801, 9000] {
            let dates = GlucoseTimeline.renderPoints(snapshot, from: at(offset)).map(\.date)
            #expect(dates == dates.sorted())
            #expect(Set(dates).count == dates.count)
        }
    }

    // MARK: - nextBoundary (Req 5.4)

    @Test("The next boundary walks the ladder and then stops")
    func nextBoundaryWalksTheLadder() {
        #expect(GlucoseTimeline.nextBoundary(snapshot, after: readingDate) == at(901))
        #expect(GlucoseTimeline.nextBoundary(snapshot, after: at(900)) == at(901))
        #expect(GlucoseTimeline.nextBoundary(snapshot, after: at(901)) == at(1801))
        #expect(GlucoseTimeline.nextBoundary(snapshot, after: at(1800)) == at(1801))
        #expect(GlucoseTimeline.nextBoundary(snapshot, after: at(1801)) == nil)
        #expect(GlucoseTimeline.nextBoundary(snapshot, after: at(9000)) == nil)
    }

    @Test("Never-recorded has no next boundary")
    func nextBoundaryOfNeverRecorded() {
        #expect(GlucoseTimeline.nextBoundary(.neverRecorded, after: readingDate) == nil)
    }

    @Test("The next boundary is the last point's successor state")
    func nextBoundaryAgreesWithRenderPoints() {
        // Whatever the last pre-baked point is, the boundary is either past it
        // (a further step exists) or nil (the ladder is done).
        for offset in [-600.0, 0, 900, 901, 1500, 1801, 9000] {
            let reference = at(offset)
            let last = GlucoseTimeline.renderPoints(snapshot, from: reference).map(\.date).last!
            if let boundary = GlucoseTimeline.nextBoundary(snapshot, after: last) {
                #expect(boundary > last)
            } else if case .lastReading = GlucoseTimeline.render(snapshot, at: last) {
                // Terminal state reached — nothing further to schedule.
            } else {
                Issue.record("no next boundary from \(last) but the ladder is not terminal")
            }
        }
    }

    // MARK: - Provenance on the render (fingerprick-glucose Reqs 3.5, 3.6)

    private var bloodSnapshot: GlucoseSnapshot {
        .make(
            mmolL: 9.1, readingDate: readingDate, trend: .steady, status: .inRange,
            provenance: .blood, holdsUntil: readingDate.addingTimeInterval(900))
    }

    @Test("A blood snapshot renders naming blood, in both value-carrying states")
    func bloodProvenanceIsNamed() {
        #expect(
            GlucoseTimeline.render(bloodSnapshot, at: readingDate)
                == .fresh(value: "9.1", status: .inRange, trend: .steady, provenance: .blood))
        #expect(
            GlucoseTimeline.render(bloodSnapshot, at: at(901))
                == .stale(value: "9.1", age: "15m", provenance: .blood))
    }

    // Req 7.1 reaching the render layer: a snapshot written by a build that
    // knew nothing of provenance carries nil, and must render as the sensor
    // reading it is rather than as an absent state.
    @Test("A snapshot with no provenance renders as sensor")
    func absentProvenanceRendersSensor() {
        #expect(
            GlucoseTimeline.render(snapshot, at: readingDate)
                == .fresh(value: "6.4", status: .inRange, trend: .risingSlow, provenance: .sensor))
    }

    // Req 3.6, and the trap the whole hold rule could have fallen into: the
    // ladder measures age from `readingDate`, NOT from `holdsUntil`. A blood
    // reading held for the full default window therefore reaches the fresh/
    // stale boundary at exactly 15 minutes, the coincidence Decision 3 chose
    // the default for — one second later it is stale, held or not.
    @Test("holdsUntil does not shift the staleness ladder")
    func holdDoesNotShiftTheLadder() {
        #expect(
            GlucoseTimeline.render(bloodSnapshot, at: at(900))
                == .fresh(value: "9.1", status: .inRange, trend: .steady, provenance: .blood))
        #expect(
            GlucoseTimeline.render(bloodSnapshot, at: at(901))
                == .stale(value: "9.1", age: "15m", provenance: .blood))
        #expect(GlucoseTimeline.nextBoundary(bloodSnapshot, after: readingDate) == at(901))
        // A window three times the default moves neither boundary.
        let longHold = GlucoseSnapshot.make(
            mmolL: 9.1, readingDate: readingDate, trend: .steady, status: .inRange,
            provenance: .blood, holdsUntil: readingDate.addingTimeInterval(2700))
        #expect(GlucoseTimeline.renderPoints(longHold, from: readingDate).map(\.date)
            == [readingDate, at(901), at(1801)])
    }

    // The value is dropped past thirty minutes, so there is no reported value
    // for a provenance to qualify (Req 3.5 binds surfaces REPORTING a value).
    @Test("The terminal states carry no provenance")
    func terminalStatesCarryNoProvenance() {
        #expect(GlucoseTimeline.render(bloodSnapshot, at: at(1801)) == .lastReading(age: "30m"))
        #expect(GlucoseTimeline.render(.neverRecorded, at: readingDate) == .neverRecorded)
    }
}

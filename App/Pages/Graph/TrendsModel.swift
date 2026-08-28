import Foundation
// `GlucoseReading` is re-exported by Persistence as a typealias, but a
// typealias only carries the NAME — its members need the defining module
// imported (it moved to GlucoseWidgetShared with the trend maths,
// glucose-lock-widget Decision 16).
import GlucoseWidgetShared
import Observation
import Persistence
import PortableContracts

// One plotted sample — a carb bar or a glucose-line vertex (design-handoff-00
// §10). Identifiable so `ForEach` inside `Chart` has stable identity.
struct TrendsChartPoint: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let value: Double
}

// One decoded insulin event for the selected range (PRD
// regression-suggestion-integration App 6/8). `kind` comes from the event's
// metadata JSON; rows whose metadata does not decode are dropped rather than
// crashing the chart.
struct InsulinEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let units: Double
    let kind: InsulinKind

    init(id: UUID, timestamp: Date, units: Double, kind: InsulinKind) {
        self.id = id
        self.timestamp = timestamp
        self.units = units
        self.kind = kind
    }

    // Decodes an `insulin` event row: `value` = units, metadata JSON carries
    // `kind` (medreg convention). Unknown metadata keys are ignored. The
    // decode lives on the type so Trends and Records read a dose row the same
    // way by construction — the two models used to hold byte-identical private
    // copies of it.
    init?(event: Event) {
        guard
            let units = event.value,
            let data = event.metadata.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let kindRaw = object["kind"] as? String,
            let kind = InsulinKind(rawValue: kindRaw)
        else { return nil }
        self.init(id: event.id, timestamp: event.timestamp, units: units, kind: kind)
    }
}

// One chart marker in the insulin band. Day range: one per dose, carrying its
// kind. Week/Month: one per non-empty day with the day's total units and a
// nil kind (a day can mix bolus and basal).
struct InsulinMarker: Identifiable {
    let id = UUID()
    let date: Date
    let units: Double
    let kind: InsulinKind?
}

// One decoded activity event for the selected range
// (specs/data/activity-events Req 4.1). `kind` comes from the event's metadata
// JSON and `durationMinutes` from `value`, which is absent when the duration
// was not recorded (Req 1.5) — nil here means unrecorded, never zero. Rows
// whose metadata does not decode are dropped, as the insulin rows are.
struct ActivityEntry: Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let kind: ActivityKind
    let durationMinutes: Double?

    init(id: UUID, timestamp: Date, kind: ActivityKind, durationMinutes: Double?) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.durationMinutes = durationMinutes
    }

    // Decodes an `activity` event row: `value` = duration in minutes and is
    // ABSENT when unrecorded (Req 1.5 — nil, never 0), metadata JSON carries
    // `kind` (specs/data/activity-events design §2). Same shape as
    // `InsulinEntry.init(event:)`, and on the type for the same reason; rows
    // that do not decode are dropped.
    init?(event: Event) {
        guard
            let data = event.metadata.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let kindRaw = object["kind"] as? String,
            let kind = ActivityKind(rawValue: kindRaw)
        else { return nil }
        self.init(
            id: event.id,
            timestamp: event.timestamp,
            kind: kind,
            durationMinutes: event.value
        )
    }

    // The activity's end, where a duration was recorded (Req 4.2).
    var endDate: Date? {
        durationMinutes.map { timestamp.addingTimeInterval($0 * 60) }
    }
}

// One chart marker in the activity band. Day range: one per activity, with
// `end` set where a duration exists so it draws as a span rather than a point
// (Req 4.2). Week/Month: one per non-empty day carrying that day's activity
// count, with a nil kind and a nil end (a day can mix kinds).
struct ActivityMarker: Identifiable {
    let id = UUID()
    let date: Date
    let end: Date?
    let kind: ActivityKind?
    let count: Int
}

// View-model for the Trends screen (§10). Loads meals, `bsl` glucose, and
// `insulin` doses for the selected range, refreshes on `eventsDidChange`, and
// exposes chart series and summary stats. All bucketing / axis maths comes from
// `TrendsMath` (MedataCore) — this type only shapes store rows into plottable
// points.
@Observable
@MainActor
final class TrendsModel {
    var range: TrendsRange = .day
    private(set) var meals: [MealRecord] = []
    private(set) var glucose: [GlucoseReading] = []
    private(set) var insulin: [InsulinEntry] = []
    // Activity events for the selected range (specs/data/activity-events
    // Req 4.1). Recorded only — nothing on this screen derives a dose from
    // them (Req 5.3 / Decision 5).
    private(set) var activities: [ActivityEntry] = []
    // Manual carb entries for the selected range (manual-carb-intake Req 6.2).
    // Kept as (date, value) pairs — a bare [Double] cannot feed either Day's
    // per-entry TrendsChartPoint or Week/Month's dailyBuckets, both of which
    // need a date per sample.
    private(set) var intakeCarbs: [DatedValue] = []

    // Chart series and axis maxima are shaped ONCE per reload and stored, not
    // recomputed on every access. They were computed properties, and the chart
    // body reads them quadratically — `mappedCarb` calls `carbAxisMax` (→
    // `carbBars`) once per bar, each axis tick re-derives them, and every access
    // re-ran `TrendsMath.dailyBuckets` and minted fresh point UUIDs. On Month
    // (≈30 day-buckets over a month of seeded glucose) that blew up into a
    // multi-second main-thread render that froze the range picker mid-selection.
    // Storing them collapses each render to array reads with stable identity.
    // Bug `graph-month-selection-hang` 2026-07-06.
    private(set) var carbBars: [TrendsChartPoint] = []
    private(set) var glucoseLine: [TrendsChartPoint] = []
    // Blood readings, at their own instants, in every range (Req 4.2). Separate
    // from `glucoseLine` because they are a different measurement, not another
    // vertex of the same trace: interpolating a fingerstick into the sensor
    // line would draw a step between two modalities as though glucose had
    // moved. Unbucketed even on week and month, where the line is daily
    // averages — a fingerstick is a discrete event, like an insulin dose.
    private(set) var bloodPoints: [TrendsChartPoint] = []
    private(set) var insulinMarkers: [InsulinMarker] = []
    private(set) var activityMarkers: [ActivityMarker] = []
    private(set) var carbAxisMax: Double = 0
    private(set) var autoGlucoseMax: Double = 0
    // Corrections overlay (snaqui PRD Req 3): the latest correction's total per
    // meal, mirroring MealHistoryModel/RecordsModel (Decision 13), so the carb
    // bars and the day-meal list plot what was eaten, not the raw estimate.
    private var correctedTotals: [UUID: Double] = [:]

    private let store: any PersistenceStore
    private let calendar = Calendar.current
    private var subscription: Task<Void, Never>?

    init(store: any PersistenceStore) {
        self.store = store
    }

    func start() async {
        await reload()
        subscription?.cancel()
        let stream = store.eventsDidChange
        subscription = Task { [weak self] in
            for await _ in stream {
                guard let self else { return }
                await self.reload()
            }
        }
    }

    func cancel() {
        subscription?.cancel()
        subscription = nil
    }

    // The calendar interval enclosing today for the selected range.
    var interval: DateInterval {
        TrendsMath.rangeInterval(for: range, containing: Date(), calendar: calendar)
    }

    func reload() async {
        let iv = interval
        let allMeals = (try? await store.allMeals()) ?? []
        meals = allMeals.filter { iv.contains($0.createdAt) }
        var corrected: [UUID: Double] = [:]
        for record in meals {
            let corrections = (try? await store.corrections(for: record.id)) ?? []
            if let total = corrections.last(where: { $0.correctedTotalCarbsGOneof != nil })?.correctedTotalCarbsG {
                corrected[record.id] = Double(total)
            }
        }
        correctedTotals = corrected
        // §10.9 / Error handling: a corrupt-record throw yields an empty series
        // and the carb chart still renders — never a crash.
        let events = (try? await store.events(in: iv.start...iv.end, type: EventType.bsl)) ?? []
        // `reading(from:)` carries `metadata.provenance` onto each row
        // (fingerprick-glucose Req 4.2). Shared with the snapshot derivation
        // and the Records row rather than re-spelled here: one place decides
        // that an absent key is a sensor reading.
        glucose = events.compactMap(GlucoseSnapshotSource.reading(from:))
        let doses = (try? await store.events(in: iv.start...iv.end, type: EventType.insulin)) ?? []
        insulin = doses.compactMap(InsulinEntry.init(event:))
        let activityEvents =
            (try? await store.events(in: iv.start...iv.end, type: EventType.activity)) ?? []
        activities = activityEvents.compactMap(ActivityEntry.init(event:))
        // `value` is already the validated carb figure written at save time
        // (manual-carb-intake design: Carb totals and graph series) — no
        // metadata decode needed for plotting.
        let intakeEvents = (try? await store.events(in: iv.start...iv.end, type: EventType.intake)) ?? []
        intakeCarbs = intakeEvents.compactMap { event in
            event.value.map { DatedValue(date: event.timestamp, value: $0) }
        }
        recomputeSeries(in: iv)
    }

    // Shape the raw rows into plottable series once, after a reload. Everything
    // here was previously a computed property re-evaluated on every chart-body
    // access (see the `carbBars` doc comment).
    private func recomputeSeries(in iv: DateInterval) {
        // The trace is the SENSOR series alone, which is what draws it unbroken
        // across the instant of a blood reading (Req 4.2): a blood vertex
        // spliced into the line would break the trace at exactly the moment the
        // requirement asks it to stay continuous. Neither series is filtered
        // out of `glucose`, so the stat cards and Records still see every
        // reading (Req 4.1).
        let sensor = glucose.filter { $0.provenance == .sensor }
        bloodPoints = glucose
            .filter { $0.provenance == .blood }
            .map { TrendsChartPoint(date: $0.timestamp, value: $0.mmolL) }
        switch range {
        case .day:
            // One bar per entry regardless of source — one carb series, not
            // two (manual-carb-intake Req 6.2).
            carbBars = meals.map { TrendsChartPoint(date: $0.createdAt, value: carbTotal($0)) }
                + intakeCarbs.map { TrendsChartPoint(date: $0.date, value: $0.value) }
            glucoseLine = sensor
                .sorted { $0.timestamp < $1.timestamp }
                .map { TrendsChartPoint(date: $0.timestamp, value: $0.mmolL) }
            insulinMarkers = insulin.map {
                InsulinMarker(date: $0.timestamp, units: $0.units, kind: $0.kind)
            }
            // One marker per activity, carrying its end where a duration was
            // recorded so the chart can draw the span rather than a point
            // (Req 4.2).
            activityMarkers = activities.map {
                ActivityMarker(date: $0.timestamp, end: $0.endDate, kind: $0.kind, count: 1)
            }
        case .week, .month:
            // Meal and intake samples combine BEFORE bucketing, so a day's
            // bucket total is one number regardless of how many sources
            // contributed to it (manual-carb-intake Req 6.2).
            let carbSamples = meals.map { DatedValue(date: $0.createdAt, value: carbTotal($0)) }
                + intakeCarbs
            carbBars = TrendsMath.dailyBuckets(carbSamples, in: iv, calendar: calendar)
                .map { TrendsChartPoint(date: $0.start, value: $0.total) }
            let glucoseSamples = sensor.map { DatedValue(date: $0.timestamp, value: $0.mmolL) }
            glucoseLine = TrendsMath.dailyBuckets(glucoseSamples, in: iv, calendar: calendar)
                .compactMap { bucket in
                    bucket.average.map { TrendsChartPoint(date: bucket.start, value: $0) }
                }
            let insulinSamples = insulin.map { DatedValue(date: $0.timestamp, value: $0.units) }
            insulinMarkers = TrendsMath.dailyBuckets(insulinSamples, in: iv, calendar: calendar)
                .filter { $0.count > 0 }
                .map { InsulinMarker(date: $0.start, units: $0.total, kind: nil) }
            // Per-day COUNT, not a duration total: an unrecorded duration is
            // absent rather than zero (Req 1.5), so summing minutes across a
            // week would silently under-report the days that carry no
            // duration. The bucket's own `count` needs no sample value, so
            // the samples carry a constant.
            let activitySamples = activities.map { DatedValue(date: $0.timestamp, value: 1) }
            activityMarkers = TrendsMath.dailyBuckets(activitySamples, in: iv, calendar: calendar)
                .filter { $0.count > 0 }
                .map { ActivityMarker(date: $0.start, end: nil, kind: nil, count: $0.count) }
        }
        carbAxisMax = TrendsMath.carbAxisMax(forMaxCarbs: carbBars.map(\.value).max() ?? 0)
        // Both series, or a blood reading above the sensor trace's peak would
        // be plotted off the top of an auto-scaled chart.
        let dataMax = (glucoseLine + bloodPoints).map(\.value).max() ?? 0
        autoGlucoseMax = max(TrendsMath.targetHighMmolL + 2, (dataMax + 1).rounded(.up))
    }

    // Removes one dose; the chart marker and the day list refresh together
    // through the store's `eventsDidChange` tick (App 8).
    func deleteDose(id: UUID) async {
        try? await store.deleteInsulinEvent(id: id)
    }

    // MARK: - Summary stats (§10.5)

    var hasGlucose: Bool { !glucose.isEmpty }

    var totalCarbs: Double { carbBars.reduce(0) { $0 + $1.value } }

    var avgCarbsPerDay: Double { totalCarbs / Double(dayCount) }

    var timeInRange: Double? { TrendsMath.timeInRange(glucose) }

    var averageGlucose: Double? {
        guard !glucose.isEmpty else { return nil }
        return glucose.reduce(0) { $0 + $1.mmolL } / Double(glucose.count)
    }

    // Total insulin over the selected range, for the stat card (App 9).
    var totalInsulinUnits: Double { insulin.reduce(0) { $0 + $1.units } }

    // The day's meals, newest first, for the Day-view list (§10.6).
    var dayMeals: [MealRecord] {
        meals.sorted { $0.createdAt > $1.createdAt }
    }

    // The day's doses, newest first, for the Day-view Insulin list (App 8).
    var dayDoses: [InsulinEntry] {
        insulin.sorted { $0.timestamp > $1.timestamp }
    }

    // The day's activities, newest first, for the Day-view Activity list
    // (specs/data/activity-events Req 4.3).
    var dayActivities: [ActivityEntry] {
        activities.sorted { $0.timestamp > $1.timestamp }
    }

    private var dayCount: Int {
        let start = calendar.startOfDay(for: interval.start)
        let days = calendar.dateComponents([.day], from: start, to: interval.end).day ?? 1
        return max(1, days)
    }

    private func carbTotal(_ record: MealRecord) -> Double {
        correctedTotals[record.id] ?? Double(record.macros.totalCarbsG)
    }

    // Corrected-when-present total for a day-list row, rounded for display.
    func displayCarbs(for record: MealRecord) -> Int {
        Int(carbTotal(record).rounded())
    }
}

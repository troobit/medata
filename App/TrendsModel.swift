import Foundation
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
    private(set) var insulinMarkers: [InsulinMarker] = []
    private(set) var carbAxisMax: Double = 0
    private(set) var autoGlucoseMax: Double = 0

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
        // §10.9 / Error handling: a corrupt-record throw yields an empty series
        // and the carb chart still renders — never a crash.
        let events = (try? await store.events(in: iv.start...iv.end, type: EventType.bsl)) ?? []
        glucose = events.compactMap { event in
            event.value.map { GlucoseReading(timestamp: event.timestamp, mmolL: $0) }
        }
        let doses = (try? await store.events(in: iv.start...iv.end, type: EventType.insulin)) ?? []
        insulin = doses.compactMap(Self.insulinEntry(from:))
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
        switch range {
        case .day:
            // One bar per entry regardless of source — one carb series, not
            // two (manual-carb-intake Req 6.2).
            carbBars = meals.map { TrendsChartPoint(date: $0.createdAt, value: carbTotal($0)) }
                + intakeCarbs.map { TrendsChartPoint(date: $0.date, value: $0.value) }
            glucoseLine = glucose
                .sorted { $0.timestamp < $1.timestamp }
                .map { TrendsChartPoint(date: $0.timestamp, value: $0.mmolL) }
            insulinMarkers = insulin.map {
                InsulinMarker(date: $0.timestamp, units: $0.units, kind: $0.kind)
            }
        case .week, .month:
            // Meal and intake samples combine BEFORE bucketing, so a day's
            // bucket total is one number regardless of how many sources
            // contributed to it (manual-carb-intake Req 6.2).
            let carbSamples = meals.map { DatedValue(date: $0.createdAt, value: carbTotal($0)) }
                + intakeCarbs
            carbBars = TrendsMath.dailyBuckets(carbSamples, in: iv, calendar: calendar)
                .map { TrendsChartPoint(date: $0.start, value: $0.total) }
            let glucoseSamples = glucose.map { DatedValue(date: $0.timestamp, value: $0.mmolL) }
            glucoseLine = TrendsMath.dailyBuckets(glucoseSamples, in: iv, calendar: calendar)
                .compactMap { bucket in
                    bucket.average.map { TrendsChartPoint(date: bucket.start, value: $0) }
                }
            let insulinSamples = insulin.map { DatedValue(date: $0.timestamp, value: $0.units) }
            insulinMarkers = TrendsMath.dailyBuckets(insulinSamples, in: iv, calendar: calendar)
                .filter { $0.count > 0 }
                .map { InsulinMarker(date: $0.start, units: $0.total, kind: nil) }
        }
        carbAxisMax = TrendsMath.carbAxisMax(forMaxCarbs: carbBars.map(\.value).max() ?? 0)
        let dataMax = glucoseLine.map(\.value).max() ?? 0
        autoGlucoseMax = max(TrendsMath.targetHighMmolL + 2, (dataMax + 1).rounded(.up))
    }

    // Decodes an `insulin` event row: `value` = units, metadata JSON carries
    // `kind` (medreg convention). Unknown metadata keys are ignored.
    private static func insulinEntry(from event: Event) -> InsulinEntry? {
        guard
            let units = event.value,
            let data = event.metadata.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let kindRaw = object["kind"] as? String,
            let kind = InsulinKind(rawValue: kindRaw)
        else { return nil }
        return InsulinEntry(id: event.id, timestamp: event.timestamp, units: units, kind: kind)
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

    private var dayCount: Int {
        let start = calendar.startOfDay(for: interval.start)
        let days = calendar.dateComponents([.day], from: start, to: interval.end).day ?? 1
        return max(1, days)
    }

    private func carbTotal(_ record: MealRecord) -> Double {
        Double(record.macros.totalCarbsG)
    }
}

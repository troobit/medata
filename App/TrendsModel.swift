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

    // MARK: - Chart series

    // Day: one bar per meal at its timestamp. Week/Month: one bar per day with
    // the day's total carbs (§10.2/§10.3).
    var carbBars: [TrendsChartPoint] {
        switch range {
        case .day:
            return meals.map { TrendsChartPoint(date: $0.createdAt, value: carbTotal($0)) }
        case .week, .month:
            let samples = meals.map { DatedValue(date: $0.createdAt, value: carbTotal($0)) }
            return TrendsMath.dailyBuckets(samples, in: interval, calendar: calendar)
                .map { TrendsChartPoint(date: $0.start, value: $0.total) }
        }
    }

    // Day: raw readings. Week/Month: per-day average glucose, empty days dropped
    // so the line has no false zero dips (§10.3).
    var glucoseLine: [TrendsChartPoint] {
        switch range {
        case .day:
            return glucose
                .sorted { $0.timestamp < $1.timestamp }
                .map { TrendsChartPoint(date: $0.timestamp, value: $0.mmolL) }
        case .week, .month:
            let samples = glucose.map { DatedValue(date: $0.timestamp, value: $0.mmolL) }
            return TrendsMath.dailyBuckets(samples, in: interval, calendar: calendar)
                .compactMap { bucket in
                    bucket.average.map { TrendsChartPoint(date: bucket.start, value: $0) }
                }
        }
    }

    // Day: one marker per dose at its administration time. Week/Month: one
    // marker per non-empty day carrying the day's total units, x-aligned with
    // the carb bars' day buckets (App 6).
    var insulinMarkers: [InsulinMarker] {
        switch range {
        case .day:
            return insulin.map {
                InsulinMarker(date: $0.timestamp, units: $0.units, kind: $0.kind)
            }
        case .week, .month:
            let samples = insulin.map { DatedValue(date: $0.timestamp, value: $0.units) }
            return TrendsMath.dailyBuckets(samples, in: interval, calendar: calendar)
                .filter { $0.count > 0 }
                .map { InsulinMarker(date: $0.start, units: $0.total, kind: nil) }
        }
    }

    // MARK: - Axes

    var carbAxisMax: Double {
        TrendsMath.carbAxisMax(forMaxCarbs: carbBars.map(\.value).max() ?? 0)
    }

    // Auto glucose maximum: covers the data and keeps the target band's top edge
    // (10.0) visible. The Fixed option overrides this in the view.
    var autoGlucoseMax: Double {
        let dataMax = glucoseLine.map(\.value).max() ?? 0
        return max(TrendsMath.targetHighMmolL + 2, (dataMax + 1).rounded(.up))
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

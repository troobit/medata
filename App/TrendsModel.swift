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

// View-model for the Trends screen (§10). Loads meals and `bsl` glucose for the
// selected range, refreshes on `eventsDidChange`, and exposes chart series and
// summary stats. All bucketing / axis maths comes from `TrendsMath` (MedataCore)
// — this type only shapes store rows into plottable points.
@Observable
@MainActor
final class TrendsModel {
    var range: TrendsRange = .day
    private(set) var meals: [MealRecord] = []
    private(set) var glucose: [GlucoseReading] = []

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

    // The day's meals, newest first, for the Day-view list (§10.6).
    var dayMeals: [MealRecord] {
        meals.sorted { $0.createdAt > $1.createdAt }
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

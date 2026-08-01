import Foundation
// Leaf enums only (GlucoseTrend / GlucoseBandStatus). GlucoseWidgetShared is
// Foundation-only with an empty dependency list, so this edge adds nothing to
// the estimation link closure (glucose-lock-widget Decision 10).
import GlucoseWidgetShared

// Pure maths for the Trends surface (UI Design Handoff 00, Reqs 10.2/10.3/10.5).
// No UI imports and no store access — the App's TrendsModel feeds it plain
// values and renders the result. It lives in the Persistence module so the
// existing MedataCore test suite covers it and the App imports it alongside the
// store.

// A single glucose reading in mmol/L (the value carried by `bsl` events).
public struct GlucoseReading: Sendable, Equatable {
    public let timestamp: Date
    public let mmolL: Double

    public init(timestamp: Date, mmolL: Double) {
        self.timestamp = timestamp
        self.mmolL = mmolL
    }
}

// A dated scalar for bucketing (e.g. a meal's carbs at its capture time).
public struct DatedValue: Sendable, Equatable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

// The three selectable ranges (Req 10.1).
public enum TrendsRange: Sendable, Equatable, CaseIterable {
    case day, week, month
}

// One calendar-day bucket of aggregated samples (Req 10.3). `average` is nil
// for an empty day so callers can drop the point from a line series.
public struct TrendsBucket: Sendable, Equatable {
    public let start: Date
    public let total: Double
    public let average: Double?
    public let count: Int

    public init(start: Date, total: Double, average: Double?, count: Int) {
        self.start = start
        self.total = total
        self.average = average
        self.count = count
    }
}

public enum TrendsMath {

    // The target band (Req 10.2/10.5).
    public static let targetLowMmolL = 3.9
    public static let targetHighMmolL = 10.0

    // Gaps longer than this are excluded from time-in-range (Req 10.5).
    public static let maxGapSeconds: TimeInterval = 60 * 60

    // MARK: - Time in range (Req 10.5)

    // Time-weighted fraction (0...1) of the covered span whose interpolated
    // glucose lies in `[low, high]`. Between consecutive readings the value is
    // linear, so the in-band sub-duration is found from the exact crossing
    // points rather than an all-or-nothing test. Intervals whose gap exceeds
    // `maxGap` are excluded from BOTH numerator and denominator. Returns nil
    // when no interval qualifies (Req 10.5 `—`).
    public static func timeInRange(
        _ readings: [GlucoseReading],
        low: Double = targetLowMmolL,
        high: Double = targetHighMmolL,
        maxGap: TimeInterval = maxGapSeconds
    ) -> Double? {
        let sorted = readings.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2 else { return nil }

        var numerator: TimeInterval = 0
        var denominator: TimeInterval = 0

        for (a, b) in zip(sorted, sorted.dropFirst()) {
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard dt > 0, dt <= maxGap else { continue }
            denominator += dt
            numerator += inBandDuration(
                v0: a.mmolL, v1: b.mmolL, dt: dt, low: low, high: high
            )
        }

        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    // Duration within one linear interval [0, dt] where the value lies in
    // [low, high]. The value goes v0 -> v1 linearly, so the in-band set is a
    // single contiguous sub-interval in fraction space.
    private static func inBandDuration(
        v0: Double, v1: Double, dt: TimeInterval, low: Double, high: Double
    ) -> TimeInterval {
        let dv = v1 - v0
        if dv == 0 {
            return (v0 >= low && v0 <= high) ? dt : 0
        }
        // Fractions at which the value equals each band edge.
        let fAtLow = (low - v0) / dv
        let fAtHigh = (high - v0) / dv
        let lowerFraction = max(0.0, min(fAtLow, fAtHigh))
        let upperFraction = min(1.0, max(fAtLow, fAtHigh))
        let span = upperFraction - lowerFraction
        return span > 0 ? span * dt : 0
    }

    // MARK: - Bucketing (Req 10.3)

    // Calendar interval enclosing `date` for the given range.
    public static func rangeInterval(
        for range: TrendsRange, containing date: Date, calendar: Calendar
    ) -> DateInterval {
        let component: Calendar.Component
        switch range {
        case .day: component = .day
        case .week: component = .weekOfYear
        case .month: component = .month
        }
        // dateInterval(of:for:) is defined for these components; fall back to a
        // single day if the calendar ever declines (it will not for gregorian).
        return calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: calendar.startOfDay(for: date), duration: 24 * 60 * 60)
    }

    // One bucket per calendar day spanning `interval`, aggregating the samples
    // that fall in each day. Empty days are present with total 0 and nil
    // average so the carb bars and glucose line share an unbroken axis.
    public static func dailyBuckets(
        _ samples: [DatedValue], in interval: DateInterval, calendar: Calendar
    ) -> [TrendsBucket] {
        var dayStarts: [Date] = []
        var cursor = calendar.startOfDay(for: interval.start)
        while cursor < interval.end {
            dayStarts.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        return dayStarts.map { dayStart in
            let dayItems = samples.filter {
                calendar.isDate($0.date, inSameDayAs: dayStart)
            }
            let total = dayItems.reduce(0) { $0 + $1.value }
            let average = dayItems.isEmpty ? nil : total / Double(dayItems.count)
            return TrendsBucket(
                start: dayStart, total: total, average: average, count: dayItems.count
            )
        }
    }

    // MARK: - Glucose trend (glucose-lock-widget Reqs 3.1-3.4, Decision 4)

    // Band edges on |rate|, in mmol/L per minute. Half-open: a boundary value
    // belongs to the faster band.
    public static let slowRateThreshold = 0.056
    public static let mediumRateThreshold = 0.111
    public static let fastRateThreshold = 0.166

    // Slope of a least-squares fit over the readings in the closed window
    // [now − window, now], in mmol/L per minute. Anchoring to `now` rather than
    // to the latest reading keeps trend and staleness on the same clock, so a
    // lagging reading cannot report a trend the staleness ladder already calls
    // stale.
    //
    // nil unless at least two readings fall in the window AND the earliest and
    // latest span `minSpan` — two near-simultaneous readings would otherwise
    // amplify a millimole of noise into a spurious fast arrow.
    public static func glucoseRate(
        _ readings: [GlucoseReading], now: Date,
        window: TimeInterval = 15 * 60, minSpan: TimeInterval = 10 * 60
    ) -> Double? {
        let windowStart = now.addingTimeInterval(-window)
        let inWindow = readings
            .filter { $0.timestamp >= windowStart && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }

        guard let earliest = inWindow.first, let latest = inWindow.last,
              inWindow.count >= 2,
              latest.timestamp.timeIntervalSince(earliest.timestamp) >= minSpan
        else { return nil }

        // x in minutes from the earliest in-window reading, so the slope is
        // already per-minute.
        let xs = inWindow.map { $0.timestamp.timeIntervalSince(earliest.timestamp) / 60 }
        let ys = inWindow.map(\.mmolL)
        let xMean = xs.reduce(0, +) / Double(xs.count)
        let yMean = ys.reduce(0, +) / Double(ys.count)

        var covariance = 0.0
        var variance = 0.0
        for (x, y) in zip(xs, ys) {
            covariance += (x - xMean) * (y - yMean)
            variance += (x - xMean) * (x - xMean)
        }
        guard variance > 0 else { return nil }
        return covariance / variance
    }

    // The rate → arrow-state map. Split out from `trend(_:now:)` so the band
    // edges are testable as exact values, with no floating-point reconstruction
    // from timestamps in between.
    public static func trend(forRate rate: Double) -> GlucoseTrend {
        let rising = rate > 0
        switch abs(rate) {
        case ..<slowRateThreshold: return .steady
        case ..<mediumRateThreshold: return rising ? .risingSlow : .fallingSlow
        case ..<fastRateThreshold: return rising ? .rising : .falling
        default: return rising ? .risingFast : .fallingFast
        }
    }

    // nil when no rate qualifies (Reqs 3.3, 3.4) — the widget then shows the
    // value with no arrow.
    public static func trend(_ readings: [GlucoseReading], now: Date) -> GlucoseTrend? {
        guard let rate = glucoseRate(readings, now: now) else { return nil }
        return trend(forRate: rate)
    }

    // The reading's position against the target band (Req 4.1). Runs on the raw
    // value while the widget shows one decimal place, so a raw 3.87 displays
    // "3.9" yet carries the low token — the raw-value band is the authority at
    // the boundary.
    public static func bandStatus(_ mmolL: Double) -> GlucoseBandStatus {
        if mmolL < targetLowMmolL { return .low }
        if mmolL > targetHighMmolL { return .high }
        return .inRange
    }

    // MARK: - Carb axis mapping (Req 10.2)

    // Dynamic carb-axis maximum: floors at 80 g and rounds up to the next 20 g
    // so the tallest bar never clips.
    public static func carbAxisMax(forMaxCarbs maxCarbs: Double) -> Double {
        let rounded = (maxCarbs / 20).rounded(.up) * 20
        return max(80, rounded)
    }

    // Maps a carb value (g) onto the shared glucose axis (single-scale
    // workaround). Round-trips exactly with `mapAxisToCarbs`.
    public static func mapCarbsToAxis(
        _ carbs: Double, carbAxisMax: Double, glucoseAxisMax: Double
    ) -> Double {
        guard carbAxisMax > 0 else { return 0 }
        return carbs / carbAxisMax * glucoseAxisMax
    }

    // Inverse of `mapCarbsToAxis`, used to relabel the trailing axis in grams.
    public static func mapAxisToCarbs(
        _ axisValue: Double, carbAxisMax: Double, glucoseAxisMax: Double
    ) -> Double {
        guard glucoseAxisMax > 0 else { return 0 }
        return axisValue / glucoseAxisMax * carbAxisMax
    }
}

// The pure path from readings to a `GlucoseSnapshot`, shared by the app and the
// MeDataWidgets extension (glucose-lock-widget Decision 16).
//
// It used to live in `Persistence` (`TrendsMath`, `GlucoseSnapshotSource`) and
// `GlucoseIngestion` (`snapToGrid`), which was fine while the app was the only
// thing that derived a snapshot. Once the widget derives its own from a
// vendor fetch (Req 6.2) both surfaces must preprocess and classify identically
// — two copies of the grid snapping or the threshold map is exactly how the
// arrow starts disagreeing across the lock screen and the app for the same
// data. `Persistence` and `GlucoseIngestion` keep thin wrappers, so app-side
// callers did not change.
//
// Foundation only, per this module's standing constraints.
import Foundation

// How a reading was measured (specs/data/fingerprick-glucose Decision 4).
// Two values and no more: a meter sample arriving through Apple Health and a
// hand-entered fingerstick are one behavioural class, separated only by the
// route recorded in `metadata.source_id`.
//
// Stored form is the `bsl` event's `metadata.provenance`. The key being ABSENT
// means sensor, which is what makes Req 7.1 free — every reading recorded
// before this feature reads back as a sensor reading with nothing rewritten.
public enum GlucoseProvenance: String, Codable, Sendable, CaseIterable {
    case sensor, blood
}

// A single glucose reading in mmol/L (the value carried by `bsl` events).
public struct GlucoseReading: Sendable, Equatable {
    public let timestamp: Date
    public let mmolL: Double
    public let provenance: GlucoseProvenance

    // `provenance` is defaulted so every existing construction site — the
    // widget extension's vendor fetch, the Graph, Records — compiles unchanged
    // and keeps meaning what it meant. Sensor is also the fail-safe direction:
    // a reading mistaken for blood would earn a hold it has not measured.
    public init(timestamp: Date, mmolL: Double, provenance: GlucoseProvenance = .sensor) {
        self.timestamp = timestamp
        self.mmolL = mmolL
        self.provenance = provenance
    }
}

// The 5-minute dedup grid (cgm-connect Decision 4) and the single value
// rounding point (cgm-connect Req 5.5). The widget applies both before deriving
// so its snapshot is built from the same numbers the ingest path would store.
public enum GlucoseGrid {

    public static let gridMs: Int64 = 5 * 60 * 1000

    // Nearest 5-minute grid mark; an instant exactly halfway between two
    // marks rounds to the LATER mark (deterministic half-to-later).
    public static func snapToGrid(_ instantMs: Int64) -> Int64 {
        let shifted = instantMs + gridMs / 2
        let floored =
            shifted >= 0
            ? shifted / gridMs
            : (shifted - gridMs + 1) / gridMs
        return floored * gridMs
    }

    public static func snap(_ instant: Date) -> Date {
        Date(timeIntervalSince1970: Double(snapToGrid(instantMs(instant))) / 1000)
    }

    public static func instantMs(_ instant: Date) -> Int64 {
        Int64((instant.timeIntervalSince1970 * 1000).rounded())
    }

    // One decimal, applied before anything compares or displays the value.
    public static func roundedMmolL(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    // mg/dL → mmol/L (cgm-connect Req 5.5). Here rather than beside either
    // caller because both the ingest path and the widget's own fetch convert
    // vendor values, and a divisor that differs by a digit between them would
    // show up as two surfaces disagreeing about the same reading.
    public static let mgPerDlPerMmolL = 18.0182

    public static func mmolL(fromMgPerDl value: Double) -> Double {
        value / mgPerDlPerMmolL
    }
}

// The trend arrow and target-band maths (Reqs 3.1-3.4, 4.1; Decision 4).
public enum GlucoseTrendMath {

    // The target band (design-handoff-00 Req 10.2/10.5, reused by Req 4.1).
    public static let targetLowMmolL = 3.9
    public static let targetHighMmolL = 10.0

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
    // amplify a millimole of noise into a spurious fast arrow. The ≥2-readings
    // guard also covers Req 3.4: a latest reading older than the window leaves
    // fewer than 2 readings in it.
    //
    // The window is 30 minutes, not the 15 the spec first assumed, because the
    // LibreLinkUp feed does not deliver a reading every 5 minutes. Measured
    // over 282 live rows on the primary device (2026-08-05), the gap between
    // consecutive readings was 15 minutes in 152 cases, 5 in 96 and 10 in 31 —
    // so a 15-minute window usually holds ONE reading and the arrow almost
    // never appeared: derivable in 33.5 % of the minutes when the reading was
    // fresh enough to display, against 99.1 % at 30 minutes. 30 is twice the
    // modal cadence, which is what makes two consecutive readings always fit;
    // 45 minutes adds 0.1 % and only lengthens the baseline. The cost is a
    // slower arrow — see glucose-lock-widget Decision 15 and task 15, which
    // re-derives the thresholds against the cadence the shared 5-minute poll
    // actually produces.
    public static func glucoseRate(
        _ readings: [GlucoseReading], now: Date,
        window: TimeInterval = 30 * 60, minSpan: TimeInterval = 10 * 60
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
}

// The readings → snapshot step, shared by the app's publisher (via
// `GlucoseSnapshotSource`, which adds the store read) and the widget's
// extension-side fetch (which adds the vendor call).
public enum GlucoseDerivation {

    // Precedence (Reqs 3.1, 3.3, 3.4, 3.9) plus the single-provenance trend.
    // `readings` is expected in ascending timestamp order — the store's
    // `(timestamp ASC, id ASC)` order — so the last row is the most recent one.
    //
    // `holdWindow` is deliberately NOT defaulted. The widget extension holds no
    // blood readings at all (its vendor fetch is sensor data by construction),
    // so it passes 0 and gets today's behaviour exactly; the app passes the
    // setting. A default would let a caller acquire hold semantics by accident.
    public static func snapshot(
        from readings: [GlucoseReading], now: Date, holdWindow: TimeInterval
    ) -> GlucoseSnapshot {
        guard let latest = readings.last else { return .neverRecorded }

        // The one comparison that decides the hold. Req 3.9 needs no branch of
        // its own: a reading back-dated further than the window simply is not
        // inside it. Strict, so Req 3.3's "when the window HAS elapsed" resumes
        // the sensor reading at the boundary rather than one tick later.
        let windowStart = now.addingTimeInterval(-holdWindow)
        let holding = readings.last {
            $0.provenance == .blood && $0.timestamp > windowStart
        }

        let displayed = holding ?? latest
        return GlucoseSnapshot.make(
            mmolL: displayed.mmolL,
            readingDate: displayed.timestamp,
            trend: trend(from: readings, now: now),
            status: GlucoseTrendMath.bandStatus(displayed.mmolL),
            provenance: displayed.provenance,
            // Absolute, and only while a hold is actually in force: a blood
            // reading displayed merely for want of anything newer has nothing
            // to protect against (Decision 8).
            holdsUntil: holding.map { $0.timestamp.addingTimeInterval(holdWindow) }
        )
    }

    // The trend over ONE provenance at a time (Req 5.1, Decision 7).
    //
    // A fingerstick dropped into a regression over interstitial values does not
    // measure a change in glucose; it measures the gap between two measurement
    // modalities, and the arrow would report that gap as a rate. So the sensor
    // series is regressed alone. When it cannot satisfy the existing
    // count-and-span rules — no sensor connected, session ended — the blood
    // readings are regressed alone under those same rules, because fingersticks
    // against fingersticks carry no such step. A mixed series is never
    // regressed, and when neither provenance qualifies there is no trend
    // (Req 5.2).
    //
    // Sensor-first rather than newest-first, so entering one blood reading
    // cannot flip a live arrow onto a sparse blood regression.
    public static func trend(from readings: [GlucoseReading], now: Date) -> GlucoseTrend? {
        if let sensorTrend = GlucoseTrendMath.trend(
            readings.filter { $0.provenance == .sensor }, now: now) {
            return sensorTrend
        }
        return GlucoseTrendMath.trend(
            readings.filter { $0.provenance == .blood }, now: now)
    }
}

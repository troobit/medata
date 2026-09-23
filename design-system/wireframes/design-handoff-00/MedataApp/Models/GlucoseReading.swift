import Foundation

/// A single blood-glucose reading imported from an external device
/// (CGM or meter). Medata is strictly read-only over this data.
struct GlucoseReading: Hashable, Identifiable {
    let id: UUID
    let takenAt: Date
    let mmolPerL: Double
    let source: String            // e.g. "CGM · Dexcom G7", "Meter · manual"

    init(id: UUID = UUID(), takenAt: Date, mmolPerL: Double, source: String) {
        self.id = id
        self.takenAt = takenAt
        self.mmolPerL = mmolPerL
        self.source = source
    }
}

/// Import boundary for glucose data. Production implementations wrap
/// HealthKit / vendor SDKs; the wireframe uses a deterministic mock.
protocol GlucoseSource {
    /// Readings within the given interval, ascending by time.
    func readings(in interval: DateInterval) async throws -> [GlucoseReading]
}

/// Deterministic mock — a plausible daily curve with post-meal rises,
/// so the Trends chart has something meaningful to draw.
struct MockGlucoseSource: GlucoseSource {
    func readings(in interval: DateInterval) async throws -> [GlucoseReading] {
        var out: [GlucoseReading] = []
        var t = interval.start
        let cal = Calendar.current
        while t <= interval.end {
            let hour = Double(cal.component(.hour, from: t))
                     + Double(cal.component(.minute, from: t)) / 60.0
            out.append(GlucoseReading(takenAt: t,
                                      mmolPerL: Self.curve(atHour: hour),
                                      source: "CGM · mock"))
            t = t.addingTimeInterval(15 * 60)   // every 15 min
        }
        return out
    }

    /// Baseline ~5.5 mmol/L with bumps after 08:00, 12:45 and 19:20 "meals".
    static func curve(atHour h: Double) -> Double {
        func bump(center: Double, height: Double, width: Double) -> Double {
            let d = (h - center) / width
            return d > 0 ? height * d * exp(1 - d) : 0
        }
        let base = 5.4 + 0.3 * sin((h - 4) / 24 * 2 * .pi)
        return (base
                + bump(center: 8.2,  height: 2.6, width: 0.9)
                + bump(center: 12.8, height: 3.1, width: 1.1)
                + bump(center: 19.4, height: 3.8, width: 1.3))
    }
}

/// Daily aggregate used by the week/month rollups.
struct DailyTrend: Hashable, Identifiable {
    var id: Date { day }
    let day: Date
    let totalCarbsGrams: Double
    let avgGlucoseMmolPerL: Double
    let timeInRangeFraction: Double   // 0…1, within 3.9–10 mmol/L
}

/// Mock week of aggregates for the wireframe.
enum SampleTrends {
    static func lastWeek(endingOn end: Date = .now) -> [DailyTrend] {
        let cal = Calendar.current
        let carbs:   [Double] = [128, 176, 104, 140, 190, 120, 149]
        let glucose: [Double] = [6.4, 7.1, 5.9, 6.6, 7.6, 6.2, 6.8]
        let tir:     [Double] = [0.81, 0.68, 0.88, 0.77, 0.61, 0.84, 0.78]
        return (0..<7).compactMap { i in
            guard let day = cal.date(byAdding: .day, value: i - 6,
                                     to: cal.startOfDay(for: end)) else { return nil }
            return DailyTrend(day: day,
                              totalCarbsGrams: carbs[i],
                              avgGlucoseMmolPerL: glucose[i],
                              timeInRangeFraction: tir[i])
        }
    }
}

import CoreGraphics
import Foundation

// Date establishment, wall-clock -> UTC conversion, warnings, and the
// top-level extraction orchestrator. Port of the reference `graph.py` time
// layer with one designed deviation: the CLI's --date flag is replaced by
// the photo asset's creation date (Decision 3).

public struct GlucoseReading: Sendable, Equatable {
    public let tsUtcMs: Int64
    public let value: Double  // mmol/L, one decimal

    public init(tsUtcMs: Int64, value: Double) {
        self.tsUtcMs = tsUtcMs
        self.value = value
    }
}

public struct Extraction: Sendable {
    public let view: GraphView
    public let readings: [GlucoseReading]
    public let axisRange: (low: Int, high: Int)
    public let date: GraphDate
    public let dateSource: String  // "asset" | "ocr"
    public let timezone: String  // IANA identifier used for the conversion
    public let warnings: [String]
}

// MARK: - Date establishment (Decision 3)

// daily24h: the printed date governs — a screenshot of a day report can be
// taken any time after the day, so the asset date cannot substitute; it only
// feeds the Req 2.6 sanity warning. home8h: the window always ends at "now",
// and the screenshot's creation instant IS that "now", so the asset date is
// the right-edge date. Reject when the governing source is missing (Req 2.2,
// 2.5).
func establishDate(
    printed: GraphDate?,
    asset: GraphDate?,
    view: GraphView
) throws -> (date: GraphDate, source: String, warnings: [String]) {
    switch view {
    case .daily24h:
        guard let printed else {
            throw RejectImage(
                "cannot establish date: no printed date was read on the 24-hour report")
        }
        var warnings: [String] = []
        if let asset, asset < printed {
            warnings.append(
                "photo creation date \(asset.isoString) precedes the printed "
                    + "report date \(printed.isoString); check the screenshot")
        }
        return (printed, "ocr", warnings)
    case .home8h:
        guard let asset else {
            throw RejectImage(
                "cannot establish date: no photo creation date is available "
                    + "for this 8-hour view")
        }
        return (asset, "asset", [])
    }
}

// MARK: - Wall-clock -> UTC

private func instant(
    _ date: GraphDate,
    minuteOfDay: Int,
    timeZone: TimeZone
) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let components = DateComponents(
        year: date.year, month: date.month, day: date.day,
        hour: minuteOfDay / 60, minute: minuteOfDay % 60
    )
    // Nonexistent wall-clock times (spring-forward) resolve to the shifted
    // instant; those days carry the DST warning anyway (Req 3.5).
    return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
}

// Wall-clock hours on the window's axis -> UTC ms since epoch. On a crossing
// window hour 0 is midnight of established - 1, so hours below 24 land on
// the preceding calendar day and hour 24 is exactly midnight of the
// established date (Req 2.3).
func hoursToUtcMs(
    _ hours: Double,
    established: GraphDate,
    crossesMidnight: Bool,
    timeZone: TimeZone
) -> Int64 {
    let base = crossesMidnight ? established.adding(days: -1) : established
    let totalMinutes = pythonRound(hours * 60)
    // Floor division so negative offsets (never produced by mark generation,
    // but safe) still land on the correct day.
    var dayOffset = totalMinutes / 1440
    var minuteOfDay = totalMinutes % 1440
    if minuteOfDay < 0 {
        minuteOfDay += 1440
        dayOffset -= 1
    }
    let date = instant(base.adding(days: dayOffset), minuteOfDay: minuteOfDay, timeZone: timeZone)
    return Int64(date.timeIntervalSince1970 * 1000)
}

// Req 3.5 warning for each covered calendar day with a DST transition.
func dstWarnings(
    established: GraphDate,
    crossesMidnight: Bool,
    timeZone: TimeZone
) -> [String] {
    var days = [established]
    if crossesMidnight {
        days.insert(established.adding(days: -1), at: 0)
    }
    var warnings: [String] = []
    for day in days {
        let start = instant(day, minuteOfDay: 0, timeZone: timeZone)
        let end = instant(day.adding(days: 1), minuteOfDay: 0, timeZone: timeZone)
        if timeZone.secondsFromGMT(for: start) != timeZone.secondsFromGMT(for: end) {
            warnings.append(
                "\(day.isoString) contains a DST transition; readings on "
                    + "that day may be offset")
        }
    }
    return warnings
}

// MARK: - Weekday warnings

private let dayAbbreviations = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

// _WEEKDAY_RE: ^\|?\s*(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s*\|?\s*([A-Za-z]{0,2})$
private let weekdayRegex = try! NSRegularExpression(
    pattern: #"^\|?\s*(Mon|Tue|Wed|Thu|Fri|Sat|Sun)\s*\|?\s*([A-Za-z]{0,2})$"#
)

// Warn (never reject) when a weekday label contradicts the date. Tokens sit
// in the band between the plot rect and the time labels — strictly below the
// plot rect, because Vision hallucinates confidence-1.0 text from trace
// shapes inside the plot, and a weekday-shaped hallucination must not emit a
// spurious warning. The '|' separator marks the midnight boundary: on a
// crossing window the left part must match weekday(established - 1) and the
// right part is a truncated prefix of weekday(established). Vision may drop
// the pipe entirely ('Wed | T' comes back 'WedT').
func weekdayWarnings(
    _ boxes: [TextBox],
    calibration: Calibration,
    established: GraphDate
) -> [String] {
    let plotBottom = calibration.plotRect.bottom
    let expected = dayAbbreviations[established.weekdayMondayZero]
    let previous = dayAbbreviations[established.adding(days: -1).weekdayMondayZero]
    let midnightPx = calibration.xFit.px(at: 24)

    var warnings: [String] = []
    for box in boxes {
        let cy = box.centre.y
        guard plotBottom <= cy, cy <= plotBottom + 250 else { continue }
        let trimmed = box.text.trimmingCharacters(in: .whitespaces)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = weekdayRegex.firstMatch(in: trimmed, options: [], range: range),
              let dayRange = Range(match.range(at: 1), in: trimmed),
              let tailRange = Range(match.range(at: 2), in: trimmed)
        else { continue }
        let day = String(trimmed[dayRange])
        let tail = String(trimmed[tailRange])

        let ok: Bool
        if !tail.isEmpty {
            // Combined boundary label: left day | truncated right day.
            ok = calibration.crossesMidnight && day == previous && expected.hasPrefix(tail)
        } else if calibration.crossesMidnight {
            let sideDay = box.centre.x < midnightPx ? previous : expected
            ok = day == sideDay
        } else {
            ok = day == expected
        }
        if !ok {
            warnings.append(
                "weekday label '\(trimmed)' contradicts the established "
                    + "date \(established.isoString) (\(expected))")
        }
    }
    return warnings
}

// MARK: - Orchestrator

public enum GlucoseGraphExtractor {

    // Full pipeline for one image; throws RejectImage, writes nothing.
    // `assetDate` is the photo's creation date in the device's current time
    // zone (Decision 3); nil when unavailable.
    public static func extract(
        cgImage: CGImage,
        assetDate: GraphDate?,
        timeZone: TimeZone = .current
    ) throws -> Extraction {
        let boxes = try TextRecogniser.recognise(cgImage)
        let bitmap = try Bitmap(cgImage: cgImage)
        let calibration = try classifyAndCalibrate(
            boxes, width: bitmap.width, height: bitmap.height, bitmap: bitmap)

        let (date, dateSource, dateWarnings) = try establishDate(
            printed: calibration.printedDate, asset: assetDate, view: calibration.view)
        var warnings = dateWarnings
        warnings += dstWarnings(
            established: date, crossesMidnight: calibration.crossesMidnight,
            timeZone: timeZone)
        warnings += weekdayWarnings(boxes, calibration: calibration, established: date)

        let (columns, occluded) = extractTrace(bitmap, calibration: calibration, boxes: boxes)
        let marks: [Double]
        switch calibration.view {
        case .daily24h:
            marks = markHours(view: .daily24h)
        case .home8h:
            if columns.isEmpty {
                marks = []
            } else {
                // Observed trace extent: the trace continues under the dot
                // toward "now", so occluded columns extend the window;
                // sampling omits the unreadable marks inside them.
                let lastCol = max(columns.keys.max()!, occluded?.hi ?? 0)
                marks = markHours(
                    view: .home8h,
                    traceExtent: (
                        first: calibration.xFit.value(at: Double(columns.keys.min()!)),
                        last: calibration.xFit.value(at: Double(lastCol))
                    ))
            }
        }
        let samples = sampleTrace(
            columns: columns, occluded: occluded, xFit: calibration.xFit, marks: marks)
        let readings = samples.map { sample in
            GlucoseReading(
                tsUtcMs: hoursToUtcMs(
                    sample.hour, established: date,
                    crossesMidnight: calibration.crossesMidnight, timeZone: timeZone),
                value: sample.value
            )
        }
        return Extraction(
            view: calibration.view,
            readings: readings,
            axisRange: calibration.axisRange,
            date: date,
            dateSource: dateSource,
            timezone: timeZone.identifier,
            warnings: warnings
        )
    }
}

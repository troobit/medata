import CoreGraphics
import Foundation

// View detection and axis calibration. Port of the reference `graph.py`
// (imgdatacollector) calibration layer; constants keep their reference names
// in comments and their values verbatim (Decision 1).

// The image cannot be processed; nothing is written (Req 2.5).
public struct RejectImage: Error, Equatable {
    public let reason: String

    public init(_ reason: String) {
        self.reason = reason
    }
}

// value = slope * px + intercept.
public struct LinearFit: Sendable, Equatable {
    public let slope: Double
    public let intercept: Double

    public init(slope: Double, intercept: Double) {
        self.slope = slope
        self.intercept = intercept
    }

    public func value(at px: Double) -> Double {
        slope * px + intercept
    }

    public func px(at value: Double) -> Double {
        (value - intercept) / slope
    }
}

public enum GraphView: String, Sendable {
    case daily24h
    case home8h
}

public struct Calibration: Sendable {
    public let view: GraphView
    public let axisRange: (low: Int, high: Int)
    public let yFit: LinearFit  // y pixel -> mmol/L
    public let xFit: LinearFit  // x pixel -> hours since the window's first midnight
    public let plotRect: (left: Double, top: Double, right: Double, bottom: Double)
    public let printedDate: GraphDate?
    public let crossesMidnight: Bool
    public let labelHours: (first: Double, last: Double)
}

// Calendar date without a time zone, mirroring Python's `datetime.date`.
// Arithmetic uses the days-from-civil algorithm so no Calendar/locale state
// leaks into date maths.
public struct GraphDate: Sendable, Equatable, Hashable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    // Days since 1970-01-01 (Howard Hinnant's days_from_civil).
    public var dayNumber: Int {
        var y = year
        if month <= 2 { y -= 1 }
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    public static func from(dayNumber z: Int) -> GraphDate {
        let z = z + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return GraphDate(year: m <= 2 ? y + 1 : y, month: m, day: d)
    }

    public func adding(days: Int) -> GraphDate {
        GraphDate.from(dayNumber: dayNumber + days)
    }

    // Monday = 0 … Sunday = 6, matching Python's `date.weekday()`.
    // 1970-01-01 was a Thursday (index 3).
    public var weekdayMondayZero: Int {
        let w = (dayNumber + 3) % 7
        return w >= 0 ? w : w + 7
    }

    public var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: GraphDate, rhs: GraphDate) -> Bool {
        lhs.dayNumber < rhs.dayNumber
    }
}

// MARK: - Constants (reference names in comments)

// _RESIDUAL_GATE: relative residual gate for axis fits — 3% of the
// inter-label pixel pitch. Exceeding it triggers one drop-worst retry
// keeping >= 3 labels.
let residualGate = 0.03
// _MAX_HOUR_PITCH: hour labels in both corpus views sit at 3 h pitch;
// anything past 6 h is not a LibreLink time axis.
let maxHourPitch = 6
// _X_PITCH_TOLERANCE: tolerance on pixel-pitch uniformity of hour labels.
// The corpus's rightmost 00:00 label renders up to ~14% left of its tick.
let xPitchTolerance = 0.2

// MARK: - Small numeric helpers

func mean(_ values: [Double]) -> Double {
    values.reduce(0, +) / Double(values.count)
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let n = sorted.count
    if n % 2 == 1 { return sorted[n / 2] }
    return (sorted[n / 2 - 1] + sorted[n / 2]) / 2
}

// Python's round(): banker's rounding, half to even.
func pythonRound(_ value: Double) -> Int {
    Int(value.rounded(.toNearestOrEven))
}

// Python's round(value, 1).
func pythonRound1(_ value: Double) -> Double {
    (value * 10).rounded(.toNearestOrEven) / 10
}

// MARK: - Label parsing

private let monthNames = [
    "january", "february", "march", "april", "may", "june", "july",
    "august", "september", "october", "november", "december"
]

// _DATE_RE: (\d{1,2})\s+(<month names>)\s+(\d{4}), case-insensitive, searched
// anywhere in the text.
private let dateRegex = try! NSRegularExpression(
    pattern: #"(\d{1,2})\s+("# + monthNames.joined(separator: "|") + #")\s+(\d{4})"#,
    options: [.caseInsensitive]
)

// First parseable long date ('2 July 2026') anywhere in the text.
public func findPrintedDate(_ boxes: [TextBox]) -> GraphDate? {
    for box in boxes {
        let text = box.text
        let range = NSRange(text.startIndex..., in: text)
        guard let match = dateRegex.firstMatch(in: text, options: [], range: range),
              let dayRange = Range(match.range(at: 1), in: text),
              let monthRange = Range(match.range(at: 2), in: text),
              let yearRange = Range(match.range(at: 3), in: text),
              let day = Int(text[dayRange]),
              let year = Int(text[yearRange]),
              let month = monthNames.firstIndex(of: text[monthRange].lowercased())
        else { continue }
        let date = GraphDate(year: year, month: month + 1, day: day)
        // Python raises ValueError for impossible dates and keeps scanning;
        // validate by round-tripping through the day-number conversion.
        if GraphDate.from(dayNumber: date.dayNumber) == date, (1...31).contains(day) {
            return date
        }
    }
    return nil
}

// _TIME_RE: ^(\d{1,2}):(\d{2})$ — full-string match on the trimmed token.
func parseTimeLabel(_ text: String) -> (hh: Int, mm: Int)? {
    let parts = text.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 2,
          (1...2).contains(parts[0].count), parts[1].count == 2,
          parts[0].allSatisfy(\.isNumber), parts[1].allSatisfy(\.isNumber),
          let hh = Int(parts[0]), let mm = Int(parts[1])
    else { return nil }
    return (hh, mm)
}

// _INT_RE: ^\d{1,2}$ on the trimmed token.
func parseIntLabel(_ text: String) -> Int? {
    guard (1...2).contains(text.count), text.allSatisfy(\.isNumber) else { return nil }
    return Int(text)
}

// MARK: - Fits

func leastSquares(_ points: [(px: Double, value: Double)]) -> LinearFit {
    let meanX = mean(points.map(\.px))
    let meanY = mean(points.map(\.value))
    let denom = points.reduce(0.0) { $0 + ($1.px - meanX) * ($1.px - meanX) }
    let slope = points.reduce(0.0) { $0 + ($1.px - meanX) * ($1.value - meanY) } / denom
    return LinearFit(slope: slope, intercept: meanY - slope * meanX)
}

// Least-squares px->value fit under the relative residual gate. Residuals
// are measured in pixels against 3% of the inter-label pixel pitch; when
// exceeded, retry once with the worst-residual point dropped, keeping at
// least 3 points. Returns (fit, indices of points used).
func fitWithRetry(
    _ points: [(px: Double, value: Double)],
    valueStep: Double,
    what: String
) throws -> (fit: LinearFit, usedIndices: [Int]) {

    func attempt(_ indices: [Int]) -> (LinearFit, [Double], Double) {
        let pts = indices.map { points[$0] }
        let fit = leastSquares(pts)
        let pitchPx = abs(valueStep / fit.slope)
        let residuals = pts.map { abs($0.px - fit.px(at: $0.value)) }
        return (fit, residuals, pitchPx)
    }

    var indices = Array(points.indices)
    var (fit, residuals, pitchPx) = attempt(indices)
    if residuals.max()! <= residualGate * pitchPx {
        return (fit, indices)
    }
    if points.count >= 4 {
        let worst = residuals.firstIndex(of: residuals.max()!)!
        indices.remove(at: worst)
        (fit, residuals, pitchPx) = attempt(indices)
        if residuals.max()! <= residualGate * pitchPx {
            return (fit, indices)
        }
    }
    throw RejectImage("cannot calibrate \(what): labels do not fit a line")
}

// MARK: - Label geometry

// The row of hh:00 labels along the time axis, sorted left to right.
// Candidates are :00 tokens in the lower half of the image (the status-bar
// clock sits at the top); the row is the largest same-y cluster.
func hourLabelRow(_ boxes: [TextBox], height: Int) -> [(box: TextBox, hour: Int)] {
    var candidates: [(TextBox, Int)] = []
    for box in boxes {
        let trimmed = box.text.trimmingCharacters(in: .whitespaces)
        guard let (hh, mm) = parseTimeLabel(trimmed), hh <= 23, mm == 0 else { continue }
        if box.center.y < Double(height) * 0.5 { continue }
        candidates.append((box, hh))
    }

    var clusters: [[(TextBox, Int)]] = []
    for item in candidates.sorted(by: { $0.0.center.y < $1.0.center.y }) {
        if let last = clusters.last, let first = last.first,
           item.0.center.y - first.0.center.y < 40 {
            clusters[clusters.count - 1].append(item)
        } else {
            clusters.append([item])
        }
    }
    guard let row = clusters.max(by: { $0.count < $1.count }) else { return [] }
    return row.sorted { $0.0.center.x < $1.0.center.x }
}

// Left-to-right label hours with a midnight wrap adding 24.
func cumulativeHours(_ labels: [(box: TextBox, hour: Int)]) throws -> [Int] {
    var hours: [Int] = []
    var wraps = 0
    for (_, hh) in labels {
        var value = hh + 24 * wraps
        if let last = hours.last, value <= last {
            wraps += 1
            value = hh + 24 * wraps
        }
        if let last = hours.last, value <= last {
            throw RejectImage("cannot identify view: hour labels are not ascending")
        }
        hours.append(value)
    }
    return hours
}

// Require uniform hour pitch and pixel pitch; return the hour pitch.
func checkUniform(_ labels: [(box: TextBox, hour: Int)], hours: [Int]) throws -> Int {
    let hourDiffs = zip(hours, hours.dropFirst()).map { $1 - $0 }
    if Set(hourDiffs).count != 1 {
        throw RejectImage("cannot identify view: hour labels are not uniformly spaced")
    }
    let xs = labels.map { $0.box.center.x }
    let pxPitches = zip(xs, xs.dropFirst()).map { $1 - $0 }
    let medianPitch = median(pxPitches.map(Double.init))
    if pxPitches.contains(where: { abs($0 - medianPitch) > xPitchTolerance * medianPitch }) {
        throw RejectImage("cannot identify view: hour labels are not uniformly spaced")
    }
    return hourDiffs[0]
}

// Integer labels in the narrow column left of the plot. The size filter
// drops boxes Vision merged with plot content (reference: IMG_0585's '9'
// comes back 84x72 when the trace passes close to the label column).
func yLabelColumn(_ boxes: [TextBox], width: Int) -> [(box: TextBox, value: Int)] {
    boxes.compactMap { box in
        let trimmed = box.text.trimmingCharacters(in: .whitespaces)
        guard let value = parseIntLabel(trimmed),
              box.center.x < 0.12 * Double(width),
              box.pixelRect.width <= 70,
              box.pixelRect.height <= 60
        else { return nil }
        return (box, value)
    }
}

// MARK: - Axis-tick x-fit refinement

// First row in [y0, y1) whose dark run spans >= 70% of [x0, x1).
func findAxisLine(_ bitmap: Bitmap, x0: Int, x1: Int, y0: Int, y1: Int) -> Int? {
    let needed = 0.7 * Double(x1 - x0)
    for y in y0..<y1 {
        var count = 0
        for x in x0..<x1 {
            let (r, g, b) = bitmap.rgb(x: x, y: y)
            if r + g + b < 400 { count += 1 }
        }
        if Double(count) >= needed { return y }
    }
    return nil
}

// Centres of the tick marks in the rows just below the axis line.
func detectTicks(_ bitmap: Bitmap, axisRow: Int, x0: Int, x1: Int) -> [Double] {
    var hits: [Int: Int] = [:]
    for dy in 3..<10 {
        let y = axisRow + dy
        if y >= bitmap.height { break }
        for x in x0..<x1 {
            let (r, g, b) = bitmap.rgb(x: x, y: y)
            if r + g + b < 400 { hits[x, default: 0] += 1 }
        }
    }
    let columns = hits.filter { $0.value >= 3 }.keys.sorted()
    var groups: [[Int]] = []
    for x in columns {
        if let last = groups.last, let tail = last.last, x - tail <= 2 {
            groups[groups.count - 1].append(x)
        } else {
            groups.append([x])
        }
    }
    return groups.map { mean($0.map(Double.init)) }
}

// Refit the time axis against detected axis ticks. Hour-label centres drift
// ~0.6% from the true tick pitch (~6 px = 8 minutes at the 24h view's right
// edge), so the label fit only seeds the hour assignment; the returned fit
// runs through the ticks. Returns nil when no usable ruler is found (caller
// keeps the label fit).
func refineXFit(
    _ bitmap: Bitmap,
    provisional: LinearFit,
    plotLeft: Double,
    plotBottom: Double
) -> LinearFit? {
    let x0 = Int(plotLeft)
    let x1 = bitmap.width - 10
    guard let axisRow = findAxisLine(
        bitmap, x0: x0, x1: x1,
        y0: Int(plotBottom), y1: min(Int(plotBottom) + 300, bitmap.height)
    ) else { return nil }

    let ticks = detectTicks(bitmap, axisRow: axisRow, x0: x0, x1: x1)
    let pxPerHour = abs(1 / provisional.slope)
    var byHour: [Int: Double] = [:]
    for tick in ticks {
        let hour = pythonRound(provisional.value(at: tick))
        let offset = abs(tick - provisional.px(at: Double(hour)))
        if offset > 0.4 * pxPerHour { continue }  // not near any hour position: noise
        if let existing = byHour[hour] {
            if offset < abs(existing - provisional.px(at: Double(hour))) {
                byHour[hour] = tick
            }
        } else {
            byHour[hour] = tick
        }
    }
    if byHour.count < 3 { return nil }

    let points = byHour.map { (px: $0.value, value: Double($0.key)) }
    var fit = leastSquares(points)
    let residuals = points.map { abs($0.px - fit.px(at: $0.value)) }
    if residuals.max()! > 0.15 * pxPerHour {
        let kept = points.indices.filter { residuals[$0] <= 0.15 * pxPerHour }
        if kept.count < 3 { return nil }
        fit = leastSquares(kept.map { points[$0] })
    }
    return fit
}

// MARK: - Classification and calibration

// Classify the view and calibrate both axes. Classification and the y fit
// come from OCR boxes alone; when `bitmap` is given, the x fit is refined
// against the detected axis ticks.
public func classifyAndCalibrate(
    _ boxes: [TextBox],
    width: Int,
    height: Int,
    bitmap: Bitmap?
) throws -> Calibration {
    let printedDate = findPrintedDate(boxes)
    let hourLabels = hourLabelRow(boxes, height: height)
    if hourLabels.count < 2 {
        throw RejectImage("cannot identify view: no time axis labels found")
    }

    let hours = try cumulativeHours(hourLabels)
    let hourPitch = try checkUniform(hourLabels, hours: hours)
    let span = hours.last! - hours.first!

    // The 24h report is identified by its label signature alone: 00:00 at
    // both extremes spanning exactly 24 hours. The printed date plays no
    // part: an unreadable date must not fail classification.
    let isDaily = hours.first! % 24 == 0
        && span == 24
        && hourLabels.first!.box.text.trimmingCharacters(in: .whitespaces) == "00:00"
        && hourLabels.last!.box.text.trimmingCharacters(in: .whitespaces) == "00:00"

    let view: GraphView
    let crossesMidnight: Bool
    if isDaily {
        view = .daily24h
        crossesMidnight = false
    } else if span < 24 && hourPitch <= maxHourPitch {
        view = .home8h
        crossesMidnight = hours.first! < 24 && 24 <= hours.last!
    } else {
        throw RejectImage(
            "cannot identify view: time labels match neither a 24-hour "
                + "report nor a home view")
    }

    let yLabels = yLabelColumn(boxes, width: width)
    if yLabels.count < 2 {
        throw RejectImage(
            "cannot calibrate glucose axis: found \(yLabels.count) y-axis "
                + "labels, need at least 2")
    }
    let values = Set(yLabels.map(\.value)).sorted()
    let steps = zip(values, values.dropFirst()).map { Double($1 - $0) }
    let valueStep = steps.isEmpty ? 3.0 : median(steps)
    let yPoints = yLabels.map { (px: Double($0.box.center.y), value: Double($0.value)) }
    let (yFit, used) = try fitWithRetry(yPoints, valueStep: valueStep, what: "glucose axis")
    let yLabelsUsed = used.map { yLabels[$0] }

    // axis_range and the plot rect's vertical extremes come from ALL parsed
    // label values: a dropped label's pixel position is suspect (its box
    // merged with plot content), but its value is a real gridline. Deriving
    // them from survivors only would record the wrong labelled range in
    // metadata and shave a pitch of headroom off the plot rect, excluding
    // trace above the range — clamping by omission, forbidden.
    let axisRange = (low: values.first!, high: values.last!)
    let pitchPx = abs(valueStep / yFit.slope)

    let left = yLabelsUsed.map { $0.box.pixelRect.maxX }.max()! + 2
    let right = hourLabels.map { $0.box.pixelRect.maxX }.max()!
    let top = yFit.px(at: Double(axisRange.high)) - pitchPx
    let bottom = yFit.px(at: Double(axisRange.low)) + 0.6 * pitchPx

    let xPoints = zip(hourLabels, hours).map { label, hour in
        (px: Double(label.box.center.x), value: Double(hour))
    }
    var xFit: LinearFit?
    if let bitmap {
        let provisional = leastSquares(xPoints)
        xFit = refineXFit(bitmap, provisional: provisional, plotLeft: left, plotBottom: bottom)
    }
    let finalXFit: LinearFit
    if let xFit {
        finalXFit = xFit
    } else {
        finalXFit = try fitWithRetry(xPoints, valueStep: Double(hourPitch), what: "time axis").fit
    }

    return Calibration(
        view: view,
        axisRange: axisRange,
        yFit: yFit,
        xFit: finalXFit,
        plotRect: (left: Double(left), top: top, right: Double(right), bottom: bottom),
        printedDate: printedDate,
        crossesMidnight: crossesMidnight,
        labelHours: (first: Double(hours.first!), last: Double(hours.last!))
    )
}

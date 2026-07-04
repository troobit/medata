import CoreGraphics
import Foundation

// Trace extraction: colour masks, current-dot occlusion, structural
// threshold-line removal, column runs. Port of the reference `graph.py`
// trace layer; constants verbatim (Decision 1).

// MARK: - Constants (reference names in comments)

// _REJOIN_GAP: vertical gap (px) across which two runs in one column are
// re-joined: the dashed threshold line's stroke is ~11 rows tall, and its
// structural removal cuts the trace where it crosses the line.
let rejoinGap = 12
// _DASH_MAX_LEN / _DASH_MIN_RUNS / _DASH_MIN_COVERAGE: a real dashed line is
// ~40 uniform dashes (<=45 px each) across >=45% of the plot width; a wiggly
// trace crosses a row at most ~15 times (measured across the corpus).
let dashMaxLen = 45
let dashMinRuns = 20
let dashMinCoverage = 0.45
// _MIN_COLUMN_PIXELS: minimum pixels in a column before it counts as trace.
let minColumnPixels = 3
// _MIN_DOT_AREA: orange components smaller than this are threshold-line
// dashes, not the dot.
let minDotArea = 500
// _MAX_RING_REACH: the search for the dot's dark ring never looks past this
// multiple of the disc radius (upper bound only).
let maxRingReach = 2.2
// _RING_MIN_COVERAGE: a 1-px annulus belongs to the ring when dark pixels
// cover at least this fraction of its circumference.
let ringMinCoverage = 0.25

struct Pixel: Hashable {
    let x: Int
    let y: Int
}

// MARK: - Colour classes

@inline(__always)
func isOrange(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    r >= 200 && (95...200).contains(g) && b < 110
}

@inline(__always)
func isRed(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    r >= 100 && g < 95 && b < 95 && (r - max(g, b)) >= 50
}

@inline(__always)
func isBlack(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    r + g + b < 240 && max(r, g, b) - min(r, g, b) < 45
}

// MARK: - Runs

// Maximal runs of consecutive integers in a sorted list.
func runs1D(_ sortedValues: [Int]) -> [(start: Int, end: Int)] {
    var runs: [(Int, Int)] = []
    for v in sortedValues {
        if let last = runs.last, v - last.1 <= 1 {
            runs[runs.count - 1].1 = v
        } else {
            runs.append((v, v))
        }
    }
    return runs
}

// Vertical runs in one column, re-joined across small gaps. Row removal
// where the trace crosses a threshold line splits one stroke into two runs;
// gaps no taller than the dashed stroke height are merged back before the
// extremum rule looks at the column.
func columnRuns(_ ys: [Int], gap: Int = rejoinGap) -> [(start: Int, end: Int)] {
    var merged: [(Int, Int)] = []
    for (a, b) in runs1D(ys.sorted()) {
        if let last = merged.last, a - last.1 - 1 <= gap {
            merged[merged.count - 1].1 = b
        } else {
            merged.append((a, b))
        }
    }
    return merged
}

// Stroke centre for a column; local extremum on multi-run columns. Multiple
// disjoint runs mean a steep flank or spike apex: take the topmost run when
// the neighbouring columns' centres lie below it, the bottommost when above.
func chooseRunCenter(_ runs: [(start: Int, end: Int)], neighbourY: Double?) -> Double {
    let centers = runs.map { Double($0.start + $0.end) / 2 }
    if centers.count == 1 { return centers[0] }
    guard let neighbourY else { return centers[0] }
    let midpoint = (centers.min()! + centers.max()!) / 2
    return neighbourY >= midpoint ? centers.min()! : centers.max()!
}

// MARK: - Structural dashed-line removal

// Drop threshold-line pixels structurally, not by colour. A row belongs to a
// dashed line when its pixels form many short interrupted runs across at
// least 45% of the plot width; only the short runs are dropped, so a trace
// stroke crossing the line survives as a small vertical gap that columnRuns
// re-joins.
func removeDashedRows(_ pixels: Set<Pixel>, plotWidth: Double) -> Set<Pixel> {
    var byRow: [Int: [Int]] = [:]
    for p in pixels {
        byRow[p.y, default: []].append(p.x)
    }
    var removed = Set<Pixel>()
    for (y, xs) in byRow {
        let sorted = xs.sorted()
        let runs = runs1D(sorted)
        let short = runs.filter { $0.end - $0.start + 1 <= dashMaxLen }
        if short.count >= dashMinRuns,
           Double(sorted.last! - sorted.first!) >= dashMinCoverage * plotWidth {
            for (a, b) in short {
                for x in a...b { removed.insert(Pixel(x: x, y: y)) }
            }
        }
    }
    return pixels.subtracting(removed)
}

// MARK: - Current-reading dot

func connectedComponents(_ points: Set<Pixel>) -> [Set<Pixel>] {
    var remaining = points
    var components: [Set<Pixel>] = []
    while let seed = remaining.popFirst() {
        var component: Set<Pixel> = [seed]
        var frontier = [seed]
        while let p = frontier.popLast() {
            for dx in -1...1 {
                for dy in -1...1 {
                    let q = Pixel(x: p.x + dx, y: p.y + dy)
                    if remaining.remove(q) != nil {
                        component.insert(q)
                        frontier.append(q)
                    }
                }
            }
        }
        components.append(component)
    }
    return components
}

// Occluded column range of the current-reading dot, or nil. The dot is the
// largest near-circular connected orange blob — the discriminator that keeps
// the dashed orange threshold line from marking the whole plot width
// occluded. Its dark ring is part of the occlusion: ring pixels are
// trace-black-coloured and unreadable.
func detectDot(orange: Set<Pixel>, dark: Set<Pixel>) -> (lo: Int, hi: Int)? {
    var best: Set<Pixel>?
    for component in connectedComponents(orange) {
        if component.count < minDotArea { continue }
        let xs = component.map(\.x)
        let ys = component.map(\.y)
        let w = xs.max()! - xs.min()! + 1
        let h = ys.max()! - ys.min()! + 1
        let aspect = Double(w) / Double(h)
        if !(0.5...2.0).contains(aspect) { continue }
        if Double(component.count) < 0.4 * Double(w * h) { continue }
        if best == nil || component.count > best!.count { best = component }
    }
    guard let best else { return nil }

    // Core columns: a threshold-line dash fused onto the blob is only a few
    // pixels tall, the disc's own columns are tens.
    var colCounts: [Int: Int] = [:]
    for p in best { colCounts[p.x, default: 0] += 1 }
    let tallest = colCounts.values.max()!
    let core = colCounts.filter { Double($0.value) >= 0.35 * Double(tallest) }.keys
    var lo = core.min()!
    var hi = core.max()!
    let rows = best.filter { (lo...hi).contains($0.x) }.map(\.y)
    let cx = Double(lo + hi) / 2
    let cy = Double(rows.min()! + rows.max()!) / 2
    let radius = Double(hi - lo + 1) / 2

    // The occlusion is the columns the marker covers INCLUDING its dark ring
    // — bounded by the ring's measured outer extent, not a bare multiple of
    // the disc radius, or any trace-dark pixel near the dot would sweep the
    // occlusion outward and silently omit readable trace. The ring is a
    // near-complete annulus hugging the disc: walk outward while each 1-px
    // annulus stays substantially covered.
    let maxReach = maxRingReach * radius
    var counts: [Int: Int] = [:]
    for p in dark {
        let d2 = (Double(p.x) - cx) * (Double(p.x) - cx) + (Double(p.y) - cy) * (Double(p.y) - cy)
        if d2 <= maxReach * maxReach {
            counts[Int(d2.squareRoot()), default: 0] += 1
        }
    }
    var ringOuter = radius
    var misses = 0
    var d = Int(radius)
    while d <= Int(maxReach) {
        if Double(counts[d] ?? 0) >= ringMinCoverage * 2 * Double.pi * Double(max(d, 1)) {
            ringOuter = Double(d + 1)
            misses = 0
        } else {
            misses += 1
            if misses > 2 { break }  // small anti-aliasing gap between disc and ring
        }
        d += 1
    }
    for p in dark {
        let d2 = (Double(p.x) - cx) * (Double(p.x) - cx) + (Double(p.y) - cy) * (Double(p.y) - cy)
        if d2 <= ringOuter * ringOuter {
            lo = min(lo, p.x)
            hi = max(hi, p.x)
        }
    }
    return (lo, hi)
}

// MARK: - Trace extraction

// Trace columns (x -> mmol/L) and the dot-occluded column range.
func extractTrace(
    _ bitmap: Bitmap,
    calibration: Calibration,
    boxes: [TextBox]
) -> (columns: [Int: Double], occluded: (lo: Int, hi: Int)?) {
    let (left, top, right, bottom) = calibration.plotRect
    let x0 = max(0, Int(left.rounded(.up)))
    let x1 = min(bitmap.width - 1, Int(right.rounded(.down)))
    let y0 = max(0, Int(top.rounded(.up)))
    let y1 = min(bitmap.height - 1, Int(bottom.rounded(.down)))

    // Text inside the plot rect (the 8h view's big readout, the weekday
    // band, the date bar) must not enter the masks. Legitimate in-plot text
    // always straddles the plot boundary; a box fully inside the plot is
    // Vision misreading the trace itself (reference: IMG_0581 returns the
    // trace's V-shape as 'N' at confidence 1.0) and must never be masked.
    var textRects: [(x0: Double, y0: Double, x1: Double, y1: Double)] = []
    for box in boxes {
        let bx = box.pixelRect.origin.x
        let by = box.pixelRect.origin.y
        let bw = box.pixelRect.width
        let bh = box.pixelRect.height
        let intersects = bx <= Double(x1) && bx + bw >= Double(x0)
            && by <= Double(y1) && by + bh >= Double(y0)
        let fullyInside = bx >= Double(x0) && bx + bw <= Double(x1)
            && by >= Double(y0) && by + bh <= Double(y1)
        if box.confidence >= 0.8 && intersects && !fullyInside {
            textRects.append((bx - 2, by - 2, bx + bw + 2, by + bh + 2))
        }
    }

    func inText(_ x: Int, _ y: Int) -> Bool {
        textRects.contains { rect in
            rect.x0 <= Double(x) && Double(x) <= rect.x1
                && rect.y0 <= Double(y) && Double(y) <= rect.y1
        }
    }

    var trace = Set<Pixel>()
    var orange = Set<Pixel>()
    // The current-reading dot can hang over the plot rect's right edge (it
    // is centred on "now"); scan orange wider so it is never clipped.
    let xOrange = min(bitmap.width - 1, x1 + 60)
    for x in x0...xOrange {
        for y in y0...y1 {
            let (r, g, b) = bitmap.rgb(x: x, y: y)
            if isOrange(r, g, b) {
                orange.insert(Pixel(x: x, y: y))
            } else if x <= x1, isBlack(r, g, b) || isRed(r, g, b) {
                if !inText(x, y) {
                    trace.insert(Pixel(x: x, y: y))
                }
            }
        }
    }

    var occluded = detectDot(orange: orange, dark: trace)
    if let occ = occluded {
        trace = trace.filter { !($0.x >= occ.lo && $0.x <= occ.hi) }
        occluded = occ
    }

    trace = removeDashedRows(trace, plotWidth: Double(x1 - x0))

    var byCol: [Int: [Int]] = [:]
    for p in trace {
        byCol[p.x, default: []].append(p.y)
    }

    var columns: [Int: Double] = [:]
    for (x, ys) in byCol {
        if ys.count < minColumnPixels { continue }
        let runs = columnRuns(ys)
        let center: Double
        if runs.count == 1 {
            center = chooseRunCenter(runs, neighbourY: nil)
        } else {
            var neighbours: [Int] = []
            for dx in [-3, -2, -1, 1, 2, 3] {
                if let column = byCol[x + dx] { neighbours.append(contentsOf: column) }
            }
            let neighbourY = neighbours.isEmpty ? nil : mean(neighbours.map(Double.init))
            center = chooseRunCenter(runs, neighbourY: neighbourY)
        }
        columns[x] = calibration.yFit.value(at: center)
    }
    return (columns, occluded)
}

import Foundation

// 5-minute mark generation and trace sampling. Port of the reference
// `graph.py` sampling layer.

// 5-minute wall-clock marks, in hours on the window's time axis.
// 24h view: the half-open [00:00, 00:00) window, 288 marks (Req 3.4).
// 8h view: every mark inside the observed trace extent.
func markHours(view: GraphView, traceExtent: (first: Double, last: Double)? = nil) -> [Double] {
    if view == .daily24h {
        return (0..<288).map { Double($0) / 12 }
    }
    guard let traceExtent else { return [] }
    let start = Int((traceExtent.first * 12 - 1e-6).rounded(.up))
    let stop = Int((traceExtent.last * 12 + 1e-6).rounded(.down))
    guard start <= stop else { return [] }
    return (start...stop).map { Double($0) / 12 }
}

// Value at each 5-minute mark, or nothing (occluded / real gap). Search
// never exceeds floor(mark_pitch / 2) px so it cannot cross into the
// adjacent mark's column. Absences of 10 minutes or less bridge by linear
// interpolation; wider gaps and dot-occluded marks are omitted.
func sampleTrace(
    columns: [Int: Double],
    occluded: (lo: Int, hi: Int)?,
    xFit: LinearFit,
    marks: [Double]
) -> [(hour: Double, value: Double)] {
    if columns.isEmpty { return [] }
    let pxPerHour = 1 / xFit.slope
    let search = Int((pxPerHour / 12 / 2).rounded(.down))
    let xsSorted = columns.keys.sorted()
    var out: [(Double, Double)] = []

    for h in marks {
        let xm = xFit.px(at: h)
        let windowStart = pythonRound(xm) - search
        let windowEnd = pythonRound(xm) + search  // inclusive
        var candidates: [Int] = []
        for x in windowStart...windowEnd where columns[x] != nil {
            candidates.append(x)
        }
        if !candidates.isEmpty {
            let nearest = candidates.min { abs(Double($0) - xm) < abs(Double($1) - xm) }!
            out.append((h, pythonRound1(columns[nearest]!)))
            continue
        }
        if let occluded, windowStart <= occluded.hi, windowEnd >= occluded.lo {
            continue  // unreadable under the dot: omitted, never bridged
        }
        // bisect_left over the sorted trace columns.
        var lo = 0
        var hi = xsSorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if Double(xsSorted[mid]) < xm { lo = mid + 1 } else { hi = mid }
        }
        if lo == 0 || lo == xsSorted.count {
            continue  // trace has not started / already ended
        }
        let xl = xsSorted[lo - 1]
        let xr = xsSorted[lo]
        let tl = xFit.value(at: Double(xl))
        let tr = xFit.value(at: Double(xr))
        if tr - tl <= 1.0 / 6 + 1e-9 {  // a break of 10 minutes or less
            let v = columns[xl]! + (columns[xr]! - columns[xl]!) * (h - tl) / (tr - tl)
            out.append((h, pythonRound1(v)))
        }
    }
    return out
}

import CoreGraphics
import Foundation
import ImageIO
import Pipeline
import SwiftUI

// Read side of the mask artefact (UI Design Handoff 00, Decision 15). Loads the
// per-meal `mask` artefact bytes from the store, decodes the RAW 8-bit label
// indices via a `CGDataProvider` (NOT a colour-managed `UIImage` decode, which
// can remap index values), and tints each region per the deterministic
// id->colour table. Colours are applied at read time only — the stored PNG
// carries indices, never colours.
//
// The view renders ONLY the translucent tinted overlay so a parent stacks it
// over the captured photo (Segmentation review, Meal overview). On ANY miss —
// no artefact row, unreadable file, unexpected pixel format — it renders
// nothing, so the photo (or its placeholder) shows through unmodified
// (Req 6.8, photo-only fallback; never errors).
//
// `onDecode` reports the set of class indices present in the raster so callers
// can drive the §5.2 unknown / unsupported-liquid banners from the authoritative
// label map (the only place unknown/liquid regions surface — they carry no
// per-class macro entry). An empty set means "no mask / nothing to report".
struct MaskOverlayLoader: View {
    let store: any PersistenceStore
    let mealId: UUID
    // Single palette ships today; kept explicit so a future palette version can
    // shift the wheel without repainting old meals (ClassColourTable is versioned).
    var paletteVersion: String = ClassColourTable.standard.version
    var onDecode: (Set<Int>) -> Void = { _ in }

    @State private var overlay: CGImage?

    var body: some View {
        Group {
            if let overlay {
                Image(decorative: overlay, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                Color.clear
            }
        }
        .task(id: mealId) { await load() }
    }

    private func load() async {
        guard
            let data = try? await store.artefactData(mealId: mealId, kind: MaskOverlayDecoder.maskKind),
            let decoded = MaskOverlayDecoder.decode(pngData: data, paletteVersion: paletteVersion)
        else {
            overlay = nil
            onDecode([])
            return
        }
        overlay = decoded.overlay
        onDecode(decoded.presentClassIds)
    }
}

// A decoded mask: the tinted RGBA overlay plus the class indices present in the
// raster.
struct DecodedMask {
    let overlay: CGImage
    let presentClassIds: Set<Int>
}

// Pure decode of the 8-bit greyscale label PNG (paired with
// `MaskArtefactWriter.encodeLabelPNG` in the Pipeline). Reading the CGImage's
// own data provider gives the native sample bytes = raw class indices, with no
// colour management applied (the encode side used DeviceGray, alpha-none, no
// ICC profile).
enum MaskOverlayDecoder {
    nonisolated static let maskKind = "mask"
    // Translucent so the photo underneath stays legible through the overlay.
    nonisolated static let overlayAlpha: Double = 0.55

    static func decode(pngData: Data, paletteVersion: String) -> DecodedMask? {
        guard let raster = labelRaster(pngData: pngData) else { return nil }
        let width = raster.width
        let height = raster.height
        let labels = raster.labels

        let palette = ClassPalette.standard
        let table = ClassColourTable(version: paletteVersion)
        let background = palette.background

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        var present = Set<Int>()
        // Cache the premultiplied bytes per index — a mask has a handful of
        // distinct classes over tens of thousands of pixels.
        var cache: [Int: (UInt8, UInt8, UInt8, UInt8)] = [:]

        rgba.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                let rowStart = y * width
                for x in 0..<width {
                    let idx = Int(labels[rowStart + x])
                    if idx == background { continue }  // transparent
                    present.insert(idx)
                    let px: (UInt8, UInt8, UInt8, UInt8)
                    if let cached = cache[idx] {
                        px = cached
                    } else {
                        let c = table.colour(forClassId: idx)
                        px = (
                            byte(c.red * overlayAlpha),
                            byte(c.green * overlayAlpha),
                            byte(c.blue * overlayAlpha),
                            byte(overlayAlpha)
                        )
                        cache[idx] = px
                    }
                    let o = (y * width + x) * 4
                    out[o] = px.0
                    out[o + 1] = px.1
                    out[o + 2] = px.2
                    out[o + 3] = px.3
                }
            }
        }

        guard let outProvider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let overlay = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: outProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else { return nil }

        return DecodedMask(overlay: overlay, presentClassIds: present)
    }

    private static func byte(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, (value * 255).rounded())))
    }

    // MARK: - Shared label-raster decode

    // Raw label raster decoded from the artefact PNG: one byte per pixel, the
    // class index, rows compacted to `width` (no padding). Shared by the
    // colourise path above and the contour path below.
    nonisolated struct LabelRaster: Sendable {
        let labels: [UInt8]
        let width: Int
        let height: Int
    }

    nonisolated static func labelRaster(pngData: Data) -> LabelRaster? {
        guard
            let source = CGImageSourceCreateWithData(pngData as CFData, nil),
            let cg = CGImageSourceCreateImageAtIndex(source, 0, nil),
            // One byte per pixel: the raw label raster. Anything else is not the
            // index map we wrote — fall back to photo-only.
            cg.bitsPerComponent == 8, cg.bitsPerPixel == 8,
            let provider = cg.dataProvider,
            let raw = provider.data
        else { return nil }

        let width = cg.width
        let height = cg.height
        let bytesPerRow = cg.bytesPerRow
        guard width > 0, height > 0, bytesPerRow >= width else { return nil }
        guard CFDataGetLength(raw) >= bytesPerRow * height,
              let bytes = CFDataGetBytePtr(raw) else { return nil }

        var labels = [UInt8](repeating: 0, count: width * height)
        labels.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                let src = bytes.advanced(by: y * bytesPerRow)
                out.baseAddress!.advanced(by: y * width).update(from: src, count: width)
            }
        }
        return LabelRaster(labels: labels, width: width, height: height)
    }

    // MARK: - Contour extraction (specs/ui/meal-review, task 10)

    // Parameters per the design's Overlay section.
    nonisolated static let contourLongEdge = 512            // extraction raster bound
    nonisolated static let contourMinAreaFraction = 0.0025  // 0.25% of the image
    nonisolated static let contourSimplifyEpsilon = 1.5     // px at extraction scale

    // Decodes the label PNG into per-class boundary loops. `includedClassIds`
    // is the Req 2.8 emission rule: contours are produced only for classes the
    // caller can show a row for (class ids present in macros.perClass) — a
    // marked area with no corresponding row would be uncorrectable. The full
    // `presentClassIds` set is still reported for EVERY class in the raster:
    // unknown_food and unsupported_liquid never carry a macro entry, so they
    // get no contour, yet they are the sole input to the Req 1.5 banners.
    //
    // `nonisolated` deliberately: the colourise decode above runs on the
    // MainActor and re-runs per appearance; this path is called through
    // `MaskContourCache` so the tracing happens off the MainActor and does not
    // block the push transition.
    nonisolated static func contours(
        from pngData: Data,
        paletteVersion: String,
        includedClassIds: Set<Int>
    ) -> MaskContourSet? {
        guard let full = labelRaster(pngData: pngData) else { return nil }
        let background = ClassPalette.standard.background

        // Present set from the full-resolution raster, before downsampling —
        // a small unknown region must not vanish from the banners because the
        // nearest-neighbour sample stepped over it.
        var present = Set<Int>()
        for label in full.labels {
            let id = Int(label)
            if id != background { present.insert(id) }
        }

        let raster = downsample(full, longEdge: contourLongEdge)
        let cellCount = Double(raster.width * raster.height)
        let minArea = contourMinAreaFraction * cellCount

        var byClass: [Int: [MaskContour]] = [:]
        for classId in includedClassIds.intersection(present) {
            guard classId != background, (0...255).contains(classId) else { continue }
            var contours: [MaskContour] = []
            for loop in traceBoundaries(of: UInt8(classId), in: raster) {
                let ring = collapseCollinear(loop)
                guard ring.count >= 3 else { continue }
                let (area2, cx, cy) = areaAndCentroid(ring)
                let area = abs(area2) / 2
                guard area >= minArea else { continue }  // speckle
                let points = ring.map { CGPoint(x: Double($0.x), y: Double($0.y)) }
                let simplified = simplifyClosed(points, epsilon: contourSimplifyEpsilon)
                guard simplified.count >= 3 else { continue }
                contours.append(MaskContour(
                    points: simplified.map {
                        CGPoint(x: $0.x / Double(raster.width), y: $0.y / Double(raster.height))
                    },
                    area: area / cellCount,
                    centroid: CGPoint(
                        x: cx / Double(raster.width),
                        y: cy / Double(raster.height)
                    )
                ))
            }
            if !contours.isEmpty { byClass[classId] = contours }
        }
        return MaskContourSet(presentClassIds: present, contoursByClassId: byClass)
    }

    // Nearest-neighbour downsample to <= `longEdge` on the long side. Class
    // identity must not be interpolated, so each output cell takes the label of
    // the nearest source pixel — never a blend.
    nonisolated private static func downsample(_ raster: LabelRaster, longEdge: Int) -> LabelRaster {
        let maxEdge = max(raster.width, raster.height)
        guard maxEdge > longEdge else { return raster }
        let scale = Double(longEdge) / Double(maxEdge)
        let ow = max(1, Int((Double(raster.width) * scale).rounded()))
        let oh = max(1, Int((Double(raster.height) * scale).rounded()))
        var out = [UInt8](repeating: 0, count: ow * oh)
        raster.labels.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<oh {
                    let sy = min(raster.height - 1, Int((Double(y) + 0.5) * Double(raster.height) / Double(oh)))
                    let srcRow = sy * raster.width
                    let dstRow = y * ow
                    for x in 0..<ow {
                        let sx = min(raster.width - 1, Int((Double(x) + 0.5) * Double(raster.width) / Double(ow)))
                        dst[dstRow + x] = src[srcRow + sx]
                    }
                }
            }
        }
        return LabelRaster(labels: out, width: ow, height: oh)
    }

    nonisolated private struct GridPoint {
        var x: Int
        var y: Int
    }

    // Traces every closed boundary loop of the target class by following the
    // directed lattice edges between an inside pixel and an outside one, with
    // the region kept on the left of the direction of travel (screen
    // coordinates, y down). Outer boundaries and holes both emerge as loops,
    // which is what even-odd Path fill and hit-testing need.
    nonisolated private static func traceBoundaries(of target: UInt8, in raster: LabelRaster) -> [[GridPoint]] {
        let w = raster.width
        let h = raster.height
        let vw = w + 1
        let labels = raster.labels

        // Outgoing-edge bitmask per lattice vertex; bit d set = a boundary edge
        // leaves the vertex in direction d (0 E, 1 S, 2 W, 3 N).
        var edges = [UInt8](repeating: 0, count: vw * (h + 1))
        labels.withUnsafeBufferPointer { px in
            @inline(__always) func inside(_ x: Int, _ y: Int) -> Bool {
                x >= 0 && x < w && y >= 0 && y < h && px[y * w + x] == target
            }
            for y in 0..<h {
                let row = y * w
                for x in 0..<w where px[row + x] == target {
                    if !inside(x, y - 1) { edges[y * vw + x + 1] |= 1 << 2 }        // top edge, W
                    if !inside(x, y + 1) { edges[(y + 1) * vw + x] |= 1 << 0 }      // bottom edge, E
                    if !inside(x - 1, y) { edges[y * vw + x] |= 1 << 1 }            // left edge, S
                    if !inside(x + 1, y) { edges[(y + 1) * vw + x + 1] |= 1 << 3 }  // right edge, N
                }
            }
        }

        let dxs = [1, 0, -1, 0]
        let dys = [0, 1, 0, -1]
        var remaining = edges
        var loops: [[GridPoint]] = []
        // Safety bound: a walk can never take more steps than directed edges exist.
        let maxSteps = 4 * edges.count

        for startV in 0..<remaining.count where remaining[startV] != 0 {
            while remaining[startV] != 0 {
                let startD = remaining[startV].trailingZeroBitCount
                var v = startV
                var d = startD
                var loop: [GridPoint] = []
                var steps = 0
                repeat {
                    remaining[v] &= ~UInt8(1 << d)
                    loop.append(GridPoint(x: v % vw, y: v / vw))
                    v += dys[d] * vw + dxs[d]
                    // Left-most existing turn (left, straight, right, back)
                    // keeps the region on the left and splits diagonal pinch
                    // points into separate loops. Decided on the immutable edge
                    // set so the pairing stays consistent across walks.
                    var nd = (d + 3) & 3
                    while edges[v] & UInt8(1 << nd) == 0 { nd = (nd + 1) & 3 }
                    d = nd
                    steps += 1
                } while !(v == startV && d == startD) && steps < maxSteps
                loops.append(loop)
            }
        }
        return loops
    }

    // Drops vertices where the boundary continues straight, leaving only the
    // corners. Purely a size reduction; the geometry is unchanged.
    nonisolated private static func collapseCollinear(_ loop: [GridPoint]) -> [GridPoint] {
        let n = loop.count
        guard n > 2 else { return loop }
        var out: [GridPoint] = []
        out.reserveCapacity(n)
        for i in 0..<n {
            let prev = loop[(i + n - 1) % n]
            let cur = loop[i]
            let next = loop[(i + 1) % n]
            let cross = (cur.x - prev.x) * (next.y - cur.y) - (cur.y - prev.y) * (next.x - cur.x)
            if cross != 0 { out.append(cur) }
        }
        return out
    }

    // Shoelace area (doubled, signed) and polygon centroid, exact on the
    // integer lattice. Holes wind opposite to outer boundaries, so callers take
    // the absolute area.
    nonisolated private static func areaAndCentroid(_ ring: [GridPoint]) -> (area2: Double, cx: Double, cy: Double) {
        var a2 = 0
        var sx = 0
        var sy = 0
        let n = ring.count
        for i in 0..<n {
            let p = ring[i]
            let q = ring[(i + 1) % n]
            let cross = p.x * q.y - q.x * p.y
            a2 += cross
            sx += (p.x + q.x) * cross
            sy += (p.y + q.y) * cross
        }
        guard a2 != 0 else {
            let mx = ring.reduce(0) { $0 + $1.x }
            let my = ring.reduce(0) { $0 + $1.y }
            return (0, Double(mx) / Double(n), Double(my) / Double(n))
        }
        return (Double(a2), Double(sx) / (3 * Double(a2)), Double(sy) / (3 * Double(a2)))
    }

    // Douglas-Peucker on a closed ring: anchor at vertex 0 and the vertex
    // farthest from it, simplify the two open chains, and rejoin — the split
    // stops the recursion from collapsing the loop to a line.
    nonisolated private static func simplifyClosed(_ points: [CGPoint], epsilon: Double) -> [CGPoint] {
        guard points.count > 4 else { return points }
        var far = 0
        var maxD = 0.0
        for (i, p) in points.enumerated() {
            let d = hypot(p.x - points[0].x, p.y - points[0].y)
            if d > maxD {
                maxD = d
                far = i
            }
        }
        guard far > 0 else { return points }
        let first = douglasPeucker(Array(points[0...far]), epsilon: epsilon)
        let second = douglasPeucker(Array(points[far...]) + [points[0]], epsilon: epsilon)
        return Array(first.dropLast()) + Array(second.dropLast())
    }

    nonisolated private static func douglasPeucker(_ points: [CGPoint], epsilon: Double) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            var maxDist = 0.0
            var idx = a
            for i in (a + 1)..<b {
                let d = perpendicularDistance(points[i], points[a], points[b])
                if d > maxDist {
                    maxDist = d
                    idx = i
                }
            }
            if maxDist > epsilon {
                keep[idx] = true
                stack.append((a, idx))
                stack.append((idx, b))
            }
        }
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    nonisolated private static func perpendicularDistance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        return abs(abx * (a.y - p.y) - (a.x - p.x) * aby) / lengthSquared.squareRoot()
    }
}

// One closed boundary loop of a detected food's areas, in unit-square
// coordinates (x and y each 0...1 over the mask raster; scale by the displayed
// image size to draw). Outer boundaries and holes are separate loops; render
// all of a class's loops into one Path with even-odd fill to reproduce the
// region for dimming (Req 2.5) and `Path.contains(_:eoFill:)` hit-testing.
nonisolated struct MaskContour: Sendable {
    // Closed polygon; the final point implicitly connects back to the first.
    let points: [CGPoint]
    // Enclosed area as a fraction of the image, always positive.
    let area: Double
    // Loop centroid in the unit square — the badge anchor for the largest loop.
    let centroid: CGPoint
}

// The decoded contour set for one meal's mask.
nonisolated struct MaskContourSet: Sendable {
    // Every non-background class index in the raster, contoured or not — the
    // Req 1.5 banner input (unknown_food / unsupported_liquid).
    let presentClassIds: Set<Int>
    // Boundary loops keyed by class index, only for the classes the caller
    // included (Req 2.8).
    let contoursByClassId: [Int: [MaskContour]]
}

// Off-MainActor decode with a per-meal cache for the contour path. The
// colourise path above stays MainActor-bound and uncached for its read-only
// consumer (MealOverviewView); the review surface goes through this actor so
// the trace runs off the MainActor and a re-appearance of the same meal —
// CaptureFlowView resyncs presentation on back-gesture pop — does not re-run
// it during the push transition.
actor MaskContourCache {
    static let shared = MaskContourCache()

    private var cache: [UUID: MaskContourSet] = [:]

    func contours(
        store: any PersistenceStore,
        mealId: UUID,
        paletteVersion: String,
        includedClassIds: Set<Int>
    ) async -> MaskContourSet? {
        if let cached = cache[mealId] { return cached }
        guard
            let data = try? await store.artefactData(mealId: mealId, kind: MaskOverlayDecoder.maskKind),
            let set = MaskOverlayDecoder.contours(
                from: data,
                paletteVersion: paletteVersion,
                includedClassIds: includedClassIds
            )
        else { return nil }  // no artefact / undecodable: photo-only, retried next appearance (Req 1.6)
        cache[mealId] = set
        return set
    }
}

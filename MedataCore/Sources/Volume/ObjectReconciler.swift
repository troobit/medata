import Foundation
import Segmentation

// Label reconciliation before volume (two-view-trust Req 2, Decisions 5–6).
// The segmenter splits one roll into several labels: unknown_food patches on
// a named class, or two bread classes across one blob, and differently across
// the two views. `MaskMatcher` matches by label only and the height field
// integrates per label, so one object became two or three rows. Per view, the
// carvable mask is tested for being ONE connected object (largest component
// after a small dilation holds ≥ 90 % of the carvable pixels); a single
// object takes one class: the user's when given, else the named carvable
// class with the most pixels (the nadir's over the oblique's on two-view),
// else unknown_food. A view that is not a single object — a multi-food
// plate — is left alone (Req 2.3).

public struct TwoViewReconciliation: Codable, Sendable, Equatable {
    // Carvable classes present in each view before reconciliation, sorted.
    // Oblique fields are nil on the single-view path.
    public let nadirClasses: [Int]
    public let obliqueClasses: [Int]?
    public let nadirSingleObject: Bool
    public let obliqueSingleObject: Bool?
    // nil when no view was a single object.
    public let chosenClass: Int?
    // Whether any pixel was relabelled.
    public let applied: Bool

    public init(nadirClasses: [Int], obliqueClasses: [Int]?, nadirSingleObject: Bool,
                obliqueSingleObject: Bool?, chosenClass: Int?, applied: Bool) {
        self.nadirClasses = nadirClasses
        self.obliqueClasses = obliqueClasses
        self.nadirSingleObject = nadirSingleObject
        self.obliqueSingleObject = obliqueSingleObject
        self.chosenClass = chosenClass
        self.applied = applied
    }
}

public enum ObjectReconciler {
    // Bridges the speckle gaps between a named region and its unknown patches.
    public static let dilationRadiusPx = 3
    public static let singleObjectFraction: Float = 0.9

    /// Single-view: one connected object with unknown patches becomes its
    /// dominant named class.
    public static func reconcile(
        nadir: SegmentationResult, palette: ClassPalette, userClass: Int? = nil
    ) -> (nadir: SegmentationResult, reconciliation: TwoViewReconciliation) {
        let view = inspect(nadir.argmax, palette: palette)
        guard view.singleObject else {
            return (nadir, .init(nadirClasses: view.classes, obliqueClasses: nil,
                                 nadirSingleObject: false, obliqueSingleObject: nil,
                                 chosenClass: nil, applied: false))
        }
        let chosen = userClass ?? view.dominantClass
        let done = view.classes == [chosen]
        return (done ? nadir : relabel(nadir, to: chosen, palette: palette),
                .init(nadirClasses: view.classes, obliqueClasses: nil,
                      nadirSingleObject: true, obliqueSingleObject: nil,
                      chosenClass: chosen, applied: !done))
    }

    /// Two-view: every single-object view is relabelled to one class so the
    /// carve has a matched class with both silhouettes.
    public static func reconcile(
        nadir: SegmentationResult, oblique: SegmentationResult,
        palette: ClassPalette, userClass: Int? = nil
    ) -> (nadir: SegmentationResult, oblique: SegmentationResult, reconciliation: TwoViewReconciliation) {
        let n = inspect(nadir.argmax, palette: palette)
        let o = inspect(oblique.argmax, palette: palette)
        func record(_ chosen: Int?, applied: Bool) -> TwoViewReconciliation {
            .init(nadirClasses: n.classes, obliqueClasses: o.classes,
                  nadirSingleObject: n.singleObject, obliqueSingleObject: o.singleObject,
                  chosenClass: chosen, applied: applied)
        }
        guard n.singleObject || o.singleObject else {
            return (nadir, oblique, record(nil, applied: false))
        }
        let named = { (v: ViewObject) -> Int? in
            v.singleObject && v.dominantClass != palette.unknownFood ? v.dominantClass : nil
        }
        let chosen = userClass ?? named(n) ?? named(o) ?? palette.unknownFood
        let nadirDone = !n.singleObject || n.classes == [chosen]
        let obliqueDone = !o.singleObject || o.classes == [chosen]
        return (nadirDone ? nadir : relabel(nadir, to: chosen, palette: palette),
                obliqueDone ? oblique : relabel(oblique, to: chosen, palette: palette),
                record(chosen, applied: !(nadirDone && obliqueDone)))
    }

    struct ViewObject {
        let classes: [Int]          // carvable classes present, sorted
        let singleObject: Bool
        let dominantClass: Int      // named class with most pixels, else unknownFood
    }

    static func inspect(_ map: ArgmaxMap, palette: ClassPalette) -> ViewObject {
        let w = map.width, h = map.height
        var counts = [Int](repeating: 0, count: 256)
        var mask = [UInt8](repeating: 0, count: w * h)
        map.pixels.withUnsafeBytes { raw in
            let lab = raw.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<(w * h) where palette.isCarvableClass(Int(lab[i])) {
                counts[Int(lab[i])] += 1
                mask[i] = 1
            }
        }
        let classes = (0..<256).filter { counts[$0] > 0 }
        let total = classes.reduce(0) { $0 + counts[$1] }
        let dominant = classes.filter { $0 != palette.unknownFood }
            .max { counts[$0] < counts[$1] } ?? palette.unknownFood
        let largest = largestComponentCarvablePixels(
            mask, dilated: dilate(mask, width: w, height: h, radius: dilationRadiusPx),
            width: w, height: h)
        let single = total > 0 && Float(largest) >= singleObjectFraction * Float(total)
        return ViewObject(classes: classes, singleObject: single, dominantClass: dominant)
    }

    /// Square (Chebyshev) dilation by `radius`, as two separable passes.
    static func dilate(_ mask: [UInt8], width w: Int, height h: Int, radius r: Int) -> [UInt8] {
        var rows = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w where mask[y * w + x] == 1 {
                for dx in max(0, x - r)...min(w - 1, x + r) { rows[y * w + dx] = 1 }
            }
        }
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w where rows[y * w + x] == 1 {
                for dy in max(0, y - r)...min(h - 1, y + r) { out[dy * w + x] = 1 }
            }
        }
        return out
    }

    /// Carvable pixels inside the largest 4-connected component of the
    /// dilated mask. `dilated` is consumed as the visited map.
    static func largestComponentCarvablePixels(
        _ mask: [UInt8], dilated: [UInt8], width w: Int, height h: Int
    ) -> Int {
        var visited = dilated
        var largest = 0
        var stack: [Int] = []
        for start in 0..<(w * h) where visited[start] == 1 {
            var count = 0
            visited[start] = 0
            stack.append(start)
            while let i = stack.popLast() {
                if mask[i] == 1 { count += 1 }
                let x = i % w, y = i / w
                if x > 0, visited[i - 1] == 1 { visited[i - 1] = 0; stack.append(i - 1) }
                if x < w - 1, visited[i + 1] == 1 { visited[i + 1] = 0; stack.append(i + 1) }
                if y > 0, visited[i - w] == 1 { visited[i - w] = 0; stack.append(i - w) }
                if y < h - 1, visited[i + w] == 1 { visited[i + w] = 0; stack.append(i + w) }
            }
            largest = max(largest, count)
        }
        return largest
    }

    /// Every carvable pixel labelled `chosen`; in the probability tensor the
    /// mass of every other carvable channel is added to `chosen`'s channel and
    /// those channels set to 0. Background and liquid channels are untouched.
    static func relabel(_ r: SegmentationResult, to chosen: Int, palette: ClassPalette) -> SegmentationResult {
        let w = r.probabilities.width, h = r.probabilities.height, k = r.probabilities.classes
        let others = (0..<k).filter { palette.isCarvableClass($0) && $0 != chosen }
        var probs = r.probabilities.bytes
        var labels = r.argmax.pixels
        probs.withUnsafeMutableBytes { p in
            let q = p.bindMemory(to: Float16.self).baseAddress!
            labels.withUnsafeMutableBytes { l in
                let lab = l.bindMemory(to: UInt8.self).baseAddress!
                for i in 0..<(w * h) {
                    if palette.isCarvableClass(Int(lab[i])) { lab[i] = UInt8(chosen) }
                    let off = i * k
                    var mass = Float(q[off + chosen])
                    for c in others {
                        mass += Float(q[off + c])
                        q[off + c] = 0
                    }
                    q[off + chosen] = Float16(mass)
                }
            }
        }
        return SegmentationResult(
            probabilities: ProbabilityTensor(bytes: probs, height: h, width: w, classes: k,
                                             palette: r.probabilities.palette),
            argmax: ArgmaxMap(pixels: labels, height: h, width: w),
            perClassMeanProb: r.perClassMeanProb, sigmaSeg: r.sigmaSeg, timings: r.timings,
            foodCoveragePercent: r.foodCoveragePercent, candidateEvidence: r.candidateEvidence)
    }
}

import Foundation
import Segmentation

// Cross-view label reconciliation before the carve (two-view-trust Req 2,
// Decision 5). `MaskMatcher` matches classes by label only, so a single food
// the segmenter names differently in the two views (bread_wholemeal from
// above, unknown_food from the side) never has a matched class and each view
// is extruded alone at the 30 mm prior. On a single-food plate the two labels
// are the same object, so both views are relabelled to one carvable class:
// the user's when given, else the named class over unknown_food, else the
// nadir's over the oblique's. A view carrying two or more named classes is a
// multi-food plate and is left alone (Req 2.3).

public struct TwoViewReconciliation: Codable, Sendable, Equatable {
    // Carvable classes present in each view before reconciliation, sorted.
    public let nadirClasses: [Int]
    public let obliqueClasses: [Int]
    // nil when a view had two or more named classes.
    public let chosenClass: Int?
    // Whether any pixel was relabelled.
    public let applied: Bool

    public init(nadirClasses: [Int], obliqueClasses: [Int], chosenClass: Int?, applied: Bool) {
        self.nadirClasses = nadirClasses
        self.obliqueClasses = obliqueClasses
        self.chosenClass = chosenClass
        self.applied = applied
    }
}

public enum TwoViewReconciler {
    public static func reconcile(
        nadir: SegmentationResult,
        oblique: SegmentationResult,
        palette: ClassPalette,
        userClass: Int? = nil
    ) -> (nadir: SegmentationResult, oblique: SegmentationResult, reconciliation: TwoViewReconciliation) {
        let nadirClasses = carvableClasses(nadir.argmax, palette: palette)
        let obliqueClasses = carvableClasses(oblique.argmax, palette: palette)
        let nadirNamed = nadirClasses.filter { $0 != palette.unknownFood }
        let obliqueNamed = obliqueClasses.filter { $0 != palette.unknownFood }
        func record(_ chosen: Int?, applied: Bool) -> TwoViewReconciliation {
            TwoViewReconciliation(nadirClasses: nadirClasses, obliqueClasses: obliqueClasses,
                                  chosenClass: chosen, applied: applied)
        }
        guard nadirNamed.count < 2, obliqueNamed.count < 2 else {
            return (nadir, oblique, record(nil, applied: false))
        }
        let chosen = userClass ?? nadirNamed.first ?? obliqueNamed.first ?? palette.unknownFood
        let nadirDone = nadirClasses.allSatisfy { $0 == chosen }
        let obliqueDone = obliqueClasses.allSatisfy { $0 == chosen }
        if nadirDone && obliqueDone {
            return (nadir, oblique, record(chosen, applied: false))
        }
        return (nadirDone ? nadir : relabel(nadir, to: chosen, palette: palette),
                obliqueDone ? oblique : relabel(oblique, to: chosen, palette: palette),
                record(chosen, applied: true))
    }

    static func carvableClasses(_ map: ArgmaxMap, palette: ClassPalette) -> [Int] {
        MaskMatcher.foodClassesPresent(map, palette: palette).sorted()
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

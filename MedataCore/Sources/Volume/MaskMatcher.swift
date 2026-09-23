import Foundation
import Segmentation

// Cross-view mask matching per design §6.11 / Req 10.4. Class-equivalence only — no
// Hungarian / spatial matching in v1. Output feeds §6.6 voxel kernel and §6.8
// confidence factors (single-view-only classes get σ_view = 0.75).

public struct MaskMatchingResult: Sendable, Equatable {
    public let classesInView1: Set<Int>
    public let classesInView2: Set<Int>
    public let matchedClasses: Set<Int>          // intersection
    public let singleViewOnlyClasses: Set<Int>   // symmetric difference

    public init(classesInView1: Set<Int>, classesInView2: Set<Int>,
                matchedClasses: Set<Int>, singleViewOnlyClasses: Set<Int>) {
        self.classesInView1 = classesInView1
        self.classesInView2 = classesInView2
        self.matchedClasses = matchedClasses
        self.singleViewOnlyClasses = singleViewOnlyClasses
    }

    public func singleViewOnly(view: Int) -> Set<Int> {
        switch view {
        case 1: return classesInView1.subtracting(classesInView2)
        case 2: return classesInView2.subtracting(classesInView1)
        default: return []
        }
    }
}

public enum MaskMatcher {
    public static func match(
        view1: ArgmaxMap,
        view2: ArgmaxMap,
        palette: ClassPalette
    ) -> MaskMatchingResult {
        let foodIn1 = foodClassesPresent(view1, palette: palette)
        let foodIn2 = foodClassesPresent(view2, palette: palette)
        return MaskMatchingResult(
            classesInView1: foodIn1,
            classesInView2: foodIn2,
            matchedClasses: foodIn1.intersection(foodIn2),
            singleViewOnlyClasses: foodIn1.symmetricDifference(foodIn2)
        )
    }

    static func foodClassesPresent(_ map: ArgmaxMap, palette: ClassPalette) -> Set<Int> {
        var out: Set<Int> = []
        map.pixels.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<(map.width * map.height) {
                let c = Int(buf[i])
                if palette.isFoodClass(c) { out.insert(c) }
            }
        }
        return out
    }
}

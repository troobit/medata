import Foundation
import Segmentation
import Testing
@testable import Volume

// two-view-trust Req 2.1–2.3: both views are relabelled to one carvable class
// before the carve — the user's, else the named class over unknown_food, else
// the nadir's over the oblique's — in the label map and in the probability
// tensor; a view with two named classes disables the pass.
@Suite("TwoViewReconciler")
struct TwoViewReconcilerTests {
    // food_a = 0, food_b = 1; bg = 2, unknown = 3, unsupported = 4.
    static let palette = ClassPalette(
        foodClasses: ["food_a", "food_b"], background: 2, unknownFood: 3,
        unsupportedLiquid: 4, version: "test")
    static let w = 4, h = 2

    /// Left half labelled `left` with p = 0.7 (0.3 on the other food-like
    /// class), right half background with p = 1.
    static func view(left: Int, other: Int = 2) -> SegmentationResult {
        let k = palette.totalClasses
        var probs = [Float16](repeating: 0, count: w * h * k)
        var labels = [UInt8](repeating: UInt8(palette.background), count: w * h)
        for i in 0..<(w * h) {
            if i % w < w / 2 {
                labels[i] = UInt8(left)
                probs[i * k + left] = 0.7
                probs[i * k + other] += 0.3
            } else {
                probs[i * k + palette.background] = 1
            }
        }
        let bytes = probs.withUnsafeBytes { Data($0) }
        return SegmentationResult(
            probabilities: ProbabilityTensor(bytes: bytes, height: h, width: w, classes: k, palette: palette),
            argmax: ArgmaxMap(pixels: Data(labels), height: h, width: w),
            perClassMeanProb: [:], sigmaSeg: 1)
    }

    /// Two-food view: left half food_a, right half food_b.
    static func twoFoods() -> SegmentationResult {
        let k = palette.totalClasses
        var probs = [Float16](repeating: 0, count: w * h * k)
        var labels = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let c = i % w < w / 2 ? 0 : 1
            labels[i] = UInt8(c)
            probs[i * k + c] = 1
        }
        let bytes = probs.withUnsafeBytes { Data($0) }
        return SegmentationResult(
            probabilities: ProbabilityTensor(bytes: bytes, height: h, width: w, classes: k, palette: palette),
            argmax: ArgmaxMap(pixels: Data(labels), height: h, width: w),
            perClassMeanProb: [:], sigmaSeg: 1)
    }

    static func labels(_ r: SegmentationResult) -> [Int] { r.argmax.pixels.map(Int.init) }

    static func prob(_ r: SegmentationResult, pixel: Int, class c: Int) -> Float {
        r.probabilities.bytes.withUnsafeBytes {
            Float($0.bindMemory(to: Float16.self)[pixel * palette.totalClasses + c])
        }
    }

    @Test func namedBeatsUnknownAndMovesMass() {
        let out = TwoViewReconciler.reconcile(
            nadir: Self.view(left: 3, other: 0), oblique: Self.view(left: 0, other: 3),
            palette: Self.palette)
        #expect(out.reconciliation == .init(nadirClasses: [3], obliqueClasses: [0], chosenClass: 0, applied: true))
        #expect(Self.labels(out.nadir) == [0, 0, 2, 2, 0, 0, 2, 2])
        #expect(Self.labels(out.oblique) == [0, 0, 2, 2, 0, 0, 2, 2])
        // Nadir pixel 0 held 0.7 unknown + 0.3 food_a: all of it is food_a now.
        #expect(abs(Self.prob(out.nadir, pixel: 0, class: 0) - 1) < 0.002)
        #expect(Self.prob(out.nadir, pixel: 0, class: 3) == 0)
        // Background pixels and channels are untouched.
        #expect(Self.prob(out.nadir, pixel: 3, class: 2) == 1)
        #expect(Self.labels(out.oblique) == Self.labels(Self.view(left: 0)))
    }

    @Test func nadirNameBeatsObliqueName() {
        let out = TwoViewReconciler.reconcile(
            nadir: Self.view(left: 1), oblique: Self.view(left: 0), palette: Self.palette)
        #expect(out.reconciliation.chosenClass == 1)
        #expect(out.reconciliation.applied)
        #expect(Self.labels(out.nadir) == Self.labels(Self.view(left: 1)))
        #expect(Self.labels(out.oblique) == [1, 1, 2, 2, 1, 1, 2, 2])
        #expect(abs(Self.prob(out.oblique, pixel: 0, class: 1) - 0.7) < 0.002)
        #expect(Self.prob(out.oblique, pixel: 0, class: 0) == 0)
    }

    @Test func twoNamedClassesInOneViewLeavesBothUntouched() {
        let nadir = Self.twoFoods(), oblique = Self.view(left: 3)
        let out = TwoViewReconciler.reconcile(nadir: nadir, oblique: oblique, palette: Self.palette)
        #expect(out.reconciliation == .init(nadirClasses: [0, 1], obliqueClasses: [3], chosenClass: nil, applied: false))
        #expect(out.nadir.argmax == nadir.argmax && out.nadir.probabilities == nadir.probabilities)
        #expect(out.oblique.argmax == oblique.argmax && out.oblique.probabilities == oblique.probabilities)
    }

    @Test func equalClassesAreANoOp() {
        let nadir = Self.view(left: 0), oblique = Self.view(left: 0)
        let out = TwoViewReconciler.reconcile(nadir: nadir, oblique: oblique, palette: Self.palette)
        #expect(out.reconciliation == .init(nadirClasses: [0], obliqueClasses: [0], chosenClass: 0, applied: false))
        #expect(out.nadir.probabilities == nadir.probabilities)
        let unknowns = TwoViewReconciler.reconcile(
            nadir: Self.view(left: 3), oblique: Self.view(left: 3), palette: Self.palette)
        #expect(unknowns.reconciliation.chosenClass == 3 && !unknowns.reconciliation.applied)
    }

    @Test func userClassOverridesBothViews() {
        let out = TwoViewReconciler.reconcile(
            nadir: Self.view(left: 0), oblique: Self.view(left: 3), palette: Self.palette, userClass: 1)
        #expect(out.reconciliation.chosenClass == 1)
        #expect(out.reconciliation.applied)
        #expect(Self.labels(out.nadir) == [1, 1, 2, 2, 1, 1, 2, 2])
        #expect(Self.labels(out.oblique) == [1, 1, 2, 2, 1, 1, 2, 2])
        #expect(abs(Self.prob(out.nadir, pixel: 0, class: 1) - 0.7) < 0.002)
        #expect(abs(Self.prob(out.oblique, pixel: 0, class: 1) - 0.7) < 0.002)
    }
}

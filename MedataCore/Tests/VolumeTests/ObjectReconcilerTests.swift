import Foundation
import Segmentation
import Testing
@testable import Volume

// two-view-trust Req 2.1–2.3 (Decision 6): a view whose carvable pixels form
// one connected object takes one class — the user's, else the named class
// with the most pixels, else unknown_food — in the label map and in the
// probability tensor; on two-view the nadir's name beats the oblique's. Two
// separate blobs are a multi-food plate and stay untouched.
@Suite("ObjectReconciler")
struct ObjectReconcilerTests {
    // food_a = 0, food_b = 1; bg = 2, unknown = 3, unsupported = 4.
    static let palette = ClassPalette(
        foodClasses: ["food_a", "food_b"], background: 2, unknownFood: 3,
        unsupportedLiquid: 4, version: "test")

    /// `label(x)` per column (rows identical). A carvable pixel holds 0.7 on
    /// its label and 0.3 on `other` when given, else 1; background holds 1.
    static func seg(w: Int, h: Int = 2, other: Int? = nil, label: (Int) -> Int) -> SegmentationResult {
        let k = palette.totalClasses
        var probs = [Float16](repeating: 0, count: w * h * k)
        var labels = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let c = label(i % w)
            labels[i] = UInt8(c)
            if let other, palette.isCarvableClass(c) {
                probs[i * k + c] = 0.7
                probs[i * k + other] += 0.3
            } else {
                probs[i * k + c] = 1
            }
        }
        let bytes = probs.withUnsafeBytes { Data($0) }
        return SegmentationResult(
            probabilities: ProbabilityTensor(bytes: bytes, height: h, width: w, classes: k, palette: palette),
            argmax: ArgmaxMap(pixels: Data(labels), height: h, width: w),
            perClassMeanProb: [:], sigmaSeg: 1)
    }

    /// Left half `left`, right half background.
    static func blob(_ left: Int, other: Int? = nil) -> SegmentationResult {
        seg(w: 4, other: other) { $0 < 2 ? left : 2 }
    }

    static func labels(_ r: SegmentationResult) -> [Int] { r.argmax.pixels.map(Int.init) }

    static func prob(_ r: SegmentationResult, pixel: Int, class c: Int) -> Float {
        r.probabilities.bytes.withUnsafeBytes {
            Float($0.bindMemory(to: Float16.self)[pixel * palette.totalClasses + c])
        }
    }

    @Test func namedBeatsUnknownAndMovesMass() {
        let out = ObjectReconciler.reconcile(
            nadir: Self.blob(3, other: 0), oblique: Self.blob(0, other: 3), palette: Self.palette)
        #expect(out.reconciliation == .init(
            nadirClasses: [3], obliqueClasses: [0], nadirSingleObject: true, obliqueSingleObject: true,
            chosenClass: 0, applied: true))
        #expect(Self.labels(out.nadir) == [0, 0, 2, 2, 0, 0, 2, 2])
        #expect(Self.labels(out.oblique) == [0, 0, 2, 2, 0, 0, 2, 2])
        // Nadir pixel 0 held 0.7 unknown + 0.3 food_a: all of it is food_a now.
        #expect(abs(Self.prob(out.nadir, pixel: 0, class: 0) - 1) < 0.002)
        #expect(Self.prob(out.nadir, pixel: 0, class: 3) == 0)
        // Background pixels and channels are untouched.
        #expect(Self.prob(out.nadir, pixel: 3, class: 2) == 1)
    }

    @Test func nadirNameBeatsObliqueName() {
        let out = ObjectReconciler.reconcile(
            nadir: Self.blob(1), oblique: Self.blob(0), palette: Self.palette)
        #expect(out.reconciliation.chosenClass == 1)
        #expect(out.reconciliation.applied)
        #expect(Self.labels(out.nadir) == Self.labels(Self.blob(1)))
        #expect(Self.labels(out.oblique) == [1, 1, 2, 2, 1, 1, 2, 2])
        #expect(Self.prob(out.oblique, pixel: 0, class: 1) == 1)
        #expect(Self.prob(out.oblique, pixel: 0, class: 0) == 0)
    }

    @Test func splitNamesOnOneBlobMergeToTheLarger() {
        // One 6-column blob: 4 columns food_a, 2 columns food_b.
        let nadir = Self.seg(w: 8) { $0 < 4 ? 0 : ($0 < 6 ? 1 : 2) }
        let out = ObjectReconciler.reconcile(nadir: nadir, palette: Self.palette)
        #expect(out.reconciliation == .init(
            nadirClasses: [0, 1], obliqueClasses: nil, nadirSingleObject: true, obliqueSingleObject: nil,
            chosenClass: 0, applied: true))
        #expect(Self.labels(out.nadir).prefix(8) == [0, 0, 0, 0, 0, 0, 2, 2])
        #expect(Self.prob(out.nadir, pixel: 5, class: 0) == 1 && Self.prob(out.nadir, pixel: 5, class: 1) == 0)
    }

    @Test func twoSeparateBlobsStayUntouched() {
        // food_a at x 0–2 and food_b at x 12–15: a 9 px gap the dilation does not bridge.
        let nadir = Self.seg(w: 16) { $0 < 3 ? 0 : ($0 >= 12 ? 1 : 2) }
        let single = ObjectReconciler.reconcile(nadir: nadir, palette: Self.palette)
        #expect(single.reconciliation == .init(
            nadirClasses: [0, 1], obliqueClasses: nil, nadirSingleObject: false, obliqueSingleObject: nil,
            chosenClass: nil, applied: false))
        #expect(single.nadir.argmax == nadir.argmax && single.nadir.probabilities == nadir.probabilities)
        // Two-view: the plate view stays; the single-object oblique takes its own name.
        let two = ObjectReconciler.reconcile(nadir: nadir, oblique: Self.blob(3), palette: Self.palette)
        #expect(two.reconciliation.nadirSingleObject == false && two.reconciliation.obliqueSingleObject == true)
        #expect(two.reconciliation.chosenClass == 3 && two.reconciliation.applied == false)
        #expect(two.nadir.argmax == nadir.argmax)
    }

    @Test func unknownSpecklesAreBridgedByDilation() {
        // food_a x 0–11 (24 px), unknown 16 px after a 2 px gap: one object.
        let bridged = Self.seg(w: 32) { $0 < 12 ? 0 : ((14..<22).contains($0) ? 3 : 2) }
        let out = ObjectReconciler.reconcile(nadir: bridged, palette: Self.palette)
        #expect(out.reconciliation.nadirSingleObject && out.reconciliation.chosenClass == 0 && out.reconciliation.applied)
        #expect(Self.labels(out.nadir)[14] == 0 && Self.labels(out.nadir)[12] == 2)
        // The same patch after an 8 px gap is a second object (60 % < 90 %).
        let apart = Self.seg(w: 32) { $0 < 12 ? 0 : ((20..<28).contains($0) ? 3 : 2) }
        let kept = ObjectReconciler.reconcile(nadir: apart, palette: Self.palette)
        #expect(!kept.reconciliation.nadirSingleObject && !kept.reconciliation.applied)
    }

    @Test func equalClassesAreANoOp() {
        let out = ObjectReconciler.reconcile(nadir: Self.blob(0), oblique: Self.blob(0), palette: Self.palette)
        #expect(out.reconciliation.chosenClass == 0 && !out.reconciliation.applied)
        #expect(out.nadir.probabilities == Self.blob(0).probabilities)
        let unknowns = ObjectReconciler.reconcile(nadir: Self.blob(3), oblique: Self.blob(3), palette: Self.palette)
        #expect(unknowns.reconciliation.chosenClass == 3 && !unknowns.reconciliation.applied)
    }

    @Test func userClassOverridesBothViews() {
        let out = ObjectReconciler.reconcile(
            nadir: Self.blob(0), oblique: Self.blob(3), palette: Self.palette, userClass: 1)
        #expect(out.reconciliation.chosenClass == 1 && out.reconciliation.applied)
        #expect(Self.labels(out.nadir) == [1, 1, 2, 2, 1, 1, 2, 2])
        #expect(Self.labels(out.oblique) == [1, 1, 2, 2, 1, 1, 2, 2])
        #expect(Self.prob(out.nadir, pixel: 0, class: 1) == 1)
        let single = ObjectReconciler.reconcile(nadir: Self.blob(0), palette: Self.palette, userClass: 1)
        #expect(single.reconciliation.chosenClass == 1 && Self.labels(single.nadir)[0] == 1)
    }
}

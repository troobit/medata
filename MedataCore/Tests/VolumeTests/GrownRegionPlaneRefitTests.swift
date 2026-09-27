import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import Testing
@testable import Volume

// The plane-adoption rule both volume branches share (depth-grown-food-region
// Decisions 3–4, two-view-trust Decision 10). Scene as in FoodRegionGrowthTests:
// nadir camera, first plane at z = −600 mm, colour 64×48 over depth 16×12, a
// slab of cells at 560 mm (40 mm above the plane) on a plate at 599 mm. One
// food_0 seed cell on the slab; growth recovers the slab, and the fitter is a
// canned closure so each refit outcome is exercised on its own.

@Suite("GrownRegionPlaneRefit")
struct GrownRegionPlaneRefitTests {

    let palette = makePalette(numFood: 2)
    let w = 64, h = 48, dw = 16, dh = 12
    let k = CameraIntrinsics(fx: 80, fy: 80, cx: 32, cy: 24,
                             distortion: [], imageWidth: 64, imageHeight: 48)
    let first = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -600,
                             residualMm: 0.5, convergedIterations: nil)

    func inSlab(_ dx: Int, _ dy: Int) -> Bool { (4..<12).contains(dx) && (3..<9).contains(dy) }

    var slabDepth: DepthMap {
        makeDepthMap(width: dw, height: dh, intrinsics: k) { dy, dx in inSlab(dx, dy) ? 560 : 599 }
    }

    var seed: ArgmaxMap {
        makeArgmax(width: w, height: h) { y, x in
            x / 4 == 5 && y / 4 == 4 ? 0 : palette.background
        }
    }

    func plane(at distanceMm: Float) -> SupportPlane {
        SupportPlane(normal: Vec3(0, 0, 1), distanceMm: distanceMm,
                     residualMm: 0.8, convergedIterations: nil)
    }

    func outcome(_ plane: SupportPlane?, _ reference: SupportPlaneReference?) -> SupportPlaneFitOutcome {
        SupportPlaneFitOutcome(
            plane: plane,
            stats: SupportPlaneFitStats(candidatePointCount: 40, inlierCount: 30,
                                        residualMm: plane?.residualMm ?? -1,
                                        reference: reference),
            refusal: plane == nil ? .lidarFitDegenerate : nil)
    }

    func refit(offsetMm: Float = 0, reference: SupportPlaneReference? = .foodSupport,
               fit: (BinaryMask) -> SupportPlaneFitOutcome) -> GrownRegionPlaneRefit.Outcome {
        GrownRegionPlaneRefit.refit(
            argmax: seed, depth: slabDepth, intrinsics: k,
            supportPlane: first, supportReference: reference, supportOffsetMm: offsetMm,
            palette: palette, config: .standard, fit: fit)
    }

    @Test("a foodSupport refit is adopted with its statistics")
    func foodSupportRefitIsAdopted() {
        var masks: [BinaryMask] = []
        let r = refit { mask in masks.append(mask); return outcome(plane(at: -598), .foodSupport) }
        #expect(r.adopted)
        #expect(r.plane.distanceMm == -598)
        #expect(r.reference == .foodSupport)
        #expect(r.adoptedStats?.candidatePointCount == 40)
        #expect(r.refitReference == .foodSupport)
        #expect(!r.refitRefused)
        #expect(r.growth.applied)
        // The refit was asked for from the GROWN mask, not the seed.
        let asked = try? #require(masks.first)
        #expect((asked?.pixels.filter { $0 != 0 }.count ?? 0) > 16)
    }

    @Test("an edgeBand refit is never adopted (Decision 3), the region still grows")
    func edgeBandRefitIsNotAdopted() {
        let r = refit { _ in outcome(plane(at: -620), .edgeBand) }
        #expect(!r.adopted)
        #expect(r.plane.distanceMm == -600)
        #expect(r.reference == .foodSupport)
        #expect(r.refitReference == .edgeBand)
        #expect(!r.refitRefused)
        #expect(r.growth.applied)
    }

    @Test("a refused refit keeps the first plane and prunes with the ring offset")
    func refusalKeepsTheFirstPlane() {
        let offset: Float = 2
        let r = refit(offsetMm: offset, reference: .edgeBand) { _ in outcome(nil, nil) }
        #expect(!r.adopted)
        #expect(r.plane.distanceMm == -600)
        #expect(r.reference == .edgeBand)
        #expect(r.refitRefused)
        #expect(r.refitReference == nil)
        // What the caller would have pruned by hand against the first plane
        // at the same offset.
        let candidate = FoodRegionGrowth.grow(
            argmax: seed, depth: slabDepth, intrinsics: k, supportPlane: first,
            supportOffsetMm: offset, palette: palette, config: .standard)
        let byHand = FoodRegionGrowth.prune(
            candidate, depth: slabDepth, intrinsics: k, supportPlane: first,
            supportOffsetMm: offset, palette: palette, config: .standard)
        #expect(r.growth.applied == byHand.applied)
        #expect(r.growth.foodPixelsAfter == byHand.foodPixelsAfter)
    }

    @Test("a region pruned to nothing keeps the first plane even on a foodSupport refit")
    func regionPrunedToEmptyKeepsTheFirstPlane() {
        // A refit plane 45 mm nearer the camera than the first puts the slab
        // top 5 mm BELOW it, so every added cell fails the floor.
        let r = refit { _ in outcome(plane(at: -555), .foodSupport) }
        #expect(r.refitReference == .foodSupport)
        #expect(!r.growth.applied)
        #expect(!r.adopted)
        #expect(r.plane.distanceMm == -600)
        #expect(r.reference == .foodSupport)
    }

    @Test("no growth means no refit and the first plane untouched")
    func noGrowthNoRefit() {
        var fits = 0
        let r = GrownRegionPlaneRefit.refit(
            argmax: seed, depth: slabDepth, intrinsics: k,
            supportPlane: first, supportReference: .edgeBand, supportOffsetMm: 0,
            palette: palette, config: .disabled) { _ in
                fits += 1
                return outcome(plane(at: -598), .foodSupport)
            }
        #expect(fits == 0)
        #expect(!r.refitAttempted)
        #expect(!r.adopted)
        #expect(!r.growth.applied)
        #expect(r.plane.distanceMm == -600)
        #expect(r.reference == .edgeBand)
    }

    // The regression bar for the refactor: the helper's plane and map are the
    // ones the single-view branch produced by hand before it existed.
    @Test("the helper reproduces the verbatim grow → refit → prune → adopt sequence")
    func parityWithTheVerbatimSequence() {
        let fit: (BinaryMask) -> SupportPlaneFitOutcome = { _ in outcome(plane(at: -597), .foodSupport) }
        let helper = refit(fit: fit)

        let candidate = FoodRegionGrowth.grow(
            argmax: seed, depth: slabDepth, intrinsics: k, supportPlane: first,
            supportOffsetMm: 0, palette: palette, config: .standard)
        var plane = first
        var growth = candidate
        if candidate.applied {
            let refit = fit(GrownRegionPlaneRefit.foodMask(from: candidate.argmax, palette: palette))
            let refitPlane = refit.foodSupportPlane
            growth = FoodRegionGrowth.prune(
                candidate, depth: slabDepth, intrinsics: k,
                supportPlane: refitPlane ?? plane, supportOffsetMm: refitPlane == nil ? 0 : 0,
                palette: palette, config: .standard)
            if growth.applied, let refitPlane { plane = refitPlane }
        }
        #expect(helper.plane.distanceMm == plane.distanceMm)
        #expect(helper.growth.applied == growth.applied)
        #expect(helper.growth.foodPixelsAfter == growth.foodPixelsAfter)
        #expect(helper.growth.argmax.pixels == growth.argmax.pixels)
    }
}

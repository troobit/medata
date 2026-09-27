import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane

// The grow → refit → prune → adopt sequence that decides which support plane
// the volume stage measures from (depth-grown-food-region Decisions 1, 3, 4;
// two-view-trust Decision 10). One implementation for the single-view branch,
// the two-view branch, the harness replay and the carve-residual audit, so
// every path adopts a plane by the same rule:
//
// 1. `FoodRegionGrowth.grow` from the first plane and its support offset.
// 2. When growth added anything, refit the plane from the grown food mask.
// 3. Only a `foodSupport` refit is usable; a table (`edgeBand`) refit keeps
//    the first plane and its offset (Decision 3).
// 4. `FoodRegionGrowth.prune` against the plane the volume will use.
// 5. Adopt the refit only when the pruned region still stands: a region
//    pruned to nothing means the refit's mask was not food, so its plane is
//    not trusted either.
//
// The caller decides what to do with `growth`: the single-view branch
// integrates over the grown map, the two-view branch (Decision 10) takes the
// plane only and keeps the segmenter's silhouette. `fit` is the plane fitter
// the caller already uses — the device's `SupportPlaneFitter.fitOutcome`, the
// harness's `LiDARSupportPlaneFitter.fitFromDepth` — so no path fits a plane
// by a rule the others do not.
public enum GrownRegionPlaneRefit {

    public struct Outcome: Sendable {
        /// The plane the volume should measure from: the adopted refit, else
        /// the first plane unchanged.
        public let plane: SupportPlane
        public let reference: SupportPlaneReference?
        /// The adopted refit's statistics; nil when the first plane stands.
        public let adoptedStats: SupportPlaneFitStats?
        /// The pruned growth result. `applied` is false when nothing survived.
        public let growth: FoodRegionGrowthResult
        /// Reference of the plane the refit returned; nil when the fitter
        /// refused or growth added nothing.
        public let refitReference: SupportPlaneReference?
        public let refitRefused: Bool

        public var adopted: Bool { adoptedStats != nil }
        /// True when growth added cells and a refit was attempted.
        public var refitAttempted: Bool { refitReference != nil || refitRefused }
    }

    /// Runs the sequence above. `supportOffsetMm` is the support surface's
    /// height above `supportPlane` (the ring median on an `edgeBand` fit, 0
    /// otherwise), the same value `grow` and a refused refit's `prune` use.
    public static func refit(
        argmax: ArgmaxMap,
        depth: DepthMap,
        intrinsics: CameraIntrinsics,
        supportPlane plane: SupportPlane,
        supportReference: SupportPlaneReference?,
        supportOffsetMm: Float,
        palette: ClassPalette,
        config: FoodRegionGrowthConfig,
        seedPoints: [SIMD2<Int>] = [],
        fit: (BinaryMask) -> SupportPlaneFitOutcome
    ) -> Outcome {
        let candidate = FoodRegionGrowth.grow(
            argmax: argmax, depth: depth, intrinsics: intrinsics,
            supportPlane: plane, supportOffsetMm: supportOffsetMm,
            palette: palette, config: config, seedPoints: seedPoints)
        guard candidate.applied else {
            return Outcome(plane: plane, reference: supportReference, adoptedStats: nil,
                           growth: candidate, refitReference: nil, refitRefused: false)
        }
        let refit = fit(foodMask(from: candidate.argmax, palette: palette))
        let refitPlane = refit.foodSupportPlane
        let refitRefused = refit.plane == nil
        let refitReference = refit.plane == nil ? nil : refit.stats.reference
        let growth = FoodRegionGrowth.prune(
            candidate, depth: depth, intrinsics: intrinsics,
            supportPlane: refitPlane ?? plane,
            supportOffsetMm: refitPlane == nil ? supportOffsetMm : 0,
            palette: palette, config: config)
        if growth.applied, let refitPlane {
            return Outcome(plane: refitPlane, reference: refit.stats.reference,
                           adoptedStats: refit.stats, growth: growth,
                           refitReference: refitReference, refitRefused: refitRefused)
        }
        return Outcome(plane: plane, reference: supportReference, adoptedStats: nil,
                       growth: growth, refitReference: refitReference, refitRefused: refitRefused)
    }

    /// The food-region mask on the argmax grid, `isVolumetricClass` per pixel
    /// — the predicate `PipelineBridges.foodMask` and
    /// `FixtureRunner.foodRegionMask` both apply.
    public static func foodMask(from argmax: ArgmaxMap, palette: ClassPalette) -> BinaryMask {
        var pixels = [UInt8](repeating: 0, count: argmax.width * argmax.height)
        argmax.pixels.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<(argmax.width * argmax.height) {
                pixels[i] = palette.isVolumetricClass(Int(buf[i])) ? 1 : 0
            }
        }
        return BinaryMask(pixels: pixels, width: argmax.width, height: argmax.height)
    }
}

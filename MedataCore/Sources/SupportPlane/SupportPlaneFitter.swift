import CardDetection
import CaptureKit
import Foundation
import PortableContracts

// Support-plane fit counters exposed to the caller as returned values (snaq-
// parity Req 3.1; replaces the racy `LiDARPlaneFitter.debugLast*` statics).
// Populated by the LiDAR fitter on both exits; the card-only path leaves the
// defaults (its quality signal is `SupportPlane.residualMm`).
public struct SupportPlaneFitStats: Sendable, Equatable {
    // UNITS DEPEND ON `reference`: native depth samples on a `.foodSupport` row,
    // colour-grid points on an `.edgeBand` one. The two differ by ~56x on a
    // 1920x1440 capture and must never be compared across references — the
    // persisted `reference` is what disambiguates them
    // (`specs/estimation/support-plane-reference/` design, Stats semantics).
    public var candidatePointCount: Int
    public var inlierCount: Int
    // Inlier RMS residual (mm). -1 sentinel: the fit refused BEFORE residual
    // was computed (point starvation / degeneracy), distinguishing that from a
    // residual-too-high refusal on a real-but-noisy plane.
    public var residualMm: Float
    // Food-region bbox in colour/mask pixel coords; -1 = no bbox resolved.
    public var foodBBoxX: Int
    public var foodBBoxY: Int
    public var foodBBoxW: Int
    public var foodBBoxH: Int
    // Which surface the plane references (Req 4.4). nil on the card-only path:
    // no depth map, so no depth-derived reference exists, and Req 6.3 wants the
    // field absent rather than defaulted.
    public var reference: SupportPlaneReference?
    // The contact-ring measure for the plane actually returned, on BOTH paths —
    // Req 6.1 requires it on every depth-derived attempt, and Req 6.2's
    // before/after comparison is unexecutable otherwise. nil when a radial band
    // was too thin to measure.
    public var ring: RingStatistics?
    // Candidate PLANES extracted by the restricted fit. A `.foodSupport`-only
    // quantity: absent on the fallback path, where no candidate set was selected
    // from.
    public var candidatePlaneCount: Int?

    public init(candidatePointCount: Int = 0, inlierCount: Int = 0,
                residualMm: Float = -1,
                foodBBoxX: Int = -1, foodBBoxY: Int = -1,
                foodBBoxW: Int = -1, foodBBoxH: Int = -1,
                reference: SupportPlaneReference? = nil,
                ring: RingStatistics? = nil,
                candidatePlaneCount: Int? = nil) {
        self.candidatePointCount = candidatePointCount
        self.inlierCount = inlierCount
        self.residualMm = residualMm
        self.foodBBoxX = foodBBoxX
        self.foodBBoxY = foodBBoxY
        self.foodBBoxW = foodBBoxW
        self.foodBBoxH = foodBBoxH
        self.reference = reference
        self.ring = ring
        self.candidatePlaneCount = candidatePlaneCount
    }
}

// Non-throwing fit result: `plane` is non-nil exactly when `refusal` is nil;
// `stats` is populated on both exits so a refusal keeps its diagnostics.
public struct SupportPlaneFitOutcome: Sendable {
    public let plane: SupportPlane?
    public let stats: SupportPlaneFitStats
    public let refusal: SupportPlaneError?

    public init(plane: SupportPlane?, stats: SupportPlaneFitStats, refusal: SupportPlaneError?) {
        self.plane = plane
        self.stats = stats
        self.refusal = refusal
    }
}

// SupportPlaneFitter protocol + production conformance per Decision 9 and the
// design's SupportPlaneFitter section. Wraps the LiDAR-vs-card dispatch that
// `Pipeline.fitSupportPlane` previously inlined, so tests can inject a probe
// implementation (Req 8.7) without `@testable` hooks on Pipeline.
public protocol SupportPlaneFitter: Sendable {
    func fitOutcome(
        nadir: RawFrame,
        cardPose: CardPose?,
        corners: [PixelCorner]?,
        preShutterFoodMask: BinaryMask?
    ) -> SupportPlaneFitOutcome
}

public extension SupportPlaneFitter {
    // Throwing convenience preserving the pre-outcome call shape for callers
    // that do not need the fit stats.
    func fit(
        nadir: RawFrame,
        cardPose: CardPose?,
        corners: [PixelCorner]?,
        preShutterFoodMask: BinaryMask?
    ) throws -> SupportPlane {
        let outcome = fitOutcome(
            nadir: nadir, cardPose: cardPose,
            corners: corners, preShutterFoodMask: preShutterFoodMask
        )
        if let plane = outcome.plane { return plane }
        throw outcome.refusal ?? SupportPlaneError.noLidarPoints
    }
}

public struct LiDARSupportPlaneFitter: SupportPlaneFitter {
    public init() {}

    public func fitOutcome(
        nadir: RawFrame,
        cardPose: CardPose?,
        corners: [PixelCorner]?,
        preShutterFoodMask: BinaryMask?
    ) -> SupportPlaneFitOutcome {
        // Empty-mask check applies at the protocol entry — BEFORE the LiDAR-vs-card
        // dispatch — so the card-only path also refuses when the pre-shutter mask
        // is empty (Decision 2 / 2x2 decision table). The Pipeline call site maps
        // SupportPlaneError.emptyFoodMask to EstimationFailure.noFoodPixels.
        guard let mask = preShutterFoodMask, Self.hasAnyOneBit(mask) else {
            return SupportPlaneFitOutcome(
                plane: nil, stats: SupportPlaneFitStats(), refusal: .emptyFoodMask
            )
        }

        if let depth = nadir.depth {
            return Self.fitFromDepth(
                depth: depth, intrinsics: nadir.intrinsics,
                mask: mask, gravity: nadir.gravity
            )
        }

        // Card-only path mirrors the pre-existing inlined logic in
        // Pipeline.fitSupportPlane: back-project the two lower card corners as
        // lower-silhouette edge points and seed a single food-centroid offset
        // from the card centre.
        guard let pose = cardPose, let c = corners, c.count >= 4 else {
            return SupportPlaneFitOutcome(
                plane: nil, stats: SupportPlaneFitStats(), refusal: .noLowerSilhouetteEdges
            )
        }
        let k = nadir.intrinsics
        let dCard = abs(pose.translationMm.z)
        let s0 = pose.scaleAtCardPlaneMmPerPx
        let lowerEdges: [Vec3] = c.suffix(2).map { corner in
            Vec3((corner.u - k.cx) * s0, (corner.v - k.cy) * s0, -dCard)
        }
        let centroid = Vec3(
            pose.translationMm.x,
            pose.translationMm.y + 20,
            pose.translationMm.z
        )
        do {
            let plane = try CardOnlyPlaneFitter.fit(CardOnlyPlaneFitter.Inputs(
                cardCentreDepthMm: dCard,
                scaleAtCardPlaneInitMmPerPx: s0,
                gravityCamera: nadir.gravity,
                edgePoints3DAtInitScale: lowerEdges,
                foodCentroids3DAtInitScale: [centroid]
            ))
            return SupportPlaneFitOutcome(
                plane: plane,
                stats: SupportPlaneFitStats(residualMm: plane.residualMm),
                refusal: nil
            )
        } catch {
            // CardOnlyPlaneFitter throws SupportPlaneError only; the fallback
            // keeps the conservative refusal if that ever changes.
            return SupportPlaneFitOutcome(
                plane: nil,
                stats: SupportPlaneFitStats(),
                refusal: (error as? SupportPlaneError) ?? .iterationDiverged
            )
        }
    }

    // The fallback ladder of Req 4 in Decision 5's order: the food-support fit is
    // attempted FIRST, and the edge-band fit runs only on the rejection path. The
    // edge-band fit is genuinely lazy — nothing before it needs its plane, since
    // the Req 3.3 escape guard compares against the annulus median rather than
    // against the edge-band plane (Decision 22).
    //
    // On the fallback path the returned plane, stats and refusal are the edge-band
    // fitter's own, unmodified (Reqs 4.2, 4.3); only the reference and the ring
    // measure are added alongside them.
    static func fitFromDepth(
        depth: DepthMap, intrinsics: CameraIntrinsics,
        mask: BinaryMask, gravity: Vec3
    ) -> SupportPlaneFitOutcome {
        if let fit = SupportRegion.fitFoodSupportPlane(
            depth: depth, colourIntrinsics: intrinsics,
            foodRegionMask: mask, gravityCamera: gravity
        ) {
            return SupportPlaneFitOutcome(
                plane: fit.plane,
                stats: SupportPlaneFitStats(
                    candidatePointCount: fit.annulusSampleCount,
                    inlierCount: fit.inlierCount,
                    residualMm: fit.plane.residualMm,
                    reference: .foodSupport,
                    ring: fit.ring,
                    candidatePlaneCount: fit.candidateCount
                ),
                refusal: nil
            )
        }

        let outcome = LiDARPlaneFitter.fitOutcome(LiDARPlaneFitter.Inputs(
            depth: depth,
            colourIntrinsics: intrinsics,
            foodRegionMask: mask,
            gravityCamera: gravity
        ))
        var stats = outcome.stats
        stats.reference = .edgeBand
        // Req 6.1: the ring measure lands on the fallback attempt too, which is what
        // makes Req 6.2's before/after comparison executable. Measured against the
        // plane that was actually returned, so there is nothing to measure on a
        // refusal.
        if let plane = outcome.plane {
            stats.ring = SupportRegion.ringStatistics(
                for: plane, depth: depth, foodMask: mask, intrinsics: intrinsics
            )
        }
        return SupportPlaneFitOutcome(
            plane: outcome.plane, stats: stats, refusal: outcome.refusal
        )
    }

    private static func hasAnyOneBit(_ mask: BinaryMask) -> Bool {
        for byte in mask.pixels where byte != 0 { return true }
        return false
    }
}

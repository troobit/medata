import CardDetection
import CaptureKit
import Foundation
import PortableContracts

// Support-plane fit counters exposed to the caller as returned values (snaq-
// parity Req 3.1; replaces the racy `LiDARPlaneFitter.debugLast*` statics).
// Populated by the LiDAR fitter on both exits; the card-only path refuses
// (two-view-trust Req 4.4) and leaves the defaults.
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
    // no depth map, so no depth-derived reference exists (and since two-view-trust
    // Req 4.4 that path refuses outright), and Req 6.3 wants the field absent
    // rather than defaulted.
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

    /// The plane only when it references the food's own support surface. A
    /// refit that lands on the table (edgeBand) is not adopted for volume:
    /// the integrator measures from the plane with no offset, and on the
    /// 2026-09-25 roll an adopted table plane read 519 cm³ against 247 cm³
    /// from the plate plane (depth-grown-food-region Decision 3).
    public var foodSupportPlane: SupportPlane? {
        stats.reference == .foodSupport ? plane : nil
    }

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

        // Card-only path (no depth map): REFUSE (two-view-trust Req 4.4).
        //
        // This branch used to back-project the two lower CARD corners as if they
        // were the food's lower silhouette edge and seed a single food centroid
        // 20 mm below the card centre. `CardOnlyPlaneFitter` then returned a
        // plane fitted to the card's neighbourhood, carrying no information
        // about where the food touches the table — and nothing downstream could
        // tell it apart from a measured fit. `docs/agent-notes/two-view-geometry-audit.md`
        // section 3 records that the path has never run end to end on a real
        // capture, so the invented plane was never even wrong in a way anyone
        // could see.
        //
        // `noLowerSilhouetteEdges` is the honest name for it: the fitter has no
        // food lower-silhouette edges, only card corners. The Pipeline maps it
        // to `EstimationFailure.noSupportPlaneWithoutDepth` — on such a capture
        // the card usually gives scale; it is the plane that is missing.
        //
        // What would make this branch work: the food's lower silhouette edges,
        // taken from the nadir food mask (pipeline Req 4.3), back-projected at
        // the card-plane scale and handed to `CardOnlyPlaneFitter` in place of
        // the card corners. `CardOnlyPlaneFitter` itself is unchanged and still
        // covered by `CardOnlyPlaneFitterTests`; it is the INPUT that is missing.
        return SupportPlaneFitOutcome(
            plane: nil, stats: SupportPlaneFitStats(), refusal: .noLowerSilhouetteEdges
        )
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
    //
    // Public because Req 5.1 makes this the SINGLE support-plane derivation: the
    // offline harness (`HarnessCore.FixtureRunner`) calls it rather than keeping a
    // copy, so a β_c fitted offline is valid on device by construction. The
    // dependency runs harness → SupportPlane, the allowed direction; no shipped code
    // gains a `HARNESS_ENABLED` dependency.
    public static func fitFromDepth(
        depth: DepthMap, intrinsics: CameraIntrinsics,
        mask: BinaryMask, gravity: Vec3,
        gravityLocked: Bool = SupportPlaneGravityLock.enabled
    ) -> SupportPlaneFitOutcome {
        if let fit = SupportRegion.fitFoodSupportPlane(
            depth: depth, colourIntrinsics: intrinsics,
            foodRegionMask: mask, gravityCamera: gravity,
            gravityLocked: gravityLocked
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
        ), gravityLocked: gravityLocked)
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

import CardDetection
import CaptureKit
import Foundation
import PortableContracts

// SupportPlaneFitter protocol + production conformance per Decision 9 and the
// design's SupportPlaneFitter section. Wraps the LiDAR-vs-card dispatch that
// `Pipeline.fitSupportPlane` previously inlined, so tests can inject a probe
// implementation (Req 8.7) without `@testable` hooks on Pipeline.
public protocol SupportPlaneFitter: Sendable {
    func fit(
        nadir: RawFrame,
        cardPose: CardPose?,
        corners: [PixelCorner]?,
        preShutterFoodMask: BinaryMask?
    ) throws -> SupportPlane
}

public struct LiDARSupportPlaneFitter: SupportPlaneFitter {
    public init() {}

    public func fit(
        nadir: RawFrame,
        cardPose: CardPose?,
        corners: [PixelCorner]?,
        preShutterFoodMask: BinaryMask?
    ) throws -> SupportPlane {
        // Empty-mask check applies at the protocol entry — BEFORE the LiDAR-vs-card
        // dispatch — so the card-only path also refuses when the pre-shutter mask
        // is empty (Decision 2 / 2x2 decision table). The Pipeline call site maps
        // SupportPlaneError.emptyFoodMask to EstimationFailure.noFoodPixels.
        guard let mask = preShutterFoodMask, Self.hasAnyOneBit(mask) else {
            throw SupportPlaneError.emptyFoodMask
        }

        if let depth = nadir.depth {
            return try LiDARPlaneFitter.fit(LiDARPlaneFitter.Inputs(
                depth: depth,
                colourIntrinsics: nadir.intrinsics,
                foodRegionMask: mask,
                gravityCamera: nadir.gravity
            ))
        }

        // Card-only path mirrors the pre-existing inlined logic in
        // Pipeline.fitSupportPlane: back-project the two lower card corners as
        // lower-silhouette edge points and seed a single food-centroid offset
        // from the card centre.
        guard let pose = cardPose, let c = corners, c.count >= 4 else {
            throw SupportPlaneError.noLowerSilhouetteEdges
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
        return try CardOnlyPlaneFitter.fit(CardOnlyPlaneFitter.Inputs(
            cardCentreDepthMm: dCard,
            scaleAtCardPlaneInitMmPerPx: s0,
            gravityCamera: nadir.gravity,
            edgePoints3DAtInitScale: lowerEdges,
            foodCentroids3DAtInitScale: [centroid]
        ))
    }

    private static func hasAnyOneBit(_ mask: BinaryMask) -> Bool {
        for byte in mask.pixels where byte != 0 { return true }
        return false
    }
}

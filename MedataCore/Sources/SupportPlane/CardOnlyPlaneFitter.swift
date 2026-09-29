import CardDetection
import CaptureKit
import Foundation
import PortableContracts

// Card-only iterative support-plane fitter per design §6.3 / Req 4.3. Three-unknown
// fixed-point on (s_card → π_sup → h_food). Used when LiDAR is unavailable in the
// canonical two-view path (a card has been detected per Req 5.2).
//
// The iteration math depends on lower-silhouette edges and food-silhouette centroids
// extracted by the segmenter (lands in tasks 19+). To make the iteration testable now,
// the fitter takes those points as Vec3s already back-projected at the INITIAL scale
// s_card,init; each iteration scales them by (1 + h_food_(k) / d_card) per §6.3.
public enum CardOnlyPlaneFitter {
    public struct Inputs: Sendable {
        public let cardCentreDepthMm: Float       // d_card from CardObservation (mm, positive)
        public let scaleAtCardPlaneInitMmPerPx: Float  // s_card,init from §6.1 step 8
        public let gravityCamera: Vec3            // unit vector in camera-1 frame
        // Lower-silhouette edge points, back-projected at s_card,init scale (mm).
        public let edgePoints3DAtInitScale: [Vec3]
        // Food-silhouette centroid points, back-projected at s_card,init scale (mm).
        public let foodCentroids3DAtInitScale: [Vec3]

        // Iteration knobs (defaults per §6.3). Exposed for tests.
        public let convergenceMm: Float
        public let bestOfFiveAcceptMm: Float
        public let maxIterations: Int

        public init(
            cardCentreDepthMm: Float,
            scaleAtCardPlaneInitMmPerPx: Float,
            gravityCamera: Vec3,
            edgePoints3DAtInitScale: [Vec3],
            foodCentroids3DAtInitScale: [Vec3],
            convergenceMm: Float = 1.0,
            bestOfFiveAcceptMm: Float = 1.5,
            maxIterations: Int = 5
        ) {
            self.cardCentreDepthMm = cardCentreDepthMm
            self.scaleAtCardPlaneInitMmPerPx = scaleAtCardPlaneInitMmPerPx
            self.gravityCamera = gravityCamera
            self.edgePoints3DAtInitScale = edgePoints3DAtInitScale
            self.foodCentroids3DAtInitScale = foodCentroids3DAtInitScale
            self.convergenceMm = convergenceMm
            self.bestOfFiveAcceptMm = bestOfFiveAcceptMm
            self.maxIterations = maxIterations
        }
    }

    public static func fit(_ inputs: Inputs) throws -> SupportPlane {
        precondition(!inputs.edgePoints3DAtInitScale.isEmpty,
                     "fitter needs at least one lower-edge point")
        let gravity = inputs.gravityCamera.normalised()

        // Initial state per §6.3: h_food_(0) = 0 mm; π_sup_(0) at the card centre.
        // Card centre in camera coords is on the optical axis at depth cardCentreDepth
        // (negative Z under §6.0); signed plane distance d = gravity · point.
        let cardCentre = Vec3(0, 0, -inputs.cardCentreDepthMm)
        var hFood: Float = 0
        var dCurrent: Float = gravity.dot(cardCentre)

        var bestResidual: Float = .infinity
        var bestPlane: SupportPlane?

        for k in 0..<inputs.maxIterations {
            let sFactor = 1 + hFood / inputs.cardCentreDepthMm
            // Scale edges + centroids uniformly to the food-plane scale s_card_(k).
            let edgeProjections = inputs.edgePoints3DAtInitScale.map {
                gravity.dot($0) * sFactor
            }
            // LSQ plane with normal = gravity collapses to d = mean(gravity · edge).
            let dNew = edgeProjections.reduce(0, +) / Float(edgeProjections.count)
            let delta = abs(dNew - dCurrent)

            // Update h_food = mean centroid height above π_sup_(k+1).
            let hNew: Float
            if inputs.foodCentroids3DAtInitScale.isEmpty {
                hNew = hFood
            } else {
                let heights = inputs.foodCentroids3DAtInitScale.map {
                    gravity.dot($0) * sFactor - dNew
                }
                hNew = heights.reduce(0, +) / Float(heights.count)
            }

            // Track best Δd seen across iterations (best-of-5 fallback per §6.3).
            if delta < bestResidual {
                bestResidual = delta
                bestPlane = SupportPlane(
                    normal: gravity,
                    distanceMm: dNew,
                    residualMm: delta,
                    convergedIterations: k + 1
                )
            }

            dCurrent = dNew
            hFood = hNew

            if delta < inputs.convergenceMm {
                return bestPlane!  // strict 1 mm convergence reached
            }
        }

        if bestResidual <= inputs.bestOfFiveAcceptMm, let bp = bestPlane {
            return bp                  // best-of-5 fallback per §6.3
        }
        throw SupportPlaneError.iterationDiverged
    }
}

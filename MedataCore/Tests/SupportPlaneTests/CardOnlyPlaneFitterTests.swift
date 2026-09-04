import CaptureKit
import PortableContracts
import XCTest
@testable import SupportPlane

// Task 15: card-only iterative support-plane fit (§6.3).
// The fixture mathematics: with gravity = (0, 1, 0) and edges/centroids constructed
// at depth z = -d_card with explicit y-coordinates, the LSQ-with-fixed-normal step
// reduces to mean(y) on the scaled edge points.
private let gravity = Vec3(0, 1, 0)
private let dCard: Float = 300                 // mm: card centre depth
private let sCardInit: Float = 0.2             // mm/px (representative; magnitude irrelevant
                                                //         because edges are pre-scaled)

// Build N edge points all at the same y (table surface), spread in x.
private func edges(yMm: Float, count: Int = 20) -> [Vec3] {
    (0..<count).map { i in
        Vec3(Float(i) * 5 - Float(count) * 2, yMm, -dCard)
    }
}

// Build N centroid points all at the same y (food bulk), spread in x.
private func centroids(yMm: Float, count: Int = 5) -> [Vec3] {
    (0..<count).map { i in
        Vec3(Float(i) * 8 - Float(count) * 4, yMm, -dCard)
    }
}

final class CardOnlyPlaneFitterTests: XCTestCase {
    // h_food_(0) = 0 mm, π_sup_(0) at card-centre depth (§6.3 init).
    // With edges and centroids at y_edge = 50 mm, the very first iteration's d_(1)
    // = mean(gravity · edge) · (1 + 0/d_card) = 50; |d_(1) - d_(0)| where d_(0) =
    // gravity · (0,0,-d_card) = 0. So Δd = 50 mm and the iteration runs.
    func testFirstIterationUsesZeroFoodHeightAndCardCentreDepth() throws {
        let inputs = CardOnlyPlaneFitter.Inputs(
            cardCentreDepthMm: dCard,
            scaleAtCardPlaneInitMmPerPx: sCardInit,
            gravityCamera: gravity,
            edgePoints3DAtInitScale: edges(yMm: 50),
            foodCentroids3DAtInitScale: centroids(yMm: 80),
            convergenceMm: 0,                  // force all 5 iterations to run
            bestOfFiveAcceptMm: 1000,
            maxIterations: 1
        )
        let plane = try CardOnlyPlaneFitter.fit(inputs)
        // After 1 iter at h_food=0 and edges at y=50, d_(1) = 50 (s_factor = 1).
        XCTAssertEqual(plane.distanceMm, 50, accuracy: 1e-4)
        XCTAssertEqual(plane.normal, gravity.normalised(), "fitted normal must equal gravity")
        XCTAssertEqual(plane.convergedIterations, 1)
    }

    // 1 mm convergence within 5 iterations for a representative fixture.
    // Edges at y_edge, centroids at y_edge + 30 mm (food sits 30 mm above the table)
    // → s_factor stabilises and Δd shrinks below 1 mm well within 5 iters.
    func testConvergesWithin5Iterations() throws {
        let yEdge: Float = 40
        let inputs = CardOnlyPlaneFitter.Inputs(
            cardCentreDepthMm: dCard,
            scaleAtCardPlaneInitMmPerPx: sCardInit,
            gravityCamera: gravity,
            edgePoints3DAtInitScale: edges(yMm: yEdge),
            foodCentroids3DAtInitScale: centroids(yMm: yEdge + 30)
        )
        let plane = try CardOnlyPlaneFitter.fit(inputs)
        XCTAssertNotNil(plane.convergedIterations)
        if let iters = plane.convergedIterations {
            XCTAssertLessThanOrEqual(iters, 5)
        }
        XCTAssertLessThan(plane.residualMm, 1.0,
                          "residual \(plane.residualMm) must be < 1 mm at convergence")
    }

    // Best-of-5 fallback at residual ≤ 1.5 mm (§6.3 tail). Loosen `convergenceMm` to
    // 0 so the strict-1mm exit never fires; the fitter must still return the best
    // observed plane provided its Δd ≤ 1.5 mm.
    func testBestOfFiveFallbackWhenStrictConvergenceNotReached() throws {
        let inputs = CardOnlyPlaneFitter.Inputs(
            cardCentreDepthMm: dCard,
            scaleAtCardPlaneInitMmPerPx: sCardInit,
            gravityCamera: gravity,
            edgePoints3DAtInitScale: edges(yMm: 30),
            foodCentroids3DAtInitScale: centroids(yMm: 60),
            convergenceMm: 0,                   // disable strict convergence exit
            bestOfFiveAcceptMm: 1.5,
            maxIterations: 5
        )
        let plane = try CardOnlyPlaneFitter.fit(inputs)
        XCTAssertLessThanOrEqual(plane.residualMm, 1.5,
                                 "best-of-5 must return plane with residual ≤ 1.5 mm")
    }

    // iterationDiverged when best Δd across iterations stays > 1.5 mm. Construct a
    // fixture where centroids are far above edges relative to d_card, so the
    // fixed-point iteration's Δd remains large across all 5 iters.
    func testIterationDivergedRefusalWhenBestResidualExceedsTolerance() {
        let yEdge: Float = 100
        // centroid 250 mm above edges; with d_card=300, h_food/d_card ratio is ~0.8
        // so s_factor jumps significantly each iter and Δd never settles below 1.5.
        let inputs = CardOnlyPlaneFitter.Inputs(
            cardCentreDepthMm: dCard,
            scaleAtCardPlaneInitMmPerPx: sCardInit,
            gravityCamera: gravity,
            edgePoints3DAtInitScale: edges(yMm: yEdge),
            foodCentroids3DAtInitScale: centroids(yMm: yEdge + 250),
            convergenceMm: 0,                  // never accept strict convergence
            bestOfFiveAcceptMm: 1.5,
            maxIterations: 5
        )
        XCTAssertThrowsError(try CardOnlyPlaneFitter.fit(inputs)) { err in
            XCTAssertEqual(err as? SupportPlaneError, .iterationDiverged)
        }
    }
}

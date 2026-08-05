import CaptureKit
import PortableContracts
import XCTest
@testable import SupportPlane

// Task 7: end-to-end `fitFoodSupportPlane` scenes named in the design's
// testing strategy table and the decision log's silent-failure / rimmed-
// plate / overhang cases. Uses the smaller `guardIntrinsics` scale (task 5's
// note on CC-RANSAC cost being linear in candidate count applies doubly here
// — this is the full public entry point, not an isolated internals call).

private func guardFoodMask(radiusPx: Float = guardFoodRadiusPx,
                           centre: (x: Float, y: Float) = guardFoodCentre) -> BinaryMask {
    ellipseFoodMask(width: guardWidth, height: guardHeight, cx: centre.x, cy: centre.y, rx: radiusPx, ry: radiusPx)
}

final class SupportRegionFitEndToEndTests: XCTestCase {
    // Plate 20 mm above a dominant table: the case today's fitter fails.
    func testPlateAboveDominantTableSelectsThePlate() {
        let dTable: Float = 100
        let dPlate: Float = 120
        let plateRadiusPx = guardFoodRadiusPx + guardPixelRadius(mm: SupportRegion.ringOuterMm, foodHeightMm: dPlate) + 2
        let depth = concentricScene(
            depthWidth: guardWidth, depthHeight: guardHeight, intrinsics: guardIntrinsics,
            centre: guardFoodCentre, foodRadiusPx: guardFoodRadiusPx, foodHeightMm: dPlate,
            rings: [(plateRadiusPx, dPlate)], backgroundHeightMm: dTable
        )
        guard let result = SupportRegion.fitFoodSupportPlane(
            depth: depth, colourIntrinsics: guardIntrinsics, foodRegionMask: guardFoodMask(), gravityCamera: Vec3(0, 1, 0)
        ) else { return XCTFail("expected the plate plane to be selected, not a fallback") }
        XCTAssertEqual(result.plane.distanceMm, dPlate, accuracy: 3.0)
        XCTAssertGreaterThanOrEqual(result.candidateCount, 2, "both the plate and the table must have been considered")
    }

    // Ring straddling plate/table ~50/50: rejected on sectors (Decision 19 —
    // a MAD bar cannot fire here at all, so this is the ONLY thing that can).
    func testStraddlingRingFiftyFiftyFallsBack() {
        let depth = angularSplitScene(
            depthWidth: guardWidth, depthHeight: guardHeight, intrinsics: guardIntrinsics,
            centre: guardFoodCentre, foodRadiusPx: guardFoodRadiusPx, foodHeightMm: 100,
            angleFractionA: 0.5, heightA: 100, heightB: 126
        )
        let result = SupportRegion.fitFoodSupportPlane(
            depth: depth, colourIntrinsics: guardIntrinsics, foodRegionMask: guardFoodMask(), gravityCamera: Vec3(0, 1, 0)
        )
        XCTAssertNil(result, "a ring straddling two surfaces must never be certified as a correct fit")
    }

    // Rimmed plate, well partly visible, rim confined to the outer band:
    // the inner band wins (Decisions 14, 21).
    func testRimmedPlateWellPartlyVisibleSelectsTheWell() {
        let dWell: Float = 100
        let dRim: Float = 118
        let midOuterBoundaryPx = guardFoodRadiusPx
            + guardPixelRadius(mm: SupportRegion.ringInnerMm + 2 * (SupportRegion.ringOuterMm - SupportRegion.ringInnerMm) / 3,
                               foodHeightMm: dWell)
        let depth = concentricScene(
            depthWidth: guardWidth, depthHeight: guardHeight, intrinsics: guardIntrinsics,
            centre: guardFoodCentre, foodRadiusPx: guardFoodRadiusPx, foodHeightMm: dWell,
            rings: [(midOuterBoundaryPx, dWell)], backgroundHeightMm: dRim
        )
        guard let result = SupportRegion.fitFoodSupportPlane(
            depth: depth, colourIntrinsics: guardIntrinsics, foodRegionMask: guardFoodMask(), gravityCamera: Vec3(0, 1, 0)
        ) else { return XCTFail("expected the well plane to be selected") }
        XCTAssertEqual(result.plane.distanceMm, dWell, accuracy: 3.0)
    }

    // Rimmed plate, rim step inside the mid band: rejected to fallback
    // rather than fit to the rim (Decision 21).
    func testRimmedPlateRimStepInsideMidBandFallsBack() {
        let dWell: Float = 100
        let dRim: Float = 118
        let bandWidthMm = (SupportRegion.ringOuterMm - SupportRegion.ringInnerMm) / 3
        let earlyMidBoundaryPx = guardFoodRadiusPx
            + guardPixelRadius(mm: SupportRegion.ringInnerMm + 0.15 * bandWidthMm, foodHeightMm: dWell)
        let depth = concentricScene(
            depthWidth: guardWidth, depthHeight: guardHeight, intrinsics: guardIntrinsics,
            centre: guardFoodCentre, foodRadiusPx: guardFoodRadiusPx, foodHeightMm: dWell,
            rings: [(earlyMidBoundaryPx, dWell)], backgroundHeightMm: dRim
        )
        let result = SupportRegion.fitFoodSupportPlane(
            depth: depth, colourIntrinsics: guardIntrinsics, foodRegionMask: guardFoodMask(), gravityCamera: Vec3(0, 1, 0)
        )
        XCTAssertNil(result, "a rim step already inside the mid band must reject to fallback, not fit the rim")
    }

    // Bowl: walls rise steeply immediately outside the food — rejected;
    // the caller falls back to .edgeBand (Decision 3).
    func testBowlFallsBack() {
        let dWell: Float = 100
        let dWall: Float = 150
        let depth = concentricScene(
            depthWidth: guardWidth, depthHeight: guardHeight, intrinsics: guardIntrinsics,
            centre: guardFoodCentre, foodRadiusPx: guardFoodRadiusPx, foodHeightMm: dWell,
            rings: [], backgroundHeightMm: dWall
        )
        let result = SupportRegion.fitFoodSupportPlane(
            depth: depth, colourIntrinsics: guardIntrinsics, foodRegionMask: guardFoodMask(), gravityCamera: Vec3(0, 1, 0)
        )
        XCTAssertNil(result, "a bowl wall must reject rather than clip food height against the rim")
    }

    // Overhanging food below the plane must NOT trigger the guards (Req 1.3,
    // 3.4; Decision 22 — a count-fraction bar rejected this feature's own
    // acceptance capture at ~11% overhang).
    func testOverhangingFoodDoesNotPreventSelection() {
        let dPlate: Float = 120
        let overhangMask = ellipseFoodMask(width: guardWidth, height: guardHeight,
                                           cx: guardFoodCentre.x, cy: guardFoodCentre.y,
                                           rx: guardFoodRadiusPx, ry: guardFoodRadiusPx)
        let depth = heightFieldDepthMap(
            intrinsics: guardIntrinsics, depthWidth: guardWidth, depthHeight: guardHeight,
            heightMmAt: { x, y in
                let dx = Float(x) - guardFoodCentre.x, dy = Float(y) - guardFoodCentre.y
                let r = (dx * dx + dy * dy).squareRoot()
                if r <= guardFoodRadiusPx {
                    // The lower ~10% of the food disc (by row) overhangs
                    // below the plate — Decision 4's accepted under-measure.
                    return dy > guardFoodRadiusPx * 0.8 ? dPlate - 15 : dPlate
                }
                return dPlate
            }
        )
        guard let result = SupportRegion.fitFoodSupportPlane(
            depth: depth, colourIntrinsics: guardIntrinsics, foodRegionMask: overhangMask, gravityCamera: Vec3(0, 1, 0)
        ) else { return XCTFail("overhanging food must not fall back — this is the feature's own acceptance capture") }
        XCTAssertEqual(result.plane.distanceMm, dPlate, accuracy: 3.0)
    }

    // Food mask pinned at the frame edge: a short/clipped ring must fall
    // back cleanly, not crash.
    func testFoodMaskAtFrameEdgeFallsBackWithoutCrash() {
        let cornerCentre: (x: Float, y: Float) = (4, 4)
        let mask = guardFoodMask(radiusPx: 2, centre: cornerCentre)
        let depth = concentricScene(
            depthWidth: guardWidth, depthHeight: guardHeight, intrinsics: guardIntrinsics,
            centre: cornerCentre, foodRadiusPx: 2, foodHeightMm: 120, rings: [], backgroundHeightMm: 120
        )
        let result = SupportRegion.fitFoodSupportPlane(
            depth: depth, colourIntrinsics: guardIntrinsics, foodRegionMask: mask, gravityCamera: Vec3(0, 1, 0)
        )
        XCTAssertNil(result, "a heavily frame-clipped ring must fall back rather than fit on a fragment")
    }

    // Req 7.7: identical capture bytes must produce an identical plane and
    // an identical selection.
    func testDeterminismSameBytesTwiceProducesIdenticalResult() {
        let dTable: Float = 100
        let dPlate: Float = 120
        let plateRadiusPx = guardFoodRadiusPx + guardPixelRadius(mm: SupportRegion.ringOuterMm, foodHeightMm: dPlate) + 2
        let depth = concentricScene(
            depthWidth: guardWidth, depthHeight: guardHeight, intrinsics: guardIntrinsics,
            centre: guardFoodCentre, foodRadiusPx: guardFoodRadiusPx, foodHeightMm: dPlate,
            rings: [(plateRadiusPx, dPlate)], backgroundHeightMm: dTable
        )
        let mask = guardFoodMask()
        let r1 = SupportRegion.fitFoodSupportPlane(depth: depth, colourIntrinsics: guardIntrinsics,
                                                    foodRegionMask: mask, gravityCamera: Vec3(0, 1, 0))
        let r2 = SupportRegion.fitFoodSupportPlane(depth: depth, colourIntrinsics: guardIntrinsics,
                                                    foodRegionMask: mask, gravityCamera: Vec3(0, 1, 0))
        guard let a = r1, let b = r2 else { return XCTFail("expected both runs to select the plate plane") }
        XCTAssertEqual(a.plane, b.plane)
        XCTAssertEqual(a.ring, b.ring)
        XCTAssertEqual(a.candidateCount, b.candidateCount)
    }
}

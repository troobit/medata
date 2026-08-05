import CaptureKit
import PortableContracts
import XCTest
@testable import SupportPlane

// Task 3: contactRing and ringStatistics (Req 3.1, 3.2, 3.5, 3.6, 3.8, 3.9;
// Decisions 14, 18–20). `contactRing`/`ringStatistics` operate on the NATIVE
// DEPTH GRID — the fixtures below build scenes directly at that resolution
// (no colour-grid downsampling in play here; that is task 1/2's contract).

private func plane(d: Float) -> SupportPlane {
    SupportPlane(normal: Vec3(0, 1, 0), distanceMm: d, residualMm: 0, convergedIterations: nil)
}

final class SupportRegionRingStatisticsTests: XCTestCase {
    // MARK: - Radial profile (Decision 14)

    // Flat surface: one plane throughout food + ring. All three bands read
    // ~0 relative to that plane, and support fraction/sectors are high.
    func testFlatSurfaceBandsAreEqualAndFullySupported() {
        let d: Float = 126
        let mask = ellipseFoodMask(width: sceneWidth, height: sceneHeight,
                                   cx: sceneFoodCentre.x, cy: sceneFoodCentre.y,
                                   rx: sceneFoodRadiusPx, ry: sceneFoodRadiusPx)
        let depth = concentricScene(foodHeightMm: d, rings: [], backgroundHeightMm: d)
        guard let s = SupportRegion.ringStatistics(foodMask: mask, depth: depth,
                                                    intrinsics: sceneDepthIntrinsics(depth), plane: plane(d: d))
        else { return XCTFail("expected ring statistics") }
        XCTAssertEqual(s.bandMedianMm.count, 3)
        for m in s.bandMedianMm { XCTAssertEqual(m, 0, accuracy: 1.0) }
        XCTAssertEqual(s.medianMm, 0, accuracy: 1.0)
        XCTAssertGreaterThanOrEqual(s.supportFraction, 0.95)
        XCTAssertEqual(s.supportingSectors, SupportRegion.ringSectorCount)
        for c in s.bandSampleCount { XCTAssertGreaterThanOrEqual(c, SupportRegion.ringMinSamples) }
    }

    // Rimmed plate, well partly visible: inner+mid stay on the well (flat),
    // outer rises onto the rim (Decision 14/21 — outer-only rise is shape
    // detection, not a rejection signal at the ringStatistics layer).
    func testRimRisesOutwardOnlyInOuterBand() {
        let dWell: Float = 100
        let dRim: Float = 118   // 18 mm rim step, dinner-plate figure from the design table
        let midOuterBoundaryPx = sceneFoodRadiusPx
            + scenePixelRadius(mm: SupportRegion.ringInnerMm + 2 * (SupportRegion.ringOuterMm - SupportRegion.ringInnerMm) / 3,
                               foodHeightMm: dWell)
        let mask = ellipseFoodMask(width: sceneWidth, height: sceneHeight,
                                   cx: sceneFoodCentre.x, cy: sceneFoodCentre.y,
                                   rx: sceneFoodRadiusPx, ry: sceneFoodRadiusPx)
        let depth = concentricScene(foodHeightMm: dWell,
                                    rings: [(midOuterBoundaryPx, dWell)],
                                    backgroundHeightMm: dRim)
        guard let s = SupportRegion.ringStatistics(foodMask: mask, depth: depth,
                                                    intrinsics: sceneDepthIntrinsics(depth), plane: plane(d: dWell))
        else { return XCTFail("expected ring statistics") }
        XCTAssertEqual(s.bandMedianMm[0], 0, accuracy: 2.0)
        XCTAssertEqual(s.bandMedianMm[1], 0, accuracy: 2.0)
        XCTAssertGreaterThan(s.bandMedianMm[2], 10, "outer band should read the rim step")
        XCTAssertLessThanOrEqual(s.bandMedianMm[1] - s.bandMedianMm[0], SupportRegion.bandStepMaxMm,
                                 "inner→mid step must stay small — the well plane must remain selectable")
    }

    // Bowl: the wall rises steeply immediately outside the food boundary, so
    // even the inner band reads a large positive offset from the well plane.
    func testBowlRisesSteeplyFromTheInnerBand() {
        let dWell: Float = 100
        let dWall: Float = 150   // steep, immediate rise — no flat well band survives
        let mask = ellipseFoodMask(width: sceneWidth, height: sceneHeight,
                                   cx: sceneFoodCentre.x, cy: sceneFoodCentre.y,
                                   rx: sceneFoodRadiusPx, ry: sceneFoodRadiusPx)
        let depth = concentricScene(foodHeightMm: dWell, rings: [], backgroundHeightMm: dWall)
        guard let s = SupportRegion.ringStatistics(foodMask: mask, depth: depth,
                                                    intrinsics: sceneDepthIntrinsics(depth), plane: plane(d: dWell))
        else { return XCTFail("expected ring statistics") }
        XCTAssertGreaterThan(s.bandMedianMm[0], 30, "bowl wall must already dominate the inner band")
    }

    // Leaked-to-table: plate covers food + inner + mid; beyond that the ring
    // has crossed the plate edge onto the (lower) table — profile falls.
    func testLeakedRingFallsOutwardInOuterBand() {
        let dPlate: Float = 126
        let dTable: Float = 100
        let mask = ellipseFoodMask(width: sceneWidth, height: sceneHeight,
                                   cx: sceneFoodCentre.x, cy: sceneFoodCentre.y,
                                   rx: sceneFoodRadiusPx, ry: sceneFoodRadiusPx)
        // dPlate = 126 matches the baseline the shared scene constants were
        // derived from, so sceneOuterBoundaryPx (mid→outer) applies directly.
        let depth = concentricScene(foodHeightMm: dPlate,
                                    rings: [(sceneOuterBoundaryPx, dPlate)],
                                    backgroundHeightMm: dTable)
        guard let s = SupportRegion.ringStatistics(foodMask: mask, depth: depth,
                                                    intrinsics: sceneDepthIntrinsics(depth), plane: plane(d: dPlate))
        else { return XCTFail("expected ring statistics") }
        XCTAssertEqual(s.bandMedianMm[0], 0, accuracy: 2.0)
        XCTAssertLessThan(s.bandMedianMm[2], -10, "outer band should fall towards the table")
    }

    // MARK: - Sector support (Req 3.6, Decision 18)

    // A ring 65 % on the table over a CONTIGUOUS arc: aggregate support (vs
    // the table candidate) reads a healthy ~0.65, but the supporting-sector
    // count is far short of all 8 — the spatial-arrangement signal the
    // aggregate fraction cannot see.
    func testStraddlingRingReadsHealthyAggregateButFewSupportingSectors() {
        let dTable: Float = 100
        let dPlate: Float = 126
        let mask = ellipseFoodMask(width: sceneWidth, height: sceneHeight,
                                   cx: sceneFoodCentre.x, cy: sceneFoodCentre.y,
                                   rx: sceneFoodRadiusPx, ry: sceneFoodRadiusPx)
        let depth = angularSplitScene(foodHeightMm: dTable, angleFractionA: 0.65,
                                      heightA: dTable, heightB: dPlate)
        guard let s = SupportRegion.ringStatistics(foodMask: mask, depth: depth,
                                                    intrinsics: sceneDepthIntrinsics(depth), plane: plane(d: dTable))
        else { return XCTFail("expected ring statistics") }
        XCTAssertEqual(s.supportFraction, 0.65, accuracy: 0.08,
                       "aggregate support must read the healthy, misleading ~0.65")
        XCTAssertLessThan(s.supportingSectors, SupportRegion.ringSectorCount,
                          "a straddling ring must not support every sector")
        XCTAssertLessThanOrEqual(s.supportingSectors, 6,
                                 "support confined to ~235° of 360° must leave only a minority of sectors")
    }

    // MARK: - Sample floor (Decision 20)

    func testThinInnerBandReturnsNil() {
        // Food pinned in a 40×40 corner crop: most of the ring/annulus falls
        // outside the image, leaving far fewer than ringMinSamples per band.
        let tinyIntrinsics = CameraIntrinsics(fx: 900, fy: 900, cx: 150, cy: -50, imageWidth: 320, imageHeight: 360)
        let mask = ellipseFoodMask(width: 40, height: 40, cx: 4, cy: 4, rx: 2, ry: 2)
        let depth = concentricScene(depthWidth: 40, depthHeight: 40, intrinsics: tinyIntrinsics,
                                    centre: (4, 4), foodRadiusPx: 2,
                                    foodHeightMm: 126, rings: [], backgroundHeightMm: 126)
        let stats = SupportRegion.ringStatistics(foodMask: mask, depth: depth,
                                                  intrinsics: sceneDepthIntrinsics(depth), plane: plane(d: 126))
        XCTAssertNil(stats, "a heavily frame-clipped ring must not synthesise 200 samples per band")
    }

    // MARK: - Support visibility (Req 3.9, Decision 14)

    func testSupportVisibilityIsGridIndependent() {
        let d: Float = 126
        // Full resolution.
        let fullIntrinsics = CameraIntrinsics(fx: 1800, fy: 1800, cx: 300, cy: -100,
                                              imageWidth: 640, imageHeight: 720)
        let fullMask = ellipseFoodMask(width: 640, height: 720, cx: 300, cy: 360, rx: 12, ry: 12)
        let fullDepth = concentricScene(depthWidth: 640, depthHeight: 720, intrinsics: fullIntrinsics,
                                        centre: (300, 360), foodRadiusPx: 12,
                                        foodHeightMm: d, rings: [], backgroundHeightMm: d)
        guard let fullStats = SupportRegion.ringStatistics(
            foodMask: fullMask, depth: fullDepth, intrinsics: sceneDepthIntrinsics(fullDepth), plane: plane(d: d)
        ) else { return XCTFail("expected full-resolution ring statistics") }

        // Half resolution: every pixel-space quantity halved; intrinsics
        // halved too, so the resulting mmPerPixel doubles and cancels.
        let halfIntrinsics = CameraIntrinsics(fx: 900, fy: 900, cx: 150, cy: -50, imageWidth: 320, imageHeight: 360)
        let halfMask = ellipseFoodMask(width: 320, height: 360, cx: 150, cy: 180, rx: 6, ry: 6)
        let halfDepth = concentricScene(depthWidth: 320, depthHeight: 360, intrinsics: halfIntrinsics,
                                        centre: (150, 180), foodRadiusPx: 6,
                                        foodHeightMm: d, rings: [], backgroundHeightMm: d)
        guard let halfStats = SupportRegion.ringStatistics(
            foodMask: halfMask, depth: halfDepth, intrinsics: sceneDepthIntrinsics(halfDepth), plane: plane(d: d)
        ) else { return XCTFail("expected half-resolution ring statistics") }

        // A flat scene has abundant support, so the ratio itself is large (not
        // clamped to [0, 1]) — what must hold across resolutions is the RATIO,
        // within discretisation noise, not an absolute closeness.
        let relativeDelta = abs(fullStats.supportVisibility - halfStats.supportVisibility) / fullStats.supportVisibility
        XCTAssertLessThan(relativeDelta, 0.1,
                          "supportVisibility is a ratio of same-grid native counts — grid-independent")
    }

    // MARK: - contactRing

    func testContactRingExcludesFoodPixelsAndReturnsRingBandOnly() {
        let d: Float = 126
        let mask = ellipseFoodMask(width: sceneWidth, height: sceneHeight,
                                   cx: sceneFoodCentre.x, cy: sceneFoodCentre.y,
                                   rx: sceneFoodRadiusPx, ry: sceneFoodRadiusPx)
        let depth = concentricScene(foodHeightMm: d, rings: [], backgroundHeightMm: d)
        let intr = sceneDepthIntrinsics(depth)
        let ring = SupportRegion.contactRing(foodMask: mask, depth: depth, intrinsics: intr)
        XCTAssertFalse(ring.isEmpty)
        for idx in ring {
            let x = idx % mask.width, y = idx / mask.width
            XCTAssertFalse(mask.isFood(x: x, y: y), "ring must contain no food pixel (Req 2.1)")
        }
    }

    func testContactRingExcludesLowConfidenceSamples() {
        let d: Float = 126
        let mask = ellipseFoodMask(width: sceneWidth, height: sceneHeight,
                                   cx: sceneFoodCentre.x, cy: sceneFoodCentre.y,
                                   rx: sceneFoodRadiusPx, ry: sceneFoodRadiusPx)
        let depth = concentricScene(foodHeightMm: d, rings: [], backgroundHeightMm: d,
                                    confidenceAt: { _, _ in 0 })   // uniformly below τ_conf
        let intr = sceneDepthIntrinsics(depth)
        let ring = SupportRegion.contactRing(foodMask: mask, depth: depth, intrinsics: intr)
        XCTAssertTrue(ring.isEmpty, "τ_conf = 0.40 must exclude uniformly low-confidence samples")
    }
}

// Depth intrinsics for a scene already built at NATIVE resolution — identity
// scale, since `contactRing`/`ringStatistics` operate on the depth grid
// directly (no colour→depth downsampling in these tests).
func sceneDepthIntrinsics(_ depth: DepthMap) -> CameraIntrinsics {
    CameraIntrinsics(fx: depth.depthIntrinsics.fx, fy: depth.depthIntrinsics.fy,
                     cx: depth.depthIntrinsics.cx, cy: depth.depthIntrinsics.cy,
                     distortion: [], imageWidth: depth.width, imageHeight: depth.height)
}

import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import XCTest
@testable import Volume

// Regression tests for bug `flat-food-volume-overread-table-plane`.
//
// Field capture 1785135663727 (two slices of rye bread on a white plate on a
// marble worktop) estimated 682.3 cm3 / 272.9 g — a ~2.9x over-read, surfaced
// to the user as "7.5 slices" of bread instead of 2.
//
// The support plane is the reference surface every height-field sample is
// measured against: `HeightFieldEstimator` integrates
// `max(0, z_support - z_top)` per pixel. The food rests on the PLATE, so the
// plate top is the correct reference. `LiDARPlaneFitter` collects candidates in
// bands as thick as the food bbox in each direction, which on a normal capture
// reach well past the plate onto the table; the table then wins RANSAC on area
// and every height gains the plate's rise above the table.
//
// The absolute error is the plate rise (26 mm on the field capture), so the
// RELATIVE error scales inversely with food height — which is why flat foods
// such as bread blow up while tall foods look merely "coarse".
//
// Scene: a 10 mm-thick flat slab of food on a plate whose top sits 20 mm above
// the table. The fit lands on the table and the volume trebles.
//
// BOTH TESTS ARE SKIPPED, DELIBERATELY. The table is currently the SPECIFIED
// reference surface, not an accident: pipeline Req 4.2 fits "at and around the
// lower edge of the food bounding region", DECISIONS.md MD-9 calls edge-band
// sampling "the table-plane prior", and bugfix
// lidar-plane-fit-degenerate-on-clean-capture Decision 1 tuned the mask so the
// band "sits on table pixels, not plate rim" — rejecting a smaller fraction
// because it would overlap the plate. Meanwhile nutrition5k-calibration Req 3.6
// requires the opposite for the offline path: integrate "above the surface the
// food rests on (the plate top), not the surrounding table".
//
// These tests encoded ONE candidate resolution — that the device adopt the
// plate-top reference the calibration path already uses — and were SKIPPED
// pending the spec work that would settle it. `specs/estimation/support-plane-reference/`
// is that work: Req 1.1 redefines the support plane as the surface the food
// rests on, and `SupportRegion.fitFoodSupportPlane` implements it. The skip is
// therefore removed and the assertions now run (task 23, Req 7.5).
//
// What changed with the un-skip. The tests exercise
// `LiDARSupportPlaneFitter.fitFromDepth` — the Req 4 fallback ladder — rather
// than `LiDARPlaneFitter.fitOutcome` directly, because the edge-band fitter is
// deliberately unchanged: it remains the fallback and still lands on the table
// by construction (Req 4.3). The reference actually selected is asserted
// alongside the plane, since a plate-height plane reached via the fallback
// would be an accident rather than the contract.
//
// Field evidence, capture bundle 1785135663727-success.fixture: shipped band
// scan 682.96 cm3 (device recorded 682.31); plane fitted to the plate surface
// 235.96 cm3; the fitted plane sits 26.1 mm below the plate the bread rests on.
// Mass 272.92 g -> 94.4 g, i.e. "7.5 slices" -> ~2.6.
final class PlateTopSupportPlaneTests: XCTestCase {

    // Depths in mm along the optical axis; a horizontal plane at Z = -d reads a
    // constant depth d, so each surface is one flat depth value.
    private let tableDepthMm: Float = 400
    private let plateTopDepthMm: Float = 380   // 20 mm above the table
    private let foodTopDepthMm: Float = 370    // 10 mm-thick slab on the plate

    private let width = 240
    private let height = 180

    // Centred 40x40 food square; a plate disc around it; table everywhere else.
    //
    // The plate radius grew from 30 px to 44 px when the skip came off, and the
    // reason is a real constraint rather than test convenience. Selection is now
    // decided by a contact ring spanning `SupportRegion.ringInnerMm` 8 mm to
    // `ringOuterMm` 25 mm outside the food boundary, so the plate has to carry
    // 25 mm of visible surface in EVERY direction — including past the food
    // square's corners, which sit 28.3 px from centre. At 370 mm range with
    // f = 200 the scale is 1.85 mm/px, making 25 mm about 13.5 px; 28.3 + 13.5
    // rounds up to 44. A 30 px plate leaves the ring's diagonal sectors on the
    // table, which is the Req 3.6 crossing case and correctly falls back — a
    // different scene from the one these tests are about.
    //
    // The pre-feature bands still favour the table, which is what makes the
    // assertions meaningful, but by 1.9:1 rather than the 9:1 the 30 px plate
    // gave: the bbox-sized bands span ~120x120 px, holding ~8,300 table pixels
    // against ~4,500 plate ones. Domination is thinner, and the fitter still
    // picks the table, because area is all it scores on.
    private let foodMinX = 100, foodMaxX = 139
    private let foodMinY = 70, foodMaxY = 109
    private let plateRadiusPx: Float = 44

    private func intrinsics() -> CameraIntrinsics {
        CameraIntrinsics(
            fx: 200, fy: 200, cx: 120, cy: 90,
            imageWidth: width, imageHeight: height
        )
    }

    private func isFood(_ x: Int, _ y: Int) -> Bool {
        x >= foodMinX && x <= foodMaxX && y >= foodMinY && y <= foodMaxY
    }

    private func isPlate(_ x: Int, _ y: Int) -> Bool {
        let dx = Float(x) - 120, dy = Float(y) - 90
        return (dx * dx + dy * dy).squareRoot() <= plateRadiusPx
    }

    // Deterministic sub-millimetre depth jitter. Perfectly coplanar synthetic
    // points make the refine() scatter matrix singular and trip the
    // `lidarFitDegenerate` stability gate (bug
    // lidar-plane-fit-degenerate-on-clean-capture); real LiDAR always carries
    // noise, and the field capture fitted at 1.95 mm residual. Amplitude stays
    // well inside the fitter's +/-5 mm inlier band.
    private func jitterMm(_ x: Int, _ y: Int) -> Float {
        var h = UInt64(truncatingIfNeeded: x &* 73_856_093 ^ y &* 19_349_663)
        h ^= h >> 33; h = h &* 0xff51_afd7_ed55_8ccd; h ^= h >> 33
        return (Float(h % 2001) / 1000 - 1)   // -1.0 ... +1.0 mm
    }

    private func depthAt(_ x: Int, _ y: Int) -> Float {
        let base: Float
        if isFood(x, y) { base = foodTopDepthMm }
        else if isPlate(x, y) { base = plateTopDepthMm }
        else { base = tableDepthMm }
        return base + jitterMm(x, y)
    }

    private func scene() -> (DepthMap, BinaryMask, CameraIntrinsics) {
        let k = intrinsics()
        let depth = makeDepthMap(
            width: width, height: height, intrinsics: k,
            depthMm: { y, x in self.depthAt(x, y) }
        )
        let mask = makeBinaryMask(width: width, height: height) { y, x in
            self.isFood(x, y)
        }
        return (depth, mask, k)
    }

    // The fitted support plane must be the surface the food RESTS ON (the plate
    // top at 380 mm), not the table it merely sits near (400 mm).
    func testSupportPlaneLandsOnPlateTopNotTable() throws {
        let (depth, mask, k) = scene()
        let outcome = LiDARSupportPlaneFitter.fitFromDepth(
            depth: depth, intrinsics: k, mask: mask, gravity: Vec3(0, 0, 1)
        )
        let plane = try XCTUnwrap(outcome.plane, "expected a support plane fit")

        // The reference is asserted, not inferred from the height: a plane at
        // plate height reached through the edge-band fallback would be luck.
        XCTAssertEqual(
            outcome.stats.reference, .foodSupport,
            "plate-top selection must come from the restricted fit, not the fallback"
        )
        // The whole-ring median is the Req 3.1 measure: ~0 on the surface the
        // food rests on, +20 mm here if the fit had landed on the table.
        let ring = try XCTUnwrap(outcome.stats.ring, "expected ring statistics")
        XCTAssertEqual(ring.medianMm, 0, accuracy: 2,
                       "ring median \(ring.medianMm) mm — the plane is not on the ring's surface")

        // distanceMm = n·p with n ≈ (0,0,1), so a surface at depth d gives -d.
        let fittedDepthMm = -plane.distanceMm
        XCTAssertEqual(
            fittedDepthMm, plateTopDepthMm, accuracy: 3,
            """
            Support plane landed \(fittedDepthMm) mm out instead of the plate top \
            at \(plateTopDepthMm) mm. A fit on the table (\(tableDepthMm) mm) adds \
            the plate's rise to every height-field sample.
            """
        )
    }

    // End-to-end consequence: the integrated volume must be the slab's own
    // volume, not the slab plus the plate's rise over the slab's footprint.
    func testFlatFoodVolumeExcludesPlateRise() throws {
        let (depth, mask, k) = scene()
        let palette = makePalette(numFood: 1)
        let foodClass = 0

        let argmax = makeArgmax(width: width, height: height) { y, x in
            self.isFood(x, y) ? foodClass : palette.background
        }
        let probs = makeProbTensor(width: width, height: height, palette: palette) { y, x, c in
            let food = self.isFood(x, y)
            if c == foodClass { return food ? 1 : 0 }
            if c == palette.background { return food ? 0 : 1 }
            return 0
        }

        let planeOutcome = LiDARSupportPlaneFitter.fitFromDepth(
            depth: depth, intrinsics: k, mask: mask, gravity: Vec3(0, 0, 1)
        )
        let plane = try XCTUnwrap(planeOutcome.plane, "expected a support plane fit")
        XCTAssertEqual(planeOutcome.stats.reference, .foodSupport)

        let outcome = HeightFieldEstimator.integrate(HeightFieldEstimator.Inputs(
            probabilities: probs,
            argmax: argmax,
            depth: depth,
            intrinsics: k,
            supportPlane: plane,
            beta: BetaCorrection(entries: [:], defaultBeta: 1.0),
            palette: palette
        ))
        let estimate = try XCTUnwrap(outcome.estimate, "expected a volume estimate")
        let volumeCm3 = try XCTUnwrap(estimate.perClassVolumesCm3["food_0"])

        // Footprint: 40x40 px at 370 mm with f = 200 → 74 mm per 40 px, so
        // ~54.8 cm2; times the 10 mm slab → ~54.8 cm3. Off-axis pixel-area
        // weighting moves this a little, so assert the slab thickness implied
        // by the volume rather than a hard-coded number.
        let footprintCm2 = footprintAreaCm2(depth: depth, k: k)
        let impliedThicknessMm = 10 * volumeCm3 / footprintCm2
        XCTAssertEqual(
            impliedThicknessMm, 10, accuracy: 1.5,
            """
            Implied food thickness \(impliedThicknessMm) mm (volume \(volumeCm3) cm3 \
            over \(footprintCm2) cm2) instead of the true 10 mm slab. A table-referenced \
            plane inflates this to ~30 mm — the flat-food over-read.
            """
        )
    }

    // Sum of the same off-axis pixel areas the estimator uses, over the food
    // silhouette, so the assertion above is independent of the projection maths.
    private func footprintAreaCm2(depth: DepthMap, k: CameraIntrinsics) -> Float {
        let fMean = (k.fx + k.fy) / 2
        var areaMm2: Float = 0
        for y in 0..<height {
            for x in 0..<width where isFood(x, y) {
                let zt = depthAt(x, y)
                let du = Float(x) - k.cx, dv = Float(y) - k.cy
                let cosTheta = fMean / (fMean * fMean + du * du + dv * dv).squareRoot()
                areaMm2 += (zt * zt) / (k.fx * k.fy * cosTheta * cosTheta * cosTheta)
            }
        }
        return areaMm2 / 100
    }
}

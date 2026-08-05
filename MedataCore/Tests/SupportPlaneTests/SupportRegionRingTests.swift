import CaptureKit
import Foundation
import PortableContracts
@testable import SupportPlane
import Testing

// Task 3: the contact ring and its statistics
// (Reqs 3.1, 3.2, 3.5, 3.6, 3.8, 3.9).
@Suite("SupportRegion contact ring and ring statistics (Reqs 3.1, 3.2, 3.6, 3.8, 3.9)")
struct SupportRegionRingTests {

    // MARK: – Radial profile (Req 3.8, Decision 14)

    @Test("a flat surface reads equal band medians and full support")
    func flatSurfaceHasEqualBands() throws {
        let ring = try #require(SPRScene.ringStatistics(
            SPRScene.plateAboveTable(plateHeightMm: 0), planeHeightMm: 0
        ))
        for band in ring.bandMedianMm {
            #expect(abs(band) < 0.5, "flat surface must read ~0 in every band; got \(ring.bandMedianMm)")
        }
        #expect(abs(ring.medianMm) < 0.5)
        #expect(ring.supportFraction == 1.0)
        #expect(ring.supportingSectors == SupportRegion.ringSectorCount)
    }

    // A rimmed plate with the well partly visible: the profile RISES outward. This is
    // the candidate Decisions 14 and 16 exist to rescue, which is why the step guard
    // reads inner→mid only (Decision 21) — see the selection suite.
    @Test("a rim in the outer band makes the profile rise outward")
    func rimRisesOutward() throws {
        let ring = try #require(SPRScene.ringStatistics(
            SPRScene.rimmedPlate(rimStartPx: 24), planeHeightMm: 20
        ))
        #expect(abs(ring.bandMedianMm[0]) < 0.5, "the inner band is on the well")
        #expect(abs(ring.bandMedianMm[1]) < 0.5, "the mid band is still on the well")
        #expect(ring.bandMedianMm[2] > 10, "the outer band is on the rim; got \(ring.bandMedianMm[2])")
    }

    @Test("a bowl wall makes every band rise steeply over the one inside it")
    func bowlRisesSteeplyOutward() throws {
        let ring = try #require(SPRScene.ringStatistics(SPRScene.bowl(), planeHeightMm: 20))
        #expect(ring.bandMedianMm[0] > 0)
        #expect(ring.bandMedianMm[1] - ring.bandMedianMm[0] > SupportRegion.bandStepMaxMm,
                "a bowl's inner→mid step must exceed the guard; got \(ring.bandMedianMm)")
        #expect(ring.bandMedianMm[2] > ring.bandMedianMm[1])
    }

    @Test("a ring that leaked past the plate edge falls outward")
    func leakedRingFallsOutward() throws {
        let ring = try #require(SPRScene.ringStatistics(
            SPRScene.plateAboveTable(plateRadiusPx: 22), planeHeightMm: 20
        ))
        #expect(abs(ring.bandMedianMm[0]) < 0.5, "the inner band is still on the plate")
        #expect(ring.bandMedianMm[2] < -10, "the outer band has leaked onto the table; got \(ring.bandMedianMm)")
    }

    // MARK: – Sample floor (Decisions 14, 20)

    @Test("the ringMinSamples floor holds per band, not just overall")
    func sampleFloorHoldsPerBand() throws {
        let ring = try #require(SPRScene.ringStatistics(SPRScene.plateAboveTable(), planeHeightMm: 20))
        #expect(ring.bandSampleCount.count == SupportRegion.ringBandCount)
        for count in ring.bandSampleCount {
            #expect(count >= SupportRegion.ringMinSamples, "band counts \(ring.bandSampleCount)")
        }
    }

    // Food smaller than ~25 mm across at 350 mm falls back: that is the price
    // Decision 20 pays for sector statistics that mean something.
    @Test("a thinner inner band than ringMinSamples returns nil")
    func thinInnerBandReturnsNil() {
        let small = SPRScene.plateAboveTable(foodRadiusPx: 3, plateHeightMm: 0)
        #expect(SPRScene.ringStatistics(small, planeHeightMm: 0) == nil,
                "a ring too thin to sector must return nil, not a noisy statistic")

        let adequate = SPRScene.plateAboveTable(plateHeightMm: 0)
        #expect(SPRScene.ringStatistics(adequate, planeHeightMm: 0) != nil,
                "the same scene with ordinary food must produce statistics")
    }

    // MARK: – Ring membership (Reqs 2.1, 7.5)

    @Test("the ring excludes food pixels and samples below tau_conf")
    func ringExcludesFoodAndLowConfidenceSamples() throws {
        var scene = SPRScene.plateAboveTable()
        // Blank the confidence over the right half of the frame, as a matte surface
        // does. tau_conf = 0.40 applies here exactly as it does in the band scan, so
        // `lidar-plane-fit-matte-table-confidence` is not bypassed.
        for y in 0..<scene.height {
            for x in 128..<scene.width { scene.confidence[y * scene.width + x] = 0 }
        }
        let depth = SPRScene.makeDepth(scene)
        let ring = SupportRegion.contactRing(
            foodMask: SPRScene.makeColourMask(scene), depth: depth,
            intrinsics: SPRScene.colourIntrinsics
        )
        #expect(!ring.isEmpty)

        let foodMask = SupportRegion.downsampleFoodMask(
            SPRScene.makeColourMask(scene), width: scene.width, height: scene.height
        )
        for index in ring {
            #expect(foodMask.pixels[index] == 0, "ring index \(index) is a food pixel")
            #expect(scene.confidence[index] != 0, "ring index \(index) is below tau_conf")
        }
    }

    // Radii are millimetres converted per capture from the median food depth, which is
    // what makes them transfer across depth-grid resolutions (Req 5.1).
    @Test("ring radii are millimetre-denominated, not pixel-denominated")
    func ringRadiiAreMillimetreDenominated() throws {
        let scene = SPRScene.plateAboveTable()
        let measured = try #require(SPRScene.measure(scene))
        let distances = SupportRegion.distanceToFoodPx(mask: measured.geometry.foodMask)

        for index in measured.samples.ring {
            let mm = distances[index] * measured.geometry.mmPerPx
            #expect(mm >= SupportRegion.ringInnerMm - 1e-3 && mm <= SupportRegion.ringOuterMm + 1e-3,
                    "ring sample at \(mm) mm is outside [\(SupportRegion.ringInnerMm), \(SupportRegion.ringOuterMm)]")
        }
        for index in measured.samples.annulus {
            let mm = distances[index] * measured.geometry.mmPerPx
            #expect(mm <= 2 * SupportRegion.ringOuterMm + 1e-3,
                    "annulus sample at \(mm) mm is outside the 2 x ringOuterMm bound")
        }
    }

    // MARK: – Sectors (Req 3.6, Decision 18)

    // The aggregate fraction is a majority vote and cannot tell a ring lying wholly on
    // the support surface from one that has crossed its edge. This scene is the food
    // half off a plate, where the TABLE plane reads a healthy aggregate and a flat
    // radial profile — every signal except the sectors says the fit is good.
    @Test("a ring supported only across an arc reads healthy in aggregate and fails on sectors")
    func sectorsSeparateArcSupportFromAggregate() throws {
        let scene = SPRScene.foodAcrossPlateEdge(edgeOffsetPx: -10)
        let table = try #require(SPRScene.ringStatistics(scene, planeHeightMm: 0))

        #expect(table.supportFraction >= SupportRegion.ringSupportMin,
                "the aggregate must look healthy; got \(table.supportFraction)")
        #expect(abs(table.medianMm) < 1, "and the ring median must read ~0; got \(table.medianMm)")
        for band in table.bandMedianMm {
            #expect(abs(band) < 1, "and the radial profile must be flat; got \(table.bandMedianMm)")
        }
        #expect(table.supportingSectors < SupportRegion.minSupportingSectors,
                "only the sector measure sees the arc; got \(table.supportingSectors) sectors")
    }

    // MARK: – Support visibility (Req 3.9)

    // Both counts are native depth samples, so the ratio is dimensionless. The same
    // physical scene on a 2x finer depth grid must report the same visibility.
    @Test("supportVisibility is grid-independent")
    func supportVisibilityIsGridIndependent() throws {
        let coarse = try #require(SPRScene.ringStatistics(SPRScene.plateAboveTable(), planeHeightMm: 20))
        let fine = try #require(SPRScene.ringStatistics(SPRScene.plateAboveTable(scale: 2), planeHeightMm: 20))

        #expect(fine.bandSampleCount[0] > 3 * coarse.bandSampleCount[0],
                "the finer grid must actually hold more samples, or this proves nothing")
        let ratio = fine.supportVisibility / coarse.supportVisibility
        #expect(abs(ratio - 1) < 0.02,
                "visibility must not scale with the grid: \(coarse.supportVisibility) vs \(fine.supportVisibility)")
    }

    @Test("supportVisibility counts annulus samples on the plane against food samples")
    func supportVisibilityIsAnnulusOverFood() throws {
        let scene = SPRScene.plateAboveTable()
        let measured = try #require(SPRScene.measure(scene))
        let plane = SPRScene.plane(atHeightMm: 20)
        let ring = try #require(SupportRegion.ringStatistics(
            samples: measured.samples, geometry: measured.geometry,
            normal: plane.normal, d: plane.d
        ))
        let inBand = measured.samples.annulus.filter {
            abs(plane.normal.dot(measured.geometry.points[$0]) - plane.d) <= LiDARPlaneFitter.inlierBandMm
        }.count
        let expected = Float(inBand) / Float(measured.geometry.foodSampleCount)
        #expect(abs(ring.supportVisibility - expected) < 1e-4)
    }
}

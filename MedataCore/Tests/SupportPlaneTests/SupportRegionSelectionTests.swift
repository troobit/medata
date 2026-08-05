import CaptureKit
import Foundation
import PortableContracts
@testable import SupportPlane
import Testing

// Task 7: admissibility guards, selection and determinism
// (Reqs 1.3, 3.1–3.4, 3.6, 3.8, 3.9, 7.7).
@Suite("SupportRegion admissibility and selection (Reqs 1.3, 3.1-3.4, 3.6, 3.8, 3.9, 7.7)")
struct SupportRegionSelectionTests {

    // MARK: – The case the pre-feature fitter gets wrong

    // The table dominates the FRAME roughly 26:1 here. It cannot dominate the
    // CANDIDATE SET: bounding to an annulus of 2 x ringOuterMm caps the table's share
    // at parity whenever the ring itself lies on the plate, which is the bound doing
    // its job (Decision 15). The design's "table dominant ~9:1" describes the scene,
    // not the bounded sample set.
    @Test("a plate 20 mm above a dominant table selects the plate")
    func selectsThePlateOverTheTable() throws {
        let scene = SPRScene.plateAboveTable()
        let tablePixels = scene.heightMm.filter { $0 == 0 }.count
        let platePixels = scene.heightMm.filter { $0 == 20 }.count
        #expect(tablePixels > 9 * platePixels, "the scene must be table-dominant: \(tablePixels) vs \(platePixels)")

        let fit = try #require(SPRScene.fit(scene))
        #expect(abs(SPRScene.heightMm(of: fit.plane) - 20) < 1,
                "expected the plate top; got \(SPRScene.heightMm(of: fit.plane)) mm above the table")
        #expect(abs(fit.ring.medianMm) < 1, "a correct fit reads a ring median of ~0")
        #expect(fit.ring.supportingSectors == SupportRegion.ringSectorCount)
        #expect(fit.candidateCount == 2)
    }

    @Test("a plain flat surface with no plate still fits")
    func flatSurfaceFits() throws {
        let fit = try #require(SPRScene.fit(SPRScene.plateAboveTable(plateHeightMm: 0)))
        #expect(abs(SPRScene.heightMm(of: fit.plane)) < 1)
    }

    // MARK: – The silent-failure case (Decision 18)

    // Food half off a flat plate. The TABLE plane scores a healthy aggregate, clears
    // the ambiguity margin, reads a FLAT band profile and a median of ~0 — every guard
    // except sectors passes, and the record it would write is the one the spec treats
    // as proof of correctness. This is worse than the defect being fixed, because the
    // diagnostic certifies the wrong answer.
    @Test("food across a plate edge is rejected on sectors, not recorded as a good fit")
    func foodAcrossThePlateEdgeIsRejectedOnSectors() throws {
        let scene = SPRScene.foodAcrossPlateEdge(edgeOffsetPx: -10)
        let measured = try #require(SPRScene.measure(scene))
        let table = SPRScene.plane(atHeightMm: 0)
        let ring = try #require(SupportRegion.ringStatistics(
            samples: measured.samples, geometry: measured.geometry,
            normal: table.normal, d: table.d
        ))
        let annulusMedian = SupportRegion.medianHeight(
            indices: measured.samples.annulus, geometry: measured.geometry,
            normal: table.normal, d: table.d
        )
        let envelope = SupportRegion.foodEnvelopeMm(
            geometry: measured.geometry, normal: table.normal, d: table.d
        )
        // Everything else about this candidate looks healthy.
        #expect(ring.supportFraction >= SupportRegion.ringSupportMin)
        #expect(abs(ring.medianMm) <= SupportRegion.ringMedianMaxMm)
        #expect(ring.bandMedianMm[1] - ring.bandMedianMm[0] <= SupportRegion.bandStepMaxMm)
        #expect(ring.supportVisibility >= SupportRegion.supportVisibilityMin)
        #expect(envelope >= SupportRegion.foodEnvelopeMinMm)
        #expect(annulusMedian <= SupportRegion.escapeBandMm)

        #expect(SupportRegion.admissibility(ring: ring, annulusMedianMm: annulusMedian,
                                            foodEnvelopeMm: envelope, extentPx: 64) == .sectors,
                "the sector guard must be what rejects it")
        #expect(SPRScene.fit(scene) == nil, "the capture must fall back, not record .foodSupport")
    }

    // Note on the sector arithmetic. For support confined to a contiguous arc, the
    // supporting-sector count is roughly `fraction x ringSectorCount`, and it lands
    // within +/-1 of that depending on where the arc falls relative to the sector
    // boundaries. With `ringSupportMin = 0.6` and `minSupportingSectors = 6` the
    // window in which the aggregate passes and the sectors fail is therefore narrow,
    // and this scene sits inside it by construction. That marginality is exactly what
    // Req 3.7's corpus measurement of the sector trio has to resolve; the guard's
    // mechanism is what this test pins, not the width of its window.

    @Test("a ring straddling the plate edge 50/50 falls back")
    func fiftyFiftyStraddleFallsBack() {
        #expect(SPRScene.fit(SPRScene.foodAcrossPlateEdge(edgeOffsetPx: 2)) == nil)
        #expect(SPRScene.fit(SPRScene.foodAcrossPlateEdge(edgeOffsetPx: -2)) == nil)
    }

    // MARK: – The rimmed plate (Decisions 14, 21)

    @Test("a rim in the outer band leaves the inner band authoritative and the well wins")
    func rimInTheOuterBandSelectsTheWell() throws {
        let fit = try #require(SPRScene.fit(SPRScene.rimmedPlate(rimStartPx: 24)))
        #expect(abs(SPRScene.heightMm(of: fit.plane) - 20) < 1,
                "expected the well at 20 mm, not the rim at 35; got \(SPRScene.heightMm(of: fit.plane))")
        #expect(fit.ring.bandMedianMm[2] > 10, "the persisted profile must still show the rim")
    }

    // A rise already present at inner→mid means the surface the ring itself rests on
    // is not flat — a rim hard against the food. Fallback is the conservative
    // direction, and it is not a rim fit.
    @Test("a rim step inside the mid band rejects to fallback")
    func rimInTheMidBandFallsBack() throws {
        let scene = SPRScene.rimmedPlate(rimStartPx: 19)
        let ring = try #require(SPRScene.ringStatistics(scene, planeHeightMm: 20))
        #expect(SupportRegion.admissibility(ring: ring, annulusMedianMm: 15, foodEnvelopeMm: 8,
                                            extentPx: 64) == .bandStep)
        #expect(SPRScene.fit(scene) == nil)
    }

    // When food fills the well, the well produces no depth samples at all and no
    // candidate plane can be fitted to it. The rim plane must not be selected in its
    // place: the food lies entirely below it, so its upper envelope is negative.
    //
    // The design expected `supportVisibility` to be the guard that fires here. It does
    // not — the rim is fully observed, so visibility reads 3.8 against a 0.15 bar. The
    // outcome the requirement demands (fallback, not a rim under-read) still holds,
    // via the envelope guard; which bar fires is a task 26 measurement.
    @Test("a fully covered well falls back rather than fitting the rim")
    func fullyCoveredWellFallsBack() throws {
        let scene = SPRScene.rimmedPlate(foodRadiusPx: 20, rimStartPx: 20)
        let ring = try #require(SPRScene.ringStatistics(scene, planeHeightMm: 35))
        #expect(ring.supportFraction == 1.0, "the rim looks like a perfect support surface")
        #expect(abs(ring.medianMm) < 1)

        let envelope = SupportRegion.foodEnvelopeMm(
            geometry: try #require(SPRScene.measure(scene)).geometry,
            normal: SPRScene.plane(atHeightMm: 35).normal, d: SPRScene.plane(atHeightMm: 35).d
        )
        #expect(envelope < SupportRegion.foodEnvelopeMinMm, "the food lies below the rim plane")
        #expect(SPRScene.fit(scene) == nil)
    }

    @Test("a bowl falls back")
    func bowlFallsBack() {
        #expect(SPRScene.fit(SPRScene.bowl()) == nil)
    }

    // MARK: – Overhang must not trigger the guards (Req 1.3, Decision 22)

    // `foodAboveFractionMax = 0.05` rejected this feature's own acceptance capture:
    // overhanging food sits BELOW the plate plane, so a count fraction votes against
    // the correct fit. The envelope test puts those samples in the lower decile where
    // they belong.
    @Test("overhanging food below the plane is accepted")
    func overhangingFoodIsAccepted() throws {
        let scene = SPRScene.overhangingFood(lobeHalfAngleDeg: 8)
        let measured = try #require(SPRScene.measure(scene))
        let plate = SPRScene.plane(atHeightMm: 20)
        let below = measured.geometry.foodIndices.filter {
            plate.normal.dot(measured.geometry.points[$0]) - plate.d < 0
        }.count
        let belowFraction = Float(below) / Float(measured.geometry.foodSampleCount)
        #expect(belowFraction > 0.05,
                "a 0.05 count-fraction bar must reject this scene, or it proves nothing; got \(belowFraction)")

        let fit = try #require(SPRScene.fit(scene), "the overhang must not trigger a guard")
        #expect(abs(SPRScene.heightMm(of: fit.plane) - 20) < 1)
        let envelope = SupportRegion.foodEnvelopeMm(
            geometry: measured.geometry, normal: plate.normal, d: plate.d
        )
        #expect(envelope >= SupportRegion.foodEnvelopeMinMm,
                "the food's upper envelope is what the guard reads; got \(envelope) mm")
    }

    // MARK: – Guards that need a constructed candidate

    private func healthyRing(supportFraction: Float = 1.0, sectors: Int = 8,
                             bands: [Float] = [0, 0, 0], median: Float = 0,
                             visibility: Float = 4) -> RingStatistics {
        RingStatistics(medianMm: median, bandMedianMm: bands, supportFraction: supportFraction,
                       supportingSectors: sectors, bandSampleCount: [300, 350, 400],
                       supportVisibility: visibility)
    }

    // Decision 22: Req 3.3's stated comparator, "below the lowest admissible
    // candidate", compares a set's minimum against itself and cannot fire. The annulus
    // median is the comparator that can — a plane that escaped through a depth dropout
    // lands far below the surrounding surface.
    @Test("a plane that escaped below the annulus is rejected")
    func planeBelowTheAnnulusIsRejected() {
        #expect(SupportRegion.admissibility(
            ring: healthyRing(), annulusMedianMm: SupportRegion.escapeBandMm + 5,
            foodEnvelopeMm: 8, extentPx: 64
        ) == .escaped)
        #expect(SupportRegion.admissibility(
            ring: healthyRing(), annulusMedianMm: SupportRegion.escapeBandMm - 5,
            foodEnvelopeMm: 8, extentPx: 64
        ) == nil)
    }

    @Test("a winning component below minAcceptedExtentPx is rejected")
    func slimComponentIsRejected() {
        #expect(SupportRegion.admissibility(
            ring: healthyRing(), annulusMedianMm: 0, foodEnvelopeMm: 8,
            extentPx: SupportRegion.minAcceptedExtentPx - 1
        ) == .extent)
        #expect(SupportRegion.admissibility(
            ring: healthyRing(), annulusMedianMm: 0, foodEnvelopeMm: 8,
            extentPx: SupportRegion.minAcceptedExtentPx
        ) == nil)
    }

    // Req 3.2's guard reads the SIGN: the support fraction is unsigned and cannot
    // separate a plane above the ring (table, +) from one below it (vessel rim, −).
    @Test("the signed ring median rejects a plane above or below the ring")
    func signedRingMedianRejectsBothDirections() {
        let above = healthyRing(bands: [SupportRegion.ringMedianMaxMm + 2, 0, 0])
        let below = healthyRing(bands: [-(SupportRegion.ringMedianMaxMm + 2), 0, 0])
        #expect(SupportRegion.admissibility(ring: above, annulusMedianMm: 0,
                                            foodEnvelopeMm: 8, extentPx: 64) == .ringMedian)
        #expect(SupportRegion.admissibility(ring: below, annulusMedianMm: 0,
                                            foodEnvelopeMm: 8, extentPx: 64) == .ringMedian)
    }

    @Test("support visibility below the bar rejects")
    func lowVisibilityRejects() {
        #expect(SupportRegion.admissibility(
            ring: healthyRing(visibility: SupportRegion.supportVisibilityMin / 2),
            annulusMedianMm: 0, foodEnvelopeMm: 8, extentPx: 64
        ) == .visibility)
    }

    // Guards are an admissibility FILTER over every candidate, then the best
    // admissible one wins. Applied after selection, a phantom candidate that failed a
    // guard would drop the capture to fallback with an admissible plate plane sitting
    // unexamined in the set.
    @Test("a phantom candidate failing a guard does not discard an admissible one")
    func guardsFilterRatherThanVeto() throws {
        // The bowl scene produces three candidates, all inadmissible; the plate scene
        // produces two, one of which fails on support fraction. If guards vetoed the
        // set, the plate scene would fall back too.
        #expect(SPRScene.fit(SPRScene.bowl()) == nil)
        let fit = try #require(SPRScene.fit(SPRScene.plateAboveTable()))
        #expect(fit.candidateCount == 2, "one candidate failed a guard and the other still won")
    }

    // MARK: – Degenerate inputs and determinism

    @Test("a food mask at the frame edge shortens the ring and falls back without crashing")
    func foodAtFrameEdgeFallsBack() {
        let scene = SPRScene.plateAboveTable(plateRadiusPx: 60, centreX: 2)
        #expect(SPRScene.ringStatistics(scene, planeHeightMm: 20) == nil,
                "a clipped ring must not be judged on the fragment that remains")
        #expect(SPRScene.fit(scene) == nil)
    }

    @Test("an empty food mask returns nil rather than throwing")
    func emptyMaskReturnsNil() {
        let scene = SPRScene.plateAboveTable()
        let empty = BinaryMask(
            pixels: [UInt8](repeating: 0, count: SPRScene.colourWidth * SPRScene.colourHeight),
            width: SPRScene.colourWidth, height: SPRScene.colourHeight
        )
        #expect(SupportRegion.fitFoodSupportPlane(
            depth: SPRScene.makeDepth(scene), colourIntrinsics: SPRScene.colourIntrinsics,
            foodRegionMask: empty, gravityCamera: SPRScene.gravity
        ) == nil)
    }

    // Req 7.7: identical capture bytes produce an identical plane and reference.
    @Test("identical depth bytes produce an identical plane and ring")
    func fitIsDeterministic() throws {
        let scene = SPRScene.plateAboveTable()
        let first = try #require(SPRScene.fit(scene))
        let second = try #require(SPRScene.fit(scene))
        #expect(first.plane == second.plane)
        #expect(first.ring == second.ring)
        #expect(first.candidateCount == second.candidateCount)
    }

    // Req 5.1: the same capture on a finer depth grid must derive the same plane,
    // because every radius is millimetre-denominated.
    @Test("the same scene on a finer depth grid derives the same plane")
    func fitTransfersAcrossDepthGrids() throws {
        let coarse = try #require(SPRScene.fit(SPRScene.plateAboveTable()))
        let fine = try #require(SPRScene.fit(SPRScene.plateAboveTable(scale: 2)))
        #expect(abs(SPRScene.heightMm(of: coarse.plane) - SPRScene.heightMm(of: fine.plane)) < 0.5)
    }

    @Test("the fit returns nil rather than throwing when the annulus is starved")
    func starvedAnnulusReturnsNil() {
        // A 16x12 depth grid cannot fill three ring bands at ringMinSamples apiece,
        // so `ringBandsAreFeasible` refuses before any plane is fitted (Decision 32).
        let tiny = SPRScene.grid(width: 16, height: 12) { x, y in
            (0, x >= 6 && x < 10 && y >= 4 && y < 8)
        }
        #expect(SPRScene.fit(tiny) == nil)
    }
}

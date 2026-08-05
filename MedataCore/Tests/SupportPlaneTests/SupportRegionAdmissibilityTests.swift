import CaptureKit
import PortableContracts
import XCTest
@testable import SupportPlane

// Task 7: admissibility guards, selection and determinism (Req 1.3, 3.1–3.4,
// 3.6, 3.8, 3.9, 7.7; Decisions 18–22).
//
// Two layers: fast DIRECT tests of `isAdmissible` against hand-built
// statistics (one guard perturbed at a time — the design's guard table, made
// executable), and a smaller set of END-TO-END `fitFoodSupportPlane` scenes
// exercising the scenes the design names explicitly (straddling ring, rimmed
// plate, bowl, overhang, determinism).

private func plane(d: Float) -> SupportPlane {
    SupportPlane(normal: Vec3(0, 1, 0), distanceMm: d, residualMm: 0, convergedIterations: nil)
}

// A baseline that clears every guard row; each test below perturbs exactly
// one field to violate exactly one guard.
private struct AdmissibleFixture {
    var candidate: SupportPlaneCandidate
    var ring: RingStatistics
    var plane: SupportPlane
    var annulus: [SupportRegion.RingSample]
    var foodPoints: [Vec3]
    var width: Int
}

private func baselineFixture() -> AdmissibleFixture {
    let width = 200
    let d: Float = 100
    var inlierIndices: [Int] = []
    for y in 50..<80 { for x in 50..<80 { inlierIndices.append(y * width + x) } }   // 30×30 block

    let annulus: [SupportRegion.RingSample] = (0..<20).map { i in
        SupportRegion.RingSample(index: 1000 + i, point: Vec3(Float(i), 100, 0), distMm: 30, angle: 0)
    }
    let foodPoints: [Vec3] = (0..<10).map { i in Vec3(Float(i), 108, 0) }   // p90 height = +8

    let ring = RingStatistics(
        medianMm: 0, bandMedianMm: [0, 0, 0], supportFraction: 0.8,
        supportingSectors: 7, bandSampleCount: [250, 250, 250], supportVisibility: 0.5
    )
    let candidate = SupportPlaneCandidate(
        normal: Vec3(0, 1, 0), d: d, residualMm: 1, inlierIndices: inlierIndices, residueInlierRatio: 0.5
    )
    return AdmissibleFixture(candidate: candidate, ring: ring, plane: plane(d: d),
                             annulus: annulus, foodPoints: foodPoints, width: width)
}

final class SupportRegionAdmissibilityTests: XCTestCase {
    // MARK: - Positive control

    func testBaselineFixtureIsAdmissible() {
        let f = baselineFixture()
        XCTAssertTrue(SupportRegion.isAdmissible(candidate: f.candidate, ring: f.ring, plane: f.plane,
                                                 annulus: f.annulus, foodPoints: f.foodPoints, width: f.width))
    }

    // MARK: - Each guard row, perturbed in isolation (design §"Selection and admissibility")

    func testRejectsBelowRingSupportMin() {
        var f = baselineFixture()
        f.ring = RingStatistics(medianMm: f.ring.medianMm, bandMedianMm: f.ring.bandMedianMm,
                                supportFraction: SupportRegion.ringSupportMin - 0.01,
                                supportingSectors: f.ring.supportingSectors,
                                bandSampleCount: f.ring.bandSampleCount, supportVisibility: f.ring.supportVisibility)
        XCTAssertFalse(SupportRegion.isAdmissible(candidate: f.candidate, ring: f.ring, plane: f.plane,
                                                  annulus: f.annulus, foodPoints: f.foodPoints, width: f.width))
    }

    func testRejectsBelowMinSupportingSectors() {
        var f = baselineFixture()
        f.ring = RingStatistics(medianMm: f.ring.medianMm, bandMedianMm: f.ring.bandMedianMm,
                                supportFraction: f.ring.supportFraction,
                                supportingSectors: SupportRegion.minSupportingSectors - 1,
                                bandSampleCount: f.ring.bandSampleCount, supportVisibility: f.ring.supportVisibility)
        XCTAssertFalse(SupportRegion.isAdmissible(candidate: f.candidate, ring: f.ring, plane: f.plane,
                                                  annulus: f.annulus, foodPoints: f.foodPoints, width: f.width))
    }

    func testRejectsWhenFoodEnvelopeP90BelowMin() {
        var f = baselineFixture()
        // Food entirely BELOW the plane — a bowl / a plane on the food top.
        f.foodPoints = (0..<10).map { i in Vec3(Float(i), 90, 0) }   // height = -10
        XCTAssertFalse(SupportRegion.isAdmissible(candidate: f.candidate, ring: f.ring, plane: f.plane,
                                                  annulus: f.annulus, foodPoints: f.foodPoints, width: f.width))
    }

    func testAcceptsFoodEnvelopeWithOverhangingMinority() {
        // Decision 22: ~11% of food below the plane (overhang) must NOT
        // trip the envelope guard — only the upper decile (p90) matters.
        var f = baselineFixture()
        var pts: [Vec3] = (0..<9).map { i in Vec3(Float(i), 108, 0) }   // 90%, height +8
        pts.append(Vec3(9, 85, 0))                                     // 10%, height -15 (overhang)
        f.foodPoints = pts
        XCTAssertTrue(SupportRegion.isAdmissible(candidate: f.candidate, ring: f.ring, plane: f.plane,
                                                 annulus: f.annulus, foodPoints: f.foodPoints, width: f.width))
    }

    func testRejectsSignedMedianAboveBand() {
        var f = baselineFixture()
        f.ring = RingStatistics(medianMm: SupportRegion.ringBandMm + 5, bandMedianMm: f.ring.bandMedianMm,
                                supportFraction: f.ring.supportFraction, supportingSectors: f.ring.supportingSectors,
                                bandSampleCount: f.ring.bandSampleCount, supportVisibility: f.ring.supportVisibility)
        XCTAssertFalse(SupportRegion.isAdmissible(candidate: f.candidate, ring: f.ring, plane: f.plane,
                                                  annulus: f.annulus, foodPoints: f.foodPoints, width: f.width),
                      "table reads strongly positive (Req 3.1) — must reject")
    }

    func testRejectsSignedMedianBelowBand() {
        var f = baselineFixture()
        f.ring = RingStatistics(medianMm: -(SupportRegion.ringBandMm + 5), bandMedianMm: f.ring.bandMedianMm,
                                supportFraction: f.ring.supportFraction, supportingSectors: f.ring.supportingSectors,
                                bandSampleCount: f.ring.bandSampleCount, supportVisibility: f.ring.supportVisibility)
        XCTAssertFalse(SupportRegion.isAdmissible(candidate: f.candidate, ring: f.ring, plane: f.plane,
                                                  annulus: f.annulus, foodPoints: f.foodPoints, width: f.width),
                      "a vessel rim reads negative (Req 3.1) — must reject")
    }

    func testRejectsInnerToMidBandStepBeyondMax() {
        var f = baselineFixture()
        f.ring = RingStatistics(medianMm: f.ring.medianMm,
                                bandMedianMm: [0, SupportRegion.bandStepMaxMm + 1, SupportRegion.bandStepMaxMm + 1],
                                supportFraction: f.ring.supportFraction, supportingSectors: f.ring.supportingSectors,
                                bandSampleCount: f.ring.bandSampleCount, supportVisibility: f.ring.supportVisibility)
        XCTAssertFalse(SupportRegion.isAdmissible(candidate: f.candidate, ring: f.ring, plane: f.plane,
                                                  annulus: f.annulus, foodPoints: f.foodPoints, width: f.width))
    }

    func testAcceptsMidToOuterRiseAlone() {
        // Decision 21: the step guard reads inner→mid ONLY — a rise that
        // first appears mid→outer is shape detection, not a rejection.
        var f = baselineFixture()
        f.ring = RingStatistics(medianMm: f.ring.medianMm, bandMedianMm: [0, 0, 18],
                                supportFraction: f.ring.supportFraction, supportingSectors: f.ring.supportingSectors,
                                bandSampleCount: f.ring.bandSampleCount, supportVisibility: f.ring.supportVisibility)
        XCTAssertTrue(SupportRegion.isAdmissible(candidate: f.candidate, ring: f.ring, plane: f.plane,
                                                 annulus: f.annulus, foodPoints: f.foodPoints, width: f.width))
    }

    func testRejectsBelowSupportVisibilityMin() {
        var f = baselineFixture()
        f.ring = RingStatistics(medianMm: f.ring.medianMm, bandMedianMm: f.ring.bandMedianMm,
                                supportFraction: f.ring.supportFraction, supportingSectors: f.ring.supportingSectors,
                                bandSampleCount: f.ring.bandSampleCount,
                                supportVisibility: SupportRegion.supportVisibilityMin - 0.01)
        XCTAssertFalse(SupportRegion.isAdmissible(candidate: f.candidate, ring: f.ring, plane: f.plane,
                                                  annulus: f.annulus, foodPoints: f.foodPoints, width: f.width))
    }

    func testRejectsWhenAnnulusMedianEscapesBelowPlane() {
        var f = baselineFixture()
        // Annulus reads far ABOVE the plane — the plane escaped low through
        // a depth dropout (Req 3.3, Decision 22).
        f.annulus = (0..<20).map { i in
            SupportRegion.RingSample(index: 1000 + i, point: Vec3(Float(i), 100 + SupportRegion.escapeBandMm + 5, 0),
                                     distMm: 30, angle: 0)
        }
        XCTAssertFalse(SupportRegion.isAdmissible(candidate: f.candidate, ring: f.ring, plane: f.plane,
                                                  annulus: f.annulus, foodPoints: f.foodPoints, width: f.width))
    }

    func testRejectsBelowMinAcceptedExtentPx() {
        var f = baselineFixture()
        // A thin 3-px-tall sliver, even if wide — badly conditioned normal.
        var thin: [Int] = []
        for y in 50..<53 { for x in 50..<90 { thin.append(y * f.width + x) } }
        f.candidate = SupportPlaneCandidate(normal: f.candidate.normal, d: f.candidate.d, residualMm: f.candidate.residualMm,
                                            inlierIndices: thin, residueInlierRatio: f.candidate.residueInlierRatio)
        XCTAssertFalse(SupportRegion.isAdmissible(candidate: f.candidate, ring: f.ring, plane: f.plane,
                                                  annulus: f.annulus, foodPoints: f.foodPoints, width: f.width))
    }
}

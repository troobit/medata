#if HARNESS_ENABLED
import Foods
import Foundation
import PortableContracts
import SupportPlane
import Testing
@testable import HarnessCore

// Task 18: the fallback rate is aggregated across the fixture corpus and
// segmented by reference (Reqs 4.4, 4.5).
//
// Decision 11's decisive argument for this architecture is that a fallback which
// quietly becomes the normal path is detectable. That argument is unfalsifiable
// unless the rate is reported, which is why an unreported rate is a defect in its
// own right rather than a missing nicety.
@Suite("Fallback-rate aggregation (Reqs 4.4, 4.5)")
struct FallbackRateTests {

    @Test("the rate is the edge-band share of depth-derived attempts")
    func rateIsTheEdgeBandShareOfDepthDerivedAttempts() throws {
        let report = AccuracyHarness.evaluate(meals: [
            meal("a", reference: .foodSupport),
            meal("b", reference: .foodSupport),
            meal("c", reference: .foodSupport),
            meal("d", reference: .edgeBand),
        ])
        #expect(report.fallback.depthDerivedCount == 4)
        #expect(report.fallback.fallbackCount == 1)
        let rate = try #require(report.fallback.fallbackRate)
        #expect(abs(rate - 0.25) < 1e-6)
    }

    @Test("counts are segmented by reference, not collapsed into one figure")
    func countsAreSegmentedByReference() {
        let report = AccuracyHarness.evaluate(meals: [
            meal("a", reference: .foodSupport),
            meal("b", reference: .edgeBand),
            meal("c", reference: .edgeBand),
            meal("d", reference: .plateRegion),
        ])
        #expect(report.fallback.countsByReference == [
            "foodSupport": 1, "edgeBand": 2, "plateRegion": 1,
        ])
    }

    // A two-view meal derives no depth plane, so it is neither a success nor a
    // fallback. Counting it in the denominator would understate the rate by
    // exactly the share of the corpus this feature does not touch.
    @Test("attempts with no depth-derived reference stay out of the denominator")
    func attemptsWithoutAReferenceAreExcludedFromTheRate() throws {
        let report = AccuracyHarness.evaluate(meals: [
            meal("a", reference: .foodSupport),
            meal("b", reference: .edgeBand),
            meal("c", reference: nil),
            meal("d", reference: nil),
        ])
        #expect(report.fallback.unreportedCount == 2)
        #expect(report.fallback.depthDerivedCount == 2)
        let rate = try #require(report.fallback.fallbackRate)
        #expect(abs(rate - 0.5) < 1e-6)
    }

    // A rate over zero attempts is absent, not zero: reporting 0 % would read as
    // "the fallback never fired" on a run where the restricted fit never ran.
    @Test("a corpus with no depth-derived attempt reports no rate at all")
    func noDepthDerivedAttemptsMeansNoRate() {
        let report = AccuracyHarness.evaluate(meals: [meal("a", reference: nil)])
        #expect(report.fallback.fallbackRate == nil)
        #expect(report.fallback.depthDerivedCount == 0)
        #expect(report.fallback.unreportedCount == 1)
    }

    @Test("the rate is reported even when nothing carried ground truth")
    func rateSurvivesAnUnscoredRun() throws {
        // Device bundles record truth as zero, so a field replay scores nothing —
        // and that is precisely the run whose fallback rate matters most.
        let report = AccuracyHarness.evaluate(meals: [
            meal("a", reference: .edgeBand, truth: 0),
            meal("b", reference: .foodSupport, truth: 0),
        ])
        #expect(report.scoredCount == 0)
        let rate = try #require(report.fallback.fallbackRate)
        #expect(abs(rate - 0.5) < 1e-6)
    }

    private func meal(_ id: String, reference: SupportPlaneReference?,
                      truth: Float = 100) -> MealEvalInput {
        MealEvalInput(
            fixtureID: id, capturePath: .singleViewLidar,
            predictedCarbsPerClass: ["white_rice": truth],
            statusPerClass: ["white_rice": .uncalibratedUnity],
            groundTruthTotalCarbsG: truth,
            supportPlaneReference: reference)
    }
}
#endif

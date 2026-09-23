import Foundation
import Testing

@testable import Dosing

// The one canonical direction (specs/data/insulin-dosing Req 1.5, 1.6,
// Decision 3). The reciprocal is a display derivation and is asserted here
// only to pin that 5.0 g/U is the developer's "2 U per 10 g".
@Suite("CarbRatio")
struct CarbRatioTests {

    // MARK: - The permitted interval (Req 1.5)

    @Test("A ratio just below the interval is rejected")
    func rejectsBelowInterval() {
        #expect(CarbRatio(gramsPerUnit: 0.9) == nil)
    }

    @Test("A ratio just above the interval is rejected")
    func rejectsAboveInterval() {
        #expect(CarbRatio(gramsPerUnit: 60.1) == nil)
    }

    @Test("A non-finite ratio is rejected")
    func rejectsNonFinite() {
        #expect(CarbRatio(gramsPerUnit: .nan) == nil)
        #expect(CarbRatio(gramsPerUnit: .infinity) == nil)
        #expect(CarbRatio(gramsPerUnit: -.infinity) == nil)
    }

    @Test("Both endpoints are accepted — the interval is closed")
    func acceptsBothEndpoints() {
        #expect(CarbRatio(gramsPerUnit: 1.0)?.gramsPerUnit == 1.0)
        #expect(CarbRatio(gramsPerUnit: 60.0)?.gramsPerUnit == 60.0)
    }

    // MARK: - The reciprocal is derived, never stored (Req 1.1, 1.2)

    @Test("5.0 g/U renders as 2.0 U per 10 g")
    func reciprocalOfBreakfastSeed() {
        let ratio = CarbRatio(gramsPerUnit: 5.0)!
        #expect(abs(ratio.unitsPerTenGrams - 2.0) < 1e-12)
    }

    @Test("10.0 g/U renders as 1.0 U per 10 g")
    func reciprocalOfLaterSeed() {
        let ratio = CarbRatio(gramsPerUnit: 10.0)!
        #expect(abs(ratio.unitsPerTenGrams - 1.0) < 1e-12)
    }

    // MARK: - Seeds and fallback (Req 1.4, 1.6)

    @Test("The shipped seeds reproduce 2 U per 10 g at breakfast and 1 U per 10 g otherwise")
    func seedsReproduceTheStatedRule() {
        let table = CarbRatioTable()
        #expect(table.ratio(for: .overnight).value.gramsPerUnit == 10.0)
        #expect(table.ratio(for: .breakfast).value.gramsPerUnit == 5.0)
        #expect(table.ratio(for: .lunch).value.gramsPerUnit == 10.0)
        #expect(table.ratio(for: .dinner).value.gramsPerUnit == 10.0)
    }

    @Test("An unconfigured band falls back to its seed and reports isSeed")
    func unconfiguredBandFallsBackAndReports() {
        let table = CarbRatioTable(configured: [.breakfast: CarbRatio(gramsPerUnit: 6.0)!])

        let breakfast = table.ratio(for: .breakfast)
        #expect(breakfast.value.gramsPerUnit == 6.0)
        #expect(breakfast.isSeed == false)

        let dinner = table.ratio(for: .dinner)
        #expect(dinner.value.gramsPerUnit == 10.0)
        #expect(dinner.isSeed == true)
    }

    @Test("Every band has a seed, so the fallback is total")
    func everyBandHasASeed() {
        for band in DoseBand.allCases {
            #expect(CarbRatioTable.seed[band] != nil)
        }
    }
}

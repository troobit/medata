import XCTest
@testable import Foods

// The combined relabel-shortlist ordering
// (estimation/alternative-class-candidates Req 7, Decision 7 as amended).
// The properties that matter are relational: recency is never displaced, and
// with no evidence the ordering must reproduce the list `ui/meal-review`
// shipped — so the shipped loop is reimplemented here as the reference.
final class ShortlistOrderingTests: XCTestCase {

    private let limit = 5

    // The shipped `MealReviewModel.buildShortlist` body (App/MealReviewModel.swift),
    // over ids: recency already filtered to eligible, then the blind top-up.
    private func shipped(recency: [String], eligible: [String], limit: Int) -> [String] {
        var out = recency
        for candidate in eligible where out.count < limit {
            if !out.contains(candidate) { out.append(candidate) }
        }
        return Array(out.prefix(limit))
    }

    // MARK: - source names (Req 7.6)

    func testSourceNamesAreDistinctAndStable() {
        XCTAssertEqual(ShortlistOrdering.recencySource, "recency")
        XCTAssertEqual(ShortlistOrdering.combinedSource, "recency_plus_candidates")
        XCTAssertNotEqual(ShortlistOrdering.recencySource, ShortlistOrdering.combinedSource)
    }

    // MARK: - layer order

    func testEvidenceFillsBetweenRecencyAndTopUp() {
        let out = ShortlistOrdering.combined(
            recency: ["bread"],
            candidates: ["pasta", "potato_boiled"],
            topUp: ["apple", "banana", "carrot"],
            limit: limit
        )
        XCTAssertEqual(out, ["bread", "pasta", "potato_boiled", "apple", "banana"])
    }

    func testEvidenceDisplacesOnlyTopUpEntries() {
        let recency = ["bread", "rice"]
        let topUp = ["apple", "banana", "carrot", "date", "egg"]
        let without = ShortlistOrdering.combined(
            recency: recency, candidates: [], topUp: topUp, limit: limit
        )
        let with = ShortlistOrdering.combined(
            recency: recency, candidates: ["pasta"], topUp: topUp, limit: limit
        )
        // The recency prefix is untouched; the loss falls on the last top-up entry.
        XCTAssertEqual(Array(with.prefix(2)), recency)
        XCTAssertEqual(with, ["bread", "rice", "pasta", "apple", "banana"])
        XCTAssertEqual(without, ["bread", "rice", "apple", "banana", "carrot"])
    }

    func testEvidenceReachesAFoodNeverChosen() {
        // Req 7.3: a class absent from both recency and the top-up prefix is
        // still offered when the evidence supports it.
        let out = ShortlistOrdering.combined(
            recency: [],
            candidates: ["pasta"],
            topUp: ["apple", "banana", "carrot", "date", "egg", "pasta"],
            limit: limit
        )
        XCTAssertEqual(out.first, "pasta")
        XCTAssertFalse(shipped(recency: [], eligible: ["apple", "banana", "carrot", "date", "egg", "pasta"], limit: limit)
            .contains("pasta"))
    }

    // MARK: - degeneracy (Req 7.4)

    func testEmptyCandidatesMatchesTheShippedList() {
        let recency = ["bread", "rice"]
        let eligible = ["apple", "banana", "bread", "carrot", "date", "egg"]
        XCTAssertEqual(
            ShortlistOrdering.combined(
                recency: recency, candidates: [], topUp: eligible, limit: limit
            ),
            shipped(recency: recency, eligible: eligible, limit: limit)
        )
    }

    func testEmptyCandidatesMatchesTheShippedListOverRandomisedInputs() {
        // Seeded, no new dependency: an LCG over a small id universe.
        var seed: UInt64 = 0x5EED
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let universe = (0..<12).map { "class_\($0)" }
        for _ in 0..<200 {
            let eligible = universe.filter { _ in next(2) == 0 }
            let recency = eligible.filter { _ in next(3) == 0 }
            XCTAssertEqual(
                ShortlistOrdering.combined(
                    recency: recency, candidates: [], topUp: eligible, limit: limit
                ),
                shipped(recency: recency, eligible: eligible, limit: limit)
            )
        }
    }

    func testRecencyPositionsAreInvariantUnderAnyCandidateInput() {
        var seed: UInt64 = 0xC0FFEE
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        let universe = (0..<12).map { "class_\($0)" }
        let recency = ["bread", "rice"]
        let topUp = recency + universe
        let baseline = ShortlistOrdering.combined(
            recency: recency, candidates: [], topUp: topUp, limit: limit
        )
        for _ in 0..<200 {
            let candidates = universe.filter { _ in next(3) == 0 }
            let out = ShortlistOrdering.combined(
                recency: recency, candidates: candidates, topUp: topUp, limit: limit
            )
            XCTAssertEqual(Array(out.prefix(recency.count)), Array(baseline.prefix(recency.count)))
        }
    }

    // MARK: - limit and duplicates

    func testLimitBoundsEveryLayer() {
        let out = ShortlistOrdering.combined(
            recency: ["a", "b", "c", "d", "e", "f", "g"],
            candidates: ["h"],
            topUp: ["i", "j"],
            limit: limit
        )
        XCTAssertEqual(out, ["a", "b", "c", "d", "e"])
        XCTAssertTrue(ShortlistOrdering.combined(
            recency: ["a"], candidates: ["b"], topUp: ["c"], limit: 0
        ).isEmpty)
    }

    func testDuplicatesKeepTheirEarliestPosition() {
        let out = ShortlistOrdering.combined(
            recency: ["bread", "bread", "rice"],
            candidates: ["rice", "pasta"],
            topUp: ["pasta", "apple", "banana"],
            limit: limit
        )
        XCTAssertEqual(out, ["bread", "rice", "pasta", "apple", "banana"])
        XCTAssertEqual(Set(out).count, out.count)
    }

    func testDeterminism() {
        let inputs = (recency: ["bread"], candidates: ["pasta", "rice"], topUp: ["apple", "banana"])
        let first = ShortlistOrdering.combined(
            recency: inputs.recency, candidates: inputs.candidates,
            topUp: inputs.topUp, limit: limit
        )
        let second = ShortlistOrdering.combined(
            recency: inputs.recency, candidates: inputs.candidates,
            topUp: inputs.topUp, limit: limit
        )
        XCTAssertEqual(first, second)
    }
}

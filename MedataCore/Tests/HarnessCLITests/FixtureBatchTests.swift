#if HARNESS_ENABLED
import Foods
import Foundation
import PortableContracts
import Segmentation
import Testing
@testable import HarnessCore

// Regression tests for calibrate-silently-drops-unreadable-fixtures
// (specs/bugfixes/): `buildCalInputs` in HarnessCLI/main.swift converted
// every FixtureRunner throw to `nil` via `try?` + `compactMap`, so a
// fixture the pipeline could not process vanished from the accuracy run
// with no message and no count. FixtureBatch.partition is the repaired
// seam: failures travel in the return value beside the successes, so a
// call site cannot structurally lose them.
@Suite("FixtureBatch partition")
struct FixtureBatchTests {

    func makeFixture(id: String) -> PbMealFixture {
        var fx = PbMealFixture()
        fx.fixtureID = id
        return fx
    }

    struct StubError: Error, CustomStringConvertible {
        let description: String
    }

    @Test("Successes and failures are partitioned; neither is lost")
    func mixedBatchPartitions() {
        let fixtures = [makeFixture(id: "good"), makeFixture(id: "bad")]
        let (results, skips) = FixtureBatch.partition(fixtures: fixtures) { fx in
            if fx.fixtureID == "bad" { throw StubError(description: "broken tensor") }
            return fx.fixtureID
        }
        #expect(results == ["good"])
        #expect(skips.map(\.fixtureID) == ["bad"])
    }

    @Test("The skip carries the thrown error's description, not a generic label")
    func skipReasonIsTheError() {
        let (_, skips) = FixtureBatch.partition(
            fixtures: [makeFixture(id: "f1")]
        ) { _ -> Never in
            throw StubError(description: "probs size 0, expected 921600")
        }
        #expect(skips.count == 1)
        #expect(skips[0].reason.contains("probs size 0, expected 921600"))
    }

    @Test("An all-failed batch yields zero results and every skip, in input order")
    func allFailedBatchKeepsEverySkip() {
        let fixtures = ["f1", "f2", "f3"].map(makeFixture)
        let (results, skips) = FixtureBatch.partition(fixtures: fixtures) { fx -> Never in
            throw StubError(description: "fails: \(fx.fixtureID)")
        }
        #expect(results.isEmpty)
        #expect(skips.map(\.fixtureID) == ["f1", "f2", "f3"])
        #expect(skips.map(\.reason) == ["fails: f1", "fails: f2", "fails: f3"])
    }

    @Test("A real FixtureRunner failure surfaces its case and fixture id in the skip")
    func realRunnerErrorIsCarried() throws {
        // An empty capture path is the cheapest real pipeline failure:
        // FixtureRunner.run throws invalidCapturePath before touching any
        // tensor or database. Before the fix this fixture silently
        // vanished from the accuracy inputs.
        var fx = PbMealFixture()
        fx.fixtureID = "device_bundle_007"
        fx.capturePathCanonical = ""
        let db = StubFoodDatabase()
        let (results, skips) = FixtureBatch.partition(fixtures: [fx]) { fx in
            try FixtureRunner.run(fixture: fx, palette: .standard,
                                  database: db, voxelEdgeMm: 3.0)
        }
        #expect(results.isEmpty)
        #expect(skips.count == 1)
        #expect(skips[0].fixtureID == "device_bundle_007")
        #expect(skips[0].reason.contains("invalidCapturePath"))
    }
}

// Minimal FoodDatabase stub — the invalidCapturePath throw fires before
// any database access, so nothing here is ever called.
private struct StubFoodDatabase: FoodDatabase {
    var version: String { "batch-test-stub" }
    func entry(for classId: String) -> FoodEntry? { nil }
    func entry(for classId: String, edition: String) -> FoodEntry? { nil }
    func availableEditions() -> [String] { [] }
    func solidServing(for classId: String) -> SolidServing? { nil }
}
#endif

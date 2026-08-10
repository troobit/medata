#if HARNESS_ENABLED
import Foundation
import PortableContracts

// Batch driver for per-fixture pipeline runs (accuracy path).
//
// The harness is a batch tool over operator-supplied files: one fixture the
// pipeline cannot process must not abort the whole run, but it must not
// vanish either (calibrate-silently-drops-unreadable-fixtures — the old
// `try?` + `compactMap` at the accuracy call site dropped failures with no
// message, so the report was computed over an unstated subset). Failures
// travel in the return value beside the successes, so a call site cannot
// structurally lose them; what it does with them (stderr, exit code) is its
// own decision.
public enum FixtureBatch {

    public struct Skip: Equatable, Sendable {
        public let fixtureID: String
        public let reason: String

        public init(fixtureID: String, reason: String) {
            self.fixtureID = fixtureID
            self.reason = reason
        }
    }

    public static func partition<T>(
        fixtures: [PbMealFixture],
        run: (PbMealFixture) throws -> T
    ) -> (results: [T], skips: [Skip]) {
        var results: [T] = []
        var skips: [Skip] = []
        for fx in fixtures {
            do {
                results.append(try run(fx))
            } catch {
                skips.append(Skip(fixtureID: fx.fixtureID,
                                  reason: String(describing: error)))
            }
        }
        return (results, skips)
    }
}
#endif

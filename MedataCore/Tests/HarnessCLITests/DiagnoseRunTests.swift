#if HARNESS_ENABLED
import Foundation
import PortableContracts
import SupportPlane
import Testing
@testable import HarnessCore

// Tests for the `HarnessCLI diagnose` subcommand's core
// (specs/estimation/ml-feedback-loop Reqs 4.1/4.2/4.3, design "Deterministic
// diagnosis"). `accuracy` computes the MealCalibrationInput and throws all but
// the carb total away; `diagnose` emits it, so the Mac-side loop can attribute a
// gap to a class, a volume, or a plane rather than guessing from one number.
//
// The replay itself is injected, exactly as FixtureBatch.partition injects it:
// what is under test here is the per-fixture record, the replay-status
// vocabulary and the version-skew stamp — not the pipeline, which has its own
// suites.
@Suite("Diagnose run")
struct DiagnoseRunTests {

    let replaySHA = "cafe1234"
    let replayDBSHA = "db99"
    let replayEdition = "CoFID 2021 + AFCD 2019"

    func makeFixture(
        id: String,
        checkpointSHA: String = "cafe1234",
        edition: String = "CoFID 2021 + AFCD 2019",
        capturePath: String = "single_view_lidar",
        groundTruthCarbsG: Float = 0
    ) -> PbMealFixture {
        var fx = PbMealFixture()
        fx.fixtureID = id
        fx.estimatorPath = "single_dominant"
        fx.segmenterCheckpointSha256 = checkpointSHA
        fx.databaseEdition = edition
        fx.capturePathCanonical = capturePath
        fx.groundTruthTotalCarbsG = groundTruthCarbsG
        return fx
    }

    func makeInput(
        _ id: String,
        predicted: [String: Float] = ["toast": 41.3],
        volumes: [String: Float] = ["toast": 152.0],
        residualMm: Float? = 1.8,
        reference: SupportPlaneReference? = .foodSupport
    ) -> MealCalibrationInput {
        MealCalibrationInput(
            fixtureID: id, capturePath: .singleViewLidar,
            dominantClass: volumes.max(by: { $0.value < $1.value })?.key,
            predictedCarbsPerClass: predicted,
            actualCarbsPerClass: [:],
            groundTruthTotalCarbsG: 0,
            perClassVolumesCm3: volumes,
            supportPlaneResidualMm: residualMm,
            supportPlaneReference: reference)
    }

    func report(
        fixtures: [PbMealFixture],
        run: @escaping (PbMealFixture) throws -> MealCalibrationInput
    ) -> DiagnoseRun.Report {
        DiagnoseRun.diagnose(
            fixtures: fixtures,
            replayCheckpointSHA256: replaySHA,
            replayDatabaseSHA256: replayDBSHA,
            replayDatabaseEdition: replayEdition,
            run: run)
    }

    // MARK: - The record the accuracy path discards (Req 4.1)

    @Test("A replayed fixture carries per-class carbs, volumes, dominant class, plane and totals")
    func replayedFixtureCarriesTheCalibrationInput() {
        let fx = makeFixture(id: "1785135663727-success", groundTruthCarbsG: 30)
        let out = report(fixtures: [fx]) { _ in
            self.makeInput("1785135663727-success",
                           predicted: ["toast": 41.3, "butter": 0.1],
                           volumes: ["toast": 152.0, "butter": 4.0])
        }

        #expect(out.fixtures.count == 1)
        let d = out.fixtures[0]
        #expect(d.replayStatus == .replayed)
        #expect(d.predictedCarbsPerClass == ["toast": 41.3, "butter": 0.1])
        #expect(d.perClassVolumesCm3 == ["toast": 152.0, "butter": 4.0])
        #expect(d.dominantClass == "toast")
        #expect(d.supportPlaneReference == "foodSupport")
        #expect(d.supportPlaneResidualMm == 1.8)
        #expect(abs(d.predictedTotalCarbsG - 41.4) < 1e-4,
                "the total is the sum of the per-class carbs, not a separate figure")
        #expect(d.groundTruthTotalCarbsG == 30)
        #expect(d.replayFailureReason == nil)
    }

    @Test("A two-view replay records an absent plane reference as absent, not as a default")
    func twoViewCarriesNoPlaneReference() {
        let fx = makeFixture(id: "two-view", capturePath: "two_view_sfs")
        let out = report(fixtures: [fx]) { _ in
            self.makeInput("two-view", residualMm: nil, reference: nil)
        }
        #expect(out.fixtures[0].supportPlaneReference == nil)
        #expect(out.fixtures[0].supportPlaneResidualMm == nil)
        #expect(out.fixtures[0].capturePathCanonical == "two_view_sfs",
                "capture mode is carried verbatim — Req 6.6 segments every metric by it")
    }

    // MARK: - Replay status vocabulary (Req 4.2)

    @Test("A fixture the pipeline cannot replay is not_replayable with its reason, never dropped")
    func notReplayableIsRecordedWithReason() {
        let fx = makeFixture(id: "no-depth")
        let out = report(fixtures: [fx]) { _ in
            throw FixtureRunner.Error.missingDepthForSingleView("no-depth")
        }

        #expect(out.fixtures.count == 1, "a failed replay is a row, not a silence")
        #expect(out.fixtures[0].replayStatus == .notReplayable)
        #expect(out.fixtures[0].replayFailureReason?.isEmpty == false)
        #expect(out.notReplayableCount == 1)
        #expect(out.replayedCount == 0)
    }

    @Test("A replay that prices no food is replay_zero_meals, distinct from a failure")
    func zeroMealsIsItsOwnStatus() {
        // Volume came out but no class resolved in the food DB: the pipeline
        // did not fail, and there is still no meal to compare a note against.
        let fx = makeFixture(id: "unpriced")
        let out = report(fixtures: [fx]) { _ in
            self.makeInput("unpriced", predicted: [:], volumes: ["mystery": 80])
        }

        #expect(out.fixtures[0].replayStatus == .replayZeroMeals)
        #expect(out.fixtures[0].perClassVolumesCm3 == ["mystery": 80],
                "the volumes survive — they are the evidence for the zero")
        #expect(out.zeroMealCount == 1)
        #expect(out.notReplayableCount == 0)
    }

    @Test("Counts and order cover every fixture exactly once")
    func everyFixtureAppearsOnce() {
        let fixtures = [makeFixture(id: "a"), makeFixture(id: "b"), makeFixture(id: "c")]
        let out = report(fixtures: fixtures) { fx in
            if fx.fixtureID == "b" { throw FixtureRunner.Error.invalidCapturePath("") }
            return self.makeInput(fx.fixtureID)
        }
        #expect(out.fixtures.map(\.fixtureID) == ["a", "b", "c"])
        #expect(out.replayedCount == 2)
        #expect(out.notReplayableCount == 1)
    }

    // MARK: - Version-skew stamping (Req 4.3)

    @Test("Matching checkpoint and edition leave the diagnosis skew-free")
    func noSkewWhenArtifactsMatch() {
        let out = report(fixtures: [makeFixture(id: "same")]) { _ in self.makeInput("same") }
        #expect(out.fixtures[0].replayVersionSkew == false)
        #expect(out.versionSkewCount == 0)
    }

    @Test("A checkpoint the replaying binary does not hold stamps replay_version_skew")
    func skewOnCheckpointMismatch() {
        let fx = makeFixture(id: "old-model", checkpointSHA: "beef0000")
        let out = report(fixtures: [fx]) { _ in self.makeInput("old-model") }
        #expect(out.fixtures[0].replayVersionSkew == true)
        #expect(out.fixtures[0].recordedModelVersion == "beef0000")
        #expect(out.versionSkewCount == 1)
    }

    @Test("A food-DB edition the replaying binary does not carry also stamps skew")
    func skewOnDatabaseEditionMismatch() {
        // The DB is half the estimate: a carb value can move without the
        // segmenter moving at all, so an edition mismatch is skew too.
        let fx = makeFixture(id: "old-db", edition: "CoFID 2019 + AFCD 2019")
        let out = report(fixtures: [fx]) { _ in self.makeInput("old-db") }
        #expect(out.fixtures[0].replayVersionSkew == true)
        #expect(out.fixtures[0].recordedDatabaseEdition == "CoFID 2019 + AFCD 2019")
    }

    @Test("A fixture that failed to replay is still stamped for skew")
    func skewIsIndependentOfReplaySuccess() {
        // The Mac side excludes skewed pairs from the 4.3 attribution floor; a
        // non-replayed fixture that is ALSO skewed must not read as skew-free.
        let fx = makeFixture(id: "old-and-broken", checkpointSHA: "beef0000")
        let out = report(fixtures: [fx]) { _ in
            throw FixtureRunner.Error.invalidCapturePath("")
        }
        #expect(out.fixtures[0].replayStatus == .notReplayable)
        #expect(out.fixtures[0].replayVersionSkew == true)
    }

    // MARK: - Replaying-artifact identity (Req 4.3)

    @Test("The report names the artifacts the replay actually ran against")
    func reportRecordsReplayingArtifacts() {
        let out = report(fixtures: [makeFixture(id: "a")]) { _ in self.makeInput("a") }
        #expect(out.replayCheckpointSha256 == replaySHA)
        #expect(out.replayDatabaseSha256 == replayDBSHA)
        #expect(out.replayDatabaseEdition == replayEdition)
    }

    @Test("The database hash is content-addressed over both artifacts, in order")
    func databaseHashIsContentAddressed() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("diagnose-hash-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let cofid = dir.appendingPathComponent("cofid_db.sqlite")
        let afcd = dir.appendingPathComponent("afcd_db.sqlite")
        try Data("cofid".utf8).write(to: cofid)
        try Data("afcd".utf8).write(to: afcd)

        let hash = try DiagnoseRun.contentSHA256(of: [cofid, afcd])
        #expect(hash.count == 64, "hex-encoded SHA-256")
        #expect(try DiagnoseRun.contentSHA256(of: [cofid, afcd]) == hash, "deterministic")
        #expect(try DiagnoseRun.contentSHA256(of: [afcd, cofid]) != hash,
                "the pair is hashed as an ordered whole, so a swap is a different DB")

        try Data("cofid-2".utf8).write(to: cofid)
        #expect(try DiagnoseRun.contentSHA256(of: [cofid, afcd]) != hash,
                "a changed artifact changes the hash")
    }

    // MARK: - Wire shape

    @Test("The JSON is snake_case with the Req 4.2 status vocabulary as written")
    func jsonShapeIsSnakeCase() throws {
        let out = report(fixtures: [makeFixture(id: "a")]) { _ in
            self.makeInput("a", predicted: [:], volumes: [:],
                           residualMm: nil, reference: nil)
        }
        let json = String(decoding: try DiagnoseRun.encoder().encode(out), as: UTF8.self)
        for key in ["replay_checkpoint_sha256", "replay_database_sha256",
                    "replay_version_skew", "predicted_carbs_per_class",
                    "per_class_volumes_cm3", "dominant_class",
                    "support_plane_reference", "support_plane_residual_mm",
                    "predicted_total_carbs_g", "replay_status"] {
            #expect(json.contains("\"\(key)\""), "missing key \(key)")
        }
        #expect(json.contains("\"replay_zero_meals\""),
                "the status vocabulary is emitted verbatim, not camel-cased")
        #expect(json.contains("\"dominant_class\" : null"),
                "an absent value is null, never a missing key the reader would default")
        #expect(json.contains("\"support_plane_reference\" : null"))
    }
}
#endif

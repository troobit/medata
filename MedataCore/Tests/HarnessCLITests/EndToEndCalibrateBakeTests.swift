#if HARNESS_ENABLED
import Foods
import Foundation
import PortableContracts
import Testing
@testable import HarnessCore

// End-to-end calibrate-to-bake integration (cross-dataset-calibration task 23,
// Req 7.2): a synthetic MetaFood3D fixture set → the real `HarnessCLI
// calibrate` binary → calibrate.json → `tools/food_db/generate.py` bake.
//
// This is the one place the full stream 1 → stream 2 → stream C chain runs in
// a test: fixture files on disk, the CLI's argument wiring and ingest-summary
// contract, the artifact JSON as `generate.py` actually receives it, and the
// baked SQLite meta/rows. It pins that the new per-class provenance fields
// persist into the shipped DB shape (Req 6.1) and that the palette↔DB edition
// lock still gates the calibrated path (the bake exiting 0 IS the lock
// holding — a drifted palette aborts with nothing written).
//
// The fixture set mirrors `tools/metafood3d/ingest.py` output (Decision 11):
// single-class mixture rows, sentinel SHA, no probability tensor, authored
// support plane riding the run summary's render_config. 34 white_rice objects
// at masses consistent with β = 0.8 clear the effective-sample gate; 3
// broccoli objects stay under it and keep unity (Req 8.1).
@Suite("End-to-end calibrate-to-bake (Req 7.2)", .serialized)
struct EndToEndCalibrateBakeTests {

    static let snapshot = "abc123def456"
    static let riceCount = 34
    static let broccoliCount = 3
    static let trueBeta: Float = 0.8

    // repo root from this file's location:
    // <root>/MedataCore/Tests/HarnessCLITests/EndToEndCalibrateBakeTests.swift
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    // The HarnessCLI binary `swift test` built alongside this test module.
    // The swift-testing runner is a toolchain helper executable (not an
    // .xctest-hosted process), so neither Bundle.main nor Bundle.allBundles
    // reaches the products directory. The test module's own loaded image
    // (via dladdr on #dsohandle) sits inside it — walk up from there to the
    // directory containing HarnessCLI.
    static var harnessCLI: URL? {
        var info = Dl_info()
        guard dladdr(UnsafeRawPointer(#dsohandle), &info) != 0,
              let imagePath = info.dli_fname else { return nil }
        var dir = URL(fileURLWithPath: String(cString: imagePath))
            .deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = dir.appendingPathComponent("HarnessCLI")
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    struct ProcessResult {
        let status: Int32
        let output: String
        let errorText: String
    }

    // Run a subprocess, draining both pipes BEFORE waiting so a full pipe
    // buffer cannot deadlock the child.
    private func run(_ executable: String, _ arguments: [String],
                     cwd: URL? = nil) throws -> ProcessResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        if let cwd { p.currentDirectoryURL = cwd }
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return ProcessResult(
            status: p.terminationStatus,
            output: String(data: outData, encoding: .utf8) ?? "",
            errorText: String(data: errData, encoding: .utf8) ?? "")
    }

    // The ingest.py-shaped fixture: estimator_path mixture, sentinel SHA, no
    // probability tensor, single-entry GT-mass map, source_dataset stamp.
    private func fixture(scene: InjectedPlaneTests, id: String,
                         className: String, massG: Float) -> PbMealFixture {
        var fx = scene.makeFixture(id: id, massG: massG)
        fx.groundTruthClassMassG = [className: massG]
        fx.sourceDataset = "metafood3d@\(Self.snapshot)"
        fx.paletteVersion = "v2"
        return fx
    }

    // The tools/metafood3d/ingest.py run_summary.json contract the CLI
    // consumes (docs/agent-notes/n5k-calibration-harness.md).
    private var runSummaryJSON: String {
        """
        {
          "dataset": "metafood3d",
          "snapshot": "\(Self.snapshot)",
          "mapping_version": "sha256:e2e-mapping",
          "licence": "CC BY-NC 4.0",
          "skipped": {},
          "mixture_fit_excluded_unmapped": [],
          "liquid_excluded": [],
          "render_config": {
            "plane_depth_mm": \(InjectedPlaneTests.planeMm),
            "intrinsics_model": "realsense_d435_factory",
            "image_width": 100,
            "image_height": 100,
            "seating_rule": "stable_pose_base_on_plane",
            "noise": "noise_free_render"
          }
        }
        """
    }

    private func dumpDatabase(python: String, db: URL) throws -> [String: Any] {
        let script = """
        import json, sqlite3, sys
        conn = sqlite3.connect(sys.argv[1])
        meta = dict(conn.execute("SELECT k, v FROM meta"))
        foods = {r[0]: {"beta": r[1], "status": r[2], "provenance": r[3]}
                 for r in conn.execute(
                     "SELECT class_id, beta, beta_status, beta_provenance "
                     "FROM foods WHERE class_id IN ('white_rice', 'broccoli')")}
        print(json.dumps({"meta": meta, "foods": foods}))
        """
        let result = try run(python, ["python3", "-c", script, db.path])
        try #require(result.status == 0, "DB dump failed: \(result.errorText)")
        let data = Data(result.output.utf8)
        return try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test("Synthetic MetaFood3D fixtures → HarnessCLI calibrate → generate.py bake")
    func fullPipelinePersistsCrossDatasetProvenance() throws {
        let harnessCLI = try #require(
            Self.harnessCLI,
            "HarnessCLI not built into the products directory near \(Bundle.main.executableURL?.path ?? "?")")
        // PATH-resolved python3 via env: the Apple system python (3.9)
        // cannot evaluate generate.py's `str | None` annotations; the repo's
        // tooling runs on a current python3 from PATH.
        let python = "/usr/bin/env"

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("e2e-calibrate-bake-\(UUID().uuidString)")
        let fixturesDir = workDir.appendingPathComponent("fixtures")
        try FileManager.default.createDirectory(
            at: fixturesDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        // --- Stage 1: the synthetic MetaFood3D fixture set ------------------
        // Masses are derived from the estimator's own volume through the
        // injected authored plane, so the CLI's fit must land on β = 0.8.
        let scene = InjectedPlaneTests()
        let plane = CalibrateRun.authoredSupportPlane(
            gravity: scene.gravity, planeDepthMm: InjectedPlaneTests.planeMm)
        let vEst = try CalibrateRun.mixtureObservation(
            fixture: scene.makeFixture(id: "probe", massG: 1),
            injectedSupportPlane: plane).totalHullVolumeCm3

        let db = try GRDBFoodDatabase.bundled()
        let rhoRice = try #require(db.entry(for: "white_rice")?.densityGPerCm3)
        let rhoBroccoli = try #require(db.entry(for: "broccoli")?.densityGPerCm3)

        for i in 0..<Self.riceCount {
            let fx = fixture(scene: scene, id: String(format: "mf3d_rice_%02d", i),
                             className: "white_rice",
                             massG: Self.trueBeta * vEst * rhoRice)
            try fx.serializedData().write(
                to: fixturesDir.appendingPathComponent("\(fx.fixtureID).fixture"))
        }
        for i in 0..<Self.broccoliCount {
            let fx = fixture(scene: scene, id: String(format: "mf3d_broc_%02d", i),
                             className: "broccoli",
                             massG: Self.trueBeta * vEst * rhoBroccoli)
            try fx.serializedData().write(
                to: fixturesDir.appendingPathComponent("\(fx.fixtureID).fixture"))
        }
        let summaryURL = workDir.appendingPathComponent("run_summary.json")
        try Data(runSummaryJSON.utf8).write(to: summaryURL)

        // --- Stage 2: the real HarnessCLI calibrate binary ------------------
        let artifactURL = workDir.appendingPathComponent("calibrate.json")
        let calibrateResult = try run(harnessCLI.path, [
            "calibrate",
            "--fixtures-dir", fixturesDir.path,
            "--ingest-summary", summaryURL.path,
            "--output", artifactURL.path,
            "--seed", "42",
            "--mapping-version", "sha256:e2e-mapping",
        ])
        let calibrateFailure = Comment(
            rawValue: "HarnessCLI calibrate failed: " + calibrateResult.errorText)
        try #require(calibrateResult.status == 0, calibrateFailure)

        // --- Stage 3: the artifact carries the new per-class fields ---------
        let artifact = try JSONDecoder().decode(
            CalibrationArtifact.self, from: Data(contentsOf: artifactURL))
        #expect(artifact.supportPlaneReference == "foodSupport")

        let rice = try #require(artifact.classes["white_rice"])
        #expect(rice.status == "calibrated")
        #expect(rice.provenance == "n5k_mixture")
        #expect(abs(rice.beta - Self.trueBeta) <= 0.02,
                "β \(rice.beta) should recover the designed \(Self.trueBeta)")
        #expect(rice.effectiveSample == Self.riceCount)
        #expect(rice.contributingDatasets == ["metafood3d": Self.riceCount])
        #expect(rice.singleSourceUncorroborated,
                "a single-dataset β must carry the Req 6.2 flag")
        #expect(rice.supportPlaneReference == "foodSupport",
                "an MF3D-only mixture β rides the authored plane (Decision 16)")

        let broccoli = try #require(artifact.classes["broccoli"])
        #expect(broccoli.status == "uncalibrated_unity",
                "\(Self.broccoliCount) samples stay under the gate (Req 8.1)")
        #expect(broccoli.contributingDatasets
                == ["metafood3d": Self.broccoliCount])

        let lineage = try #require(artifact.lineage)
        #expect(lineage.renderConfig?.planeDepthMm == InjectedPlaneTests.planeMm)
        #expect(lineage.perDataset["metafood3d"]?.snapshot == Self.snapshot)

        // --- Stage 4: generate.py bake ---------------------------------------
        // cwd = workDir, so the relative OUTPUT_DIR lands the baked DBs in the
        // temp tree while the palette lock still reads the real
        // ClassPalette.swift via its absolute repo-root anchor. Exit 0 is the
        // lock (and the Req 5.3 density spot-check) holding.
        let generatePy = Self.repoRoot
            .appendingPathComponent("tools/food_db/generate.py")
        let bakeResult = try run(python, [
            "python3", generatePy.path, "--calibration-json", artifactURL.path,
        ], cwd: workDir)
        let bakeFailure = Comment(
            rawValue: "generate.py bake failed: " + bakeResult.errorText)
        try #require(bakeResult.status == 0, bakeFailure)

        // --- Stage 5: provenance persisted into both shipped DB shapes ------
        let resources = workDir
            .appendingPathComponent("MedataCore/Sources/Foods/Resources")
        for dbName in ["cofid_db.sqlite", "afcd_db.sqlite"] {
            let dump = try dumpDatabase(
                python: python, db: resources.appendingPathComponent(dbName))
            let meta = try #require(dump["meta"] as? [String: Any])

            #expect(meta["palette_version"] as? String == "v2",
                    "\(dbName): palette↔DB edition lock (Req 7.2)")

            let contributing = try #require(
                meta["calibration_contributing_datasets_per_class"] as? String)
            let contributingDict = try #require(
                try JSONSerialization.jsonObject(
                    with: Data(contributing.utf8)) as? [String: [String: Int]])
            #expect(contributingDict == [
                "white_rice": ["metafood3d": Self.riceCount],
                "broccoli": ["metafood3d": Self.broccoliCount],
            ], "\(dbName): Req 6.1 — every baked β's data source persists")

            let singleSource = try #require(
                meta["calibration_single_source_classes"] as? String)
            #expect(try JSONSerialization.jsonObject(
                        with: Data(singleSource.utf8)) as? [String]
                    == ["white_rice"], "\(dbName): Req 6.2 flag persists")

            #expect(meta["calibration_reference_skipped_classes"] as? String
                    == "[]", "\(dbName): nothing reference-skipped in this run")
        }

        // Row-level check on the primary DB: the flagged single-source staple
        // BAKES on the statistical gates (Req 8.3); the under-sampled class
        // keeps unity (Req 8.1).
        let cofid = try dumpDatabase(
            python: python, db: resources.appendingPathComponent("cofid_db.sqlite"))
        let foods = try #require(cofid["foods"] as? [String: [String: Any]])
        let riceRow = try #require(foods["white_rice"])
        #expect(abs((riceRow["beta"] as? Double ?? 0) - Double(Self.trueBeta))
                <= 0.02)
        #expect(riceRow["status"] as? String == "calibrated")
        #expect(riceRow["provenance"] as? String == "n5k_mixture")
        let broccoliRow = try #require(foods["broccoli"])
        #expect(broccoliRow["beta"] as? Double == 1.0)
        #expect(broccoliRow["status"] as? String == "uncalibrated_unity")
    }
}
#endif

import Foundation
import GRDB
import PortableContracts
import XCTest
@testable import Persistence

// Correction-record store tests per specs/ui/meal-review design "Testing
// Strategy" (task 9): the cascade break and row identity. The third test in
// that strategy — β re-derivation equality — lives in MacrosTests.
final class CorrectionRecordsTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorrectionRecordsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        store = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Cascade (Req 9.10)
    //
    // deleteMeal removes the meal and its artefacts and leaves
    // correction_records intact. This is the regression test for the defect
    // the spec exists to fix: retake and delete previously destroyed every
    // correction made during the session along with the meal.

    func testDeleteMealLeavesCorrectionRecordsIntact() async throws {
        let meal = makeMealRecord()
        try await store.save(meal, artefacts: [])
        let artefact = MealArtefact(
            kind: "mask", viewId: "nadir", filename: "nadir.mask",
            bytesSize: 4, sha256Hex: "abc"
        )
        try await store.writeArtefact(mealId: meal.id, artefact: artefact,
                                      data: Data([1, 2, 3, 4]))

        var record = makeCorrectionRecord(mealId: meal.id)
        try await store.createCorrectionRecords([record])
        record.classCorrected = true
        record.corrected = makeDerivation(classId: "couscous")
        record.updatedAtMs = record.createdAtMs + 1_000
        try await store.updateCorrectionRecord(record, upsertingCorrection: nil)

        try await store.deleteMeal(id: meal.id)

        // Meal and artefacts are gone.
        do {
            _ = try await store.meal(id: meal.id)
            XCTFail("meal must be deleted")
        } catch let error as Persistence.PersistenceError {
            XCTAssertEqual(error, .mealNotFound(meal.id))
        }
        let artefactBytes = try await store.artefactData(mealId: meal.id, kind: "mask")
        XCTAssertNil(artefactBytes, "artefact rows and files must cascade")

        // The correction records survive, still carrying the correction.
        let survivors = try await store.correctionRecords(for: meal.id)
        XCTAssertEqual(survivors.count, 1)
        XCTAssertTrue(survivors[0].classCorrected)
        XCTAssertEqual(survivors[0].corrected.classID, "couscous")
    }

    // MARK: - Row identity (Req 9.2, 9.3)
    //
    // Repeated corrections to one food leave exactly one row, with predicted
    // byte-identical to its first write and corrected reflecting only the
    // latest change. Includes the re-presentation case: creating rows twice
    // for the same meal must not reset created_at or clear a correction
    // already made.

    func testRepeatedCorrectionsKeepOneRowAndImmutablePredicted() async throws {
        let mealId = UUID()
        let original = makeCorrectionRecord(mealId: mealId)
        let originalPredictedBytes = try original.predicted.serializedData()
        try await store.createCorrectionRecords([original])

        // First correction: relabel.
        var relabelled = original
        relabelled.classCorrected = true
        relabelled.corrected = makeDerivation(classId: "couscous")
        relabelled.updatedAtMs = original.createdAtMs + 1_000
        try await store.updateCorrectionRecord(relabelled, upsertingCorrection: nil)

        // Second correction: amount on top of the relabel.
        var amountToo = relabelled
        amountToo.amountCorrected = true
        amountToo.corrected.massG = 180
        amountToo.updatedAtMs = original.createdAtMs + 2_000
        try await store.updateCorrectionRecord(amountToo, upsertingCorrection: nil)

        let rows = try await store.correctionRecords(for: mealId)
        XCTAssertEqual(rows.count, 1, "repeated corrections must not append rows")
        let row = rows[0]
        XCTAssertEqual(try row.predicted.serializedData(), originalPredictedBytes,
                       "predicted side must be byte-identical to its first write")
        XCTAssertEqual(row.createdAtMs, original.createdAtMs)
        XCTAssertTrue(row.classCorrected)
        XCTAssertTrue(row.amountCorrected)
        XCTAssertEqual(row.corrected.massG, 180, accuracy: 1e-9,
                       "corrected side reflects only the latest change")
    }

    func testRePresentationDoesNotResetCreatedAtOrClearCorrections() async throws {
        let mealId = UUID()
        let original = makeCorrectionRecord(mealId: mealId)
        try await store.createCorrectionRecords([original])

        var rejected = original
        rejected.rejected = true
        rejected.updatedAtMs = original.createdAtMs + 500
        try await store.updateCorrectionRecord(rejected, upsertingCorrection: nil)

        // The surface re-appears (back-gesture resync): creation runs again
        // with a later created_at. It must be a silent no-op.
        var recreated = makeCorrectionRecord(mealId: mealId)
        recreated.createdAtMs = original.createdAtMs + 60_000
        recreated.updatedAtMs = recreated.createdAtMs
        try await store.createCorrectionRecords([recreated])

        let rows = try await store.correctionRecords(for: mealId)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].createdAtMs, original.createdAtMs,
                       "re-creation must not reset created_at")
        XCTAssertTrue(rows[0].rejected,
                      "re-creation must not clear a correction already made")
    }

    // MARK: - Self-healing mutation (Req 8.5 hardening)
    //
    // updateCorrectionRecord is an upsert, not a bare UPDATE: when the
    // creation INSERT failed (its error is swallowed per Req 8.5), the first
    // mutation must materialise the row rather than matching zero rows on
    // every later correction while the reconciling corrections write beside
    // it succeeds.

    func testUpdateWithoutPriorCreateInsertsTheRow() async throws {
        let mealId = UUID()
        var record = makeCorrectionRecord(mealId: mealId)
        record.classCorrected = true
        record.corrected = makeDerivation(classId: "couscous")
        try await store.updateCorrectionRecord(record, upsertingCorrection: nil)

        let rows = try await store.correctionRecords(for: mealId)
        XCTAssertEqual(rows.count, 1, "mutation must self-heal a missing row")
        XCTAssertTrue(rows[0].classCorrected)
        XCTAssertEqual(rows[0].corrected.classID, "couscous")
    }

    func testBatchUpdateWritesEveryRowAndTheCorrectionTogether() async throws {
        let mealId = UUID()
        var rice = makeCorrectionRecord(mealId: mealId)
        var peas = makeCorrectionRecord(mealId: mealId)
        peas.predicted = makeDerivation(classId: "peas")
        try await store.createCorrectionRecords([rice, peas])

        rice.amountCorrected = true
        rice.updatedAtMs = rice.createdAtMs + 1_000
        peas.amountCorrected = true
        peas.updatedAtMs = peas.createdAtMs + 1_000
        var correction = PbUserCorrection()
        correction.createdAtMs = rice.createdAtMs
        correction.correctedTotalCarbsG = 18
        try await store.updateCorrectionRecords(
            [rice, peas], upsertingCorrection: correction
        )

        let rows = try await store.correctionRecords(for: mealId)
        XCTAssertEqual(rows.count, 2)
        XCTAssertTrue(rows.allSatisfy(\.amountCorrected),
                      "every row of the batch must carry the update")
        let stored = try await store.corrections(for: mealId)
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored[0].correctedTotalCarbsG, 18, accuracy: 1e-6,
                       "the reconciling upsert rides the same call")
    }

    // MARK: - No-eviction exemptions (Req 9.9)
    //
    // The corpus admits no deletion path: the Debug reset clears every event
    // table but leaves correction_records, and the artefact sweep exempts
    // meals holding an actual correction while never touching the corpus.

    func testDeleteAllDataLeavesCorrectionRecordsIntact() async throws {
        let meal = makeMealRecord()
        try await store.save(meal, artefacts: [])
        var record = makeCorrectionRecord(mealId: meal.id)
        try await store.createCorrectionRecords([record])
        record.rejected = true
        record.updatedAtMs = record.createdAtMs + 1_000
        try await store.updateCorrectionRecord(record, upsertingCorrection: nil)

        try await store.deleteAllData()

        let meals = try await store.allMeals()
        XCTAssertTrue(meals.isEmpty, "the Debug reset clears every meal")
        let survivors = try await store.correctionRecords(for: meal.id)
        XCTAssertEqual(survivors.count, 1)
        XCTAssertTrue(survivors[0].rejected,
                      "the Debug reset must not touch the corpus")
    }

    func testDeleteArtefactsExemptsCorrectedMealsAndKeepsCorpus() async throws {
        // Two old meals: one holding an ACTUAL correction, one holding only
        // the UNCHANGED row every reviewed meal has (Req 8.4: mere row
        // existence is not an exemption).
        let old = Date(timeIntervalSinceNow: -60 * 24 * 60 * 60)
        let correctedMeal = makeMealRecord(createdAt: old)
        let unchangedMeal = makeMealRecord(createdAt: old)
        let artefact = MealArtefact(
            kind: "mask", viewId: "nadir", filename: "nadir.mask",
            bytesSize: 4, sha256Hex: "abc"
        )
        for meal in [correctedMeal, unchangedMeal] {
            try await store.save(meal, artefacts: [])
            try await store.writeArtefact(mealId: meal.id, artefact: artefact,
                                          data: Data([1, 2, 3, 4]))
        }
        var corrected = makeCorrectionRecord(mealId: correctedMeal.id)
        try await store.createCorrectionRecords([corrected])
        corrected.amountCorrected = true
        corrected.updatedAtMs = corrected.createdAtMs + 1_000
        try await store.updateCorrectionRecord(corrected, upsertingCorrection: nil)
        try await store.createCorrectionRecords(
            [makeCorrectionRecord(mealId: unchangedMeal.id)]
        )

        try await store.deleteArtefacts(
            olderThan: Date(timeIntervalSinceNow: -30 * 24 * 60 * 60)
        )

        let keptBytes = try await store.artefactData(mealId: correctedMeal.id, kind: "mask")
        XCTAssertNotNil(keptBytes,
                        "a meal holding an actual correction is exempt from the sweep")
        let sweptBytes = try await store.artefactData(mealId: unchangedMeal.id, kind: "mask")
        XCTAssertNil(sweptBytes, "mere row existence is not an exemption")
        // The corpus itself is untouched on both sides (Req 9.9).
        let correctedRows = try await store.correctionRecords(for: correctedMeal.id)
        XCTAssertEqual(correctedRows.count, 1)
        let unchangedRows = try await store.correctionRecords(for: unchangedMeal.id)
        XCTAssertEqual(unchangedRows.count, 1)
    }

    // MARK: - The reconciling write (Req 8.5, design "the reconciling write")

    func testUpsertCorrectionToleratesSameMillisecondWrites() async throws {
        let mealId = UUID()
        var correction = PbUserCorrection()
        correction.createdAtMs = 1_750_000_000_000
        correction.correctedTotalCarbsG = 30

        // Two writes at the same created_at must not raise a constraint
        // violation — the second updates in place (latest value wins).
        try await store.upsertCorrection(mealId: mealId, correction: correction)
        correction.correctedTotalCarbsG = 28
        correction.correctedClassIds = ["white_rice": "couscous"]
        try await store.upsertCorrection(mealId: mealId, correction: correction)

        let stored = try await store.corrections(for: mealId)
        XCTAssertEqual(stored.count, 1, "one corrections row per meal")
        XCTAssertEqual(stored[0].correctedTotalCarbsG, 28, accuracy: 1e-6)
        XCTAssertEqual(stored[0].correctedClassIds, ["white_rice": "couscous"])
    }

    func testRecentCorrectedClassIdsOrdersByRecencyDistinct() async throws {
        // Three meals correcting white_rice → couscous, then → bulgur.
        let specs: [(corrected: String, at: Int64)] = [
            ("couscous", 1_000), ("bulgur", 2_000), ("couscous", 3_000)
        ]
        for (corrected, at) in specs {
            var record = makeCorrectionRecord(mealId: UUID())
            record.createdAtMs = at
            try await store.createCorrectionRecords([record])
            record.classCorrected = true
            record.corrected = makeDerivation(classId: corrected)
            record.updatedAtMs = at + 1
            try await store.updateCorrectionRecord(record, upsertingCorrection: nil)
        }

        let recent = try await store.recentCorrectedClassIds(
            forPredictedClass: "white_rice", limit: 5
        )
        XCTAssertEqual(recent, ["couscous", "bulgur"],
                       "distinct corrected classes, newest first")
    }

    // MARK: - Fixtures

    private func makeDerivation(classId: String) -> PbFoodDerivation {
        var d = PbFoodDerivation()
        d.classID = classId
        d.classIndex = 7
        d.volumeCm3 = 108
        d.volumePreBetaCm3 = 120
        d.betaUsed = 0.9
        d.betaStatus = .calibrated
        d.densityGPerCm3 = 1.05
        d.carbsPer100G = 32
        d.densitySource = "CoFID 2024"
        d.coefficientSource = "CoFID 2024"
        d.massG = 113.4
        d.carbsG = 36.288
        return d
    }

    private func makeCorrectionRecord(mealId: UUID) -> PbCorrectionRecord {
        var r = PbCorrectionRecord()
        r.schemaVersion = "1"
        r.mealID = mealId.uuidString
        r.createdAtMs = 1_750_000_000_000
        r.updatedAtMs = r.createdAtMs
        r.paletteVersion = "v2"
        r.databaseEdition = "CoFID 2024"
        r.segmenterSource = "test"
        r.buildStamp = "test"
        r.predicted = makeDerivation(classId: "white_rice")
        return r
    }

    private func makeMealRecord(createdAt: Date = Date()) -> MealRecord {
        var perClassEntry = PbPerClassMacros()
        perClassEntry.volumeCm3 = 108
        perClassEntry.massG = 113.4
        perClassEntry.carbsG = 36.288
        perClassEntry.betaUsed = 0.9
        perClassEntry.betaStatus = .calibrated

        var macros = PbMacroResult()
        macros.totalCarbsG = 36.288
        macros.perClass = ["white_rice": perClassEntry]

        var volumes = PbVolumeResult()
        volumes.perClassVolumesCm3 = ["white_rice": 108]
        volumes.perClassVolumesPreBetaCm3 = ["white_rice": 120]

        var confidence = PbConfidenceResult()
        confidence.sigmaMeal = 0.8

        return MealRecord(
            createdAt: createdAt,
            capturePath: .singleViewLidar,
            databaseEdition: "CoFID 2024",
            paletteVersion: "v2",
            calibration: PbCameraIntrinsics(),
            supportPlane: PbSupportPlane(),
            scale: PbMetricScale(),
            volumes: volumes,
            macros: macros,
            confidence: confidence,
            perClassCalibration: ["white_rice": .calibrated]
        )
    }
}

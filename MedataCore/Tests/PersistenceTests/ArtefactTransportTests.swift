import Foundation
import PortableContracts
import XCTest
@testable import Persistence

// Byte-transport surface for per-meal artefacts (UI Design Handoff 00,
// Decision 15). The store owns the filesystem layout; no paths cross its
// boundary. `writeArtefact` writes the file first, then the row; `artefactData`
// returns nil (never throws) when the artefact or its file is absent — that nil
// is the §6.8 photo-only fallback signal.
final class ArtefactTransportTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArtefactTransportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        store = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func maskArtefact(filename: String = "mask.png", size: Int) -> MealArtefact {
        MealArtefact(kind: "mask", viewId: "nadir", filename: filename, bytesSize: size, sha256Hex: "")
    }

    private func maskFileURL(mealId: UUID, filename: String) -> URL {
        tempDir
            .appendingPathComponent("meals", isDirectory: true)
            .appendingPathComponent(mealId.uuidString, isDirectory: true)
            .appendingPathComponent(filename)
    }

    func testWriteArtefactWritesFileAndRowThenReadsBack() async throws {
        let mealId = UUID()
        let data = Data([0, 1, 2, 3, 4, 250, 255])
        try await store.writeArtefact(
            mealId: mealId,
            artefact: maskArtefact(size: data.count),
            data: data
        )

        // File is on disk at meals/{id}/{filename}.
        let fileURL = maskFileURL(mealId: mealId, filename: "mask.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(try Data(contentsOf: fileURL), data)

        // And the bytes come back through the store API.
        let readBack = try await store.artefactData(mealId: mealId, kind: "mask")
        XCTAssertEqual(readBack, data)
    }

    func testArtefactDataNilWhenNoRow() async throws {
        let readBack = try await store.artefactData(mealId: UUID(), kind: "mask")
        XCTAssertNil(readBack)
    }

    func testArtefactDataNilWhenFileMissing() async throws {
        let mealId = UUID()
        let data = Data([1, 2, 3])
        try await store.writeArtefact(
            mealId: mealId,
            artefact: maskArtefact(size: data.count),
            data: data
        )
        // Remove the file behind the store's back; the row remains.
        try FileManager.default.removeItem(at: maskFileURL(mealId: mealId, filename: "mask.png"))

        let readBack = try await store.artefactData(mealId: mealId, kind: "mask")
        XCTAssertNil(readBack, "absent file must return nil, not throw")
    }

    func testDeleteMealRemovesArtefactFile() async throws {
        let mealId = UUID()
        let data = Data([9, 9, 9])
        try await store.writeArtefact(
            mealId: mealId,
            artefact: maskArtefact(size: data.count),
            data: data
        )
        let fileURL = maskFileURL(mealId: mealId, filename: "mask.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        try await store.deleteMeal(id: mealId)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        let readBack = try await store.artefactData(mealId: mealId, kind: "mask")
        XCTAssertNil(readBack)
    }
}

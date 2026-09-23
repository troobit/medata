import Foundation
import PortableContracts
import XCTest
import ZIPFoundation
@testable import Persistence

// Tests for archive export (zip) per design §4.1 / Req 15.8 / task 45.

final class ArchiveExportTests: XCTestCase {

    private var store: GRDBPersistenceStore!
    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dbURL = tempDir.appendingPathComponent("meals.sqlite")
        store = try GRDBPersistenceStore(dbURL: dbURL, artefactsBaseURL: tempDir)
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - T45.1 exportArchive returns a path to a .zip file

    func testExportArchiveReturnsZipPath() async throws {
        let path = try await store.exportArchive()
        XCTAssertTrue(path.hasSuffix(".zip"), "archive path should end with .zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path), "archive file must exist")
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - T45.2 Archive contains meals.sqlite

    func testArchiveContainsMealsSqlite() async throws {
        let path = try await store.exportArchive()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let archiveURL = URL(fileURLWithPath: path)
        guard let archive = Archive(url: archiveURL, accessMode: .read) else {
            return XCTFail("could not open ZIP archive")
        }
        let entries = archive.map { $0.path }
        XCTAssertTrue(entries.contains("meals.sqlite"), "archive must contain meals.sqlite, found: \(entries)")
    }

    // MARK: - T45.3 Archive contains per-meal artefact files when present

    func testArchiveContainsArtefactFiles() async throws {
        // Write a fake artefact file under meals/<uuid>/.
        let mealId = UUID()
        let mealDir = tempDir.appendingPathComponent("meals/\(mealId.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: mealDir, withIntermediateDirectories: true)
        let imageFile = mealDir.appendingPathComponent("nadir.image")
        try Data("fake image data".utf8).write(to: imageFile)

        let path = try await store.exportArchive()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let archiveURL = URL(fileURLWithPath: path)
        guard let archive = Archive(url: archiveURL, accessMode: .read) else {
            return XCTFail("could not open ZIP archive")
        }
        let entries = archive.map { $0.path }
        let expectedEntry = "meals/\(mealId.uuidString)/nadir.image"
        XCTAssertTrue(entries.contains(expectedEntry),
            "archive should contain artefact \(expectedEntry), found: \(entries)")
    }

    // MARK: - T45.4 Two consecutive exports produce independent files

    func testTwoConsecutiveExportsAreIndependent() async throws {
        let path1 = try await store.exportArchive()
        let path2 = try await store.exportArchive()
        defer {
            try? FileManager.default.removeItem(atPath: path1)
            try? FileManager.default.removeItem(atPath: path2)
        }
        XCTAssertNotEqual(path1, path2, "each export should produce a distinct file path")
        XCTAssertTrue(FileManager.default.fileExists(atPath: path1))
        XCTAssertTrue(FileManager.default.fileExists(atPath: path2))
    }
}

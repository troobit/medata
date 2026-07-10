import CoreGraphics
import Foundation
import ImageIO
import PortableContracts
import Segmentation
import Testing
import UniformTypeIdentifiers
@testable import Persistence
@testable import Pipeline

// Stage L persists the segmentation label raster as an 8-bit greyscale PNG of
// RAW class indices — no colour, no colour profile (UI Design Handoff 00,
// Decision 15). The encode/write is storage-only and must never fail the meal
// save. The full pipeline cannot reach Stage L on a synthetic RawFrame, so the
// extractable writer is tested directly here.
@Suite("Stage L mask artefact")
struct StageLMaskArtefactTests {

    private func makeArgmax() -> ArgmaxMap {
        // Distinct label indices per pixel, including the sentinel classes.
        let pixels = Data([
            0, 1, 2, 3,
            4, 5, 6, 7,
            8, 32, 33, 34
        ])
        return ArgmaxMap(pixels: pixels, height: 3, width: 4)
    }

    // Reads tight 1-byte-per-pixel grey samples from a decoded CGImage.
    private func rawGreyBytes(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data else { return [] }
        let ptr = CFDataGetBytePtr(data)!
        let bytesPerRow = image.bytesPerRow
        var out: [UInt8] = []
        for y in 0..<image.height {
            for x in 0..<image.width {
                out.append(ptr[y * bytesPerRow + x])
            }
        }
        return out
    }

    @Test("Encodes an 8-bit greyscale PNG whose samples equal the raw label indices")
    func encodesRawIndices() throws {
        let argmax = makeArgmax()
        let png = try MaskArtefactWriter.encodeLabelPNG(argmax)

        // Decodable PNG.
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 4)
        #expect(image.height == 3)
        #expect(image.bitsPerComponent == 8)
        // Single greyscale component (no colour).
        #expect(image.colorSpace?.model == .monochrome)
        // Samples equal the input indices, unremapped.
        #expect(rawGreyBytes(image) == Array(argmax.pixels))
    }

    @Test("persistMask writes a mask row and the bytes decode back to the indices")
    func persistMaskWritesArtefact() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("StageLMask-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let store = try GRDBPersistenceStore(
            dbURL: tempDir.appendingPathComponent("meals.sqlite"),
            artefactsBaseURL: tempDir
        )
        let mealId = UUID()
        let argmax = makeArgmax()

        await MaskArtefactWriter.persistMask(argmax: argmax, mealId: mealId, store: store)

        let data = try await store.artefactData(mealId: mealId, kind: "mask")
        let png = try #require(data)
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(rawGreyBytes(image) == Array(argmax.pixels))
    }

    @Test("persistMask swallows a store write failure — the meal save is unaffected")
    func persistMaskSwallowsFailure() async {
        let argmax = makeArgmax()
        // ThrowingStore.writeArtefact throws; persistMask must not propagate.
        await MaskArtefactWriter.persistMask(
            argmax: argmax, mealId: UUID(), store: ThrowingStore()
        )
        // Reaching here without a thrown error is the assertion.
        #expect(Bool(true))
    }
}

// A store whose artefact write always fails, to prove persistMask swallows.
private struct ThrowingStore: PersistenceStore {
    struct Boom: Error {}
    func save(_ record: MealRecord, artefacts: [MealArtefact]) async throws {}
    func appendCorrection(mealId: UUID, correction: PbUserCorrection) async throws {}
    func meal(id: UUID) async throws -> MealRecord { throw PersistenceError.mealNotFound(id) }
    func deleteArtefacts(olderThan date: Date) async throws {}
    func exportArchive() async throws -> String { "" }
    func sweepIfDue() async throws {}
    func updatePhotoAssetID(mealId: UUID, photoAssetID: String) async throws {}
    func allMeals() async throws -> [MealRecord] { [] }
    func deleteMeal(id: UUID) async throws {}
    func writeArtefact(mealId: UUID, artefact: MealArtefact, data: Data) async throws { throw Boom() }
    func artefactData(mealId: UUID, kind: String) async throws -> Data? { nil }
    func events(in range: ClosedRange<Date>, type: String?) async throws -> [Event] { [] }
    func corrections(for mealId: UUID) async throws -> [PbUserCorrection] { [] }
    func isImageProcessed(hash: String) async throws -> Bool {
        fatalError("unused")
    }
    func ingestBsl(
        readings: [BslReading], metadataJSON: String,
        sourceHash: String, filename: String
    ) async throws -> BslIngestSummary {
        fatalError("unused")
    }
    func ingestLiveBsl(_ readings: [LiveBslReading]) async throws -> BslIngestSummary {
        fatalError("unused")
    }
    func saveInsulinDose(_ dose: InsulinDose) async throws {
        fatalError("unused")
    }
    func deleteInsulinEvent(id: UUID) async throws {
        fatalError("unused")
    }
    func saveIntakeEntry(_ entry: IntakeEntry) async throws {
        fatalError("unused")
    }
    func updateIntakeEntry(_ entry: IntakeEntry) async throws {
        fatalError("unused")
    }
    func deleteIntakeEntry(id: UUID) async throws {
        fatalError("unused")
    }
    var eventsDidChange: AsyncStream<Void> { AsyncStream { _ in } }
}

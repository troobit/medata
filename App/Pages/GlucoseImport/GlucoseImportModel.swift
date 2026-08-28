import CoreGraphics
import CryptoKit
import Foundation
import GlucoseGraph
import ImageIO
import Persistence
import Photos
import PhotosUI
import SwiftUI

// Drives the LibreLink screenshot import (specs/data/libre-ingestion §Import
// UI, Decision 7). Images process strictly sequentially — one decoded bitmap
// in memory at a time, deterministic keep-first merge order, per-image
// transactions — so cancellation between images is always safe.
@Observable
@MainActor
final class GlucoseImportModel {

    struct ImageResult: Identifiable {
        enum Outcome {
            case stored(BslIngestSummary)
            case skippedDuplicate
            case rejected(reason: String)
            case failed(message: String)
        }

        let id = UUID()
        let filename: String
        let outcome: Outcome
        let warnings: [String]
    }

    private let store: any PersistenceStore
    private(set) var results: [ImageResult] = []
    private(set) var isProcessing = false
    private(set) var processedCount = 0
    private(set) var totalCount = 0
    private var processingTask: Task<Void, Never>?

    init(store: any PersistenceStore) {
        self.store = store
    }

    func process(items: [PhotosPickerItem]) {
        guard !items.isEmpty, !isProcessing else { return }
        isProcessing = true
        processedCount = 0
        totalCount = items.count
        processingTask = Task {
            for (index, item) in items.enumerated() {
                if Task.isCancelled { break }
                let result = await processItem(item, fallbackName: "image \(index + 1)")
                results.insert(result, at: 0)
                processedCount += 1
            }
            isProcessing = false
        }
    }

    // Cancellation stops after the in-flight image; committed images stay
    // committed (per-image transactions, Req 4.5).
    func cancel() {
        processingTask?.cancel()
        processingTask = nil
        isProcessing = false
    }

    private func processItem(
        _ item: PhotosPickerItem, fallbackName: String
    ) async -> ImageResult {
        let asset = item.itemIdentifier.flatMap { identifier in
            PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject
        }
        let filename = asset
            .flatMap { PHAssetResource.assetResources(for: $0).first?.originalFilename }
            ?? fallbackName

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                return ImageResult(
                    filename: filename,
                    outcome: .failed(message: "cannot read image data"),
                    warnings: [])
            }

            let hashHex = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }.joined()
            if try await store.isImageProcessed(hash: hashHex) {
                return ImageResult(
                    filename: filename, outcome: .skippedDuplicate, warnings: [])
            }

            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                return ImageResult(
                    filename: filename,
                    outcome: .failed(message: "cannot decode image"),
                    warnings: [])
            }

            // Decision 3: the asset's creation instant is the 8h view's
            // right-edge "now". PHAsset first, EXIF DateTimeOriginal second.
            let assetDate = graphDate(from: asset?.creationDate)
                ?? exifDate(from: source)

            // Extraction is CPU-bound (per-pixel scans + Vision OCR); keep
            // it off the main actor.
            let extraction = try await Task.detached(priority: .userInitiated) {
                try GlucoseGraphExtractor.extract(
                    cgImage: cgImage, assetDate: assetDate, timeZone: .current)
            }.value

            let metadataJSON = try Self.metadataJSON(
                extraction: extraction, hashHex: hashHex, filename: filename)
            let readings = extraction.readings.map {
                BslReading(timestampMs: $0.tsUtcMs, value: $0.value)
            }
            let summary = try await store.ingestBsl(
                readings: readings, metadataJSON: metadataJSON,
                sourceHash: hashHex, filename: filename)
            return ImageResult(
                filename: filename, outcome: .stored(summary),
                warnings: extraction.warnings)
        } catch let reject as RejectImage {
            return ImageResult(
                filename: filename, outcome: .rejected(reason: reject.reason),
                warnings: [])
        } catch {
            return ImageResult(
                filename: filename,
                outcome: .failed(message: error.localizedDescription),
                warnings: [])
        }
    }

    private func graphDate(from date: Date?) -> GraphDate? {
        guard let date else { return nil }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month,
              let day = components.day else { return nil }
        return GraphDate(year: year, month: month, day: day)
    }

    // EXIF DateTimeOriginal is "yyyy:MM:dd HH:mm:ss" wall-clock; only the
    // calendar date matters here.
    private func exifDate(from source: CGImageSource) -> GraphDate? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let stamp = exif[kCGImagePropertyExifDateTimeOriginal] as? String
        else { return nil }
        let datePart = stamp.prefix(10).split(separator: ":")
        guard datePart.count == 3,
              let year = Int(datePart[0]), let month = Int(datePart[1]),
              let day = Int(datePart[2]) else { return nil }
        return GraphDate(year: year, month: month, day: day)
    }

    // Same metadata keys as the reference tool (Req 4.2), with date_source
    // "asset" replacing "supplied".
    private static func metadataJSON(
        extraction: Extraction, hashHex: String, filename: String
    ) throws -> String {
        let payload: [String: Any] = [
            "source_hash": "sha256:\(hashHex)",
            "source_file": filename,
            "view": extraction.view.rawValue,
            "date": extraction.date.isoString,
            "date_source": extraction.dateSource,
            "timezone": extraction.timezone,
            "axis_range": [extraction.axisRange.low, extraction.axisRange.high],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [])
        return String(decoding: data, as: UTF8.self)
    }
}

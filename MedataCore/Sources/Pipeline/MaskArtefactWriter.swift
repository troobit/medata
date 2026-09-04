import CoreGraphics
import Foundation
import ImageIO
import os
import Persistence
import Segmentation
import UniformTypeIdentifiers

// Storage-only persistence of the segmentation mask (UI Design Handoff 00,
// Decision 15). At Stage L, after the meal is saved, the label raster is encoded
// as an 8-bit greyscale PNG of RAW class indices — no colour, no colour profile
// — and written via `writeArtefact(kind: "mask")`. Colours are applied only at
// read time from the id->colour table; the stored bytes are indices.
//
// This touches NO estimation maths (Decision 15 boundary): it consumes the
// already-computed argmax and writes bytes. Any encode/write failure is logged
// and swallowed so the meal save is never affected.
enum MaskArtefactWriter {

    static let maskKind = "mask"
    static let maskFilename = "mask.png"

    private static let log = Logger(subsystem: "ie.medata.app", category: "MaskArtefact")

    enum EncodeError: Error {
        case cgImageCreationFailed
        case destinationCreationFailed
        case encodeFailed
    }

    // Encodes the argmax as an 8-bit greyscale PNG whose samples are the raw
    // class indices. DeviceGray + alpha-none means one byte per pixel and no
    // ICC profile, so a raw bitmap read on the way back gives the indices
    // unchanged.
    static func encodeLabelPNG(_ argmax: ArgmaxMap) throws -> Data {
        let width = argmax.width
        let height = argmax.height
        let pixels = argmax.pixels

        guard let provider = CGDataProvider(data: pixels as CFData) else {
            throw EncodeError.cgImageCreationFailed
        }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        guard let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ) else {
            throw EncodeError.cgImageCreationFailed
        }

        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            out as CFMutableData, UTType.png.identifier as CFString, 1, nil
        ) else {
            throw EncodeError.destinationCreationFailed
        }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw EncodeError.encodeFailed
        }
        return out as Data
    }

    // Encodes and persists the mask. Never throws: any failure is logged and
    // swallowed so the meal save (which already succeeded) is unaffected.
    static func persistMask(argmax: ArgmaxMap, mealId: UUID, store: any PersistenceStore) async {
        do {
            let png = try encodeLabelPNG(argmax)
            let artefact = MealArtefact(
                kind: maskKind,
                viewId: "nadir",
                filename: maskFilename,
                bytesSize: png.count,
                sha256Hex: ""
            )
            try await store.writeArtefact(mealId: mealId, artefact: artefact, data: png)
        } catch {
            log.error("event=mask.persist.failed mealId=\(mealId.uuidString, privacy: .public) error=\(String(describing: error), privacy: .public)")
        }
    }
}

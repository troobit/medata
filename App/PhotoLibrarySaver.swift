import CaptureKit
import Foundation
import Photos
import UIKit

// PhotoKit add-only saver used by the capture flow after a successful estimate
// (Decision 37, Req §17.3). The original captured RGB nadir frame is written
// to the user's Photos library and the returned `PHAsset.localIdentifier` is
// stamped on the persisted `MealRecord.photoAssetID`.
//
// The saver is protocol-based so unit tests can inject a deterministic stub
// without touching PhotoKit (which is unavailable in unit-test bundles that
// don't link a host app). `PhotoKitSaver` is the production implementation.
protocol PhotoLibrarySaver: Sendable {
    // Returns the PHAsset.localIdentifier of the saved photo, or an empty
    // string when add-only authorisation is denied / restricted / unavailable.
    // Throws only on unexpected PhotoKit errors (out-of-disk, library locked);
    // a denial is not an error — estimation still completes per Decision 37.
    func saveNadirFrame(_ frame: RawFrame) async throws -> String
}

// Failure modes that propagate to the UI as the Irish-English placeholder
// state, but never block the meal record from being persisted.
enum PhotoLibrarySaveError: Error, Equatable {
    case encodingFailed         // RawFrame could not be re-encoded as RGB/JPEG
    case performChangesFailed   // PHPhotoLibrary.performChanges threw
}

// Production saver: requests `.addOnly` authorisation on first call, encodes
// the RawFrame as PNG via UIImage, and writes a new asset via PHPhotoLibrary.
// Returns "" when the user denies authorisation so the caller persists the
// meal with an empty identifier (the result view then shows a placeholder).
struct PhotoKitSaver: PhotoLibrarySaver {

    func saveNadirFrame(_ frame: RawFrame) async throws -> String {
        let status = await Self.requestAddOnlyAuthorisation()
        guard status == .authorized || status == .limited else {
            return ""
        }
        guard let image = Self.uiImage(from: frame),
              let pngData = image.pngData()
        else {
            throw PhotoLibrarySaveError.encodingFailed
        }
        return try await Self.performAdd(pngData: pngData)
    }

    private static func requestAddOnlyAuthorisation() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func performAdd(pngData: Data) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            var assetID: String = ""
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: pngData, options: nil)
                assetID = request.placeholderForCreatedAsset?.localIdentifier ?? ""
            }, completionHandler: { success, error in
                if let error {
                    continuation.resume(throwing: PhotoLibrarySaveError.performChangesFailed)
                    _ = error
                } else if success {
                    continuation.resume(returning: assetID)
                } else {
                    continuation.resume(throwing: PhotoLibrarySaveError.performChangesFailed)
                }
            })
        }
    }

    // Convert RawFrame.imageBytes to UIImage. The portable contract is RGB8 in
    // sRGB at the platform-native orientation; iOS captures BGRA8 and converts
    // upstream, but the renderer here accepts either by inspecting pixelFormat.
    private static func uiImage(from frame: RawFrame) -> UIImage? {
        let bytesPerPixel: Int
        let bitmapInfo: CGBitmapInfo
        switch frame.pixelFormat {
        case .rgb8:
            bytesPerPixel = 3
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        case .rgba8:
            bytesPerPixel = 4
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        case .bgra8:
            bytesPerPixel = 4
            bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                .union(.byteOrder32Little)
        }
        let width = frame.imageWidth
        let height = frame.imageHeight
        let bytesPerRow = width * bytesPerPixel
        guard frame.imageBytes.count == bytesPerRow * height else { return nil }
        let colourSpace = CGColorSpaceCreateDeviceRGB()
        let data = frame.imageBytes as CFData
        guard let provider = CGDataProvider(data: data),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: bytesPerPixel * 8,
                bytesPerRow: bytesPerRow,
                space: colourSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              )
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

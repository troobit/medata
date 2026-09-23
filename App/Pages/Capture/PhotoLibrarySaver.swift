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

// Failure modes that propagate to the UI as the thumbnail placeholder
// state, but never block the meal record from being persisted.
enum PhotoLibrarySaveError: Error, Equatable {
    case encodingFailed  // RawFrame could not be re-encoded as RGB/JPEG
    case performChangesFailed  // PHPhotoLibrary.performChanges threw
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
            PHPhotoLibrary.shared().performChanges(
                {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: pngData, options: nil)
                    assetID = request.placeholderForCreatedAsset?.localIdentifier ?? ""
                },
                completionHandler: { success, error in
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

    // Convert RawFrame.imageBytes to UIImage. The decode itself is shared with
    // the capture surfaces via `RawFrameImage.cgImage(_:)` — same pixel-format
    // switch, same byte-count guard; only the UIImage wrapper is local.
    private static func uiImage(from frame: RawFrame) -> UIImage? {
        RawFrameImage.cgImage(frame).map(UIImage.init(cgImage:))
    }
}

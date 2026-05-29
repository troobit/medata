import Foundation
import Persistence
import Photos
import PortableContracts
import SwiftUI

// Pure formatter that the SwiftUI body and unit tests both consume. Keeps the
// MealRow view itself a thin shell so the Req §19.2 / §19.3 contract is testable
// without spinning up SwiftUI snapshot infrastructure.
struct MealRowFormat {
    let record: MealRecord

    var showsPlaceholderChip: Bool { record.segmenterSource == "dev_stub" }
    var photoAssetID: String? { record.photoAssetID }
    var carbDisplay: String { "\(ResultFormat.carbsGrams(record.macros.totalCarbsG)) g" }

    var timestampString: String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_IE")
        fmt.dateFormat = "dd MMM yyyy, HH:mm"
        return fmt.string(from: record.createdAt)
    }
}

// Single row in the Meals tab list (UI Req §19.2 / §19.3 / Decision 15).
// Thumbnail comes via `PHImageManager.requestImage(for:targetSize:contentMode:options:resultHandler:)`
// using `record.photoAssetID`; the placeholder chip rides on
// `record.segmenterSource == "dev_stub"` so the dev-stub provenance is visible
// in the history even after Phase 3 ships.
struct MealRow: View {
    let record: MealRecord

    @State private var thumbnail: UIImage?

    private var format: MealRowFormat { MealRowFormat(record: record) }

    var body: some View {
        HStack(spacing: 12) {
            thumbnailView
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(format.carbDisplay)
                        .font(.headline.monospacedDigit())
                    if format.showsPlaceholderChip {
                        Text("Placeholder")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.yellow.opacity(0.25), in: Capsule())
                            .overlay(Capsule().stroke(Color.yellow, lineWidth: 1))
                            .accessibilityIdentifier("meal.placeholderChip")
                    }
                    ConfidencePill(sigmaMeal: record.confidence.sigmaMeal)
                }
                Text(format.timestampString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .task { await loadThumbnail() }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.15))
                Image(systemName: "photo.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64, height: 64)
            .accessibilityIdentifier("meal.photoFallback")
        }
    }

    private func loadThumbnail() async {
        guard let assetID = record.photoAssetID else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 192, height: 192),
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                continuation.resume(returning: result)
            }
        }
        self.thumbnail = image
    }
}

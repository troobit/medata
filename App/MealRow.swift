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

enum MealRowLayout {
    // §19.2 / `design-system/pages/meals-tab.md` §"MealRow": 4:3 photo above
    // a caption row.
    static let photoAspectRatio: CGFloat = 4.0 / 3.0
    static let photoCornerRadius: CGFloat = 14
    static let rowSpacing: CGFloat = 24
    // Target size is 2× the row width to keep `PHImageManager` allocations
    // bounded (`PHImageManagerMaximumSize` is wasteful for a list cell).
    static let thumbnailTargetMultiplier: CGFloat = 2

    static func thumbnailTargetSize(rowWidth: CGFloat) -> CGSize {
        let width = max(rowWidth, 1) * thumbnailTargetMultiplier
        let height = width / photoAspectRatio
        return CGSize(width: width, height: height)
    }
}

// Single row in the Meals tab list (UI Req §19.2 / §19.3 / §20.9 /
// Decision 16). Feed-style layout per `design-system/pages/meals-tab.md`:
// full-width 4:3 photo with rounded corners, then a caption row (carb total
// + confidence pill + optional placeholder chip), then the timestamp.
struct MealRow: View {
    let record: MealRecord

    @State private var thumbnail: UIImage?

    private var format: MealRowFormat { MealRowFormat(record: record) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            photo
            captionRow
            Text(format.timestampString)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
                .accessibilityIdentifier("meal.timestamp")
        }
        .padding(.vertical, MealRowLayout.rowSpacing / 2)
        .task { await loadThumbnail() }
    }

    private var photo: some View {
        GeometryReader { geom in
            ZStack {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.surfaceElevated
                    Image(systemName: "fork.knife")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.textSecondary)
                        .accessibilityIdentifier("meal.photoFallback")
                }
            }
            .frame(width: geom.size.width, height: geom.size.width / MealRowLayout.photoAspectRatio)
            .clipShape(RoundedRectangle(cornerRadius: MealRowLayout.photoCornerRadius))
        }
        .aspectRatio(MealRowLayout.photoAspectRatio, contentMode: .fit)
        .accessibilityIdentifier("meal.photo")
    }

    private var captionRow: some View {
        HStack(spacing: 12) {
            Text(format.carbDisplay)
                .font(.system(size: 24, weight: .heavy, design: .default).monospacedDigit())
                .foregroundStyle(Color.textPrimary)
                .accessibilityIdentifier("meal.carbDisplay")
            ConfidencePill(sigmaMeal: record.confidence.sigmaMeal)
            if format.showsPlaceholderChip { placeholderChip }
            Spacer()
        }
    }

    private var placeholderChip: some View {
        Text("Placeholder")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.placeholderBG, in: Capsule())
            .foregroundStyle(Color.placeholderFG)
            .accessibilityIdentifier("meal.placeholderChip")
    }

    private func loadThumbnail() async {
        guard let assetID = record.photoAssetID else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false
        let rowWidth = await MainActor.run { UIScreen.main.bounds.width - 32 }
        let target = MealRowLayout.thumbnailTargetSize(rowWidth: rowWidth)
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                continuation.resume(returning: result)
            }
        }
        self.thumbnail = image
    }
}

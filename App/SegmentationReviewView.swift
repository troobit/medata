import Photos
import Pipeline
import SwiftUI

// Segmentation review (§5, design-system/pages/segmentation-review.md). Post-hoc
// display of the completed estimate's masks — the pipeline is NOT split
// (Decision 7): the estimate already ran during `.estimating`, so the primary
// action merely advances to Result and its label must not imply pending work
// (Req 5.3). Shows the captured photo with the per-class mask overlay, a class
// list with mask-colour swatches (NO per-class confidence — Decision 16), and
// amber banners for unknown regions / unsupported liquids when the raster
// contains them (Req 5.2).
struct SegmentationReviewView: View {
    let record: MealRecord
    let store: any PersistenceStore
    var onCarbs: () -> Void = {}

    @State private var photo: UIImage?
    // Class indices present in the mask raster, reported by MaskOverlayLoader.
    // Unknown / unsupported-liquid regions carry no per-class macro entry, so the
    // raster is the only place they surface (§5.2). Empty when no mask (Req 6.8).
    @State private var presentClassIds: Set<Int> = []

    private let palette = ClassPalette.v1Standard
    private var table: ClassColourTable { ClassColourTable(version: record.paletteVersion) }

    private var hasUnknownRegion: Bool { presentClassIds.contains(palette.unknownFood) }
    private var hasUnsupportedLiquid: Bool { presentClassIds.contains(palette.unsupportedLiquid) }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.captureBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    photoWithMask
                    if hasUnknownRegion {
                        banner("Unknown region · counted as unknown carbs", symbol: "questionmark.circle.fill")
                    }
                    if hasUnsupportedLiquid {
                        banner("Liquid · not estimated", symbol: "drop.fill")
                    }
                    classList
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 96)
            }
            carbsAction
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        // Deliberately untitled (snaqui Req 4).
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPhoto() }
    }

    // §5.1: captured photo with the per-class mask overlay. The overlay renders
    // nothing when the mask is unavailable, so the photo (or its placeholder)
    // shows through unchanged (Req 6.8).
    private var photoWithMask: some View {
        ZStack {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.captureChromeBG
                    Image(systemName: "fork.knife")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.captureChromeText.opacity(0.5))
                }
                .accessibilityIdentifier("review.thumbnailFallback")
            }
            MaskOverlayLoader(
                store: store,
                mealId: record.id,
                paletteVersion: record.paletteVersion,
                onDecode: { presentClassIds = $0 }
            )
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(4.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("review.photo")
    }

    // Amber, icon + text (not colour alone — Req 14.4 / §5.2).
    private func banner(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(text)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.captureChromeText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .systemOrange).opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    // §5.1: class list with mask-colour swatches; no per-class confidence
    // (Decision 16). Header `Detected (N)`.
    private var classList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Detected (\(rows.count))")
                .font(.headline)
                .foregroundStyle(Color.captureChromeText)
            ForEach(rows, id: \.name) { row in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(swatchColour(for: row.name))
                        .frame(width: 16, height: 16)
                    Text(row.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.captureChromeText)
                    Spacer()
                    Text("\(row.carbsG) g carbs")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.captureChromeText.opacity(0.75))
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("review.classList")
    }

    // §5.3 / Decision 7: advance to Result. `Carbs` — estimation already done, so
    // the label does not imply pending work.
    // The pill sizing/background/contentShape live INSIDE the Button's label: a
    // Button's tap gesture only covers its label, so `.frame(maxWidth:)` etc.
    // applied OUTSIDE the Button draw a wide pill whose surface is dead — only
    // the centred text was tappable, so the Carbs button read as unresponsive
    // (same UIKit hit-testing trap fixed for CaptureErrorOverlay in 09aab63).
    private var carbsAction: some View {
        Button(action: onCarbs) {
            Text("Carbs")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.captureBackground)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityIdentifier("review.carbs")
    }

    private struct ClassRow {
        let name: String
        let displayName: String
        let carbsG: Int
    }

    // Sorted by carbs descending for a stable, meaningful order (matches Result).
    private var rows: [ClassRow] {
        record.macros.perClass
            .map { name, macro in
                ClassRow(name: name, displayName: Self.prettify(name), carbsG: Int(macro.carbsG.rounded()))
            }
            .sorted { $0.carbsG > $1.carbsG }
    }

    // Swatch colour from the id->colour table, keyed by the class' palette index.
    // Falls back to a neutral chrome tone if the name is not in the palette.
    private func swatchColour(for name: String) -> Color {
        guard let id = classId(for: name) else { return Color.captureChromeBG }
        let c = table.colour(forClassId: id)
        return Color(red: c.red, green: c.green, blue: c.blue)
    }

    private func classId(for name: String) -> Int? {
        if let i = palette.foodClasses.firstIndex(of: name) { return i }
        if let i = palette.liquidClasses.firstIndex(of: name) { return palette.foodClasses.count + i }
        return nil
    }

    // "white_rice" → "White rice".
    private static func prettify(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    private func loadPhoto() async {
        let assetID = record.photoAssetID
        guard !assetID.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false
        photo = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                continuation.resume(returning: result)
            }
        }
    }
}

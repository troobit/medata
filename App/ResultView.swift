import Photos
import Pipeline
import SwiftUI

// Three-state confidence band keyed off σ_meal per Req §9.2 / Decision 8.
// Boundaries: High σ ≥ 0.75, Moderate 0.60 ≤ σ < 0.75, Low σ < 0.60.
enum ConfidenceLevel: Equatable {
    case low
    case moderate
    case high

    static func forSigma(_ sigma: Float) -> ConfidenceLevel {
        if sigma >= 0.75 { return .high }
        if sigma >= 0.60 { return .moderate }
        return .low
    }

    var label: String {
        switch self {
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }

    var colour: Color {
        switch self {
        case .low: return .confidenceLow
        case .moderate: return .confidenceModerate
        case .high: return .confidenceHigh
        }
    }
}

enum ResultFormat {
    // §9.1: total meal carbohydrates in grams rounded to 1 g.
    static func carbsGrams(_ totalCarbsG: Float) -> Int {
        Int(totalCarbsG.rounded())
    }

    // §9.3: uncertain-estimate prompt shown when σ_meal < 0.60.
    static func showsUncertainPrompt(_ sigma: Float) -> Bool {
        sigma < 0.60
    }

    // Decision 42 / Req §23.3: placeholder banner shown only for meals stamped
    // by the Phase 1 dev-stub segmenter. Gated on the persisted record value,
    // NOT on the build flag, so a Phase 1 record viewed under a later Phase 3
    // build still surfaces the banner per design §3.5.
    static let devStubSegmenterSource = "dev_stub"
    static func showsPlaceholderBanner(segmenterSource: String) -> Bool {
        segmenterSource == devStubSegmenterSource
    }

    static let placeholderBannerCopy =
        "Placeholder estimate. The food recogniser is a development stub — the carbohydrate value is not a real measurement."
}

// Controls how `ResultView` is presented. The just-captured path (Photo tab)
// shows the "Retake" + "Done" action row; the history-detail path (Meals tab)
// hides it because the user got there from the list and the back button is
// the way out (UI Req §20.8 / §19.4).
enum ResultPresentation: Equatable {
    case justCaptured
    case historyDetail

    var showsActionRow: Bool {
        switch self {
        case .justCaptured: return true
        case .historyDetail: return false
        }
    }

    // Back-compat alias for the test-suite name introduced in v1.1 tab phase.
    var showsNewCapture: Bool { showsActionRow }
}

enum ResultViewLayout {
    // §20.12 Dynamic Type clamp at AX5: maximum display size 88pt to prevent
    // the carb total running off-screen.
    static let displayMinPoints: CGFloat = 56
    static let displayBasePoints: CGFloat = 72
    static let displayMaxPoints: CGFloat = 88

    static func displayPoints(_ sizeCategory: ContentSizeCategory) -> CGFloat {
        switch sizeCategory {
        case .extraSmall, .small, .medium, .large, .extraLarge:
            return displayBasePoints
        case .extraExtraLarge, .extraExtraExtraLarge:
            return min(displayBasePoints * 1.1, displayMaxPoints)
        default:
            return displayMaxPoints
        }
    }
}

// Post-capture result. Shows only the carb total and the confidence pill —
// no per-class breakdown, no clinical macros (Req §9.5, Decision 3).
// Visual treatment per `design-system/pages/photo-tab.md` §"ResultView"
// (Decision 16 / Req §20.2 / §20.8): full-bleed dimmed photo background, carb
// total at the `display` type-scale, confidence pill below, placeholder chip
// when `segmenterSource == "dev_stub"`.
struct ResultView: View {
    let record: MealRecord
    var mode: ResultPresentation = .justCaptured
    var onNewCapture: () -> Void = {}
    var onRetake: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var photo: UIImage?

    private var sigma: Float { record.confidence.sigmaMeal }
    private var showsPlaceholderChip: Bool { record.segmenterSource == "dev_stub" }
    private var displayPoints: CGFloat { ResultViewLayout.displayPoints(sizeCategory) }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 16) {
                Spacer()
                carbTotal
                ConfidencePill(sigmaMeal: sigma)
                if showsPlaceholderChip { placeholderChip }
                if ResultFormat.showsUncertainPrompt(sigma) { uncertainPrompt }
                Spacer()
                if mode.showsActionRow { actionRow }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.captureBackground)
        .ignoresSafeArea()
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPhoto() }
    }

    @ViewBuilder
    private var background: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .accessibilityHidden(true)
        } else {
            Color.captureBackground
        }
        LinearGradient(
            colors: [Color.captureScrim, Color.clear, Color.captureScrim],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var carbTotal: some View {
        Text("\(ResultFormat.carbsGrams(record.macros.totalCarbsG)) g")
            .font(.system(size: displayPoints, weight: .heavy, design: .default).monospacedDigit())
            .foregroundStyle(Color.captureChromeText)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .smooth, value: record.macros.totalCarbsG)
            .accessibilityIdentifier("result.carbsTotal")
    }

    private var placeholderChip: some View {
        Text("Placeholder estimate")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.placeholderBG, in: Capsule())
            .foregroundStyle(Color.placeholderFG)
            .accessibilityIdentifier("result.placeholderChip")
    }

    private var uncertainPrompt: some View {
        Text("This estimate is uncertain. Consider retaking the photo for a better result.")
            .font(.callout)
            .foregroundStyle(Color.captureChromeText.opacity(0.85))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
    }

    private var actionRow: some View {
        HStack(spacing: 16) {
            Button("Retake", action: onRetake)
                .font(.body.weight(.semibold))
                .frame(width: 120, height: 48)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.captureChromeText, lineWidth: 1.5))
                .foregroundStyle(Color.captureChromeText)
                .accessibilityIdentifier("result.retake")

            Button("Done", action: onNewCapture)
                .font(.body.weight(.semibold))
                .frame(width: 120, height: 48)
                .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(Color.captureBackground)
                .accessibilityIdentifier("result.newCapture")
        }
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
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                continuation.resume(returning: result)
            }
        }
        self.photo = image
    }
}

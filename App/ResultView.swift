import Photos
import Pipeline
import SwiftUI

// Four-state confidence band keyed off σ_meal per Req §9.2 / Decision 17
// (supersedes Decision 8's three-tier scheme). Boundaries:
//   High        σ ≥ 0.75
//   Moderate    0.50 ≤ σ < 0.75
//   Low         0.20 ≤ σ < 0.50
//   Very Low    σ < 0.20  (also triggers the result-view retake surface §9.3)
enum ConfidenceLevel: Equatable {
    case veryLow
    case low
    case moderate
    case high

    static func forSigma(_ sigma: Float) -> ConfidenceLevel {
        if sigma >= 0.75 { return .high }
        if sigma >= 0.50 { return .moderate }
        if sigma >= 0.20 { return .low }
        return .veryLow
    }

    var label: String {
        switch self {
        case .veryLow: return "Very Low"
        case .low: return "Low"
        case .moderate: return "Moderate"
        case .high: return "High"
        }
    }

    var colour: Color {
        switch self {
        case .veryLow: return .confidenceVeryLow
        case .low: return .confidenceLow
        case .moderate: return .confidenceModerate
        case .high: return .confidenceHigh
        }
    }
}

// nutrition5k-calibration Req 8.1 (Decisions 18–19): exactly one of these
// states per result; the liquid over-estimate flag (Req 8.2) is independent
// and additive, never part of this enum.
enum CalibrationBannerState: Equatable {
    case full
    case softened
    case suppressed
    case none       // standalone drink — no solid-food class contributes
}

enum ResultFormat {
    // §9.1: total meal carbohydrates in grams rounded to 1 g.
    static func carbsGrams(_ totalCarbsG: Float) -> Int {
        Int(totalCarbsG.rounded())
    }

    // §9.3 / Decision 17: Very-Low surface gate. Fires only when σ_meal
    // collapses below 0.20 — the prior σ < 0.60 prompt is superseded
    // (Decision 8 → Decision 17). Below this threshold the estimate may be
    // wrong by orders of magnitude and the user is offered Retake / Keep
    // as-is.
    static let veryLowSigmaThreshold: Float = 0.20
    static func showsVeryLowSurface(_ sigma: Float) -> Bool {
        sigma < veryLowSigmaThreshold
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

    // Req §7.2 / §7.3 (model-production) + nutrition5k-calibration Req 8.1
    // (Decision 18): the former showsUncalibratedBanner boolean is now one
    // three-state calibration-confidence signal, evaluated over the result's
    // contributing SOLID-food classes only — liquid classes carry no β and
    // never enter this evaluation. Distinct from the σ-keyed confidence pill
    // and from the `dev_stub` placeholder banner, which marks *fake* numbers.
    //
    //   full       — any solid class pooled/unity, or no per-class data at all
    //                (conservative pre-existing rule for old/degenerate records)
    //   softened   — every solid class calibrated, any not yet device-verified
    //   suppressed — every solid class calibrated AND device-verified
    //                (unreachable within this spec; flag-injection tested)
    //   none       — no solid class contributes (standalone drink): a stated
    //                rule, not the suppressed state reached by vacuous truth
    static func calibrationBanner(
        perClass: [String: PbPerClassMacros]
    ) -> CalibrationBannerState {
        if perClass.isEmpty { return .full }
        let solids = perClass.values.filter { !$0.isLiquid }
        if solids.isEmpty { return .none }
        if solids.contains(where: { $0.betaStatus != .calibrated }) { return .full }
        if solids.contains(where: { !$0.deviceVerified }) { return .softened }
        return .suppressed
    }

    // Req 8.2 (Decision 19): both liquid estimate paths over-read; the flag is
    // result-level, set by the estimation pipeline, and renders additively
    // alongside whichever calibration state 8.1 selected.
    static func showsLiquidOverEstimateFlag(_ macros: PbMacroResult) -> Bool {
        macros.liquidOverEstimate
    }

    static let uncalibratedBannerCopy =
        "Uncalibrated estimate — volume bias is not yet corrected, so this carbohydrate value is more likely too high than too low."

    static let softenedBannerCopy =
        "This estimate is population-calibrated — not yet verified on this device."

    static let liquidOverEstimateFlagCopy =
        "Includes a drink estimate that assumes a full serving, so it is more likely too high than too low."

    // Decision 17 / research Decisions 43–47 (UI side): the Very-Low surface
    // surfaces the per-stage angular error Δθ that contributed to the low
    // confidence. The persisted `PbConfidenceResult` carries
    // `deltaThetaNadirDeg` / `deltaThetaObliqueDeg` (proto fields 5/6, threaded
    // through `PipelineBridges.pbConfidenceResult`), so we report the larger of
    // the two stages. `deltaThetaObliqueDeg` is unset on the single-view path;
    // an unset record defaults to nadir 0 → "0° from target".
    static func maxDeltaThetaDeg(for record: MealRecord) -> Int {
        let confidence = record.confidence
        var maxDelta = confidence.deltaThetaNadirDeg
        if confidence.hasDeltaThetaObliqueDeg {
            maxDelta = max(maxDelta, confidence.deltaThetaObliqueDeg)
        }
        return Int(maxDelta.rounded())
    }
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
    // Decision 17: "Keep as-is" hides the Very-Low surface for the current
    // view session only — navigating away and back re-shows it (no persistent
    // dismissed flag). `@State` is per-instance, so this resets on each push.
    @State private var keepAsIsDismissed = false

    private var sigma: Float { record.confidence.sigmaMeal }
    private var showsPlaceholderChip: Bool { record.segmenterSource == "dev_stub" }
    // dev_stub numbers are fake — the placeholder chip owns that case — so the
    // real-but-over-reading surfaces (calibration banner, liquid flag) are
    // suppressed there to avoid a contradictory "real over-estimate" claim
    // over placeholder figures (design §3.5).
    private var calibrationBanner: CalibrationBannerState {
        showsPlaceholderChip
            ? .none
            : ResultFormat.calibrationBanner(perClass: record.macros.perClass)
    }
    private var showsLiquidFlag: Bool {
        !showsPlaceholderChip
            && ResultFormat.showsLiquidOverEstimateFlag(record.macros)
    }
    private var showsVeryLowSurface: Bool {
        ResultFormat.showsVeryLowSurface(sigma) && !keepAsIsDismissed
    }
    private var displayPoints: CGFloat { ResultViewLayout.displayPoints(sizeCategory) }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 16) {
                Spacer()
                carbTotal
                ConfidencePill(sigmaMeal: sigma)
                if showsPlaceholderChip { placeholderChip }
                switch calibrationBanner {
                case .full:      calibrationBannerCard(ResultFormat.uncalibratedBannerCopy)
                case .softened:  calibrationBannerCard(ResultFormat.softenedBannerCopy)
                case .suppressed, .none: EmptyView()
                }
                if showsLiquidFlag { liquidOverEstimateFlag }
                if showsVeryLowSurface { veryLowSurface }
                Spacer()
                if mode.showsActionRow { actionRow }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color.captureBackground)
        // Only the background layers (photo + gradient, below) ignore the safe
        // area for the full-bleed look. The ZStack itself must NOT — otherwise
        // its content and hit region extend under the system tab bar and
        // swallow tab taps, leaving the result screen unable to switch tabs.
        // The tab bar is not a takeover; it stays visible and reachable in both
        // .justCaptured and .historyDetail (bugfix/result-view-covers-tab-bar).
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
                .ignoresSafeArea()
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

    // Req §7.3 + nutrition5k-calibration Req 8.1/8.3: real-but-uncalibrated
    // honesty surface. The softened tier reuses this existing model-production
    // styling with the softened copy — presentation stays model-production-
    // owned. An up-arrow glyph plus the copy convey the upward
    // (over-estimating) volume bias. The orange `confidenceModerate` rounded
    // card is visually distinct from the yellow `dev_stub` placeholder capsule
    // (which marks fake numbers) and from the grey/red Very-Low surface below.
    private func calibrationBannerCard(_ copy: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.circle.fill")
            Text(copy)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.captureChromeText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.confidenceModerate.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result.uncalibratedBanner")
    }

    // Req 8.2: additive liquid over-estimate flag — renders alongside whatever
    // calibration state 8.1 selected, and stands alone for a standalone drink.
    // Same card treatment, distinct glyph, so the two surfaces read as siblings.
    private var liquidOverEstimateFlag: some View {
        HStack(spacing: 8) {
            Image(systemName: "cup.and.saucer.fill")
            Text(ResultFormat.liquidOverEstimateFlagCopy)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.captureChromeText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.confidenceModerate.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result.liquidOverEstimateFlag")
    }

    // Decision 17 / Req §9.3: surfaces below σ_meal < 0.20 with two-line
    // explanation + Retake / Keep as-is. The surface is in-session-only —
    // navigating away and back re-shows it. The meal is already persisted by
    // the capture pipeline, so "Keep as-is" only dismisses the surface; it
    // does not write any "dismissed" flag.
    private var veryLowSurface: some View {
        VStack(spacing: 12) {
            Text("This estimate may be wrong by orders of magnitude.")
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.captureChromeText)
                .multilineTextAlignment(.center)
            Text("Capture was at \(ResultFormat.maxDeltaThetaDeg(for: record))° from target.")
                .font(.caption)
                .foregroundStyle(Color.captureChromeText.opacity(0.75))
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Button("Retake", action: onRetake)
                    .font(.body.weight(.semibold))
                    .frame(width: 120, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.captureChromeText, lineWidth: 1.5))
                    .foregroundStyle(Color.captureChromeText)
                    .accessibilityIdentifier("result.veryLow.retake")

                Button("Keep as-is") { keepAsIsDismissed = true }
                    .font(.body.weight(.semibold))
                    .frame(width: 120, height: 44)
                    .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.captureBackground)
                    .accessibilityIdentifier("result.veryLow.keepAsIs")
            }
        }
        .padding(.horizontal, 24)
        .accessibilityIdentifier("result.veryLowSurface")
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

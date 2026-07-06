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

// Controls how `ResultView` is presented. Both paths now show the Adjust/Done
// action row (Req 6.7 v0.4 — historyDetail showing the row is a deliberate
// change from the tab-era design); the only difference is the ⋯ menu contents
// (Retake+Delete on a fresh capture, Delete only from history — Decision 17).
enum ResultPresentation: Equatable {
    case justCaptured
    case historyDetail
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

// Result screen (§6, design-system/pages/result.md). Hero carb total (original
// estimate) + four-tier confidence pill, a summary card (thumbnail, foods count,
// total mass, `CoFID + AFCD`), a per-food breakdown (name/mass/volume/carbs — no
// σ, Decision 16), dashed macro placeholders, and an Adjust/Done action row with
// a ⋯ menu (Retake+Delete fresh, Delete from history — Decision 17). Keeps the
// calibration banner, liquid flag, very-low surface, and placeholder chip.
struct ResultView: View {
    let record: MealRecord
    let store: any PersistenceStore
    var mode: ResultPresentation = .justCaptured
    // Adjust → Manual correction; Done → dismiss (capture) / pop (history);
    // Retake and Delete live in the ⋯ menu (Decision 17). All defaulted so the
    // capture stack and the Data / Trends history stacks both compile.
    var onAdjust: () -> Void = {}
    var onDone: () -> Void = {}
    var onRetake: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.sizeCategory) private var sizeCategory
    @State private var photo: UIImage?
    // Decision 19 / Req 7.3: the hero keeps the ORIGINAL estimate; a correction
    // only adds the `corrected` marker. Re-read on `eventsDidChange` while
    // visible, mirroring MealOverviewView (Decision 18).
    @State private var isCorrected = false
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
        ZStack(alignment: .bottom) {
            Color.captureBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    carbTotal
                    if isCorrected { correctedMarker }
                    ConfidencePill(sigmaMeal: sigma)
                    if showsPlaceholderChip { placeholderChip }
                    switch calibrationBanner {
                    case .full:      calibrationBannerCard(ResultFormat.uncalibratedBannerCopy)
                    case .softened:  calibrationBannerCard(ResultFormat.softenedBannerCopy)
                    case .suppressed, .none: EmptyView()
                    }
                    if showsLiquidFlag { liquidOverEstimateFlag }
                    if showsVeryLowSurface { veryLowSurface }
                    summaryCard
                    breakdown
                    macroPlaceholders
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                // Leave room so the pinned action row never overlaps content.
                .padding(.bottom, 96)
            }
            actionRow
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPhoto() }
        .task { await observeCorrections() }
    }

    // `corrected` marker (Req 7.3). Same string and capsule treatment as
    // MealOverviewView's marker, adapted to the Result screen's dark capture
    // palette. The hero total above it stays the original estimate.
    private var correctedMarker: some View {
        Text("corrected")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.captureChromeBG, in: Capsule())
            .foregroundStyle(Color.captureChromeText.opacity(0.7))
            .accessibilityIdentifier("result.correctedMarker")
    }

    // Hero: original estimate (§6.1) — the carb total is the persisted value and
    // is never replaced by a correction here (corrected totals surface in Data /
    // Overview). `g carbs` suffix per the copy inventory.
    private var carbTotal: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text("\(ResultFormat.carbsGrams(record.macros.totalCarbsG))")
                .font(.system(size: displayPoints, weight: .heavy, design: .default).monospacedDigit())
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .smooth, value: record.macros.totalCarbsG)
            Text("g carbs")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.captureChromeText.opacity(0.7))
        }
        .foregroundStyle(Color.captureChromeText)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("result.carbsTotal")
    }

    // Summary card (§6.3): thumbnail (with §6.8 fallback), foods count, total
    // mass, and the food-database edition.
    private var summaryCard: some View {
        HStack(spacing: 16) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                Text("\(foodCount) foods")
                    .font(.headline)
                    .foregroundStyle(Color.captureChromeText)
                Text("\(totalMassGrams) g total")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Color.captureChromeText.opacity(0.8))
                Text("CoFID + AFCD")
                    .font(.caption)
                    .foregroundStyle(Color.captureChromeText.opacity(0.6))
            }
            Spacer()
        }
        .padding(16)
        .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("result.summaryCard")
    }

    // §6.8 fallback: neutral placeholder when the photo asset is unavailable.
    private var thumbnail: some View {
        Group {
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.captureChromeBG
                    Image(systemName: "fork.knife")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.captureChromeText.opacity(0.5))
                }
                .accessibilityIdentifier("result.thumbnailFallback")
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // Per-food breakdown (§6.4): name, mass, volume, carbs — no σ (Decision 16).
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per food")
                .font(.headline)
                .foregroundStyle(Color.captureChromeText)
            ForEach(perClassRows, id: \.name) { row in
                HStack {
                    Text(row.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.captureChromeText)
                    Spacer()
                    Text("\(row.massG) g · \(row.volumeCm3) cm³ · \(row.carbsG) g carbs")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.captureChromeText.opacity(0.75))
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("result.breakdown")
    }

    // Dashed, disabled macro placeholders that hold layout space (§6.5).
    private var macroPlaceholders: some View {
        HStack(spacing: 12) {
            macroPlaceholder("Protein — soon")
            macroPlaceholder("Fat — soon")
        }
    }

    private func macroPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Color.captureChromeText.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        Color.captureChromeText.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                    )
            )
    }

    private var foodCount: Int { record.macros.perClass.count }
    private var totalMassGrams: Int {
        Int(record.macros.perClass.values.reduce(Float(0)) { $0 + $1.massG }.rounded())
    }

    private struct PerClassRow {
        let name: String
        let displayName: String
        let massG: Int
        let volumeCm3: Int
        let carbsG: Int
    }

    // Sorted by carbs descending for a stable, meaningful order.
    private var perClassRows: [PerClassRow] {
        record.macros.perClass
            .map { name, macro in
                PerClassRow(
                    name: name,
                    displayName: Self.prettify(name),
                    massG: Int(macro.massG.rounded()),
                    volumeCm3: Int(macro.volumeCm3.rounded()),
                    carbsG: Int(macro.carbsG.rounded())
                )
            }
            .sorted { $0.carbsG > $1.carbsG }
    }

    // "white_rice" → "White rice".
    private static func prettify(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
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
                Button(action: onRetake) {
                    Text("Retake")
                        .font(.body.weight(.semibold))
                        .frame(width: 120, height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.captureChromeText, lineWidth: 1.5))
                        .foregroundStyle(Color.captureChromeText)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("result.veryLow.retake")

                Button { keepAsIsDismissed = true } label: {
                    Text("Keep as-is")
                        .font(.body.weight(.semibold))
                        .frame(width: 120, height: 44)
                        .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Color.captureBackground)
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .accessibilityIdentifier("result.veryLow.keepAsIs")
            }
        }
        .padding(.horizontal, 24)
        .accessibilityIdentifier("result.veryLowSurface")
    }

    // §6.6/6.7 (Decision 17): Adjust (bordered) + Done (prominent), shown in both
    // presentations (historyDetail now shows the action row — deliberate). The ⋯
    // menu carries Retake + Delete on a fresh capture, Delete only from history.
    private var actionRow: some View {
        HStack(spacing: 12) {
            Button(action: onAdjust) {
                Text("Adjust")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.captureChromeText, lineWidth: 1.5))
                    .foregroundStyle(Color.captureChromeText)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityIdentifier("result.adjust")

            Button(action: onDone) {
                Text("Done")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.captureBackground)
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityIdentifier("result.done")

            Menu {
                if mode == .justCaptured {
                    Button("Retake", action: onRetake)
                }
                Button("Delete", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 48, height: 48)
                    .background(Color.captureChromeBG, in: RoundedRectangle(cornerRadius: 12))
                    .foregroundStyle(Color.captureChromeText)
            }
            .accessibilityLabel("More")
            .accessibilityIdentifier("result.menu")
        }
    }

    private func loadPhoto() async {
        // Shared with Data / Meal overview via the extracted loader (§6.8).
        self.photo = await MealPhotoLoader.loadImage(assetID: record.photoAssetID)
    }

    // Mirror of MealOverviewView.observeCorrections (Decision 18): refresh once
    // on appear, then whenever a correction lands while the view is visible.
    private func observeCorrections() async {
        await refreshCorrected()
        for await _ in store.eventsDidChange {
            await refreshCorrected()
        }
    }

    private func refreshCorrected() async {
        let corrections = (try? await store.corrections(for: record.id)) ?? []
        isCorrected = !corrections.isEmpty
    }
}

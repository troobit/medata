import Photos
import SwiftUI
import UIKit

// The shared meal readouts (specs/ui/shared-meal-components Req 3): the carb
// amount pair, the corrected marker, and the recorded-suggestion line render
// identically on every surface that shows them because they are written here
// once. The block LAYOUTS stay surface-owned — the overview and review rows
// are leading-aligned baselines with a trailing pill, the result hero is a
// centred stack — so the shared unit is the content, not the container
// (decision_log.md Decision 3).

// Which token family a surface draws its text from. Under
// specs/ui/unified-dark-theme both resolve on black; the distinction keeps
// each token's provenance per surface (capture chrome vs grouped semantic).
enum MealPalette {
    case capture
    case grouped

    var primary: Color {
        switch self {
        case .capture: Color.captureChromeText
        case .grouped: Color.textPrimary
        }
    }

    var secondary: Color {
        switch self {
        case .capture: Color.captureChromeText.opacity(0.75)
        case .grouped: Color.textSecondary
        }
    }

    var markerBackground: Color {
        switch self {
        case .capture: Color.captureChromeBG
        case .grouped: Color.surfaceElevated
        }
    }
}

// The `corrected` capsule — one implementation for its four sites (Req 3.2):
// meal overview, meal review, result, and the Records meal row.
struct CorrectedMarker: View {
    let palette: MealPalette
    let identifier: String

    var body: some View {
        Text("corrected")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(palette.markerBackground, in: Capsule())
            .foregroundStyle(palette.secondary)
            .accessibilityIdentifier(identifier)
    }
}

// The numeral + "g carbs" pair, parameterised by palette and numeral size
// (Req 3.1). Every surface's big carb figure is this view.
struct CarbAmountText: View {
    let carbs: Int
    let pointSize: CGFloat
    let palette: MealPalette
    /// The value whose change drives the numeric roll.
    var animates: Double?
    /// Suffix treatment differs by surface: subheadline on the compact
    /// overview row, title3 on the capture-family heroes.
    var suffixFont: Font = .subheadline.weight(.semibold)
    var spacing: CGFloat = 6

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: spacing) {
            Text("\(carbs)")
                .font(.system(size: pointSize, weight: .heavy).monospacedDigit())
                .foregroundStyle(palette.primary)
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .smooth, value: animates ?? 0)
            Text("g carbs")
                .font(suffixFont)
                .foregroundStyle(palette.secondary)
        }
    }
}

// The dose line for history surfaces (insulin-dosing Req 6.10/6.11): the
// suggestion RECOMPUTED for the meal's own instant — its band, its window —
// from recorded events and the settings in force at read time. No recorded row
// exists to read (Decision 18), so a later ratio change re-renders past meals
// at the new ratio; that is accepted, the readout being a present-tense
// statement of the rule applied to that meal.
//
// What was actually injected against a meal, paired by the ±45-minute window
// over insulin events and never by a stored link.
//
// Since 2026-08-28 this line no longer carries the SUGGESTION: that moved into
// the dose pill at the top of the surface, where its colour carries the
// estimate's confidence. Rendering it here as well would have shown the same
// number twice on one screen, in two registers, saying two different things.
enum DoseHistoryLine {
    static func runs(_ readout: DoseReadout?, givenUnits: Double?) -> [MiddleDotLine.Run] {
        guard readout != nil, let givenUnits else { return [] }
        return [
            MiddleDotLine.Run(
                id: "result.doseGiven",
                text: "given \(DoseReadout.wholeUnitsLabel(givenUnits))",
                animates: givenUnits
            )
        ]
    }

    static func spokenLine(_ readout: DoseReadout?, givenUnits: Double?) -> String? {
        guard readout != nil, let givenUnits else { return nil }
        return "given \(spokenUnits(givenUnits))"
    }

    private static func spokenUnits(_ units: Double) -> String {
        let rounded = (units * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded)) units" }
        return String(format: "%.1f units", rounded)
    }
}

// Photo resolution for the meal surfaces (Meal-overview and Result resolve
// the captured photo identically — design-handoff-00 §6.8 fallback; relocated
// from the retired MealHistoryModel.swift). `nonisolated` so callers on any
// actor can await it; the Photos callback resumes a single checked
// continuation.
//
// `.highQualityFormat` delivers exactly one callback: `.opportunistic` would
// invoke the handler twice (a fast degraded image then the full one), which
// crashes a checked continuation with "resumed more than once".
enum MealPhotoLoader {
    nonisolated static func loadImage(
        assetID: String,
        targetSize: CGSize = PHImageManagerMaximumSize
    ) async -> UIImage? {
        guard !assetID.isEmpty else { return nil }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil)
        guard let asset = assets.firstObject else { return nil }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isSynchronous = false
        options.isNetworkAccessAllowed = false
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { result, _ in
                continuation.resume(returning: result)
            }
        }
    }
}

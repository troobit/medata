import Persistence
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

// The recorded-suggestion line for history surfaces (insulin-dosing
// Req 6.10/6.11): the ledger row's values verbatim, never a recomputation —
// the band, ratio and insulin-on-board belong to the moment the number was
// produced. "suggested" labels a past hypothesis (design-direction §6.3) and
// is not counsel. A row that was a suppression, or no row at all, renders
// nothing (Req 6.6).
enum RecordedSuggestion {
    static func line(_ row: DoseSuggestionRecord?) -> String? {
        guard let row, let rounded = row.roundedUnits else { return nil }
        var line = "suggested \(DoseReadout.wholeUnitsLabel(rounded))"
        line += " · \(DoseReadout.gramsPerUnitLabel(row.crGramsPerUnit))"
        if let given = row.givenUnits {
            line += " · given \(DoseReadout.wholeUnitsLabel(given))"
        }
        return line
    }

    // VoiceOver form: "12 U" spoken verbatim reads as "twelve you" and
    // "5 g/U" as "g slash u" (ui-ux review 2026-08-25).
    static func spokenLine(_ row: DoseSuggestionRecord?) -> String? {
        guard let row, let rounded = row.roundedUnits else { return nil }
        let ratio = row.crGramsPerUnit
        let ratioText = ratio == ratio.rounded()
            ? String(Int(ratio)) : String(format: "%.1f", ratio)
        var line = "suggested \(spokenUnits(rounded)) at \(ratioText) grams per unit"
        if let given = row.givenUnits {
            line += ", given \(spokenUnits(given))"
        }
        return line
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

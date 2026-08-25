import Pipeline
import SwiftUI

// Shared three-tier confidence pill rendering (UI Req §9.2 / §19.2 / Decision 8
// / Decision 16). Used by `ResultView` and `MealRow` so the visual treatment
// stays identical between the just-captured surface and the meal-history row.
//
// The icon next to the label satisfies the `color-not-only` accessibility rule
// — a colour-blind user can still distinguish High / Moderate / Low without
// relying on hue alone.
struct ConfidencePill: View {
    let sigmaMeal: Float

    private var level: ConfidenceLevel { .forSigma(sigmaMeal) }

    var body: some View {
        Label {
            Text(level.label)
                .font(.body.weight(.semibold))
        } icon: {
            Image(systemName: level.iconName)
        }
        .labelStyle(.titleAndIcon)
        // Dark-on-fill for the bright tiers (white on the accent green is
        // ~1.9:1 and on orange ~2.8:1 — both under MASTER.md's ≥4.5:1
        // budget; the accent-filled controls already pair captureBackground
        // text with bright fills). Very Low's desaturated grey is the one
        // fill dark enough to need white.
        .foregroundStyle(level == .veryLow ? Color.captureChromeText : Color.captureBackground)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 28)
        .background(level.colour.opacity(0.85), in: Capsule())
        .accessibilityLabel("Confidence \(level.label)")
        .accessibilityIdentifier("confidencePill.\(level.accessibilityToken)")
    }
}

extension ConfidenceLevel {
    // SF Symbol per design-system/pages/photo-tab.md §"ResultView" + the
    // `color-not-only` rule referenced in MASTER.md. Decision 17: Very Low
    // gets a desaturated `minus.circle.fill` so it reads as "essentially
    // worthless" rather than the louder Low-tier alarm icon.
    var iconName: String {
        switch self {
        case .high: return "checkmark.seal.fill"
        case .moderate: return "exclamationmark.triangle.fill"
        case .low: return "xmark.octagon.fill"
        case .veryLow: return "minus.circle.fill"
        }
    }

    var accessibilityToken: String {
        switch self {
        case .high: return "high"
        case .moderate: return "moderate"
        case .low: return "low"
        case .veryLow: return "veryLow"
        }
    }
}

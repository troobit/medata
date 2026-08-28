import Pipeline
import SwiftUI

// Shared confidence rendering. `DosePill` below is what the capture surfaces
// now show; `ConfidencePill` renders the level as its own named pill and is
// kept for the surfaces that report confidence as the subject rather than as
// a property of a dose.
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


// The dose, in the slot the confidence pill used to hold (insulin-dosing
// design-direction §2.2, settled on device 2026-08-28).
//
// The trade this makes: a confidence tier is something a person reads off the
// plate faster than the model computes it, so spending the most prominent
// chrome on the model's own self-assessment bought little. The dose is the
// number that is acted on, and it is the one the reader cannot derive by
// looking. So the dose takes the slot, and confidence becomes the COLOUR of
// that slot — the accuracy signal now attaches to the thing it qualifies
// rather than sitting beside it, and the tier is named in words in the
// working, one tap away.
//
// Metrics are ConfidencePill's exactly — same padding, same `minHeight: 28`,
// same capsule — because this view replaces that one in place. Nothing above
// the scroll boundary moves, so `specs/ui/meal-review` Req 6.6 (the plate
// control visible without scrolling) is untouched by construction.
struct DosePill: View {
    let unitsLabel: String
    let sigmaMeal: Float
    let animates: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var level: ConfidenceLevel { .forSigma(sigmaMeal) }

    var body: some View {
        Label {
            Text(unitsLabel)
                .font(.body.monospacedDigit().weight(.semibold))
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .smooth, value: animates)
        } icon: {
            Image(systemName: "syringe")
        }
        .labelStyle(.titleAndIcon)
        // Dark-on-fill for the bright tiers, white on Very Low's desaturated
        // grey — the same contrast split ConfidencePill makes, for the same
        // MASTER.md >= 4.5:1 reason.
        .foregroundStyle(level == .veryLow ? Color.captureChromeText : Color.captureBackground)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(minHeight: 28)
        .background(level.colour.opacity(0.85), in: Capsule())
        // One spoken element: the quantity, then what the colour says, because
        // the fill carries the tier and VoiceOver cannot see a fill.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(unitsLabel), estimate confidence \(level.label)")
        .accessibilityHint("Shows the working")
        .accessibilityIdentifier("dosePill.\(level.accessibilityToken)")
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

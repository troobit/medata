import SwiftUI

// The middle-dot line (specs/data/insulin-dosing design-direction §2.2).
//
// It no longer carries a dose. As of 2026-08-28 the dose renders as `DosePill`
// in the slot the confidence pill held, so what is left on these lines is the
// measured and reported material around it — the plate mass, the units
// actually given. Those stay in the DERIVED register: same font, same colour,
// same size, never accent-coloured, never filled.
//
// Segments are joined by " · " (U+00B7) at its own opacity. The construction
// is an HStack of Text runs rather than a concatenation, because design.md
// requires the line height to be unchanged AND every numeral to keep its own
// `.contentTransition(.numericText())` — concatenated Text cannot carry a
// per-run content transition, and a single Text cannot carry a per-run
// opacity. An HStack of runs with an interleaved separator run satisfies both;
// the separator is still a Text run, not a divider view.
struct MiddleDotLine: View {
    struct Run {
        let id: String
        let text: String
        var emphasised = false
        /// The value whose change drives the numeric roll, when the run holds
        /// a number.
        var animates: Double?
    }

    let runs: [Run]
    let textColour: Color
    let separatorColour: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(runs.enumerated()), id: \.offset) { index, run in
                if index > 0 {
                    Text(" · ")
                        .foregroundStyle(separatorColour)
                }
                Text(run.text)
                    .fontWeight(run.emphasised ? .semibold : .regular)
                    .foregroundStyle(textColour)
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .smooth, value: run.animates ?? 0)
                    .accessibilityIdentifier(run.id)
            }
        }
        .font(.subheadline.monospacedDigit())
        .lineLimit(1)
        .minimumScaleFactor(0.9)
    }
}

// The meal-review total row's second line (design-direction §2.1–2.3).
//
// Mass only, since 2026-08-28: the dose moved into the pill that used to hold
// the confidence tier, so this line no longer carries two quantities that look
// alike but are not — a measured mass and a dose derived from it. What is left
// is the figure a kitchen scale can be held against.
struct MealTotalSecondLine: View {
    let massG: Double

    private var mass: Int { Int(massG.rounded()) }

    var body: some View {
        Text("≈ \(mass) g on plate")
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(Color.captureChromeText.opacity(0.75))
            .lineLimit(1)
            .minimumScaleFactor(0.9)
            .accessibilityLabel("\(mass) grams on plate")
            .accessibilityIdentifier("review.massLine")
    }
}

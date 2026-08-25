import SwiftUI

// The middle-dot line — the one shape a dose suggestion ever takes
// (specs/data/insulin-dosing design-direction §2.2).
//
// A dose suggestion is permanently in the DERIVED register: same font, same
// colour and same size as the number beside it, never accent-coloured, never
// filled, never a control. On these screens the accent colour already means
// "this button writes a row", so a number that is not accent-coloured visibly
// cannot be an instruction. The distinction is structural, and that is what
// keeps the developer-phase no-disclaimer rule intact without a word of copy.
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
// The line's axis is TIME: what is on the plate now, then what to inject now.
// Segments accrete left to right in the order their moment arrives, which is
// why a later second-spike suggestion needs no redesign — it is the next
// segment on a line that was always a timeline.
//
// The divisor rides along. design-direction §10 leaves the choice between bare
// `12 U` and `12 U · 5 g/U` open for a device pass; this build takes the
// data-forward branch, because the ratio is the parameter the whole feature
// exists to measure and putting it on screen at every meal is how it stops
// being invisible. The shed order below makes that additive rather than
// costly: the ratio is the FIRST thing dropped when the line tightens, so at
// any width where it does not fit the line is byte-identical to design.md's
// `≈ 214 g on plate · 12 U`. Reverting to the bare form permanently is
// deleting one candidate from `ViewThatFits`.
struct MealTotalSecondLine: View {
    let massG: Double
    let readout: DoseReadout?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var mass: Int { Int(massG.rounded()) }

    private var doseRun: MiddleDotLine.Run? {
        guard let readout else { return nil }
        return MiddleDotLine.Run(
            id: "review.doseSuggestion",
            text: readout.unitsLabel,
            emphasised: true,
            animates: Double(readout.units)
        )
    }

    private var ratioRun: MiddleDotLine.Run? {
        guard let readout else { return nil }
        return MiddleDotLine.Run(
            id: "review.doseRatio",
            text: readout.ratioLabel,
            animates: readout.gramsPerUnit
        )
    }

    private func massRun(_ text: String) -> MiddleDotLine.Run {
        MiddleDotLine.Run(id: "review.massLine", text: text, animates: massG)
    }

    private var spokenLabel: String {
        guard let readout else { return "\(mass) grams on plate" }
        return "\(mass) grams on plate. \(readout.spokenUnits) at \(readout.spokenRatio)."
    }

    private func line(_ runs: [MiddleDotLine.Run?]) -> some View {
        MiddleDotLine(
            runs: runs.compactMap { $0 },
            textColour: Color.captureChromeText.opacity(0.75),
            separatorColour: Color.captureChromeText.opacity(0.45)
        )
    }

    var body: some View {
        if let doseRun {
            // The ratio is the FIRST thing shed: at any width where it does
            // not fit, the line is byte-identical to design.md's
            // `≈ 214 g on plate · 12 U` and then follows design-direction
            // §2.3's shed order (words before numbers, the dose never).
            ViewThatFits(in: .horizontal) {
                line([massRun("≈ \(mass) g on plate"), doseRun, ratioRun])
                line([massRun("≈ \(mass) g on plate"), doseRun])
                line([massRun("≈ \(mass) g"), doseRun])
                line([massRun("\(mass) g"), doseRun])
                line([doseRun])
            }
            // The combined row label gains a clause naming the quantity,
            // because VoiceOver has no adjacency to read the relationship
            // from. Naming a number in a spoken label is labelling, not
            // counsel — the rule bars instruction, not nouns.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spokenLabel)
        } else {
            // No suggestion is an absent segment, not a placeholder: the line
            // is exactly what ships today.
            Text("≈ \(mass) g on plate")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Color.captureChromeText.opacity(0.75))
                .contentTransition(reduceMotion ? .identity : .numericText())
                .animation(reduceMotion ? nil : .smooth, value: massG)
                .accessibilityIdentifier("review.massLine")
        }
    }
}

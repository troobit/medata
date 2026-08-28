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
        /// SF Symbol naming what kind of quantity the run holds, drawn before
        /// the numeral. On the dose run this is what separates a derived dose
        /// from the estimate it was derived from (design-direction §2.2).
        var symbol: String?
        /// Marks the run as opening its working on tap (Req 6.12). Rendered as
        /// a dotted underline: the affordance has to be visible, and a dotted
        /// rule is the one mark that adds no glyph, no colour and no height.
        var inspectable = false
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
                HStack(spacing: 3) {
                    if let symbol = run.symbol {
                        Image(systemName: symbol)
                            .imageScale(.small)
                            .foregroundStyle(textColour)
                            // The spoken label is composed on the whole line,
                            // so the glyph must not add a second announcement.
                            .accessibilityHidden(true)
                    }
                    Text(run.text)
                        .fontWeight(run.emphasised ? .semibold : .regular)
                        .foregroundStyle(textColour)
                        .underline(run.inspectable, pattern: .dot)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .animation(reduceMotion ? nil : .smooth, value: run.animates ?? 0)
                        .accessibilityIdentifier(run.id)
                }
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
// The divisor does NOT ride along. design-direction §10 left the choice
// between bare `12 U` and `12 U · 5 g/U` open for a device pass and asked for
// it to be decided on device with a real meal on screen; the 2026-08-28
// session decided bare, so the line is design.md's
// `≈ 214 g on plate · 12 U` at every width. The ratio is one tap away in the
// working, which is where a reader who wants it is already going.
//
// The dose segment carries the syringe glyph and a dotted underline. The
// glyph says what kind of quantity it is without the reader decoding `U`, and
// it is what stops the dose reading as a third peer measurement beside the
// mass — the mass is measured, the dose is derived FROM it. The underline is
// the only thing on the line that says the working exists.
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
            animates: Double(readout.units),
            symbol: "syringe",
            inspectable: true
        )
    }

    private func massRun(_ text: String) -> MiddleDotLine.Run {
        MiddleDotLine.Run(id: "review.massLine", text: text, animates: massG)
    }

    // Parity with the line: the ratio left the screen, so it leaves the
    // spoken label too. A VoiceOver reader who wants it takes the same route
    // a sighted one does — the "Show working" action on this row.
    private var spokenLabel: String {
        guard let readout else { return "\(mass) grams on plate" }
        return "\(mass) grams on plate. \(readout.spokenUnits)."
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
            // design-direction §2.3's shed order: words before numbers, the
            // dose never.
            ViewThatFits(in: .horizontal) {
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

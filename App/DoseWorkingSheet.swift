import Dosing
import SwiftUI

// The working, one tap away (specs/data/insulin-dosing Req 6.12, Decisions
// 17/18).
//
// Tapping the dose readout on any surface — the review line, the manual-entry
// line, the history detail — opens the calculation behind the number:
//
//     60 g ÷ 5 g/U = 12.0 U
//     − 1.4 U, for insulin on board
//     = 10.6 U
//     → 11 U
//
// The base line, one line per reduction, the unrounded result, the rounding
// step. Because `reductionUnits` is capped at `baseUnits` in the suggester,
// the lines sum exactly at every step — never a hidden jump.
//
// Reveal-not-act: nothing is written, no control appears, dismissal returns
// the untouched surface. Arithmetic labelling only — no advice, no range, no
// confidence (Req 6.8).

/// The lines, as text. Pure, so live surfaces and the history recompute render
/// the same working from the same `SuggestedDose` (Req 6.11).
enum DoseWorking {

    struct Line: Identifiable {
        let id: String
        let text: String
        let spoken: String
    }

    static func lines(_ readout: DoseReadout) -> [Line] {
        let dose = readout.dose
        var lines: [Line] = [
            Line(
                id: "working.base",
                text: "\(grams(readout.carbsG)) ÷ \(ratio(readout.gramsPerUnit)) "
                    + "= \(decimalUnits(dose.baseUnits))",
                spoken: "\(grams(readout.carbsG)) divided by "
                    + "\(spokenRatio(readout.gramsPerUnit)) "
                    + "is \(spokenDecimalUnits(dose.baseUnits))"
            )
        ]
        // A zero reduction renders no line: there is nothing to subtract, and
        // an explicit "− 0 U" would state a term that did not apply.
        if dose.reductionUnits > 0 {
            lines.append(
                Line(
                    id: "working.reduction.iob",
                    text: "− \(decimalUnits(dose.reductionUnits)), for insulin on board",
                    spoken: "minus \(spokenDecimalUnits(dose.reductionUnits)), "
                        + "for insulin on board"
                )
            )
            lines.append(
                Line(
                    id: "working.exact",
                    text: "= \(decimalUnits(dose.exactUnits))",
                    spoken: "is \(spokenDecimalUnits(dose.exactUnits))"
                )
            )
        }
        lines.append(
            Line(
                id: "working.rounded",
                text: "→ \(DoseReadout.wholeUnitsLabel(dose.roundedUnits))",
                spoken: "rounds to \(readout.spokenUnits)"
            )
        )
        return lines
    }

    /// Grams, to the nearest whole gram — the figure the surface already shows.
    private static func grams(_ value: Double) -> String {
        "\(Int(value.rounded())) g"
    }

    /// The base line states the divisor to one decimal too — `5.0 g/U`, not
    /// the readout line's shorter `5 g/U`: here it is a term in an equation
    /// that must be checkable against the figures either side of it.
    private static func ratio(_ value: Double) -> String {
        String(format: "%.1f g/U", value)
    }

    private static func spokenRatio(_ value: Double) -> String {
        String(format: "%.1f grams per unit", value)
    }

    /// The base, reduction and unrounded-result terms state at least one
    /// decimal place, so the rounding error stays inspectable (Req 5.3). They
    /// are arithmetic facts, not dose figures, so the whole-unit rule of
    /// Req 5.1 does not govern them.
    private static func decimalUnits(_ value: Double) -> String {
        String(format: "%.1f U", value)
    }

    private static func spokenDecimalUnits(_ value: Double) -> String {
        String(format: "%.1f units", value)
    }
}

struct DoseWorkingSheet: View {
    let readout: DoseReadout

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(DoseWorking.lines(readout)) { line in
                    Text(line.text)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(Color.textPrimary)
                        .accessibilityLabel(line.spoken)
                        .accessibilityIdentifier(line.id)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(Color.surfacePrimary)
            .navigationTitle("Working")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("working.done")
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

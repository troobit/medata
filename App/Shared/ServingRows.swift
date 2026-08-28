import Foods
import SwiftUI

// The per-food serving-adjustment controls, shared verbatim between the two
// surfaces that render them — MealReviewView (capture review) and ResultView
// (Records/Graph history) — per specs/ui/shared-meal-components Req 1. Each
// surface keeps its own state backing through the callbacks (Req 1.2):
// review routes to MealReviewModel.setAmount, result to its pendingGrams
// dictionary; only the rendering and arithmetic live here. Accessibility
// identifiers are parameterised by the row's full prefix (`result.row.<id>` /
// `review.row.<id>`) so both surfaces' ids are byte-identical to before
// (Req 1.3).

// The plate-fraction quick control's stops (serving-adjust PRD, iOS Req 2).
// Moved here from ResultView.swift, unchanged.
enum PlateFraction: CaseIterable {
    case all, threeQuarters, half, quarter

    var factor: Double {
        switch self {
        case .all: return 1
        case .threeQuarters: return 0.75
        case .half: return 0.5
        case .quarter: return 0.25
        }
    }

    var label: String {
        switch self {
        case .all: return "All"
        case .threeQuarters: return "¾"
        case .half: return "½"
        case .quarter: return "¼"
        }
    }

    var identifier: String {
        switch self {
        case .all: return "all"
        case .threeQuarters: return "threeQuarters"
        case .half: return "half"
        case .quarter: return "quarter"
        }
    }
}

// Step arithmetic and the gram-keypad sanitiser — one implementation of the
// numbers both surfaces move (Req 1.1).
enum ServingStepLogic {
    static let fallbackStepGrams = 10.0
    static let maxRowGrams = 5000.0

    // Serving-unit step where one exists; the shipped gram fallback otherwise
    // (serving-adjust Req 6.1, 6.2). Not capped at the measured volume.
    static func stepped(from current: Double, serving: SolidServing?, direction: Double) -> Double {
        let stepGrams: Double
        if let serving {
            stepGrams = serving.step * serving.gramsPerUnit
        } else {
            stepGrams = fallbackStepGrams
        }
        return min(maxRowGrams, max(0, current + direction * stepGrams))
    }

    // Mass keypad sanitiser (BenchmarkMealEditorSheet.clampedGrams precedent):
    // strips non-digits, caps at 4 digits, clamps at `maxRowGrams`. Idempotent
    // for any whole-gram value within the cap, so programmatic field writes
    // survive the onChange round-trip without corrupting pending state.
    static func clampedRowGrams(_ text: String) -> String {
        let digits = String(text.filter(\.isNumber).prefix(4))
        guard let value = Int(digits) else { return "" }
        return String(min(value, Int(maxRowGrams)))
    }

    static func unitLabel(_ serving: SolidServing, count: Double) -> String {
        ServingMath.unitLabel(count: count, singular: serving.unitSingular, plural: serving.unitPlural)
    }
}

// The amount, serving-first: "≈ 1½ potatoes · 87 g" for a class with a
// serving unit, plain "120 g" for the gram fallback. A Button (not the
// steppers) so tapping it opens the gram reveal; shape inside the label
// (the dead-pill trap, ui-capture-flow.md).
struct ServingAmountButton: View {
    let grams: Double
    let serving: SolidServing?
    /// Full accessibility prefix for the row, e.g. `result.row.pasta`.
    let idPrefix: String
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let serving {
                    let count = ServingMath.displayHalfUnits(
                        ServingMath.servings(grams: grams, gramsPerUnit: serving.gramsPerUnit)
                    )
                    Text("≈ \(ServingMath.halfUnitText(count)) \(ServingStepLogic.unitLabel(serving, count: count))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.captureChromeText)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                    Text("\(Int(grams.rounded())) g")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.captureChromeText.opacity(0.6))
                        .contentTransition(reduceMotion ? .identity : .numericText())
                } else {
                    Text("\(Int(grams.rounded())) g")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Color.captureChromeText)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                }
            }
            .multilineTextAlignment(.leading)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("\(idPrefix).amount")
    }
}

// The gram reveal (serving-adjust iOS Req 3): an editable gram value, two-way
// bound with the serving readout — typing grams re-renders the serving
// equivalence live, and stepping while editing rewrites the field. The
// surface owns the text state and the commit; the clamp is shared.
struct ServingGramEditor: View {
    @Binding var text: String
    let grams: Double
    let serving: SolidServing?
    let idPrefix: String
    var focus: FocusState<Bool>.Binding
    /// Called with each clamped whole-gram value as it is typed.
    let onGrams: (Double) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            TextField("0", text: $text)
                .keyboardType(.numberPad)
                .focused(focus)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color.captureChromeText)
                .frame(width: 52)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.captureBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: Metrics.cornerChip))
                .onChange(of: text) { _, newValue in
                    let clamped = ServingStepLogic.clampedRowGrams(newValue)
                    if clamped != newValue { text = clamped }
                    // Empty is a transient typing state — keep the last value.
                    if let grams = Int(clamped) {
                        onGrams(Double(grams))
                    }
                }
                .accessibilityIdentifier("\(idPrefix).gramField")
            Text("g")
                .font(.caption)
                .foregroundStyle(Color.captureChromeText.opacity(0.6))
            if let serving {
                let count = ServingMath.displayHalfUnits(
                    ServingMath.servings(grams: grams, gramsPerUnit: serving.gramsPerUnit)
                )
                Text("≈ \(ServingMath.halfUnitText(count)) \(ServingStepLogic.unitLabel(serving, count: count))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.captureChromeText.opacity(0.6))
                    .contentTransition(reduceMotion ? .identity : .numericText())
            }
        }
    }
}

// Compact ± step control. Sizing and `contentShape` live INSIDE the Button
// label — the dead-surface trap (ui-capture-flow.md). Both surfaces converge
// on the 44 pt hit target (shared-meal-components Req 1.4: the larger of the
// two shipped sizes).
struct ServingStepButton: View {
    let symbol: String
    let enabled: Bool
    let idPrefix: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color.captureBackground.opacity(0.6), in: Circle())
                .foregroundStyle(Color.captureChromeText.opacity(enabled ? 1 : 0.3))
                .contentShape(Circle())
        }
        .disabled(!enabled)
        .accessibilityLabel(symbol == "plus" ? "Increase amount" : "Decrease amount")
        .accessibilityIdentifier("\(idPrefix).\(symbol)")
    }
}

// One stop of a plate-fraction control. The two surfaces keep their own
// container rows (selection semantics differ: review persists a scale through
// the model, result derives the highlight from its rows) and their own
// metrics, passed in here so the stop itself is written once.
struct PlateFractionButton: View {
    let fraction: PlateFraction
    let isActive: Bool
    let minWidth: CGFloat
    let height: CGFloat
    let inactiveBackground: Color
    let inactiveTextOpacity: Double
    /// Surface prefix, e.g. `result` / `review`.
    let idPrefix: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(fraction.label)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: minWidth)
                .frame(height: height)
                .padding(.horizontal, minWidth < 40 ? 4 : 0)
                .background(
                    isActive ? Color.captureChromeText : inactiveBackground,
                    in: Capsule()
                )
                .foregroundStyle(
                    isActive ? Color.captureBackground : Color.captureChromeText.opacity(inactiveTextOpacity)
                )
                .contentShape(Capsule())
        }
        .accessibilityIdentifier("\(idPrefix).fraction.\(fraction.identifier)")
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

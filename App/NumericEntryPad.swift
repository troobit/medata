import SwiftUI

// The one numeric control (specs/ui/unified-entry-sheet Req 1).
//
// Both halves come from `GlucoseEntrySheet`, which solved this first and
// solved it well; this file is that solution generalised so the insulin sheet
// can hold the same one, and the glucose sheet deleted rather than kept in
// parallel.

/// The digit-shift rule: digits arrive from the right against a fixed number
/// of decimal places, so the point is never typed (Req 1.1).
///
/// `1`, `2`, `1` at one decimal is 12.1; at zero decimals it is 121. The
/// alternative — a decimal-point field — costs an extra keystroke on every
/// fractional value, which is what put glucose over its four-interaction
/// budget when it was measured (`fingerprick-glucose` Req 2.3).
///
/// Pure and free of SwiftUI, so the rule is testable without a view.
struct DigitEntry: Equatable {
    let decimals: Int
    let range: ClosedRange<Double>
    private(set) var digits = ""

    init(decimals: Int, range: ClosedRange<Double>) {
        self.decimals = decimals
        self.range = range
    }

    private var divisor: Double { pow(10, Double(decimals)) }

    var value: Double { (Double(digits) ?? 0) / divisor }

    var displayValue: String { String(format: "%.\(decimals)f", value) }

    var isInRange: Bool { range.contains(value) }

    /// Raw digits in, filtered digits out. The keypad's delete key hands back
    /// a shorter string, so backspace needs no case of its own.
    ///
    /// Three rules, in order: digits only; no leading zero, so `0` `8` `4` and
    /// `8` `4` both read 8.4; and nothing that would carry the value past the
    /// range, which is what makes an out-of-range entry unreachable rather
    /// than merely refused (Req 1.3). The last rule also caps the length
    /// without a separate check — one digit too many always exceeds the top.
    mutating func setDigits(_ raw: String) {
        var next = String(raw.filter(\.isNumber))
        while next.first == "0" { next.removeFirst() }
        guard !next.isEmpty else {
            digits = ""
            return
        }
        guard let parsed = Double(next), parsed / divisor <= range.upperBound else { return }
        digits = next
    }

    /// Seeds the buffer from a number, so a remembered or suggested value is
    /// something the NEXT keystroke replaces rather than appends to. Without
    /// this a seeded 10 U would turn into 105 U on pressing `5`.
    mutating func set(value: Double) {
        let scaled = Int((value * divisor).rounded())
        setDigits(scaled <= 0 ? "" : String(scaled))
    }
}

/// The numeral IS the field (Req 1.2).
///
/// A separate visible text field would put a second number on the screen and
/// make the implicit decimal point something to reconcile between them.
/// Instead the field is laid underneath at full size with clear text and a
/// clear caret, so it takes the keystrokes and the tap target while the
/// formatted value is what is drawn.
///
/// Focus belongs to the caller: a request made in the same run loop as the
/// sheet's presentation is dropped, and the hop that fixes it is a property of
/// the presenting sheet rather than of this view.
struct NumericEntryPad: View {
    @Binding var digits: String
    let displayValue: String
    let isComplete: Bool
    let unitLabel: String
    let accessibilityLabel: String
    let identifier: String
    @FocusState.Binding var focused: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                TextField("", text: $digits)
                    .keyboardType(.numberPad)
                    .focused($focused)
                    .font(.system(size: 72, weight: .bold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.clear)
                    .tint(.clear)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityValue(displayValue)
                    .accessibilityIdentifier(identifier)
                // Formatted live, so the decimal point that is never typed is
                // visible rather than remembered.
                Text(displayValue)
                    .font(.system(size: 72, weight: .bold).monospacedDigit())
                    .foregroundStyle(isComplete ? Color.textPrimary : Color.textSecondary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.1), value: displayValue)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            Text(unitLabel)
                .font(.subheadline)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

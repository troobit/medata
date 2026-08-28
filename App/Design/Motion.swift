import SwiftUI

// Motion, in one place (see App/Design/README.md).
//
// Every rolling figure in the app must stop rolling when the phone asks it to:
// Settings → Accessibility → Motion → Reduce Motion. That rule was previously
// kept by hand at twenty-odd call sites, each repeating the same ternary pair,
// and an audit on 2026-08-28 found three that had forgotten it — including one
// added the same day. A rule that has to be remembered at every call site is a
// rule that will be forgotten at one of them.
//
// So the gate lives HERE, inside one modifier, and the call sites say what they
// mean instead: `.animatedNumeral(value: units)`.

extension Animation {
    /// A figure changing to another figure. The default for numerals.
    static let numeral: Animation = .smooth

    /// A control acknowledging a press.
    static let press: Animation = .snappy(duration: 0.1)

    /// Something arriving or leaving.
    static let fade: Animation = .easeInOut(duration: 0.2)
}

private struct AnimatedNumeral<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .numeral, value: value)
    }
}

extension View {
    /// Rolls a numeral when `value` changes, and does not when the phone has
    /// asked for less motion. Use this for every figure that changes; do not
    /// write the `contentTransition`/`animation` pair by hand.
    func animatedNumeral(value: some Equatable) -> some View {
        modifier(AnimatedNumeral(value: value))
    }
}

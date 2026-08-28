import Foundation

// The numbers the design is made of (see App/Design/README.md).
//
// Every one of these was a bare literal repeated across several files — twenty
// sites said `cornerRadius: 12`, five said `.opacity(0.4)` for "this control is
// disabled". Naming them does two things: it makes a global change one edit,
// and it makes an ODD value visible as a deliberate exception rather than as
// another number in the pile.
enum Metrics {
    // MARK: Corner radii
    /// Cards, pills and primary buttons — the app's default roundness.
    static let cornerCard: CGFloat = 12
    /// Chips and small inline controls.
    static let cornerChip: CGFloat = 8
    /// Large sheet-level containers.
    static let cornerSheet: CGFloat = 16

    // MARK: Control heights
    /// Secondary controls, and anything paired beside one.
    static let control: CGFloat = 44
    /// Primary actions — Record, Save, Done.
    static let controlLarge: CGFloat = 48

    // MARK: Alpha ladder
    /// Fill alpha for a coloured pill or banner, so text stays legible on it.
    static let fillAlpha: Double = 0.85
    /// A control that cannot currently be used.
    static let disabled: Double = 0.4
    /// A scrim behind a control floating over content.
    static let scrim: Double = 0.6

    /// Secondary and tertiary text on the capture chrome, in descending
    /// prominence. Three steps, deliberately — a fourth would not be
    /// distinguishable on device.
    static let textSecondary: Double = 0.75
    static let textTertiary: Double = 0.6
    static let textQuaternary: Double = 0.5
}

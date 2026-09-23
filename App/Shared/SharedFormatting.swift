import SwiftUI

// One formatter set and one timeline-row grammar for the list surfaces
// (specs/ui/shared-meal-components Req 4). Before this file the en_IE
// medium/short helper was written out five times, each allocating a fresh
// DateFormatter per call; the row HStack (glyph in a fixed 20 pt frame,
// headline over caption stack, trailing content) was written six times.

enum MedataFormat {
    // Cached: DateFormatter construction is the expensive part, and every
    // call site renders the same en_IE medium/short shape.
    private static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_IE")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// "25 Aug 2026, 10:30" — the Records/Intake/Overview timestamp shape.
    static func dateTimeString(_ date: Date) -> String {
        dateTime.string(from: date)
    }

    /// "08:41" — the Graph meal-list clock shape.
    static func clockString(_ date: Date) -> String {
        clock.string(from: date)
    }

    /// A quantity and its unit: whole number when the value lands on one at
    /// a single decimal place, otherwise exactly one decimal — "5 U",
    /// "4.5 g/U", "87 g", "12 units".
    ///
    /// The half-away-from-zero rule is applied ONCE, to tenths, before the
    /// integer test: without it a value of 4.999 would fail `== rounded()`
    /// and print "5.0" beside a sibling figure printing "5". Five call sites
    /// carried this five-line shape verbatim, differing only in the suffix.
    ///
    /// This is the DEFAULT shape, not the only one. A surface that must show
    /// a decimal place even on a whole value — because the figure is a term
    /// in an equation the reader is checking — formats it itself and says
    /// why (see `DoseWorkingSheet.ratio`).
    /// `nonisolated` because `DoseReadout`'s labels are: the readout is a
    /// `nonisolated struct` so the dosing maths can be read off any actor, and
    /// a MainActor-only formatter would drag it back onto the main actor.
    /// Pure arithmetic over its arguments, so there is nothing to isolate.
    nonisolated static func quantity(_ value: Double, unit: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return "\(Int(rounded)) \(unit)" }
        return String(format: "%.1f", rounded) + " " + unit
    }

    /// Food-class display name: underscores to spaces, leading capital.
    /// One home for the three copies meal surfaces carried.
    static func prettify(_ raw: String) -> String {
        let spaced = raw.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }
}

// The timeline row: glyph in a fixed 20 pt frame so text columns align across
// row types, a headline-over-caption stack, and optional trailing content.
// Each consumer keeps its own data decoding and fills the slots.
struct TimelineRow<Headline: View, Footer: View, Trailing: View>: View {
    let glyph: String
    let glyphTint: Color
    let timestamp: Date
    @ViewBuilder var headline: Headline
    @ViewBuilder var footer: Footer
    @ViewBuilder var trailing: Trailing

    init(
        glyph: String,
        glyphTint: Color,
        timestamp: Date,
        @ViewBuilder headline: () -> Headline,
        @ViewBuilder footer: () -> Footer = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.glyph = glyph
        self.glyphTint = glyphTint
        self.timestamp = timestamp
        self.headline = headline()
        self.footer = footer()
        self.trailing = trailing()
    }

    var body: some View {
        HStack {
            Image(systemName: glyph)
                .foregroundStyle(glyphTint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                headline
                Text(MedataFormat.dateTimeString(timestamp))
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
                footer
            }
            Spacer()
            trailing
        }
    }
}

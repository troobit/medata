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

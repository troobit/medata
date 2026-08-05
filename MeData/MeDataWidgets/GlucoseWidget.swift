import GlucoseWidgetShared
import SwiftUI
import WidgetKit

// The data-driven glucose kind (specs/ui/glucose-lock-widget). Unlike the two
// launcher kinds it reads state — but only the App Group snapshot: no event log,
// no persistence store, no network (Req 2.6). All the staleness logic lives in
// GlucoseWidgetShared as pure functions; this file is the WidgetKit adapter over
// it (Decision 12) plus the per-family views.

// MARK: - Timeline

// The WidgetKit wrapper over one (date, render) pair from
// GlucoseTimeline.renderPoints. `readingDate` rides along for the one thing the
// pure ladder cannot express: a live-ticking age for a FRESH reading, whose
// single entry spans up to 15 minutes of wall time (Decision 14).
struct GlucoseEntry: TimelineEntry {
    let date: Date
    let render: GlucoseRender
    let readingDate: Date?
}

// Witnesses are explicitly `nonisolated`: the target builds with
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, so the conformance does not compile
// otherwise (see LauncherProvider, docs/agent-notes/widget-extension.md).
struct GlucoseProvider: TimelineProvider {
    nonisolated func placeholder(in context: Context) -> GlucoseEntry {
        // The gallery preview shows the empty state rather than a specimen
        // reading — no fabricated decimal (Req 2.7), functional copy (Req 8.2).
        GlucoseEntry(date: .now, render: .neverRecorded, readingDate: nil)
    }

    nonisolated func getSnapshot(in context: Context, completion: @escaping (GlucoseEntry) -> Void) {
        let now = Date.now
        let snapshot = GlucoseSnapshotStore.read()
        completion(
            GlucoseEntry(
                date: now, render: GlucoseTimeline.render(snapshot, at: now),
                readingDate: snapshot.readingDate))
    }

    nonisolated func getTimeline(in context: Context, completion: @escaping (Timeline<GlucoseEntry>) -> Void) {
        let now = Date.now
        let snapshot = GlucoseSnapshotStore.read()
        let entries = GlucoseTimeline.renderPoints(snapshot, from: now).map {
            GlucoseEntry(date: $0.date, render: $0.render, readingDate: snapshot.readingDate)
        }
        // A terminal state (last-reading / never-recorded) cannot advance on its
        // own, so it waits for the app's explicit reload rather than booking a
        // pointless refresh.
        let policy: TimelineReloadPolicy =
            GlucoseTimeline.nextBoundary(snapshot, after: now).map { .after($0) } ?? .never
        completion(Timeline(entries: entries, policy: policy))
    }
}

// MARK: - Widget

struct GlucoseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlucoseSnapshotStore.widgetKind, provider: GlucoseProvider()) { entry in
            GlucoseWidgetView(entry: entry)
                .widgetURL(URL(string: "medata://graph"))
        }
        .configurationDisplayName("Glucose")
        .description("Shows the latest glucose reading and its trend.")
        .supportedFamilies([
            .accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall,
        ])
    }
}

// MARK: - View

struct GlucoseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    let entry: GlucoseEntry

    // Req 5.2 — the de-emphasis is opacity, not colour, because the Lock Screen
    // renders vibrant monochrome and hue carries no meaning there.
    private static let staleOpacity = 0.5

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryInline: inline
        case .systemSmall: small
        default: rectangular
        }
    }

    // MARK: Families

    // Req 2.3 — value, status token and arrow. No age line fits, so opacity is
    // the sole staleness cue here (Req 5.2).
    @ViewBuilder
    private var circular: some View {
        switch entry.render {
        case let .fresh(value, status, trend):
            VStack(spacing: 0) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint(status))
                HStack(spacing: 2) {
                    if let token = token(status) {
                        Text(token)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(tint(status))
                    }
                    // Larger than the token but short of the value's 20 pt —
                    // the circular family is a ~40 pt disc and a full-size
                    // arrow beside a token overflows it.
                    if let trend {
                        Text(trend.arrow)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(tint(status))
                    }
                }
            }
        case let .stale(value, _):
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .opacity(Self.staleOpacity)
        case let .lastReading(age):
            VStack(spacing: 0) {
                Image(systemName: "clock").font(.system(size: 12))
                Text(age).font(.system(size: 13, weight: .medium))
            }
            .opacity(Self.staleOpacity)
        case .neverRecorded:
            Text("—").font(.title3).opacity(Self.staleOpacity)
        }
    }

    // Req 2.4 — value, status token, arrow and the reading's age.
    @ViewBuilder
    private var rectangular: some View {
        switch entry.render {
        case let .fresh(value, status, trend):
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(.system(.title2, design: .rounded).weight(.semibold))
                        .foregroundStyle(tint(status))
                    if let token = token(status) {
                        Text(token).font(.caption).fontWeight(.bold).foregroundStyle(tint(status))
                    }
                    // Arrow at the VALUE's size, not the token's: on the Lock
                    // Screen it was caption-sized and read as a footnote to the
                    // number rather than as the second thing you look at. The
                    // token stays small — it is a qualifier; the arrow is data.
                    if let trend {
                        Text(trend.arrow)
                            .font(.system(.title2, design: .rounded).weight(.semibold))
                            .foregroundStyle(tint(status))
                    }
                }
                freshAge
            }
        case let .stale(value, age):
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(.title2, design: .rounded).weight(.semibold))
                Text(age).font(.caption2)
            }
            .opacity(Self.staleOpacity)
        case let .lastReading(age):
            VStack(alignment: .leading, spacing: 1) {
                Text("Last reading").font(.caption)
                Text(age).font(.caption2)
            }
            .opacity(Self.staleOpacity)
        case .neverRecorded:
            Text("No glucose reading").font(.caption).opacity(Self.staleOpacity)
        }
    }

    // The StandBy surface. StandBy's widget panel is fed from the Home Screen
    // pool, so `systemSmall` is what reaches it — the accessory families never
    // do. Offering it therefore also lists the kind on the Home Screen; that is
    // the unavoidable price of StandBy, not a second placement we wanted.
    // Content matches `rectangular` (value, token, arrow, age) at the larger
    // type the panel affords, so the status channel and staleness cues stay
    // identical across surfaces.
    @ViewBuilder
    private var small: some View {
        switch entry.render {
        case let .fresh(value, status, trend):
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint(status))
                HStack(spacing: 4) {
                    if let token = token(status) {
                        Text(token)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(tint(status))
                    }
                    // Matches `rectangular`'s treatment at this family's scale.
                    if let trend {
                        Text(trend.arrow)
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                            .foregroundStyle(tint(status))
                    }
                }
                freshAge
            }
        case let .stale(value, age):
            VStack(spacing: 2) {
                Text(value).font(.system(size: 44, weight: .semibold, design: .rounded))
                Text(age).font(.caption)
            }
            .opacity(Self.staleOpacity)
        case let .lastReading(age):
            VStack(spacing: 2) {
                Image(systemName: "clock").font(.title2)
                Text("Last reading").font(.callout)
                Text(age).font(.caption)
            }
            .opacity(Self.staleOpacity)
        case .neverRecorded:
            Text("No glucose reading").font(.callout).opacity(Self.staleOpacity)
        }
    }

    // Req 2.5 — one line, always monochrome, so the token is the only status
    // channel available here.
    @ViewBuilder
    private var inline: some View {
        switch entry.render {
        case let .fresh(value, status, trend):
            Text([token(status), value, trend?.arrow].compactMap { $0 }.joined(separator: " "))
        case let .stale(value, age):
            Text("\(value) · \(age)")
        case let .lastReading(age):
            Text("Last reading \(age)")
        case .neverRecorded:
            Text("No glucose reading")
        }
    }

    // A fresh entry lives for up to 15 minutes, so a baked age string would read
    // "0m" for most of it. `.relative` ticks without spending timeline entries;
    // the stale and last-reading states use the pure ladder's own age string
    // (Req 5.5 format) because theirs is pinned to a known transition instant.
    @ViewBuilder
    private var freshAge: some View {
        if let readingDate = entry.readingDate {
            Text(readingDate, style: .relative).font(.caption2)
        }
    }

    // MARK: Status channel (Req 4.2, Decision 7)

    // The sole status signal: a short token that survives monochrome vibrant
    // rendering. In-range carries none — an absent token is the in-range state.
    private func token(_ status: GlucoseBandStatus) -> String? {
        switch status {
        case .low: return "LO"
        case .inRange: return nil
        case .high: return "HI"
        }
    }

    // Colour is layered on the token only where the system renders full colour
    // (StandBy day), never as the signal itself (Req 4.3).
    private func tint(_ status: GlucoseBandStatus) -> Color {
        guard renderingMode == .fullColor else { return .primary }
        switch status {
        case .low: return .red
        case .inRange: return .primary
        case .high: return .orange
        }
    }
}

import SwiftUI
import WidgetKit

// MeData launcher widgets — PRD specs/regression-suggestion-integration
// (Lock screen widget context). Three STATIC widget kinds: lock-screen
// accessory widgets carry a single tap target each, so "dose", "Capture" and
// "BSL" are separate widgets the user places side by side. None of them
// displays data — each deep-links into the app (App/AppRoot.swift
// handleDeepLink), so none has a persistence import. Keep them that way: the
// App Group and the snapshot read belong to the data-driven glucose kind in
// GlucoseWidget.swift alone.

@main
struct MeDataWidgetBundle: WidgetBundle {
    var body: some Widget {
        InsulinDoseWidget()
        CaptureWidget()
        GlucoseAddWidget()
        GlucoseWidget()
    }
}

// MARK: - Static timeline

// A launcher never updates: one entry, policy .never.
// `nonisolated` for the same reason as `GlucoseEntry` — WidgetKit reads the
// conformance from a nonisolated context.
nonisolated struct LauncherEntry: TimelineEntry {
    let date: Date
}

struct LauncherProvider: TimelineProvider {
    nonisolated func placeholder(in context: Context) -> LauncherEntry {
        LauncherEntry(date: .now)
    }

    nonisolated func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: .now))
    }

    nonisolated func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [LauncherEntry(date: .now)], policy: .never))
    }
}

// MARK: - Widgets

struct InsulinDoseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ie.medata.widget.insulin", provider: LauncherProvider()) { _ in
            LauncherView(symbol: "syringe", label: "dose")
                .widgetURL(URL(string: "medata://insulin/add"))
        }
        .configurationDisplayName("dose")
        .description("Opens the insulin dose entry.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

struct CaptureWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ie.medata.widget.capture", provider: LauncherProvider()) { _ in
            LauncherView(symbol: "camera.fill", label: "Capture")
                .widgetURL(URL(string: "medata://capture"))
        }
        .configurationDisplayName("Capture")
        .description("Opens the meal capture camera.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

// The glucose-entry launcher (fingerprick-glucose Req 2.2). Its kind is
// `ie.medata.widget.glucose.add`, distinct from the data-driven
// `ie.medata.widget.glucose` in GlucoseWidget.swift — two widgets about the
// same measurement, one that shows it and one that records it, and WidgetKit
// keys placement, reload budget and timeline on the kind string. Reusing the
// data kind would make a launcher share the glucose tile's reload budget and
// replace its tap destination.
//
// A launcher, so it stays on the launcher rules: no App Group, no persistence,
// no network, policy `.never`.
struct GlucoseAddWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ie.medata.widget.glucose.add", provider: LauncherProvider()) { _ in
            LauncherView(symbol: "drop.fill", label: "BSL")
                .widgetURL(URL(string: "medata://glucose/add"))
        }
        .configurationDisplayName("BSL")
        .description("Opens the blood glucose entry.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .systemSmall])
    }
}

// MARK: - View

struct LauncherView: View {
    @Environment(\.widgetFamily) private var family

    let symbol: String
    let label: String

    var body: some View {
        content
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: symbol)
                .font(.title2)
                .accessibilityLabel(label)
        case .accessoryRectangular:
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.headline)
                Text(label)
                    .font(.headline)
            }
        default: // .systemSmall
            VStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 40))
                Text(label)
                    .font(.headline)
            }
        }
    }
}

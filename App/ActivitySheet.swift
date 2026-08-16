import Persistence
import SwiftUI

// The activity-entry sheet (specs/data/activity-events Req 3), presented as a
// plain medium-detent sheet from AppRoot — the same weight as the insulin dose
// sheet, deliberately lighter than the Capture/Records/Graph covers.
//
// ATTEMPT 2 — "everything on one surface": all seven kinds are a 4×2 grid of
// icon tiles, so no kind is ever off-screen and picking one is a single tap
// wherever the eye lands, and the duration is a row of one-tap presets rather
// than a stepper. What it gives up is arbitrary precision — 37 minutes cannot
// be expressed, only the presets or nothing — on the reasoning that a
// remembered duration is a rounded guess anyway, and that a stepper walking to
// 45 in five-minute taps is the slowest control on the sheet.
//
// It opens on the most recently used kind, so the repeat path is open → Save
// (Req 3.1/3.3). Duration starts blank and blank saves `nil` (Req 3.4/1.5);
// the time control defaults to now and moves backwards (Req 3.2). No
// intensity, effort or calorie control (Req 2.4), and no reassurance or
// disclaimer copy anywhere (Req 4.4).
//
// NOTE: sizing/`contentShape` live INSIDE each Button label — a Button's tap
// gesture covers only its label, so outside modifiers draw a dead surface
// (ui-capture-flow.md gotcha).
struct ActivitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ActivityModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    init(store: any PersistenceStore) {
        _model = State(initialValue: ActivityModel(store: store))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                kindGrid
                durationPresets
                timeRow
                saveButton
                if let saveError = model.saveError {
                    Text(saveError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .background(Color.surfacePrimary)
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Kind (Req 2.1, 3.3)

    // Every kind visible at once: seven tiles over two rows of four, so the
    // remembered kind and every alternative are one tap apart.
    private var kindGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(ActivityKind.allCases, id: \.self) { kind in
                kindTile(kind)
            }
        }
        .accessibilityIdentifier("activity.kinds")
    }

    private func kindTile(_ kind: ActivityKind) -> some View {
        let isOn = model.kind == kind
        return Button {
            model.kind = kind
        } label: {
            VStack(spacing: 4) {
                Image(systemName: kind.symbolName)
                    .font(.system(size: 22, weight: .medium))
                Text(kind.displayLabel)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                isOn ? Color.seriesActivity : Color.surfaceElevated,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .foregroundStyle(isOn ? Color.captureBackground : Color.textSecondary)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity.kind.\(kind.rawValue)")
    }

    // MARK: - Duration (Req 3.4)

    // One tap sets a duration, tapping the same preset again clears it — so
    // blank, which is what most entries will carry, is never more than one tap
    // away and never blocks Save.
    private var durationPresets: some View {
        HStack(spacing: 8) {
            ForEach(ActivityModel.durationPresets, id: \.self) { minutes in
                durationChip(minutes)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("activity.duration")
    }

    private func durationChip(_ minutes: Double) -> some View {
        let isOn = model.durationMinutes == minutes
        return Button {
            model.toggleDuration(minutes)
        } label: {
            Text("\(Int(minutes))")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(isOn ? Color.textPrimary : Color.surfaceElevated, in: Capsule())
                .foregroundStyle(isOn ? Color.surfacePrimary : Color.textSecondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity.duration.\(Int(minutes))")
    }

    // MARK: - Time (Req 3.2)

    private var timeRow: some View {
        DatePicker(
            "Start",
            selection: $model.timestamp,
            in: ...Date(),
            displayedComponents: [.date, .hourAndMinute]
        )
        .datePickerStyle(.compact)
        .environment(\.locale, Locale(identifier: "en_IE"))
        .accessibilityIdentifier("activity.time")
    }

    // The button states what will be written, duration included, so the one
    // control that is easy to leave in the wrong state is legible before the
    // tap rather than after it.
    private var saveButton: some View {
        Button {
            Task {
                if await model.save() { dismiss() }
            }
        } label: {
            if model.isSaving {
                MedataLoadingSymbol(mode: .loop, size: 22)
                    .frame(maxWidth: .infinity)
            } else {
                Text(saveLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.medataAccent)
        .foregroundStyle(Color.captureBackground)
        .disabled(model.isSaving)
        .accessibilityIdentifier("activity.save")
    }

    private var saveLabel: String {
        guard let minutes = model.durationMinutes else { return "Save \(model.kind.displayLabel)" }
        return "Save \(model.kind.displayLabel) · \(Int(minutes)) min"
    }
}

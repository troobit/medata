import Persistence
import SwiftUI

// The activity-entry sheet (specs/data/activity-events Req 3), presented as a
// plain medium-detent sheet from AppRoot — the same weight as the insulin dose
// sheet, deliberately lighter than the Capture/Records/Graph covers.
//
// ATTEMPT 1 — "chip row and stepper", the dose-sheet idiom applied verbatim:
// the kinds are a horizontally scrolling row of labelled chips and the
// duration is a ±5-minute stepper flanking a large numeral, exactly as
// `InsulinDoseSheet` handles units. It opens on the most recently used kind,
// so the repeat path is open → Save (Req 3.1/3.3). Duration starts blank and
// blank saves `nil` (Req 3.4/1.5); the time control defaults to now and moves
// backwards (Req 3.2). No intensity, effort or calorie control (Req 2.4), and
// no reassurance or disclaimer copy anywhere (Req 4.4).
//
// NOTE: sizing/`contentShape` live INSIDE each Button label — a Button's tap
// gesture covers only its label, so outside modifiers draw a dead surface
// (ui-capture-flow.md gotcha).
struct ActivitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ActivityModel

    init(store: any PersistenceStore) {
        _model = State(initialValue: ActivityModel(store: store))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                kindChips
                durationStepper
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

    private var kindChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityKind.allCases, id: \.self) { kind in
                    kindChip(kind)
                }
            }
            .padding(.horizontal, 2)
        }
        .accessibilityIdentifier("activity.kinds")
    }

    private func kindChip(_ kind: ActivityKind) -> some View {
        let isOn = model.kind == kind
        return Button {
            model.kind = kind
        } label: {
            Label(kind.displayLabel, systemImage: kind.symbolName)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isOn ? Color.seriesActivity : Color.surfaceElevated, in: Capsule())
                .foregroundStyle(isOn ? Color.captureBackground : Color.textSecondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity.kind.\(kind.rawValue)")
    }

    // MARK: - Duration (Req 3.4)

    // Blank by default and blank is reachable again: stepping down off the
    // 5-minute floor clears the value rather than bottoming out.
    private var durationStepper: some View {
        HStack(spacing: 20) {
            stepControl("minus", identifier: "activity.duration.minus") {
                model.stepDurationDown()
            }
            VStack(spacing: 0) {
                Text(model.durationLabel)
                    .font(.system(size: 34, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.1), value: model.durationMinutes)
                    .accessibilityIdentifier("activity.duration")
                Text("duration")
                    .font(.caption)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(minWidth: 120)
            stepControl("plus", identifier: "activity.duration.plus") {
                model.stepDurationUp()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stepControl(
        _ symbol: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 56, height: 56)
                .background(Color.surfaceElevated, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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
                Text("Save \(model.kind.displayLabel)")
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
}

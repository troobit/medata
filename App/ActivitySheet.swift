import SwiftUI

// The activity-entry sheet (specs/data/activity-events Req 3). A plain
// medium-detent sheet, the same weight as the dose sheet, not a full-screen
// cover.
//
// The whole screen is arranged so the common case is one tap: the kind is
// already the one saved last, the duration is optional, the time is already
// now, and `Save` names exactly what it writes. Everything else on the sheet
// is there to be ignored.
//
// Kinds are a wrapping grid of chips rather than a picker or a scrolling row:
// every kind is on screen at once, so choosing one is a single hit at a fixed
// position instead of a scroll-then-hit. Each chip carries its glyph because a
// glyph is faster to find than a word — this is a label on a noun, not a
// signal beside a number.
//
// No intensity control, no effort rating, no calorie field (Req 2.4). No
// reassurance, disclaimer, warning or coaching copy anywhere (Req 4.4).
struct ActivitySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model: ActivityModel

    init(activities: any ActivityStoring) {
        _model = State(initialValue: ActivityModel(activities: activities))
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Kind (Req 3.3)

    private var kindChips: some View {
        ChipFlow(spacing: 8, lineSpacing: 8) {
            ForEach(ActivityKind.allCases, id: \.self) { kind in
                kindChip(kind)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("activity.kinds")
    }

    private func kindChip(_ kind: ActivityKind) -> some View {
        let isOn = model.kind == kind
        return Button {
            model.kind = kind
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.symbolName)
                    .font(.subheadline)
                Text(kind.label)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(isOn ? Color.medataAccent : Color.surfaceElevated, in: Capsule())
            .foregroundStyle(isOn ? Color.captureBackground : Color.textSecondary)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("activity.kind.\(kind.rawValue)")
    }

    // MARK: - Duration (Req 3.4) — optional, never blocking Save

    // The dose sheet's stepper at one register down: 56pt rather than 72pt,
    // because a duration is a covariate and a dose is the headline number.
    private var durationStepper: some View {
        HStack(spacing: 24) {
            stepControl("minus", direction: .down, identifier: "activity.minus")
            VStack(spacing: 0) {
                Text(model.durationLabel)
                    .font(.system(size: 56, weight: .bold).monospacedDigit())
                    .foregroundStyle(
                        model.durationMinutes == nil ? Color.textSecondary : Color.textPrimary
                    )
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.1), value: model.durationMinutes)
                    .accessibilityIdentifier("activity.duration")
                Text("minutes")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(minWidth: 120)
            stepControl("plus", direction: .up, identifier: "activity.plus")
        }
        .frame(maxWidth: .infinity)
    }

    // Press-down steps once (a plain tap = ±5 min); keeping the finger down
    // hands over to the shared repeat schedule, so 45 minutes is one hold.
    private func stepControl(
        _ symbol: String, direction: ActivityModel.StepDirection, identifier: String
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 24, weight: .bold))
            .foregroundStyle(Color.textPrimary)
            .frame(width: 56, height: 56)
            .background(Color.surfaceElevated, in: Circle())
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: .infinity) {
            } onPressingChanged: { pressing in
                if pressing {
                    model.beginHold(direction)
                } else {
                    model.endHold()
                }
            }
            .accessibilityLabel(direction == .up ? "Increase duration" : "Decrease duration")
            .accessibilityIdentifier(identifier)
    }

    // MARK: - Time (Req 3.2) — the one divergence from the dose sheet

    private var timeRow: some View {
        DatePicker(
            "Started",
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
                Text(model.saveLabel)
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

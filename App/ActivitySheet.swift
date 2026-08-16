import Persistence
import SwiftUI

// The activity mode of `LogSheet` (specs/data/activity-events Req 3).
//
// The grammar is the insulin mode's, one slot at a time: kind, quantity,
// when, commit. Only the two middle slots differ — the kind set is seven
// wrapping chips rather than a two-way segment, and the quantity is optional,
// which is why it is a stepper with a blank state rather than a numeral that
// always reads something.
//
// No intensity control, no effort rating, no calorie field (Req 2.4):
// intensity is carried by the kind and its recorded cardiovascular character,
// and by duration where one is given.
struct ActivityContent: View {
    @Bindable var model: ActivityModel
    let onSaved: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            kindChips
            durationStepper
            EntryTimeRow(timestamp: $model.timestamp, identifier: "activity.time")
            EntrySaveButton(
                title: model.saveTitle,
                isSaving: model.isSaving,
                isEnabled: true,
                identifier: "activity.save"
            ) {
                Task { if await model.save() { onSaved() } }
            }
            if let saveError = model.saveError {
                Text(saveError)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    // Preselected to the most recently saved kind (Req 3.3), so the repeat
    // case is open → Save. Wraps rather than compressing — the Graph's metric
    // chips and these are one layout (`ChipFlow`).
    private var kindChips: some View {
        ChipFlow(spacing: 8, lineSpacing: 8) {
            ForEach(ActivityKind.allCases, id: \.self) { kind in
                EntryChip(
                    title: ActivityModel.label(for: kind),
                    isActive: model.kind == kind,
                    identifier: "activity.kind.\(kind.rawValue)"
                ) {
                    model.kind = kind
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Optional, and it never blocks a save (Req 3.4). Blank renders an em
    // dash and stores an ABSENT duration, never 0 (Req 1.5) — this is the one
    // slot in the app where the em dash is right, because the slot exists and
    // has no value.
    private var durationStepper: some View {
        HStack(spacing: 28) {
            stepControl("minus", delta: -1, identifier: "activity.minus")
            VStack(spacing: 0) {
                Text(model.durationLabel)
                    .font(.system(size: 56, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.1), value: model.durationMinutes)
                    .accessibilityIdentifier("activity.duration")
                Text("minutes")
                    .font(.subheadline)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(minWidth: 120)
            stepControl("plus", delta: 1, identifier: "activity.plus")
        }
        .frame(maxWidth: .infinity)
    }

    private func stepControl(_ symbol: String, delta: Int, identifier: String) -> some View {
        Button {
            model.stepDuration(delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.textPrimary)
                .frame(width: 68, height: 68)
                .background(Color.surfaceElevated, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(delta > 0 ? "Increase duration" : "Decrease duration")
        .accessibilityIdentifier(identifier)
    }
}

import Persistence
import SwiftUI

// The schedule-editing surface (specs/data/dose-schedule Req 1.3, 1.4, 3.2,
// 3.3). A section in the existing Settings Form, following the settings-row
// pattern already there; functional copy only.
//
// Disable is deliberately distinct from delete: a regime change is reversible
// without re-entering the whole entry (Req 1.4). Editing a scheduled dose
// alters no already-recorded dose and closes no open occurrence
// retrospectively — that holds mechanically, because a scheduled dose is
// configuration and the occurrence ledger is a separate table it never writes
// to (Req 1.5).
extension SettingsView {

    @ViewBuilder
    var doseScheduleSection: some View {
        Section("Dose schedule") {
            ForEach(doseSchedule.schedules) { schedule in
                scheduleRow(schedule)
            }
            .onDelete { offsets in
                let ids = offsets.map { doseSchedule.schedules[$0].id }
                Task {
                    for id in ids { await doseSchedule.delete(scheduleID: id) }
                }
            }
            Button {
                Task {
                    await doseSchedule.save(schedules: doseSchedule.schedules + [
                        ScheduledDose(hour: 12, minute: 0, nominalUnits: 10, kind: .basal)
                    ])
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .accessibilityIdentifier("settings.doseScheduleAdd")
        }

        Section("Reminder") {
            // I and K. Seeded at 30 minutes and 4 for a two-hour tail. They are
            // a starting point, not a finding, and nothing here presents them
            // as recommended values — the labels state what they do and the
            // numbers stand on their own.
            Stepper(
                "Repeat every \(doseSchedule.plan.intervalMinutes) min",
                value: intervalBinding, in: 5...240, step: 5
            )
            .accessibilityIdentifier("settings.doseInterval")
            Stepper(
                "Repeats \(doseSchedule.plan.followUpCount)",
                value: followUpBinding, in: 0...12
            )
            .accessibilityIdentifier("settings.doseFollowUps")
            LabeledContent("Stops after") {
                Text(cutoffLabel)
                    .foregroundStyle(Color.textSecondary)
            }
            // The two attempts at the in-app surface, side by side on one
            // build (tags `dose-schedule-ui-attempt-1` and `-2`). A comparison
            // switch for the phone, not a feature — it goes when one of the two
            // wins.
            Picker("Surface", selection: surfaceStyleBinding) {
                Text("Card").tag(DoseScheduleSettings.SurfaceStyle.banner)
                Text("Dose control").tag(DoseScheduleSettings.SurfaceStyle.doseRoute)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("settings.doseSurface")
        }
    }

    private var surfaceStyleBinding: Binding<DoseScheduleSettings.SurfaceStyle> {
        Binding(
            get: { doseSchedule.surfaceStyle },
            set: { doseSchedule.surfaceStyle = $0 }
        )
    }

    private func scheduleRow(_ schedule: ScheduledDose) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                DatePicker(
                    "Time",
                    selection: timeBinding(for: schedule),
                    displayedComponents: [.hourAndMinute]
                )
                .datePickerStyle(.compact)
                .environment(\.locale, Locale(identifier: "en_IE"))
                .labelsHidden()
                Spacer()
                Toggle("", isOn: enabledBinding(for: schedule))
                    .labelsHidden()
                    .accessibilityLabel("Enabled")
            }
            Stepper(
                "\(DoseScheduleModel.unitsLabel(schedule.nominalUnits)) \(schedule.kind.rawValue)",
                value: unitsBinding(for: schedule), in: 1...60
            )
            Picker("Kind", selection: kindBinding(for: schedule)) {
                Text("Bolus").tag(InsulinKind.bolus)
                Text("Basal").tag(InsulinKind.basal)
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("settings.doseSchedule.\(schedule.id.uuidString)")
    }

    // MARK: - Bindings

    private var intervalBinding: Binding<Int> {
        Binding(
            get: { doseSchedule.plan.intervalMinutes },
            set: { value in
                var plan = doseSchedule.plan
                plan.intervalMinutes = value
                Task { await doseSchedule.save(plan: plan) }
            }
        )
    }

    private var followUpBinding: Binding<Int> {
        Binding(
            get: { doseSchedule.plan.followUpCount },
            set: { value in
                var plan = doseSchedule.plan
                plan.followUpCount = value
                Task { await doseSchedule.save(plan: plan) }
            }
        )
    }

    private var cutoffLabel: String {
        let seconds = Int(doseSchedule.plan.cutoffSeconds)
        if seconds == 0 { return "—" }
        if seconds < 3600 { return "\(seconds / 60) min" }
        let hours = Double(seconds) / 3600
        return hours == hours.rounded()
            ? "\(Int(hours)) h"
            : String(format: "%.1f h", hours)
    }

    private func update(_ schedule: ScheduledDose, _ mutate: (inout ScheduledDose) -> Void) {
        var updated = schedule
        mutate(&updated)
        let all = doseSchedule.schedules.map { $0.id == updated.id ? updated : $0 }
        Task { await doseSchedule.save(schedules: all) }
    }

    private func enabledBinding(for schedule: ScheduledDose) -> Binding<Bool> {
        Binding(
            get: { schedule.isEnabled },
            set: { value in update(schedule) { $0.isEnabled = value } }
        )
    }

    private func unitsBinding(for schedule: ScheduledDose) -> Binding<Int> {
        Binding(
            get: { Int(schedule.nominalUnits.rounded()) },
            set: { value in update(schedule) { $0.nominalUnits = Double(value) } }
        )
    }

    private func kindBinding(for schedule: ScheduledDose) -> Binding<InsulinKind> {
        Binding(
            get: { schedule.kind },
            set: { value in update(schedule) { $0.kind = value } }
        )
    }

    // The time is edited as a `Date` because that is what `DatePicker` speaks,
    // but only the hour and minute are ever read back out of it. The schedule
    // stores wall-clock components, never an instant, so travel and a
    // daylight-saving transition leave it alone (Req 1.6).
    private func timeBinding(for schedule: ScheduledDose) -> Binding<Date> {
        Binding(
            get: {
                var parts = DateComponents()
                parts.hour = schedule.hour
                parts.minute = schedule.minute
                return Calendar.current.date(from: parts) ?? Date()
            },
            set: { value in
                let parts = Calendar.current.dateComponents(
                    [.hour, .minute], from: value
                )
                update(schedule) {
                    $0.hour = parts.hour ?? $0.hour
                    $0.minute = parts.minute ?? $0.minute
                }
            }
        )
    }
}

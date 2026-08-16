import Persistence
import SwiftUI

// UI ATTEMPT 2 at the in-app outstanding-dose surface (specs/data/dose-schedule
// Req 2.4, 4.5; tagged `dose-schedule-ui-attempt-2`).
//
// The bet: nothing new should appear on screen. Home already has a Dose control
// and the developer already knows where it is; when a dose is outstanding that
// control changes what it does — one tap on it records the dose — rather than a
// card appearing above it. Home keeps exactly the same shape whether or not a
// dose is due, and the discharge lands where the hand already goes.
//
// The secondary closures move behind a long press, because putting Adjust and
// Skip on the row would rebuild the card this attempt exists to avoid.
//
// What it trades away: discoverability, entirely. A control that changes meaning
// teaches nothing, and a developer who has not read this file has no way to know
// that the Dose button now logs rather than opens the sheet. It also has nowhere
// to put a second outstanding dose — the morning and the evening both due would
// have to queue through one control — and the lateness has to fit on one line
// beside the amount.
//
// Like attempt 1 it reads the LEDGER, not a notification, so the
// refused-authorisation path (Req 7.2) is the same feature rather than a
// degraded one. No adherence percentage, no streak, no compliance score.
struct OutstandingDoseControl: View {
    let dose: OutstandingDose
    let onLog: () -> Void
    let onAdjust: () -> Void
    let onSkip: () -> Void

    @State private var showsSecondary = false

    var body: some View {
        Button(action: onLog) {
            HStack(spacing: 12) {
                Image(systemName: "syringe")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Log \(DoseScheduleModel.unitsLabel(dose.schedule.nominalUnits)) \(dose.schedule.kind.rawValue)")
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption2)
                        .opacity(0.75)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.captureBackground)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(.medataAccent)
        .accessibilityIdentifier("dose.log")
        // A long press is the only affordance for the two uncommon closures.
        // That is the cost of not adding a surface, and it is deliberate rather
        // than an oversight.
        .onLongPressGesture { showsSecondary = true }
        .confirmationDialog(
            DoseScheduleModel.reminderTitle(for: dose.schedule),
            isPresented: $showsSecondary,
            titleVisibility: .visible
        ) {
            Button("Adjust") { onAdjust() }
                .accessibilityIdentifier("dose.adjust")
            Button("Skip") { onSkip() }
                .accessibilityIdentifier("dose.skip")
            Button("Cancel", role: .cancel) {}
        }
    }

    // A time and an elapsed interval, on one line. Both are facts about the
    // occurrence and neither is a judgement about the developer.
    private var subtitle: String {
        let due = String(format: "%02d:%02d", dose.schedule.hour, dose.schedule.minute)
        let late = dose.lateness
        if late < 60 { return "due \(due)" }
        if late < 3600 { return "due \(due) · \(Int(late / 60)) min" }
        return "due \(due) · \(Int(late / 3600)) h"
    }
}

import Persistence
import SwiftUI

// UI ATTEMPT 1 at the in-app outstanding-dose surface (specs/data/dose-schedule
// Req 2.4, 4.5; tagged `dose-schedule-ui-attempt-1`).
//
// The bet: an outstanding dose deserves its own surface. A dedicated card sits
// on Home above every route, states the dose and how late it is, and offers all
// three closures — Log, Adjust, Skip — as visible controls. Nothing is hidden
// behind a gesture and nothing is inferred from a control changing meaning.
//
// What it trades away: permanent vertical space on the launch screen for a card
// that is absent most of the day, and a third surface competing with Capture
// for the eye. The Log control is the largest thing on Home whenever it exists,
// which is either exactly right or exactly wrong depending on how a real
// morning feels.
//
// It reads the LEDGER, not a notification: the card renders whenever an
// occurrence is outstanding, with no dependence on a notification having been
// delivered or seen. That is what makes the refused-authorisation path
// (Req 7.2) the same feature rather than a degraded one.
//
// No adherence percentage, no streak, no compliance score, no comparison
// against a target. Outstanding state is tracked because the reminder cannot
// function without it; scoring the developer on it stays out of scope.
struct OutstandingDoseBanner: View {
    let dose: OutstandingDose
    let onLog: () -> Void
    let onAdjust: () -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            HStack(spacing: 10) {
                logButton
                secondaryButton("Adjust", identifier: "dose.adjust", action: onAdjust)
                secondaryButton("Skip", identifier: "dose.skip", action: onSkip)
            }
        }
        .padding(16)
        .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("dose.outstanding")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DoseScheduleModel.reminderTitle(for: dose.schedule))
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(Color.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // A time and an elapsed interval. Both are facts about the occurrence, and
    // neither is a judgement about the developer.
    private var subtitle: String {
        let due = String(format: "%02d:%02d", dose.schedule.hour, dose.schedule.minute)
        let late = dose.lateness
        if late < 60 { return "Due \(due)" }
        if late < 3600 { return "Due \(due) · \(Int(late / 60)) min" }
        return "Due \(due) · \(Int(late / 3600)) h"
    }

    private var logButton: some View {
        Button(action: onLog) {
            Text("Log \(DoseScheduleModel.unitsLabel(dose.schedule.nominalUnits))")
                .font(.headline)
                .foregroundStyle(Color.captureBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(.medataAccent)
        .accessibilityIdentifier("dose.log")
    }

    private func secondaryButton(
        _ title: String, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .background(Color.surfacePrimary, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

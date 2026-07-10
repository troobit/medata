import SwiftUI

// The home page — launch root and the app's router (home-router Req 1). A pure
// router (Decision 2): six controls, no summary data, and no presentation
// state of its own — each control fires a closure injected by AppRoot, which
// owns the cover/sheet state (Decision 9). Capture is the primary action
// (Req 1.3), accent-prominent per the established capture treatment.
// NOTE: sizing/`contentShape` live INSIDE each Button label — a Button's tap
// gesture covers only its label, so outside modifiers draw a dead surface
// (ui-capture-flow.md gotcha).
struct HomeView: View {
    let onCapture: () -> Void
    let onIntake: () -> Void
    let onDose: () -> Void
    let onRecords: () -> Void
    let onGraph: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("MeData")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
            captureButton
            routeButton("Intake", systemImage: "fork.knife", identifier: "home.intake", action: onIntake)
            routeButton("Dose", systemImage: "syringe", identifier: "home.dose", action: onDose)
            routeButton("Records", systemImage: "square.stack.3d.up", identifier: "home.records", action: onRecords)
            routeButton("Graph", systemImage: "chart.xyaxis.line", identifier: "home.graph", action: onGraph)
            routeButton("Settings", systemImage: "gearshape.fill", identifier: "home.settings", action: onSettings)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.surfacePrimary)
    }

    // The primary action (Req 1.3): the largest control, accent-filled via the
    // same `.borderedProminent` + `.tint(.medataAccent)` treatment the old
    // Graph-toolbar capture control carried. Dark foreground on the bright
    // accent, matching the metric-chip idiom.
    private var captureButton: some View {
        Button(action: onCapture) {
            Label("Capture", systemImage: "camera.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.captureBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderedProminent)
        .tint(.medataAccent)
        .accessibilityIdentifier("home.capture")
    }

    // The five secondary routes: one consistent full-width treatment on the
    // elevated surface (statCard idiom).
    private func routeButton(
        _ title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

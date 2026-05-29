import Pipeline
import SwiftUI

// Live-condition indicators consumed only by this view so the high-churn
// per-frame writes (tilt / distance / coverage) don't retrigger the whole
// capture view body. Renders the tilt indicator, distance state, LiDAR
// coverage gauge, and the active capture-mode label.
struct LiveIndicatorView: View {
    @Bindable var model: LiveIndicatorModel
    let supportsLiDAR: Bool
    let activeMode: CaptureMode
    var targetTiltDegrees: Float = 0

    private var tiltInRange: Bool {
        abs(model.liveTiltDegrees - targetTiltDegrees) <= 5
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tiltRow
            distanceRow
            if supportsLiDAR { coverageRow }
            modeRow
        }
        .font(.footnote)
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }

    private var tiltRow: some View {
        HStack {
            Image(systemName: tiltInRange ? "level.fill" : "level")
                .foregroundStyle(tiltInRange ? Color.medataAccent : .secondary)
            Text("Tilt \(Int(model.liveTiltDegrees.rounded()))°")
            Spacer()
            Text(tiltInRange ? "Level" : "Adjust angle")
                .foregroundStyle(tiltInRange ? Color.medataAccent : .secondary)
        }
    }

    @ViewBuilder
    private var distanceRow: some View {
        HStack {
            Image(systemName: "ruler")
            if supportsLiDAR, let cm = model.liveDistanceCm {
                let ok = cm >= 25 && cm <= 50
                Text("Distance \(Int(cm.rounded())) cm")
                Spacer()
                Text(ok ? "In range" : "Move to 25–50 cm")
                    .foregroundStyle(ok ? Color.medataAccent : .secondary)
            } else {
                // No LiDAR ⇒ static guidance, no distance gate (§3.2).
                Text("Hold about 30–40 cm away")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var coverageRow: some View {
        HStack {
            Image(systemName: "square.stack.3d.up")
            Text("Depth coverage")
            Spacer()
            ProgressView(value: Double(model.liveLiDARCoveragePercent), total: 100)
                .frame(width: 80)
            Text("\(Int(model.liveLiDARCoveragePercent.rounded()))%")
        }
    }

    private var modeRow: some View {
        HStack {
            Image(systemName: activeMode == .single ? "viewfinder" : "viewfinder.rectangular")
            Text(activeMode == .single ? "Single-view (LiDAR)" : "Two-view")
            Spacer()
            // Surface which distance gating mode is active (§3.3).
            Text(supportsLiDAR ? "Measured" : "Guidance")
                .foregroundStyle(.secondary)
        }
    }
}

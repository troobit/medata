import SwiftUI

/// Capture variant A — sequential, telemetry-first. No conversational copy:
/// live tilt/distance/sensor data, a bubble level for guidance, and an
/// explicit 1-view / 2-view mode toggle (req §3.5).
struct CaptureView: View {
    @EnvironmentObject var env: AppEnvironment
    @State private var path: [Route] = []
    @State private var showingFork = false
    @State private var twoViewMode = false
    var onOpenHistory: () -> Void
    var onOpenSettings: () -> Void
    var onOpenTrends: () -> Void = {}

    var body: some View {
        ZStack {
            // Viewfinder placeholder. Real implementation hosts AVCaptureVideoPreviewLayer
            // / ARView behind this stack.
            ViewfinderBackdrop()
            CaptureGuideOverlay()
            VStack {
                topBar
                HStack {
                    Spacer()
                    BubbleLevelView(withinTolerance: true)
                        .padding(.trailing, DS.spacingL)
                        .padding(.top, DS.spacingM)
                }
                Spacer()
                bottomChrome
            }
        }
        .navigationBarHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(.all, edges: .top)
        .sheet(isPresented: $showingFork) {
            LidarForkSheet()
                .presentationDetents([.medium])
        }
    }

    private var topBar: some View {
        HStack {
            Button { /* dismiss */ } label: {
                Image(systemName: "xmark")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.35), in: Circle())
            }
            Spacer()
            Text(twoViewMode ? "2-VIEW · NADIR" : "1-VIEW · LiDAR")
                .font(.caption.monospaced().weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.35), in: Capsule())
            Spacer()
            HStack(spacing: DS.spacingS) {
                Button { onOpenTrends() } label: {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.35), in: Circle())
                }
                Button { onOpenHistory() } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(.black.opacity(0.35), in: Circle())
                }
            }
        }
        .padding(.horizontal, DS.spacingL)
        .padding(.top, 60)
    }

    private var bottomChrome: some View {
        VStack(spacing: DS.spacingM) {
            // Telemetry — data only, no conversational copy.
            HStack(spacing: DS.spacingM) {
                telemetryItem("tilt", "1.8°")
                telemetryItem("dist", "34 cm")
                Label("LiDAR", systemImage: "circle.fill")
                    .font(.caption2.monospaced())
                    .foregroundStyle(DS.success)
                    .labelStyle(.titleAndIcon)
                    .imageScale(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.black.opacity(0.35), in: Capsule())

            HStack {
                // Tap toggles 1-view / 2-view; long-press opens the
                // capture-path fork sheet with details.
                Text(twoViewMode ? "2-VIEW" : "1-VIEW")
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.black.opacity(0.35), in: Circle())
                    .onTapGesture { twoViewMode.toggle() }
                    .onLongPressGesture { showingFork = true }
                Spacer()
                ShutterButton {
                    Task { await tryCapture() }
                }
                Spacer()
                Button { onOpenSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.title3).foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(.black.opacity(0.35), in: Circle())
                }
            }
            .padding(.horizontal, DS.spacingL)
        }
        .padding(.bottom, 30)
    }

    private func telemetryItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(label).foregroundStyle(.white.opacity(0.6))
            Text(value).foregroundStyle(.white)
        }
        .font(.caption2.monospaced())
    }

    private func tryCapture() async {
        do {
            let frame = try await MockCaptureService().capture(target: .nadir)
            let req = EstimationRequest(nadir: frame, oblique: nil, relativePose: nil, title: titleForNow())
            let meal = try await env.pipeline.estimate(req)
            env.mealStore.add(meal)
            // In a real app we'd push onto the parent's NavigationPath here.
        } catch {
            // No-op for the wireframe.
        }
    }

    private func titleForNow() -> String {
        let h = Calendar.current.component(.hour, from: .now)
        switch h {
        case 5..<11: return "Breakfast"
        case 11..<15: return "Lunch"
        case 15..<18: return "Snack"
        default: return "Dinner"
        }
    }
}

// MARK: - subviews

struct ViewfinderBackdrop: View {
    var body: some View {
        ZStack {
            Color.black
            // Striped placeholder so previews have something to look at.
            Canvas { ctx, size in
                let stripe: CGFloat = 16
                let count = Int((size.width + size.height) / stripe)
                for i in 0..<count {
                    let x = CGFloat(i) * stripe
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height + stripe/2, y: size.height))
                    path.addLine(to: CGPoint(x: x + stripe/2, y: 0))
                    path.closeSubpath()
                    ctx.fill(path, with: .color(.white.opacity(i.isMultiple(of: 2) ? 0.04 : 0.07)))
                }
            }
        }
        .ignoresSafeArea()
    }
}

struct ShutterButton: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(.white, lineWidth: 3).frame(width: 70, height: 70)
                Circle().fill(.white).frame(width: 58, height: 58)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Bubble level — green centered bubble when the phone is within ±5° of
/// flat; drifts and turns amber when off. Static in the wireframe; the real
/// implementation drives offset/state from CoreMotion.
struct BubbleLevelView: View {
    var withinTolerance: Bool
    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.9), lineWidth: 1.5)
            Circle()
                .stroke(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: 28, height: 28)
            Circle()
                .fill(withinTolerance ? DS.success : DS.warning)
                .frame(width: 14, height: 14)
                .offset(withinTolerance ? .zero : CGSize(width: 14, height: -8))
                .overlay(
                    Circle().stroke(.white, lineWidth: 1.5)
                        .frame(width: 14, height: 14)
                        .offset(withinTolerance ? .zero : CGSize(width: 14, height: -8))
                )
        }
        .frame(width: 76, height: 76)
        .background(.black.opacity(0.25), in: Circle())
    }
}

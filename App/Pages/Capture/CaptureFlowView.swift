import CaptureKit
import Pipeline
import SwiftUI

// Capture surface under the handoff-00 Graph-rooted shell (Req 2, design page
// `design-system/pages/capture.md`). Presented as a full-screen cover from the
// Graph root (Decision 20). Composes:
//   • top bar        — close control (top-leading), mode capsule (top-centre),
//                      `MedataBubbleLevel` (top-right)
//   • `TelemetryCapsule` — always-visible tilt / distance / LiDAR-dot chip
//   • transient surfaces — Initialising / hold steady / Capturing / Target 25°
//                      / blocked-gate chip
//   • bottom row     — mode button, `ShutterButton`
//   • `MedataLoadingSymbol` — over frozen frames during `.estimating`
// Behaviour lives in `CaptureFlowModel`; this is composition only. The effective
// capture mode is read via `@AppStorage` (with a LiDAR-aware default, Req 16.2)
// so fork-sheet / mode-button writes flow here without coupling. Torch is gone
// (Decision 14); the Trends/Data/Settings buttons moved to the Graph root
// (Decision 20).
struct CaptureFlowView: View {
    @Bindable var model: CaptureFlowModel
    let engine: ARKitCaptureEngine
    let store: any PersistenceStore
    let visionCardDetector: VisionCardDetector?
    let preShutterSegmenter: PreShutterSegmenter?

    // The Capture cover has no drag-to-dismiss; the top-leading close control
    // dismisses it back to Graph (Decision 20). Dismissing sets `AppRoot`'s
    // `activeSheet` to nil, which fires `captureModel.captureDismissed()`.
    @Environment(\.dismiss) private var dismiss

    init(
        model: CaptureFlowModel,
        engine: ARKitCaptureEngine,
        store: any PersistenceStore,
        visionCardDetector: VisionCardDetector? = nil,
        preShutterSegmenter: PreShutterSegmenter? = nil
    ) {
        self.model = model
        self.engine = engine
        self.store = store
        self.visionCardDetector = visionCardDetector
        self.preShutterSegmenter = preShutterSegmenter
    }

    @State private var observer: LiveSampleObserver?
    @State private var hasWarmedCardDetector = false
    // Empty string means the capture-mode key is unset — the effective mode then
    // forks on device capability (Req 16.2), mirroring `defaultCaptureModeReader`.
    @AppStorage(SettingsKeys.captureMode) private var captureModeRaw: String = ""
    @State private var showingForkSheet = false
    // Transient failing-gate chip shown above the shutter on a blocked tap
    // (design: parity audit — replaces the old badge reveal).
    @State private var blockedChip: String?
    @State private var blockedChipTask: Task<Void, Never>?

    private var effectiveMode: CaptureMode {
        if let m = CaptureMode(rawValue: captureModeRaw) { return m }
        return model.supportsLiDAR ? .single : .double
    }

    // Top-centre mode capsule text (Req 2.2): the current stage, monospaced.
    private var modeCapsuleText: String {
        if model.awaitingObliqueView { return "2-VIEW · OBLIQUE" }
        return effectiveMode == .double ? "2-VIEW · NADIR" : "1-VIEW · LiDAR"
    }

    var body: some View {
        NavigationStack(path: $model.navigationPath) {
            capture
                .navigationDestination(for: CaptureRoute.self) { route in
                    captureDestination(route)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
        }
        // Back-gesture soft-lock resync: popping the capture stack to empty via
        // the edge swipe / back chevron (e.g. from the review surface) leaves
        // `.showingResult` armed with no on-screen surface and a dead shutter.
        // `dismissResult()` is idempotent on an already-empty path (it only sets
        // the path to empty and returns to `.ready`), so this brings the flow
        // back to a live capture state.
        .onChange(of: model.navigationPath) { _, path in
            if path.isEmpty, case .showingResult = model.state {
                model.dismissResult()
            }
        }
    }

    // Capture-stack route (design: Navigation routes, reshaped by
    // specs/ui/meal-review). runEstimation pushes `.result` directly; the
    // single review surface carries outlines, relabel/reject and the
    // serving/gram/scale controls — no intermediate screen.
    @ViewBuilder
    private func captureDestination(_ route: CaptureRoute) -> some View {
        switch route {
        case .result(let record):
            MealReviewView(
                record: record,
                store: store,
                onRecord: { model.dismissResult() },
                // Retake and Delete both discard the just-captured meal (it is
                // already persisted) and return to Capture (Decision 17). The
                // review model has already stamped capture_abandoned on the
                // correction rows, which survive the delete (Req 9.10).
                onRetake: { model.deleteAndDismiss(record) },
                onDelete: { model.deleteAndDismiss(record) }
            )
        }
    }

    // Full-bleed capture chrome (Req 2.1). The AR preview is the content; the
    // chrome is a top bar (close control + mode capsule + bubble level), a
    // telemetry capsule and transient surfaces above the shutter, and a bottom
    // row (mode / shutter). `.permissionDenied` keeps the top bar (with its
    // close control) rendered while disabling the shutter and mode (Req 1.6).
    private var capture: some View {
        ZStack {
            backgroundLayer

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                // While aiming the oblique view, show the banked nadir as a
                // top-trailing inset so the user can confirm their top-down shot
                // landed. Hidden during `.estimating`.
                if model.awaitingObliqueView, !isEstimating, let nadir = model.capturedNadirFrame {
                    HStack {
                        Spacer()
                        NadirThumbnailView(frame: nadir)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                Spacer()
                if isPermissionDenied { permissionDeniedMessage }
                Spacer()
                bottomArea
            }

            if isEstimating { estimatingOverlay }

            // §4 error state: full-screen overlay replacing the old RefusalSheet.
            if let refusal = model.refusal {
                CaptureErrorOverlay(
                    failure: refusal.failure,
                    onRetry: { model.retry() },
                    onTwoView: { model.switchToTwoViewAndRetry() },
                    onCancel: { model.dismissRefusal() }
                )
                .transition(.opacity)
                // Composite above the live AR layer and freeze-frame so its
                // Retry/2-view buttons receive touches. Without this the
                // ARPreviewView representable underneath could intercept taps in
                // the centre of the overlay (only Cancel, lower down, responded).
                .zIndex(1)
            }
        }
        .sheet(isPresented: $showingForkSheet) {
            LidarForkSheetView(model: model)
        }
        .onAppear {
            let obs = observer ?? LiveSampleObserver(model: model)
            observer = obs
            obs.start(frames: engine.frames)
            // Each `engine.frames` call returns an independent per-subscriber
            // stream (ARKitCaptureEngine.swift:111), so the pre-shutter
            // producer's subscription is disjoint from the live observer's.
            preShutterSegmenter?.resume(frames: engine.frames)
        }
        .onDisappear { observer?.stop() }
        .onChange(of: shouldProducePreShutter) { _, newValue in
            // Req 1.4 / Decision 5: producer halts in capturing / estimating /
            // result / refused, resumes on return to a producing state. Each
            // resume gets a fresh per-subscriber stream from `engine.frames`.
            if newValue {
                preShutterSegmenter?.resume(frames: engine.frames)
            } else {
                preShutterSegmenter?.pause()
            }
        }
        .onChange(of: isReady) { _, ready in
            // Req 5.7: warm the Vision request once on first entry to
            // `.ready` so the first shutter-tap of a session pays warm-path
            // latency only. `Task { ... }` is fire-and-forget; warmup is
            // cancellable internally and never blocks the live indicator
            // stream.
            guard ready, !hasWarmedCardDetector, let detector = visionCardDetector else { return }
            hasWarmedCardDetector = true
            Task { await detector.warmup() }
        }
    }

    // Mirror of the state-machine gating in the design's "State-machine
    // gating" section. Producer runs when the flow is in a state where the
    // user can still adjust framing (initialising / ready / trackingLost);
    // pauses in transient states where the result would be discarded.
    private var shouldProducePreShutter: Bool {
        switch model.state {
        case .initialising, .ready, .trackingLost: return true
        default: return false
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        if case .estimating(let result) = model.state {
            // Freeze the viewfinder during estimation: swap the live AR feed for
            // the captured frame(s) the estimator is working from, blurred and
            // dimmed, so the user sees the photo is taken and can put the phone
            // down. The MedataLoadingSymbol renders over this in `estimatingOverlay`.
            CapturedFramesView(result: result)
                .blur(radius: 18)
                .overlay(Color.captureBackground.opacity(0.25))
                .ignoresSafeArea()
        } else if isPermissionDenied {
            Color.captureBackground.ignoresSafeArea()
        } else {
            // Stop the AR view from hit-testing while the refusal overlay is up,
            // so its buttons — not the live camera layer — receive the taps.
            ARPreviewView(engine: engine)
                .ignoresSafeArea()
                .allowsHitTesting(model.refusal == nil)
        }
    }

    // MARK: - Top bar (Req 2.1)

    private var topBar: some View {
        ZStack {
            // Mode capsule, top-centre (Req 2.2). Hidden while denied.
            if !isPermissionDenied {
                Text(modeCapsuleText)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(Color.captureChromeText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.captureChromeBG, in: Capsule())
                    .frame(maxWidth: .infinity, alignment: .center)
                    .accessibilityIdentifier("modeCapsule")
            }
            HStack(alignment: .top) {
                // Close control, top-leading (Req 2.1): dismisses the Capture
                // cover back to Graph. Reuses `CloseCoverButton` (xmark,
                // accessibility `Close`), wrapped in a 40pt chrome circle to
                // match the capture aesthetic. Remains usable while permission
                // is denied (Req 1.6).
                CloseCoverButton { dismiss() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.captureChromeText)
                    .frame(width: 40, height: 40)
                    .background(Color.captureChromeBG, in: Circle())
                Spacer()
                // Bubble level, top-right (Req 2.1). Hidden while denied.
                if !isPermissionDenied {
                    MedataBubbleLevel(
                        tiltVector: model.indicators.liveTiltVector,
                        awaitingOblique: model.awaitingObliqueView
                    )
                }
            }
        }
    }

    // MARK: - Bottom area (Req 2.1)

    @ViewBuilder
    private var bottomArea: some View {
        VStack(spacing: 12) {
            transientStatus
            if !isPermissionDenied, !isEstimating {
                TelemetryCapsule(model: model.indicators, supportsLiDAR: model.supportsLiDAR)
            }
            bottomRow
            Color.clear.frame(height: ShutterButtonMetrics.bottomClearance)
        }
        .padding(.bottom, 8)
    }

    // Transient state surfaces above the shutter (Req 2.1 clause; copy inventory).
    @ViewBuilder
    private var transientStatus: some View {
        if let hint = transientHint {
            Label(hint.text, systemImage: hint.symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.captureChromeText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.captureChromeBG, in: Capsule())
                .accessibilityIdentifier(hint.identifier)
        }
    }

    // Ordered so the most urgent surface wins: capture/estimation states, then
    // the blocked-shutter chip, then the oblique guidance.
    private var transientHint: (text: String, identifier: String, symbol: String)? {
        switch model.state {
        case .initialising: return ("Initialising", "hint.initialising", "hourglass")
        case .trackingLost: return ("hold steady", "hint.trackingLost", "arrow.triangle.2.circlepath")
        case .capturing: return ("Capturing", "hint.capturing", "camera")
        case .estimating: return nil // the loading symbol owns this state
        default: break
        }
        if let chip = blockedChip {
            return (chip, "hint.blocked", "exclamationmark.circle")
        }
        if let message = model.obliqueTiltMessage {
            return (message, "hint.obliqueTilt", "rotate.3d")
        }
        return nil
    }

    private var bottomRow: some View {
        ZStack {
            ShutterButton(
                state: shutterState,
                action: { model.shutter() },
                onBlockedTap: {
                    model.shutterBlockedTapped()
                    flashBlockedChip()
                }
            )
            // Mode button leading, shutter centred. Settings moved to the Graph
            // root (Decision 20), so the trailing slot is empty.
            HStack {
                modeButton
                Spacer()
            }
        }
        .padding(.horizontal, 32)
    }

    // Bottom-left mode button (Req 2.5): tap toggles 1-view/2-view; long-press
    // opens the capture-path fork sheet (§3). Disabled while denied or busy.
    private var modeButton: some View {
        Text(effectiveMode == .double ? "2-VIEW" : "1-VIEW")
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .foregroundStyle(Color.captureChromeText)
            .frame(width: 64, height: 40)
            .background(Color.captureChromeBG, in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { toggleMode() }
            .onLongPressGesture { showingForkSheet = true }
            .opacity(isPermissionDenied || model.isBusy ? 0.4 : 1)
            .disabled(isPermissionDenied || model.isBusy)
            .accessibilityLabel("Capture mode")
            .accessibilityIdentifier("modeButton")
    }

    private func toggleMode() {
        // Non-LiDAR devices are locked to two-view (Req 3.3); tapping is a no-op.
        guard model.supportsLiDAR else { return }
        captureModeRaw = (effectiveMode == .single ? CaptureMode.double : .single).rawValue
    }

    // MedataLoadingSymbol over the frozen frames during estimation (§1.3,
    // closes ldsym06). Accessibility label `Estimating` per the copy inventory.
    private var estimatingOverlay: some View {
        MedataLoadingSymbol(mode: .loop)
            .accessibilityElement()
            .accessibilityLabel("Estimating")
            .accessibilityIdentifier("hint.estimating")
    }

    // Centred refusal copy for `.permissionDenied` (Req 1.6). The top bar (with
    // its close control) stays rendered; only the shutter and mode are disabled,
    // so the user can always dismiss the Capture cover from the refusal state.
    private var permissionDeniedMessage: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 44))
                .foregroundStyle(Color.captureChromeText.opacity(0.7))
            Text(permissionDeniedText)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.captureChromeText)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("permissionDenied.message")
            Button("Open Settings") { model.openSettings() }
                .font(.body.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .tint(.medataAccent)
        }
        .padding(.horizontal, 32)
    }

    private var permissionDeniedText: String {
        if case .permissionDenied(.motion) = model.state { return "Motion access denied" }
        return "Camera access denied"
    }

    private func flashBlockedChip() {
        blockedChip = model.failingShutterGate ?? "wait"
        blockedChipTask?.cancel()
        blockedChipTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if !Task.isCancelled { blockedChip = nil }
        }
    }

    private var isPermissionDenied: Bool {
        if case .permissionDenied = model.state { return true }
        return false
    }

    private var isReady: Bool {
        if case .ready = model.state { return true }
        return false
    }

    private var isEstimating: Bool {
        if case .estimating = model.state { return true }
        return false
    }

    private var shutterState: ShutterButtonState {
        if isPermissionDenied { return .disabled }
        if model.isBusy { return .capturing }
        return model.canShutter ? .ready : .disabled
    }

}

// Static rendering of the captured frame(s) shown in place of the live
// `ARPreviewView` during `.estimating` (Req §"Freeze viewfinder"). Single mode
// shows the nadir frame filling the safe area; two-view mode stacks nadir over
// oblique so the user sees BOTH photos were taken. Vertical stacking reads
// better than side-by-side here: each captured buffer is itself landscape
// (1920×1440), so two of them sit naturally one above the other in the portrait
// safe area without per-frame letterboxing.
private struct CapturedFramesView: View {
    let result: CaptureResult

    var body: some View {
        GeometryReader { proxy in
            // Nadir fills the whole safe area in single mode; in two-view mode it
            // takes the top half and the oblique the bottom half.
            let nadirHeight = obliqueImage == nil ? proxy.size.height : proxy.size.height / 2
            VStack(spacing: 0) {
                frameImage(result.nadirFrame)
                    .frame(width: proxy.size.width, height: nadirHeight)
                    .clipped()
                if let oblique = obliqueImage {
                    Image(decorative: oblique, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height / 2)
                        .clipped()
                }
            }
        }
        .accessibilityIdentifier("capturedFrames")
    }

    @ViewBuilder
    private func frameImage(_ frame: RawFrame) -> some View {
        if let cgImage = RawFrameImage.cgImage(frame) {
            Image(decorative: cgImage, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            Color.captureBackground
        }
    }

    private var obliqueImage: CGImage? {
        guard let oblique = result.obliqueFrame else { return nil }
        return RawFrameImage.cgImage(oblique)
    }
}

// Small labelled thumbnail of the banked nadir frame, shown over the live
// viewfinder while the user aims the oblique view so they can confirm their
// top-down shot landed (smolspec no-food-pixels-on-fruit-plate-mvp). Renders
// nothing if the frame fails to decode. Full review / select / retake of the
// captured frames is deferred to a future spec.
private struct NadirThumbnailView: View {
    let frame: RawFrame

    private let width: CGFloat = 96
    // Captured buffers are landscape ~4:3 (e.g. 1920×1440).
    private var height: CGFloat { width * 3 / 4 }

    var body: some View {
        if let cgImage = RawFrameImage.cgImage(frame) {
            VStack(alignment: .leading, spacing: 4) {
                Image(decorative: cgImage, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.captureChromeText, lineWidth: 1)
                    )
                Label("Nadir", systemImage: "checkmark.circle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.captureChromeText)
            }
            .accessibilityIdentifier("capturedNadirThumbnail")
        } else {
            EmptyView()
        }
    }
}
// The standalone `PermissionDeniedView` (full-screen, no chrome) was folded
// into the capture layout in the handoff-00 chrome rebuild: the denial copy is
// centred while the top bar (with its close control) stays rendered (Req 1.6) —
// see `permissionDeniedMessage`.

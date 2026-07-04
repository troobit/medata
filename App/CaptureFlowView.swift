import CaptureKit
import Pipeline
import SwiftUI

// Root of the Photo tab (UI Req §20 / Decision 16). Composes:
//   • `CaptureTopBar`            — close + flash/torch (top chrome)
//   • `LiveIndicatorBadge`       — consolidated tilt/distance/coverage chip
//   • `CaptureModeToggle`        — capsule pill above the shutter
//   • `ShutterButton`            — 76pt circle with press feedback
//   • `RefusalSheet`             — bottom-sheet refusal surface
// Behaviour lives in `CaptureFlowModel`; this is composition only.
// CaptureMode (Decision 35) is read via `@AppStorage` so any UI toggle change
// flows here without coupling.
// The persistent tilt guide is `TiltBubbleGuide` — a 2-D attitude level whose
// dot distance encodes tilt and direction encodes azimuth.
struct CaptureFlowView: View {
    @Bindable var model: CaptureFlowModel
    let engine: ARKitCaptureEngine
    let store: any PersistenceStore
    let visionCardDetector: VisionCardDetector?
    let preShutterSegmenter: PreShutterSegmenter?
    // Capture-chrome buttons open the Data / Trends / Settings sheets through
    // these closures (the shell owns the single `ActiveSheet` state — Decision 11).
    let onOpenData: () -> Void
    let onOpenTrends: () -> Void
    let onOpenSettings: () -> Void

    init(
        model: CaptureFlowModel,
        engine: ARKitCaptureEngine,
        store: any PersistenceStore,
        visionCardDetector: VisionCardDetector? = nil,
        preShutterSegmenter: PreShutterSegmenter? = nil,
        onOpenData: @escaping () -> Void = {},
        onOpenTrends: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {}
    ) {
        self.model = model
        self.engine = engine
        self.store = store
        self.visionCardDetector = visionCardDetector
        self.preShutterSegmenter = preShutterSegmenter
        self.onOpenData = onOpenData
        self.onOpenTrends = onOpenTrends
        self.onOpenSettings = onOpenSettings
    }

    @State private var observer: LiveSampleObserver?
    @State private var hasWarmedCardDetector = false

    var body: some View {
        NavigationStack(path: $model.navigationPath) {
            content
                .navigationDestination(for: CaptureRoute.self) { route in
                    captureDestination(route)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    // Capture-stack routes (design: Navigation routes). runEstimation pushes
    // `.review`; its Carbs action pushes `.result`; `Adjust` pushes `.correction`.
    @ViewBuilder
    private func captureDestination(_ route: CaptureRoute) -> some View {
        switch route {
        case .review(let record):
            SegmentationReviewView(record: record, onCarbs: {
                model.navigationPath.append(CaptureRoute.result(record))
            })
        case .result(let record):
            ResultView(
                record: record,
                mode: .justCaptured,
                onNewCapture: { model.dismissResult() },
                onRetake: { model.dismissResult() }
            )
        case .correction(let record):
            ManualCorrectionView(record: record, onSave: { model.popRoute() })
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .permissionDenied(let subject):
            PermissionDeniedView(subject: subject) { model.openSettings() }
        default:
            capture
        }
    }

    private var capture: some View {
        ZStack {
            Color.captureBackground.ignoresSafeArea()
            // Freeze the viewfinder during estimation: swap the live AR feed for
            // the captured frame(s) the estimator is working from, so the user
            // sees the photo is taken and can put the phone down (Req §"Freeze
            // viewfinder"). Every other state shows the live preview; the chrome
            // VStack below renders unchanged over whichever layer is shown.
            if case .estimating(let result) = model.state {
                // Blur + dim the frozen capture so the viewfinder reads as
                // "processing" — the same pause the tilt guide shows, applied to
                // the camera. The live AR feed is not rendered here at all.
                CapturedFramesView(result: result)
                    .blur(radius: 18)
                    .overlay(Color.captureBackground.opacity(0.25))
                    .ignoresSafeArea()
            } else {
                ARPreviewView(engine: engine).ignoresSafeArea()
            }

            VStack(spacing: 0) {
                CaptureTopBar()
                    .padding(.top, 8)
                // While aiming the oblique view, show the banked nadir as a
                // top-trailing inset so the user can confirm their top-down
                // shot landed. Hidden during `.estimating`, when
                // `CapturedFramesView` already shows both frames full-screen.
                if model.awaitingObliqueView, !isEstimating, let nadir = model.capturedNadirFrame {
                    HStack {
                        Spacer()
                        NadirThumbnailView(frame: nadir)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                }
                Spacer().frame(height: 24)
                if isEstimating {
                    // Viewfinder is frozen during estimation; swap the live
                    // tilt/distance/coverage badge for the "Estimating…" hint so
                    // the chrome stops reading as a live camera (Req §"Freeze
                    // viewfinder").
                    initialisingHint
                } else if model.currentSnapshot != nil, !isInitialising {
                    LiveIndicatorBadge(
                        model: model.indicators,
                        supportsLiDAR: model.supportsLiDAR,
                        isReady: isReady,
                        targetTiltDegrees: model.awaitingObliqueView ? 25 : 0
                    )
                } else {
                    initialisingHint
                }
                Spacer()
                bottomChrome
            }

            // Persistent graphical tilt guide, leading-aligned and vertically
            // centred over the viewfinder. Unlike the badge — which auto-hides 5s
            // after framing is in range (LiveIndicatorModel.scheduleHide) — this
            // stays on screen the whole time the user is aiming, so the angle
            // target never disappears mid-adjustment. Shown under the same
            // condition as the badge; never takes hits so it can't block chrome.
            if model.currentSnapshot != nil, !isEstimating, !isInitialising {
                HStack {
                    tiltGuide
                        .padding(.leading, 16)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .sheet(item: refusalBinding) { refusal in
            RefusalSheet(failure: refusal.failure) { model.retry() }
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

    @ViewBuilder
    private var bottomChrome: some View {
        VStack(spacing: 16) {
            if isEstimating {
                // Viewfinder is frozen during estimation; suppress the live
                // tilt message, mode toggle and shutter so the chrome stops
                // reading as a live camera, but keep the clearance spacer so the
                // layout footprint is preserved (Req §"Freeze viewfinder").
                Color.clear.frame(height: ShutterButtonMetrics.bottomClearance)
            } else {
                // Decision 18 / research Decision 43: nadir captures always
                // proceed regardless of tilt; the oblique stage retains a
                // |Δθ − 25°| ≤ 30° hard cap. When the user is on the oblique
                // stage but outside the cap, surface the Irish-English failure
                // copy above the shutter so the disabled state has a written
                // explanation (Req §2.3).
                if let message = model.obliqueTiltMessage {
                    Text(message)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.captureChromeText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.captureChromeBG, in: Capsule())
                        .accessibilityIdentifier("hint.obliqueTilt")
                }
                CaptureModeToggle(supportsLiDAR: model.supportsLiDAR, interactive: !model.isBusy)
                    .padding(.horizontal, 48)
                ShutterButton(
                    state: shutterState,
                    action: { model.shutter() },
                    onBlockedTap: { model.shutterBlockedTapped() }
                )
                Color.clear.frame(height: ShutterButtonMetrics.bottomClearance)
            }
        }
    }

    // Persistent tilt guide: the 2-D attitude level reading live tilt and stage.
    private var tiltGuide: some View {
        TiltBubbleGuide(
            tiltVector: model.indicators.liveTiltVector,
            awaitingOblique: model.awaitingObliqueView
        )
    }

    @ViewBuilder
    private var initialisingHint: some View {
        let hint: (text: String, identifier: String, symbol: String)? = {
            switch model.state {
            case .initialising: return ("Initialising…", "hint.initialising", "hourglass")
            case .trackingLost: return ("Tracking lost — hold steady", "hint.trackingLost", "arrow.triangle.2.circlepath")
            case .estimating: return ("Estimating…", "hint.estimating", "hourglass")
            case .capturing: return ("Capturing…", "hint.capturing", "camera")
            default: return nil
            }
        }()
        if let hint {
            Label(hint.text, systemImage: hint.symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.captureChromeText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.captureChromeBG, in: Capsule())
                .accessibilityIdentifier(hint.identifier)
        }
    }

    private var isInitialising: Bool {
        if case .initialising = model.state { return true }
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
        if model.isBusy { return .capturing }
        return model.canShutter ? .ready : .disabled
    }

    // Bridges `model.refusal` into a `Binding` for `.sheet(item:)`. A swipe-down
    // on the sheet writes `nil` here; the setter delegates to the model's
    // explicit dismissal command, which transitions `.refused → .ready` so the
    // sheet does not re-present on the next render (surface-not-detected
    // bugfix). `model.refusal` itself stays derived from state — there is no
    // separate stored refusal to keep in sync.
    private var refusalBinding: Binding<ActiveRefusal?> {
        Binding(
            get: { model.refusal },
            set: { newValue in
                if newValue == nil { model.dismissRefusal() }
            }
        )
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
        if let cgImage = decodeCGImage(from: frame) {
            Image(decorative: cgImage, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            Color.captureBackground
        }
    }

    private var obliqueImage: CGImage? {
        guard let oblique = result.obliqueFrame else { return nil }
        return decodeCGImage(from: oblique)
    }
}

// Inline `CGImage` decode from `RawFrame.imageBytes` + `.pixelFormat`. The
// bytes are BGRA8 after the rawframe-rgb-conversion fix; the switch keeps the
// other portable formats decodable too. No shared utility module per spec —
// this stays file-local so both the frozen `CapturedFramesView` and the
// oblique-aiming nadir thumbnail share one decode path.
fileprivate func decodeCGImage(from frame: RawFrame) -> CGImage? {
    let bytesPerPixel: Int
    let bitmapInfo: CGBitmapInfo
    switch frame.pixelFormat {
    case .rgb8:
        bytesPerPixel = 3
        bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
    case .rgba8:
        bytesPerPixel = 4
        bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
    case .bgra8:
        bytesPerPixel = 4
        bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
            .union(.byteOrder32Little)
    }
    let width = frame.imageWidth
    let height = frame.imageHeight
    let bytesPerRow = width * bytesPerPixel
    guard frame.imageBytes.count == bytesPerRow * height else { return nil }
    guard let provider = CGDataProvider(data: frame.imageBytes as CFData) else { return nil }
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: bytesPerPixel * 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: bitmapInfo,
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )
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
        if let cgImage = decodeCGImage(from: frame) {
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

// Permission-denied branch with a deep link to the app's iOS Settings (§1.3).
private struct PermissionDeniedView: View {
    let subject: PermissionSubject
    let openSettings: () -> Void

    private var message: String {
        switch subject {
        case .camera:
            return "MeData needs camera access to capture your meal. Enable it in Settings to continue."
        case .motion:
            return "MeData needs motion access for the tilt indicator. Enable it in Settings to continue."
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .padding(.horizontal)
            Button("Open Settings", action: openSettings)
                .buttonStyle(.borderedProminent)
                .tint(.medataAccent)
        }
        .padding()
    }
}

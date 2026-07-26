import ARKit
import CaptureKit
import OSLog
import Pipeline
import SwiftUI

@main
struct MedataApp: App {
    @State private var model: CaptureFlowModel
    @State private var engine: ARKitCaptureEngine
    @State private var visionCardDetector: VisionCardDetector?
    @State private var preShutterSegmenter: PreShutterSegmenter?
    @State private var glucoseConnections: GlucoseConnectionsModel
    private let store: any PersistenceStore
    @Environment(\.scenePhase) private var scenePhase

    #if DEBUG
    @State private var uiTestHarness: UITestHarness?
    #endif

    init() {
        Self.logLaunchIdentity()
        let engine = ARKitCaptureEngine()
        let store = Self.makeStore()
        _engine = State(initialValue: engine)
        self.store = store

        // Live glucose ingestion (cgm-connect Phase 4): one coordinator plus
        // both sources for the whole app. Constructed here (a stored property
        // must be initialised before the harness early-return), but the side
        // effects — BGTask registration and the launch reconnect — run below
        // it so harness launches stay hermetic.
        let glucose = GlucoseConnectionsModel(store: store)
        _glucoseConnections = State(initialValue: glucose)

        #if DEBUG
        if UITestSupport.isActive {
            let harness = UITestHarness()
            _model = State(initialValue: harness.model)
            _uiTestHarness = State(initialValue: harness)
            _visionCardDetector = State(initialValue: nil)
            _preShutterSegmenter = State(initialValue: nil)
            return
        }
        _uiTestHarness = State(initialValue: nil)
        #endif

        // BGTask registration must complete before the application finishes
        // launching; start() then registers the sources and reconnects any
        // the user has connected — sources hold no cross-launch sink, so
        // without this connect their catchUp()/background delivery would
        // no-op forever.
        glucose.registerBackgroundRefresh()
        glucose.start()

        // Vision-backed card detector (Req 5.1-5.7). Construct once at app
        // launch so the same instance is wired into Pipeline AND pre-warmed
        // by `CaptureFlowView` on entry to `.ready` (warmup reuses the same
        // `VNDetectRectanglesRequest` so the first shutter-tap pays warm-path
        // latency only).
        let cardDetector = VisionCardDetector()
        _visionCardDetector = State(initialValue: cardDetector)

        // Pre-shutter segmenter uses its OWN CoreMLSegmenter instance —
        // separate from the one PipelineFactory wires into Pipeline.estimate —
        // per Decision 12. Two `MLModel` loads at launch (< 50 ms) eliminate
        // the in-shutter / pre-shutter race entirely.
        let preShutter = PreShutterSegmenter(
            // `.livePreview` routes the ~2–3.5 Hz pre-shutter `segmenter.mask`
            // log to `.debug` so it does not flood the persisted unified-log
            // store and evict `launch` / `supportplane.end` (the on-device
            // plane-fit-refusal diagnostics). The Pipeline's own segmenter keeps
            // the default `.perCapture` (`.info`).
            segmenter: try! Pipeline.makeSegmenter(maskLog: .livePreview),
            // Must match PipelineFactory's palette (v2 since the ab812dc3aa9d
            // promotion) — a v1 palette against the 36-channel model misses
            // cereal in the arming predicate and misreads the sentinels
            // (bugfix app-palette-drift-after-v2-promotion).
            palette: .v2Standard,
            source: Pipeline.preShutterSourceTag == "pre_shutter_stub"
                ? .preShutterStub : .preShutterCoreML
        )
        _preShutterSegmenter = State(initialValue: preShutter)

        // Decision 42 / Req §23: real Pipeline backed by the dev-stub segmenter
        // under DEV_STUB_SEGMENTER (Phase 1, Debug). Release builds will throw
        // until Phase 3 bundles `segmenter.mlpackage`; `try!` is correct
        // because a missing model at launch is a development error, not a
        // recoverable runtime condition.
        //
        // Capture-bundle recorder (capture-bundle-recorder smolspec): every
        // attempt writes a replayable fixture into Documents/captures, which
        // Info.plist exposes via the Files app — the sole management surface.
        let capturesDir = URL.documentsDirectory.appendingPathComponent(
            "captures", isDirectory: true
        )
        let pipeline = try! Pipeline.makeForDevice(
            store: store,
            cardDetector: cardDetector,
            bundleRecorder: CaptureBundleRecorder(directoryURL: capturesDir)
        )
        _model = State(initialValue: CaptureFlowModel(
            session: CaptureSession(engine: engine),
            pipeline: pipeline,
            indicators: LiveIndicatorModel(),
            interruptions: engine.interruptions,
            supportsLiDAR: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth),
            databaseEdition: "CoFID 2024 + AFCD 2024",
            paletteVersion: "v2",
            // Slim capture-stage refusal records carry the same lineage tag
            // the pipeline stamps on its own outcome records (snaq-parity).
            segmenterSource: pipeline.segmenterSource,
            store: store,
            photoSaver: PhotoKitSaver(),
            preShutterSegmenter: preShutter
        ))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                AppRoot(
                    captureModel: model,
                    engine: engine,
                    store: store,
                    glucoseConnections: glucoseConnections,
                    visionCardDetector: visionCardDetector,
                    preShutterSegmenter: preShutterSegmenter
                )
                #if DEBUG
                if let uiTestHarness {
                    UITestControlPanel(harness: uiTestHarness)
                }
                #endif
            }
            .tint(.medataAccent)
            .onChange(of: scenePhase) { _, phase in
                model.scenePhaseChanged(phase)
                // Req 2.6 / 3.2: opening the app forces a glucose catch-up on
                // every connected source.
                if phase == .active {
                    glucoseConnections.catchUpConnectedSources()
                }
            }
        }
    }

    // One launch line identifying WHICH binary is running and WHICH segmenter
    // it binds — days were lost debugging against stale installs and against
    // the stub without realising. `MedataBuildStamp` lives in
    // MeData/Info.plist as `$(MEDATA_BUILD_STAMP)`, filled in by
    // `make build-app` / `make deploy-release-stub` (<git sha>-<timestamp>);
    // a plain Xcode Run leaves it empty => "unstamped". Always match this
    // stamp against the one the Make target printed before trusting a
    // captured trail.
    private static func logLaunchIdentity() {
        let plistStamp = Bundle.main.object(forInfoDictionaryKey: "MedataBuildStamp")
            as? String
        let stamp = (plistStamp?.isEmpty ?? true) ? "unstamped" : plistStamp!
        let source = Pipeline.preShutterSourceTag == "pre_shutter_stub" ? "stub" : "coreml"
        Logger(subsystem: "ie.medata.app", category: "Shutter")
            .info("event=launch buildStamp=\(stamp, privacy: .public) segmenterSource=\(source, privacy: .public)")
    }

    private static func makeStore() -> any PersistenceStore {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        do {
            return try GRDBPersistenceStore(
                dbURL: base.appendingPathComponent("meals.sqlite"),
                artefactsBaseURL: base
            )
        } catch {
            fatalError("Failed to open the meal store: \(error)")
        }
    }
}

#if DEBUG
// MARK: - XCUITest harness (DEBUG only)
//
// The capture flow is AR-gated: the shutter only arms once a live ARSession
// reaches `.ready`, and ARKit doesn't run on the simulator. So the XCUITests in
// MeData/UITests/ launch the app with `-uitest` and drive the flow through this
// deterministic harness instead of a real camera. None of this is compiled into
// release builds.
//
// Activation:
//   -uitest                    enable the harness
//   -uitestPipeline refuse     estimation throws .noScaleAvailable (default)
//   -uitestPipeline stall      estimation suspends so `.estimating` is observable
//
// `UITestControlPanel` exposes hidden buttons that call the model's public
// commands — these are the only seam the tests need, mirroring what
// LiveSampleObserver / the interruption stream would push at runtime.

enum UITestSupport {
    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-uitest")
    }

    enum PipelineMode: String {
        case refuse
        case stall
    }

    static var pipelineMode: PipelineMode {
        guard let raw = value(forArgument: "-uitestPipeline"),
              let mode = PipelineMode(rawValue: raw) else { return .refuse }
        return mode
    }

    static func makePipeline() -> any PipelineEstimator {
        switch pipelineMode {
        case .refuse: return RefusingPipeline()
        case .stall: return StallingPipeline()
        }
    }

    private static func value(forArgument name: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}

// CaptureEngine whose `captureFrame` blocks until the test releases it, so an
// XCUITest can observe the transient `.capturing` state before the frame returns.
private final class UITestCaptureEngine: CaptureEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: CheckedContinuation<RawFrame, Error>?

    func start() async throws {}

    func captureFrame(target: CaptureTarget) async throws -> RawFrame {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            pending = continuation
            lock.unlock()
        }
    }

    func release() async {}

    func releaseCapturedFrame() {
        lock.lock()
        let continuation = pending
        pending = nil
        lock.unlock()
        continuation?.resume(returning: .fixture())
    }
}

// XCUITest pipeline that refuses immediately, used to exercise the
// `.refused` state branch without spinning up the real pipeline (which would
// need a working ARSession + LiDAR depth, neither of which the simulator
// provides). The production refusal path is covered by `EstimationFailureTests`.
private struct RefusingPipeline: PipelineEstimator {
    func estimate(captureResult: CaptureResult, mode: CaptureMode) async throws -> MealRecord {
        throw EstimationFailure.noScaleAvailable
    }
}

// Suspends long enough that `.estimating` is observable, then refuses. Backgrounding
// cancels the wrapping Task (CancellationError), which the model swallows (Decision 12).
private struct StallingPipeline: PipelineEstimator {
    func estimate(captureResult: CaptureResult, mode: CaptureMode) async throws -> MealRecord {
        try await Task.sleep(nanoseconds: 30 * 1_000_000_000)
        throw EstimationFailure.noScaleAvailable
    }
}

@MainActor
final class UITestHarness {
    let model: CaptureFlowModel
    private let engine = UITestCaptureEngine()
    private let interruptionContinuation: AsyncStream<ARKitCaptureEngine.InterruptionEvent>.Continuation

    init() {
        let (stream, continuation) =
            AsyncStream<ARKitCaptureEngine.InterruptionEvent>.makeStream()
        interruptionContinuation = continuation
        model = CaptureFlowModel(
            session: CaptureSession(engine: engine),
            pipeline: UITestSupport.makePipeline(),
            indicators: LiveIndicatorModel(),
            interruptions: stream,
            supportsLiDAR: true,
            databaseEdition: "uitest",
            paletteVersion: "uitest",
            segmenterSource: "uitest",
            cameraAuthorisation: { .authorized },
            motionAvailable: { true }
        )
    }

    // Push the model from .initialising to .ready with in-range gating (tilt 0°,
    // 35 cm, 90% coverage) so the shutter arms — what LiveSampleObserver would
    // emit from a live ARFrame, which can't be synthesised on the simulator.
    func driveToReady() {
        model.liveSampleDidUpdate(
            tiltDegrees: 0,
            distanceCm: 35,
            lidarCoveragePercent: 90,
            trackingIsNormal: true
        )
    }

    func releaseCapture() { engine.releaseCapturedFrame() }
    func emitInterruptionBegan() { interruptionContinuation.yield(.began) }
    func emitInterruptionEnded() { interruptionContinuation.yield(.ended) }
}

// Hidden trigger controls pinned to the leading edge (clear of the shutter and
// the top banner) so XCUITests can drive transitions by accessibility identifier.
struct UITestControlPanel: View {
    let harness: UITestHarness

    var body: some View {
        VStack(spacing: 6) {
            Button("Ready") { harness.driveToReady() }
                .accessibilityIdentifier("uitest.driveToReady")
            Button("Release") { harness.releaseCapture() }
                .accessibilityIdentifier("uitest.releaseCapture")
            Button("Began") { harness.emitInterruptionBegan() }
                .accessibilityIdentifier("uitest.interruptionBegan")
            Button("Ended") { harness.emitInterruptionEnded() }
                .accessibilityIdentifier("uitest.interruptionEnded")
        }
        .buttonStyle(.bordered)
        .font(.caption2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(.leading, 4)
        .accessibilityIdentifier("uitest.controlPanel")
    }
}
#endif

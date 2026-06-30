import CardDetection
import CaptureKit
import Foods
import Foundation
import Segmentation
import SupportPlane

// Pipeline construction for device-MVP builds per design §2.5 / Decision 42 / Req §23.
//
// Selects the inference engine at compile time:
//   - DEV_STUB_SEGMENTER defined (Phase 1, Debug): `StubInferenceEngine` — no model
//     file required; stamps `segmenterSource = "dev_stub"`.
//   - DEV_STUB_SEGMENTER undefined (Phase 3, Release): `CoreMLInferenceEngine`
//     loading the bundled `segmenter.mlpackage`; stamps
//     `segmenterSource = "coreml_<modelVersion>"`. Throws on missing model.
//
// The bundled CoFID + AFCD food database (Decision 39) is loaded via
// `GRDBFoodDatabase.bundled()`. Production callers pass a Vision-backed
// `CardDetector` (the App target's `VisionCardDetector`); MedataCore tests
// pass `NullCardDetector()` (internal to the Pipeline module) or a custom
// mock conformance.

public enum PipelineFactoryError: Error, Equatable {
    // Phase 3: the bundled `segmenter.mlpackage` is not present in the
    // Pipeline target's resource bundle (`Bundle.module`). Phase 1 should
    // never reach this branch.
    case segmenterModelMissing
}

extension Pipeline {
    public static func makeForDevice(
        store: any PersistenceStore,
        cardDetector: any CardDetector,
        palette: ClassPalette = .v1Standard,
        supportPlaneFitter: any SupportPlaneFitter = LiDARSupportPlaneFitter()
    ) throws -> Pipeline {
        let foods = try GRDBFoodDatabase.bundled()
        let segmenter = try makeSegmenter(palette: palette)
        return Pipeline(
            cardDetector: cardDetector,
            segmenter: segmenter,
            database: foods,
            store: store,
            supportPlaneFitter: supportPlaneFitter,
            segmenterSource: segmenterSourceTag(for: segmenter)
        )
    }

    /// Constructs a `CoreMLSegmenter` using the same compile-time engine
    /// selection as `makeForDevice` (`StubInferenceEngine` under
    /// `DEV_STUB_SEGMENTER`, `CoreMLInferenceEngine` otherwise). App-target
    /// callers use this to build a SEPARATE pre-shutter segmenter from the
    /// one wired into `Pipeline` (Decision 12 of
    /// `specs/estimation/pipeline-real-device-correctness/`: pre-shutter and in-shutter
    /// must not share an `MLModel` instance).
    public static func makeSegmenter(palette: ClassPalette = .v1Standard) throws -> CoreMLSegmenter {
        let targetSize = SegmenterPreProcessor.defaultTargetSize
        #if DEV_STUB_SEGMENTER
        let engine: any SegmenterInferenceEngine = StubInferenceEngine(palette: palette)
        let modelPath = "/dev/null"
        let modelVersion: String? = nil
        #else
        let modelURL = try resolveBundledSegmenterURL()
        let coreEngine = try CoreMLInferenceEngine(
            modelPath: modelURL.path, targetSize: targetSize
        )
        let engine: any SegmenterInferenceEngine = coreEngine
        let modelPath = modelURL.path
        let modelVersion: String? = coreEngine.modelVersion
        #endif
        return CoreMLSegmenter(
            modelPath: modelPath, palette: palette, engine: engine,
            targetSize: targetSize, modelVersion: modelVersion
        )
    }

    /// Resolves the bundled `segmenter.mlpackage` produced by
    /// `tools/segmenter/export.py`, throwing `segmenterModelMissing` when the
    /// resource is absent (Req 5.2, 5.3).
    ///
    /// The model lives under the `Pipeline` target's own resource bundle
    /// (`Bundle.module`, declared via `.copy("Resources")` in `Package.swift`),
    /// not the app's `Bundle.main` (Req 5.1). It is looked up in the
    /// `Resources` subdirectory because `.copy` of a directory preserves that
    /// structure inside the bundle (see model-production Decision 7).
    ///
    /// This is kept as an always-compiled helper — separate from the
    /// `#if DEV_STUB_SEGMENTER` gate above — so the resolution contract is
    /// testable under the Debug / DEV_STUB SPM-test build, where the `#else`
    /// branch that calls it is compiled out.
    static func resolveBundledSegmenterURL(in bundle: Bundle = .module) throws -> URL {
        guard let url = bundle.url(
            forResource: "segmenter", withExtension: "mlpackage", subdirectory: "Resources"
        ) else {
            throw PipelineFactoryError.segmenterModelMissing
        }
        return url
    }

    /// `segmenterSource` tag stamped onto every `MealRecord` the given segmenter
    /// produces (Decision 42 / Req §23.6, 5.4). `"dev_stub"` under Phase 1 builds,
    /// `"coreml_<modelVersion>"` under Phase 3 / Release — where `<modelVersion>`
    /// is the loaded model's own version (the checkpoint SHA-256 prefix), so a
    /// persisted meal is traceable to its exact model build.
    public static func segmenterSourceTag(for segmenter: CoreMLSegmenter) -> String {
        #if DEV_STUB_SEGMENTER
        return "dev_stub"
        #else
        return coreMLSourceTag(
            modelVersion: segmenter.modelVersion ?? CoreMLInferenceEngine.fallbackModelVersion
        )
        #endif
    }

    /// Pure, always-compiled interpolation of a Core ML source tag. Kept out of
    /// the `#if DEV_STUB_SEGMENTER` gate so the `coreml_<version>` contract is
    /// testable under the Debug / DEV_STUB SPM-test build (Req 5.4).
    static func coreMLSourceTag(modelVersion: String) -> String {
        "coreml_\(modelVersion)"
    }

    /// Pre-shutter source tag matching the `PreShutterSegmenter.Source` enum
    /// raw values. Driven by the same compile-time gate as
    /// `segmenterSourceTag` so the App-target caller picks the right
    /// `pre_shutter_stub` / `pre_shutter_coreml` label without duplicating
    /// the `#if DEV_STUB_SEGMENTER` check.
    public static var preShutterSourceTag: String {
        #if DEV_STUB_SEGMENTER
        return "pre_shutter_stub"
        #else
        return "pre_shutter_coreml"
        #endif
    }
}

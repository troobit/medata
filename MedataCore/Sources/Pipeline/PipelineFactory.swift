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
    // app's main bundle. Phase 1 should never reach this branch.
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
            segmenterSource: segmenterSourceTag
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
        #else
        guard let modelURL = Bundle.main.url(
            forResource: "segmenter", withExtension: "mlpackage"
        ) else {
            throw PipelineFactoryError.segmenterModelMissing
        }
        let engine: any SegmenterInferenceEngine = try CoreMLInferenceEngine(
            modelPath: modelURL.path, targetSize: targetSize
        )
        let modelPath = modelURL.path
        #endif
        return CoreMLSegmenter(
            modelPath: modelPath, palette: palette, engine: engine, targetSize: targetSize
        )
    }

    /// `segmenterSource` tag stamped onto every `MealRecord` this pipeline
    /// produces (Decision 42 / Req §23.6). `"dev_stub"` under Phase 1 builds,
    /// `"coreml_<modelVersion>"` under Phase 3 / Release.
    public static var segmenterSourceTag: String {
        #if DEV_STUB_SEGMENTER
        return "dev_stub"
        #else
        return "coreml_\(CoreMLInferenceEngine.modelVersion)"
        #endif
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

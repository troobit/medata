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
//     loading the bundled `food_segmenter.mlpackage`; stamps
//     `segmenterSource = "coreml_<modelVersion>"`. Throws on missing model.
//
// The bundled CoFID + AFCD food database (Decision 39) is loaded via
// `GRDBFoodDatabase.bundled()`. Production callers pass a Vision-backed
// `CardDetector` (the App target's `VisionCardDetector`); MedataCore tests
// pass `NullCardDetector()` (internal to the Pipeline module) or a custom
// mock conformance.

public enum PipelineFactoryError: Error, Equatable {
    // Phase 3: the bundled `food_segmenter.mlpackage` is not present in the
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
        let targetSize = SegmenterPreProcessor.defaultTargetSize

        #if DEV_STUB_SEGMENTER
        let engine: any SegmenterInferenceEngine = StubInferenceEngine(palette: palette)
        let modelPath = "/dev/null"
        let source = "dev_stub"
        #else
        guard let modelURL = Bundle.main.url(
            forResource: "food_segmenter", withExtension: "mlpackage"
        ) else {
            throw PipelineFactoryError.segmenterModelMissing
        }
        let engine: any SegmenterInferenceEngine = try CoreMLInferenceEngine(
            modelPath: modelURL.path, targetSize: targetSize
        )
        let modelPath = modelURL.path
        let source = "coreml_\(CoreMLInferenceEngine.modelVersion)"
        #endif

        let segmenter = CoreMLSegmenter(
            modelPath: modelPath, palette: palette, engine: engine, targetSize: targetSize
        )
        return Pipeline(
            cardDetector: cardDetector,
            segmenter: segmenter,
            database: foods,
            store: store,
            supportPlaneFitter: supportPlaneFitter,
            segmenterSource: source
        )
    }
}

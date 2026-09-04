import CardDetection
import CaptureKit
import Foundation

// No-op CardDetector with `internal` visibility so MedataCore tests can reuse
// it. Production builds wire a Vision-backed `CardDetector` from the App
// target via `PipelineFactory.makeForDevice`. App-target tests use their own
// local mock conformances (the established pattern in `EstimationFailureTests`
// and `PipelinePerformanceTests`) and cannot import this type.
struct NullCardDetector: CardDetector {
    func detect(in frame: RawFrame) async -> [PixelCorner]? { nil }
}

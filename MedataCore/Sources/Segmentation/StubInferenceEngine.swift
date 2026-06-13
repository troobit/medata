import Foundation

// Phase 1 development stub per Req §23.2 / Decision 42 / design §3.5.
//
// Returns deterministic FP32 logits that, after the post-processor's softmax,
// place ≥ 0.99 of the per-pixel mass on `dominantClass` (default 0). The stub
// ignores the FP16 input bytes entirely — it does NOT consume the image
// pre-processor's output. Pre-processing still runs upstream in CoreMLSegmenter
// so the call shape matches Phase 3; only the inference itself is replaced.
//
// No Core ML import, no `.mlpackage` file. Selected at compile time by the
// `DEV_STUB_SEGMENTER` flag in `Pipeline.makeForDevice` (Req §23.4).
public struct StubInferenceEngine: SegmenterInferenceEngine, Sendable {
    public let palette: ClassPalette
    public let dominantClass: Int

    public init(palette: ClassPalette, dominantClass: Int = 0) {
        precondition(dominantClass >= 0 && dominantClass < palette.totalClasses,
                     "dominantClass \(dominantClass) is out of bounds for palette of \(palette.totalClasses) classes")
        self.palette = palette
        self.dominantClass = dominantClass
    }

    // High vs low logits chosen so softmax( [high, low, low, ...] ) places
    // ≥ 0.99 on the dominant class for any palette up to ~1000 classes:
    //   p_dom = e^h / (e^h + (C-1) e^l) = 1 / (1 + (C-1) e^{l-h})
    //   With h - l = 20, (C-1) e^{-20} ≈ 23 · 2e-9 ≈ 5e-8 for C = 24 → p_dom ≈ 1 − 5e-8.
    private static let dominantLogit: Float = 10
    private static let recessiveLogit: Float = -10

    public func runInference(
        inputFP16Bytes: Data, targetSize: Int
    ) async throws -> (logits: [Float], classes: Int) {
        let classes = palette.totalClasses
        let pixelCount = targetSize * targetSize
        var logits = [Float](repeating: Self.recessiveLogit, count: pixelCount * classes)
        // Centred-ellipse predicate per Decision 8 of
        // `specs/pipeline-real-device-correctness/`. Semi-axes (α·targetSize/2,
        // α·targetSize/2) with α = 0.618 cover π·α²/4 ≈ 30 % of frame area, so
        // the pre-shutter pass produces a non-trivial, OOM-bounded mask under
        // Phase 1 dev builds. Inside ellipse → dominant logit; outside →
        // background-class logit.
        let alpha: Float = 0.618
        let cx = Float(targetSize) / 2
        let cy = Float(targetSize) / 2
        let rx = alpha * Float(targetSize) / 2
        let ry = alpha * Float(targetSize) / 2
        let background = palette.background
        for y in 0..<targetSize {
            let dy = (Float(y) + 0.5 - cy) / ry
            let dyy = dy * dy
            for x in 0..<targetSize {
                let dx = (Float(x) + 0.5 - cx) / rx
                let inside = (dx * dx + dyy) <= 1
                let pixel = y * targetSize + x
                if inside {
                    logits[pixel * classes + dominantClass] = Self.dominantLogit
                } else {
                    logits[pixel * classes + background] = Self.dominantLogit
                }
            }
        }
        return (logits, classes)
    }
}

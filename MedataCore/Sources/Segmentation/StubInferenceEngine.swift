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
        // Stride writes through the dominant-class slot only — touching ~targetSize²
        // values rather than C·targetSize² — comfortably inside the 50 ms budget.
        for p in 0..<pixelCount {
            logits[p * classes + dominantClass] = Self.dominantLogit
        }
        return (logits, classes)
    }
}

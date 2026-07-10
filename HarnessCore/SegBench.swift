#if HARNESS_ENABLED
import Foundation
import Segmentation

// One sample for the segmenter mIoU bench: predicted argmax vs ground-truth argmax.
public struct SegBenchSample: Sendable {
    public let fixtureID: String
    // Predicted argmax from the segmenter — UInt8 flat [H × W], row-major.
    public let predictedArgmax: [UInt8]
    // Ground-truth annotation — same layout.
    public let groundTruthArgmax: [UInt8]
    public let width: Int
    public let height: Int

    public init(
        fixtureID: String,
        predictedArgmax: [UInt8],
        groundTruthArgmax: [UInt8],
        width: Int,
        height: Int
    ) {
        self.fixtureID = fixtureID
        self.predictedArgmax = predictedArgmax
        self.groundTruthArgmax = groundTruthArgmax
        self.width = width
        self.height = height
    }
}

// Per-class IoU and the mean food-class mIoU (Req 8.9).
public struct SegBenchReport: Sendable {
    // IoU per class index.
    public let perClassIoU: [Int: Float]
    // Mean IoU over food classes only (excludes background, unknown_food, unsupported_liquid).
    public let meanFoodClassIoU: Float
    // Confusion matrix: confusionMatrix[predicted][actual] = pixel count.
    public let confusionMatrix: [[Int]]
    public let classCount: Int
    // CI fails if meanFoodClassIoU < 0.48 (Req 8.9 as amended by
    // segmenter-foundation Decision 5; was 0.60 — one gate with
    // tools/segmenter/validation.py's MEAN_IOU_BAR).
    public var passesBar: Bool { meanFoodClassIoU >= 0.48 }
}

// Computes IoU metrics from a collection of SegBenchSamples.
public enum SegBench {

    // Evaluate all samples and return the bench report.
    public static func evaluate(
        samples: [SegBenchSample],
        palette: ClassPalette
    ) -> SegBenchReport {
        let C = palette.totalClasses
        // Accumulated confusion matrix across all samples.
        var confusion = Array(repeating: Array(repeating: 0, count: C), count: C)

        for s in samples {
            let n = s.width * s.height
            for i in 0..<n {
                let pred = Int(s.predictedArgmax[i])
                let gt   = Int(s.groundTruthArgmax[i])
                guard pred < C, gt < C else { continue }
                confusion[pred][gt] += 1
            }
        }

        // Per-class IoU: TP / (TP + FP + FN).
        var perClassIoU: [Int: Float] = [:]
        for c in 0..<C {
            let tp = confusion[c][c]
            var fp = 0
            var fn = 0
            for k in 0..<C {
                if k != c { fp += confusion[c][k] }  // predicted c, actually k
                if k != c { fn += confusion[k][c] }  // predicted k, actually c
            }
            let denom = tp + fp + fn
            if denom > 0 { perClassIoU[c] = Float(tp) / Float(denom) }
        }

        // Mean over food classes only — excludes background, unknown_food, unsupported_liquid,
        // and classes absent from both prediction and GT (denom=0, standard mIoU convention).
        let excludedIndices: Set<Int> = [
            palette.background,
            palette.unknownFood,
            palette.unsupportedLiquid
        ]
        let presentFoodIoUs = (0..<C)
            .filter { !excludedIndices.contains($0) }
            .compactMap { perClassIoU[$0] }
        let meanIoU: Float = presentFoodIoUs.isEmpty
            ? 0
            : presentFoodIoUs.reduce(0, +) / Float(presentFoodIoUs.count)

        return SegBenchReport(
            perClassIoU: perClassIoU,
            meanFoodClassIoU: meanIoU,
            confusionMatrix: confusion,
            classCount: C
        )
    }
}
#endif

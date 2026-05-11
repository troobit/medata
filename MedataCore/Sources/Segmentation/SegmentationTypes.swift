import Foundation
import PortableContracts

// Swift wrappers over the portable Pb* contracts in PortableContracts/Schemas.
// The `bytes` field of ProbabilityTensor is the portable contract per design §3.5
// (FP16 IEEE-754 LE, HWC row-major). On iOS, an MTLBuffer adaptor may back the same
// bytes for GPU consumption; the adaptor is private to Segmentation/Volume and not
// part of this public type (P1 fix).

public struct ProbabilityTensor: Sendable, Equatable {
    public let bytes: Data
    public let height: Int
    public let width: Int
    public let classes: Int
    public let palette: ClassPalette

    public init(bytes: Data, height: Int, width: Int, classes: Int, palette: ClassPalette) {
        precondition(bytes.count == height * width * classes * 2,
                     "ProbabilityTensor.bytes size must be height*width*classes*2 (FP16 LE HWC)")
        self.bytes = bytes
        self.height = height
        self.width = width
        self.classes = classes
        self.palette = palette
    }
}

public struct ArgmaxMap: Sendable, Equatable {
    public let pixels: Data
    public let height: Int
    public let width: Int

    public init(pixels: Data, height: Int, width: Int) {
        precondition(pixels.count == height * width,
                     "ArgmaxMap.pixels size must be height*width (UInt8 row-major)")
        self.pixels = pixels
        self.height = height
        self.width = width
    }
}

public struct SegmentationResult: Sendable {
    public let probabilities: ProbabilityTensor
    public let argmax: ArgmaxMap
    public let perClassMeanProb: [String: Float]
    public let sigmaSeg: Float

    public init(probabilities: ProbabilityTensor, argmax: ArgmaxMap,
                perClassMeanProb: [String: Float], sigmaSeg: Float) {
        self.probabilities = probabilities
        self.argmax = argmax
        self.perClassMeanProb = perClassMeanProb
        self.sigmaSeg = sigmaSeg
    }
}

public enum SegmentationError: Error, Equatable {
    case noFoodPixels                            // §5 refusal: silhouette test (1 − q[bg]) ≥ τ_sil
    case invalidInputDimensions(String)
    case invalidLogitsShape(String)
    case modelLoadFailed(String)
    case modelInferenceFailed(String)
    case weightsBudgetExceeded(actual: Int, max: Int)
}

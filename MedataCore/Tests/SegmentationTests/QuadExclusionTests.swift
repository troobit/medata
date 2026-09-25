import Foundation
import Testing
@testable import Segmentation

// two-view-trust Req 4.6: the pixels under an accepted ID-1 card are cleared
// to background in both the probability tensor and the label map.
@Suite("QuadExclusion")
struct QuadExclusionTests {
    static let palette = ClassPalette(
        foodClasses: ["solid_a"], liquidClasses: [],
        background: 1, unknownFood: 2, unsupportedLiquid: 3, version: "test")
    static let w = 8, h = 6

    /// Every pixel is solid_a with probability 1.
    static func allFood() -> SegmentationResult {
        let k = palette.totalClasses
        var probs = [Float16](repeating: 0, count: w * h * k)
        for i in 0..<(w * h) { probs[i * k] = 1 }
        let bytes = probs.withUnsafeBytes { Data($0) }
        return SegmentationResult(
            probabilities: ProbabilityTensor(bytes: bytes, height: h, width: w, classes: k, palette: palette),
            argmax: ArgmaxMap(pixels: Data(repeating: 0, count: w * h), height: h, width: w),
            perClassMeanProb: ["solid_a": 1], sigmaSeg: 1)
    }

    static func label(_ r: SegmentationResult, _ x: Int, _ y: Int) -> Int {
        Int(r.argmax.pixels[y * w + x])
    }

    static func background(_ r: SegmentationResult, _ x: Int, _ y: Int) -> Float {
        r.probabilities.bytes.withUnsafeBytes {
            Float($0.bindMemory(to: Float16.self)[(y * w + x) * palette.totalClasses + palette.background])
        }
    }

    @Test func axisAlignedQuadClearsExactlyItsPixels() {
        let quad: [SIMD2<Float>] = [[2, 1], [5, 1], [5, 4], [2, 4]]
        let (r, cleared) = Self.allFood().excluding(quad: quad)
        #expect(cleared == 9)
        for y in 0..<Self.h {
            for x in 0..<Self.w {
                let inside = (2..<5).contains(x) && (1..<4).contains(y)
                #expect(Self.label(r, x, y) == (inside ? 1 : 0), "label at \(x),\(y)")
                #expect(Self.background(r, x, y) == (inside ? 1 : 0), "background at \(x),\(y)")
            }
        }
    }

    @Test func windingAndClippingDoNotMatter() {
        let clockwise: [SIMD2<Float>] = [[2, 1], [5, 1], [5, 4], [2, 4]]
        let anticlockwise: [SIMD2<Float>] = [[2, 1], [2, 4], [5, 4], [5, 1]]
        #expect(Self.allFood().excluding(quad: clockwise).result.argmax
                == Self.allFood().excluding(quad: anticlockwise).result.argmax)
        // Off-image corners are clipped, not an error.
        let (r, cleared) = Self.allFood().excluding(quad: [[-3, -3], [3, -3], [3, 2], [-3, 2]])
        #expect(cleared == 6)
        #expect(Self.label(r, 0, 0) == 1 && Self.label(r, 3, 0) == 0)
    }

    @Test func rotatedQuadClearsItsInterior() {
        // Diamond centred on (4, 3): its centre row spans the widest.
        let diamond: [SIMD2<Float>] = [[4, 0], [8, 3], [4, 6], [0, 3]]
        let (r, cleared) = Self.allFood().excluding(quad: diamond)
        #expect(cleared > 0 && cleared < Self.w * Self.h)
        #expect(Self.label(r, 4, 3) == 1)
        #expect(Self.label(r, 0, 0) == 0 && Self.label(r, 7, 5) == 0)
    }

    @Test func nonQuadIsIgnored() {
        let (r, cleared) = Self.allFood().excluding(quad: [[0, 0], [8, 0], [8, 6]])
        #expect(cleared == 0)
        #expect(r.argmax == Self.allFood().argmax)
    }
}

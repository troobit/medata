import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import Testing
@testable import Pipeline

// two-view-trust Req 4.6 (oblique half): the picked card's 3-D corners go
// through the inter-view transform and the oblique intrinsics, and the quad
// they land on is what gets cleared.
@Suite("PipelineBridges.projectToOblique")
struct CardObliqueProjectionTests {
    // A card 40 × 20 mm centred 400 mm in front of the nadir camera (z = −400).
    static let cardMm: [Vec3] = [Vec3(-20, -11, -400), Vec3(20, -11, -400), Vec3(20, 9, -400), Vec3(-20, 9, -400)]
    static let k = CameraIntrinsics(fx: 100, fy: 100, cx: 32, cy: 24, distortion: [], imageWidth: 64, imageHeight: 48)

    /// Rotation about x by `deg` then translation, column-major.
    static func transform(xDeg: Float, t: Vec3) -> Mat4 {
        let c = cos(xDeg * .pi / 180), s = sin(xDeg * .pi / 180)
        return Mat4(columns: [[1, 0, 0, 0], [0, c, s, 0], [0, -s, c, 0], [t.x, t.y, t.z, 1]])
    }

    @Test func matchesAnIndependentProjection() {
        let m = Self.transform(xDeg: 25, t: Vec3(10, -150, 40))
        let projected = PipelineBridges.projectToOblique(Self.cardMm, transform1To2: m, intrinsics: Self.k)
        #expect(projected.count == 4)
        for (p, q) in zip(Self.cardMm, projected) {
            // p₂ = R·p₁ + t by hand, then §6.0 projection.
            let y2 = m.columns[1][1] * p.y + m.columns[2][1] * p.z + m.columns[3][1]
            let z2 = m.columns[1][2] * p.y + m.columns[2][2] * p.z + m.columns[3][2]
            let x2 = p.x + m.columns[3][0]
            #expect(abs(q.x - (Self.k.fx * x2 / -z2 + Self.k.cx)) < 1e-3)
            #expect(abs(q.y - (Self.k.fy * y2 / -z2 + Self.k.cy)) < 1e-3)
        }
        // A corner behind the oblique camera projects nothing.
        #expect(PipelineBridges.projectToOblique(Self.cardMm, transform1To2: Self.transform(xDeg: 0, t: Vec3(0, 0, 500)), intrinsics: Self.k).isEmpty)
    }

    @Test func clearsExactlyTheProjectedQuad() {
        // Identity transform: the quad is [27, 37] × [21.25, 26.25] px, so the
        // pixel centres inside are x 27…36 and y 21…25: 50 pixels.
        let quad = PipelineBridges.projectToOblique(Self.cardMm, transform1To2: .identity, intrinsics: Self.k)
        let palette = ClassPalette(foodClasses: ["solid_a"], background: 1, unknownFood: 2, unsupportedLiquid: 3, version: "test")
        let w = 64, h = 48, c = palette.totalClasses
        var probs = [Float16](repeating: 0, count: w * h * c)
        for i in 0..<(w * h) { probs[i * c] = 1 }
        let seg = SegmentationResult(
            probabilities: ProbabilityTensor(bytes: probs.withUnsafeBytes { Data($0) }, height: h, width: w, classes: c, palette: palette),
            argmax: ArgmaxMap(pixels: Data(repeating: 0, count: w * h), height: h, width: w),
            perClassMeanProb: [:], sigmaSeg: 1)
        let (cleared, count) = seg.excluding(quad: quad)
        #expect(count == 50)
        func label(_ x: Int, _ y: Int) -> Int { Int(cleared.argmax.pixels[y * w + x]) }
        #expect(label(27, 21) == 1 && label(36, 25) == 1)
        #expect(label(26, 21) == 0 && label(37, 21) == 0 && label(27, 20) == 0 && label(27, 26) == 0)
    }
}

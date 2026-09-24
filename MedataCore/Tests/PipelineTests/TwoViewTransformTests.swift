import CaptureKit
import Foundation
import PortableContracts
import Testing
@testable import Pipeline

// two-view-trust Req 1.2: the transform the carve applies is in millimetres and
// in the §6.0 frame (+y down). ARKit poses are metres in a +y-up camera frame.
// The invariant: for any two poses and any world point, mapping the point into
// each camera by hand (metres, ARKit frame), converting each to §6.0 mm, and
// applying transform1To2 to the first must land on the second.

@Suite("PipelineBridges.transform1To2 units and frame")
struct TwoViewTransformTests {

    // Column-major rigid pose from a rotation (rows given) and a translation.
    static func pose(rows r: [[Float]], t: [Float]) -> Mat4 {
        Mat4(columns: [
            [r[0][0], r[1][0], r[2][0], 0],
            [r[0][1], r[1][1], r[2][1], 0],
            [r[0][2], r[1][2], r[2][2], 0],
            [t[0], t[1], t[2], 1],
        ])
    }
    static func apply(_ m: Mat4, _ p: [Float]) -> [Float] {
        (0..<3).map { r in
            m.columns[0][r] * p[0] + m.columns[1][r] * p[1] + m.columns[2][r] * p[2] + m.columns[3][r]
        }
    }
    static func inverse(_ m: Mat4) -> Mat4 { PipelineBridges.rigidInverse(m) }

    static func frame(_ pose: Mat4) -> RawFrame {
        RawFrame(imageBytes: Data(), pixelFormat: .bgra8, colourSpace: .sRGB, orientation: 1,
                 imageWidth: 4, imageHeight: 3, timestampMonotonicNs: 1,
                 intrinsics: CameraIntrinsics(fx: 1, fy: 1, cx: 2, cy: 1.5, distortion: [],
                                              imageWidth: 4, imageHeight: 3),
                 gravity: Vec3(0, 0, 1), worldFromCamera: pose, depth: nil)
    }

    @Test("a world point maps between the views in §6.0 millimetres")
    func worldPointMapsBetweenViews() {
        // Camera 1: at (0, 0.36, 0) m looking straight down (camera −z → world −y):
        // camera x → world x, camera y → world −z, camera −z → world −y.
        let w1 = Self.pose(rows: [[1, 0, 0], [0, 0, 1], [0, -1, 0]], t: [0, 0.36, 0])
        // Camera 2: moved 0.12 m in world x, tilted 25° about world x, 0.34 m up.
        let c = cos(Float(25) * .pi / 180), s = sin(Float(25) * .pi / 180)
        let tilt: [[Float]] = [[1, 0, 0], [0, c, -s], [0, s, c]]
        let base: [[Float]] = [[1, 0, 0], [0, 0, 1], [0, -1, 0]]
        var r2 = [[Float]](repeating: [0, 0, 0], count: 3)
        for i in 0..<3 { for j in 0..<3 { r2[i][j] = (0..<3).reduce(0) { $0 + tilt[i][$1] * base[$1][j] } } }
        let w2 = Self.pose(rows: r2, t: [0.12, 0.34, 0.02])
        let pWorld: [Float] = [0.03, 0.01, -0.02]   // a point on the table, metres

        let p1 = Self.apply(Self.inverse(w1), pWorld)   // camera-1 frame, metres, ARKit +y up
        let p2 = Self.apply(Self.inverse(w2), pWorld)
        let toImage: ([Float]) -> Vec3 = { Vec3($0[0] * 1000, -$0[1] * 1000, $0[2] * 1000) }
        let p1Img = toImage(p1), p2Img = toImage(p2)

        let t = PipelineBridges.transform1To2(nadir: Self.frame(w1), oblique: Self.frame(w2))
        let mapped = Self.apply(t, [p1Img.x, p1Img.y, p1Img.z])
        #expect(abs(mapped[0] - p2Img.x) < 0.01, "x \(mapped[0]) vs \(p2Img.x)")
        #expect(abs(mapped[1] - p2Img.y) < 0.01, "y \(mapped[1]) vs \(p2Img.y)")
        #expect(abs(mapped[2] - p2Img.z) < 0.01, "z \(mapped[2]) vs \(p2Img.z)")
        // The point sits ~0.34 m in front of camera 2: negative z, hundreds of mm.
        #expect(mapped[2] < -300 && mapped[2] > -400)
    }

    @Test("rigidInverse is an inverse: T · T⁻¹ = I for a general pose")
    func rigidInverseInverts() {
        let c = cos(Float(0.7)), s = sin(Float(0.7))
        let d = cos(Float(0.3)), e = sin(Float(0.3))
        // R = Rz(0.7) · Rx(0.3)
        let rz: [[Float]] = [[c, -s, 0], [s, c, 0], [0, 0, 1]]
        let rx: [[Float]] = [[1, 0, 0], [0, d, -e], [0, e, d]]
        var r = [[Float]](repeating: [0, 0, 0], count: 3)
        for i in 0..<3 { for j in 0..<3 { r[i][j] = (0..<3).reduce(0) { $0 + rz[i][$1] * rx[$1][j] } } }
        let t = Self.pose(rows: r, t: [0.12, -0.34, 0.05])
        let product = PipelineBridges.multiply(t, PipelineBridges.rigidInverse(t))
        for col in 0..<4 { for row in 0..<4 {
            let expected: Float = col == row ? 1 : 0
            #expect(abs(product.columns[col][row] - expected) < 1e-5, "[\(col)][\(row)]")
        } }
    }

    @Test("identity poses give the identity transform")
    func identityIsIdentity() {
        let t = PipelineBridges.transform1To2(nadir: Self.frame(.identity), oblique: Self.frame(.identity))
        #expect(t == Mat4.identity)
    }
}

import XCTest
@testable import PortableContracts

// Vec3 / Mat4 convention tests (design §6.0).
final class Vec3ConventionTests: XCTestCase {
    func testCrossProductIsRightHanded() {
        // x̂ × ŷ = ẑ (right-handed), per design §6.0 (+X right, +Y up, -Z forward).
        let xHat = Vec3(1, 0, 0)
        let yHat = Vec3(0, 1, 0)
        let zHat = Vec3(0, 0, 1)
        XCTAssertEqual(xHat.cross(yHat), zHat)
        XCTAssertEqual(yHat.cross(zHat), xHat)
        XCTAssertEqual(zHat.cross(xHat), yHat)
        // Anti-commutativity sign check.
        XCTAssertEqual(yHat.cross(xHat), Vec3(0, 0, -1))
    }

    func testDotProduct() {
        let a = Vec3(1, 2, 3)
        let b = Vec3(4, -5, 6)
        let expected: Float = 1 * 4 + 2 * -5 + 3 * 6
        XCTAssertEqual(a.dot(b), expected)
    }

    func testNormaliseUnitVector() {
        let n = Vec3(0, -3, 4).normalised()
        XCTAssertEqual(n.length, 1, accuracy: 1e-6)
        XCTAssertEqual(n, Vec3(0, -0.6, 0.8))
    }

    func testNormaliseZeroVectorReturnsZero() {
        let n = Vec3.zero.normalised()
        XCTAssertEqual(n, Vec3.zero, "zero-length vector normalisation should be a no-op")
    }

    func testArithmeticOperators() {
        let a = Vec3(1, 2, 3)
        let b = Vec3(4, 5, 6)
        XCTAssertEqual(a + b, Vec3(5, 7, 9))
        XCTAssertEqual(b - a, Vec3(3, 3, 3))
        XCTAssertEqual(2.0 * a, Vec3(2, 4, 6))
        XCTAssertEqual(a * 2.0, Vec3(2, 4, 6))
        XCTAssertEqual(-a, Vec3(-1, -2, -3))
    }
}

final class Mat4ConventionTests: XCTestCase {
    func testColumnMajorLayout() {
        // Column 0 must be [m00, m10, m20, m30] (column-major).
        let m = Mat4(columns: [
            [1, 2, 3, 4],   // column 0
            [5, 6, 7, 8],   // column 1
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ])
        // Indexing: subscript(col:, row:) — column-first, like simd_float4x4.
        XCTAssertEqual(m[col: 0, row: 0], 1)
        XCTAssertEqual(m[col: 0, row: 3], 4)
        XCTAssertEqual(m[col: 3, row: 0], 13)
        XCTAssertEqual(m[col: 3, row: 3], 16)

        // Flat column-major serialisation: column 0 first, then column 1, etc.
        let flat = m.flatColumnMajor()
        XCTAssertEqual(flat, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16])

        // Round-trip flat → Mat4.
        let m2 = Mat4(flatColumnMajor: flat)
        XCTAssertEqual(m, m2)
    }

    func testIdentity() {
        let id = Mat4.identity
        for i in 0..<4 {
            for j in 0..<4 {
                XCTAssertEqual(id[col: i, row: j], i == j ? 1 : 0)
            }
        }
    }
}

final class ProjectionConventionTests: XCTestCase {
    private func makeIntrinsics() -> PbCameraIntrinsics {
        var k = PbCameraIntrinsics()
        k.fx = 1500
        k.fy = 1500
        k.cx = 2016
        k.cy = 1512
        k.imageWidth = 4032
        k.imageHeight = 3024
        return k
    }

    func testProjectionSignNegZForward() {
        // Point at (0, 0, -100) is on optical axis 100 mm in front of camera (-Z forward).
        // Should project to (cx, cy).
        let k = makeIntrinsics()
        let result = project(k, Vec3(0, 0, -100))
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.u, k.cx, accuracy: 1e-4)
        XCTAssertEqual(result!.v, k.cy, accuracy: 1e-4)
    }

    func testProjectionRefusesPointsBehindCamera() {
        let k = makeIntrinsics()
        XCTAssertNil(project(k, Vec3(0, 0, 100)),  "Z >= 0 is behind camera per §6.0")
        XCTAssertNil(project(k, Vec3(0, 0, 0)), "Z == 0 is degenerate")
    }

    func testProjectionFormula() {
        // For p = (X, Y, Z) with Z < 0:
        //   u = fx * X / (-Z) + cx
        //   v = fy * Y / (-Z) + cy
        let k = makeIntrinsics()
        let p = Vec3(50, -30, -200)
        let r = project(k, p)!
        let expectedU = k.fx * 50 / 200 + k.cx
        let expectedV = k.fy * -30 / 200 + k.cy
        XCTAssertEqual(r.u, expectedU, accuracy: 1e-4)
        XCTAssertEqual(r.v, expectedV, accuracy: 1e-4)
    }
}

final class Vec3Mat4ProtobufBridgeTests: XCTestCase {
    func testVec3PbBridgeRoundTrip() {
        let v = Vec3(1.5, -2.5, 3.5)
        let pb = v.pb
        let back = Vec3(pb: pb)
        XCTAssertEqual(v, back)
    }

    func testMat4PbBridgeRoundTrip() {
        let m = Mat4(columns: [
            [1, 2, 3, 4],
            [5, 6, 7, 8],
            [9, 10, 11, 12],
            [13, 14, 15, 16]
        ])
        let pb = m.pb
        XCTAssertEqual(pb.m.count, 16)
        XCTAssertEqual(pb.m[0], 1)   // column 0, row 0
        XCTAssertEqual(pb.m[4], 5)   // column 1, row 0
        let back = Mat4(pb: pb)
        XCTAssertEqual(m, back)
    }
}

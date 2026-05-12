import CaptureKit
import Foundation
import PortableContracts
import SupportPlane
import XCTest
@testable import Volume

// Tests for VoxelGridSizer per design §6.10.
//
// Geometry: camera at origin, −Z forward. Support plane at z = −400 mm (facing camera).
// Gravity = (0, 0, −1) in camera frame (nadir camera, looking straight down).
//   axisZ = −gravity = (0, 0, 1).
//   axisX = (1,0,0) − axisZ * 0 = (1,0,0) (already ⊥ gravity).
//   axisY = axisZ × axisX = (0,0,1)×(1,0,0) = (0·0−1·0, 1·1−0·0, 0·0−0·1) = (0,1,0).
//
// Note: VoxelGridSizer computes axes internally from gravity; these expected values
// are asserted in the axis tests.

final class VoxelGridSizerTests: XCTestCase {

    // MARK: - fixtures

    let palette = makePalette(numFood: 2)

    // nadir-camera intrinsics: 100×100, fx=fy=500.
    let k = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50,
                             distortion: [], imageWidth: 100, imageHeight: 100)

    // Support plane at z=−400, normal (0,0,1).
    let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -400,
                             residualMm: 0.5, convergedIterations: nil)

    // gravity = (0,0,−1) for a nadir camera.
    let gravity = Vec3(0, 0, -1)

    // Food mask: 20×20 rectangle centred in 100×100 image.
    func centredMask(fw: Int = 20, fh: Int = 20) -> BinaryMask {
        makeBinaryMask(width: 100, height: 100) { y, x in
            (40..<60).contains(x) && (40..<60).contains(y)
        }
    }

    func makeInputs(foodMask: BinaryMask? = nil,
                    edgeMm: Float = VoxelGridSizer.defaultEdgeMm,
                    gravity gv: Vec3? = nil) -> VoxelGridSizer.Inputs {
        VoxelGridSizer.Inputs(
            foodMask: foodMask ?? centredMask(),
            nadirIntrinsics: k,
            supportPlane: plane,
            gravityCamera: gv ?? gravity,
            edgeMm: edgeMm
        )
    }

    // MARK: - T31.1 BBox back-projection through support plane (ray–plane intersection)

    func testBBoxBackProjectionIntersectsPlane() throws {
        let grid = try VoxelGridSizer.size(makeInputs())
        // Food mask covers x ∈ [40,60), y ∈ [40,60).
        // For gravity=(0,0,−1) the origin (centroid projected onto plane) should have z≈−400.
        XCTAssertEqual(grid.originCamera1.z, -400, accuracy: 5,
            "Grid origin z should be near the support plane z=−400")
    }

    // MARK: - T31.2 Multiples-of-8 rounding for Metal threadgroups

    func testDimensionsAreMultiplesOf8() throws {
        let grid = try VoxelGridSizer.size(makeInputs())
        XCTAssertEqual(grid.dimsX % 8, 0, "dimsX must be a multiple of 8")
        XCTAssertEqual(grid.dimsY % 8, 0, "dimsY must be a multiple of 8")
        XCTAssertEqual(grid.dimsZ % 8, 0, "dimsZ must be a multiple of 8")
    }

    // MARK: - T31.3 Gravity-aligned axes

    func testGravityAlignedAxes() throws {
        let grid = try VoxelGridSizer.size(makeInputs())
        // axisZ = −gravity = (0,0,1).
        let expectedAxisZ = (-gravity).normalised()
        XCTAssertEqual(grid.axisZ.x, expectedAxisZ.x, accuracy: 1e-5)
        XCTAssertEqual(grid.axisZ.y, expectedAxisZ.y, accuracy: 1e-5)
        XCTAssertEqual(grid.axisZ.z, expectedAxisZ.z, accuracy: 1e-5)

        // axisX must be ⊥ to axisZ (dot product ≈ 0).
        let dotXZ = grid.axisX.dot(grid.axisZ)
        XCTAssertEqual(dotXZ, 0, accuracy: 1e-5, "axisX must be ⊥ axisZ")

        // axisY = axisZ × axisX (right-hand rule) — all three must be orthonormal.
        let crossZX = grid.axisZ.cross(grid.axisX)
        XCTAssertEqual(crossZX.x, grid.axisY.x, accuracy: 1e-5)
        XCTAssertEqual(crossZX.y, grid.axisY.y, accuracy: 1e-5)
        XCTAssertEqual(crossZX.z, grid.axisY.z, accuracy: 1e-5)

        // Each axis must be unit length.
        XCTAssertEqual(grid.axisX.length, 1, accuracy: 1e-5)
        XCTAssertEqual(grid.axisY.length, 1, accuracy: 1e-5)
        XCTAssertEqual(grid.axisZ.length, 1, accuracy: 1e-5)
    }

    // MARK: - T31.4 Horizontal cap at 360 mm

    func testHorizontalCapAt360mm() throws {
        // Extremely large food mask spanning entire image forces a very wide bbox.
        // Even for a 100×100 image at 400 mm the projected extent is bounded to 360 mm.
        let wideFood = makeBinaryMask(width: 100, height: 100) { _, _ in true }
        let grid = try VoxelGridSizer.size(makeInputs(foodMask: wideFood))
        let extent = Float(grid.dimsX) * VoxelGridSizer.defaultEdgeMm
        XCTAssertLessThanOrEqual(extent,
            VoxelGridSizer.horizontalCapMm + Float(VoxelGridSizer.threadgroupAlignment) * VoxelGridSizer.defaultEdgeMm,
            "Horizontal extent must not exceed the 360 mm cap (plus one threadgroup rounding)")
    }

    // MARK: - T31.5 Vertical extent is 120 mm

    func testVerticalExtentIs120mm() throws {
        let grid = try VoxelGridSizer.size(makeInputs())
        // dimsZ × edgeMm ≥ 120 mm (rounded up to multiple of 8, may be slightly above).
        let verticalExtent = Float(grid.dimsZ) * VoxelGridSizer.defaultEdgeMm
        XCTAssertGreaterThanOrEqual(verticalExtent, VoxelGridSizer.verticalExtentMm,
            "Vertical extent must be ≥ 120 mm")
        // Must not exceed 120 + 8*edgeMm (one threadgroup above the cap).
        XCTAssertLessThanOrEqual(verticalExtent,
            VoxelGridSizer.verticalExtentMm + Float(VoxelGridSizer.threadgroupAlignment) * VoxelGridSizer.defaultEdgeMm)
    }

    // MARK: - T31.6 Origin = food-silhouette centroid projected onto support plane

    func testOriginIsFoodCentroidOnSupportPlane() throws {
        // A food mask with centroid shifted to (30, 40) in image coordinates.
        let offCentredMask = makeBinaryMask(width: 100, height: 100) { y, x in
            (28..<32).contains(x) && (38..<42).contains(y)
        }
        let grid = try VoxelGridSizer.size(makeInputs(foodMask: offCentredMask))
        // Back-project centroid pixel (30, 40) to the support plane z=−400.
        // dir = ((30−50)/500, (40−50)/500, −1).normalised() ≈ (−0.04, −0.02, −1) / ~1.001
        let dirX = (30 - k.cx) / k.fx
        let dirY = (40 - k.cy) / k.fy
        let dirZ: Float = -1
        let len = (dirX * dirX + dirY * dirY + dirZ * dirZ).squareRoot()
        let dNorm = Vec3(dirX / len, dirY / len, dirZ / len)
        let alpha = plane.distanceMm / plane.normal.dot(dNorm)
        let expectedOrigin = dNorm * alpha
        XCTAssertEqual(grid.originCamera1.x, expectedOrigin.x, accuracy: 2,
            "Origin x should match centroid back-projection")
        XCTAssertEqual(grid.originCamera1.y, expectedOrigin.y, accuracy: 2,
            "Origin y should match centroid back-projection")
        XCTAssertEqual(grid.originCamera1.z, expectedOrigin.z, accuracy: 2,
            "Origin z should match centroid back-projection")
    }

    // MARK: - T31.7 Summary proto is populated

    func testSummaryIsPopulated() throws {
        let grid = try VoxelGridSizer.size(makeInputs())
        let summary = VoxelGridSizer.summary(grid, perClassVoxelCount: ["food_0": 42])
        XCTAssertEqual(summary.edgeMm, grid.edgeMm, accuracy: 1e-5)
        XCTAssertEqual(Int(summary.dimsX), grid.dimsX)
        XCTAssertEqual(Int(summary.dimsY), grid.dimsY)
        XCTAssertEqual(Int(summary.dimsZ), grid.dimsZ)
        XCTAssertEqual(summary.perClassVoxelCount["food_0"], 42)
    }

    // MARK: - T31.8 Invalid edge rejects immediately

    func testInvalidEdgeThrows() {
        let inputs = makeInputs(edgeMm: -1)
        XCTAssertThrowsError(try VoxelGridSizer.size(inputs)) { err in
            if case .invalidGrid = err as? VolumeError { return }
            XCTFail("Expected invalidGrid, got \(err)")
        }
    }
}

import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane
import Testing
@testable import Volume

// two-view-trust, night audit: `RawFrame.gravity` is world-up in the camera
// frame, and the plane normal is aligned to it (n̂ · gravity > 0). The grid's
// vertical axis must be that vector, so every voxel sits ABOVE the plane on a
// real nadir capture (gravity ≈ (0, 0, 1), plane z = −d).

@Suite("VoxelGridSizer vertical axis")
struct VoxelGridSizerAxisTests {
    @Test("with world-up (0,0,1) every voxel centre is above the support plane")
    func gridIsAboveThePlane() throws {
        let k = CameraIntrinsics(fx: 500, fy: 500, cx: 50, cy: 50, distortion: [],
                                 imageWidth: 100, imageHeight: 100)
        let plane = SupportPlane(normal: Vec3(0, 0, 1), distanceMm: -400,
                                 residualMm: 0.5, convergedIterations: nil)
        let mask = makeBinaryMask(width: 100, height: 100) { y, x in abs(x - 50) < 10 && abs(y - 50) < 10 }
        let grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
            foodMask: mask, nadirIntrinsics: k, supportPlane: plane, gravityCamera: Vec3(0, 0, 1)))
        #expect(grid.axisZ.z > 0.99)
        var above = 0, total = 0
        for iz in 0..<grid.dimsZ { for iy in 0..<grid.dimsY { for ix in 0..<grid.dimsX {
            let p = grid.voxelCentre(ix: ix, iy: iy, iz: iz)
            total += 1
            if signedDistanceToPlane(p, plane: plane) > 0 { above += 1 }
        } } }
        #expect(above == total, "\(above) of \(total) voxels above the plane")
    }
}

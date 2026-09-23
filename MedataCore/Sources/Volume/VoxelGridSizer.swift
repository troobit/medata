import CaptureKit
import Foundation
import PortableContracts
import SupportPlane

// Voxel-grid sizing per design §6.10 / Req 9.2, 9.3. Pure function shared by both the
// two-view and single-view paths. Returns a VoxelGrid plus the persistence-ready
// PbVoxelGridSummary (without per-class voxel counts — those are filled by the volume
// kernels).

public enum VoxelGridSizer {
    public static let defaultEdgeMm: Float = 3
    public static let horizontalCapMm: Float = 360
    public static let verticalExtentMm: Float = 120
    public static let horizontalMarginMm: Float = 30
    public static let threadgroupAlignment: Int = 8

    public struct Inputs: Sendable {
        public let foodMask: BinaryMask
        public let nadirIntrinsics: CameraIntrinsics
        public let supportPlane: SupportPlane
        public let gravityCamera: Vec3            // unit vector, camera-1 frame
        public let edgeMm: Float

        public init(foodMask: BinaryMask, nadirIntrinsics: CameraIntrinsics,
                    supportPlane: SupportPlane, gravityCamera: Vec3,
                    edgeMm: Float = VoxelGridSizer.defaultEdgeMm) {
            self.foodMask = foodMask
            self.nadirIntrinsics = nadirIntrinsics
            self.supportPlane = supportPlane
            self.gravityCamera = gravityCamera
            self.edgeMm = edgeMm
        }
    }

    public static func size(_ inputs: Inputs) throws -> VoxelGrid {
        guard inputs.edgeMm > 0 else {
            throw VolumeError.invalidGrid("edgeMm must be positive (got \(inputs.edgeMm))")
        }
        guard let bbox = foodMaskBBox(inputs.foodMask) else {
            throw VolumeError.invalidGrid("food mask is empty — no bbox")
        }
        let k = inputs.nadirIntrinsics
        let plane = inputs.supportPlane

        // Step 1: back-project the four bbox corner pixels to π_sup (camera-1 frame, mm).
        let corners: [(Float, Float)] = [
            (Float(bbox.minX), Float(bbox.minY)),
            (Float(bbox.maxX), Float(bbox.minY)),
            (Float(bbox.maxX), Float(bbox.maxY)),
            (Float(bbox.minX), Float(bbox.maxY))
        ]
        var cornerPoints: [Vec3] = []
        cornerPoints.reserveCapacity(4)
        for (u, v) in corners {
            guard let p = backprojectPixelToPlane(u: u, v: v, k: k, plane: plane) else {
                throw VolumeError.invalidGrid("bbox corner does not intersect support plane")
            }
            cornerPoints.append(p)
        }

        // Build gravity-aligned axes per §6.10 step 4.
        let gravity = inputs.gravityCamera.normalised()
        let axisZ = (-gravity).normalised()                            // points "up"
        // axis_x: project camera +x onto plane (subtract its component along axis_z),
        // then normalise. The camera-1 +X axis in camera frame is (1, 0, 0).
        let cameraXRaw = Vec3(1, 0, 0)
        var axisX = cameraXRaw - axisZ * cameraXRaw.dot(axisZ)
        if axisX.lengthSquared < 1e-6 {
            // Camera +X happens to be parallel to gravity; fall back to camera +Y.
            let cameraY = Vec3(0, 1, 0)
            axisX = cameraY - axisZ * cameraY.dot(axisZ)
        }
        axisX = axisX.normalised()
        let axisY = axisZ.cross(axisX).normalised()

        // Step 2: horizontal extent within π_sup = max pairwise distance of corner
        // projections, projected into the plane-tangent basis (axisX, axisY).
        var bboxHorizontalMm: Float = 0
        for i in 0..<corners.count {
            for j in (i + 1)..<corners.count {
                let d = projectedDistanceInPlane(cornerPoints[i], cornerPoints[j],
                                                 axisX: axisX, axisY: axisY)
                if d > bboxHorizontalMm { bboxHorizontalMm = d }
            }
        }

        // Step 3: extents and dims, rounded up to multiples of threadgroupAlignment.
        let extentXyMm = min(bboxHorizontalMm + horizontalMarginMm, horizontalCapMm)
        let extentZMm = verticalExtentMm
        let dimsXY = roundUpToMultiple(ceilDiv(extentXyMm, inputs.edgeMm), threadgroupAlignment)
        let dimsZ = roundUpToMultiple(ceilDiv(extentZMm, inputs.edgeMm), threadgroupAlignment)

        // Step 4: origin = centroid pixel of food mask projected onto π_sup.
        let centroidPixel = foodMaskCentroid(inputs.foodMask, fallback: bbox.centre)
        guard let origin = backprojectPixelToPlane(
            u: centroidPixel.x, v: centroidPixel.y, k: k, plane: plane
        ) else {
            throw VolumeError.invalidGrid("centroid does not intersect support plane")
        }

        return VoxelGrid(
            edgeMm: inputs.edgeMm,
            dimsX: dimsXY, dimsY: dimsXY, dimsZ: dimsZ,
            originCamera1: origin,
            axisX: axisX, axisY: axisY, axisZ: axisZ
        )
    }

    public static func summary(
        _ grid: VoxelGrid,
        perClassVoxelCount: [String: Int] = [:]
    ) -> PbVoxelGridSummary {
        var s = PbVoxelGridSummary()
        s.edgeMm = grid.edgeMm
        s.dimsX = Int32(grid.dimsX)
        s.dimsY = Int32(grid.dimsY)
        s.dimsZ = Int32(grid.dimsZ)
        s.originCamera1 = grid.originCamera1.pb
        var counts: [String: Int32] = [:]
        for (k, v) in perClassVoxelCount { counts[k] = Int32(v) }
        s.perClassVoxelCount = counts
        return s
    }

    // MARK: - helpers

    static func backprojectPixelToPlane(
        u: Float, v: Float, k: CameraIntrinsics, plane: SupportPlane
    ) -> Vec3? {
        // §6.10 ray-plane intersection. Ray direction in camera-1 frame uses §6.0
        // projection convention (−Z forward): d = ((u−c_x)/f_x, (v−c_y)/f_y, −1).
        let dir = Vec3(
            (u - k.cx) / k.fx,
            (v - k.cy) / k.fy,
            -1
        ).normalised()
        let denom = plane.normal.dot(dir)
        if abs(denom) < 1e-9 { return nil }
        let alpha = plane.distanceMm / denom
        if alpha <= 0 { return nil }
        return dir * alpha
    }

    static func projectedDistanceInPlane(
        _ a: Vec3, _ b: Vec3, axisX: Vec3, axisY: Vec3
    ) -> Float {
        let d = a - b
        let dx = d.dot(axisX)
        let dy = d.dot(axisY)
        return (dx * dx + dy * dy).squareRoot()
    }

    static func foodMaskCentroid(_ mask: BinaryMask, fallback: (x: Float, y: Float))
        -> (x: Float, y: Float) {
        var sumX: Double = 0
        var sumY: Double = 0
        var count = 0
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.isFood(x: x, y: y) {
                sumX += Double(x)
                sumY += Double(y)
                count += 1
            }
        }
        if count == 0 { return fallback }
        return (Float(sumX / Double(count)), Float(sumY / Double(count)))
    }

    struct BBox: Sendable {
        let minX: Int
        let maxX: Int
        let minY: Int
        let maxY: Int
        var centre: (x: Float, y: Float) {
            (Float(minX + maxX) / 2, Float(minY + maxY) / 2)
        }
    }

    static func foodMaskBBox(_ mask: BinaryMask) -> BBox? {
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.isFood(x: x, y: y) {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        if maxX < 0 { return nil }
        return BBox(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    @inline(__always)
    static func ceilDiv(_ value: Float, _ denom: Float) -> Int {
        Int((value / denom).rounded(.up))
    }

    @inline(__always)
    static func roundUpToMultiple(_ value: Int, _ multiple: Int) -> Int {
        precondition(multiple > 0)
        let r = value % multiple
        return r == 0 ? value : value + (multiple - r)
    }
}

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

    // ── Measured vertical extent (two-view-trust, 2026-09-25) ────────────────
    // Two silhouette cones at the tilts the aim guide allows never close over a
    // low food: a voxel at height h only leaves the oblique silhouette once
    // h · tan(theta) exceeds the object's extent along the tilt direction, which
    // for the 120 x 70 mm roll at 22 degrees is ~340 mm — far above any grid.
    // `verticalExtentMm` is therefore not a safety cap on the carve, it IS the
    // answer: the roll's 927 cm3 dropped to 756, 587 and 379 cm3 as the cap was
    // walked down 120 -> 86 -> 62 -> 40 mm. When the nadir frame carries depth
    // the food's height is measurable, so the grid stops where the food does.
    /// Percentile of the per-pixel food heights taken as the food's top.
    /// 0.98, not the raw maximum: a food region carries 1e4–1e5 usable depth
    /// samples, so the top 2 % is hundreds of pixels — far more than the handful
    /// a specular highlight, a mask fringe over a further surface, or one bad
    /// LiDAR return can produce — while on a domed food the top 2 % of the area
    /// still sits within a couple of millimetres of the apex.
    public static let heightPercentile: Float = 0.98
    /// Headroom above the measured height, mm. Only quantisation and the
    /// support plane's own fit residual — NOT an allowance for the percentile
    /// undershooting the apex. Measured on the three 2026-09-25 two-view
    /// bundles the percentile runs ABOVE the food: 47.3, 50.4 and 36.0 mm on
    /// rolls of ~40 mm, because the height is taken over the same smoothed
    /// depth the plane was fitted to. A larger margin would be pure headroom,
    /// and headroom is what the carve turns into volume.
    public static let heightMarginMm: Float = 5
    /// Floor for a measured extent, mm. A flat food must still get a grid
    /// taller than the plane's uncertainty.
    public static let minVerticalExtentMm: Float = 30
    /// Fewest usable depth samples a measured height may rest on; below this
    /// the constant extent is kept.
    public static let minHeightSampleCount: Int = 64

    public struct Inputs: Sendable {
        public let foodMask: BinaryMask
        public let nadirIntrinsics: CameraIntrinsics
        public let supportPlane: SupportPlane
        public let gravityCamera: Vec3            // unit vector, camera-1 frame
        public let edgeMm: Float
        /// Food height above the support plane measured from the nadir depth
        /// (`measuredFoodHeightMm`), mm. nil — no depth, or too few usable
        /// samples — keeps the `verticalExtentMm` constant and its rounding
        /// exactly as they were, so the no-LiDAR path is unchanged.
        public let measuredFoodHeightMm: Float?

        public init(foodMask: BinaryMask, nadirIntrinsics: CameraIntrinsics,
                    supportPlane: SupportPlane, gravityCamera: Vec3,
                    edgeMm: Float = VoxelGridSizer.defaultEdgeMm,
                    measuredFoodHeightMm: Float? = nil) {
            self.foodMask = foodMask
            self.nadirIntrinsics = nadirIntrinsics
            self.supportPlane = supportPlane
            self.gravityCamera = gravityCamera
            self.edgeMm = edgeMm
            self.measuredFoodHeightMm = measuredFoodHeightMm
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

        // Build gravity-aligned axes per §6.10 step 4. `gravityCamera` carries
        // WORLD-UP in the §6.0 camera frame — that is what `RawFrame.gravity`
        // holds since bugfix capture-no-flat-surface-gravity-frame
        // (`CameraGravity.worldUpInCameraFrame`), and it is the vector the
        // plane fitter's normal is aligned to (n̂ · gravity > 0). The grid's
        // vertical axis is that vector itself. The earlier `-gravity` read the
        // field as pointing down, which on every real capture put the whole
        // grid below the support plane, where the carve discards it
        // (two-view-trust, night audit 2026-09-24).
        let axisZ = inputs.gravityCamera.normalised()                  // points "up"
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
        let dimsXY = roundUpToMultiple(ceilDiv(extentXyMm, inputs.edgeMm), threadgroupAlignment)
        // Vertical dims. With a measured height the extent is that height plus
        // the margin, floored and capped, and rounded up to a whole voxel only:
        // the threadgroup alignment quantises the vertical extent in steps of
        // 8 * edge (24 mm at the default edge), which on a 40 mm food is most of
        // the measurement. The kernel guards `gid.z >= dims_z` (voxel_carve.metal),
        // so a dims_z that is not a multiple of 8 costs a partly idle tail
        // threadgroup and nothing else. Without a measured height the old
        // constant AND the old rounding are kept, byte for byte.
        let dimsZ: Int
        if let measured = inputs.measuredFoodHeightMm {
            let extentZMm = min(max(measured + heightMarginMm, minVerticalExtentMm), verticalExtentMm)
            dimsZ = max(1, ceilDiv(extentZMm, inputs.edgeMm))
        } else {
            dimsZ = roundUpToMultiple(ceilDiv(verticalExtentMm, inputs.edgeMm), threadgroupAlignment)
        }

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

    /// Food height above the support plane, mm, measured from the nadir depth
    /// over the nadir food mask: the `heightPercentile` of the per-pixel
    /// heights. Returns nil when fewer than `minHeightSampleCount` pixels carry
    /// usable depth, so a sparse or absent depth map falls back to the constant.
    ///
    /// The per-pixel arithmetic is `heightAboveSupportPlaneMm`, the same
    /// function the single-view height field and the depth-grown region use, so
    /// the height that sizes the carve grid is the height the single-view path
    /// would integrate.
    public static func measuredFoodHeightMm(
        foodMask: BinaryMask,
        depth: DepthMap,
        intrinsics: CameraIntrinsics,
        supportPlane: SupportPlane
    ) -> Float? {
        let w = foodMask.width
        let h = foodMask.height
        var heights: [Float] = []
        heights.reserveCapacity(4096)
        for y in 0..<h {
            for x in 0..<w where foodMask.isFood(x: x, y: y) {
                let conf = sampleConfidenceUInt8(
                    depth: depth, colourX: x, colourY: y,
                    colourWidth: w, colourHeight: h)
                if Float(conf) / 255 < HeightFieldEstimator.tauConfidence { continue }
                guard let zt = sampleDepthBilinearMm(
                    depth: depth, colourX: Float(x), colourY: Float(y),
                    colourWidth: w, colourHeight: h), zt > 0 else { continue }
                guard let height = heightAboveSupportPlaneMm(
                    colourX: Float(x), colourY: Float(y), depthMm: zt,
                    intrinsics: intrinsics, plane: supportPlane) else { continue }
                heights.append(height)
            }
        }
        guard heights.count >= minHeightSampleCount else { return nil }
        heights.sort()
        let idx = Int((Float(heights.count - 1) * heightPercentile).rounded())
        return heights[min(heights.count - 1, max(0, idx))]
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

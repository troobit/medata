import CaptureKit
import Foundation
import PortableContracts
import Segmentation
import SupportPlane

// Shared types for the Volume module. Per design §6.0, all metric coordinates are in
// millimetres; volumes are converted from mm³ to cm³ at dispatcher boundaries (M5).

public struct VoxelGrid: Sendable, Equatable {
    public let edgeMm: Float
    public let dimsX: Int
    public let dimsY: Int
    public let dimsZ: Int
    public let originCamera1: Vec3     // mm, food-silhouette centroid projected onto π_sup
    public let axisX: Vec3             // unit, perpendicular to gravity
    public let axisY: Vec3             // unit, perpendicular to gravity
    public let axisZ: Vec3             // unit, opposite to gravity (axis_z = −gravity)

    public init(edgeMm: Float, dimsX: Int, dimsY: Int, dimsZ: Int,
                originCamera1: Vec3, axisX: Vec3, axisY: Vec3, axisZ: Vec3) {
        self.edgeMm = edgeMm
        self.dimsX = dimsX
        self.dimsY = dimsY
        self.dimsZ = dimsZ
        self.originCamera1 = originCamera1
        self.axisX = axisX
        self.axisY = axisY
        self.axisZ = axisZ
    }

    public var voxelCount: Int { dimsX * dimsY * dimsZ }

    // Voxel centre in camera-1 mm. (ix, iy, iz) are 0-based.
    public func voxelCentre(ix: Int, iy: Int, iz: Int) -> Vec3 {
        let halfX = Float(dimsX) * edgeMm / 2
        let halfY = Float(dimsY) * edgeMm / 2
        let dx = (Float(ix) + 0.5) * edgeMm - halfX
        let dy = (Float(iy) + 0.5) * edgeMm - halfY
        let dz = (Float(iz) + 0.5) * edgeMm
        return originCamera1 + axisX * dx + axisY * dy + axisZ * dz
    }
}

// Swift-ergonomic β_c lookup. Wraps PbBetaCorrectionTable.
public struct BetaCorrection: Sendable, Equatable {
    public let entries: [String: Float]
    public let defaultBeta: Float

    public init(entries: [String: Float] = [:], defaultBeta: Float = 1.0) {
        self.entries = entries
        self.defaultBeta = defaultBeta
    }

    public func beta(for className: String) -> Float {
        entries[className] ?? defaultBeta
    }
}

public extension BetaCorrection {
    init(pb: PbBetaCorrectionTable, defaultBeta: Float = 1.0) {
        var out: [String: Float] = [:]
        for (name, entry) in pb.entries {
            out[name] = entry.beta
        }
        self.init(entries: out, defaultBeta: defaultBeta)
    }
}

public enum VolumeError: Error, Equatable {
    case noFoodVolumeRecovered
    case lidarCoverageTooLow(classes: [String])
    case invalidGrid(String)
    case mismatchedViewDimensions(String)
}

// Stage measurements accumulated by the volume estimators (snaq-parity
// Req 3.1/3.2). Populated on every run — success or refusal — so a "no volume"
// refusal carries the causal detail (what was recovered, what was discarded,
// what was silently skipped) instead of dying with a throw.
public struct VolumeStats: Sendable, Equatable {
    // Per-class recovered volumes before β-correction and before any
    // threshold (voxel-count or minimum-volume) is applied.
    public let perClassVolumesPreBetaCm3: [String: Float]
    // Same classes after β-correction, still before thresholding.
    public let perClassVolumesPostBetaCm3: [String: Float]
    // β factor applied per class present in the pre-threshold maps.
    public let betaApplied: [String: Float]
    // Classes dropped by a threshold (carve: < minVoxelCountForClass voxels or
    // a fallback extrusion under 1 cm³; height-field: post-β volume under
    // minVolumeCm3). Sorted for deterministic output.
    public let thresholdDiscardedClasses: [String]
    // Carve: voxels that passed the silhouette test in both views but resolved
    // to no owning class (empty candidate list or all-zero scores).
    public let degenerateVoxelSkipCount: Int
    // Rays skipped on degenerate geometry: support plane parallel to the ray,
    // or the plane intersection behind the camera (single-view extrusion).
    public let degenerateRaySkipCount: Int
    // Height-field only: per-class LiDAR coverage fraction (empty for carve).
    public let lidarCoverageFraction: [String: Float]

    public init(perClassVolumesPreBetaCm3: [String: Float] = [:],
                perClassVolumesPostBetaCm3: [String: Float] = [:],
                betaApplied: [String: Float] = [:],
                thresholdDiscardedClasses: [String] = [],
                degenerateVoxelSkipCount: Int = 0,
                degenerateRaySkipCount: Int = 0,
                lidarCoverageFraction: [String: Float] = [:]) {
        self.perClassVolumesPreBetaCm3 = perClassVolumesPreBetaCm3
        self.perClassVolumesPostBetaCm3 = perClassVolumesPostBetaCm3
        self.betaApplied = betaApplied
        self.thresholdDiscardedClasses = thresholdDiscardedClasses
        self.degenerateVoxelSkipCount = degenerateVoxelSkipCount
        self.degenerateRaySkipCount = degenerateRaySkipCount
        self.lidarCoverageFraction = lidarCoverageFraction
    }
}

// Non-throwing estimator result (snaq-parity design lane A / Decision 14):
// `estimate` is non-nil exactly when `refusal` is nil; `stats` is populated on
// both exits. The Pipeline stamps `stats` into its diagnostics accumulator
// first, then maps a non-nil `refusal` to the `EstimationFailure` throw.
public struct VolumeOutcome<Estimate: Sendable>: Sendable {
    public let estimate: Estimate?
    public let stats: VolumeStats
    public let refusal: VolumeError?

    public init(estimate: Estimate?, stats: VolumeStats, refusal: VolumeError?) {
        self.estimate = estimate
        self.stats = stats
        self.refusal = refusal
    }
}

// Helper: read FP16 probability at (y, x, c) from the portable HWC byte tensor.
@inline(__always)
internal func readProbabilityFP16(
    _ tensor: ProbabilityTensor, y: Int, x: Int, c: Int
) -> Float {
    let off = ((y * tensor.width) + x) * tensor.classes + c
    return tensor.bytes.withUnsafeBytes { raw -> Float in
        let buf = raw.bindMemory(to: Float16.self).baseAddress!
        return Float(buf[off])
    }
}

// Read confidence byte (UInt8 0..255) for a colour-grid pixel by nearest-neighbour
// sampling the depth-grid confidence buffer. Mirrors LiDARPlaneFitter helpers.
@inline(__always)
internal func sampleConfidenceUInt8(
    depth: DepthMap, colourX: Int, colourY: Int,
    colourWidth: Int, colourHeight: Int
) -> UInt8 {
    let dx = min(depth.width - 1,
                 max(0, Int((Float(colourX) + 0.5) * Float(depth.width) / Float(colourWidth))))
    let dy = min(depth.height - 1,
                 max(0, Int((Float(colourY) + 0.5) * Float(depth.height) / Float(colourHeight))))
    return depth.confidenceBytes[dy * depth.width + dx]
}

// Bilinear depth sample (mm). Returns nil when out of range.
@inline(__always)
internal func sampleDepthBilinearMm(
    depth: DepthMap, colourX: Float, colourY: Float,
    colourWidth: Int, colourHeight: Int
) -> Float? {
    let fx = (colourX + 0.5) * Float(depth.width) / Float(colourWidth) - 0.5
    let fy = (colourY + 0.5) * Float(depth.height) / Float(colourHeight) - 0.5
    if fx < 0 || fy < 0 { return nil }
    let x0 = Int(fx.rounded(.down))
    let y0 = Int(fy.rounded(.down))
    let x1 = min(depth.width - 1, x0 + 1)
    let y1 = min(depth.height - 1, y0 + 1)
    if x0 >= depth.width || y0 >= depth.height { return nil }
    let ax = fx - Float(x0)
    let ay = fy - Float(y0)
    let z00 = readDepthMm(depth, x: x0, y: y0)
    let z10 = readDepthMm(depth, x: x1, y: y0)
    let z01 = readDepthMm(depth, x: x0, y: y1)
    let z11 = readDepthMm(depth, x: x1, y: y1)
    let zx0 = (1 - ax) * z00 + ax * z10
    let zx1 = (1 - ax) * z01 + ax * z11
    return (1 - ay) * zx0 + ay * zx1
}

@inline(__always)
internal func readDepthMm(_ depth: DepthMap, x: Int, y: Int) -> Float {
    let offset = (y * depth.width + x) * 4
    return depth.depthBytesMm.withUnsafeBytes { raw in
        raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
    }
}

// Project a camera-1 point to image coordinates per §6.0 (−Z forward).
// Returns nil if the point is behind the camera (Z ≥ 0).
@inline(__always)
internal func projectCamera1(_ k: CameraIntrinsics, _ p: Vec3) -> (Float, Float)? {
    if p.z >= 0 { return nil }
    let u = k.fx * p.x / (-p.z) + k.cx
    let v = k.fy * p.y / (-p.z) + k.cy
    return (u, v)
}

// Apply a column-major 4×4 transform to a 3-vector (treats v as [x, y, z, 1]).
@inline(__always)
internal func applyMat4(_ m: Mat4, _ p: Vec3) -> Vec3 {
    let x = m[col: 0, row: 0] * p.x + m[col: 1, row: 0] * p.y + m[col: 2, row: 0] * p.z + m[col: 3, row: 0]
    let y = m[col: 0, row: 1] * p.x + m[col: 1, row: 1] * p.y + m[col: 2, row: 1] * p.z + m[col: 3, row: 1]
    let z = m[col: 0, row: 2] * p.x + m[col: 1, row: 2] * p.y + m[col: 2, row: 2] * p.z + m[col: 3, row: 2]
    return Vec3(x, y, z)
}

// Signed distance from a camera-1 point to π_sup (mm). The plane stored in SupportPlane
// is (n̂, d) so that n̂ · p = d on the plane and n̂ · p > d "above" the plane (where
// the food lives, since n̂ is oriented so n̂ · gravity > 0 per §6.2). The voxel-discard
// rule in §6.6 reads "dot(p − π.point, π.normal) < 0 → below". Equivalent to
// (n̂ · p − d) < 0.
@inline(__always)
internal func signedDistanceToPlane(_ p: Vec3, plane: SupportPlane) -> Float {
    plane.normal.dot(p) - plane.distanceMm
}

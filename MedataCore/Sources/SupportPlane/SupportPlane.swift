import CaptureKit
import Foundation
import PortableContracts

// Swift-ergonomic SupportPlane type per design §3.3. Mirrors PbSupportPlane wire format
// (SupportPlane.proto). The Swift type uses mm everywhere (per §6.0 unit convention).
public struct SupportPlane: Sendable, Equatable {
    public let normal: Vec3            // unit, points "up" so n̂ · gravity > 0 per §6.2
    public let distanceMm: Float       // signed mm from camera origin along normal
    public let residualMm: Float       // RANSAC inlier σ (or LSQ residual for card path)
    public let convergedIterations: Int?  // nil for LiDAR fit; iter count for card-only

    public init(normal: Vec3, distanceMm: Float, residualMm: Float, convergedIterations: Int?) {
        self.normal = normal
        self.distanceMm = distanceMm
        self.residualMm = residualMm
        self.convergedIterations = convergedIterations
    }
}

public enum SupportPlaneError: Error, Equatable {
    case lidarFitResidualTooHigh
    case lidarFitDegenerate
    case noLowerSilhouetteEdges
    case iterationDiverged
    case noLidarPoints              // <3 valid samples after confidence filter
}

// Binary food-region mask resampled to the colour-image grid. 1 = food, 0 = background.
// Defined in SupportPlane (rather than Segmentation) so the LiDAR fitter doesn't depend
// on the segmenter module — Segmentation can produce one of these from its argmax map.
public struct BinaryMask: Sendable {
    public let pixels: [UInt8]
    public let width: Int
    public let height: Int

    public init(pixels: [UInt8], width: Int, height: Int) {
        precondition(pixels.count == width * height,
                     "BinaryMask pixels.count must equal width * height")
        self.pixels = pixels
        self.width = width
        self.height = height
    }

    @inline(__always)
    public func isFood(x: Int, y: Int) -> Bool {
        pixels[y * width + x] != 0
    }
}

import PortableContracts

// Capture-path dispatch per design §2.3 / Req 3.5, 3.8.

/// LiDAR sensor status at the time of nadir capture. Computed by the capture flow
/// before calling the pipeline. `foodRegionCoveragePercent` is the fraction of food-region
/// pixels (from a preliminary bounding-region estimate) that have high-confidence depth.
public struct LiDARStatus: Sendable, Equatable {
    public let available: Bool
    /// 0.0 .. 100.0. Meaningful only when `available` is true.
    public let foodRegionCoveragePercent: Float

    public init(available: Bool, foodRegionCoveragePercent: Float = 0) {
        self.available = available
        self.foodRegionCoveragePercent = foodRegionCoveragePercent
    }

    /// Convenience: LiDAR not present on this device.
    public static let unavailable = LiDARStatus(available: false, foodRegionCoveragePercent: 0)
}

/// Whether a support plane was successfully detected during the preliminary scan.
/// The capture flow produces this before calling `selectCapturePath`.
public struct SupportPlaneCandidate: Sendable, Equatable {
    public let detected: Bool

    public init(detected: Bool) {
        self.detected = detected
    }
}

/// Pure dispatch function per design §2.3.
///
/// Returns `.singleViewLidar` only when ALL three conditions hold:
///   1. LiDAR sensor is available.
///   2. A support plane has been detected.
///   3. Valid depth covers ≥ 80 % of the food region (Req 3.5).
///
/// Otherwise returns `.twoViewSfS`.
public func selectCapturePath(
    lidar: LiDARStatus,
    supportPlane: SupportPlaneCandidate
) -> CapturePath {
    guard lidar.available,
          supportPlane.detected,
          lidar.foodRegionCoveragePercent >= 80 else {
        return .twoViewSfS
    }
    return .singleViewLidar
}

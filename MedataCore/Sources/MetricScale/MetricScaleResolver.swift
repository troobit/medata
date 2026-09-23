import Foundation
import PortableContracts

// Pure-function metric-scale resolver per design §6.4 / Req 7. Inputs are mm/px
// scales — the LiDAR-side adapter converts m/px → mm/px (factor 1000) before
// calling resolve(), so this function operates in a single unit system per §6.4.
public enum MetricScaleError: Error, Equatable {
    case noScaleAvailable
}

public struct MetricScale: Sendable, Equatable, Codable {
    public let metresPerVoxelEdgeMm: Float    // s_meal at the food plane, mm/pixel
    public let sigmaScale: Float              // σ_s ∈ [ε, 1] per Req 7
    public let cardScaleAvailable: Bool
    public let lidarScaleAvailable: Bool

    public init(metresPerVoxelEdgeMm: Float, sigmaScale: Float,
                cardScaleAvailable: Bool, lidarScaleAvailable: Bool) {
        self.metresPerVoxelEdgeMm = metresPerVoxelEdgeMm
        self.sigmaScale = sigmaScale
        self.cardScaleAvailable = cardScaleAvailable
        self.lidarScaleAvailable = lidarScaleAvailable
    }
}

public enum MetricScaleResolver {
    // ε floor per Req 13.1 (sub-confidence floor used by σ_meal aggregation).
    public static let sigmaFloor: Float = 0.05

    // Both inputs are mm/pixel at the food plane. Pass nil for an unavailable signal.
    public static func resolve(
        cardScaleMmPerPx: Float?,
        lidarScaleMmPerPx: Float?
    ) throws -> MetricScale {
        switch (cardScaleMmPerPx, lidarScaleMmPerPx) {
        case let (s_card?, s_lidar?):
            // Symmetric-agreement form per §6.4 (M4 fix).
            let avg = (s_card + s_lidar) / 2
            let disagreement = avg > 0 ? abs(s_lidar - s_card) / avg : 1
            let a = 1 - min(1, disagreement)
            let sigma = clampSigma(0.85 + 0.15 * a)
            return MetricScale(
                metresPerVoxelEdgeMm: s_lidar,
                sigmaScale: sigma,
                cardScaleAvailable: true,
                lidarScaleAvailable: true
            )
        case let (nil, s_lidar?):
            return MetricScale(
                metresPerVoxelEdgeMm: s_lidar,
                sigmaScale: clampSigma(0.85),
                cardScaleAvailable: false,
                lidarScaleAvailable: true
            )
        case let (s_card?, nil):
            return MetricScale(
                metresPerVoxelEdgeMm: s_card,
                sigmaScale: clampSigma(0.85),
                cardScaleAvailable: true,
                lidarScaleAvailable: false
            )
        case (nil, nil):
            throw MetricScaleError.noScaleAvailable
        }
    }

    @inline(__always)
    private static func clampSigma(_ s: Float) -> Float {
        max(sigmaFloor, min(1, s))
    }
}

// LiDAR adapter: convert m/px (raw input) → mm/px (resolver contract). Caller passes
// the m/px scale derived from depth statistics over the food region; this is the only
// place the unit conversion happens, per §6.4.
public enum LiDARScaleAdapter {
    public static func mmPerPx(fromMetresPerPx mPerPx: Float) -> Float {
        mPerPx * 1000
    }
}

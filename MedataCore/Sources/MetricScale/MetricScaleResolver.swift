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
    // A detected rectangle whose scale disagrees with LiDAR by more than this
    // is not the card (two-view-trust Req 4.1): plate rims and packaging pass
    // Vision's ID-1 aspect envelope and read 17–66 % off on the 2026-09-24
    // bundles, where a real card on the table sits within a few per cent of
    // the food plane. Such a rectangle is dropped and the result is the
    // LiDAR-only one, so a false card can never raise σ_scale.
    public static let maxCardLidarDisagreement: Float = 0.15

    // Both inputs are mm/pixel at the food plane. Pass nil for an unavailable signal.
    public static func resolve(
        cardScaleMmPerPx: Float?,
        lidarScaleMmPerPx: Float?
    ) throws -> MetricScale {
        switch (cardScaleMmPerPx, lidarScaleMmPerPx) {
        case let (s_card?, s_lidar?):
            // Symmetric-agreement form per §6.4 (M4 fix).
            let disagreement = Self.disagreement(s_card, s_lidar)
            if disagreement > maxCardLidarDisagreement {
                return try resolve(cardScaleMmPerPx: nil, lidarScaleMmPerPx: s_lidar)
            }
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

    /// Symmetric relative disagreement between two mm/px scales, 1 when
    /// their mean is not positive.
    public static func disagreement(_ a: Float, _ b: Float) -> Float {
        let avg = (a + b) / 2
        return avg > 0 ? abs(a - b) / avg : 1
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

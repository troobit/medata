import Foundation
import PortableContracts

// σ_geom_view lookup per Req 13.2.
public enum ViewCoverage: Equatable, Sendable {
    case twoViewFull        // clean two-view, full silhouette agreement → σ_view = 1.00
    case singleViewFull     // single-view LiDAR, ≥80% LiDAR coverage   → σ_view = 0.90
    case twoViewPartial     // two-view, ≥1 class in one view only       → σ_view = 0.75
    case singleViewPartial  // single-view LiDAR, 50–80% LiDAR coverage  → σ_view = 0.60

    public var sigmaView: Float {
        switch self {
        case .twoViewFull:      return 1.00
        case .singleViewFull:   return 0.90
        case .twoViewPartial:   return 0.75
        case .singleViewPartial: return 0.60
        }
    }
}

// Decomposed σ_geom sub-factors. Stored per Req 13.4 so the combination can be revisited.
public struct GeomSubconfidences: Sendable, Codable, Equatable {
    public let sigmaView: Float     // 0.60..1.00, lookup per ViewCoverage
    public let sigmaPlane: Float    // exp(−r/5) · iter_penalty
    public let sigmaOccl: Float     // 1.00 unless single-view with inter-class occlusion

    public init(sigmaView: Float, sigmaPlane: Float, sigmaOccl: Float) {
        self.sigmaView = sigmaView
        self.sigmaPlane = sigmaPlane
        self.sigmaOccl = sigmaOccl
    }

    public var product: Float { sigmaView * sigmaPlane * sigmaOccl }
}

// Full confidence record persisted with the meal (Req 13.4).
public struct ConfidenceResult: Sendable, Codable, Equatable {
    public let sigmaMeal: Float     // geometric mean, floored at ε (Req 13.1)
    public let sigmaScale: Float    // σ_s from MetricScale
    public let sigmaSeg: Float      // mean class probability from Segmentation
    public let sigmaGeom: GeomSubconfidences

    public init(sigmaMeal: Float, sigmaScale: Float, sigmaSeg: Float, sigmaGeom: GeomSubconfidences) {
        self.sigmaMeal = sigmaMeal
        self.sigmaScale = sigmaScale
        self.sigmaSeg = sigmaSeg
        self.sigmaGeom = sigmaGeom
    }
}

// Pure computation per design §6.8 / Req 13. No mutable state.
public enum Confidence {

    // ε floor applied to each of the three top-level inputs before the geometric mean.
    public static let epsilon: Float = 0.05

    // Uncertain-estimate UI threshold (Req 13.5).
    public static let uncertainThreshold: Float = 0.6

    // Compute σ_meal and all sub-factors.
    //
    // Parameters:
    //   sigmaScale         — σ_s from MetricScale.resolve (Req 7.1)
    //   sigmaSeg           — mean top-class probability over food pixels (M8 pin)
    //   planeFitResidualMm — r from SupportPlane fit (Req 4.6), used in σ_plane formula
    //   viewCoverage       — lookup-table input per Req 13.2
    //   capturePath        — determines whether σ_occl applies
    //   interClassOcclusionDetected — nadir-view flag from HeightFieldEstimator (§6.8)
    //   cardOnlyPath       — true when support plane used card-only iterative fit (§4.3)
    //   cardOnlyIterations — number of iterations taken; penalty applied when == 5 (§6.8)
    public static func combine(
        sigmaScale: Float,
        sigmaSeg: Float,
        planeFitResidualMm: Float,
        viewCoverage: ViewCoverage,
        capturePath: CapturePath,
        interClassOcclusionDetected: Bool,
        cardOnlyPath: Bool,
        cardOnlyIterations: Int
    ) -> ConfidenceResult {
        // σ_geom sub-factors (not individually floored — product is floored at meal level)
        let sigmaView  = viewCoverage.sigmaView
        var sigmaPlane = Foundation.exp(-planeFitResidualMm / 5.0)  // r_0 = 5 mm
        if cardOnlyPath && cardOnlyIterations == 5 {
            sigmaPlane *= 0.9   // best-of-5 fallback penalty per §6.8
        }
        let sigmaOccl: Float
        if capturePath == .singleViewLidar && interClassOcclusionDetected {
            sigmaOccl = 0.80
        } else {
            sigmaOccl = 1.00
        }

        let sigmaGeom = GeomSubconfidences(
            sigmaView:  sigmaView,
            sigmaPlane: sigmaPlane,
            sigmaOccl:  sigmaOccl
        )

        // Floor the three top-level inputs independently, then compute geometric mean.
        let sTilde    = max(epsilon, sigmaScale)
        let segTilde  = max(epsilon, sigmaSeg)
        let geomTilde = max(epsilon, sigmaGeom.product)
        // Clamp after pow to absorb float rounding when all inputs equal ε exactly.
        let sigmaMeal = max(epsilon, Foundation.pow(sTilde * segTilde * geomTilde, 1.0 / 3.0))

        return ConfidenceResult(
            sigmaMeal:  sigmaMeal,
            sigmaScale: sigmaScale,
            sigmaSeg:   sigmaSeg,
            sigmaGeom:  sigmaGeom
        )
    }
}

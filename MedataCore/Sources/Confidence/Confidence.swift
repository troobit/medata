import Foundation
import PortableContracts

// σ_geom_view lookup per Req 13.2.
public enum ViewCoverage: Equatable, Sendable {
    case twoViewFull          // clean two-view, full silhouette agreement → σ_view = 1.00
    case singleViewFull       // single-view LiDAR, ≥80% LiDAR coverage    → σ_view = 0.90
    case twoViewPartial       // two-view, ≥1 class in one view only        → σ_view = 0.75
    case singleViewPartial    // single-view LiDAR, 50–80% LiDAR coverage   → σ_view = 0.60
    case singleViewMinimal    // single-view LiDAR, 30–50% LiDAR coverage   → σ_view = 0.30 (Decision 47)

    public var sigmaView: Float {
        switch self {
        case .twoViewFull:        return 1.00
        case .singleViewFull:     return 0.90
        case .twoViewPartial:     return 0.75
        case .singleViewPartial:  return 0.60
        case .singleViewMinimal:  return 0.30
        }
    }
}

// Decomposed σ_geom sub-factors. Stored per Req 13.4 so the combination can be revisited.
public struct GeomSubconfidences: Sendable, Codable, Equatable {
    public let sigmaView: Float     // 0.30..1.00, lookup per ViewCoverage
    public let sigmaPlane: Float    // exp(−r/5) · iter_penalty
    public let sigmaOccl: Float     // 1.00 unless single-view with inter-class occlusion
    public let sigmaTilt: Float     // max(ε, cos(Δθ_capture)) per Decision 44

    public init(sigmaView: Float, sigmaPlane: Float, sigmaOccl: Float, sigmaTilt: Float = 1.0) {
        self.sigmaView = sigmaView
        self.sigmaPlane = sigmaPlane
        self.sigmaOccl = sigmaOccl
        self.sigmaTilt = sigmaTilt
    }

    // Legacy records persisted before sigmaTilt was added decode it as 1.0
    // (the identity multiplier) so historical σ_meal values are not retroactively
    // penalised. Req 13.4.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sigmaView = try c.decode(Float.self, forKey: .sigmaView)
        sigmaPlane = try c.decode(Float.self, forKey: .sigmaPlane)
        sigmaOccl = try c.decode(Float.self, forKey: .sigmaOccl)
        sigmaTilt = try c.decodeIfPresent(Float.self, forKey: .sigmaTilt) ?? 1.0
    }

    public var product: Float { sigmaView * sigmaPlane * sigmaOccl * sigmaTilt }
}

// Full confidence record persisted with the meal (Req 13.4).
public struct ConfidenceResult: Sendable, Codable, Equatable {
    public let sigmaMeal: Float                 // geometric mean, floored at ε (Req 13.1)
    public let sigmaScale: Float                // σ_s from MetricScale
    public let sigmaSeg: Float                  // mean class probability from Segmentation
    public let sigmaGeom: GeomSubconfidences
    public let deltaThetaNadirDeg: Float        // per-stage angular error at capture, Req 13.4
    public let deltaThetaObliqueDeg: Float?     // nil for single-view path, Req 13.4

    public init(
        sigmaMeal: Float,
        sigmaScale: Float,
        sigmaSeg: Float,
        sigmaGeom: GeomSubconfidences,
        deltaThetaNadirDeg: Float = 0,
        deltaThetaObliqueDeg: Float? = nil
    ) {
        self.sigmaMeal = sigmaMeal
        self.sigmaScale = sigmaScale
        self.sigmaSeg = sigmaSeg
        self.sigmaGeom = sigmaGeom
        self.deltaThetaNadirDeg = deltaThetaNadirDeg
        self.deltaThetaObliqueDeg = deltaThetaObliqueDeg
    }

    // Legacy records decode Δθ fields as 0 / nil so they remain interpretable.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sigmaMeal = try c.decode(Float.self, forKey: .sigmaMeal)
        sigmaScale = try c.decode(Float.self, forKey: .sigmaScale)
        sigmaSeg = try c.decode(Float.self, forKey: .sigmaSeg)
        sigmaGeom = try c.decode(GeomSubconfidences.self, forKey: .sigmaGeom)
        deltaThetaNadirDeg = try c.decodeIfPresent(Float.self, forKey: .deltaThetaNadirDeg) ?? 0
        deltaThetaObliqueDeg = try c.decodeIfPresent(Float.self, forKey: .deltaThetaObliqueDeg)
    }
}

// Pure computation per design §6.8 / Req 13. No mutable state.
public enum Confidence {

    // ε floor applied to each of the three top-level inputs before the geometric mean,
    // and to σ_tilt = cos(Δθ). Lowered from 0.05 to 0.01 per Decision 45 so soft
    // acceptance of high-tilt captures still produces a meaningful (very low)
    // confidence rather than collapsing to 0.05.
    public static let epsilon: Float = 0.01

    // Uncertain-estimate UI threshold (Req 13.5).
    public static let uncertainThreshold: Float = 0.6

    // Multiplicative penalty on σ_plane when the support plane came from the
    // edge-band fallback rather than the food-support fit
    // (`specs/estimation/support-plane-reference/` Req 4.6, Decision 12). It is a
    // SEPARATE factor rather than a residual adjustment precisely so that the
    // persisted `planeResidualMm` stays the measured residual: the fallback plane
    // can be a perfectly good fit to the wrong surface, so its residual says
    // nothing about the error the reference introduces.
    //
    // [owed] — a task 26 corpus measurement. 0.9 mirrors the card-only best-of-5
    // penalty below and satisfies Req 4.6's "no higher than a restricted fit of
    // equal residual" at any value in (0, 1); the corpus is what prices it.
    public static let supportPlaneFallbackPenalty: Float = 0.9

    // Compute σ_meal and all sub-factors.
    //
    // Parameters:
    //   sigmaScale                — σ_s from MetricScale.resolve (Req 7.1)
    //   sigmaSeg                  — mean top-class probability over food pixels (M8 pin)
    //   planeFitResidualMm        — r from SupportPlane fit (Req 4.6), used in σ_plane formula
    //   viewCoverage              — lookup-table input per Req 13.2
    //   capturePath               — determines whether σ_occl applies
    //   interClassOcclusionDetected — nadir-view flag from HeightFieldEstimator (§6.8)
    //   cardOnlyPath              — true when support plane used card-only iterative fit (§4.3)
    //   cardOnlyIterations        — number of iterations taken; penalty applied when == 5 (§6.8)
    //   supportPlaneFallback      — the plane came from the edge-band fallback rather
    //                               than the food-support fit (support-plane-reference Req 4.6)
    //   deltaThetaNadirDeg        — angular deviation of the nadir frame from 0° at shutter
    //   deltaThetaObliqueDeg      — angular deviation of the oblique frame from 25°; nil = single-view
    public static func combine(
        sigmaScale: Float,
        sigmaSeg: Float,
        planeFitResidualMm: Float,
        viewCoverage: ViewCoverage,
        capturePath: CapturePath,
        interClassOcclusionDetected: Bool,
        cardOnlyPath: Bool,
        cardOnlyIterations: Int,
        deltaThetaNadirDeg: Float = 0,
        deltaThetaObliqueDeg: Float? = nil,
        supportPlaneFallback: Bool = false
    ) -> ConfidenceResult {
        // σ_geom sub-factors (not individually floored — product is floored at meal level)
        let sigmaView  = viewCoverage.sigmaView
        var sigmaPlane = Foundation.exp(-planeFitResidualMm / 5.0)  // r_0 = 5 mm
        if cardOnlyPath && cardOnlyIterations == 5 {
            sigmaPlane *= 0.9   // best-of-5 fallback penalty per §6.8
        }
        if supportPlaneFallback {
            // support-plane-reference Req 4.6: the fallback plane must never report
            // higher confidence than a restricted fit of equal residual.
            sigmaPlane *= supportPlaneFallbackPenalty
        }
        let sigmaOccl: Float
        if capturePath == .singleViewLidar && interClassOcclusionDetected {
            sigmaOccl = 0.80
        } else {
            sigmaOccl = 1.00
        }

        // σ_tilt per Decision 44: cos(Δθ_capture), floored at ε. For two-view the
        // worse of the two views is taken, since the volume bound is set by the
        // worse-conditioned view. For single-view only nadir applies.
        let deltaThetaDeg: Float
        if let oblique = deltaThetaObliqueDeg {
            deltaThetaDeg = max(deltaThetaNadirDeg, oblique)
        } else {
            deltaThetaDeg = deltaThetaNadirDeg
        }
        let deltaThetaRad = deltaThetaDeg * .pi / 180
        let sigmaTilt = max(epsilon, Foundation.cos(deltaThetaRad))

        let sigmaGeom = GeomSubconfidences(
            sigmaView:  sigmaView,
            sigmaPlane: sigmaPlane,
            sigmaOccl:  sigmaOccl,
            sigmaTilt:  sigmaTilt
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
            sigmaGeom:  sigmaGeom,
            deltaThetaNadirDeg: deltaThetaNadirDeg,
            deltaThetaObliqueDeg: deltaThetaObliqueDeg
        )
    }
}

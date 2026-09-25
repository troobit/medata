import CaptureKit
import Confidence
import Foods
import Foundation
import Macros
import MetricScale
import PortableContracts
import Segmentation
import SupportPlane
import Volume

// Bridges between Swift-ergonomic module types and the Pb* wire types stored in
// MealRecord. These are the only files in Pipeline that touch the Pb* constructors.

public enum PipelineBridges {
    /// Nadir-frame points (mm, §6.0) as oblique pixels through p₂ = T·p₁ and
    /// the §6.0 projection (−z forward). Empty when any point lands behind
    /// the oblique camera, so a caller clearing a quad clears nothing.
    public static func projectToOblique(
        _ pointsMm: [Vec3], transform1To2 m: Mat4, intrinsics k: CameraIntrinsics
    ) -> [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for p in pointsMm {
            let x = m[col: 0, row: 0] * p.x + m[col: 1, row: 0] * p.y + m[col: 2, row: 0] * p.z + m[col: 3, row: 0]
            let y = m[col: 0, row: 1] * p.x + m[col: 1, row: 1] * p.y + m[col: 2, row: 1] * p.z + m[col: 3, row: 1]
            let z = m[col: 0, row: 2] * p.x + m[col: 1, row: 2] * p.y + m[col: 2, row: 2] * p.z + m[col: 3, row: 2]
            guard z < 0 else { return [] }
            out.append(SIMD2(k.fx * x / -z + k.cx, k.fy * y / -z + k.cy))
        }
        return out
    }


    // MARK: - SupportPlane → PbSupportPlane

    static func pbSupportPlane(_ sp: SupportPlane) -> PbSupportPlane {
        var out = PbSupportPlane()
        out.normal = sp.normal.pb
        out.distance = sp.distanceMm
        out.residualMm = sp.residualMm
        if let iters = sp.convergedIterations {
            out.convergedIterations = Int32(iters)
        }
        return out
    }

    // MARK: - MetricScale → PbMetricScale

    static func pbMetricScale(_ ms: MetricScale) -> PbMetricScale {
        var out = PbMetricScale()
        out.metresPerVoxelEdge = ms.metresPerVoxelEdgeMm
        out.sigmaScale = ms.sigmaScale
        out.cardScaleAvailable = ms.cardScaleAvailable
        out.lidarScaleAvailable = ms.lidarScaleAvailable
        return out
    }

    // MARK: - MacroResult → PbMacroResult

    static func pbMacroResult(_ mr: MacroResult) -> PbMacroResult {
        var out = PbMacroResult()
        out.totalCarbsG = mr.totalCarbsG
        out.perClass = Dictionary(uniqueKeysWithValues: mr.perClass.map { (k, v) in
            (k, pbPerClassMacros(v))
        })
        var ct = PbClinicalMacros()
        ct.energyKj = mr.clinicalTotals.energyKJ
        ct.proteinG = mr.clinicalTotals.proteinG
        ct.fatG = mr.clinicalTotals.fatG
        ct.fibreG = mr.clinicalTotals.fibreG
        out.clinicalTotals = ct
        out.liquidOverEstimate = mr.liquidOverEstimate
        return out
    }

    private static func pbPerClassMacros(_ pcm: PerClassMacros) -> PbPerClassMacros {
        var out = PbPerClassMacros()
        out.volumeCm3 = pcm.volumeCm3
        out.massG = pcm.massG
        out.carbsG = pcm.carbsG
        out.densitySource = pcm.densitySource
        out.coefficientSource = pcm.coefficientSource
        out.betaUsed = pcm.betaUsed
        out.betaStatus = pbBetaStatus(pcm.betaStatus)
        out.proteinG = pcm.proteinG
        out.fatG = pcm.fatG
        out.deviceVerified = pcm.deviceVerified
        out.isLiquid = pcm.isLiquid
        return out
    }

    // MARK: - ConfidenceResult → PbConfidenceResult

    static func pbConfidenceResult(_ cr: ConfidenceResult) -> PbConfidenceResult {
        var out = PbConfidenceResult()
        out.sigmaMeal = cr.sigmaMeal
        out.sigmaScale = cr.sigmaScale
        out.sigmaSeg = cr.sigmaSeg
        var geom = PbGeomSubconfidences()
        geom.sigmaView = cr.sigmaGeom.sigmaView
        geom.sigmaPlane = cr.sigmaGeom.sigmaPlane
        geom.sigmaOccl = cr.sigmaGeom.sigmaOccl
        geom.sigmaTilt = cr.sigmaGeom.sigmaTilt
        out.sigmaGeom = geom
        out.deltaThetaNadirDeg = cr.deltaThetaNadirDeg
        if let oblique = cr.deltaThetaObliqueDeg {
            out.deltaThetaObliqueDeg = oblique
        }
        return out
    }

    // MARK: - VolumeResult from single-view HeightFieldEstimate → PbVolumeResult

    static func pbVolumeResult(singleView est: HeightFieldEstimate,
                               preBetaVolumesCm3: [String: Float]) -> PbVolumeResult {
        var out = PbVolumeResult()
        out.perClassVolumesCm3 = est.perClassVolumesCm3
        out.lidarCoverageFraction = est.lidarCoverageFraction
        out.ambiguousVoxelFraction = 0
        out.perClassVolumesPreBetaCm3 = filteredPreBeta(preBetaVolumesCm3, to: est.perClassVolumesCm3)
        return out
    }

    // MARK: - VolumeResult from two-view VoxelCarveEstimate → PbVolumeResult

    static func pbVolumeResult(twoView est: VoxelCarveEstimate,
                               preBetaVolumesCm3: [String: Float]) -> PbVolumeResult {
        var out = PbVolumeResult()
        out.perClassVolumesCm3 = est.perClassVolumesCm3
        out.ambiguousVoxelFraction = est.ambiguousVoxelFraction
        out.voxelGridSummary = est.voxelGridSummary
        out.perClassVolumesPreBetaCm3 = filteredPreBeta(preBetaVolumesCm3, to: est.perClassVolumesCm3)
        return out
    }

    // The estimators' VolumeStats pre-β map is pre-threshold, so it can hold
    // classes the estimate discarded. The persisted pre-β map is keyed
    // identically to per_class_volumes_cm3 (meal-review Decision 17).
    private static func filteredPreBeta(_ preBeta: [String: Float],
                                        to persisted: [String: Float]) -> [String: Float] {
        preBeta.filter { persisted[$0.key] != nil }
    }

    // MARK: - BetaCalibrationStatus bridge

    static func pbBetaStatus(_ s: Foods.BetaCalibrationStatus) -> PbBetaCalibrationStatus {
        switch s {
        case .calibrated:           return .calibrated
        case .uncalibratedPooled:   return .uncalibratedPooled
        case .uncalibratedUnity:    return .uncalibratedUnity
        }
    }

    // MARK: - CandidateEvidence → PbCandidateSet

    // Ranking is already fixed by `CandidateEvidence.compute`; this only splits
    // each ranked set into the parallel arrays the record persists (Decision 10),
    // written together so the reader's equal-length invariant holds by
    // construction.
    static func pbCandidateEvidence(
        _ evidence: [String: [CandidateEvidence.Candidate]]
    ) -> [String: PbCandidateSet] {
        evidence.mapValues { candidates in
            var out = PbCandidateSet()
            out.classNames = candidates.map(\.className)
            out.meanPermille = candidates.map(\.meanPermille)
            return out
        }
    }

    // MARK: - BinaryMask from ArgmaxMap (food-like pixels: solid, liquid, unknown)

    static func foodMask(from argmax: ArgmaxMap, palette: ClassPalette) -> BinaryMask {
        var pixels = [UInt8](repeating: 0, count: argmax.width * argmax.height)
        argmax.pixels.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<(argmax.width * argmax.height) {
                let c = Int(buf[i])
                pixels[i] = palette.isVolumetricClass(c) ? 1 : 0
            }
        }
        return BinaryMask(pixels: pixels, width: argmax.width, height: argmax.height)
    }

    // MARK: - Mat4 operations for transform computation

    // Rigid-body inverse: if T = [R|t; 0|1] then T^{-1} = [R^T | -R^T·t; 0|1].
    //
    // `columns[c][r]` is column c, row r, so R(row i, col j) = columns[j][i] and
    // R^T(i, j) = R(j, i) = columns[i][j]. Until 2026-09-25 this function read
    // R^T(i, j) as columns[j][i] — that is R itself — and returned [R | −R·t],
    // which is not an inverse. `transform1To2` therefore composed R₂·R₁ instead
    // of R₂ᵀ·R₁: for two cameras both looking down, a near-180° "relative"
    // rotation (163° and 73° on the 2026-09-24 bundles) in place of the real
    // 25°, and the two silhouettes never met in the carve (two-view-trust,
    // night audit). Pinned by TwoViewTransformTests.
    static func rigidInverse(_ m: Mat4) -> Mat4 {
        let c = m.columns
        // R^T(i, j) = R(j, i) = columns[i][j]
        let rt00 = c[0][0]; let rt01 = c[0][1]; let rt02 = c[0][2]
        let rt10 = c[1][0]; let rt11 = c[1][1]; let rt12 = c[1][2]
        let rt20 = c[2][0]; let rt21 = c[2][1]; let rt22 = c[2][2]
        // t (column 3, rows 0–2)
        let tx = c[3][0]; let ty = c[3][1]; let tz = c[3][2]
        // -R^T · t
        let itx = -(rt00 * tx + rt01 * ty + rt02 * tz)
        let ity = -(rt10 * tx + rt11 * ty + rt12 * tz)
        let itz = -(rt20 * tx + rt21 * ty + rt22 * tz)
        // Output column j holds R^T(0, j), R^T(1, j), R^T(2, j).
        return Mat4(columns: [
            [rt00, rt10, rt20, 0],
            [rt01, rt11, rt21, 0],
            [rt02, rt12, rt22, 0],
            [itx,  ity,  itz,  1]
        ])
    }

    // Column-major 4×4 matrix multiply: result = lhs · rhs.
    static func multiply(_ lhs: Mat4, _ rhs: Mat4) -> Mat4 {
        let a = lhs.columns; let b = rhs.columns
        var c = [[Float]](repeating: [Float](repeating: 0, count: 4), count: 4)
        for col in 0..<4 {
            for row in 0..<4 {
                var sum: Float = 0
                for k in 0..<4 { sum += a[k][row] * b[col][k] }
                c[col][row] = sum
            }
        }
        return Mat4(columns: c)
    }

    // Compute T_{1→2}: p₂ = T · p₁  (design §6.0), in the frame and units the
    // carve uses. `RawFrame.worldFromCamera` is the platform pose as ARKit
    // gives it: translation in METRES, camera frame +x right, +y UP, −z
    // forward. The carve's points are millimetres in the §6.0 frame (+y DOWN,
    // the image row direction; `projectCamera1`, `CameraGravity`). So
    //   T_img = F · (worldFromCamera₂)⁻¹ · worldFromCamera₁ · F,  F = diag(1, −1, 1, 1)
    // with the translation scaled by 1000. Before 2026-09-25 neither happened,
    // and the oblique camera sat 0.1 mm from the nadir one in a mirrored frame
    // (two-view-trust, night audit).
    static let millimetresPerMetre: Float = 1000
    static func transform1To2(nadir: RawFrame, oblique: RawFrame) -> Mat4 {
        let worldToOblique = rigidInverse(oblique.worldFromCamera)
        let arkit = multiply(worldToOblique, nadir.worldFromCamera)
        return imageFrameMillimetres(fromARKitCameraTransform: arkit)
    }

    // Conjugate an ARKit camera→camera rigid transform (metres, +y up) into the
    // §6.0 frame (millimetres, +y down): T' = F·T·F, translation × 1000.
    static func imageFrameMillimetres(fromARKitCameraTransform t: Mat4) -> Mat4 {
        let c = t.columns
        // F·R·F negates the row-1 and column-1 off-diagonals of R; F·t flips t.y.
        func sign(_ col: Int, _ row: Int) -> Float { ((col == 1) != (row == 1)) ? -1 : 1 }
        var out = [[Float]](repeating: [Float](repeating: 0, count: 4), count: 4)
        for col in 0..<3 {
            for row in 0..<3 { out[col][row] = c[col][row] * sign(col, row) }
        }
        out[3] = [c[3][0] * millimetresPerMetre,
                  -c[3][1] * millimetresPerMetre,
                  c[3][2] * millimetresPerMetre, 1]
        return Mat4(columns: out)
    }
}

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

enum PipelineBridges {

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

    static func pbVolumeResult(singleView est: HeightFieldEstimate) -> PbVolumeResult {
        var out = PbVolumeResult()
        out.perClassVolumesCm3 = est.perClassVolumesCm3
        out.lidarCoverageFraction = est.lidarCoverageFraction
        out.ambiguousVoxelFraction = 0
        return out
    }

    // MARK: - VolumeResult from two-view VoxelCarveEstimate → PbVolumeResult

    static func pbVolumeResult(twoView est: VoxelCarveEstimate) -> PbVolumeResult {
        var out = PbVolumeResult()
        out.perClassVolumesCm3 = est.perClassVolumesCm3
        out.ambiguousVoxelFraction = est.ambiguousVoxelFraction
        out.voxelGridSummary = est.voxelGridSummary
        return out
    }

    // MARK: - BetaCalibrationStatus bridge

    static func pbBetaStatus(_ s: Foods.BetaCalibrationStatus) -> PbBetaCalibrationStatus {
        switch s {
        case .calibrated:           return .calibrated
        case .uncalibratedPooled:   return .uncalibratedPooled
        case .uncalibratedUnity:    return .uncalibratedUnity
        }
    }

    // MARK: - BinaryMask from ArgmaxMap (food pixels only)

    static func foodMask(from argmax: ArgmaxMap, palette: ClassPalette) -> BinaryMask {
        var pixels = [UInt8](repeating: 0, count: argmax.width * argmax.height)
        argmax.pixels.withUnsafeBytes { raw in
            let buf = raw.bindMemory(to: UInt8.self).baseAddress!
            for i in 0..<(argmax.width * argmax.height) {
                let c = Int(buf[i])
                pixels[i] = palette.isFoodClass(c) ? 1 : 0
            }
        }
        return BinaryMask(pixels: pixels, width: argmax.width, height: argmax.height)
    }

    // MARK: - Mat4 operations for transform computation

    // Rigid-body inverse: if T = [R|t; 0|1] then T^{-1} = [R^T | -R^T·t; 0|1].
    static func rigidInverse(_ m: Mat4) -> Mat4 {
        let r = m.columns
        // R^T (3×3 upper-left)
        let rt00 = r[0][0]; let rt01 = r[1][0]; let rt02 = r[2][0]
        let rt10 = r[0][1]; let rt11 = r[1][1]; let rt12 = r[2][1]
        let rt20 = r[0][2]; let rt21 = r[1][2]; let rt22 = r[2][2]
        // t (column 3, rows 0–2)
        let tx = r[3][0]; let ty = r[3][1]; let tz = r[3][2]
        // -R^T · t
        let itx = -(rt00 * tx + rt01 * ty + rt02 * tz)
        let ity = -(rt10 * tx + rt11 * ty + rt12 * tz)
        let itz = -(rt20 * tx + rt21 * ty + rt22 * tz)
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

    // Compute T_{1→2}: p₂ = T · p₁  (design §6.0)
    // T_{1→2} = (worldFromCamera₂)⁻¹ · worldFromCamera₁
    static func transform1To2(nadir: RawFrame, oblique: RawFrame) -> Mat4 {
        let worldToOblique = rigidInverse(oblique.worldFromCamera)
        return multiply(worldToOblique, nadir.worldFromCamera)
    }
}

import Foundation

// Per design §3.7. Served-portion bulk density and per-100 g coefficients for one food class.
public struct FoodEntry: Sendable, Equatable {
    public let classId: String
    public let name: String
    public let densityGPerCm3: Float        // g/cm³ (served-portion bulk density)
    public let energyKJPer100g: Float
    public let carbsMonoG: Float            // monosaccharide-equivalent per 100 g
    public let proteinG: Float
    public let fatG: Float
    public let fibreG: Float
    public let beta: Float                  // β_c ∈ (0, 1] per Req 11.7
    public let calibrationStatus: BetaCalibrationStatus
    public let densitySource: String
    public let compositionSource: String
    // nutrition5k-calibration Req 5.4 / 8.1: provenance is a separate dimension
    // from calibrationStatus (closed DB vocabulary: n5k_single_dominant |
    // n5k_mixture | gravimetric | none); device_verified is baked per class and
    // flipped only by the future device-spot-check spec.
    public let betaProvenance: String
    public let deviceVerified: Bool

    public init(
        classId: String, name: String,
        densityGPerCm3: Float, energyKJPer100g: Float, carbsMonoG: Float,
        proteinG: Float, fatG: Float, fibreG: Float,
        beta: Float, calibrationStatus: BetaCalibrationStatus,
        densitySource: String, compositionSource: String,
        betaProvenance: String = "none", deviceVerified: Bool = false
    ) {
        self.classId = classId
        self.name = name
        self.densityGPerCm3 = densityGPerCm3
        self.energyKJPer100g = energyKJPer100g
        self.carbsMonoG = carbsMonoG
        self.proteinG = proteinG
        self.fatG = fatG
        self.fibreG = fibreG
        self.beta = beta
        self.calibrationStatus = calibrationStatus
        self.densitySource = densitySource
        self.compositionSource = compositionSource
        self.betaProvenance = betaProvenance
        self.deviceVerified = deviceVerified
    }
}

// Mirrors PbBetaCalibrationStatus from BetaCorrectionTable.proto.
public enum BetaCalibrationStatus: String, Codable, Equatable, Sendable {
    case calibrated
    case uncalibratedPooled = "uncalibrated_pooled"
    case uncalibratedUnity  = "uncalibrated_unity"
}

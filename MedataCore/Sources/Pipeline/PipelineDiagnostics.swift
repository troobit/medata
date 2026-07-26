import Foundation
import Persistence
import Segmentation
import Volume

// Estimation-attempt diagnostics (snaq-parity lane A, Req 2.1/2.6/3.1–3.4).
//
// `PipelineDiagnostics` is a reference type created at the top of
// `Pipeline.estimate`; stages append measurements as they run, the do/catch
// stamps the outcome, and `snapshot()` builds the immutable `Sendable`
// `EstimationAttemptRecord` handed to `CaptureFlowDelegate.didCompleteAttempt`.
// The record is also the JSON payload persisted in the `estimation_outcomes`
// `measurements` column — schema-versioned via `v` so the in-app browser
// tolerates older rows. It carries derived measurements and references only,
// never raw capture imagery (Req 2.6).

public struct EstimationAttemptRecord: Codable, Sendable, Equatable {
    // Bump when the encoded shape changes incompatibly. Older rows keep their
    // stamped version; every field beyond the founding set is optional so the
    // decoder accepts rows written by any earlier schema.
    public static let currentSchemaVersion = 1

    // Shared vocabulary with the `estimation_outcomes.outcome` column and
    // the benchmark-report filters — one definition, so the producer and its
    // consumers cannot drift apart on the stored strings.
    public typealias Outcome = EstimationOutcomeKind

    // Failure encoding {domain, case, payload}. `domain` distinguishes
    // pipeline refusals ("estimation") from capture-stage refusals ("capture",
    // written by CaptureFlowModel for attempts that never reach the pipeline —
    // CaptureError is not an EstimationFailure).
    public struct FailureInfo: Codable, Sendable, Equatable {
        public let domain: String
        public let caseName: String
        public let payload: String?

        enum CodingKeys: String, CodingKey {
            case domain
            case caseName = "case"
            case payload
        }

        public init(domain: String, caseName: String, payload: String?) {
            self.domain = domain
            self.caseName = caseName
            self.payload = payload
        }

        // Estimation-domain encoding of the typed failure cases, with
        // associated values flattened into `payload`.
        public init(estimation failure: EstimationFailure) {
            let caseName: String
            var payload: String?
            switch failure {
            case .noLidarDevice: caseName = "noLidarDevice"
            case .arWorldTrackingLost: caseName = "arWorldTrackingLost"
            case .lidarUnavailableMidCapture: caseName = "lidarUnavailableMidCapture"
            case .degenerateCardPose: caseName = "degenerateCardPose"
            case .cardTooOblique: caseName = "cardTooOblique"
            case .lidarFitDegenerate: caseName = "lidarFitDegenerate"
            case .lidarFitResidualTooHigh: caseName = "lidarFitResidualTooHigh"
            case .iterationDiverged: caseName = "iterationDiverged"
            case .noScaleAvailable: caseName = "noScaleAvailable"
            case .noFoodPixels: caseName = "noFoodPixels"
            case .unrecognisedFood: caseName = "unrecognisedFood"
            case .noFoodVolumeRecovered: caseName = "noFoodVolumeRecovered"
            case .lidarCoverageTooLow(let classes):
                caseName = "lidarCoverageTooLow"
                payload = classes.joined(separator: ", ")
            case .obliqueTiltOutOfRange: caseName = "obliqueTiltOutOfRange"
            case .mealsDbCorrupt: caseName = "mealsDbCorrupt"
            case .internalError(let description):
                caseName = "internalError"
                payload = description
            }
            self.init(domain: "estimation", caseName: caseName, payload: payload)
        }
    }

    // Per-view segmenter measurements: food coverage plus the sub-stage
    // latency clocks from CoreMLSegmenter (Req 4.1 — the tail profile is read
    // from these fields on real captures). The timing fields are optional so
    // a segmenter without timings (the dev stub) records nil, never a fake
    // zero indistinguishable from a sub-millisecond stage.
    public struct SegmentationMeasurements: Codable, Sendable, Equatable {
        public let foodCoveragePercent: Float?
        public let preprocessMs: Int?
        public let predictionMs: Int?
        public let argmaxMs: Int?

        public init(foodCoveragePercent: Float?,
                    preprocessMs: Int?, predictionMs: Int?, argmaxMs: Int?) {
            self.foodCoveragePercent = foodCoveragePercent
            self.preprocessMs = preprocessMs
            self.predictionMs = predictionMs
            self.argmaxMs = argmaxMs
        }
    }

    // Volume-stage stats — the Codable mirror of `Volume.VolumeStats`.
    public struct VolumeMeasurements: Codable, Sendable, Equatable {
        public let perClassVolumesPreBetaCm3: [String: Float]
        public let perClassVolumesPostBetaCm3: [String: Float]
        public let betaApplied: [String: Float]
        public let thresholdDiscardedClasses: [String]
        public let degenerateVoxelSkipCount: Int
        public let degenerateRaySkipCount: Int
        public let lidarCoverageFraction: [String: Float]

        public init(perClassVolumesPreBetaCm3: [String: Float],
                    perClassVolumesPostBetaCm3: [String: Float],
                    betaApplied: [String: Float],
                    thresholdDiscardedClasses: [String],
                    degenerateVoxelSkipCount: Int,
                    degenerateRaySkipCount: Int,
                    lidarCoverageFraction: [String: Float]) {
            self.perClassVolumesPreBetaCm3 = perClassVolumesPreBetaCm3
            self.perClassVolumesPostBetaCm3 = perClassVolumesPostBetaCm3
            self.betaApplied = betaApplied
            self.thresholdDiscardedClasses = thresholdDiscardedClasses
            self.degenerateVoxelSkipCount = degenerateVoxelSkipCount
            self.degenerateRaySkipCount = degenerateRaySkipCount
            self.lidarCoverageFraction = lidarCoverageFraction
        }

        public init(stats: VolumeStats) {
            self.init(
                perClassVolumesPreBetaCm3: stats.perClassVolumesPreBetaCm3,
                perClassVolumesPostBetaCm3: stats.perClassVolumesPostBetaCm3,
                betaApplied: stats.betaApplied,
                thresholdDiscardedClasses: stats.thresholdDiscardedClasses,
                degenerateVoxelSkipCount: stats.degenerateVoxelSkipCount,
                degenerateRaySkipCount: stats.degenerateRaySkipCount,
                lidarCoverageFraction: stats.lidarCoverageFraction
            )
        }
    }

    // Compact per-class decomposition of a successful estimate (Req 3.4):
    // class → volume → matched food code → carbs, with the β applied. Copied
    // into the record so a later deleteMeal cannot hollow the attribution out.
    public struct ClassDecomposition: Codable, Sendable, Equatable {
        public let className: String
        public let volumeCm3: Float
        public let massG: Float
        public let carbsG: Float
        public let beta: Float
        public let densitySource: String
        public let coefficientSource: String

        public init(className: String, volumeCm3: Float, massG: Float,
                    carbsG: Float, beta: Float,
                    densitySource: String, coefficientSource: String) {
            self.className = className
            self.volumeCm3 = volumeCm3
            self.massG = massG
            self.carbsG = carbsG
            self.beta = beta
            self.densitySource = densitySource
            self.coefficientSource = coefficientSource
        }
    }

    public struct SigmaTerms: Codable, Sendable, Equatable {
        public let sigmaMeal: Float
        public let sigmaScale: Float
        public let sigmaSeg: Float
        public let sigmaPlane: Float
        public let sigmaView: Float
        public let sigmaTilt: Float

        public init(sigmaMeal: Float, sigmaScale: Float, sigmaSeg: Float,
                    sigmaPlane: Float, sigmaView: Float, sigmaTilt: Float) {
            self.sigmaMeal = sigmaMeal
            self.sigmaScale = sigmaScale
            self.sigmaSeg = sigmaSeg
            self.sigmaPlane = sigmaPlane
            self.sigmaView = sigmaView
            self.sigmaTilt = sigmaTilt
        }
    }

    // Founding required fields — present in every schema version.
    public let v: Int
    public let timestampMs: Int64
    public let outcome: Outcome
    public let modelVersion: String
    public let capturePath: String

    // Everything else is optional so older rows decode (Req 2.2 browser).
    public let failure: FailureInfo?
    public let mealID: String?
    public let nadirTiltDeg: Float?
    public let obliqueTiltDeg: Float?
    public let scaleSource: String?
    public let cardFallback: Bool?
    public let planeCandidateCount: Int?
    public let planeInlierCount: Int?
    public let planeResidualMm: Float?
    public let foodRegionCoveragePercent: Float?
    public let segmentationNadir: SegmentationMeasurements?
    public let segmentationOblique: SegmentationMeasurements?
    public let volume: VolumeMeasurements?
    public let preShutterSegmentationErrorCount: Int?
    public let decomposition: [ClassDecomposition]?
    public let sigma: SigmaTerms?

    public init(v: Int,
                timestampMs: Int64,
                outcome: Outcome,
                failure: FailureInfo?,
                modelVersion: String,
                mealID: String?,
                capturePath: String,
                nadirTiltDeg: Float? = nil,
                obliqueTiltDeg: Float? = nil,
                scaleSource: String? = nil,
                cardFallback: Bool? = nil,
                planeCandidateCount: Int? = nil,
                planeInlierCount: Int? = nil,
                planeResidualMm: Float? = nil,
                foodRegionCoveragePercent: Float? = nil,
                segmentationNadir: SegmentationMeasurements? = nil,
                segmentationOblique: SegmentationMeasurements? = nil,
                volume: VolumeMeasurements? = nil,
                preShutterSegmentationErrorCount: Int? = nil,
                decomposition: [ClassDecomposition]? = nil,
                sigma: SigmaTerms? = nil) {
        self.v = v
        self.timestampMs = timestampMs
        self.outcome = outcome
        self.failure = failure
        self.modelVersion = modelVersion
        self.mealID = mealID
        self.capturePath = capturePath
        self.nadirTiltDeg = nadirTiltDeg
        self.obliqueTiltDeg = obliqueTiltDeg
        self.scaleSource = scaleSource
        self.cardFallback = cardFallback
        self.planeCandidateCount = planeCandidateCount
        self.planeInlierCount = planeInlierCount
        self.planeResidualMm = planeResidualMm
        self.foodRegionCoveragePercent = foodRegionCoveragePercent
        self.segmentationNadir = segmentationNadir
        self.segmentationOblique = segmentationOblique
        self.volume = volume
        self.preShutterSegmentationErrorCount = preShutterSegmentationErrorCount
        self.decomposition = decomposition
        self.sigma = sigma
    }

    // The pre-shutter error counter lives in the App layer (PreShutterSegmenter)
    // and is merged at persist time by CaptureFlowModel; the snapshot itself is
    // immutable, so merging returns a copy.
    public func withPreShutterSegmentationErrorCount(_ count: Int) -> EstimationAttemptRecord {
        EstimationAttemptRecord(
            v: v, timestampMs: timestampMs, outcome: outcome, failure: failure,
            modelVersion: modelVersion, mealID: mealID, capturePath: capturePath,
            nadirTiltDeg: nadirTiltDeg, obliqueTiltDeg: obliqueTiltDeg,
            scaleSource: scaleSource, cardFallback: cardFallback,
            planeCandidateCount: planeCandidateCount,
            planeInlierCount: planeInlierCount, planeResidualMm: planeResidualMm,
            foodRegionCoveragePercent: foodRegionCoveragePercent,
            segmentationNadir: segmentationNadir,
            segmentationOblique: segmentationOblique,
            volume: volume,
            preShutterSegmentationErrorCount: count,
            decomposition: decomposition, sigma: sigma
        )
    }
}

// Reference-type accumulator: created at the top of `Pipeline.estimate`,
// appended to by stage helpers, stamped by the outcome do/catch, snapshotted
// once at handoff. It never crosses an isolation boundary — only the immutable
// snapshot does — so it is deliberately not Sendable.
public final class PipelineDiagnostics {
    public enum SegmentationView {
        case nadir
        case oblique
    }

    private let capturePath: String
    private let modelVersion: String
    private let timestampMs: Int64

    private var nadirTiltDeg: Float?
    private var obliqueTiltDeg: Float?
    private var scaleSource: String?
    private var cardFallback: Bool?
    private var planeCandidateCount: Int?
    private var planeInlierCount: Int?
    private var planeResidualMm: Float?
    private var foodRegionCoveragePercent: Float?
    private var segmentationNadir: EstimationAttemptRecord.SegmentationMeasurements?
    private var segmentationOblique: EstimationAttemptRecord.SegmentationMeasurements?
    private var volume: EstimationAttemptRecord.VolumeMeasurements?
    private var outcome: EstimationAttemptRecord.Outcome = .refused
    private var failure: EstimationAttemptRecord.FailureInfo?
    private var mealID: String?
    private var decomposition: [EstimationAttemptRecord.ClassDecomposition]?
    private var sigma: EstimationAttemptRecord.SigmaTerms?

    // Capture-bundle carriers (capture-bundle-recorder smolspec): the stage
    // body stashes its segmentation results here so `estimate`'s outcome arms
    // can hand them to CaptureBundleRecorder even when a later stage throws.
    // Carrier only — never encoded into the snapshot record; the Req 2.6
    // no-imagery rule applies to the record, not to bundles.
    public var debugNadirSegmentation: SegmentationResult?
    public var debugObliqueSegmentation: SegmentationResult?

    public init(capturePath: String, modelVersion: String, timestampMs: Int64) {
        self.capturePath = capturePath
        self.modelVersion = modelVersion
        self.timestampMs = timestampMs
    }

    // MARK: - stage measurements

    public func recordTilt(nadirDeg: Float, obliqueDeg: Float?) {
        nadirTiltDeg = nadirDeg
        obliqueTiltDeg = obliqueDeg
    }

    // `cardFallback` is sticky: a fallback recorded at card-detection time is
    // never cleared by the later scale-stage record.
    public func recordScale(source: String, cardFallback: Bool) {
        scaleSource = source
        self.cardFallback = (self.cardFallback ?? false) || cardFallback
    }

    public func recordCardFallback() {
        cardFallback = true
    }

    public func recordSupportPlane(candidateCount: Int, inlierCount: Int, residualMm: Float) {
        planeCandidateCount = candidateCount
        planeInlierCount = inlierCount
        planeResidualMm = residualMm
    }

    public func recordFoodRegionCoverage(percent: Float) {
        foodRegionCoveragePercent = percent
    }

    public func recordSegmentation(
        view: SegmentationView,
        measurements: EstimationAttemptRecord.SegmentationMeasurements
    ) {
        switch view {
        case .nadir: segmentationNadir = measurements
        case .oblique: segmentationOblique = measurements
        }
    }

    public func recordVolume(stats: VolumeStats) {
        volume = EstimationAttemptRecord.VolumeMeasurements(stats: stats)
    }

    // MARK: - outcome stamping (exactly one stamp per attempt)

    public func stampSuccess(
        mealID: String,
        decomposition: [EstimationAttemptRecord.ClassDecomposition],
        sigma: EstimationAttemptRecord.SigmaTerms
    ) {
        outcome = .success
        failure = nil
        self.mealID = mealID
        self.decomposition = decomposition
        self.sigma = sigma
    }

    public func stampFailure(_ estimationFailure: EstimationFailure) {
        outcome = .refused
        failure = EstimationAttemptRecord.FailureInfo(estimation: estimationFailure)
    }

    // Non-typed errors preserve the underlying description in Release builds,
    // not only the Swift type name (Req 3.3). `String(reflecting:)` rather
    // than `String(describing:)`: for a payload-less enum the latter yields
    // only the bare case name, losing the error type.
    public func stampError(_ error: any Error) {
        outcome = .refused
        failure = EstimationAttemptRecord.FailureInfo(
            domain: "estimation",
            caseName: "internalError",
            payload: String(reflecting: error)
        )
    }

    // MARK: - snapshot

    public func snapshot() -> EstimationAttemptRecord {
        EstimationAttemptRecord(
            v: EstimationAttemptRecord.currentSchemaVersion,
            timestampMs: timestampMs,
            outcome: outcome,
            failure: failure,
            modelVersion: modelVersion,
            mealID: mealID,
            capturePath: capturePath,
            nadirTiltDeg: nadirTiltDeg,
            obliqueTiltDeg: obliqueTiltDeg,
            scaleSource: scaleSource,
            cardFallback: cardFallback,
            planeCandidateCount: planeCandidateCount,
            planeInlierCount: planeInlierCount,
            planeResidualMm: planeResidualMm,
            foodRegionCoveragePercent: foodRegionCoveragePercent,
            segmentationNadir: segmentationNadir,
            segmentationOblique: segmentationOblique,
            volume: volume,
            preShutterSegmentationErrorCount: nil,
            decomposition: decomposition,
            sigma: sigma
        )
    }
}

// Bridge to the persisted row (specs/estimation/snaq-parity design Data
// Models). The snapshot itself becomes the `measurements` JSON and its
// failure the `failure` JSON — Persistence stores both opaquely because it
// sits below Pipeline in the dependency graph. Defined here (not in the App
// layer) so the encoding is exercised by the compiled MedataCore surface.
extension EstimationOutcome {
    public init(record: EstimationAttemptRecord, benchmarkMealID: UUID?) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let measurementsJSON = String(decoding: try encoder.encode(record), as: UTF8.self)
        let failureJSON = try record.failure.map {
            String(decoding: try encoder.encode($0), as: UTF8.self)
        }
        self.init(
            timestampMs: record.timestampMs,
            outcome: record.outcome.rawValue,
            failureJSON: failureJSON,
            measurementsJSON: measurementsJSON,
            mealID: record.mealID.flatMap(UUID.init(uuidString:)),
            modelVersion: record.modelVersion,
            benchmarkMealID: benchmarkMealID
        )
    }
}

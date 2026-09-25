import Foundation
import Persistence
import Segmentation
import SupportPlane
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
            case .noSupportPlaneWithoutDepth: caseName = "noSupportPlaneWithoutDepth"
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
    // Support-plane point counts. UNITS DEPEND ON `planeReference`: native depth
    // samples on a `foodSupport` row, colour-grid points on an `edgeBand` one —
    // ~56x apart, and never comparable across references
    // (`specs/estimation/support-plane-reference/` design, Stats semantics).
    public let planeCandidateCount: Int?
    public let planeInlierCount: Int?
    public let planeResidualMm: Float?
    // `specs/estimation/support-plane-reference/` Reqs 6.1–6.4. All optional with
    // no default: a pre-feature row must stay distinguishable from one this feature
    // wrote (Req 6.3), and a default would erase exactly that distinction. Stored
    // meals are left as recorded — no migration, no backfill (Decision 6).
    //
    // `foodSupport` / `edgeBand` — which surface the plane references (Req 4.4).
    public let planeReference: String?
    // Whole-ring median signed height above the plane: ~0 on a correct fit,
    // +18…+26 mm when the plane is the table (Req 6.2). Recorded on the fallback
    // path too, or that comparison has no "before".
    public let planeRingMedianMm: Float?
    // Inner/mid/outer band medians — the radial profile that identifies a
    // rim-borne ring after the fact (Decision 14).
    public let planeRingBandMediansMm: [Float]?
    // Candidate PLANES extracted by the restricted fit; absent on the fallback
    // path. Distinct from `planeCandidateCount`, which counts POINTS.
    public let planeCandidatePlaneCount: Int?
    // Req 6.4: a ring median of ~0 alone cannot distinguish a correct fit from a
    // ring that crossed the plate edge onto the table — both read ~0. The sector
    // count is what makes that check executable from the record alone.
    public let planeSupportingSectors: Int?
    public let foodRegionCoveragePercent: Float?
    public let segmentationNadir: SegmentationMeasurements?
    public let segmentationOblique: SegmentationMeasurements?
    public let volume: VolumeMeasurements?
    public let preShutterSegmentationErrorCount: Int?
    public let decomposition: [ClassDecomposition]?
    public let sigma: SigmaTerms?
    // Depth-grown food region (depth-grown-food-region Req 3–4): whether the
    // pass added pixels, the food-like count before and after, and what the
    // plane refit from the grown mask returned. nil when the pass did not run
    // (two-view path, or a refusal before volume).
    public let regionGrowth: RegionGrowthMeasurements?
    // Two-view poses (two-view-trust Req 1.1): the platform poses of both
    // frames, their tracking-session generations, and the transform (mm, §6.0
    // frame) the carve used, so a stored transform can be audited against the
    // photos offline. nil on single-view.
    public let twoViewPoses: TwoViewPoses?
    // two-view-trust Req 4.1/4.2/4.6: the rectangle taken as the ID-1 card
    // and what was done with it; nil when none passed `CardPoseSolver.pick`.
    public let card: CardMeasurements?
    // How many rectangles the detector offered, card or not.
    public let cardCandidateCount: Int?
    // two-view-trust Req 2.1: the carvable classes each view carried and the
    // one both were relabelled to before the carve; nil on single-view.
    public let twoViewReconciliation: TwoViewReconciliation?
    // The carve grid's vertical bound and the measurement behind it
    // (two-view-trust, 2026-09-25); nil on single-view. The carve cannot read
    // above `verticalExtentMm`, and at the tilts the aim guide allows nothing
    // else closes the hull from above, so this pair is what a two-view volume
    // has to be read against.
    public let voxelGrid: VoxelGridMeasurements?
    // Why this attempt's number must not be read as a measurement, as a
    // `DegradedReason` raw value; nil when nothing degraded it. Stored as a
    // string for the same reason `planeReference` is: a row written by a later
    // build must still decode here (two-view-trust Decision 8).
    public let degradedReason: String?

    // Reasons an attempt is recorded but its number is not a measurement
    // (two-view-trust Decision 8). One reason today; it is an enum so a second
    // one cannot be spelled two ways.
    public enum DegradedReason: String, Sendable {
        // Two-view carve with no depth in the nadir frame. Nothing bounds the
        // voxel grid's height: two silhouette cones close only above roughly
        // 74 degrees of tilt and the shutter arms between 10 and 40, so the
        // grid's constant extent sets the answer rather than the food does.
        // Measured 2026-09-25 against a synthetic control: 1.6x to 2.5x truth.
        case unboundedCarveHeight = "unbounded_carve_height"
    }

    public struct TwoViewPoses: Codable, Sendable, Equatable {
        public let nadirSessionGeneration: Int
        public let obliqueSessionGeneration: Int
        public let nadirWorldFromCamera: [Float]     // 16, column-major, metres (ARKit)
        public let obliqueWorldFromCamera: [Float]
        public let transform1To2Mm: [Float]          // 16, column-major, mm, §6.0 frame
        public init(nadirSessionGeneration: Int, obliqueSessionGeneration: Int,
                    nadirWorldFromCamera: [Float], obliqueWorldFromCamera: [Float],
                    transform1To2Mm: [Float]) {
            self.nadirSessionGeneration = nadirSessionGeneration
            self.obliqueSessionGeneration = obliqueSessionGeneration
            self.nadirWorldFromCamera = nadirWorldFromCamera
            self.obliqueWorldFromCamera = obliqueWorldFromCamera
            self.transform1To2Mm = transform1To2Mm
        }
    }

    public struct CardMeasurements: Codable, Sendable, Equatable {
        public let pnpResidualPx: Float
        public let distanceMm: Float
        public let scaleMmPerPx: Float
        // Symmetric disagreement against the LiDAR scale; nil without LiDAR.
        public let lidarDisagreement: Float?
        // Nadir pixels whose label changed to background under the card quad.
        public let clearedPixels: Int
        // Oblique pixels cleared under the card's projected quad; nil on single-view.
        public let obliqueClearedPixels: Int?
        // The card's nadir quad as eight image-pixel values, TL TR BR BL, so the
        // review can shade the reference rather than leave a hole in the outline
        // (two-view-trust Req 4.2).
        public let cornersImagePx: [Float]?

        public init(pnpResidualPx: Float, distanceMm: Float, scaleMmPerPx: Float,
                    lidarDisagreement: Float?, clearedPixels: Int, obliqueClearedPixels: Int? = nil,
                    cornersImagePx: [Float]? = nil) {
            self.pnpResidualPx = pnpResidualPx
            self.distanceMm = distanceMm
            self.scaleMmPerPx = scaleMmPerPx
            self.lidarDisagreement = lidarDisagreement
            self.clearedPixels = clearedPixels
            self.obliqueClearedPixels = obliqueClearedPixels
            self.cornersImagePx = cornersImagePx
        }
    }

    public struct RegionGrowthMeasurements: Codable, Sendable, Equatable {
        public let applied: Bool
        public let capTripped: Bool
        public let foodPixelsBefore: Int
        public let foodPixelsAfter: Int
        // Reference of the plane the refit returned; nil when the fitter
        // refused or growth added nothing. Only a `foodSupport` refit is
        // adopted for volume (depth-grown-food-region Decision 3); an
        // `edgeBand` value here means the first plane was kept.
        public let refitReference: String?
        public let refitRefused: Bool

        public init(applied: Bool, capTripped: Bool, foodPixelsBefore: Int,
                    foodPixelsAfter: Int, refitReference: String?, refitRefused: Bool) {
            self.applied = applied
            self.capTripped = capTripped
            self.foodPixelsBefore = foodPixelsBefore
            self.foodPixelsAfter = foodPixelsAfter
            self.refitReference = refitReference
            self.refitRefused = refitRefused
        }
    }

    public struct VoxelGridMeasurements: Codable, Sendable, Equatable {
        /// `VoxelGridSizer.heightPercentile` of the food's per-pixel height
        /// above the support plane in the nadir view, mm. nil when the nadir
        /// frame carried no depth or too few usable samples — the grid then
        /// kept the `verticalExtentMm` constant.
        public let measuredFoodHeightMm: Float?
        /// The grid's actual vertical extent, dimsZ whole voxels, mm.
        public let verticalExtentMm: Float
        public let dimsZ: Int
        public let edgeMm: Float

        public init(measuredFoodHeightMm: Float?, verticalExtentMm: Float,
                    dimsZ: Int, edgeMm: Float) {
            self.measuredFoodHeightMm = measuredFoodHeightMm
            self.verticalExtentMm = verticalExtentMm
            self.dimsZ = dimsZ
            self.edgeMm = edgeMm
        }
    }

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
                planeReference: String? = nil,
                planeRingMedianMm: Float? = nil,
                planeRingBandMediansMm: [Float]? = nil,
                planeCandidatePlaneCount: Int? = nil,
                planeSupportingSectors: Int? = nil,
                foodRegionCoveragePercent: Float? = nil,
                segmentationNadir: SegmentationMeasurements? = nil,
                segmentationOblique: SegmentationMeasurements? = nil,
                volume: VolumeMeasurements? = nil,
                preShutterSegmentationErrorCount: Int? = nil,
                decomposition: [ClassDecomposition]? = nil,
                sigma: SigmaTerms? = nil,
                regionGrowth: RegionGrowthMeasurements? = nil,
                twoViewPoses: TwoViewPoses? = nil,
                card: CardMeasurements? = nil,
                cardCandidateCount: Int? = nil,
                twoViewReconciliation: TwoViewReconciliation? = nil,
                voxelGrid: VoxelGridMeasurements? = nil,
                degradedReason: String? = nil) {
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
        self.planeReference = planeReference
        self.planeRingMedianMm = planeRingMedianMm
        self.planeRingBandMediansMm = planeRingBandMediansMm
        self.planeCandidatePlaneCount = planeCandidatePlaneCount
        self.planeSupportingSectors = planeSupportingSectors
        self.foodRegionCoveragePercent = foodRegionCoveragePercent
        self.segmentationNadir = segmentationNadir
        self.segmentationOblique = segmentationOblique
        self.volume = volume
        self.preShutterSegmentationErrorCount = preShutterSegmentationErrorCount
        self.decomposition = decomposition
        self.sigma = sigma
        self.regionGrowth = regionGrowth
        self.twoViewPoses = twoViewPoses
        self.card = card
        self.cardCandidateCount = cardCandidateCount
        self.twoViewReconciliation = twoViewReconciliation
        self.voxelGrid = voxelGrid
        self.degradedReason = degradedReason
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
            planeReference: planeReference,
            planeRingMedianMm: planeRingMedianMm,
            planeRingBandMediansMm: planeRingBandMediansMm,
            planeCandidatePlaneCount: planeCandidatePlaneCount,
            planeSupportingSectors: planeSupportingSectors,
            foodRegionCoveragePercent: foodRegionCoveragePercent,
            segmentationNadir: segmentationNadir,
            segmentationOblique: segmentationOblique,
            volume: volume,
            preShutterSegmentationErrorCount: count,
            decomposition: decomposition, sigma: sigma,
            regionGrowth: regionGrowth, twoViewPoses: twoViewPoses, card: card,
            cardCandidateCount: cardCandidateCount,
            twoViewReconciliation: twoViewReconciliation,
            voxelGrid: voxelGrid,
            degradedReason: degradedReason
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
    private var planeReference: String?
    private var planeRingMedianMm: Float?
    private var planeRingBandMediansMm: [Float]?
    private var planeCandidatePlaneCount: Int?
    private var planeSupportingSectors: Int?
    private var foodRegionCoveragePercent: Float?
    private var regionGrowth: EstimationAttemptRecord.RegionGrowthMeasurements?
    private var twoViewPoses: EstimationAttemptRecord.TwoViewPoses?
    private var card: EstimationAttemptRecord.CardMeasurements?
    private var cardCandidateCount: Int?
    private var twoViewReconciliation: TwoViewReconciliation?
    private var voxelGrid: EstimationAttemptRecord.VoxelGridMeasurements?
    private var degradedReason: String?
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

    // `reference`, `ring` and `candidatePlaneCount` arrive from the fit stats and
    // are recorded on BOTH the restricted and the fallback path
    // (`specs/estimation/support-plane-reference/` Reqs 6.1–6.4). They stay
    // optional the whole way down: the card-only path derives no depth plane, so
    // there is nothing to record and nothing to default.
    public func recordSupportPlane(candidateCount: Int, inlierCount: Int, residualMm: Float,
                                   reference: SupportPlaneReference? = nil,
                                   ring: RingStatistics? = nil,
                                   candidatePlaneCount: Int? = nil) {
        planeCandidateCount = candidateCount
        planeInlierCount = inlierCount
        planeResidualMm = residualMm
        planeReference = reference?.rawValue
        planeRingMedianMm = ring?.medianMm
        planeRingBandMediansMm = ring?.bandMedianMm
        planeSupportingSectors = ring?.supportingSectors
        planeCandidatePlaneCount = candidatePlaneCount
    }

    public func recordFoodRegionCoverage(percent: Float) {
        foodRegionCoveragePercent = percent
    }

    public func recordRegionGrowth(_ m: EstimationAttemptRecord.RegionGrowthMeasurements) {
        regionGrowth = m
    }

    public func recordTwoViewPoses(_ p: EstimationAttemptRecord.TwoViewPoses) {
        twoViewPoses = p
    }

    public func recordCard(_ c: EstimationAttemptRecord.CardMeasurements) {
        card = c
    }

    public func recordCardObliqueCleared(_ pixels: Int) {
        guard let c = card else { return }
        card = .init(pnpResidualPx: c.pnpResidualPx, distanceMm: c.distanceMm, scaleMmPerPx: c.scaleMmPerPx,
                     lidarDisagreement: c.lidarDisagreement, clearedPixels: c.clearedPixels,
                     obliqueClearedPixels: pixels)
    }

    public func recordCardCandidates(_ count: Int) {
        cardCandidateCount = count
    }

    public func recordTwoViewReconciliation(_ r: TwoViewReconciliation) {
        twoViewReconciliation = r
    }

    public func recordVoxelGrid(_ g: EstimationAttemptRecord.VoxelGridMeasurements) {
        voxelGrid = g
    }

    // Marks this attempt's number as something other than a measurement
    // (two-view-trust Decision 8). Recorded on refusals too: the reason is a
    // property of the capture, not of the outcome.
    public func recordDegraded(_ reason: EstimationAttemptRecord.DegradedReason) {
        degradedReason = reason.rawValue
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
            planeReference: planeReference,
            planeRingMedianMm: planeRingMedianMm,
            planeRingBandMediansMm: planeRingBandMediansMm,
            planeCandidatePlaneCount: planeCandidatePlaneCount,
            planeSupportingSectors: planeSupportingSectors,
            foodRegionCoveragePercent: foodRegionCoveragePercent,
            segmentationNadir: segmentationNadir,
            segmentationOblique: segmentationOblique,
            volume: volume,
            preShutterSegmentationErrorCount: nil,
            decomposition: decomposition,
            sigma: sigma,
            regionGrowth: regionGrowth,
            twoViewPoses: twoViewPoses,
            card: card,
            cardCandidateCount: cardCandidateCount,
            twoViewReconciliation: twoViewReconciliation,
            voxelGrid: voxelGrid,
            degradedReason: degradedReason
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

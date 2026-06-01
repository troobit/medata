import CardDetection
import CaptureKit
import Confidence
import Foods
import Foundation
import Macros
import MetricScale
#if DEBUG
import os
#endif
@_exported import Persistence
@_exported import PortableContracts
import Segmentation
import SupportPlane
import Volume

#if DEBUG
// Dev-build-only signposter per Req 16.5 / 16.7. Visible in Instruments → Points of Interest.
private let pipelineSignposter = OSSignposter(
    subsystem: "ie.medata.pipeline",
    category: "Stages"
)
#endif

// Orchestrator for pipeline stages C–L per design §2.2.
// Dependencies are injected at construction so the pipeline is fully testable.
public struct Pipeline: Sendable {
    private let cardDetector: any CardDetector
    private let segmenter: CoreMLSegmenter
    private let database: any FoodDatabase
    private let store: any PersistenceStore
    // Stamped onto every MealRecord this pipeline produces (Decision 42, Req §23.6):
    // "dev_stub" for Phase 1 device-MVP builds, "coreml_<modelVersion>" for Phase 3.
    // Internal (not private) so tests can verify the factory stamps the correct
    // value without running the full pipeline; production reads happen inside
    // Pipeline.estimate.
    let segmenterSource: String
    public weak var delegate: (any CaptureFlowDelegate)?

    public init(
        cardDetector: any CardDetector,
        segmenter: CoreMLSegmenter,
        database: any FoodDatabase,
        store: any PersistenceStore,
        segmenterSource: String = ""
    ) {
        self.cardDetector = cardDetector
        self.segmenter = segmenter
        self.database = database
        self.store = store
        self.segmenterSource = segmenterSource
    }

    // Main entry point per design §2.4.
    // `mode` is the user-selected CaptureMode from §2.3 / Decision 35; it drives
    // volume-estimator dispatch and is copied to MealRecord.capturePath.
    public func estimate(captureResult: CaptureResult, mode: CaptureMode) async throws -> MealRecord {
        let nadir = captureResult.nadirFrame
        let capturePath = mode.capturePath

        // Per-stage angular error at shutter-tap time (Decision 43/44). Nadir
        // targets 0° from vertical; oblique targets 25°. The values feed σ_tilt
        // in `Confidence.combine` further down. The oblique stage also enforces
        // the 30° hard cap (Decision 43): outside that envelope the visual hull
        // is unreliable enough that we refuse rather than report a degraded
        // estimate. The nadir gate is informational only — any angle is allowed.
        let deltaThetaNadirDeg = captureResult.nadirAngleAtCaptureDeg
        let deltaThetaObliqueDeg: Float?
        if let obliqueAngle = captureResult.obliqueAngleAtCaptureDeg, capturePath == .twoViewSfS {
            let delta = abs(obliqueAngle - 25)
            if delta > 30 {
                throw EstimationFailure.obliqueTiltOutOfRange
            }
            deltaThetaObliqueDeg = delta
        } else {
            deltaThetaObliqueDeg = nil
        }

        // ── Stage C: Card detection ──────────────────────────────────────────────
        #if DEBUG
        let cardInterval = pipelineSignposter.beginInterval("CardDetection")
        #endif
        let corners = await cardDetector.detect(in: nadir)
        let cardPose: CardPose?
        if let c = corners {
            do {
                cardPose = try CardPoseSolver.solve(corners: c, intrinsics: nadir.intrinsics)
            } catch CardPoseError.degenerateCardPose {
                #if DEBUG
                pipelineSignposter.endInterval("CardDetection", cardInterval)
                #endif
                throw EstimationFailure.degenerateCardPose
            } catch CardPoseError.cardTooOblique {
                #if DEBUG
                pipelineSignposter.endInterval("CardDetection", cardInterval)
                #endif
                throw EstimationFailure.cardTooOblique
            } catch {
                #if DEBUG
                pipelineSignposter.endInterval("CardDetection", cardInterval)
                #endif
                throw EstimationFailure.degenerateCardPose
            }
        } else {
            cardPose = nil
        }
        #if DEBUG
        pipelineSignposter.endInterval("CardDetection", cardInterval)
        #endif

        // ── Stage D: SupportPlane ────────────────────────────────────────────────
        #if DEBUG
        let planeInterval = pipelineSignposter.beginInterval("SupportPlane")
        #endif
        let plane: SupportPlane
        do {
            plane = try fitSupportPlane(
                nadir: nadir, cardPose: cardPose, corners: corners
            )
        } catch {
            #if DEBUG
            pipelineSignposter.endInterval("SupportPlane", planeInterval)
            #endif
            throw error
        }
        #if DEBUG
        pipelineSignposter.endInterval("SupportPlane", planeInterval)
        #endif

        // ── Stage E: MetricScale ─────────────────────────────────────────────────
        #if DEBUG
        let scaleInterval = pipelineSignposter.beginInterval("MetricScale")
        #endif
        let lidarMmPerPx: Float?
        if nadir.depth != nil {
            let fMean = (nadir.intrinsics.fx + nadir.intrinsics.fy) / 2
            lidarMmPerPx = abs(plane.distanceMm) / fMean
        } else {
            lidarMmPerPx = nil
        }
        let scale: MetricScale
        do {
            scale = try MetricScaleResolver.resolve(
                cardScaleMmPerPx: cardPose?.scaleAtCardPlaneMmPerPx,
                lidarScaleMmPerPx: lidarMmPerPx
            )
        } catch MetricScaleError.noScaleAvailable {
            #if DEBUG
            pipelineSignposter.endInterval("MetricScale", scaleInterval)
            #endif
            throw EstimationFailure.noScaleAvailable
        }
        #if DEBUG
        pipelineSignposter.endInterval("MetricScale", scaleInterval)
        #endif

        // ── Stage F: Segmentation ────────────────────────────────────────────────
        #if DEBUG
        let segInterval = pipelineSignposter.beginInterval("Segmentation")
        #endif
        let nadirSeg: SegmentationResult
        do {
            nadirSeg = try await segmenter.segment(nadir)
        } catch SegmentationError.noFoodPixels {
            #if DEBUG
            pipelineSignposter.endInterval("Segmentation", segInterval)
            #endif
            throw EstimationFailure.noFoodPixels
        }
        #if DEBUG
        pipelineSignposter.endInterval("Segmentation", segInterval)
        #endif
        let palette = nadirSeg.probabilities.palette

        // β-correction table from database at current edition.
        let beta = buildBeta(palette: palette, edition: captureResult.databaseEdition)

        // ── Stages G/H/I: Volume ─────────────────────────────────────────────────
        #if DEBUG
        let volumeInterval = pipelineSignposter.beginInterval("Volume")
        #endif
        let pbVolumes: PbVolumeResult
        let interClassOcclusion: Bool
        var viewCoverage: ViewCoverage

        switch capturePath {
        case .singleViewLidar:
            guard let depth = nadir.depth else {
                #if DEBUG
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.lidarUnavailableMidCapture
            }
            do {
                let est = try HeightFieldEstimator.integrate(HeightFieldEstimator.Inputs(
                    probabilities: nadirSeg.probabilities,
                    argmax: nadirSeg.argmax,
                    depth: depth,
                    intrinsics: nadir.intrinsics,
                    supportPlane: plane,
                    beta: beta,
                    palette: palette
                ))
                pbVolumes = PipelineBridges.pbVolumeResult(singleView: est)
                interClassOcclusion = est.interClassOcclusionDetected
                if interClassOcclusion {
                    delegate?.didDetectInterClassOcclusion()
                }
                let minCov = est.lidarCoverageFraction.values.min() ?? 1
                // Three-tier σ_view lookup for single-view per Decision 47.
                // ≥0.80 → singleViewFull (0.90), 0.50–0.80 → singleViewPartial (0.60),
                // 0.30–0.50 → singleViewMinimal (0.30). Below 0.30 the height-field
                // integrator refuses (see HeightFieldEstimator.coverageRefuseFraction).
                if minCov >= 0.80 {
                    viewCoverage = .singleViewFull
                } else if minCov >= 0.50 {
                    viewCoverage = .singleViewPartial
                } else {
                    viewCoverage = .singleViewMinimal
                }
            } catch VolumeError.lidarCoverageTooLow(let classes) {
                #if DEBUG
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.lidarCoverageTooLow(classes)
            } catch VolumeError.noFoodVolumeRecovered {
                #if DEBUG
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.noFoodVolumeRecovered
            }

        case .twoViewSfS:
            guard let oblique = captureResult.obliqueFrame else {
                #if DEBUG
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.arWorldTrackingLost
            }
            let obliqueSeg: SegmentationResult
            do {
                obliqueSeg = try await segmenter.segment(oblique)
            } catch SegmentationError.noFoodPixels {
                #if DEBUG
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.noFoodPixels
            }
            let matching = MaskMatcher.match(
                view1: nadirSeg.argmax,
                view2: obliqueSeg.argmax,
                palette: palette
            )
            let t1to2 = PipelineBridges.transform1To2(nadir: nadir, oblique: oblique)
            let foodMask = PipelineBridges.foodMask(from: nadirSeg.argmax, palette: palette)
            let grid: VoxelGrid
            do {
                grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
                    foodMask: foodMask,
                    nadirIntrinsics: nadir.intrinsics,
                    supportPlane: plane,
                    gravityCamera: nadir.gravity
                ))
            } catch {
                #if DEBUG
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.noFoodVolumeRecovered
            }
            do {
                let est = try VoxelCarveEstimator.carve(VoxelCarveEstimator.Inputs(
                    grid: grid,
                    view1: VoxelCarveView(probabilities: nadirSeg.probabilities,
                                         intrinsics: nadir.intrinsics),
                    view2: VoxelCarveView(probabilities: obliqueSeg.probabilities,
                                         intrinsics: oblique.intrinsics),
                    transform1To2: t1to2,
                    supportPlane: plane,
                    matchedClasses: matching.matchedClasses,
                    singleViewOnlyClassesView1: matching.singleViewOnly(view: 1),
                    singleViewOnlyClassesView2: matching.singleViewOnly(view: 2),
                    beta: beta,
                    palette: palette
                ))
                pbVolumes = PipelineBridges.pbVolumeResult(twoView: est)
                interClassOcclusion = false
                viewCoverage = matching.singleViewOnlyClasses.isEmpty ? .twoViewFull : .twoViewPartial
            } catch VolumeError.noFoodVolumeRecovered {
                #if DEBUG
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.noFoodVolumeRecovered
            }
        }
        #if DEBUG
        pipelineSignposter.endInterval("Volume", volumeInterval)
        #endif

        // ── Stage J: Macros ──────────────────────────────────────────────────────
        #if DEBUG
        let macrosInterval = pipelineSignposter.beginInterval("Macros")
        #endif
        let macros = Macros.compute(
            perClassVolumesCm3: pbVolumes.perClassVolumesCm3,
            database: database,
            edition: captureResult.databaseEdition
        )
        #if DEBUG
        pipelineSignposter.endInterval("Macros", macrosInterval)
        #endif

        // ── Stage K: Confidence ──────────────────────────────────────────────────
        #if DEBUG
        let confidenceInterval = pipelineSignposter.beginInterval("Confidence")
        #endif
        let confidence = Confidence.combine(
            sigmaScale: scale.sigmaScale,
            sigmaSeg: nadirSeg.sigmaSeg,
            planeFitResidualMm: plane.residualMm,
            viewCoverage: viewCoverage,
            capturePath: captureResult.capturePath,
            interClassOcclusionDetected: interClassOcclusion,
            cardOnlyPath: nadir.depth == nil,
            cardOnlyIterations: plane.convergedIterations ?? 0,
            deltaThetaNadirDeg: deltaThetaNadirDeg,
            deltaThetaObliqueDeg: deltaThetaObliqueDeg
        )
        #if DEBUG
        pipelineSignposter.endInterval("Confidence", confidenceInterval)
        #endif

        // ── Assemble MealRecord ──────────────────────────────────────────────────
        let perClassCalib: [String: PbBetaCalibrationStatus] = macros.perClass
            .mapValues { PipelineBridges.pbBetaStatus($0.betaStatus) }

        let record = MealRecord(
            capturePath: capturePath,
            databaseEdition: captureResult.databaseEdition,
            paletteVersion: captureResult.paletteVersion,
            segmenterSource: segmenterSource,
            calibration: nadir.intrinsics.pb,
            supportPlane: PipelineBridges.pbSupportPlane(plane),
            scale: PipelineBridges.pbMetricScale(scale),
            volumes: pbVolumes,
            macros: PipelineBridges.pbMacroResult(macros),
            confidence: PipelineBridges.pbConfidenceResult(confidence),
            perClassCalibration: perClassCalib
        )

        // ── Stage L: Persistence ─────────────────────────────────────────────────
        #if DEBUG
        let persistenceInterval = pipelineSignposter.beginInterval("Persistence")
        #endif
        try await store.save(record, artefacts: [])
        #if DEBUG
        pipelineSignposter.endInterval("Persistence", persistenceInterval)
        #endif

        delegate?.didProduceEstimate(record)

        return record
    }

    // MARK: - Private helpers

    private func fitSupportPlane(
        nadir: RawFrame,
        cardPose: CardPose?,
        corners: [PixelCorner]?
    ) throws -> SupportPlane {
        // LiDAR plane fit takes precedence when depth is available.
        if let depth = nadir.depth {
            let roughMask = BinaryMask(
                pixels: [UInt8](repeating: 1, count: nadir.imageWidth * nadir.imageHeight),
                width: nadir.imageWidth,
                height: nadir.imageHeight
            )
            do {
                return try LiDARPlaneFitter.fit(LiDARPlaneFitter.Inputs(
                    depth: depth,
                    colourIntrinsics: nadir.intrinsics,
                    foodRegionMask: roughMask,
                    gravityCamera: nadir.gravity
                ))
            } catch SupportPlaneError.lidarFitDegenerate {
                throw EstimationFailure.lidarFitDegenerate
            } catch SupportPlaneError.lidarFitResidualTooHigh {
                throw EstimationFailure.lidarFitResidualTooHigh
            } catch {
                throw EstimationFailure.lidarFitDegenerate
            }
        }

        // Card-only path: back-project lower card corners as lower-silhouette edge
        // points (approximation; full Canny-edge extraction is a future enhancement).
        guard let pose = cardPose, let c = corners, c.count >= 4 else {
            throw EstimationFailure.noScaleAvailable
        }
        let k = nadir.intrinsics
        let dCard = abs(pose.translationMm.z)
        let s0 = pose.scaleAtCardPlaneMmPerPx
        let lowerEdges: [Vec3] = c.suffix(2).map { corner in
            Vec3((corner.u - k.cx) * s0, (corner.v - k.cy) * s0, -dCard)
        }
        let centroid = Vec3(pose.translationMm.x, pose.translationMm.y + 20, pose.translationMm.z)
        do {
            return try CardOnlyPlaneFitter.fit(CardOnlyPlaneFitter.Inputs(
                cardCentreDepthMm: dCard,
                scaleAtCardPlaneInitMmPerPx: s0,
                gravityCamera: nadir.gravity,
                edgePoints3DAtInitScale: lowerEdges,
                foodCentroids3DAtInitScale: [centroid]
            ))
        } catch SupportPlaneError.iterationDiverged {
            throw EstimationFailure.iterationDiverged
        } catch SupportPlaneError.noLowerSilhouetteEdges {
            throw EstimationFailure.iterationDiverged
        } catch {
            throw EstimationFailure.iterationDiverged
        }
    }

    private func buildBeta(palette: ClassPalette, edition: String) -> BetaCorrection {
        var entries: [String: Float] = [:]
        for className in palette.foodClasses {
            if let entry = database.entry(for: className, edition: edition) {
                entries[className] = entry.beta
            }
        }
        return BetaCorrection(entries: entries)
    }
}

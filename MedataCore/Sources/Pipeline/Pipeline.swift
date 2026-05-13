import CardDetection
import CaptureKit
import Confidence
import Foods
import Foundation
import Macros
import MetricScale
import Persistence
import PortableContracts
import Segmentation
import SupportPlane
import Volume

// Orchestrator for pipeline stages C–L per design §2.2.
// Dependencies are injected at construction so the pipeline is fully testable.
public struct Pipeline: Sendable {
    private let cardDetector: any CardDetector
    private let segmenter: CoreMLSegmenter
    private let database: any FoodDatabase
    private let store: any PersistenceStore
    public weak var delegate: (any CaptureFlowDelegate)?

    public init(
        cardDetector: any CardDetector,
        segmenter: CoreMLSegmenter,
        database: any FoodDatabase,
        store: any PersistenceStore
    ) {
        self.cardDetector = cardDetector
        self.segmenter = segmenter
        self.database = database
        self.store = store
    }

    // Main entry point per design §2.4.
    public func estimate(captureResult: CaptureResult) async throws -> MealRecord {
        let nadir = captureResult.nadirFrame

        // ── Stage C: Card detection ──────────────────────────────────────────────
        let corners = await cardDetector.detect(in: nadir)
        let cardPose: CardPose?
        if let c = corners {
            do {
                cardPose = try CardPoseSolver.solve(corners: c, intrinsics: nadir.intrinsics)
            } catch CardPoseError.degenerateCardPose {
                throw EstimationFailure.degenerateCardPose
            } catch CardPoseError.cardTooOblique {
                throw EstimationFailure.cardTooOblique
            } catch {
                throw EstimationFailure.degenerateCardPose
            }
        } else {
            cardPose = nil
        }

        // ── Stage D: SupportPlane ────────────────────────────────────────────────
        let plane = try fitSupportPlane(
            nadir: nadir, cardPose: cardPose, corners: corners
        )

        // ── Stage E: MetricScale ─────────────────────────────────────────────────
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
            throw EstimationFailure.noScaleAvailable
        }

        // ── Stage F: Segmentation ────────────────────────────────────────────────
        let nadirSeg: SegmentationResult
        do {
            nadirSeg = try await segmenter.segment(nadir)
        } catch SegmentationError.noFoodPixels {
            throw EstimationFailure.noFoodPixels
        }
        let palette = nadirSeg.probabilities.palette

        // β-correction table from database at current edition.
        let beta = buildBeta(palette: palette, edition: captureResult.databaseEdition)

        // ── Stages G/H/I: Volume ─────────────────────────────────────────────────
        let pbVolumes: PbVolumeResult
        let interClassOcclusion: Bool
        var viewCoverage: ViewCoverage

        switch captureResult.capturePath {
        case .singleViewLidar:
            guard let depth = nadir.depth else {
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
                viewCoverage = minCov >= 0.80 ? .singleViewFull : .singleViewPartial
            } catch VolumeError.lidarCoverageTooLow(let classes) {
                throw EstimationFailure.lidarCoverageTooLow(classes)
            } catch VolumeError.noFoodVolumeRecovered {
                throw EstimationFailure.noFoodVolumeRecovered
            }

        case .twoViewSfS:
            guard let oblique = captureResult.obliqueFrame else {
                throw EstimationFailure.arWorldTrackingLost
            }
            let obliqueSeg: SegmentationResult
            do {
                obliqueSeg = try await segmenter.segment(oblique)
            } catch SegmentationError.noFoodPixels {
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
                throw EstimationFailure.noFoodVolumeRecovered
            }
        }

        // ── Stage J: Macros ──────────────────────────────────────────────────────
        let macros = Macros.compute(
            perClassVolumesCm3: pbVolumes.perClassVolumesCm3,
            database: database,
            edition: captureResult.databaseEdition
        )

        // ── Stage K: Confidence ──────────────────────────────────────────────────
        let confidence = Confidence.combine(
            sigmaScale: scale.sigmaScale,
            sigmaSeg: nadirSeg.sigmaSeg,
            planeFitResidualMm: plane.residualMm,
            viewCoverage: viewCoverage,
            capturePath: captureResult.capturePath,
            interClassOcclusionDetected: interClassOcclusion,
            cardOnlyPath: nadir.depth == nil,
            cardOnlyIterations: plane.convergedIterations ?? 0
        )

        // ── Assemble MealRecord ──────────────────────────────────────────────────
        let perClassCalib: [String: PbBetaCalibrationStatus] = macros.perClass
            .mapValues { PipelineBridges.pbBetaStatus($0.betaStatus) }

        let record = MealRecord(
            capturePath: captureResult.capturePath,
            databaseEdition: captureResult.databaseEdition,
            paletteVersion: captureResult.paletteVersion,
            calibration: nadir.intrinsics.pb,
            supportPlane: PipelineBridges.pbSupportPlane(plane),
            scale: PipelineBridges.pbMetricScale(scale),
            volumes: pbVolumes,
            macros: PipelineBridges.pbMacroResult(macros),
            confidence: PipelineBridges.pbConfidenceResult(confidence),
            perClassCalibration: perClassCalib
        )

        // ── Stage L: Persistence ─────────────────────────────────────────────────
        try await store.save(record, artefacts: [])

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

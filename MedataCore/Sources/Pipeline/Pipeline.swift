import CardDetection
import CaptureKit
import Confidence
import Foods
import Foundation
import Macros
import MetricScale
import os
@_exported import Persistence
@_exported import PortableContracts
// Re-export so App-target callers (PreShutterSegmenter, CaptureFlowModel) can
// construct CoreMLSegmenter and refer to BinaryMask / ClassPalette without
// adding extra package products. Keeps the App's package dependency surface a
// single `MedataCore` import.
@_exported import Segmentation
@_exported import SupportPlane
import Volume

#if DEBUG
// Dev-build-only signposter per Req 16.5 / 16.7. Visible in Instruments → Points of Interest.
private let pipelineSignposter = OSSignposter(
    subsystem: "ie.medata.pipeline",
    category: "Stages"
)

// Per-stage start log. Shares the `ie.medata.app` / `Shutter` channel; emitted
// at every pipeline-stage entry so a Console.app trail identifies the stage in
// progress when estimate.end never fires (i.e., the pipeline hangs inside one
// stage). The next stage's start line implies the previous stage finished — no
// separate end line is emitted to keep the trail compact.
private let pipelineStageLog = Logger(subsystem: "ie.medata.app", category: "Shutter")
#endif

// Structured-log channel for the support-plane fit. Shares the `ie.medata.app`
// / `Shutter` channel with the `estimate.start` / `estimate.end` events, so a
// single Console predicate captures the full shutter→result trail. Emitted in
// Release too — the `supportplane.end success=false` trace is the only
// on-device window into a `lidarFitDegenerate` failure without a Debug build.
private let supportPlaneLog = Logger(subsystem: "ie.medata.app", category: "Shutter")

// Orchestrator for pipeline stages C–L per design §2.2.
// Dependencies are injected at construction so the pipeline is fully testable.
public struct Pipeline: Sendable {
    private let cardDetector: any CardDetector
    private let segmenter: CoreMLSegmenter
    private let database: any FoodDatabase
    private let store: any PersistenceStore
    private let supportPlaneFitter: any SupportPlaneFitter
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
        supportPlaneFitter: any SupportPlaneFitter = LiDARSupportPlaneFitter(),
        segmenterSource: String = ""
    ) {
        self.cardDetector = cardDetector
        self.segmenter = segmenter
        self.database = database
        self.store = store
        self.supportPlaneFitter = supportPlaneFitter
        self.segmenterSource = segmenterSource
    }

    // Main entry point per design §2.4.
    // `mode` is the user-selected CaptureMode from §2.3 / Decision 35; it drives
    // volume-estimator dispatch and is copied to MealRecord.capturePath.
    //
    // Outcome recording (snaq-parity lane A): every non-cancelled attempt —
    // success, typed refusal, or non-typed error — stamps its outcome into the
    // diagnostics accumulator and hands exactly one immutable snapshot to
    // `CaptureFlowDelegate.didCompleteAttempt`. Cancellation is not an outcome:
    // a user-abandoned capture produces no record so benchmark completion
    // rates are not depressed by abandonment.
    public func estimate(captureResult: CaptureResult, mode: CaptureMode) async throws -> MealRecord {
        let diagnostics = PipelineDiagnostics(
            capturePath: mode.capturePath.rawValue,
            modelVersion: segmenterSource,
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000)
        )
        do {
            let record = try await runEstimation(
                captureResult: captureResult, mode: mode, diagnostics: diagnostics
            )
            delegate?.didCompleteAttempt(diagnostics.snapshot())
            return record
        } catch let error where error is CancellationError {
            throw error
        } catch let failure as EstimationFailure {
            diagnostics.stampFailure(failure)
            delegate?.didCompleteAttempt(diagnostics.snapshot())
            throw failure
        } catch {
            // Non-typed error: the underlying description is preserved in the
            // record, in Release builds too (Req 3.3).
            diagnostics.stampError(error)
            delegate?.didCompleteAttempt(diagnostics.snapshot())
            throw error
        }
    }

    // The pipeline body proper: stages C–L. Stage helpers append measurements
    // to `diagnostics` as they run; the success outcome is stamped here (the
    // per-class decomposition needs the macros/confidence values), failures are
    // stamped by `estimate`'s catch ladder.
    private func runEstimation(
        captureResult: CaptureResult, mode: CaptureMode, diagnostics: PipelineDiagnostics
    ) async throws -> MealRecord {
        let nadir = captureResult.nadirFrame
        let capturePath = mode.capturePath
        diagnostics.recordTilt(
            nadirDeg: captureResult.nadirAngleAtCaptureDeg,
            obliqueDeg: captureResult.obliqueAngleAtCaptureDeg
        )
        #if DEBUG
        // estimate.start augmented with maskAgeMs (Req 4.5 erratum / Decision 15).
        let maskAgeMs = captureResult.preShutterMaskAgeMs ?? -1
        supportPlaneLog.info(
            "event=estimate.start maskAgeMs=\(maskAgeMs, privacy: .public)"
        )
        #endif

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
        pipelineStageLog.info("event=pipeline.stage.start name=CardDetection")
        let cardStartedAt = ContinuousClock.now
        let cardInterval = pipelineSignposter.beginInterval("CardDetection")
        #endif
        let corners = await cardDetector.detect(in: nadir)
        let cardPose: CardPose?
        if let c = corners {
            do {
                cardPose = try CardPoseSolver.solve(corners: c, intrinsics: nadir.intrinsics)
            } catch CardPoseError.degenerateCardPose where nadir.depth != nil {
                // LiDAR-first fallback (Decision 1): a degenerate card read does
                // not abort the estimate when LiDAR depth is present — LiDAR
                // supplies both scale and support plane. Continue with cardPose
                // absent; the post-block logStageEnd fires the single stage-end.
                // The fallback flag is recorded in Release too (Req 3.2).
                diagnostics.recordCardFallback()
                #if DEBUG
                supportPlaneLog.info("event=scale.card_fallback reason=degenerateCardPose")
                #endif
                cardPose = nil
            } catch CardPoseError.cardTooOblique where nadir.depth != nil {
                // LiDAR-first fallback (Decision 1): same as above for an oblique
                // card. Continue on the LiDAR-only path.
                diagnostics.recordCardFallback()
                #if DEBUG
                supportPlaneLog.info("event=scale.card_fallback reason=cardTooOblique")
                #endif
                cardPose = nil
            } catch CardPoseError.degenerateCardPose {
                #if DEBUG
                logStageEnd(name: "CardDetection", startedAt: cardStartedAt)
                pipelineSignposter.endInterval("CardDetection", cardInterval)
                #endif
                throw EstimationFailure.degenerateCardPose
            } catch CardPoseError.cardTooOblique {
                #if DEBUG
                logStageEnd(name: "CardDetection", startedAt: cardStartedAt)
                pipelineSignposter.endInterval("CardDetection", cardInterval)
                #endif
                throw EstimationFailure.cardTooOblique
            } catch {
                // Generic (unexpected) card-solve errors stay fail-closed
                // (Decision 2): refuse regardless of LiDAR depth so unknown
                // failures stay surfaced rather than masked behind a LiDAR fit.
                #if DEBUG
                logStageEnd(name: "CardDetection", startedAt: cardStartedAt)
                pipelineSignposter.endInterval("CardDetection", cardInterval)
                #endif
                throw EstimationFailure.degenerateCardPose
            }
        } else {
            cardPose = nil
        }
        #if DEBUG
        logStageEnd(name: "CardDetection", startedAt: cardStartedAt)
        pipelineSignposter.endInterval("CardDetection", cardInterval)
        #endif

        // ── Stage D: SupportPlane ────────────────────────────────────────────────
        #if DEBUG
        pipelineStageLog.info("event=pipeline.stage.start name=SupportPlane")
        let planeStartedAt = ContinuousClock.now
        let planeInterval = pipelineSignposter.beginInterval("SupportPlane")
        #endif
        let plane: SupportPlane
        do {
            plane = try fitSupportPlane(
                nadir: nadir,
                cardPose: cardPose,
                corners: corners,
                preShutterFoodMask: captureResult.preShutterFoodMask,
                diagnostics: diagnostics
            )
        } catch {
            #if DEBUG
            logStageEnd(name: "SupportPlane", startedAt: planeStartedAt)
            pipelineSignposter.endInterval("SupportPlane", planeInterval)
            #endif
            throw error
        }
        #if DEBUG
        logStageEnd(name: "SupportPlane", startedAt: planeStartedAt)
        pipelineSignposter.endInterval("SupportPlane", planeInterval)
        #endif

        // Coverage recompute per Decision 14 / Req 4.1: compute the real
        // `foodRegionCoveragePercent` against the pre-shutter mask + depth
        // confidence buffer. The value is logged at estimate.end (Decision 15)
        // but does NOT drive path selection in v1 (Decision 1).
        let foodRegionCoveragePercent = computeFoodRegionCoverage(
            depth: nadir.depth,
            confidenceThreshold: 0.66,
            mask: captureResult.preShutterFoodMask,
            colourWidth: nadir.imageWidth,
            colourHeight: nadir.imageHeight
        )
        diagnostics.recordFoodRegionCoverage(percent: foodRegionCoveragePercent)

        // ── Stage E: MetricScale ─────────────────────────────────────────────────
        #if DEBUG
        pipelineStageLog.info("event=pipeline.stage.start name=MetricScale")
        let scaleStartedAt = ContinuousClock.now
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
            logStageEnd(name: "MetricScale", startedAt: scaleStartedAt)
            pipelineSignposter.endInterval("MetricScale", scaleInterval)
            #endif
            throw EstimationFailure.noScaleAvailable
        }
        diagnostics.recordScale(source: Self.scaleSourceLabel(scale), cardFallback: false)
        #if DEBUG
        logStageEnd(name: "MetricScale", startedAt: scaleStartedAt)
        pipelineSignposter.endInterval("MetricScale", scaleInterval)
        #endif

        // ── Stage F: Segmentation ────────────────────────────────────────────────
        #if DEBUG
        pipelineStageLog.info("event=pipeline.stage.start name=Segmentation width=\(nadir.imageWidth, privacy: .public) height=\(nadir.imageHeight, privacy: .public)")
        let segStartedAt = ContinuousClock.now
        let segInterval = pipelineSignposter.beginInterval("Segmentation")
        #endif
        let nadirSeg: SegmentationResult
        do {
            nadirSeg = try await segmenter.segment(nadir)
        } catch SegmentationError.noFoodPixels {
            #if DEBUG
            logStageEnd(name: "Segmentation", startedAt: segStartedAt)
            pipelineSignposter.endInterval("Segmentation", segInterval)
            #endif
            throw EstimationFailure.noFoodPixels
        }
        #if DEBUG
        logStageEnd(name: "Segmentation", startedAt: segStartedAt)
        pipelineSignposter.endInterval("Segmentation", segInterval)
        #endif
        diagnostics.recordSegmentation(view: .nadir, measurements: Self.segmentationMeasurements(nadirSeg))
        let palette = nadirSeg.probabilities.palette

        // Fail-closed near-empty-mask gate (estimation-runtime-consistency):
        // refuse before Volume/β when food coverage is below the stated minimum,
        // so a speckle-only mask surfaces as a consistent `noFoodPixels` refusal
        // rather than a wildly variable carb number. Guards both capture paths —
        // the nadir mask is the primary silhouette for each.
        try enforceMinimumFoodCoverage(argmax: nadirSeg.argmax, palette: palette)

        // β-correction table from database at current edition.
        let beta = buildBeta(palette: palette, edition: captureResult.databaseEdition)

        // ── Stages G/H/I: Volume ─────────────────────────────────────────────────
        #if DEBUG
        pipelineStageLog.info("event=pipeline.stage.start name=Volume capturePath=\(capturePath.rawValue, privacy: .public)")
        let volumeStartedAt = ContinuousClock.now
        let volumeInterval = pipelineSignposter.beginInterval("Volume")
        #endif
        let pbVolumes: PbVolumeResult
        let interClassOcclusion: Bool
        var viewCoverage: ViewCoverage

        switch capturePath {
        case .singleViewLidar:
            guard let depth = nadir.depth else {
                #if DEBUG
                logStageEnd(name: "Volume", startedAt: volumeStartedAt)
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.lidarUnavailableMidCapture
            }
            let outcome = HeightFieldEstimator.integrate(HeightFieldEstimator.Inputs(
                probabilities: nadirSeg.probabilities,
                argmax: nadirSeg.argmax,
                depth: depth,
                intrinsics: nadir.intrinsics,
                supportPlane: plane,
                beta: beta,
                palette: palette
            ))
            // Stats stamped BEFORE the refusal is mapped to a throw, so the
            // "no volume" record carries its causal measurements (Req 3.1).
            diagnostics.recordVolume(stats: outcome.stats)
            guard let est = outcome.estimate else {
                #if DEBUG
                logStageEnd(name: "Volume", startedAt: volumeStartedAt)
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw Self.estimationFailure(fromVolumeRefusal: outcome.refusal)
            }
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

        case .twoViewSfS:
            guard let oblique = captureResult.obliqueFrame else {
                #if DEBUG
                logStageEnd(name: "Volume", startedAt: volumeStartedAt)
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.arWorldTrackingLost
            }
            let obliqueSeg: SegmentationResult
            do {
                obliqueSeg = try await segmenter.segment(oblique)
            } catch SegmentationError.noFoodPixels {
                #if DEBUG
                logStageEnd(name: "Volume", startedAt: volumeStartedAt)
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.noFoodPixels
            }
            diagnostics.recordSegmentation(view: .oblique, measurements: Self.segmentationMeasurements(obliqueSeg))
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
                logStageEnd(name: "Volume", startedAt: volumeStartedAt)
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.noFoodVolumeRecovered
            }
            let outcome = VoxelCarveEstimator.carve(VoxelCarveEstimator.Inputs(
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
            // Stats stamped BEFORE the refusal is mapped to a throw (Req 3.1).
            diagnostics.recordVolume(stats: outcome.stats)
            guard let est = outcome.estimate else {
                #if DEBUG
                logStageEnd(name: "Volume", startedAt: volumeStartedAt)
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw Self.estimationFailure(fromVolumeRefusal: outcome.refusal)
            }
            pbVolumes = PipelineBridges.pbVolumeResult(twoView: est)
            interClassOcclusion = false
            viewCoverage = matching.singleViewOnlyClasses.isEmpty ? .twoViewFull : .twoViewPartial
        }
        #if DEBUG
        logStageEnd(name: "Volume", startedAt: volumeStartedAt)
        pipelineSignposter.endInterval("Volume", volumeInterval)
        #endif

        // ── Stage J: Macros ──────────────────────────────────────────────────────
        #if DEBUG
        pipelineStageLog.info("event=pipeline.stage.start name=Macros")
        let macrosStartedAt = ContinuousClock.now
        let macrosInterval = pipelineSignposter.beginInterval("Macros")
        #endif
        let macros = Macros.compute(
            perClassVolumesCm3: pbVolumes.perClassVolumesCm3,
            database: database,
            edition: captureResult.databaseEdition,
            liquidClassIds: Set(palette.liquidClasses)
        )
        #if DEBUG
        logStageEnd(name: "Macros", startedAt: macrosStartedAt)
        pipelineSignposter.endInterval("Macros", macrosInterval)
        #endif

        // ── Stage K: Confidence ──────────────────────────────────────────────────
        #if DEBUG
        pipelineStageLog.info("event=pipeline.stage.start name=Confidence")
        let confidenceStartedAt = ContinuousClock.now
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
        logStageEnd(name: "Confidence", startedAt: confidenceStartedAt)
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
        pipelineStageLog.info("event=pipeline.stage.start name=Persistence")
        let persistenceStartedAt = ContinuousClock.now
        let persistenceInterval = pipelineSignposter.beginInterval("Persistence")
        #endif
        do {
            try await store.save(record, artefacts: [])
        } catch {
            #if DEBUG
            logStageEnd(name: "Persistence", startedAt: persistenceStartedAt)
            pipelineSignposter.endInterval("Persistence", persistenceInterval)
            #endif
            throw error
        }
        // Storage-only (Decision 15): persist the segmentation label raster as an
        // 8-bit greyscale PNG of raw class indices for the mask-overlay surfaces.
        // Failure is logged and swallowed inside persistMask — never fails the
        // meal save, which has already committed above.
        await MaskArtefactWriter.persistMask(
            argmax: nadirSeg.argmax, mealId: record.id, store: store
        )
        #if DEBUG
        logStageEnd(name: "Persistence", startedAt: persistenceStartedAt)
        pipelineSignposter.endInterval("Persistence", persistenceInterval)
        #endif

        // Success outcome: per-class decomposition (Req 3.4) + σ terms, copied
        // into the record so a later deleteMeal cannot hollow the attribution.
        let decomposition = macros.perClass
            .map { name, perClass in
                EstimationAttemptRecord.ClassDecomposition(
                    className: name,
                    volumeCm3: perClass.volumeCm3,
                    massG: perClass.massG,
                    carbsG: perClass.carbsG,
                    beta: perClass.betaUsed,
                    densitySource: perClass.densitySource,
                    coefficientSource: perClass.coefficientSource
                )
            }
            .sorted { $0.className < $1.className }
        diagnostics.stampSuccess(
            mealID: record.id.uuidString,
            decomposition: decomposition,
            sigma: EstimationAttemptRecord.SigmaTerms(
                sigmaMeal: confidence.sigmaMeal,
                sigmaScale: confidence.sigmaScale,
                sigmaSeg: confidence.sigmaSeg,
                sigmaPlane: confidence.sigmaGeom.sigmaPlane,
                sigmaView: confidence.sigmaGeom.sigmaView,
                sigmaTilt: confidence.sigmaGeom.sigmaTilt
            )
        )

        delegate?.didProduceEstimate(record)

        #if DEBUG
        // estimate.end augmented with foodRegionCoveragePercent (Decision 15 /
        // Req 4.5 erratum). Logged here at success-exit; the failure branches
        // above throw before reaching this point.
        supportPlaneLog.info(
            "event=estimate.end success=true foodRegionCoveragePercent=\(foodRegionCoveragePercent, privacy: .public)"
        )
        #endif
        return record
    }

    // MARK: - Private helpers

    #if DEBUG
    // Emits the paired `pipeline.stage.end` line for a stage whose `stage.start`
    // already fired. `latencyMs` is integer milliseconds accrued from the
    // `ContinuousClock` instant captured at the stage's entry — on both the
    // success path and every refusal/early-return path, so each `stage.start`
    // has exactly one matching `stage.end`. Same `pipelineStageLog` channel and
    // `#if DEBUG` gating as the start lines.
    private func logStageEnd(name: String, startedAt: ContinuousClock.Instant) {
        let latencyMs = Int((ContinuousClock.now - startedAt) / .milliseconds(1))
        pipelineStageLog.info(
            "event=pipeline.stage.end name=\(name, privacy: .public) latencyMs=\(latencyMs, privacy: .public)"
        )
    }
    #endif

    // Thin wrapper that delegates to the injected `SupportPlaneFitter` and
    // maps the protocol's `SupportPlaneError` cases to the pipeline-level
    // `EstimationFailure` cases used by the rest of `estimate(_:)`. The empty-
    // mask gate (Decision 2) lives inside the fitter so the card-only path
    // also refuses with `noFoodPixels` when the pre-shutter mask is absent.
    // Fit stats arrive as returned values on both exits (snaq-parity Req 3.1;
    // previously the `LiDARPlaneFitter.debugLast*` statics) and are recorded
    // into the diagnostics accumulator before any throw.
    private func fitSupportPlane(
        nadir: RawFrame,
        cardPose: CardPose?,
        corners: [PixelCorner]?,
        preShutterFoodMask: BinaryMask?,
        diagnostics: PipelineDiagnostics
    ) throws -> SupportPlane {
        #if DEBUG
        supportPlaneLog.info(
            """
            event=supportplane.start width=\(nadir.imageWidth, privacy: .public) \
            height=\(nadir.imageHeight, privacy: .public) source=pre_shutter
            """
        )
        #endif
        let outcome = supportPlaneFitter.fitOutcome(
            nadir: nadir,
            cardPose: cardPose,
            corners: corners,
            preShutterFoodMask: preShutterFoodMask
        )
        let stats = outcome.stats
        diagnostics.recordSupportPlane(
            candidateCount: stats.candidatePointCount,
            inlierCount: stats.inlierCount,
            residualMm: stats.residualMm
        )
        if let plane = outcome.plane {
            #if DEBUG
            supportPlaneLog.info(
                """
                event=supportplane.end success=true \
                residual_mm=\(plane.residualMm, privacy: .public)
                """
            )
            #endif
            return plane
        }
        let error = outcome.refusal ?? .noLidarPoints
        // Failure-path trace. `failure=` carries the EXACT SupportPlaneError
        // case so `noLidarPoints` (scan starved → remapped below to
        // lidarFitDegenerate) is distinguishable from a genuine
        // collinear-inlier `lidarFitDegenerate`. The candidate/inlier counts
        // and food bbox come from the fit outcome's stats. Emitted in
        // Release too — this is the only on-device window into a
        // `lidarFitDegenerate` failure without a Debug/stub build.
        // Bug `lidar-plane-fit-degenerate-on-clean-capture`.
        supportPlaneLog.info(
            """
            event=supportplane.end success=false \
            failure=\(Self.supportPlaneFailureLabel(error), privacy: .public) \
            candidates=\(stats.candidatePointCount, privacy: .public) \
            inliers=\(stats.inlierCount, privacy: .public) \
            residual_mm=\(stats.residualMm, privacy: .public) \
            bboxX=\(stats.foodBBoxX, privacy: .public) \
            bboxY=\(stats.foodBBoxY, privacy: .public) \
            bboxW=\(stats.foodBBoxW, privacy: .public) \
            bboxH=\(stats.foodBBoxH, privacy: .public)
            """
        )
        switch error {
        case .emptyFoodMask:
            throw EstimationFailure.noFoodPixels
        case .lidarFitDegenerate:
            throw EstimationFailure.lidarFitDegenerate
        case .lidarFitResidualTooHigh:
            throw EstimationFailure.lidarFitResidualTooHigh
        case .noLidarPoints:
            // Pre-existing card-only fallback when LiDAR cannot produce a fit
            // and a card pose is unavailable; otherwise the fitter raises
            // `noLowerSilhouetteEdges` which we map to `noScaleAvailable`.
            throw EstimationFailure.lidarFitDegenerate
        case .noLowerSilhouetteEdges:
            throw EstimationFailure.noScaleAvailable
        case .iterationDiverged:
            throw EstimationFailure.iterationDiverged
        }
    }

    // Resolved-scale label for the outcome record (Req 3.1: "the resolved
    // scale source").
    private static func scaleSourceLabel(_ scale: MetricScale) -> String {
        switch (scale.cardScaleAvailable, scale.lidarScaleAvailable) {
        case (true, true): return "card+lidar"
        case (false, true): return "lidar"
        case (true, false): return "card"
        case (false, false): return "none"
        }
    }

    // Per-view segmentation measurements for the outcome record: coverage plus
    // the sub-stage clocks from CoreMLSegmenter (Req 4.1).
    private static func segmentationMeasurements(
        _ seg: SegmentationResult
    ) -> EstimationAttemptRecord.SegmentationMeasurements {
        EstimationAttemptRecord.SegmentationMeasurements(
            foodCoveragePercent: seg.foodCoveragePercent,
            preprocessMs: seg.timings?.preprocessMs ?? 0,
            predictionMs: seg.timings?.predictionMs ?? 0,
            argmaxMs: seg.timings?.argmaxMs ?? 0
        )
    }

    // Maps a volume-stage refusal to the pipeline-level failure. The two typed
    // refusals keep their pre-existing EstimationFailure mapping; any other
    // VolumeError propagates unchanged (matching the previous uncaught-throw
    // behaviour). `nil` cannot occur when `estimate` is nil per the
    // VolumeOutcome contract; noFoodVolumeRecovered is the conservative
    // fallback if it ever does.
    private static func estimationFailure(fromVolumeRefusal refusal: VolumeError?) -> any Error {
        switch refusal {
        case .lidarCoverageTooLow(let classes):
            return EstimationFailure.lidarCoverageTooLow(classes)
        case .noFoodVolumeRecovered, nil:
            return EstimationFailure.noFoodVolumeRecovered
        case .some(let other):
            return other
        }
    }

    // Stable kebab-ish label for the SupportPlaneError case, used by the
    // `supportplane.end success=false` trace above.
    private static func supportPlaneFailureLabel(_ error: SupportPlaneError) -> String {
        switch error {
        case .lidarFitResidualTooHigh: return "lidarFitResidualTooHigh"
        case .lidarFitDegenerate: return "lidarFitDegenerate"
        case .noLowerSilhouetteEdges: return "noLowerSilhouetteEdges"
        case .iterationDiverged: return "iterationDiverged"
        case .noLidarPoints: return "noLidarPoints"
        case .emptyFoodMask: return "emptyFoodMask"
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

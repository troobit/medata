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
    // Depth-grown food region constants (depth-grown-food-region Decision 2);
    // `.disabled` reproduces the ungrown single-view estimate.
    private let regionGrowth: FoodRegionGrowthConfig

    // Hard cap on |oblique tilt − 25°| (Decision 43). Beyond it the visual
    // hull is unreliable enough to refuse rather than report a degraded
    // estimate. Configurable only so the field build can measure what a
    // wider band buys (two-view-trust Decision 8); the default is the
    // shipped value and nothing in a product build changes it.
    public static let defaultObliqueTiltCapDeg: Float = 30
    private let obliqueTiltCapDeg: Float
    // Stamped onto every MealRecord this pipeline produces (Decision 42, Req §23.6):
    // "dev_stub" for Phase 1 device-MVP builds, "coreml_<modelVersion>" for Phase 3.
    // Public so the App layer can stamp the same lineage tag onto the slim
    // capture-stage refusal records that never reach the pipeline (snaq-parity
    // lane A) and tests can verify the factory stamps the correct value.
    public let segmenterSource: String
    public weak var delegate: (any CaptureFlowDelegate)?
    // Developer-phase capture recorder (capture-bundle-recorder smolspec).
    // Injected at construction — unlike `delegate` it needs no post-init
    // stamping dance in CaptureFlowModel. nil (harness, tests) records nothing.
    private let bundleRecorder: CaptureBundleRecorder?

    public init(
        cardDetector: any CardDetector,
        segmenter: CoreMLSegmenter,
        database: any FoodDatabase,
        store: any PersistenceStore,
        supportPlaneFitter: any SupportPlaneFitter = LiDARSupportPlaneFitter(),
        segmenterSource: String = "",
        bundleRecorder: CaptureBundleRecorder? = nil,
        regionGrowth: FoodRegionGrowthConfig = .standard,
        obliqueTiltCapDeg: Float = Self.defaultObliqueTiltCapDeg
    ) {
        self.cardDetector = cardDetector
        self.segmenter = segmenter
        self.database = database
        self.store = store
        self.supportPlaneFitter = supportPlaneFitter
        self.segmenterSource = segmenterSource
        self.bundleRecorder = bundleRecorder
        self.regionGrowth = regionGrowth
        self.obliqueTiltCapDeg = obliqueTiltCapDeg
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
        let timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
        let diagnostics = PipelineDiagnostics(
            capturePath: mode.capturePath.rawValue,
            modelVersion: segmenterSource,
            timestampMs: timestampMs
        )
        do {
            let record = try await runEstimation(
                captureResult: captureResult, mode: mode, diagnostics: diagnostics
            )
            delegate?.didCompleteAttempt(diagnostics.snapshot())
            recordBundle(captureResult: captureResult, diagnostics: diagnostics,
                         timestampMs: timestampMs, outcome: .success)
            return record
        } catch let error where error is CancellationError {
            // No attempt record and no bundle: user abandonment is not an outcome.
            throw error
        } catch let failure as EstimationFailure {
            diagnostics.stampFailure(failure)
            delegate?.didCompleteAttempt(diagnostics.snapshot())
            recordBundle(captureResult: captureResult, diagnostics: diagnostics,
                         timestampMs: timestampMs, outcome: .refused)
            throw failure
        } catch {
            // Non-typed error: the underlying description is preserved in the
            // record, in Release builds too (Req 3.3).
            diagnostics.stampError(error)
            delegate?.didCompleteAttempt(diagnostics.snapshot())
            recordBundle(captureResult: captureResult, diagnostics: diagnostics,
                         timestampMs: timestampMs, outcome: .refused)
            throw error
        }
    }

    // Write-behind hand-off to the capture-bundle recorder. The Sendable
    // payload is extracted HERE — the non-Sendable diagnostics accumulator
    // must not cross into the task. The unstructured Task decouples the
    // bundle encode (~200 MB at camera resolution) from the estimation task,
    // so a flow cancelled after the result returns cannot abandon the write;
    // the actor serialises concurrent recordings.
    private func recordBundle(
        captureResult: CaptureResult,
        diagnostics: PipelineDiagnostics,
        timestampMs: Int64,
        outcome: EstimationAttemptRecord.Outcome
    ) {
        guard let bundleRecorder else { return }
        let payload = CaptureBundleRecorder.Payload(
            captureResult: captureResult,
            nadirSegmentation: diagnostics.debugNadirSegmentation,
            obliqueSegmentation: diagnostics.debugObliqueSegmentation,
            segmenterVersion: segmenter.modelVersion ?? segmenterSource,
            timestampMs: timestampMs,
            outcome: outcome.rawValue
        )
        Task { await bundleRecorder.record(payload) }
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
        // two-view-trust Decision 8: with no depth in the nadir frame nothing
        // bounds the carve's height. Two silhouette cones close only above
        // roughly 74 degrees of tilt on a plate-sized object and the shutter
        // arms between 10 and 40, so the grid's constant vertical extent sets
        // the answer — measured at 1.6x to 2.5x truth on a synthetic control.
        // The volume is therefore not a measurement and must not be read as a
        // dosing number. Stamped here, before any stage can refuse, so a
        // refused row carries the same fact about the capture that a
        // successful one does; the review screen derives it from the persisted
        // record (`MealRecord.carveHeightWasUnbounded`).
        if capturePath == .twoViewSfS, nadir.depth == nil {
            diagnostics.recordDegraded(.unboundedCarveHeight)
            supportPlaneLog.info(
                "event=estimate.degraded reason=\(EstimationAttemptRecord.DegradedReason.unboundedCarveHeight.rawValue, privacy: .public)"
            )
        }
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
            if delta > obliqueTiltCapDeg {
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
        // Every ranked rectangle is a candidate (two-view-trust Decision 3).
        // With LiDAR the pick waits for stage E, where the LiDAR scale can
        // arbitrate; without it the card is the only scale and must be
        // chosen now, and a candidate that cannot solve refuses as before.
        let candidates = await cardDetector.detect(in: nadir)
        diagnostics.recordCardCandidates(candidates.count)
        var corners: [PixelCorner]?
        var cardPose: CardPose?
        if nadir.depth == nil, !candidates.isEmpty {
            do {
                if let card = try CardPoseSolver.pick(candidates: candidates, intrinsics: nadir.intrinsics) {
                    (corners, cardPose) = card
                }
            } catch CardPoseError.cardTooOblique {
                #if DEBUG
                logStageEnd(name: "CardDetection", startedAt: cardStartedAt)
                pipelineSignposter.endInterval("CardDetection", cardInterval)
                #endif
                throw EstimationFailure.cardTooOblique
            } catch {
                // degenerateCardPose and any unexpected solve error stay
                // fail-closed (Decision 2).
                #if DEBUG
                logStageEnd(name: "CardDetection", startedAt: cardStartedAt)
                pipelineSignposter.endInterval("CardDetection", cardInterval)
                #endif
                throw EstimationFailure.degenerateCardPose
            }
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
        var plane: SupportPlane
        var planeReference: SupportPlaneReference?
        var planeRingMedianMm: Float?
        do {
            (plane, planeReference, planeRingMedianMm) = try fitSupportPlane(
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
        if let lidarMmPerPx, !candidates.isEmpty {
            // LiDAR-first (Decision 1): a candidate set that cannot solve is
            // a fallback, not a refusal, and the LiDAR scale arbitrates
            // between the rectangles that do solve.
            do {
                if let card = try CardPoseSolver.pick(
                    candidates: candidates, intrinsics: nadir.intrinsics, lidarMmPerPx: lidarMmPerPx) {
                    (corners, cardPose) = card
                }
            } catch {
                diagnostics.recordCardFallback()
                supportPlaneLog.info("event=scale.card_fallback reason=\(String(describing: error), privacy: .public)")
            }
        }
        var scale: MetricScale
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
        let segmented: SegmentationResult
        do {
            segmented = try await segmenter.segment(nadir)
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
        diagnostics.recordSegmentation(view: .nadir, measurements: Self.segmentationMeasurements(segmented))
        // The bundle keeps the segmenter's own output; the card exclusion below
        // is a pipeline step the harness replays, not a segmenter property.
        diagnostics.debugNadirSegmentation = segmented
        // An accepted card is cleared to background before anything measures
        // the nadir (two-view-trust Req 4.6): an out-of-palette object the
        // segmenter calls food, whose extent the pose solve already fixed.
        var nadirSeg = segmented
        var clearedPixels = 0
        if let cardPose, let corners {
            (nadirSeg, clearedPixels) = segmented.excluding(quad: corners.map { SIMD2($0.u, $0.v) })
            let disagreement = lidarMmPerPx.map { CardPoseSolver.disagreement(cardPose.scaleAtCardPlaneMmPerPx, $0) }
            diagnostics.recordCard(.init(
                pnpResidualPx: cardPose.pnpResidualPx, distanceMm: cardPose.translationMm.z.magnitude,
                scaleMmPerPx: cardPose.scaleAtCardPlaneMmPerPx, lidarDisagreement: disagreement,
                clearedPixels: clearedPixels,
                cornersImagePx: corners.flatMap { [$0.u, $0.v] }))
        }
        supportPlaneLog.info("event=card candidates=\(candidates.count, privacy: .public) picked=\(cardPose != nil, privacy: .public) clearedPixels=\(clearedPixels, privacy: .public)")
        let palette = nadirSeg.probabilities.palette

        // Fail-closed gate on the nadir argmax, guarding both capture paths —
        // the nadir mask is the primary silhouette for each. A near-empty
        // food-like mask surfaces as `noFoodPixels`
        // (estimation-runtime-consistency), so a speckle-only mask refuses
        // legibly rather than emitting a wildly variable carb number.
        // `unknown_food` counts as food-like here: an unnamed region is
        // carried through as a row the user names in review
        // (unknown-food-nameable Req 1), not refused.
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
        // The label map the volume stage measured and the review outline
        // shows: the depth-grown map on the single-view path when growth
        // applied, the segmenter's own otherwise. The capture bundle always
        // keeps `nadirSeg.argmax` (depth-grown-food-region Req 6).
        var measuredArgmax = nadirSeg.argmax

        switch capturePath {
        case .singleViewLidar:
            guard let depth = nadir.depth else {
                #if DEBUG
                logStageEnd(name: "Volume", startedAt: volumeStartedAt)
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.lidarUnavailableMidCapture
            }
            // One connected object with unknown patches or a split name is
            // one row (two-view-trust Req 2.1). The bundle keeps the raw map.
            let reconciled = ObjectReconciler.reconcile(nadir: nadirSeg, palette: palette, userClass: nil)
            Self.logReconciliation(reconciled.reconciliation, diagnostics: diagnostics)
            let nadirSeg = reconciled.nadir
            measuredArgmax = nadirSeg.argmax
            // Depth-grown food region (depth-grown-food-region Req 1–4): grow
            // the segmenter's food-like regions into the raised slab around
            // them, then refit the plane from the grown mask so the contact
            // ring sits on the plate rather than on the food. A refused refit
            // keeps the first plane; a tripped cap keeps the segmenter's map.
            // The support surface sits at the ring median above an edge-band
            // (table) plane and at the plane itself on a foodSupport fit.
            let growth = refitPlaneFromGrownRegion(
                nadir: nadir, depth: depth, argmax: nadirSeg.argmax,
                cardPose: cardPose, corners: corners,
                plane: &plane, planeReference: &planeReference,
                planeRingMedianMm: planeRingMedianMm, scale: &scale, palette: palette,
                planeOnly: false, diagnostics: diagnostics)
            if growth.applied { measuredArgmax = growth.argmax }
            let outcome = HeightFieldEstimator.integrate(HeightFieldEstimator.Inputs(
                probabilities: nadirSeg.probabilities,
                argmax: measuredArgmax,
                depth: depth,
                intrinsics: nadir.intrinsics,
                supportPlane: plane,
                beta: beta,
                palette: palette,
                grownRegion: growth.grownRegion
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
            pbVolumes = PipelineBridges.pbVolumeResult(
                singleView: est,
                preBetaVolumesCm3: outcome.stats.perClassVolumesPreBetaCm3
            )
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
            // Two-view geometry audit (two-view-trust Req 1.1): the poses that
            // relate the views are only comparable within one tracking-session
            // run. Record both poses and the transform the carve will use, and
            // refuse a pair that straddles a session reset — its transform
            // would relate two different world origins.
            let t1to2 = PipelineBridges.transform1To2(nadir: nadir, oblique: oblique)
            diagnostics.recordTwoViewPoses(.init(
                nadirSessionGeneration: nadir.sessionGeneration,
                obliqueSessionGeneration: oblique.sessionGeneration,
                nadirWorldFromCamera: nadir.worldFromCamera.flatColumnMajor(),
                obliqueWorldFromCamera: oblique.worldFromCamera.flatColumnMajor(),
                transform1To2Mm: t1to2.flatColumnMajor()))
            supportPlaneLog.info(
                """
                event=two_view.poses nadirGen=\(nadir.sessionGeneration, privacy: .public) \
                obliqueGen=\(oblique.sessionGeneration, privacy: .public) \
                t_mm=\(t1to2.columns[3][0], privacy: .public),\(t1to2.columns[3][1], privacy: .public),\(t1to2.columns[3][2], privacy: .public)
                """
            )
            guard nadir.sessionGeneration == oblique.sessionGeneration else {
                #if DEBUG
                logStageEnd(name: "Volume", startedAt: volumeStartedAt)
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.arWorldTrackingLost
            }
            let rawObliqueSeg: SegmentationResult
            do {
                rawObliqueSeg = try await segmenter.segment(oblique)
            } catch SegmentationError.noFoodPixels {
                #if DEBUG
                logStageEnd(name: "Volume", startedAt: volumeStartedAt)
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.noFoodPixels
            }
            diagnostics.recordSegmentation(view: .oblique, measurements: Self.segmentationMeasurements(rawObliqueSeg))
            diagnostics.debugObliqueSegmentation = rawObliqueSeg
            // The picked card is cleared from the oblique too (Req 4.6, oblique
            // half): its 3-D corners go through the verified transform and the
            // oblique intrinsics, and the quad is cleared as in the nadir.
            var obliqueSeg = rawObliqueSeg
            if let cardPose {
                let quad = PipelineBridges.projectToOblique(
                    cardPose.cornersCameraMm, transform1To2: t1to2, intrinsics: oblique.intrinsics)
                let cleared: Int
                (obliqueSeg, cleared) = rawObliqueSeg.excluding(quad: quad)
                diagnostics.recordCardObliqueCleared(cleared)
                supportPlaneLog.info(
                    "event=card view=oblique clearedPixels=\(cleared, privacy: .public) quad=\(quad.map { [$0.x, $0.y] }, privacy: .public)")
            }
            // Both views relabelled to one carvable class so the carve has a
            // matched class with both silhouettes (two-view-trust Req 2.1).
            // The bundle keeps the raw segmenter outputs assigned above.
            let reconciled = ObjectReconciler.reconcile(
                nadir: nadirSeg, oblique: obliqueSeg, palette: palette, userClass: nil)
            Self.logReconciliation(reconciled.reconciliation, diagnostics: diagnostics)
            let nadirSeg = reconciled.nadir
            obliqueSeg = reconciled.oblique
            // The review outline is drawn from this map and matched to the
            // rows by class. Without this line it stays the segmenter's own
            // labels while the rows carry the reconciled class, and a nadir
            // that saw only `unknown_food` draws nothing at all against a
            // `bread_wholemeal` row (2026-09-25 outcomes 7845FF40, BB05A08C).
            measuredArgmax = nadirSeg.argmax
            // Plane refit from the grown region, plane only (two-view-trust
            // Decision 10): the same grow → refit → prune → adopt sequence
            // as the single-view branch decides the plane the carve floors on
            // and measures height from, because a first plane sitting on the
            // table hands the carve a slab of hull under the food. The grown
            // map goes no further — the carve silhouette, the review outline
            // and the persisted mask stay the segmenter's own.
            if let depth = nadir.depth {
                _ = refitPlaneFromGrownRegion(
                    nadir: nadir, depth: depth, argmax: nadirSeg.argmax,
                    cardPose: cardPose, corners: corners,
                    plane: &plane, planeReference: &planeReference,
                    planeRingMedianMm: planeRingMedianMm, scale: &scale, palette: palette,
                    planeOnly: true, diagnostics: diagnostics)
            }
            let matching = MaskMatcher.match(
                view1: nadirSeg.argmax,
                view2: obliqueSeg.argmax,
                palette: palette
            )
            let foodMask = PipelineBridges.foodMask(from: nadirSeg.argmax, palette: palette)
            // The grid's height is the food's height when the nadir frame can
            // measure it (two-view-trust, 2026-09-25). Two silhouettes at the
            // tilts the aim guide allows do not close the hull from above, so
            // the vertical extent is not a safety cap — it sets the answer.
            // Without depth this is nil and the 120 mm constant stands.
            let measuredFoodHeightMm = nadir.depth.flatMap {
                VoxelGridSizer.measuredFoodHeightMm(
                    foodMask: foodMask, depth: $0,
                    intrinsics: nadir.intrinsics, supportPlane: plane)
            }
            // Without depth the class height cap is the extent; with depth it
            // is a ceiling the measured extent cannot exceed and never a
            // floor (two-view-trust Decision 11). The class is the reconciled
            // nadir map's; several classes take the tallest cap. Where no
            // height is measured the cap scales with the silhouette's
            // footprint on the plane for a class whose forms scale with it
            // (Decision 12); a measurement keeps Decision 11's ceiling.
            let footprintMm2 = VoxelGridSizer.silhouetteFootprintMm2(
                foodMask: foodMask, intrinsics: nadir.intrinsics, supportPlane: plane)
            let classCap = ClassHeightPriors.bundled?.carveCap(
                forNadirArgmax: nadirSeg.argmax, palette: palette,
                footprintMm2: footprintMm2, heightMeasured: measuredFoodHeightMm != nil)
            let bound = VoxelGridSizer.verticalBound(
                measuredFoodHeightMm: measuredFoodHeightMm, classCap: classCap)
            let grid: VoxelGrid
            do {
                grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
                    foodMask: foodMask,
                    nadirIntrinsics: nadir.intrinsics,
                    supportPlane: plane,
                    gravityCamera: nadir.gravity,
                    measuredFoodHeightMm: measuredFoodHeightMm,
                    classCap: classCap
                ))
            } catch {
                #if DEBUG
                logStageEnd(name: "Volume", startedAt: volumeStartedAt)
                pipelineSignposter.endInterval("Volume", volumeInterval)
                #endif
                throw EstimationFailure.noFoodVolumeRecovered
            }
            diagnostics.recordVoxelGrid(.init(
                measuredFoodHeightMm: measuredFoodHeightMm,
                verticalExtentMm: grid.verticalExtentMm,
                dimsZ: grid.dimsZ, edgeMm: grid.edgeMm,
                classCapMm: classCap?.mm, capSource: bound.source.rawValue,
                footprintMm2: footprintMm2))
            // Release-emitted channel: what bounded the carve on this attempt.
            supportPlaneLog.info(
                """
                event=grid.height measured_mm=\(measuredFoodHeightMm ?? -1, privacy: .public) \
                extent_mm=\(grid.verticalExtentMm, privacy: .public) \
                dimsZ=\(grid.dimsZ, privacy: .public) edge_mm=\(grid.edgeMm, privacy: .public) \
                cap_mm=\(classCap?.mm ?? -1, privacy: .public) \
                cap_source=\(bound.source.rawValue, privacy: .public) \
                footprint_mm2=\(footprintMm2, privacy: .public)
                """
            )
            let outcome = VoxelCarveEstimator.carve(VoxelCarveEstimator.Inputs(
                grid: grid,
                view1: VoxelCarveView(probabilities: nadirSeg.probabilities,
                                     intrinsics: nadir.intrinsics,
                                     argmax: nadirSeg.argmax),
                view2: VoxelCarveView(probabilities: obliqueSeg.probabilities,
                                     intrinsics: oblique.intrinsics,
                                     argmax: obliqueSeg.argmax),
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
            pbVolumes = PipelineBridges.pbVolumeResult(
                twoView: est,
                preBetaVolumesCm3: outcome.stats.perClassVolumesPreBetaCm3
            )
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
            deltaThetaObliqueDeg: deltaThetaObliqueDeg,
            supportPlaneFallback: planeReference == .edgeBand
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
            perClassCalibration: perClassCalib,
            candidateEvidence: PipelineBridges.pbCandidateEvidence(
                nadirSeg.candidateEvidence ?? [:]
            ),
            // The marker records that the evidence pass RAN, not that anything
            // qualified (Decision 4) — that is what keeps the Req 8.2 partition
            // a property of the code path rather than of plate content.
            candidateEvidenceProduced: nadirSeg.candidateEvidence != nil
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
            argmax: measuredArgmax, mealId: record.id, store: store
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
    // Returns the reference alongside the plane: the confidence stage needs it for
    // the Req 4.6 fallback penalty, and it is not recoverable from the plane
    // itself (`specs/estimation/support-plane-reference/`).
    private func fitSupportPlane(
        nadir: RawFrame,
        cardPose: CardPose?,
        corners: [PixelCorner]?,
        preShutterFoodMask: BinaryMask?,
        diagnostics: PipelineDiagnostics
    ) throws -> (plane: SupportPlane, reference: SupportPlaneReference?, ringMedianMm: Float?) {
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
            residualMm: stats.residualMm,
            reference: stats.reference,
            ring: stats.ring,
            candidatePlaneCount: stats.candidatePlaneCount
        )
        if let plane = outcome.plane {
            #if DEBUG
            supportPlaneLog.info(
                """
                event=supportplane.end success=true \
                residual_mm=\(plane.residualMm, privacy: .public) \
                reference=\(stats.reference?.rawValue ?? "none", privacy: .public) \
                ring_median_mm=\(stats.ring?.medianMm ?? .nan, privacy: .public) \
                supporting_sectors=\(stats.ring?.supportingSectors ?? -1, privacy: .public)
                """
            )
            #endif
            return (plane, stats.reference, stats.ring?.medianMm)
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
            // `noLowerSilhouetteEdges`, mapped just below.
            throw EstimationFailure.lidarFitDegenerate
        case .noLowerSilhouetteEdges:
            // Since 9f02ff2 the card-only branch of the fitter refuses with
            // this whenever there is no depth (two-view-trust Req 4.4), and on
            // such a capture the card usually resolves scale perfectly well —
            // it is the PLANE that is missing. `noScaleAvailable` sent every
            // reader of the row or the log to the wrong stage (task 13).
            throw EstimationFailure.noSupportPlaneWithoutDepth
        case .iterationDiverged:
            throw EstimationFailure.iterationDiverged
        }
    }

    // Resolved-scale label for the outcome record (Req 3.1: "the resolved
    // scale source").
    // depth-grown-food-region: the support surface's height above the fitted
    // plane. An edge-band plane is the table and the fitter's ring median is
    // the plate top above it; a foodSupport plane is the support surface.
    static func supportOffsetMm(reference: SupportPlaneReference?, ringMedianMm: Float?) -> Float {
        guard reference == .edgeBand, let median = ringMedianMm, median.isFinite, median > 0 else { return 0 }
        return median
    }

    // Grow → refit → prune → adopt (`GrownRegionPlaneRefit`), then the
    // pipeline's own consequences of an adopted plane: the diagnostics row,
    // the LiDAR scale, and the Release-emitted `event=region.grow` line. Both
    // volume branches run this; only the single-view one integrates over the
    // returned map (two-view-trust Decision 10, `planeOnly`).
    private func refitPlaneFromGrownRegion(
        nadir: RawFrame,
        depth: DepthMap,
        argmax: ArgmaxMap,
        cardPose: CardPose?,
        corners: [PixelCorner]?,
        plane: inout SupportPlane,
        planeReference: inout SupportPlaneReference?,
        planeRingMedianMm: Float?,
        scale: inout MetricScale,
        palette: ClassPalette,
        planeOnly: Bool,
        diagnostics: PipelineDiagnostics
    ) -> FoodRegionGrowthResult {
        let outcome = GrownRegionPlaneRefit.refit(
            argmax: argmax, depth: depth, intrinsics: nadir.intrinsics,
            supportPlane: plane, supportReference: planeReference,
            supportOffsetMm: Self.supportOffsetMm(reference: planeReference, ringMedianMm: planeRingMedianMm),
            palette: palette, config: regionGrowth
        ) { mask in
            supportPlaneFitter.fitOutcome(
                nadir: nadir, cardPose: cardPose, corners: corners, preShutterFoodMask: mask)
        }
        if let stats = outcome.adoptedStats {
            plane = outcome.plane
            planeReference = outcome.reference
            diagnostics.recordSupportPlane(
                candidateCount: stats.candidatePointCount,
                inlierCount: stats.inlierCount,
                residualMm: stats.residualMm,
                reference: stats.reference,
                ring: stats.ring,
                candidatePlaneCount: stats.candidatePlaneCount)
            // The LiDAR scale is the plane distance over the focal length
            // (stage E); it follows the plane the volume uses.
            let fMean = (nadir.intrinsics.fx + nadir.intrinsics.fy) / 2
            if let rescaled = try? MetricScaleResolver.resolve(
                cardScaleMmPerPx: cardPose?.scaleAtCardPlaneMmPerPx,
                lidarScaleMmPerPx: abs(plane.distanceMm) / fMean) {
                scale = rescaled
            }
        }
        let growth = outcome.growth
        diagnostics.recordRegionGrowth(.init(
            applied: growth.applied, capTripped: growth.capTripped,
            foodPixelsBefore: growth.foodPixelsBefore, foodPixelsAfter: growth.foodPixelsAfter,
            refitReference: outcome.refitReference?.rawValue, refitRefused: outcome.refitRefused,
            planeOnly: planeOnly))
        let refitLabel = outcome.refitReference?.rawValue ?? (outcome.refitRefused ? "refused" : "none")
        let residualMm = plane.residualMm
        // On the Release-emitted channel (pipelineStageLog is Debug-only):
        // this line is the on-device window into what growth did.
        supportPlaneLog.info(
            """
            event=region.grow applied=\(growth.applied, privacy: .public) \
            capTripped=\(growth.capTripped, privacy: .public) \
            before=\(growth.foodPixelsBefore, privacy: .public) \
            after=\(growth.foodPixelsAfter, privacy: .public) \
            refit=\(refitLabel, privacy: .public) \
            planeOnly=\(planeOnly, privacy: .public) \
            residual_mm=\(residualMm, privacy: .public)
            """
        )
        return growth
    }

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
            preprocessMs: seg.timings?.preprocessMs,
            predictionMs: seg.timings?.predictionMs,
            argmaxMs: seg.timings?.argmaxMs
        )
    }

    // Maps a volume-stage refusal to the pipeline-level failure. The two typed
    // refusals keep their pre-existing EstimationFailure mapping; any other
    // VolumeError propagates unchanged (matching the previous uncaught-throw
    // behaviour). `nil` cannot occur when `estimate` is nil per the
    // VolumeOutcome contract; noFoodVolumeRecovered is the conservative
    // fallback if it ever does.
    private static func logReconciliation(_ r: TwoViewReconciliation, diagnostics: PipelineDiagnostics) {
        diagnostics.recordTwoViewReconciliation(r)
        supportPlaneLog.info(
            """
            event=object.reconcile applied=\(r.applied, privacy: .public) \
            nadir=\(r.nadirClasses, privacy: .public) \
            nadirSingle=\(r.nadirSingleObject, privacy: .public) \
            oblique=\(String(describing: r.obliqueClasses), privacy: .public) \
            obliqueSingle=\(String(describing: r.obliqueSingleObject), privacy: .public) \
            chosen=\(String(describing: r.chosenClass), privacy: .public)
            """
        )
    }

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
        // Shared with the review path's relabel re-derivation (meal-review
        // Decision 8's impact clause) so both apply the same β table.
        Macros.betaCorrection(for: palette.foodClasses, database: database, edition: edition)
    }
}

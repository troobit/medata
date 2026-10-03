#if HARNESS_ENABLED
import CaptureKit
import CardDetection
import CardDetectionVision
import CoreGraphics
import Foods
import Foundation
import ImageIO
import Macros
import Pipeline
import PortableContracts
import Segmentation
import SupportPlane
import Volume

// Converts a PbMealFixture into a MealCalibrationInput by running the pipeline
// stages that depend on the cached segmenter outputs (prob tensors + argmax).
// The camera and segmenter are mocked from fixture data per design §7.3.
// β is held at 1.0 so V_c^uncal is produced (used by BetaCalibrator as the
// uncorrected predicted volume).
public enum FixtureRunner {

    public enum Error: Swift.Error {
        case invalidCapturePath(String)
        case missingDepthForSingleView(String)
        case missingObliqueDataForTwoView(String)
        case volumeEstimationFailed(String, Swift.Error)
        // The probability tensor does not match H*W*C*2 for the resolved
        // palette. Thrown rather than left to `ProbabilityTensor`'s
        // precondition, which traps the process: this is a batch tool over
        // operator-supplied files, so a malformed or mis-palletted bundle must
        // be a skipped fixture with a message, not a crash that loses the
        // report for every other bundle in the directory.
        case probsSizeMismatch(String, expected: Int, got: Int)
        // The stored nadir PNG did not decode, or its pixel grid is not the one
        // the nadir intrinsics declare.
        case nadirImageUnusable(String, detail: String)
    }

    // Run the volume + macros pipeline (β = 1) on one fixture.
    // Returns a MealCalibrationInput with per-class predicted and actual carbs.
    // `regularisation` is the same pass `SegmenterPostProcessor.process` runs on
    // device before the label map reaches the volume stage. Replay reads the
    // argmax a fixture stored rather than deriving it from logits, so without
    // this the harness would integrate volume over an UNregularised mask while
    // the app integrates over a regularised one (unknown-food-nameable task 3).
    // Defaults to `.standard` for that reason; pass `.disabled` for the
    // raw-argmax behaviour.
    public static func run(
        fixture: PbMealFixture,
        palette: ClassPalette,
        database: any FoodDatabase,
        voxelEdgeMm: Float = 3.0,
        regularisation: MaskRegularisationConfig = .standard,
        growth: FoodRegionGrowthConfig = .standard,
        reconciliation: Bool = true,
        cardExclusion: Bool = true,
        nadirSeed: SIMD2<Int>? = nil
    ) throws -> MealCalibrationInput {
        guard let capturePath = CapturePath(rawValue: fixture.capturePathCanonical) else {
            throw Error.invalidCapturePath(fixture.capturePathCanonical)
        }

        let nadirIntrinsics = CameraIntrinsics(pb: fixture.nadirIntrinsics)
        let C = palette.totalClasses
        let W = nadirIntrinsics.imageWidth
        let H = nadirIntrinsics.imageHeight
        let gravity = Vec3(pb: fixture.gravity)

        let expectedProbBytes = H * W * C * 2
        guard fixture.nadirProbs.count == expectedProbBytes else {
            throw Error.probsSizeMismatch(
                fixture.fixtureID, expected: expectedProbBytes, got: fixture.nadirProbs.count)
        }

        // Build nadir segmentation result from cached probs + argmax.
        let nadirSeg = makeSegResult(
            probsData: fixture.nadirProbs,
            argmaxData: fixture.nadirArgmax,
            width: W, height: H, classes: C, palette: palette,
            regularisation: regularisation
        )

        // Unity β correction (β = 1.0 for all classes).
        let unityBeta = BetaCorrection(entries: [:], defaultBeta: 1.0)

        let perClassVolumesCm3: [String: Float]
        var supportPlaneResidualMm: Float?
        var supportPlaneReference: SupportPlaneReference?
        var regionGrowth: MealCalibrationInput.RegionGrowth?
        switch capturePath {
        case .singleViewLidar:
            guard fixture.hasNadirDepth else {
                throw Error.missingDepthForSingleView(fixture.fixtureID)
            }
            let depth = DepthMap(pb: fixture.nadirDepth)
            // Req 5.1: one implementation for device and replay. Both the legacy
            // whole-frame fit and the N5k plate-region flood fill are gone from this
            // branch — the estimator_path stamp no longer selects a fitter here. The
            // flood fill survives for the mixture path, which has no segmentation
            // output to derive a mask from (Decision 17).
            // The device fits the first plane from the pre-shutter mask it captured
            // (`captureResult.preShutterFoodMask`); a bundle that carries it replays
            // from the same mask. Fixtures without one keep the argmax-derived mask.
            var fit = try fitSupportPlane(
                depth: depth, intrinsics: nadirIntrinsics, gravity: gravity,
                foodMask: preShutterMask(fixture, width: W, height: H)
                    ?? foodRegionMask(argmax: nadirSeg.argmax, palette: palette),
                fixtureID: fixture.fixtureID)
            // The device's stage C–F order: the LiDAR scale at the first plane
            // picks the card, the card quad is cleared from the nadir labels
            // (two-view-trust Req 4.6), then one object takes one class before
            // growth (Req 2.1).
            var nadirSeg = nadirSeg
            if cardExclusion, let card = try pickCard(
                fixture: fixture, intrinsics: nadirIntrinsics, lidarMmPerPx: lidarScale(fit.plane, nadirIntrinsics)) {
                nadirSeg = nadirSeg.excluding(quad: card.corners.map { SIMD2($0.u, $0.v) }).result
            }
            if reconciliation {
                nadirSeg = ObjectReconciler.reconcile(nadir: nadirSeg, palette: palette, userClass: nil).nadir
            }
            // Depth-grown food region, exactly as Pipeline.estimate runs it
            // (depth-grown-food-region Req 7): grow from the regularised map,
            // refit from the grown mask, keep the first plane on a refusal.
            // two-view-trust Req 3.14: the replay applies the identical seed
            // rule the device will; `nadirSeed: nil` replays without it.
            let refit = refitPlaneFromGrownRegion(
                argmax: nadirSeg.argmax, depth: depth, intrinsics: nadirIntrinsics,
                gravity: gravity, first: fit, palette: palette, growth: growth,
                seedPoints: nadirSeed.map { [$0] } ?? [], gateBySeedArea: true)
            let grown = refit.growth
            var measuredSeg = nadirSeg
            if grown.applied {
                measuredSeg = SegmentationResult(
                    probabilities: nadirSeg.probabilities, argmax: grown.argmax,
                    perClassMeanProb: nadirSeg.perClassMeanProb, sigmaSeg: nadirSeg.sigmaSeg)
            }
            if let stats = refit.adoptedStats {
                fit = SingleViewPlaneFit(plane: refit.plane, reference: refit.reference,
                                         ringMedianMm: stats.ring?.medianMm)
            }
            // A seed clears the components it did not name whether or not the
            // fill added anything, so the silhouette that is integrated is the
            // restricted one in every branch.
            if nadirSeed != nil, !grown.applied {
                measuredSeg = SegmentationResult(
                    probabilities: nadirSeg.probabilities, argmax: grown.argmax,
                    perClassMeanProb: nadirSeg.perClassMeanProb, sigmaSeg: nadirSeg.sigmaSeg)
            }
            regionGrowth = .init(
                applied: grown.applied, capTripped: grown.capTripped,
                foodPixelsBefore: grown.foodPixelsBefore, foodPixelsAfter: grown.foodPixelsAfter,
                refitReference: refit.refitReference, refitRefused: refit.refitRefused,
                seedAreaCm2: refit.seedAreaCm2, gated: refit.gated,
                grownAreaCm2: refit.grownAreaCm2)
            supportPlaneResidualMm = fit.plane.residualMm
            supportPlaneReference = fit.reference
            let est = try runHeightField(
                seg: measuredSeg, depth: depth,
                intrinsics: nadirIntrinsics, plane: fit.plane,
                beta: unityBeta, palette: palette,
                fixtureID: fixture.fixtureID,
                grownRegion: grown.grownRegion
            )
            perClassVolumesCm3 = est.perClassVolumesCm3

        case .twoViewSfS:
            guard !fixture.obliqueProbs.isEmpty, !fixture.obliqueArgmax.isEmpty,
                  fixture.hasObliqueIntrinsics else {
                throw Error.missingObliqueDataForTwoView(fixture.fixtureID)
            }
            let obliqueIntrinsics = CameraIntrinsics(pb: fixture.obliqueIntrinsics)
            let obliqueW = obliqueIntrinsics.imageWidth
            let obliqueH = obliqueIntrinsics.imageHeight
            // Req 10 applies to each view independently on the two-view path.
            var obliqueSeg = makeSegResult(
                probsData: fixture.obliqueProbs,
                argmaxData: fixture.obliqueArgmax,
                width: obliqueW, height: obliqueH,
                classes: C, palette: palette,
                regularisation: regularisation
            )
            // A device two-view bundle from a LiDAR phone carries nadir depth:
            // fit the support plane exactly as the device did (stage D) so the
            // replay's volume is the device's, not a nominal-plane approximation.
            var plane: SupportPlane
            var firstFit: SingleViewPlaneFit?
            if fixture.hasNadirDepth {
                // `try`, not `try?`: a refused fit refuses the replay, as
                // `Pipeline.fitSupportPlane` refuses the capture on both
                // paths. Falling through to the nominal plane here printed a
                // volume the device can never produce.
                let fit = try fitSupportPlane(
                    depth: DepthMap(pb: fixture.nadirDepth), intrinsics: nadirIntrinsics,
                    gravity: gravity,
                    foodMask: preShutterMask(fixture, width: W, height: H)
                        ?? foodRegionMask(argmax: nadirSeg.argmax, palette: palette),
                    fixtureID: fixture.fixtureID)
                plane = fit.plane
                firstFit = fit
                supportPlaneResidualMm = fit.plane.residualMm
                supportPlaneReference = fit.reference
            } else {
                // Depth-free fixtures ONLY (non-LiDAR captures, synthetic
                // controls): the gravity-aligned nominal plane at -300 mm, so
                // the degraded no-depth carve can be exercised offline.
                // Production refuses this capture (`noSupportPlaneWithoutDepth`);
                // the -1 residual carried into the summary marks the result
                // as a nominal-plane replay, not device behaviour.
                plane = nominalPlane(gravity: gravity)
                supportPlaneResidualMm = plane.residualMm
            }
            let t1to2 = Mat4(pb: fixture.t1To2)
            // Card exclusion in both views as on the device (Req 4.6): the
            // nadir quad directly, the oblique through the stored transform.
            var nadirSeg = nadirSeg
            if cardExclusion, let card = try pickCard(
                fixture: fixture, intrinsics: nadirIntrinsics,
                lidarMmPerPx: fixture.hasNadirDepth ? lidarScale(plane, nadirIntrinsics) : nil) {
                nadirSeg = nadirSeg.excluding(quad: card.corners.map { SIMD2($0.u, $0.v) }).result
                obliqueSeg = obliqueSeg.excluding(quad: PipelineBridges.projectToOblique(
                    card.pose.cornersCameraMm, transform1To2: t1to2, intrinsics: obliqueIntrinsics)).result
            }
            // Same pass, same place as Pipeline (two-view-trust Req 2.1), so a
            // replay carves what the device carved. `reconciliation: false`
            // replays the raw labels for comparison.
            if reconciliation {
                let r = ObjectReconciler.reconcile(
                    nadir: nadirSeg, oblique: obliqueSeg, palette: palette, userClass: nil)
                nadirSeg = r.nadir
                obliqueSeg = r.oblique
            }
            // Plane refit from the grown region, plane only (two-view-trust
            // Decision 10), exactly as Pipeline's two-view branch runs it: the
            // adopted plane floors the carve and measures its height; the
            // silhouette stays the reconciled map.
            if let first = firstFit {
                let depth = DepthMap(pb: fixture.nadirDepth)
                let refit = refitPlaneFromGrownRegion(
                    argmax: nadirSeg.argmax, depth: depth, intrinsics: nadirIntrinsics,
                    gravity: gravity, first: first, palette: palette, growth: growth)
                if refit.adopted {
                    plane = refit.plane
                    supportPlaneResidualMm = refit.plane.residualMm
                    supportPlaneReference = refit.reference
                }
                regionGrowth = .init(
                    applied: refit.growth.applied, capTripped: refit.growth.capTripped,
                    foodPixelsBefore: refit.growth.foodPixelsBefore,
                    foodPixelsAfter: refit.growth.foodPixelsAfter,
                    refitReference: refit.refitReference, refitRefused: refit.refitRefused)
            }
            let est = try runVoxelCarve(
                nadirSeg: nadirSeg, obliqueSeg: obliqueSeg,
                nadirIntrinsics: nadirIntrinsics, obliqueIntrinsics: obliqueIntrinsics,
                t1to2: t1to2, plane: plane, gravity: gravity,
                nadirDepth: fixture.hasNadirDepth ? DepthMap(pb: fixture.nadirDepth) : nil,
                beta: unityBeta, palette: palette,
                voxelEdgeMm: voxelEdgeMm, fixtureID: fixture.fixtureID
            )
            perClassVolumesCm3 = est.perClassVolumesCm3
        }

        // Macros with β = 1 → predicted_c = V_c^uncal * ρ_c * κ_c / 100.
        let macros = Macros.compute(
            perClassVolumesCm3: perClassVolumesCm3,
            database: database,
            edition: fixture.databaseEdition
        )
        let predictedCarbsPerClass = macros.perClass.mapValues(\.carbsG)

        // Build actual carbs: m_c^* * κ_c / 100 using database coefficients.
        var actualCarbs: [String: Float] = [:]
        for (classId, massG) in fixture.groundTruthClassMassG {
            if let entry = database.entry(for: classId, edition: fixture.databaseEdition) {
                actualCarbs[classId] = massG * entry.carbsMonoG / 100.0
            }
        }

        let dominantClass = perClassVolumesCm3
            .max(by: { $0.value < $1.value })?.key

        return MealCalibrationInput(
            fixtureID: fixture.fixtureID,
            capturePath: capturePath,
            dominantClass: dominantClass,
            predictedCarbsPerClass: predictedCarbsPerClass,
            actualCarbsPerClass: actualCarbs,
            groundTruthTotalCarbsG: fixture.groundTruthTotalCarbsG,
            perClassVolumesCm3: perClassVolumesCm3,
            supportPlaneResidualMm: supportPlaneResidualMm,
            supportPlaneReference: supportPlaneReference,
            regionGrowth: regionGrowth
        )
    }

    // MARK: - Food-support plane (Req 5.1)

    public struct SingleViewPlaneFit: Sendable {
        public let plane: SupportPlane
        // nil is unreachable on this path (the depth branch always records one) and
        // is carried only because `SupportPlaneFitStats` must leave it absent on the
        // card-only path, where no depth-derived reference exists (Req 6.3).
        public let reference: SupportPlaneReference?
        // Ring median above the plane (depth-grown-food-region): the plate top's
        // height on an edge-band fit, ~0 on a foodSupport fit.
        public let ringMedianMm: Float?

        public init(plane: SupportPlane, reference: SupportPlaneReference?, ringMedianMm: Float? = nil) {
            self.plane = plane
            self.reference = reference
            self.ringMedianMm = ringMedianMm
        }

        // The support surface's height above `plane`, the rule Pipeline uses.
        public var supportOffsetMm: Float {
            guard reference == .edgeBand, let m = ringMedianMm, m.isFinite, m > 0 else { return 0 }
            return m
        }
    }

    // The offline replay's support plane, derived by the SAME code the device runs
    // (Req 5.1). Throws on a refusal so the caller skips and records the fixture,
    // which is the pre-existing Req 3.4/3.8 skip path.
    public static func fitSupportPlane(
        depth: DepthMap,
        intrinsics: CameraIntrinsics,
        gravity: Vec3,
        foodMask: BinaryMask,
        fixtureID: String
    ) throws -> SingleViewPlaneFit {
        let outcome = LiDARSupportPlaneFitter.fitFromDepth(
            depth: depth, intrinsics: intrinsics, mask: foodMask, gravity: gravity)
        guard let plane = outcome.plane else {
            throw Error.volumeEstimationFailed(
                fixtureID, outcome.refusal ?? SupportPlaneError.noLidarPoints)
        }
        return SingleViewPlaneFit(plane: plane, reference: outcome.stats.reference,
                                  ringMedianMm: outcome.stats.ring?.medianMm)
    }

    // Grow → refit → prune → adopt with the replay's fitter, which is the same
    // `LiDARSupportPlaneFitter.fitFromDepth` the device's fitter wraps, so the
    // plane a replay adopts is the plane the device adopts (Req 5.1).
    static func refitPlaneFromGrownRegion(
        argmax: ArgmaxMap,
        depth: DepthMap,
        intrinsics: CameraIntrinsics,
        gravity: Vec3,
        first: SingleViewPlaneFit,
        palette: ClassPalette,
        growth: FoodRegionGrowthConfig,
        seedPoints: [SIMD2<Int>] = [],
        gateBySeedArea: Bool = false
    ) -> GrownRegionPlaneRefit.Outcome {
        GrownRegionPlaneRefit.refit(
            argmax: argmax, depth: depth, intrinsics: intrinsics,
            supportPlane: first.plane, supportReference: first.reference,
            supportOffsetMm: first.supportOffsetMm,
            palette: palette, config: growth, seedPoints: seedPoints,
            gateBySeedArea: gateBySeedArea
        ) { mask in
            LiDARSupportPlaneFitter.fitFromDepth(
                depth: depth, intrinsics: intrinsics, mask: mask, gravity: gravity)
        }
    }

    // The food-region mask on the argmax grid. `fitFoodSupportPlane` needs one and
    // this call site had none; argmax is the same source the device's segmenter
    // produces, so the two paths see the same mask (Req 5.1). The predicate is
    // `isVolumetricClass`, matching `PipelineBridges.foodMask` — an all-unknown
    // plate must reach the fitter on replay for the same reason it must on
    // device (unknown-food-nameable Req 2).
    public static func foodRegionMask(argmax: ArgmaxMap, palette: ClassPalette) -> BinaryMask {
        BinaryMask(
            pixels: argmax.pixels.map { palette.isVolumetricClass(Int($0)) ? UInt8(1) : UInt8(0) },
            width: argmax.width,
            height: argmax.height
        )
    }

    // The device's pre-shutter food mask as the bundle recorded it
    // (`CaptureBundleRecorder`: raw `BinaryMask.pixels`, 1 = food, on the colour
    // grid). nil when the fixture has none or its size is not the nadir's.
    static func preShutterMask(_ fixture: PbMealFixture, width: Int, height: Int) -> BinaryMask? {
        guard Int(fixture.preShutterMaskWidth) == width,
              Int(fixture.preShutterMaskHeight) == height,
              fixture.preShutterMask.count == width * height
        else { return nil }
        return BinaryMask(pixels: [UInt8](fixture.preShutterMask), width: width, height: height)
    }

    // MARK: - Plate-region support plane (mixture calibration only, Decision 17)

    // Documented 4-neighbour depth-continuity threshold for the plate flood
    // fill: per-pixel steps on food/plate surfaces stay well below it, while
    // the plate-rim drop to the table (≈20 mm) exceeds it and stops the fill.
    public static let plateDepthContinuityThresholdMm: Float = 5.0

    // How far from the frame centre to search for a valid (non-sentinel) seed
    // pixel — a specular highlight can null the exact centre.
    static let plateSeedSearchRadiusPx = 8

    // Flood fill on 4-neighbour depth continuity, seeded at the frame centre
    // (the N5k rig centres the plate under the camera). Sentinel/at-cap pixels
    // (depth 0) are barriers, never members. Mask is on the depth grid.
    // Returns nil when no valid seed exists near the centre.
    public static func plateRegionMask(
        depth: DepthMap,
        continuityThresholdMm: Float = plateDepthContinuityThresholdMm
    ) -> BinaryMask? {
        let w = depth.width
        let h = depth.height
        let z: [Float] = depth.depthBytesMm.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self).prefix(w * h))
        }
        // Seed at the centre; on a sentinel, take the nearest valid pixel
        // within the search radius (expanding rings).
        var seed = -1
        outer: for r in 0...plateSeedSearchRadiusPx {
            for dy in -r...r {
                for dx in -r...r where max(abs(dx), abs(dy)) == r {
                    let x = w / 2 + dx
                    let y = h / 2 + dy
                    guard x >= 0, x < w, y >= 0, y < h else { continue }
                    if z[y * w + x] > 0 { seed = y * w + x; break outer }
                }
            }
        }
        guard seed >= 0 else { return nil }

        var member = [UInt8](repeating: 0, count: w * h)
        var stack = [seed]
        member[seed] = 1
        while let idx = stack.popLast() {
            let x = idx % w
            let y = idx / w
            let zc = z[idx]
            for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] {
                guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                let nIdx = ny * w + nx
                guard member[nIdx] == 0 else { continue }
                let zn = z[nIdx]
                guard zn > 0, abs(zn - zc) < continuityThresholdMm else { continue }
                member[nIdx] = 1
                stack.append(nIdx)
            }
        }
        return BinaryMask(pixels: member, width: w, height: h)
    }

    // Fit the support plane restricted to the flood-filled plate region, so the
    // RANSAC lands on the plate top rather than the table. Throws when no
    // plate region can be resolved, the region yields no plane, or the fit
    // residual exceeds `residualMaxMm` (the Req 3.4/3.8 skip-and-record path).
    //
    // Scoped to the MIXTURE calibration path (Decision 17). Mixture fixtures carry
    // neither `probs_hwc` nor `argmax_hw`, so no food mask can be derived at that
    // site and `fitFoodSupportPlane` requires one — a data limitation, not a wiring
    // gap. The mixture corpus is a fixed overhead rig where the frame-centre seed
    // assumption Req 2.2 rejects for handheld capture does hold. Planes fitted here
    // carry `SupportPlaneReference.plateRegion`, and Req 5.4 keeps β_c fitted within
    // a reference: nothing may mix them.
    public static func fitPlateRegionPlane(
        depth: DepthMap,
        intrinsics: CameraIntrinsics,
        gravity: Vec3,
        fixtureID: String,
        residualMaxMm: Float = LiDARPlaneFitter.residualMaxMm
    ) throws -> SupportPlane {
        guard let depthMask = plateRegionMask(depth: depth) else {
            throw Error.volumeEstimationFailed(fixtureID, SupportPlaneError.noLidarPoints)
        }
        // LiDARPlaneFitter expects the mask on the colour grid; resample by
        // nearest neighbour when the grids differ (N5k rgb/depth match, so this
        // is normally the identity).
        let mask: BinaryMask
        if depthMask.width == intrinsics.imageWidth && depthMask.height == intrinsics.imageHeight {
            mask = depthMask
        } else {
            let cw = intrinsics.imageWidth
            let ch = intrinsics.imageHeight
            var pixels = [UInt8](repeating: 0, count: cw * ch)
            for y in 0..<ch {
                let dy = min(depthMask.height - 1, y * depthMask.height / ch)
                for x in 0..<cw {
                    let dx = min(depthMask.width - 1, x * depthMask.width / cw)
                    pixels[y * cw + x] = depthMask.isFood(x: dx, y: dy) ? 1 : 0
                }
            }
            mask = BinaryMask(pixels: pixels, width: cw, height: ch)
        }
        do {
            return try LiDARPlaneFitter.fit(LiDARPlaneFitter.Inputs(
                depth: depth,
                colourIntrinsics: intrinsics,
                foodRegionMask: mask,
                gravityCamera: gravity,
                residualMaxMm: residualMaxMm,
                candidateRegion: .insideMask
            ))
        } catch {
            throw Error.volumeEstimationFailed(fixtureID, error)
        }
    }

    // MARK: - Card pick (the device's stage C + E on the stored nadir frame)

    static func lidarScale(_ plane: SupportPlane, _ k: CameraIntrinsics) -> Float {
        abs(plane.distanceMm) / ((k.fx + k.fy) / 2)
    }

    /// The card the device would pick: Vision's ranked rectangles on the
    /// stored nadir image, solved and arbitrated by the LiDAR scale
    /// (`CardPoseSolver.pick`). nil for a fixture without an image, when
    /// nothing is found, or when no rectangle solves as a card.
    public static func pickCard(
        fixture: PbMealFixture, intrinsics: CameraIntrinsics, lidarMmPerPx: Float?
    ) throws -> (corners: [PixelCorner], pose: CardPose)? {
        guard !fixture.nadirImage.isEmpty else { return nil }
        let frame = try nadirFrame(fixture: fixture)
        let candidates = detectCards(in: frame)
        guard !candidates.isEmpty else { return nil }
        return try? CardPoseSolver.pick(candidates: candidates, intrinsics: intrinsics, lidarMmPerPx: lidarMmPerPx)
    }

    /// `detect(in:)` is async and replay is synchronous: block until the
    /// detector's continuation resumes off its own queue.
    public static func detectCards(in frame: RawFrame, maximumObservations: Int = 8) -> [[PixelCorner]] {
        final class Box: @unchecked Sendable { var candidates: [[PixelCorner]] = [] }
        let detector = VisionCardDetector(maximumObservations: maximumObservations)
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        Task {
            box.candidates = await detector.detect(in: frame)
            done.signal()
        }
        done.wait()
        return box.candidates
    }

    // MARK: - Nadir frame (card-detection replay)

    // The stored nadir PNG (RGB8 sRGB, top-left origin — the
    // `CaptureBundleRecorder.encodeRGB8PNG` contract) decoded back into the
    // BGRA8 `RawFrame` the device handed `VisionCardDetector`. Depth stays nil
    // and the pose identity: the detector reads image bytes and nothing else.
    public static func nadirFrame(fixture: PbMealFixture) throws -> RawFrame {
        try frame(png: fixture.nadirImage, intrinsics: CameraIntrinsics(pb: fixture.nadirIntrinsics), fixture: fixture)
    }

    /// The oblique twin of `nadirFrame`; gravity is the nadir's, which the
    /// detector never reads.
    public static func obliqueFrame(fixture: PbMealFixture) throws -> RawFrame {
        try frame(png: fixture.obliqueImage, intrinsics: CameraIntrinsics(pb: fixture.obliqueIntrinsics), fixture: fixture)
    }

    private static func frame(png: Data, intrinsics: CameraIntrinsics, fixture: PbMealFixture) throws -> RawFrame {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw Error.nadirImageUnusable(fixture.fixtureID, detail: "PNG did not decode")
        }
        let w = image.width
        let h = image.height
        guard w == intrinsics.imageWidth, h == intrinsics.imageHeight else {
            throw Error.nadirImageUnusable(
                fixture.fixtureID,
                detail: "PNG is \(w)x\(h), intrinsics say \(intrinsics.imageWidth)x\(intrinsics.imageHeight)")
        }
        // Same CG mapping `VisionCardDetector` uses to read the bytes back
        // (kCVPixelFormatType_32BGRA: byteOrder32Little + premultipliedFirst).
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                    bytesPerRow: w * 4, space: space,
                    bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue
                        | CGImageAlphaInfo.premultipliedFirst.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard drawn else {
            throw Error.nadirImageUnusable(fixture.fixtureID, detail: "BGRA8 context creation failed")
        }
        return RawFrame(
            imageBytes: Data(bytes), pixelFormat: .bgra8, colourSpace: .sRGB,
            orientation: 1, imageWidth: w, imageHeight: h, timestampMonotonicNs: 0,
            intrinsics: intrinsics, gravity: Vec3(pb: fixture.gravity),
            worldFromCamera: .identity, depth: nil)
    }

    // MARK: - Private helpers

    static func makeSegResult(
        probsData: Data,
        argmaxData: Data,
        width: Int, height: Int,
        classes: Int,
        palette: ClassPalette,
        regularisation: MaskRegularisationConfig
    ) -> SegmentationResult {
        let probs = ProbabilityTensor(
            bytes: probsData, height: height, width: width,
            classes: classes, palette: palette
        )
        // A checkpoint-mode N5k fixture carries the model's probabilities and
        // no argmax (N5k has no truth mask; ingest.py leaves nadir_argmax
        // empty), so the label map is derived here exactly as the device
        // derives it from the tensor. A recorded device bundle carries both.
        let rawArgmax = argmaxData.count == width * height
            ? argmaxData
            : Data(SegBench.argmaxFromFP16Probs(
                probsData: probsData, width: width, height: height, classes: classes))
        let cleaned = SegmenterPostProcessor.regularise(
            argmax: rawArgmax, width: width, height: height,
            palette: palette, config: regularisation)
        let argmax = ArgmaxMap(pixels: cleaned, height: height, width: width)
        // sigmaSeg not critical for calibration; use 1.0.
        return SegmentationResult(
            probabilities: probs, argmax: argmax,
            perClassMeanProb: [:], sigmaSeg: 1.0
        )
    }

    // Gravity-aligned nominal support plane at -300 mm from camera.
    static func nominalPlane(gravity: Vec3) -> SupportPlane {
        // `gravity` is world-up in the camera frame (RawFrame.gravity contract),
        // so the plane normal IS that vector; negating it pointed the nominal
        // plane down and put the carve grid under it.
        let normal = gravity.normalised()
        // residualMm = -1, NOT 0: this plane was invented, not fitted, and a zero
        // residual is the strongest possible claim of fit quality. -1 is the
        // sentinel `SupportPlaneFitStats` already documents for "refused before a
        // residual was computed". Production REFUSES a depth-free two-view capture
        // (`noSupportPlaneWithoutDepth`); this nominal plane is what lets the
        // harness carve anyway, which is legitimate for the synthetic controls and
        // is NOT evidence of device behaviour — the sentinel is how a reader tells.
        return SupportPlane(normal: normal, distanceMm: -300, residualMm: -1, convergedIterations: nil)
    }

    private static func runHeightField(
        seg: SegmentationResult,
        depth: DepthMap,
        intrinsics: CameraIntrinsics,
        plane: SupportPlane,
        beta: BetaCorrection,
        palette: ClassPalette,
        fixtureID: String,
        grownRegion: BinaryMask? = nil
    ) throws -> HeightFieldEstimate {
        let outcome = HeightFieldEstimator.integrate(HeightFieldEstimator.Inputs(
            probabilities: seg.probabilities,
            argmax: seg.argmax,
            depth: depth,
            intrinsics: intrinsics,
            supportPlane: plane,
            beta: beta,
            palette: palette,
            grownRegion: grownRegion
        ))
        guard let est = outcome.estimate else {
            throw Error.volumeEstimationFailed(
                fixtureID, outcome.refusal ?? VolumeError.noFoodVolumeRecovered
            )
        }
        return est
    }

    private static func runVoxelCarve(
        nadirSeg: SegmentationResult,
        obliqueSeg: SegmentationResult,
        nadirIntrinsics: CameraIntrinsics,
        obliqueIntrinsics: CameraIntrinsics,
        t1to2: Mat4,
        plane: SupportPlane,
        gravity: Vec3,
        nadirDepth: DepthMap?,
        beta: BetaCorrection,
        palette: ClassPalette,
        voxelEdgeMm: Float,
        fixtureID: String
    ) throws -> VoxelCarveEstimate {
        let matching = MaskMatcher.match(
            view1: nadirSeg.argmax,
            view2: obliqueSeg.argmax,
            palette: palette
        )
        let foodMask = foodRegionMask(argmax: nadirSeg.argmax, palette: palette)
        // Same vertical bound as the device (Pipeline, stage I): with nadir
        // depth the grid stops at the food's own height, capped by the class
        // prior; without it the class cap is the extent (two-view-trust
        // Decision 11).
        let measuredFoodHeightMm = nadirDepth.flatMap {
            VoxelGridSizer.measuredFoodHeightMm(
                foodMask: foodMask, depth: $0,
                intrinsics: nadirIntrinsics, supportPlane: plane)
        }
        // The cap scales with the silhouette's footprint where no height is
        // measured (Decision 12); a measurement keeps Decision 11's ceiling.
        let footprintMm2 = VoxelGridSizer.silhouetteFootprintMm2(
            foodMask: foodMask, intrinsics: nadirIntrinsics, supportPlane: plane)
        let classCap = ClassHeightPriors.bundled?.carveCap(
            forNadirArgmax: nadirSeg.argmax, palette: palette,
            footprintMm2: footprintMm2, heightMeasured: measuredFoodHeightMm != nil)
        let grid: VoxelGrid
        do {
            grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
                foodMask: foodMask,
                nadirIntrinsics: nadirIntrinsics,
                supportPlane: plane,
                gravityCamera: gravity,
                edgeMm: voxelEdgeMm,
                measuredFoodHeightMm: measuredFoodHeightMm,
                classCap: classCap
            ))
        } catch {
            throw Error.volumeEstimationFailed(fixtureID, error)
        }
        let outcome = VoxelCarveEstimator.carve(VoxelCarveEstimator.Inputs(
            grid: grid,
            view1: VoxelCarveView(probabilities: nadirSeg.probabilities,
                                 intrinsics: nadirIntrinsics,
                                 argmax: nadirSeg.argmax),
            view2: VoxelCarveView(probabilities: obliqueSeg.probabilities,
                                 intrinsics: obliqueIntrinsics,
                                 argmax: obliqueSeg.argmax),
            transform1To2: t1to2,
            supportPlane: plane,
            matchedClasses: matching.matchedClasses,
            singleViewOnlyClassesView1: matching.singleViewOnly(view: 1),
            singleViewOnlyClassesView2: matching.singleViewOnly(view: 2),
            beta: beta,
            palette: palette
        ))
        guard let est = outcome.estimate else {
            throw Error.volumeEstimationFailed(
                fixtureID, outcome.refusal ?? VolumeError.noFoodVolumeRecovered
            )
        }
        return est
    }
}
#endif

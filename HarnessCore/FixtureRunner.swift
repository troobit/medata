#if HARNESS_ENABLED
import CaptureKit
import Foods
import Foundation
import Macros
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
    }

    // Run the volume + macros pipeline (β = 1) on one fixture.
    // Returns a MealCalibrationInput with per-class predicted and actual carbs.
    public static func run(
        fixture: PbMealFixture,
        palette: ClassPalette,
        database: any FoodDatabase,
        voxelEdgeMm: Float = 3.0
    ) throws -> MealCalibrationInput {
        guard let capturePath = CapturePath(rawValue: fixture.capturePathCanonical) else {
            throw Error.invalidCapturePath(fixture.capturePathCanonical)
        }

        let nadirIntrinsics = CameraIntrinsics(pb: fixture.nadirIntrinsics)
        let C = palette.totalClasses
        let W = nadirIntrinsics.imageWidth
        let H = nadirIntrinsics.imageHeight
        let gravity = Vec3(pb: fixture.gravity)

        // Build nadir segmentation result from cached probs + argmax.
        let nadirSeg = makeSegResult(
            probsData: fixture.nadirProbs,
            argmaxData: fixture.nadirArgmax,
            width: W, height: H, classes: C, palette: palette
        )

        // Unity β correction (β = 1.0 for all classes).
        let unityBeta = BetaCorrection(entries: [:], defaultBeta: 1.0)

        let perClassVolumesCm3: [String: Float]
        var supportPlaneResidualMm: Float?
        switch capturePath {
        case .singleViewLidar:
            guard fixture.hasNadirDepth else {
                throw Error.missingDepthForSingleView(fixture.fixtureID)
            }
            let depth = DepthMap(pb: fixture.nadirDepth)
            // N5k fixtures (stamped with an estimator_path) restrict the plane
            // fit to the flood-filled plate region so RANSAC lands on the plate
            // top, not the surrounding table (Req 3.6, Decision 15 amendment).
            let plane: SupportPlane
            if fixture.estimatorPath.isEmpty {
                plane = try fitPlaneFromDepth(depth: depth, intrinsics: nadirIntrinsics,
                                              gravity: gravity, fixtureID: fixture.fixtureID)
            } else {
                plane = try fitPlateRegionPlane(depth: depth, intrinsics: nadirIntrinsics,
                                                gravity: gravity, fixtureID: fixture.fixtureID)
            }
            supportPlaneResidualMm = plane.residualMm
            let est = try runHeightField(
                seg: nadirSeg, depth: depth,
                intrinsics: nadirIntrinsics, plane: plane,
                beta: unityBeta, palette: palette,
                fixtureID: fixture.fixtureID
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
            let obliqueSeg = makeSegResult(
                probsData: fixture.obliqueProbs,
                argmaxData: fixture.obliqueArgmax,
                width: obliqueW, height: obliqueH,
                classes: C, palette: palette
            )
            // Nominal plane: gravity-aligned at -300 mm (typical table distance).
            let plane = nominalPlane(gravity: gravity)
            let t1to2 = Mat4(pb: fixture.t1To2)
            let est = try runVoxelCarve(
                nadirSeg: nadirSeg, obliqueSeg: obliqueSeg,
                nadirIntrinsics: nadirIntrinsics, obliqueIntrinsics: obliqueIntrinsics,
                t1to2: t1to2, plane: plane, gravity: gravity,
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
            supportPlaneResidualMm: supportPlaneResidualMm
        )
    }

    // MARK: - Plate-region support plane (N5k, Req 3.6)

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

    // MARK: - Private helpers

    private static func makeSegResult(
        probsData: Data,
        argmaxData: Data,
        width: Int, height: Int,
        classes: Int,
        palette: ClassPalette
    ) -> SegmentationResult {
        let probs = ProbabilityTensor(
            bytes: probsData, height: height, width: width,
            classes: classes, palette: palette
        )
        let argmax = ArgmaxMap(pixels: argmaxData, height: height, width: width)
        // sigmaSeg not critical for calibration; use 1.0.
        return SegmentationResult(
            probabilities: probs, argmax: argmax,
            perClassMeanProb: [:], sigmaSeg: 1.0
        )
    }

    private static func fitPlaneFromDepth(
        depth: DepthMap,
        intrinsics: CameraIntrinsics,
        gravity: Vec3,
        fixtureID: String
    ) throws -> SupportPlane {
        let mask = BinaryMask(
            pixels: [UInt8](repeating: 1, count: intrinsics.imageWidth * intrinsics.imageHeight),
            width: intrinsics.imageWidth,
            height: intrinsics.imageHeight
        )
        do {
            return try LiDARPlaneFitter.fit(LiDARPlaneFitter.Inputs(
                depth: depth,
                colourIntrinsics: intrinsics,
                foodRegionMask: mask,
                gravityCamera: gravity
            ))
        } catch {
            throw Error.volumeEstimationFailed(fixtureID, error)
        }
    }

    // Gravity-aligned nominal support plane at -300 mm from camera.
    private static func nominalPlane(gravity: Vec3) -> SupportPlane {
        // Normal points opposite to gravity (upward).
        let nx = -gravity.x; let ny = -gravity.y; let nz = -gravity.z
        let len = (nx * nx + ny * ny + nz * nz).squareRoot()
        let normal = Vec3(nx / len, ny / len, nz / len)
        return SupportPlane(normal: normal, distanceMm: -300, residualMm: 0, convergedIterations: nil)
    }

    private static func runHeightField(
        seg: SegmentationResult,
        depth: DepthMap,
        intrinsics: CameraIntrinsics,
        plane: SupportPlane,
        beta: BetaCorrection,
        palette: ClassPalette,
        fixtureID: String
    ) throws -> HeightFieldEstimate {
        let outcome = HeightFieldEstimator.integrate(HeightFieldEstimator.Inputs(
            probabilities: seg.probabilities,
            argmax: seg.argmax,
            depth: depth,
            intrinsics: intrinsics,
            supportPlane: plane,
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

    private static func runVoxelCarve(
        nadirSeg: SegmentationResult,
        obliqueSeg: SegmentationResult,
        nadirIntrinsics: CameraIntrinsics,
        obliqueIntrinsics: CameraIntrinsics,
        t1to2: Mat4,
        plane: SupportPlane,
        gravity: Vec3,
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
        let foodMask = BinaryMask(
            pixels: nadirSeg.argmax.pixels.map { b in
                palette.isFoodClass(Int(b)) ? UInt8(1) : UInt8(0)
            },
            width: nadirSeg.argmax.width,
            height: nadirSeg.argmax.height
        )
        let grid: VoxelGrid
        do {
            grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
                foodMask: foodMask,
                nadirIntrinsics: nadirIntrinsics,
                supportPlane: plane,
                gravityCamera: gravity,
                edgeMm: voxelEdgeMm
            ))
        } catch {
            throw Error.volumeEstimationFailed(fixtureID, error)
        }
        let outcome = VoxelCarveEstimator.carve(VoxelCarveEstimator.Inputs(
            grid: grid,
            view1: VoxelCarveView(probabilities: nadirSeg.probabilities,
                                 intrinsics: nadirIntrinsics),
            view2: VoxelCarveView(probabilities: obliqueSeg.probabilities,
                                 intrinsics: obliqueIntrinsics),
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

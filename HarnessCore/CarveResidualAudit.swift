#if HARNESS_ENABLED
import CaptureKit
import Foundation
import Pipeline
import PortableContracts
import Segmentation
import SupportPlane
import Volume

// Splits the two-view carve's residual over-read into the three quantities that
// can each be measured, rather than inferred, on a stored bundle
// (`specs/estimation/two-view-trust/`, `docs/agent-notes/two-view-geometry-audit.md` §7):
//
//   1. the footprint the nadir silhouette hands the carve, in cm² on the
//      support plane — measurable, and comparable to the food's real footprint;
//   2. the vertical extent the grid was given, and the whole distribution of
//      measured food heights behind it, so a percentile choice can be judged
//      against how much food a lower one would clip;
//   3. the visual hull's OWN bias at this bundle's baseline — a box of known
//      size, carved with exact silhouettes through the same estimator, the same
//      intrinsics and the same stored `t_1→2`. The ratio of that carve to the
//      box's voxelised truth is the error no mask and no height bound can
//      remove, because it is what two silhouette cones circumscribe.
//
// With those three the carve's number is accounted for rather than guessed at:
// a carve of a low, convex food is close to a prism over its silhouette, so
//   V ≈ footprint × extent × hullBias
// and every factor on the right is measured here.
public enum CarveResidualAudit {

    // MARK: - Report

    public struct HeightQuantile: Sendable, Encodable {
        public let percentile: Float
        public let heightMm: Float
    }

    /// One (percentile, margin) setting of the grid's vertical bound.
    public struct SweepRow: Sendable, Encodable {
        public let percentile: Float
        public let marginMm: Float
        /// The percentile of the height samples this row used.
        public let heightMm: Float
        /// The grid's actual vertical extent, `dimsZ × edge` after the clamp.
        public let extentMm: Float
        public let dimsZ: Int
        public let carvedCm3: Float
        /// Fraction of the measured food-height samples that sit ABOVE the
        /// extent — the food this bound clips. A percentile only "looks
        /// better" honestly when this stays near the percentile's own tail.
        public let clippedSampleFraction: Float
    }

    /// The visual hull's intrinsic bias at this bundle's geometry.
    public struct SyntheticRow: Sendable, Encodable {
        public let boxMm: [Float]              // L × W × H, grid axes
        public let extentMm: Float
        /// Voxels of the same grid whose centres lie inside the box.
        public let voxelisedTruthCm3: Float
        public let carvedCm3: Float
        /// carved / voxelisedTruth — the hull bias with perfect masks.
        public let hullBias: Float
        /// The box's nadir silhouette re-measured by the same footprint rule
        /// used on the real mask, against the box's true L × W. Validates the
        /// footprint measurement itself.
        public let silhouetteFootprintCm2: Float
        public let trueFootprintCm2: Float
    }

    /// One candidate support plane and everything that follows from it. The
    /// plane is the carve's FLOOR as well as the origin the height field is
    /// measured from, so a plane that sits low both raises the measured food
    /// height and hands the carve a slab of hull under the food. Comparing
    /// the plane the two-view branch fits with the plane the single-view
    /// branch ends on — the one the 267–302 cm³ reference rests on — is the
    /// only way to tell those two effects from a genuine over-read.
    public struct PlaneVariant: Sendable, Encodable {
        public let name: String
        public let reference: String?
        public let distanceMm: Float
        public let residualMm: Float
        public let footprintCm2: Float
        public let medianHeightMm: Float
        public let p98HeightMm: Float
        public let extentMm: Float
        public let carvedCm3: Float
        /// The single-view height-field integral over the SAME nadir frame,
        /// the SAME plane and the SAME silhouette the carve used, cm³. This is
        /// the like-for-like reference: it is a LiDAR measurement of the food's
        /// own surface, so `carvedCm3 / heightFieldCm3` is what the visual hull
        /// adds over the surface, with no capture-to-capture variation in it.
        public let heightFieldCm3: Float
    }

    public struct Report: Sendable, Encodable {
        public let fixtureID: String
        public let capturePath: String
        public let planeReference: String?
        public let planeResidualMm: Float?
        public let nadirFoodPixels: Int
        public let obliqueFoodPixels: Int
        public let nadirFootprintCm2: Float
        public let obliqueFootprintCm2: Float
        public let heightSampleCount: Int
        public let heights: [HeightQuantile]
        public let baselineMm: Float
        public let obliqueRotationDeg: Float
        public let productionCarvedCm3: Float
        public let productionExtentMm: Float
        /// productionCarvedCm3 / (nadirFootprintCm2 × productionExtentMm) — how
        /// far the carve exceeds a straight prism over its own silhouette.
        public let prismFill: Float
        public let sweep: [SweepRow]
        public let synthetic: [SyntheticRow]
        public let planeVariants: [PlaneVariant]
    }

    public struct Options: Sendable {
        public let edgeMm: Float
        public let percentiles: [Float]
        public let marginsMm: [Float]
        /// Synthetic control box, mm, in grid axes (length, width, height).
        public let boxMm: SIMD3<Float>
        public let regularisation: MaskRegularisationConfig
        public let cardExclusion: Bool
        public let reconciliation: Bool

        public init(edgeMm: Float = 3,
                    percentiles: [Float] = [0.90, 0.95, 0.98, 1.0],
                    marginsMm: [Float] = [0, 2, 5],
                    boxMm: SIMD3<Float> = SIMD3(120, 70, 40),
                    regularisation: MaskRegularisationConfig = .standard,
                    cardExclusion: Bool = true,
                    reconciliation: Bool = true) {
            self.edgeMm = edgeMm
            self.percentiles = percentiles
            self.marginsMm = marginsMm
            self.boxMm = boxMm
            self.regularisation = regularisation
            self.cardExclusion = cardExclusion
            self.reconciliation = reconciliation
        }
    }

    /// The nadir-only half of the report: the support plane the bundle fits,
    /// the silhouette footprint on it, and the whole height distribution over
    /// the food mask. Runs on ANY bundle with nadir depth, so the single-view
    /// captures of the same food — the reference the two-view number is judged
    /// against — can be measured with the identical rule.
    public struct HeightProfile: Sendable, Encodable {
        public let fixtureID: String
        public let capturePath: String
        public let planeReference: String?
        public let planeResidualMm: Float?
        public let planeDistanceMm: Float
        public let foodPixels: Int
        public let footprintCm2: Float
        public let sampleCount: Int
        public let heights: [HeightQuantile]
        /// Sum of h over the food mask with each pixel's area at ITS OWN depth
        /// — the single-view height-field integral, cm³. The quantity the
        /// carve is being judged against, computed here from the same mask the
        /// carve's silhouette uses.
        public let heightFieldIntegralCm3: Float
    }

    public enum Error: Swift.Error {
        case notTwoView(String)
        case noNadirDepth(String)
        case noHeightSamples(String)
        case carveFailed(String, VolumeError)
        case gridFailed(String, String)
    }

    // MARK: - Entry point

    public static func audit(
        fixture: PbMealFixture,
        palette: ClassPalette,
        options: Options = Options()
    ) throws -> Report {
        guard fixture.capturePathCanonical == CapturePath.twoViewSfS.rawValue,
              !fixture.obliqueProbs.isEmpty, fixture.hasObliqueIntrinsics else {
            throw Error.notTwoView(fixture.fixtureID)
        }
        guard fixture.hasNadirDepth else { throw Error.noNadirDepth(fixture.fixtureID) }

        let nadirK = CameraIntrinsics(pb: fixture.nadirIntrinsics)
        let obliqueK = CameraIntrinsics(pb: fixture.obliqueIntrinsics)
        let gravity = Vec3(pb: fixture.gravity)
        let depth = DepthMap(pb: fixture.nadirDepth)
        let t1to2 = Mat4(pb: fixture.t1To2)
        let C = palette.totalClasses

        var nadirSeg = FixtureRunner.makeSegResult(
            probsData: fixture.nadirProbs, argmaxData: fixture.nadirArgmax,
            width: nadirK.imageWidth, height: nadirK.imageHeight,
            classes: C, palette: palette, regularisation: options.regularisation)
        var obliqueSeg = FixtureRunner.makeSegResult(
            probsData: fixture.obliqueProbs, argmaxData: fixture.obliqueArgmax,
            width: obliqueK.imageWidth, height: obliqueK.imageHeight,
            classes: C, palette: palette, regularisation: options.regularisation)

        // Stage D exactly as FixtureRunner's two-view branch runs it.
        let plane: SupportPlane
        var planeReference: String?
        var planeResidualMm: Float?
        var supportOffsetMm: Float = 0
        if let fit = try? FixtureRunner.fitSupportPlane(
            depth: depth, intrinsics: nadirK, gravity: gravity,
            foodMask: FixtureRunner.preShutterMask(
                fixture, width: nadirK.imageWidth, height: nadirK.imageHeight)
                ?? FixtureRunner.foodRegionMask(argmax: nadirSeg.argmax, palette: palette),
            fixtureID: fixture.fixtureID) {
            plane = fit.plane
            planeReference = fit.reference?.rawValue
            planeResidualMm = fit.plane.residualMm
            supportOffsetMm = fit.supportOffsetMm
        } else {
            plane = FixtureRunner.nominalPlane(gravity: gravity)
        }

        if options.cardExclusion, let card = try FixtureRunner.pickCard(
            fixture: fixture, intrinsics: nadirK,
            lidarMmPerPx: abs(plane.distanceMm) / ((nadirK.fx + nadirK.fy) / 2)) {
            nadirSeg = nadirSeg.excluding(quad: card.corners.map { SIMD2($0.u, $0.v) }).result
            obliqueSeg = obliqueSeg.excluding(quad: PipelineBridges.projectToOblique(
                card.pose.cornersCameraMm, transform1To2: t1to2, intrinsics: obliqueK)).result
        }
        if options.reconciliation {
            let r = ObjectReconciler.reconcile(
                nadir: nadirSeg, oblique: obliqueSeg, palette: palette, userClass: nil)
            nadirSeg = r.nadir
            obliqueSeg = r.oblique
        }

        let matching = MaskMatcher.match(
            view1: nadirSeg.argmax, view2: obliqueSeg.argmax, palette: palette)
        let foodMask = FixtureRunner.foodRegionMask(argmax: nadirSeg.argmax, palette: palette)

        // (1) footprint on the support plane, from the same label map the carve
        //     uses for its silhouette.
        let nadirFootprint = footprintCm2(
            mask: foodMask, intrinsics: nadirK, plane: plane)
        let obliqueMask = FixtureRunner.foodRegionMask(
            argmax: obliqueSeg.argmax, palette: palette)
        // The oblique footprint is an "as if nadir" figure — the plane is not
        // fronto-parallel to that camera — and is reported only as a relative
        // size check between the two silhouettes, not as a metric area.
        let obliqueFootprint = footprintCm2(
            mask: obliqueMask, intrinsics: obliqueK, plane: plane)

        // (2) the height distribution the bound is drawn from.
        let samples = VoxelGridSizer.foodHeightSamplesMm(
            foodMask: foodMask, depth: depth, intrinsics: nadirK, supportPlane: plane)
        guard samples.count >= VoxelGridSizer.minHeightSampleCount else {
            throw Error.noHeightSamples(fixture.fixtureID)
        }
        let reported: [Float] = [0.02, 0.10, 0.25, 0.5, 0.75, 0.90, 0.95, 0.98, 0.99, 1.0]
        let heights = reported.compactMap { p -> HeightQuantile? in
            VoxelGridSizer.percentile(ofSorted: samples, p).map {
                HeightQuantile(percentile: p, heightMm: $0)
            }
        }

        func carveAt(heightMm: Float, marginMm: Float,
                     plane: SupportPlane) throws -> (Float, VoxelGrid) {
            // `VoxelGridSizer` adds its own `heightMarginMm` and then clamps, so
            // a sweep over the margin is expressed by offsetting the height it
            // is handed: extent = clamp(measured + heightMarginMm) and
            // measured = h + margin − heightMarginMm gives clamp(h + margin)
            // exactly, clamp included. No production constant is touched.
            let offset = heightMm + marginMm - VoxelGridSizer.heightMarginMm
            let grid: VoxelGrid
            do {
                grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
                    foodMask: foodMask, nadirIntrinsics: nadirK, supportPlane: plane,
                    gravityCamera: gravity, edgeMm: options.edgeMm,
                    measuredFoodHeightMm: offset))
            } catch {
                throw Error.gridFailed(fixture.fixtureID, "\(error)")
            }
            let outcome = VoxelCarveEstimator.carve(VoxelCarveEstimator.Inputs(
                grid: grid,
                view1: VoxelCarveView(probabilities: nadirSeg.probabilities,
                                      intrinsics: nadirK, argmax: nadirSeg.argmax),
                view2: VoxelCarveView(probabilities: obliqueSeg.probabilities,
                                      intrinsics: obliqueK, argmax: obliqueSeg.argmax),
                transform1To2: t1to2, supportPlane: plane,
                matchedClasses: matching.matchedClasses,
                singleViewOnlyClassesView1: matching.singleViewOnly(view: 1),
                singleViewOnlyClassesView2: matching.singleViewOnly(view: 2),
                beta: BetaCorrection(), palette: palette))
            guard let est = outcome.estimate else {
                throw Error.carveFailed(fixture.fixtureID,
                                        outcome.refusal ?? .noFoodVolumeRecovered)
            }
            return (est.perClassVolumesCm3.values.reduce(0, +), grid)
        }

        var sweep: [SweepRow] = []
        for p in options.percentiles {
            guard let h = VoxelGridSizer.percentile(ofSorted: samples, p) else { continue }
            for m in options.marginsMm {
                let (volume, grid) = try carveAt(heightMm: h, marginMm: m, plane: plane)
                let extent = grid.verticalExtentMm
                let clipped = Float(samples.filter { $0 > extent }.count) / Float(samples.count)
                sweep.append(SweepRow(
                    percentile: p, marginMm: m, heightMm: h, extentMm: extent,
                    dimsZ: grid.dimsZ, carvedCm3: volume, clippedSampleFraction: clipped))
            }
        }

        // Production setting, for the prism identity.
        let productionHeight = VoxelGridSizer.percentile(
            ofSorted: samples, VoxelGridSizer.heightPercentile) ?? 0
        let (productionVolume, productionGrid) = try carveAt(
            heightMm: productionHeight, marginMm: VoxelGridSizer.heightMarginMm, plane: plane)
        let productionExtent = productionGrid.verticalExtentMm
        let prism = nadirFootprint * productionExtent / 10   // cm² · mm → cm³

        // Plane variants. The two-view branch fits its plane once, from the
        // pre-shutter (or argmax) food mask. The single-view branch — the path
        // that produces the reference number — grows the food region from that
        // first plane and REFITS from the grown mask, keeping the refit only
        // when it lands on `foodSupport` (Decision 3). Run that same sequence
        // here and carve under both, so a plane difference is separated from
        // everything else.
        var planeVariants: [PlaneVariant] = []
        func describe(_ name: String, _ p: SupportPlane, _ reference: String?) throws -> PlaneVariant {
            let s = VoxelGridSizer.foodHeightSamplesMm(
                foodMask: foodMask, depth: depth, intrinsics: nadirK, supportPlane: p)
            let median = VoxelGridSizer.percentile(ofSorted: s, 0.5) ?? 0
            let p98 = VoxelGridSizer.percentile(ofSorted: s, VoxelGridSizer.heightPercentile) ?? 0
            let (volume, grid) = try carveAt(
                heightMm: p98, marginMm: VoxelGridSizer.heightMarginMm, plane: p)
            return PlaneVariant(
                name: name, reference: reference,
                distanceMm: p.distanceMm, residualMm: p.residualMm,
                footprintCm2: footprintCm2(mask: foodMask, intrinsics: nadirK, plane: p),
                medianHeightMm: median, p98HeightMm: p98,
                extentMm: grid.verticalExtentMm, carvedCm3: volume,
                heightFieldCm3: heightFieldIntegralCm3(
                    mask: foodMask, depth: depth, intrinsics: nadirK, plane: p))
        }
        planeVariants.append(try describe("asFitted", plane, planeReference))
        let candidate = FoodRegionGrowth.grow(
            argmax: nadirSeg.argmax, depth: depth, intrinsics: nadirK,
            supportPlane: plane, supportOffsetMm: supportOffsetMm,
            palette: palette, config: .standard, seedPoints: [])
        if candidate.applied,
           let refitted = try? FixtureRunner.fitSupportPlane(
               depth: depth, intrinsics: nadirK, gravity: gravity,
               foodMask: FixtureRunner.foodRegionMask(argmax: candidate.argmax, palette: palette),
               fixtureID: fixture.fixtureID) {
            planeVariants.append(try describe(
                "grownRefit", refitted.plane, refitted.reference?.rawValue))
        }

        // (3) the hull's own bias at this bundle's baseline.
        let synthetic = try syntheticControls(
            boxMm: options.boxMm, referenceGrid: productionGrid,
            nadirK: nadirK, obliqueK: obliqueK, t1to2: t1to2,
            plane: plane, gravity: gravity, edgeMm: options.edgeMm,
            marginsMm: options.marginsMm, fixtureID: fixture.fixtureID)

        return Report(
            fixtureID: fixture.fixtureID,
            capturePath: fixture.capturePathCanonical,
            planeReference: planeReference,
            planeResidualMm: planeResidualMm,
            nadirFoodPixels: foodMask.pixels.reduce(0) { $0 + ($1 != 0 ? 1 : 0) },
            obliqueFoodPixels: obliqueMask.pixels.reduce(0) { $0 + ($1 != 0 ? 1 : 0) },
            nadirFootprintCm2: nadirFootprint,
            obliqueFootprintCm2: obliqueFootprint,
            heightSampleCount: samples.count,
            heights: heights,
            baselineMm: baselineMm(t1to2),
            obliqueRotationDeg: rotationDeg(t1to2),
            productionCarvedCm3: productionVolume,
            productionExtentMm: productionExtent,
            prismFill: prism > 0 ? productionVolume / prism : 0,
            sweep: sweep,
            synthetic: synthetic,
            planeVariants: planeVariants)
    }

    // MARK: - Height profile

    public static func heightProfile(
        fixture: PbMealFixture,
        palette: ClassPalette,
        options: Options = Options()
    ) throws -> HeightProfile {
        guard fixture.hasNadirDepth else { throw Error.noNadirDepth(fixture.fixtureID) }
        let k = CameraIntrinsics(pb: fixture.nadirIntrinsics)
        let gravity = Vec3(pb: fixture.gravity)
        let depth = DepthMap(pb: fixture.nadirDepth)
        let seg = FixtureRunner.makeSegResult(
            probsData: fixture.nadirProbs, argmaxData: fixture.nadirArgmax,
            width: k.imageWidth, height: k.imageHeight,
            classes: palette.totalClasses, palette: palette,
            regularisation: options.regularisation)
        let mask = FixtureRunner.preShutterMask(
            fixture, width: k.imageWidth, height: k.imageHeight)
            ?? FixtureRunner.foodRegionMask(argmax: seg.argmax, palette: palette)
        let plane: SupportPlane
        var reference: String?
        var residual: Float?
        if let fit = try? FixtureRunner.fitSupportPlane(
            depth: depth, intrinsics: k, gravity: gravity,
            foodMask: mask, fixtureID: fixture.fixtureID) {
            plane = fit.plane
            reference = fit.reference?.rawValue
            residual = fit.plane.residualMm
        } else {
            plane = FixtureRunner.nominalPlane(gravity: gravity)
        }
        let foodMask = FixtureRunner.foodRegionMask(argmax: seg.argmax, palette: palette)
        let samples = VoxelGridSizer.foodHeightSamplesMm(
            foodMask: foodMask, depth: depth, intrinsics: k, supportPlane: plane)
        guard samples.count >= VoxelGridSizer.minHeightSampleCount else {
            throw Error.noHeightSamples(fixture.fixtureID)
        }
        let reported: [Float] = [0.02, 0.10, 0.25, 0.5, 0.75, 0.90, 0.95, 0.98, 0.99, 1.0]
        return HeightProfile(
            fixtureID: fixture.fixtureID,
            capturePath: fixture.capturePathCanonical,
            planeReference: reference,
            planeResidualMm: residual,
            planeDistanceMm: plane.distanceMm,
            foodPixels: foodMask.pixels.reduce(0) { $0 + ($1 != 0 ? 1 : 0) },
            footprintCm2: footprintCm2(mask: foodMask, intrinsics: k, plane: plane),
            sampleCount: samples.count,
            heights: reported.compactMap { p in
                VoxelGridSizer.percentile(ofSorted: samples, p).map {
                    HeightQuantile(percentile: p, heightMm: $0)
                }
            },
            heightFieldIntegralCm3: heightFieldIntegralCm3(
                mask: foodMask, depth: depth, intrinsics: k, plane: plane))
    }

    /// Sum over food pixels of (pixel area at the food surface) x (height above
    /// the plane), cm³ — the single-view height-field integral restricted to
    /// the label mask, with no growth and no beta.
    static func heightFieldIntegralCm3(
        mask: BinaryMask, depth: DepthMap, intrinsics k: CameraIntrinsics, plane: SupportPlane
    ) -> Float {
        let fMean = (k.fx + k.fy) / 2
        var totalMm3: Double = 0
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.isFood(x: x, y: y) {
                guard let zt = sampleDepthMm(depth: depth, x: x, y: y,
                                             width: mask.width, height: mask.height),
                      zt > 0 else { continue }
                guard let h = heightAboveSupportPlaneMm(
                    colourX: Float(x), colourY: Float(y), depthMm: zt,
                    intrinsics: k, plane: plane), h > 0 else { continue }
                let du = Float(x) - k.cx, dv = Float(y) - k.cy
                let cosTheta = fMean / (fMean * fMean + du * du + dv * dv).squareRoot()
                let cos3 = cosTheta * cosTheta * cosTheta
                totalMm3 += Double(zt * zt / (k.fx * k.fy * cos3) * h)
            }
        }
        return Float(totalMm3 / 1000)
    }

    static func sampleDepthMm(
        depth: DepthMap, x: Int, y: Int, width: Int, height: Int
    ) -> Float? {
        let dx = min(depth.width - 1, max(0, Int((Float(x) + 0.5) * Float(depth.width) / Float(width))))
        let dy = min(depth.height - 1, max(0, Int((Float(y) + 0.5) * Float(depth.height) / Float(height))))
        let i = dy * depth.width + dx
        guard i < depth.confidenceBytes.count,
              Float(depth.confidenceBytes[i]) / 255 >= 0.4 else { return nil }
        let offset = i * 4
        return depth.depthBytesMm.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
        }
    }

    // MARK: - Synthetic control

    // A box of known size placed on the support plane under the real food,
    // aligned to the real grid's axes, with EXACT silhouettes in both views:
    // a convex solid projects to the convex hull of its projected vertices, so
    // the hull of the eight projected corners IS the silhouette, with no
    // segmenter in the loop. Everything else — intrinsics, the stored t_1→2,
    // the plane, the sizer, the estimator — is the real pipeline.
    static func syntheticControls(
        boxMm: SIMD3<Float>,
        referenceGrid: VoxelGrid,
        nadirK: CameraIntrinsics,
        obliqueK: CameraIntrinsics,
        t1to2: Mat4,
        plane: SupportPlane,
        gravity: Vec3,
        edgeMm: Float,
        marginsMm: [Float],
        fixtureID: String
    ) throws -> [SyntheticRow] {
        // One food class: bg = 1, unknown = 2, liquid = 3 → 4 channels, so the
        // synthetic tensors cost a fraction of a real 34-class one.
        let boxPalette = ClassPalette(
            foodClasses: ["box"], background: 1, unknownFood: 2,
            unsupportedLiquid: 3, version: "carve-residual-audit")

        let base = referenceGrid.originCamera1
        let ax = referenceGrid.axisX, ay = referenceGrid.axisY, az = referenceGrid.axisZ
        var corners: [Vec3] = []
        for sx in [Float(-0.5), 0.5] {
            for sy in [Float(-0.5), 0.5] {
                for sz in [Float(0), 1] {
                    corners.append(base + ax * (sx * boxMm.x)
                                        + ay * (sy * boxMm.y)
                                        + az * (sz * boxMm.z))
                }
            }
        }

        let nadirHull = convexHull(corners.compactMap { project(nadirK, $0) })
        let obliqueHull = convexHull(corners.compactMap {
            project(obliqueK, apply(t1to2, $0))
        })
        guard nadirHull.count >= 3, obliqueHull.count >= 3 else {
            throw Error.gridFailed(fixtureID, "synthetic box does not project into both views")
        }

        let nadirMask = polygonMask(nadirHull, width: nadirK.imageWidth, height: nadirK.imageHeight)
        let obliqueMask = polygonMask(obliqueHull, width: obliqueK.imageWidth, height: obliqueK.imageHeight)
        let nadirView = silhouetteView(nadirMask, intrinsics: nadirK, palette: boxPalette)
        let obliqueView = silhouetteView(obliqueMask, intrinsics: obliqueK, palette: boxPalette)

        var rows: [SyntheticRow] = []
        // The box's true height with each swept margin on top, so the margin's
        // cost is separated from the hull's own bias.
        for margin in marginsMm {
            let offset = boxMm.z + margin - VoxelGridSizer.heightMarginMm
            let grid: VoxelGrid
            do {
                grid = try VoxelGridSizer.size(VoxelGridSizer.Inputs(
                    foodMask: nadirMask, nadirIntrinsics: nadirK, supportPlane: plane,
                    gravityCamera: gravity, edgeMm: edgeMm, measuredFoodHeightMm: offset))
            } catch {
                throw Error.gridFailed(fixtureID, "synthetic grid: \(error)")
            }
            let outcome = VoxelCarveEstimator.carve(VoxelCarveEstimator.Inputs(
                grid: grid, view1: nadirView, view2: obliqueView,
                transform1To2: t1to2, supportPlane: plane,
                matchedClasses: [0], singleViewOnlyClassesView1: [],
                singleViewOnlyClassesView2: [],
                beta: BetaCorrection(), palette: boxPalette))
            guard let est = outcome.estimate else {
                throw Error.carveFailed(fixtureID, outcome.refusal ?? .noFoodVolumeRecovered)
            }
            rows.append(SyntheticRow(
                boxMm: [boxMm.x, boxMm.y, boxMm.z],
                extentMm: grid.verticalExtentMm,
                voxelisedTruthCm3: voxelisedTruthCm3(
                    grid: grid, base: base, ax: ax, ay: ay, az: az, boxMm: boxMm),
                carvedCm3: est.perClassVolumesCm3.values.reduce(0, +),
                hullBias: {
                    let truth = voxelisedTruthCm3(
                        grid: grid, base: base, ax: ax, ay: ay, az: az, boxMm: boxMm)
                    return truth > 0 ? est.perClassVolumesCm3.values.reduce(0, +) / truth : 0
                }(),
                silhouetteFootprintCm2: footprintCm2(
                    mask: nadirMask, intrinsics: nadirK, plane: plane),
                trueFootprintCm2: boxMm.x * boxMm.y / 100))
        }
        return rows
    }

    static func voxelisedTruthCm3(
        grid: VoxelGrid, base: Vec3, ax: Vec3, ay: Vec3, az: Vec3, boxMm: SIMD3<Float>
    ) -> Float {
        var inside = 0
        for iz in 0..<grid.dimsZ {
            for iy in 0..<grid.dimsY {
                for ix in 0..<grid.dimsX {
                    let d = grid.voxelCentre(ix: ix, iy: iy, iz: iz) - base
                    let u = d.dot(ax), v = d.dot(ay), w = d.dot(az)
                    if abs(u) <= boxMm.x / 2, abs(v) <= boxMm.y / 2, w >= 0, w <= boxMm.z {
                        inside += 1
                    }
                }
            }
        }
        let voxelMm3 = Double(grid.edgeMm) * Double(grid.edgeMm) * Double(grid.edgeMm)
        return Float(Double(inside) * voxelMm3 / 1000)
    }

    static func silhouetteView(
        _ mask: BinaryMask, intrinsics: CameraIntrinsics, palette: ClassPalette
    ) -> VoxelCarveView {
        let w = mask.width, h = mask.height, c = palette.totalClasses
        var probs = Data(count: w * h * c * 2)
        var labels = Data(count: w * h)
        probs.withUnsafeMutableBytes { rawP in
            labels.withUnsafeMutableBytes { rawL in
                let p = rawP.bindMemory(to: Float16.self).baseAddress!
                let l = rawL.bindMemory(to: UInt8.self).baseAddress!
                for i in 0..<(w * h) {
                    let food = mask.pixels[i] != 0
                    l[i] = UInt8(food ? 0 : palette.background)
                    let off = i * c
                    for k in 0..<c { p[off + k] = 0 }
                    p[off + 0] = food ? 0.95 : 0.01
                    p[off + palette.background] = food ? 0.05 : 0.99
                }
            }
        }
        return VoxelCarveView(
            probabilities: ProbabilityTensor(
                bytes: probs, height: h, width: w, classes: c, palette: palette),
            intrinsics: intrinsics,
            argmax: ArgmaxMap(pixels: labels, height: h, width: w))
    }

    // MARK: - Geometry helpers
    //
    // Deliberate local copies of Volume's internal §6.0 projection helpers
    // (`projectCamera1`, `applyMat4`): three lines each, and duplicating them
    // is cheaper than widening the estimator's internals for a diagnostic.

    @inline(__always)
    static func project(_ k: CameraIntrinsics, _ p: Vec3) -> SIMD2<Float>? {
        guard p.z < 0 else { return nil }
        return SIMD2(k.fx * p.x / -p.z + k.cx, k.fy * p.y / -p.z + k.cy)
    }

    @inline(__always)
    static func apply(_ m: Mat4, _ p: Vec3) -> Vec3 {
        Vec3(m[col: 0, row: 0] * p.x + m[col: 1, row: 0] * p.y + m[col: 2, row: 0] * p.z + m[col: 3, row: 0],
             m[col: 0, row: 1] * p.x + m[col: 1, row: 1] * p.y + m[col: 2, row: 1] * p.z + m[col: 3, row: 1],
             m[col: 0, row: 2] * p.x + m[col: 1, row: 2] * p.y + m[col: 2, row: 2] * p.z + m[col: 3, row: 2])
    }

    /// Translation length of `t_1→2`, mm — the two views' baseline.
    public static func baselineMm(_ m: Mat4) -> Float {
        let t = Vec3(m[col: 3, row: 0], m[col: 3, row: 1], m[col: 3, row: 2])
        return t.length
    }

    /// Rotation angle of `t_1→2`, degrees — the tilt between the two views.
    public static func rotationDeg(_ m: Mat4) -> Float {
        let trace = m[col: 0, row: 0] + m[col: 1, row: 1] + m[col: 2, row: 2]
        let c = max(-1, min(1, (trace - 1) / 2))
        return acos(c) * 180 / .pi
    }

    /// Metric area of a mask's food pixels on the support plane, cm². Each
    /// pixel contributes the same `z_T² / (f_x f_y cos³θ)` patch the
    /// single-view extrusion integrates, so the figure is the footprint the
    /// carve itself works over.
    static func footprintCm2(
        mask: BinaryMask, intrinsics k: CameraIntrinsics, plane: SupportPlane
    ) -> Float {
        let fMean = (k.fx + k.fy) / 2
        var totalMm2: Double = 0
        for y in 0..<mask.height {
            for x in 0..<mask.width where mask.isFood(x: x, y: y) {
                let dir = Vec3((Float(x) - k.cx) / k.fx, (Float(y) - k.cy) / k.fy, -1).normalised()
                let denom = plane.normal.dot(dir)
                if abs(denom) < 1e-9 { continue }
                let alpha = plane.distanceMm / denom
                if alpha <= 0 { continue }
                let zT = abs((dir * alpha).z)
                let du = Float(x) - k.cx, dv = Float(y) - k.cy
                let cosTheta = fMean / (fMean * fMean + du * du + dv * dv).squareRoot()
                let cos3 = cosTheta * cosTheta * cosTheta
                totalMm2 += Double(zT * zT / (k.fx * k.fy * cos3))
            }
        }
        return Float(totalMm2 / 100)
    }

    /// Monotone-chain convex hull, counter-clockwise in image coordinates.
    static func convexHull(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
        guard points.count >= 3 else { return points }
        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        func cross(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
            (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x)
        }
        var lower: [SIMD2<Float>] = []
        for p in sorted {
            while lower.count >= 2, cross(lower[lower.count - 2], lower[lower.count - 1], p) <= 0 {
                lower.removeLast()
            }
            lower.append(p)
        }
        var upper: [SIMD2<Float>] = []
        for p in sorted.reversed() {
            while upper.count >= 2, cross(upper[upper.count - 2], upper[upper.count - 1], p) <= 0 {
                upper.removeLast()
            }
            upper.append(p)
        }
        lower.removeLast()
        upper.removeLast()
        return lower + upper
    }

    /// Fill a convex polygon (CCW) into a BinaryMask at pixel centres.
    static func polygonMask(_ hull: [SIMD2<Float>], width: Int, height: Int) -> BinaryMask {
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard hull.count >= 3 else { return BinaryMask(pixels: pixels, width: width, height: height) }
        let minY = max(0, Int(hull.map(\.y).min()!.rounded(.down)))
        let maxY = min(height - 1, Int(hull.map(\.y).max()!.rounded(.up)))
        let minX = max(0, Int(hull.map(\.x).min()!.rounded(.down)))
        let maxX = min(width - 1, Int(hull.map(\.x).max()!.rounded(.up)))
        guard minY <= maxY, minX <= maxX else {
            return BinaryMask(pixels: pixels, width: width, height: height)
        }
        for y in minY...maxY {
            for x in minX...maxX {
                let px = Float(x), py = Float(y)
                var inside = true
                for i in 0..<hull.count {
                    let a = hull[i], b = hull[(i + 1) % hull.count]
                    if (b.x - a.x) * (py - a.y) - (b.y - a.y) * (px - a.x) < 0 {
                        inside = false
                        break
                    }
                }
                if inside { pixels[y * width + x] = 1 }
            }
        }
        return BinaryMask(pixels: pixels, width: width, height: height)
    }
}
#endif

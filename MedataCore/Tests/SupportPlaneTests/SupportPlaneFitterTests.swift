import CaptureKit
@testable import CardDetection
import Foundation
import PortableContracts
@testable import SupportPlane
import Testing

// Contract coverage for the SupportPlaneFitter protocol introduced by Decision 9
// and the design's SupportPlaneFitter section. The 2x2 decision table (depth ×
// mask) is exhaustively exercised here so the empty-mask refusal can't drift
// past the protocol entry and into the LiDAR / card dispatch.
@Suite("SupportPlaneFitter protocol contract (Decision 2 / Decision 9)")
struct SupportPlaneFitterTests {

    // MARK: - Empty / nil mask → SupportPlaneError.emptyFoodMask

    @Test("depth nil + mask nil throws emptyFoodMask")
    func depthNilMaskNilThrowsEmpty() throws {
        let fitter = LiDARSupportPlaneFitter()
        let frame = Self.makeFrameNoDepth()
        do {
            _ = try fitter.fit(
                nadir: frame,
                cardPose: nil,
                corners: nil,
                preShutterFoodMask: nil
            )
            Issue.record("expected emptyFoodMask; fit succeeded")
        } catch let error as SupportPlaneError {
            #expect(error == .emptyFoodMask, "expected emptyFoodMask; got \(error)")
        }
    }

    @Test("depth nil + mask empty throws emptyFoodMask")
    func depthNilMaskEmptyThrowsEmpty() throws {
        let fitter = LiDARSupportPlaneFitter()
        let frame = Self.makeFrameNoDepth()
        let emptyMask = BinaryMask(
            pixels: [UInt8](repeating: 0, count: 64 * 64),
            width: 64, height: 64
        )
        do {
            _ = try fitter.fit(
                nadir: frame,
                cardPose: nil,
                corners: nil,
                preShutterFoodMask: emptyMask
            )
            Issue.record("expected emptyFoodMask; fit succeeded")
        } catch let error as SupportPlaneError {
            #expect(error == .emptyFoodMask, "expected emptyFoodMask; got \(error)")
        }
    }

    @Test("depth present + mask nil throws emptyFoodMask")
    func depthPresentMaskNilThrowsEmpty() throws {
        let fitter = LiDARSupportPlaneFitter()
        let fixture = Self.makeLiDARFixture()
        do {
            _ = try fitter.fit(
                nadir: fixture.frame,
                cardPose: nil,
                corners: nil,
                preShutterFoodMask: nil
            )
            Issue.record("expected emptyFoodMask; fit succeeded")
        } catch let error as SupportPlaneError {
            #expect(error == .emptyFoodMask, "expected emptyFoodMask; got \(error)")
        }
    }

    @Test("depth present + mask empty throws emptyFoodMask")
    func depthPresentMaskEmptyThrowsEmpty() throws {
        let fitter = LiDARSupportPlaneFitter()
        let fixture = Self.makeLiDARFixture()
        let emptyMask = BinaryMask(
            pixels: [UInt8](repeating: 0, count: fixture.width * fixture.height),
            width: fixture.width, height: fixture.height
        )
        do {
            _ = try fitter.fit(
                nadir: fixture.frame,
                cardPose: nil,
                corners: nil,
                preShutterFoodMask: emptyMask
            )
            Issue.record("expected emptyFoodMask; fit succeeded")
        } catch let error as SupportPlaneError {
            #expect(error == .emptyFoodMask, "expected emptyFoodMask; got \(error)")
        }
    }

    // MARK: - depth present + non-empty mask → LiDAR branch

    @Test("depth present + non-empty mask runs the LiDAR branch on the fruit-plate fixture")
    func depthPresentMaskNonEmptyRunsLidarBranch() throws {
        let fitter = LiDARSupportPlaneFitter()
        let fixture = Self.makeLiDARFixture()
        // Use a 70 % centred-rectangle mask — the same shape as the (now deleted)
        // Phase 1 placeholder — so the synthetic fixture matches the band that
        // `LiDARPlaneFitter` already exercises in SupportPlaneRoughMaskTests.
        let mask = Self.centreRectMask(
            width: fixture.width,
            height: fixture.height,
            fillFraction: 0.7
        )
        let plane = try fitter.fit(
            nadir: fixture.frame,
            cardPose: nil,
            corners: nil,
            preShutterFoodMask: mask
        )
        // LiDAR fit reports nil for convergedIterations (CardOnlyPlaneFitter
        // reports the iteration count). This is the marker that the LiDAR
        // branch — not the card branch — ran.
        #expect(plane.convergedIterations == nil,
                "LiDAR branch must produce convergedIterations == nil")
        let cosAngle = plane.normal.dot(fixture.frame.gravity)
        let angleRad = acos(max(-1, min(1, cosAngle)))
        #expect(angleRad <= LiDARPlaneFitter.gravityAngleMaxRad,
                "plane normal off-gravity by \(angleRad) rad")
        #expect(plane.residualMm.isFinite, "residual should be finite")
        #expect(plane.residualMm < LiDARPlaneFitter.residualMaxMm,
                "residual \(plane.residualMm) mm exceeds \(LiDARPlaneFitter.residualMaxMm) mm cap")
    }

    // MARK: - depth nil + non-empty mask → the card-only path REFUSES

    // two-view-trust Req 4.4: `CardOnlyPlaneFitter` must be fed the food's lower
    // silhouette edges, not the card's corners and a constant. Until it is, the
    // card-only branch refuses rather than returning an invented plane. It used
    // to back-project the two lower CARD corners as a stand-in for the food's
    // lower silhouette edge and seed one food centroid 20 mm below the card
    // centre, which describes the card's neighbourhood and not the food's
    // contact surface.
    @Test("depth nil + non-empty mask + a valid card pose refuses with noLowerSilhouetteEdges")
    func cardOnlyBranchRefusesEvenWithAValidCardPose() throws {
        let fitter = LiDARSupportPlaneFitter()
        let frame = Self.makeFrameNoDepth()
        let mask = Self.lowerEdgeMask()
        // The same pose and corner fixture the branch used to accept: a card
        // squarely in view, four corners in TL → TR → BR → BL order. Nothing
        // about the inputs is degenerate — the refusal is about what they mean,
        // not about whether they parse.
        let dCard: Float = 300
        let pose = CardPose(
            rotationColumnMajor: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            translationMm: Vec3(0, 0, -dCard),
            scaleAtCardPlaneMmPerPx: 0.2,
            pnpResidualPx: 0,
            cardNormalCameraFrame: Vec3(0, 0, 1)
        )
        let corners: [PixelCorner] = [
            PixelCorner(28, 28),
            PixelCorner(36, 28),
            PixelCorner(36, 34),
            PixelCorner(28, 34)
        ]
        let outcome = fitter.fitOutcome(
            nadir: frame, cardPose: pose, corners: corners, preShutterFoodMask: mask
        )
        #expect(outcome.plane == nil, "the card-only path must not invent a plane")
        #expect(outcome.refusal == .noLowerSilhouetteEdges,
                "expected noLowerSilhouetteEdges; got \(String(describing: outcome.refusal))")
        // A refusal carries no reference and no ring: there is no depth map, so
        // no depth-derived reference exists (Req 6.3 wants the field absent).
        #expect(outcome.stats.reference == nil)
        #expect(outcome.stats.ring == nil)
        #expect(outcome.stats.candidatePlaneCount == nil)
        // -1 is the "refused before a residual was computed" sentinel.
        #expect(outcome.stats.residualMm == -1)
    }

    @Test("the card-only refusal reaches throwing callers as noLowerSilhouetteEdges")
    func cardOnlyRefusalThrowsTheSameCase() throws {
        let fitter = LiDARSupportPlaneFitter()
        do {
            _ = try fitter.fit(
                nadir: Self.makeFrameNoDepth(),
                cardPose: nil, corners: nil,
                preShutterFoodMask: Self.lowerEdgeMask()
            )
            Issue.record("expected noLowerSilhouetteEdges; fit succeeded")
        } catch let error as SupportPlaneError {
            #expect(error == .noLowerSilhouetteEdges, "expected noLowerSilhouetteEdges; got \(error)")
        }
    }

    // The empty-mask gate is at the protocol entry, BEFORE the LiDAR-vs-card
    // dispatch, so an empty mask on a depthless frame still reads emptyFoodMask
    // rather than the card path's refusal. Without this the Pipeline would map
    // a missing food mask to noScaleAvailable instead of noFoodPixels.
    @Test("the empty-mask gate still fires before the dispatch on a depthless frame")
    func emptyMaskGateStillPrecedesTheCardOnlyRefusal() throws {
        let fitter = LiDARSupportPlaneFitter()
        let empty = BinaryMask(
            pixels: [UInt8](repeating: 0, count: 64 * 64), width: 64, height: 64
        )
        let outcome = fitter.fitOutcome(
            nadir: Self.makeFrameNoDepth(), cardPose: nil, corners: nil,
            preShutterFoodMask: empty
        )
        #expect(outcome.refusal == .emptyFoodMask,
                "the empty-mask gate must win over the card-only refusal")
    }

    // MARK: - The depth path is untouched by this change

    // The card arguments reach `fitOutcome` on the depth path too. Nothing on
    // that path may read them: the outcome must be exactly what `fitFromDepth`
    // returns for the same depth map, pose or no pose.
    @Test("a card pose does not change the depth path's outcome by one bit")
    func depthPathIgnoresTheCardArgumentsEntirely() throws {
        let fitter = LiDARSupportPlaneFitter()
        let fixture = Self.makeLiDARFixture()
        let mask = Self.centreRectMask(
            width: fixture.width, height: fixture.height, fillFraction: 0.7
        )
        let pose = CardPose(
            rotationColumnMajor: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            translationMm: Vec3(0, 0, -300),
            scaleAtCardPlaneMmPerPx: 0.2,
            pnpResidualPx: 0,
            cardNormalCameraFrame: Vec3(0, 0, 1)
        )
        let corners: [PixelCorner] = [
            PixelCorner(28, 28), PixelCorner(36, 28),
            PixelCorner(36, 34), PixelCorner(28, 34)
        ]
        let withCard = fitter.fitOutcome(
            nadir: fixture.frame, cardPose: pose, corners: corners,
            preShutterFoodMask: mask
        )
        let withoutCard = fitter.fitOutcome(
            nadir: fixture.frame, cardPose: nil, corners: nil,
            preShutterFoodMask: mask
        )
        let direct = LiDARSupportPlaneFitter.fitFromDepth(
            depth: try #require(fixture.frame.depth),
            intrinsics: fixture.frame.intrinsics,
            mask: mask, gravity: fixture.frame.gravity
        )
        let expected = try #require(direct.plane)
        for outcome in [withCard, withoutCard] {
            let plane = try #require(outcome.plane)
            #expect(plane.normal.x == expected.normal.x)
            #expect(plane.normal.y == expected.normal.y)
            #expect(plane.normal.z == expected.normal.z)
            #expect(plane.distanceMm == expected.distanceMm)
            #expect(plane.residualMm == expected.residualMm)
            #expect(plane.convergedIterations == expected.convergedIterations)
            #expect(outcome.stats == direct.stats)
            #expect(outcome.refusal == nil)
        }
    }

    // MARK: - Fixture helpers

    private struct LiDARFixture {
        let frame: RawFrame
        let width: Int
        let height: Int
    }

    private static func makeLiDARFixture() -> LiDARFixture {
        // Reuses the synthetic depth fixture from SupportPlaneRoughMaskTests: a
        // 64×64 gravity-aligned table at d = 200 mm with a closer plate patch
        // in the centre 70 %×70 % region. Self-contained so this suite does
        // not @testable import the Pipeline-level helper.
        let w = 64, h = 64
        let intrinsics = CameraIntrinsics(
            fx: 200, fy: 200, cx: 32, cy: 32,
            distortion: [], imageWidth: w, imageHeight: h
        )
        let gravity = Vec3(0, 1, 0)
        let tiltRad: Float = 3 * .pi / 180
        let nTable = Vec3(sin(tiltRad), cos(tiltRad), 0)
        let tableD: Float = 200
        let plateD: Float = 150
        let plateXRange = 10..<54
        let plateYRange = 10..<54
        var depthBytes = Data(count: w * h * 4)
        depthBytes.withUnsafeMutableBytes { rawPtr in
            let buf = rawPtr.bindMemory(to: Float.self)
            for y in 0..<h {
                let dirY = (Float(y) - intrinsics.cy) / intrinsics.fy
                for x in 0..<w {
                    let dirX = (Float(x) - intrinsics.cx) / intrinsics.fx
                    let isPlate = plateXRange.contains(x) && plateYRange.contains(y)
                    if isPlate {
                        buf[y * w + x] = plateD
                    } else {
                        let denom = nTable.x * dirX + nTable.y * dirY
                        if denom > 0 {
                            let jitter = sin(Float(y) * 0.7 + Float(x) * 0.3) * 0.2
                            buf[y * w + x] = tableD / denom + jitter
                        } else {
                            buf[y * w + x] = 0
                        }
                    }
                }
            }
        }
        let depth = DepthMap(
            depthBytesMm: depthBytes,
            confidenceBytes: Data(repeating: 255, count: w * h),
            width: w, height: h, rowStrideBytes: w * 4,
            depthIntrinsics: intrinsics,
            depthFromColour: .identity
        )
        let frame = RawFrame(
            imageBytes: Data(repeating: 0, count: w * h * 4),
            pixelFormat: .bgra8,
            colourSpace: .sRGB,
            orientation: 1,
            imageWidth: w, imageHeight: h,
            timestampMonotonicNs: 1,
            intrinsics: intrinsics,
            gravity: gravity,
            worldFromCamera: .identity,
            depth: depth
        )
        return LiDARFixture(frame: frame, width: w, height: h)
    }

    // A minimal non-empty mask: one row of food pixels. The card-only path never
    // consumed the mask — that is the defect Req 4.4 names — so its only job here
    // is to get past the protocol's empty-mask gate.
    private static func lowerEdgeMask() -> BinaryMask {
        var pixels = [UInt8](repeating: 0, count: 64 * 64)
        for x in 24..<40 { pixels[24 * 64 + x] = 1 }
        return BinaryMask(pixels: pixels, width: 64, height: 64)
    }

    private static func makeFrameNoDepth() -> RawFrame {
        let w = 64, h = 64
        let intrinsics = CameraIntrinsics(
            fx: 200, fy: 200, cx: 32, cy: 32,
            distortion: [], imageWidth: w, imageHeight: h
        )
        return RawFrame(
            imageBytes: Data(repeating: 0, count: w * h * 4),
            pixelFormat: .bgra8,
            colourSpace: .sRGB,
            orientation: 1,
            imageWidth: w, imageHeight: h,
            timestampMonotonicNs: 1,
            intrinsics: intrinsics,
            gravity: Vec3(0, 1, 0),
            worldFromCamera: .identity,
            depth: nil
        )
    }

    private static func centreRectMask(
        width: Int, height: Int, fillFraction: Float
    ) -> BinaryMask {
        let border = (1 - fillFraction) / 2
        let xMin = Int((border * Float(width)).rounded(.up))
        let xMax = Int(((1 - border) * Float(width)).rounded(.down))
        let yMin = Int((border * Float(height)).rounded(.up))
        let yMax = Int(((1 - border) * Float(height)).rounded(.down))
        var pixels = [UInt8](repeating: 0, count: width * height)
        if xMin < xMax && yMin < yMax {
            for y in yMin..<yMax {
                let rowBase = y * width
                for x in xMin..<xMax {
                    pixels[rowBase + x] = 1
                }
            }
        }
        return BinaryMask(pixels: pixels, width: width, height: height)
    }
}

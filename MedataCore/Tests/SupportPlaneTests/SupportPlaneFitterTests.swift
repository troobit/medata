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

    // MARK: - depth nil + non-empty mask → CardOnly branch

    @Test("depth nil + non-empty mask + valid card pose runs the CardOnly branch")
    func depthNilMaskNonEmptyRunsCardOnlyBranch() throws {
        let fitter = LiDARSupportPlaneFitter()
        let frame = Self.makeFrameNoDepth()
        // Minimal non-empty mask. The CardOnly fitter does not consume the mask;
        // the protocol's empty-mask gate only checks that it is non-empty.
        let mask = BinaryMask(
            pixels: {
                var p = [UInt8](repeating: 0, count: 64 * 64)
                for x in 24..<40 { p[24 * 64 + x] = 1 }
                return p
            }(),
            width: 64, height: 64
        )
        // Build a card pose + corners that the CardOnlyPlaneFitter accepts.
        // Using the same fixture shape as `CardOnlyPlaneFitterTests`.
        let dCard: Float = 300
        let pose = CardPose(
            rotationColumnMajor: [1, 0, 0, 0, 1, 0, 0, 0, 1],
            translationMm: Vec3(0, 0, -dCard),
            scaleAtCardPlaneMmPerPx: 0.2,
            pnpResidualPx: 0,
            cardNormalCameraFrame: Vec3(0, 0, 1)
        )
        // Corner order TL → TR → BR → BL; only the lower two corners
        // (BR, BL) are read by Pipeline.fitSupportPlane's CardOnly branch.
        let corners: [PixelCorner] = [
            PixelCorner(28, 28),
            PixelCorner(36, 28),
            PixelCorner(36, 34),
            PixelCorner(28, 34)
        ]
        let plane = try fitter.fit(
            nadir: frame,
            cardPose: pose,
            corners: corners,
            preShutterFoodMask: mask
        )
        // CardOnly fit reports a finite iteration count.
        #expect(plane.convergedIterations != nil,
                "CardOnly branch must populate convergedIterations")
        #expect(plane.residualMm.isFinite, "residual should be finite")
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

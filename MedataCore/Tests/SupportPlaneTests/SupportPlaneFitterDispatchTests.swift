import CaptureKit
import Foundation
import PortableContracts
@testable import SupportPlane
import Testing

// Task 9: the fitter's restricted-then-edge-band dispatch and the lazy fallback
// (Reqs 4.1–4.3, 6.1).
//
// The ordering is Decision 5's: the restricted fit is attempted FIRST and the
// edge-band fit runs only on the rejection path. Laziness is observable through
// the food bbox — `LiDARPlaneFitter.collectCandidatePoints` is the only thing that
// resolves it, so a bbox still at the -1 sentinel on a `.foodSupport` outcome means
// the edge-band scan never ran.
@Suite("SupportPlaneFitter dispatch and lazy fallback (Reqs 4.1-4.3, 6.1)")
struct SupportPlaneFitterDispatchTests {

    // MARK: – The restricted fit runs first and wins

    @Test("a plate above a table takes the restricted fit, and the edge-band scan never runs")
    func restrictedFitWinsAndTheEdgeBandScanIsSkipped() throws {
        let scene = SPRScene.plateAboveTable()
        let outcome = Self.fitOutcome(scene)

        let plane = try #require(outcome.plane)
        #expect(outcome.stats.reference == .foodSupport)
        #expect(abs(SPRScene.heightMm(of: plane) - 20) < 1,
                "expected the plate top; got \(SPRScene.heightMm(of: plane)) mm above the table")
        // Req 6.1: the ring measure is recorded on every depth-derived attempt.
        let ring = try #require(outcome.stats.ring)
        #expect(abs(ring.medianMm) < 1, "a correct fit reads a ring median of ~0")
        #expect(outcome.stats.candidatePlaneCount == 2)
        // The edge-band collector is what resolves the bbox; still at the sentinel
        // means it was never called (Decision 5's lazy fallback).
        #expect(outcome.stats.foodBBoxX == -1,
                "the edge-band scan ran on the success path — the fallback is not lazy")
    }

    @Test("candidate and inlier counts on a .foodSupport row are NATIVE DEPTH SAMPLES")
    func foodSupportCountsAreNativeDepthSamples() throws {
        let scene = SPRScene.plateAboveTable()
        let outcome = Self.fitOutcome(scene)
        #expect(outcome.stats.reference == .foodSupport)
        // The whole depth grid is 256x192 = 49_152 samples, so a colour-grid count
        // (786_432 pixels, ~56x more) cannot fit inside it. This is the assertion
        // that pins the units the design warns must never be compared across
        // references.
        #expect(outcome.stats.candidatePointCount > 0)
        #expect(outcome.stats.candidatePointCount
                <= SPRScene.depthWidth * SPRScene.depthHeight)
        #expect(outcome.stats.inlierCount > 0)
        #expect(outcome.stats.inlierCount <= outcome.stats.candidatePointCount)
    }

    // MARK: – Rejection falls back to the pre-feature plane, unchanged

    // Food across a flat plate's edge is rejected on sectors (Decision 18), so this
    // scene reaches the fallback through the selection path rather than through a
    // starved ring.
    @Test("a rejected restricted fit falls back to a byte-identical edge-band plane")
    func fallbackPlaneIsIdenticalToTheEdgeBandFit() throws {
        let scene = SPRScene.foodAcrossPlateEdge(edgeOffsetPx: 2)
        #expect(SPRScene.fit(scene) == nil, "precondition: the restricted fit must reject")

        let outcome = Self.fitOutcome(scene)
        let plane = try #require(outcome.plane)
        #expect(outcome.stats.reference == .edgeBand)

        let direct = LiDARPlaneFitter.fitOutcome(LiDARPlaneFitter.Inputs(
            depth: SPRScene.makeDepth(scene),
            colourIntrinsics: SPRScene.colourIntrinsics,
            foodRegionMask: SPRScene.makeColourMask(scene),
            gravityCamera: SPRScene.gravity
        ))
        let expected = try #require(direct.plane)
        #expect(plane.normal.x == expected.normal.x)
        #expect(plane.normal.y == expected.normal.y)
        #expect(plane.normal.z == expected.normal.z)
        #expect(plane.distanceMm == expected.distanceMm)
        #expect(plane.residualMm == expected.residualMm)
        #expect(plane.convergedIterations == expected.convergedIterations)
        // Decision 12: the persisted residual stays the MEASURED residual. Nothing
        // on the fallback path rewrites it — the confidence penalty is a separate,
        // multiplicative factor on sigmaPlane.
        #expect(outcome.stats.residualMm == expected.residualMm)
    }

    // Req 6.2's before/after comparison is unexecutable unless the ring measure is
    // computed on the fallback path too.
    @Test("ring statistics are recorded on the fallback path as well")
    func fallbackPathStillRecordsRingStatistics() throws {
        let scene = SPRScene.foodAcrossPlateEdge(edgeOffsetPx: 2)
        let outcome = Self.fitOutcome(scene)
        #expect(outcome.stats.reference == .edgeBand)
        let ring = try #require(outcome.stats.ring,
                                "Req 6.1 requires the ring measure on every depth-derived attempt")
        #expect(ring.bandMedianMm.count == SupportRegion.ringBandCount)
        #expect(ring.supportingSectors >= 0)
        // No candidate planes were selected, so the count is a `.foodSupport`
        // quantity and must be absent rather than zero on this row.
        #expect(outcome.stats.candidatePlaneCount == nil)
    }

    // MARK: – Refusal conditions are unchanged (Req 4.2)

    @Test("a depth map with no valid returns refuses exactly as the edge-band fit does")
    func refusalConditionsAreUnchanged() throws {
        let scene = SPRScene.plateAboveTable()
        let blank = DepthMap(
            depthBytesMm: Data(count: SPRScene.depthWidth * SPRScene.depthHeight * 4),
            confidenceBytes: Data(repeating: 255,
                                  count: SPRScene.depthWidth * SPRScene.depthHeight),
            width: SPRScene.depthWidth, height: SPRScene.depthHeight,
            rowStrideBytes: SPRScene.depthWidth * 4,
            depthIntrinsics: CameraIntrinsics(
                fx: 0, fy: 0, cx: 0, cy: 0, distortion: [],
                imageWidth: SPRScene.depthWidth, imageHeight: SPRScene.depthHeight
            ),
            depthFromColour: .identity
        )
        let mask = SPRScene.makeColourMask(scene)
        let frame = RawFrame(
            imageBytes: Data(count: SPRScene.colourWidth * SPRScene.colourHeight * 4),
            pixelFormat: .bgra8, colourSpace: .sRGB, orientation: 1,
            imageWidth: SPRScene.colourWidth, imageHeight: SPRScene.colourHeight,
            timestampMonotonicNs: 1,
            intrinsics: SPRScene.colourIntrinsics, gravity: SPRScene.gravity,
            worldFromCamera: .identity, depth: blank
        )
        let outcome = LiDARSupportPlaneFitter().fitOutcome(
            nadir: frame, cardPose: nil, corners: nil, preShutterFoodMask: mask
        )
        let direct = LiDARPlaneFitter.fitOutcome(LiDARPlaneFitter.Inputs(
            depth: blank, colourIntrinsics: SPRScene.colourIntrinsics,
            foodRegionMask: mask, gravityCamera: SPRScene.gravity
        ))
        #expect(outcome.plane == nil)
        #expect(outcome.refusal == direct.refusal,
                "the pipeline Req 4.5 refusal set must be unchanged")
        #expect(outcome.stats.reference == .edgeBand)
    }

    @Test("the card-only path records no plane reference at all")
    func cardOnlyPathRecordsNoReference() throws {
        // No depth map means no depth-derived reference exists; the field is absent
        // rather than defaulted, which is the distinction Req 6.3 preserves.
        let frame = RawFrame(
            imageBytes: Data(count: 64 * 64 * 4),
            pixelFormat: .bgra8, colourSpace: .sRGB, orientation: 1,
            imageWidth: 64, imageHeight: 64,
            timestampMonotonicNs: 1,
            intrinsics: CameraIntrinsics(fx: 200, fy: 200, cx: 32, cy: 32,
                                         distortion: [], imageWidth: 64, imageHeight: 64),
            gravity: Vec3(0, 1, 0),
            worldFromCamera: .identity, depth: nil
        )
        var pixels = [UInt8](repeating: 0, count: 64 * 64)
        for x in 24..<40 { pixels[24 * 64 + x] = 1 }
        let outcome = LiDARSupportPlaneFitter().fitOutcome(
            nadir: frame, cardPose: nil, corners: nil,
            preShutterFoodMask: BinaryMask(pixels: pixels, width: 64, height: 64)
        )
        #expect(outcome.stats.reference == nil)
        #expect(outcome.stats.ring == nil)
    }

    // MARK: – Helpers

    private static func fitOutcome(_ grid: SPRScene.Grid) -> SupportPlaneFitOutcome {
        LiDARSupportPlaneFitter().fitOutcome(
            nadir: SPRScene.makeFrame(grid),
            cardPose: nil,
            corners: nil,
            preShutterFoodMask: SPRScene.makeColourMask(grid)
        )
    }
}

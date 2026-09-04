import CaptureKit
import Foundation
import PortableContracts
@testable import SupportPlane
import Testing

// Task 5: bounded candidate sampling and CC-RANSAC extraction (Reqs 2.2, 2.3, 2.4).
@Suite("SupportRegion bounded sampling and CC-RANSAC (Reqs 2.2, 2.3, 2.4)")
struct SupportRegionCandidateTests {

    // MARK: – The bound (Decision 15)

    // The candidate set is an ANNULUS of annulusOuterMm around the food mask — not
    // dilate(foodMask, 2 x foodRadius), which spans ~8.3 s^2 against the pre-feature
    // four-band scan's ~4 s^2 and is therefore looser than the code it replaces.
    @Test("clutter outside the food's neighbourhood cannot become a candidate")
    func clutterOutsideTheAnnulusIsNotACandidate() throws {
        // A large co-height slab in the frame corner, far outside the annulus.
        let scene = SPRScene.grid { x, y in
            let r = SPRScene.radius(x, y, centreX: 128, centreY: 96)
            if r <= 12.5 { return (28, true) }
            if r <= 28 { return (20, false) }
            if x > 200 && y > 150 { return (20, false) }   // the distractor
            return (0, false)
        }
        let measured = try #require(SPRScene.measure(scene))
        let distances = SupportRegion.distanceToFoodPx(mask: measured.geometry.foodMask)

        var distractorSamples = 0
        for index in measured.samples.annulus {
            let x = index % scene.width, y = index / scene.width
            if x > 200 && y > 150 { distractorSamples += 1 }
            #expect(distances[index] * measured.geometry.mmPerPx <= 2 * SupportRegion.ringOuterMm + 1e-3)
        }
        #expect(distractorSamples == 0, "\(distractorSamples) distractor samples entered the candidate set")
    }

    @Test("the annulus is tighter than the pre-feature four-band scan")
    func annulusIsTighterThanTheBandScan() throws {
        let scene = SPRScene.plateAboveTable()
        let measured = try #require(SPRScene.measure(scene))

        var stats = SupportPlaneFitStats()
        let bandPoints = LiDARPlaneFitter.collectCandidatePoints(
            .init(depth: SPRScene.makeDepth(scene), colourIntrinsics: SPRScene.colourIntrinsics,
                  foodRegionMask: SPRScene.makeColourMask(scene), gravityCamera: SPRScene.gravity),
            stats: &stats
        )
        // Req 2.4: sufficiency is assessed in independent depth samples. The band scan
        // enumerates the colour grid, replicating each depth measurement ~16x on these
        // scenes and ~56x on device, which is what inflated every count derived from
        // it. The comparison below is therefore of counts, not of areas.
        #expect(measured.samples.annulus.count < bandPoints.count / 4,
                "annulus \(measured.samples.annulus.count) vs band scan \(bandPoints.count)")
    }

    // MARK: – Component scoring (Decision 13)

    @Test("component labelling returns the largest 8-connected blob, not the total")
    func largestComponentIgnoresDisconnectedBlobs() {
        let width = 32, height = 32
        let scratch = SupportRegion.ComponentScratch(width: width, height: height)
        var indices: [Int] = []
        for y in 2..<6 { for x in 2..<7 { indices.append(y * width + x) } }      // 20 px
        for y in 20..<24 { for x in 20..<22 { indices.append(y * width + x) } }  // 8 px
        indices.sort()

        let component = scratch.largestComponent(of: indices)
        #expect(component.size == 20, "expected the 20-pixel blob; got \(component.size) of \(indices.count)")
        #expect(component.members.count == 20)
        #expect(component.minExtentPx == 4, "bbox is 5x4; the min extent is 4")
        #expect(component.members == component.members.sorted(), "members must be ascending for stable comparison")
    }

    @Test("8-connectivity joins diagonal neighbours")
    func componentUsesEightConnectivity() {
        let width = 16
        let scratch = SupportRegion.ComponentScratch(width: width, height: 16)
        let indices = [5 * width + 5, 6 * width + 6, 7 * width + 7].sorted()
        #expect(scratch.largestComponent(of: indices).size == 3)
    }

    // A co-height board elsewhere in the annulus lies exactly on the plate's plane, so
    // it is an inlier by distance and a separate blob by connectivity. Scoring on raw
    // inlier count would credit it; scoring on the largest component does not.
    @Test("a co-height board is an inlier of the plate plane but not part of its component")
    func coHeightBoardIsExcludedFromTheComponent() throws {
        let scene = SPRScene.plateWithCoHeightBoard()
        let measured = try #require(SPRScene.measure(scene))
        var rng = SplitMix64(seed: Fnv1a64.hash(SPRScene.makeDepth(scene).depthBytesMm))
        let candidates = SupportRegion.extractCandidates(
            annulus: measured.samples.annulus, geometry: measured.geometry,
            gravity: SPRScene.gravity, rng: &rng
        )
        let plate = try #require(candidates.first { abs(SPRScene.tableDepthMm + $0.d / $0.normal.z - 20) < 1 })

        let rawInliers = measured.samples.annulus.filter {
            abs(plate.normal.dot(measured.geometry.points[$0]) - plate.d) < LiDARPlaneFitter.inlierBandMm
        }.count
        #expect(plate.componentSize < rawInliers,
                "component \(plate.componentSize) must be smaller than the raw inlier count \(rawInliers)")
        // The board is roughly 600 px; the component must have shed at least that.
        #expect(rawInliers - plate.componentSize > 400)
    }

    // MARK: – Adaptive iterations

    // maxIterations = 256 was sized to find the DOMINANT plane and must not be
    // inherited on faith: P(clean triple) is 98 % at w = 0.25 but 3 % at w = 0.05.
    @Test("iteration count is derived from the observed inlier ratio, not fixed at 256")
    func adaptiveIterationsDeriveFromTheInlierRatio() {
        let high = SupportRegion.requiredIterations(inlierRatio: 0.9)
        let mid = SupportRegion.requiredIterations(inlierRatio: 0.5)
        let low = SupportRegion.requiredIterations(inlierRatio: 0.25)
        let starved = SupportRegion.requiredIterations(inlierRatio: 0.05)

        #expect(high < mid && mid < low && low < starved, "\(high), \(mid), \(low), \(starved)")
        #expect(high <= 10, "a 0.9 inlier ratio needs a handful of draws; got \(high)")
        #expect(mid != 256 && low != 256, "the budget must not be the inherited constant")
        #expect(starved == SupportRegion.maxIterationsPerPass,
                "a 5 % ratio must saturate the cap rather than stopping early")
        #expect(SupportRegion.requiredIterations(inlierRatio: 0) == SupportRegion.maxIterationsPerPass)
    }

    // MARK: – Sequential extraction

    // The iteration budget is sufficient because pass 1 removes the table, and it is
    // the plate's fraction OF THE RESIDUE that pass 2's formula applies to.
    @Test("sequential extraction removes the table first and surfaces the plate next")
    func sequentialExtractionSurfacesThePlate() throws {
        let scene = SPRScene.plateAboveTable()
        let measured = try #require(SPRScene.measure(scene))
        var rng = SplitMix64(seed: Fnv1a64.hash(SPRScene.makeDepth(scene).depthBytesMm))
        let candidates = SupportRegion.extractCandidates(
            annulus: measured.samples.annulus, geometry: measured.geometry,
            gravity: SPRScene.gravity, rng: &rng
        )
        let heights = candidates.map { SPRScene.tableDepthMm + $0.d / $0.normal.z }

        #expect(candidates.count == 2, "expected the table and the plate; got \(heights)")
        #expect(abs(heights[0]) < 1, "pass 1 must take the table; got \(heights[0])")
        #expect(abs(heights[1] - 20) < 1, "pass 2 must take the plate; got \(heights[1])")
        #expect(candidates[1].residueInlierRatio > 0.9,
                "the plate is nearly all of the residue once the table is removed")
        #expect(candidates.count <= SupportRegion.maxCandidatePlanes)
    }

    @Test("extraction is deterministic for identical depth bytes")
    func extractionIsDeterministic() throws {
        let scene = SPRScene.plateAboveTable()
        let measured = try #require(SPRScene.measure(scene))

        func run() -> [SupportRegion.PlaneCandidate] {
            var rng = SplitMix64(seed: Fnv1a64.hash(SPRScene.makeDepth(scene).depthBytesMm))
            return SupportRegion.extractCandidates(
                annulus: measured.samples.annulus, geometry: measured.geometry,
                gravity: SPRScene.gravity, rng: &rng
            )
        }
        let first = run(), second = run()
        #expect(first.count == second.count)
        for (a, b) in zip(first, second) {
            #expect(a.d == b.d && a.normal == b.normal)
            #expect(a.componentSize == b.componentSize && a.extentPx == b.extentPx)
        }
    }
}

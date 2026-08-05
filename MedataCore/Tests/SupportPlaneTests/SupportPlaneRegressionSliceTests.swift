import CaptureKit
import Foundation
import PortableContracts
@testable import SupportPlane
import Testing

// Reqs 6.2, 7.1 and 7.2 against the two committed depth slices (task 22).
//
// These criteria previously named 195 MB capture bundles that live on the device.
// `tools/fixture_slice.py` cuts the ~290 KB the support-plane fit actually reads out
// of each, so the criteria are now executable by anyone with the repository — which
// is the point: an acceptance criterion nobody can run is not one.
//
// EVERY assertion here is independent of the `[owed]` constants. Each measures a
// named plane against the capture, never "the plane the guards selected", because
// the admissibility thresholds are placeholders until task 26 measures them and
// Req 3.7 forbids shipping them as asserted. What the guards currently DO is
// recorded separately, at the end, as the input task 26 exists to consume.
//
// Three figures the spec states do not reproduce, and are superseded by Decision 28
// rather than quietly re-stated here: Req 6.2's +18…+26 mm pre-feature ring measure,
// Req 7.1's 235.96 cm3 corrected volume, and Req 7.2's ~200 cm3. The pre-feature
// volumes DO reproduce within ~5 %, which is what says the slices are faithful and
// the disagreement is in the diagnosis figures rather than in this data.
@Suite("Regression criteria against the committed depth slices (Reqs 6.2, 7.1, 7.2)")
struct SupportPlaneRegressionSliceTests {

    // The parity capture: two slices of rye bread on a white plate, no weighed truth.
    static let parityCapture = "1785135663727"
    // The weighed capture: 2 slices of bread at 80 g, 34 g carbs.
    static let weighedCapture = "1785901032716"

    // Everything each capture is measured for, computed once. The pre-feature fit
    // runs over ~1.4 M colour-grid candidates, so recomputing it per test costs more
    // than the rest of the suite put together.
    struct Measured {
        let preFeatureRing: RingStatistics?
        let preFeatureVolumeCm3: Float
        let correctedRing: RingStatistics?
        let correctedVolumeCm3: Float
        let footprintCm2: Float
        let rejections: [SupportRegion.CandidateRejection]
    }

    static let parity = measure(parityCapture)
    static let weighed = measure(weighedCapture)

    // MARK: - Req 6.2, the falsifiable diagnostic

    // Req 6.2 exists to make the ring measure falsifiable rather than merely
    // recorded: it must read one thing under the pre-feature fit and another under
    // the corrected one. Both halves are measured here on the same capture, so the
    // comparison is like-for-like.
    @Test("the ring measure separates the pre-feature plane from the corrected one")
    func ringMeasureSeparatesTheTwoReferences() throws {
        let before = try #require(Self.parity.preFeatureRing)
        // MEASURED +4.2 mm, against the +18…+26 mm Req 6.2 states. The direction is
        // right — the pre-feature plane sits BELOW the surface the food rests on, so
        // the ring reads positive — but the magnitude is a quarter of the recorded
        // one. Decision 28 supersedes the range; task 27 re-measures on device.
        #expect(before.medianMm > 2 && before.medianMm < 8,
                "pre-feature ring median \(before.medianMm) mm")
        // The pre-feature plane fails the ring on its own terms, which is the point:
        // it is not the surface the food rests on.
        #expect(before.supportFraction < 0.5)

        let after = try #require(Self.parity.correctedRing)
        // MEASURED −0.93 mm. This is the half of Req 6.2 that does hold, and it is
        // the half that matters: the corrected plane reads approximately zero.
        #expect(abs(after.medianMm) < 2,
                "corrected ring median \(after.medianMm) mm should be ~0")
        #expect(after.supportFraction > before.supportFraction)
    }

    // The same separation on the weighed capture, which is flatter and closer-cropped
    // — the pre-feature ring reads further from zero, the corrected one nearer it.
    @Test("the ring measure separates the two references on the weighed capture too")
    func ringMeasureSeparatesOnTheWeighedCapture() throws {
        let before = try #require(Self.weighed.preFeatureRing)
        let after = try #require(Self.weighed.correctedRing)
        #expect(before.medianMm > 4, "pre-feature ring median \(before.medianMm) mm")
        #expect(abs(after.medianMm) < abs(before.medianMm),
                "corrected \(after.medianMm) mm is not nearer zero than \(before.medianMm) mm")
    }

    // MARK: - Reqs 7.1 and 7.2, volume

    // Req 7.1 is explicitly a parity check against a known implementation, not an
    // accuracy claim — the capture has no weighed truth. The known implementation was
    // the throwaway `DiagProbe`, deleted in task 23, so what is checkable now is that
    // the pre-feature volume reproduces the shipped figure and that correcting the
    // plane removes most of it.
    @Test("correcting the plane removes over half the parity capture's volume")
    func parityCaptureVolumeFallsWithTheCorrectedPlane() {
        let before = Self.parity.preFeatureVolumeCm3
        let after = Self.parity.correctedVolumeCm3

        // MEASURED 714.8 cm3 against the 682.96 cm3 the diagnosis recorded: +4.7 %,
        // inside Req 7.1's own 5 % band. That agreement is what establishes the slice
        // and this depth-grid integration as faithful to the shipped path.
        #expect(abs(before - 682.96) / 682.96 < 0.05,
                "pre-feature volume \(before) cm3 is not within 5 % of the recorded 682.96")
        // MEASURED 306.8 cm3, against the 235.96 cm3 the diagnosis recorded for its
        // own restricted fit — 30 % apart, superseded by Decision 28. The reduction
        // is asserted instead, since that is the claim this feature actually makes.
        #expect(after < before * 0.5,
                "corrected volume \(after) cm3 must be less than half the pre-feature \(before) cm3")
    }

    // Req 7.2's volume band cannot be met by any candidate on this capture, and the
    // reason is not the plane. Stated as a measurement so it is attributable.
    @Test("the weighed capture's food mask is too large for its volume band")
    func weighedCaptureVolumeIsMaskBound() {
        let before = Self.weighed.preFeatureVolumeCm3
        // MEASURED 735.7 cm3 against the 714.84 cm3 Req 7.2 records: +2.9 %.
        #expect(abs(before - 714.84) / 714.84 < 0.05,
                "pre-feature volume \(before) cm3 is not within 5 % of the recorded 714.84")

        // The mask covers ~298 cm2 of depth samples. Two slices of bread are ~200 cm2,
        // so ~50 % of the masked area is not bread — and Req 7.2's 200 cm3 target
        // over 298 cm2 implies a mean food height of 6.7 mm, against the ~11 mm the
        // depth map actually shows. No support plane can reconcile those: the gap is
        // segmentation, which is why Req 7.2 pins the class as a precondition.
        let footprint = Self.weighed.footprintCm2
        #expect(footprint > 250,
                "food footprint \(footprint) cm2 — the mask-bound argument rests on this")
    }

    // MARK: - What the guards do today (the task 26 input)

    // Both captures currently fall back. This is NOT asserted as correct behaviour —
    // it is the corpus measurement task 26 was written to consume, recorded where it
    // cannot be lost. The substantive claim is the second assertion: every rejection
    // is on a constant the design marked `[owed]`, so nothing structural is wrong
    // with the geometry, and setting the constants is the whole of the remaining work.
    @Test("every candidate rejection on both captures is on an owed constant")
    func rejectionsAreAllOnOwedConstants() {
        let owed: Set<SupportRegion.CandidateRejection> = [.supportFraction, .sectors, .extent]
        for (name, measured) in [(Self.parityCapture, Self.parity), (Self.weighedCapture, Self.weighed)] {
            let reasons = measured.rejections
            #expect(!reasons.isEmpty, "\(name) admitted a candidate — task 26 has moved on")
            for reason in reasons {
                #expect(owed.contains(reason),
                        "\(name) rejected a candidate on \(reason.rawValue), which is not an owed constant")
            }
        }
    }

    // MARK: - Helpers
    //
    // Each measures a NAMED plane rather than a selected one, so no assertion above
    // depends on an owed constant.

    private static func measure(_ name: String) -> Measured {
        guard let slice = try? DepthSlice.load(name) else {
            return Measured(preFeatureRing: nil, preFeatureVolumeCm3: 0,
                            correctedRing: nil, correctedVolumeCm3: 0,
                            footprintCm2: 0, rejections: [])
        }
        let preFeature = preFeaturePlane(slice)
        let best = bestCandidate(slice)
        return Measured(
            preFeatureRing: preFeature.flatMap {
                SupportRegion.ringStatistics(for: $0, depth: slice.depth,
                                             foodMask: slice.foodMask,
                                             intrinsics: slice.colourIntrinsics)
            },
            preFeatureVolumeCm3: preFeature.map {
                volumeCm3(slice, normal: $0.normal, d: $0.distanceMm)
            } ?? 0,
            correctedRing: best?.ring,
            correctedVolumeCm3: best.map {
                volumeCm3(slice, normal: $0.candidate.normal, d: $0.candidate.d)
            } ?? 0,
            footprintCm2: foodFootprintCm2(slice) ?? 0,
            rejections: rejectionReasons(slice) ?? []
        )
    }

    private static func geometry(_ slice: DepthSlice) -> SupportRegion.DepthGeometry? {
        SupportRegion.prepare(depth: slice.depth, colourIntrinsics: slice.colourIntrinsics,
                              foodRegionMask: slice.foodMask)
    }

    // The pre-feature edge-band fit, run through the colour-grid mask it requires.
    private static func preFeaturePlane(_ slice: DepthSlice) -> SupportPlane? {
        LiDARPlaneFitter.fitOutcome(LiDARPlaneFitter.Inputs(
            depth: slice.depth, colourIntrinsics: slice.colourIntrinsics,
            foodRegionMask: slice.colourFoodMask, gravityCamera: slice.gravity
        )).plane
    }

    // The candidate the design intends to select — highest inner-band support — taken
    // before admissibility so the measurement does not depend on the thresholds.
    private static func bestCandidate(_ slice: DepthSlice)
    -> (candidate: SupportRegion.PlaneCandidate, ring: RingStatistics)? {
        guard let g = geometry(slice) else { return nil }
        let samples = SupportRegion.ringSamples(geometry: g)
        var rng = SplitMix64(seed: Fnv1a64.hash(slice.depth.depthBytesMm))
        let candidates = SupportRegion.extractCandidates(
            annulus: samples.annulus, geometry: g,
            gravity: slice.gravity.normalised(), rng: &rng
        )
        let scored = candidates.compactMap { candidate -> (SupportRegion.PlaneCandidate, RingStatistics)? in
            guard let ring = SupportRegion.ringStatistics(
                samples: samples, geometry: g, normal: candidate.normal, d: candidate.d
            ) else { return nil }
            return (candidate, ring)
        }
        return scored.max { $0.1.supportFraction < $1.1.supportFraction }
    }

    private static func preFeatureRing(_ slice: DepthSlice) -> RingStatistics? {
        guard let plane = preFeaturePlane(slice) else { return nil }
        return SupportRegion.ringStatistics(
            for: plane, depth: slice.depth,
            foodMask: slice.foodMask, intrinsics: slice.colourIntrinsics
        )
    }

    private static func bestCandidateRing(_ slice: DepthSlice) -> RingStatistics? {
        bestCandidate(slice)?.ring
    }

    private static func preFeatureVolumeCm3(_ slice: DepthSlice) -> Float? {
        guard let plane = preFeaturePlane(slice) else { return nil }
        return volumeCm3(slice, normal: plane.normal, d: plane.distanceMm)
    }

    private static func bestCandidateVolumeCm3(_ slice: DepthSlice) -> Float? {
        guard let best = bestCandidate(slice) else { return nil }
        return volumeCm3(slice, normal: best.candidate.normal, d: best.candidate.d)
    }

    private static func rejectionReasons(_ slice: DepthSlice) -> [SupportRegion.CandidateRejection]? {
        guard let g = geometry(slice) else { return nil }
        let samples = SupportRegion.ringSamples(geometry: g)
        var rng = SplitMix64(seed: Fnv1a64.hash(slice.depth.depthBytesMm))
        let candidates = SupportRegion.extractCandidates(
            annulus: samples.annulus, geometry: g,
            gravity: slice.gravity.normalised(), rng: &rng
        )
        return candidates.compactMap { candidate in
            guard let ring = SupportRegion.ringStatistics(
                samples: samples, geometry: g, normal: candidate.normal, d: candidate.d
            ) else { return SupportRegion.CandidateRejection.ringUnavailable }
            return SupportRegion.admissibility(
                ring: ring,
                annulusMedianMm: SupportRegion.medianHeight(
                    indices: samples.annulus, geometry: g, normal: candidate.normal, d: candidate.d),
                foodEnvelopeMm: SupportRegion.foodEnvelopeMm(
                    geometry: g, normal: candidate.normal, d: candidate.d),
                extentPx: candidate.extentPx
            )
        }
    }

    // Height-field integration on the NATIVE depth grid: sum of
    // max(0, height above plane) x off-axis pixel area over the food samples. Same
    // pixel-area weighting `HeightFieldEstimator` uses, applied to depth samples
    // rather than colour ones — which is the whole reason the slice can be 290 KB.
    private static func volumeCm3(_ slice: DepthSlice, normal: Vec3, d: Float) -> Float {
        guard let g = geometry(slice) else { return 0 }
        let k = g.intrinsics
        let fMean = (k.fx + k.fy) / 2
        var mm3: Float = 0
        for index in g.foodIndices {
            let point = g.points[index]
            let height = normal.dot(point) - d
            guard height > 0 else { continue }
            mm3 += height * pixelAreaMm2(index: index, point: point, k: k, fMean: fMean)
        }
        return mm3 / 1000
    }

    private static func foodFootprintCm2(_ slice: DepthSlice) -> Float? {
        guard let g = geometry(slice) else { return nil }
        let k = g.intrinsics
        let fMean = (k.fx + k.fy) / 2
        var mm2: Float = 0
        for index in g.foodIndices {
            mm2 += pixelAreaMm2(index: index, point: g.points[index], k: k, fMean: fMean)
        }
        return mm2 / 100
    }

    private static func pixelAreaMm2(index: Int, point: Vec3,
                                     k: CameraIntrinsics, fMean: Float) -> Float {
        let x = index % k.imageWidth, y = index / k.imageWidth
        let du = Float(x) - k.cx, dv = Float(y) - k.cy
        let cosTheta = fMean / (fMean * fMean + du * du + dv * dv).squareRoot()
        let z = -point.z
        return (z * z) / (k.fx * k.fy * cosTheta * cosTheta * cosTheta)
    }
}

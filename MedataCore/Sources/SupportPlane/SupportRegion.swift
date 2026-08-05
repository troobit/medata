import CaptureKit
import Foundation
import PortableContracts

// Food-support plane fit per `specs/estimation/support-plane-reference/`.
//
// The pre-feature fitter (`LiDARPlaneFitter`) selects the largest gravity-aligned
// plane in four colour-grid bands around the food bbox, which is the TABLE when the
// food rests on a plate — measured 26.1 mm too low, and integrated per-pixel, so the
// offset is added to every food pixel. This file replaces "largest plane in the
// frame" with "the plane the food is resting on" by changing three things:
//
//   1. WHICH SAMPLES COMPETE — a mm-denominated annulus of `2 × ringOuterMm` around
//      the food mask, enumerated on the NATIVE depth grid (Req 2.4). The band scan
//      enumerated 1920×1440 colour pixels against a 256×192 depth map, replicating
//      each measurement ~56×.
//   2. HOW A CANDIDATE IS SCORED — the size of its largest 8-connected inlier
//      component, not its raw inlier count (CC-RANSAC; Gallo, Manduchi & Rafii 2011).
//   3. WHICH CANDIDATE WINS — measured contact with the food, via a radial/angular
//      contact ring, under an admissibility filter applied to EVERY candidate before
//      the best one is picked (design §Selection and admissibility).
//
// Rejection is an expected outcome, not an error: `fitFoodSupportPlane` returns nil
// and the caller runs the pre-feature edge-band fit unchanged (Req 4.1–4.3).
public enum SupportPlaneReference: String, Sendable, Codable {
    case foodSupport
    case edgeBand
    // The N5k mixture calibration path's flood-filled plate region. Never produced
    // on device or by the single-view replay — it exists so a calibration artefact
    // can say which basis each β was fitted on, because the mixture corpus keeps the
    // flood fill permanently (Decision 17) and Req 5.4 forbids mixing references.
    case plateRegion
}

// Contact-ring measurements for ONE candidate plane. Every field is persisted or
// feeds a guard; there is deliberately no MAD statistic — the MAD bar cannot fire on
// an admissible candidate and was deleted with its constant and its field
// (Decision 19).
public struct RingStatistics: Sendable, Equatable {
    // Whole-ring median signed height above the plane. ~0 on a correct fit,
    // +18…+26 mm when the plane is the table. Persisted for Req 6.2; NOT used for
    // selection — a median has a 50 % cliff (design §Score).
    public let medianMm: Float
    // Inner/mid/outer band medians. Rises outward on a rimmed plate, falls outward
    // on a ring that leaked past the plate edge (Decision 14). The step guard reads
    // [0]→[1] only (Decision 21).
    public let bandMedianMm: [Float]
    // Share of INNER-band samples within ±ringBandMm of the plane. This is the score.
    public let supportFraction: Float
    // Inner-band sectors meeting `sectorSupportMin`. Empty sectors count as neither
    // supporting nor failing (Decision 20). Persisted (Req 6.4): a ring median of ~0
    // is not on its own evidence of a correct fit (Decision 18).
    public let supportingSectors: Int
    // Per-band sample counts; `ringMinSamples` holds PER band (Decisions 14, 20).
    public let bandSampleCount: [Int]
    // Annulus samples within `inlierBandMm` of the plane ÷ food sample count. Both
    // native depth samples, so the ratio is grid-independent (Req 5.1).
    public let supportVisibility: Float

    public init(medianMm: Float, bandMedianMm: [Float], supportFraction: Float,
                supportingSectors: Int, bandSampleCount: [Int], supportVisibility: Float) {
        self.medianMm = medianMm
        self.bandMedianMm = bandMedianMm
        self.supportFraction = supportFraction
        self.supportingSectors = supportingSectors
        self.bandSampleCount = bandSampleCount
        self.supportVisibility = supportVisibility
    }
}

public enum SupportRegion {

    // MARK: – Constants
    //
    // Radii are in MILLIMETRES, converted to pixels per capture from the median food
    // depth, so they transfer across depth-grid resolutions (Req 5.1).
    //
    // Provenance markers, per the design's Components section:
    //   [derived]   derivation recorded in design.md
    //   [measured]  derivation confirmed against the committed corpus (Decision 29)
    //   [inherited] from a named, already-tested constant
    //   [owed]      a task 26 corpus measurement — shipping an [owed] value
    //               as-asserted is a defect, and Req 3.7 says so for the sector trio.

    // [measured] Decision 29. The ~4 px depth smear spans 7.45 mm and 7.36 mm on the
    // two committed slices, at median food depths of 338.9 mm and 336.9 mm — inside
    // 8 mm on both. The smear is a fixed PIXEL count, so `smear_mm = 4z/f_d`: with
    // f_d 182.0 and 183.2 px the envelope is 364.1 mm and 366.4 mm, and the corpus sits
    // at 93.1 % and 92.0 % of it. Under 8 % of headroom, so the range a capture is taken
    // at now matters and `prerequisites.md` asks for it to be recorded per capture.
    //
    // Decision 29 concluded this "must become `max(ringInnerMm, 4 × mmPerPx)`" beyond
    // the envelope. Measured and REJECTED (Decision 39). `mmPerPx` is `z/f_d` and carries
    // range and grid resolution alike, but only range moves the smear — a coarser grid
    // subsamples a map ARKit has already smoothed. At 128 px the smear-tracking radius
    // therefore reads 14.9 mm for a physical smear still near 7.4, eats 6.9 mm of a
    // 17 mm ring, and leaves three bands of 3.37 and 3.43 mm against depth pixels of
    // 3.73 and 3.68 — each band narrower than one pixel. `1785135663727` loses ring
    // feasibility outright (inner band 166 against `ringMinSamples`) and `1785901032716`
    // clears it by nothing (exactly 200), on a grid where the plane transfers within
    // 0.9 mm today. The envelope is a RANGE bound and is left to the capture session;
    // it must not be paid for with Req 5.1's transfer.
    public static let ringInnerMm: Float = 8
    // [owed] against a RESTATED rule (Decision 33). The old rule — "must sit inside the
    // smallest measured plate margin" — is measured and unsatisfiable: the support
    // margin, the distance from the food boundary at which the surface departs by more
    // than `ringBandMm`, is 4 mm in the tightest sector of BOTH committed captures,
    // inside `ringInnerMm`. No ring can be placed inside it.
    //
    // Measured per-sector margins are [16, 40, 10, 42, 6, 4, 6, 44] mm and
    // [34, 4, 46, 8, 30, 14, 12, 6] mm — every departure inside the ring is a FALL of
    // 5.1 to 15.6 mm, so these are plate edges. 3 of 8 sectors reach `ringOuterMm` on
    // each capture, and only 4 of 8 reach the inner band's 13.7 mm, which is BELOW
    // `minSupportingSectors`. The supporting count is therefore capped by where the
    // plate ends before `sectorSupportMin` is consulted at all.
    //
    // What is owed is the margin the SECTOR measure needs in enough sectors, which is a
    // joint derivation with the trio and waits on the same captures.
    public static let ringOuterMm: Float = 25
    // Structural: inner / mid / outer.
    public static let ringBandCount = 3
    // [owed] below the smallest measured rim step — and UNEXERCISED (Decision 34). The
    // guard fires on an outward RISE; every inner→mid step in the corpus is a FALL, of
    // −0.5 to −6.5 mm, because a flat plate ends and the table begins. The corpus is
    // therefore 6.5 mm from the bar on the wrong side and supplies no floor either. The
    // ceiling still waits on the ruler measurement in `prerequisites.md`.
    public static let bandStepMaxMm: Float = 6
    // [owed] prerequisites capture 4 is the only source for the VALUE. Its firability
    // is settled (Decision 29): the ratio is computed over the ANNULUS, which begins at
    // the food boundary and so does see a support strip thinner than `ringInnerMm`.
    // Measured ceilings — every annulus sample an inlier — are 1.710 and 1.426, and the
    // highest-support candidate reaches 0.880 and 1.032, so 0.15 is roughly a tenth of
    // the achievable range rather than unreachable.
    //
    // Firable but never FIRED (Decision 34): the lowest visibility any corpus candidate
    // reaches is 0.246, 1.6x the bar, so the corpus cannot distinguish 0.15 from any
    // value below that.
    public static let supportVisibilityMin: Float = 0.15
    // [inherited] LiDARPlaneFitter.inlierBandMm = 5.
    public static let ringBandMm: Float = 5
    // [owed] must be measured against the support-surface noise distribution: a
    // ±5 mm band at 0.6 support implies σ_z ≲ 5.9 mm. The Decision 46 tension is
    // resolved in KIND (Decision 29) — that 20 mm bar is a whole-plane residual over a
    // matte table, not a per-sample σ — but not in VALUE: the measured per-sample σ on
    // a flat surface is 3.44 mm on one committed slice and 6.98 mm on the other, at
    // 338.9 mm and 336.9 mm respectively. A 2× spread at the same range is a surface
    // difference, and ringBandMm = 5 falls between the two. A matte-surface capture is
    // required before this can be set (prerequisites, capture session).
    public static let ringSupportMin: Float = 0.6
    // Sector measure (Req 3.6, Decisions 18–20). Equal arcs about the food-mask
    // centroid; empty sectors count as neither supporting nor failing, and the bar is
    // absolute, so a ring heavily clipped by the frame edge fails towards fallback.
    // [owed] Req 3.7 explicitly forbids shipping these as asserted values — and
    // Decision 30 records that the measure itself is blind where it matters: the count
    // takes |height|, so a correct plane whose ring escaped DOWNWARD onto the table
    // (failing sectors −6.8…−32.6 mm) and a table plane with part of its ring on the
    // plate (failing sectors +16.6…+19.8 mm) both score 5 of 8.
    //
    // The replacement rule is now stated (Decision 40): a FAILING sector whose signed
    // inner-band median exceeds +ringBandMm is CROSSED — the support surface is still
    // there and this plane is not on it — and a candidate is rejected when more than
    // `maxCrossedSectors` sectors are crossed. Below −ringBandMm the sector has ESCAPED,
    // which is the plate ending (Decision 33) and not grounds for rejection. The
    // magnitude bar costs nothing: it is `ringBandMm`, already [inherited], and the
    // separating window is −6.794…+16.603 mm, so it sits ~11.7 mm clear on both sides.
    // Restricting to FAILING sectors is what earns that — over all sectors the window is
    // +3.846…+5.974 mm, a tenth as wide, and the bar would be fitted rather than
    // inherited.
    //
    // Nothing is rewired here. `maxCrossedSectors` is bracketed 0…2 by the corpus and
    // [owed] to prerequisites capture 6; shipping the rule means asserting that count,
    // which is what Req 3.7 forbids for exactly these constants. Setting the trio waits
    // on the captures alone now, not on a proposal as well.
    //
    // The committed SUITE brackets it at 0…2 as well (Decision 43) — the same eight
    // scenes on which `minSupportingSectors` has an EMPTY joint interval, 6…5. So no
    // committed scene has to move when the rule lands, and the two sources agree
    // exactly, which they do for no other [owed] constant. Nothing in hand narrows
    // 0…2: every committed scene and both corpus candidates return the same verdict
    // at 0, at 1 and at 2.
    public static let ringSectorCount = 8
    public static let sectorSupportMin: Float = 0.5
    public static let minSupportingSectors = 6
    // [owed] two candidates 26 mm apart scoring near-equally is the straddling-ring
    // case, and a coin flip between them moves the carb number 3×.
    //
    // STRADDLED, and never reachable on the corpus (Decision 34). The margin compares the
    // top two ADMISSIBLE candidates and neither capture produces even one, so it has never
    // run on real data. The gaps real candidates open are 0.312 and 0.117 — 0.15 falls
    // between them, so it would call one capture's pair distinct and the other's
    // ambiguous, and neither capture has a known-correct winner to say which is right.
    public static let ringSupportMarginMin: Float = 0.15
    // [owed] Decision 22 — the Req 3.3 comparator. "Below the lowest admissible
    // candidate" compares a set minimum against itself and cannot fire.
    //
    // The one-sidedness is CORRECT (Decision 34): Req 3.3 rejects a plane lying below the
    // surrounding surface, and such a plane reads a POSITIVE annulus median. The corpus
    // confirms the orientation and nothing else — annulus medians span −36.6 to +5.7 mm,
    // so the largest positive is a fifth of the bar, and the one candidate far from its
    // surroundings is far ABOVE them, which is `ringMedianMaxMm`'s case and not this one.
    public static let escapeBandMm: Float = 30
    // [measured] ringSectorCount × 25: at 25 samples per sector a 0.5 bar has binomial
    // σ ≈ 0.10 and separates a supported sector (p ≈ 0.9) from a crossed one
    // (p ≈ 0.3) by > 4σ. At the old floor of 60, sectors averaged 7 samples
    // (σ ≈ 0.19) and the guard was noise (Decision 20). Holds PER radial band.
    //
    // Confirmed against the corpus with large margin (Decision 29): measured band
    // counts are [1120, 1132, 1213] and [1294, 1347, 1392], 5.6× to 7.0× the floor,
    // and inner-band sectors carry 102–184 samples apiece against the 25 the
    // derivation targets — binomial σ ≈ 0.042 at the 0.5 bar.
    public static let ringMinSamples = 200
    // [inherited] ringBandMm. The SIGNED admission guard of Req 3.2 — the support
    // fraction is unsigned and cannot separate a plane above the ring (table, +)
    // from one below it (vessel rim, −). Both are rejected; the persisted sign is
    // what says which.
    public static let ringMedianMaxMm: Float = 5
    // [derived] Decision 22 — replaces foodAboveFractionMax, which rejected this
    // feature's own acceptance capture (~11 % of the weighed bread's samples
    // overhang below the plate plane, against a 5 % bar). Denominated in millimetres
    // as Req 3.4 states, not as a sample-count fraction.
    public static let foodEnvelopePercentile: Float = 0.90
    // [owed] Decision 22, bounded from ABOVE only (Decision 34). The corpus's intended
    // candidate — highest ring support, taken before admissibility — reports an envelope
    // of 26.6 mm and 25.8 mm, so any floor at or above 25.8 rejects the fit this feature
    // exists to produce. Every envelope the corpus measures is positive (7.2 to 39.6 mm),
    // so the negative-envelope cases the guard is written for — a bowl, a plane on the
    // food top — are scenes it does not contain and there is no floor.
    public static let foodEnvelopeMinMm: Float = 0
    // Structural: table, support, one more.
    public static let maxCandidatePlanes = 3
    // [owed] Decision 32, but a NARROWER owing than before. This was
    // `minCandidateSamples = 500`, one number answering two unrelated questions: "can
    // this capture support the fit at all" and "is there enough residue left for
    // another extraction pass". The first is now asked exactly, by
    // `ringBandsAreFeasible`, so only the second is left here and the value has one
    // job. The value itself does not move — nothing measured justifies moving it.
    //
    // Denominated in millimetres², not samples, since Decision 38. It was `500` raw
    // depth samples, and a sample count divides by four under a 2x grid halving where
    // the surface it stands for does not: the corpus runs three extraction passes
    // natively and two at half resolution, so `planeCandidateCount` — a PERSISTED field
    // (Req 6.1) — was a property of the sensor's grid rather than of the scene
    // (Decision 35). Converting through the same `mmPerPx` the ring radii and
    // `minAcceptedExtentMm` already use removes the dependence: the residue's AREA is
    // near-invariant across the halving (36 280 → 36 176 mm² and 42 458 → 41 961 mm²
    // on the first pass) where its sample count quarters.
    //
    // The VALUE does not move. 500 samples at the corpus's pixel areas of 3.465 mm² and
    // 3.383 mm² is 1732.6 mm² and 1691.5 mm², so 1691 mm² is the largest whole
    // millimetre² at or below both and every corpus pass keeps its verdict.
    //
    // The corpus bounds it from ABOVE only. Measured residue per pass is
    // [36 280, 11 471, 2013] mm² and [42 458, 9509, 3153] mm², so any floor above
    // 2013 mm² cuts a pass the corpus produces. Both third-pass candidates are then
    // rejected on their own merits (`extent` at 22.3 mm, and `supportFraction`), so
    // cutting them would change no plane on this corpus — but it would drop
    // `planeCandidateCount` from 3 to 2, and pass 3 is where a plate under a dominant
    // table can still surface. Nothing in the corpus fails for want of residue, so
    // there is no measured floor and the lower end stays owed to the capture session.
    public static let minResidueAreaMm2: Float = 1691
    // The floor as the sample count a given capture's grid expresses it in. Rounded UP,
    // so the bar is never weaker than the area it stands for.
    public static func minResidueSamples(mmPerPx: Float) -> Int {
        Int((minResidueAreaMm2 / (mmPerPx * mmPerPx)).rounded(.up))
    }
    // [owed] minimum bbox extent of the winning inlier component, in MILLIMETRES —
    // a sliver gives a badly conditioned normal (Req 2.3).
    //
    // Denominated in millimetres, not pixels, since Decision 37. It was `24 px`, and
    // that was the only bar in `admissibility` measured in pixels while every other one
    // is millimetres or a dimensionless fraction — which is precisely what Req 5.1's
    // transfer across depth grids rests on. Halve the grid and pixel extents halve with
    // it, so a surface admitted at 44 px was rejected as a sliver at 22 px by the same
    // bar (Decision 35). Converting through `mmPerPx`, the conversion the ring radii
    // already use, removes the dependence: the same physical surface measures the same
    // millimetres on any grid, and the corpus confirms it holds to 0.5 mm across a 2×
    // halving where the pixel count halves exactly.
    //
    // The VALUE does not move — nothing measured justifies moving it. 24 px at the
    // corpus's `mmPerPx` of 1.8616 and 1.8393 is 44.68 and 44.14 mm, so 44 mm is the
    // largest whole millimetre at or below both and every corpus verdict is unchanged.
    //
    // Bracketed by the corpus at 22.3…47.8 mm and no tighter (Decisions 32, 37).
    // Measured extents are 229, 141, 22 mm and 285, 81, 48 mm: the 22 mm candidate is a
    // 153-sample sliver sitting 32.9 mm off the ring and is rejected here, which is the
    // guard working, so the floor is above 22.3. The ceiling is soft — 47.8 mm is the
    // smallest extent on a candidate that reaches the later guards, and that candidate
    // is rejected on `supportFraction` anyway, so the corpus never shows a 47.8 mm
    // candidate deserving admission. Unlike the pixel bracket this one is a physical
    // bracket rather than a 256×192 one, so a capture at another depth resolution can
    // now be admitted to the corpus without restating it.
    public static let minAcceptedExtentMm: Float = 44
    // [derived] adaptive stopping caps it; the per-pass residue inlier ratio is
    // reported so the budget holds as a measurement. The budget is sufficient
    // because extraction is SEQUENTIAL — pass 1 removes the table — not because the
    // pass-1 inlier ratio is high (it is ~6 %, where 2048 iterations reach ~36 %).
    public static let maxIterationsPerPass = 2048
    // Target probability of drawing one outlier-free triple, for adaptive stopping.
    static let ransacSuccessProbability = 0.99
    // The candidate set is an annulus of 2 × ringOuterMm around the food mask
    // (Decision 15). NOT dilate(foodMask, 2 × foodRadius), which spans ~8.3 s²
    // against the pre-feature bands' ~4 s² — looser than the code it replaces.
    static let annulusOuterMultiple: Float = 2
    // A pass removes its polished inliers within 2 × inlierBandMm; a 1× shell seeds
    // near-duplicate planes on the next pass.
    static let inlierRemovalMultiple: Float = 2

    // MARK: – Depth intrinsics (design §Native depth grid, and the intrinsics trap)

    // `depth.depthIntrinsics` is UNUSABLE on device: ARKitCaptureEngine writes
    // CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0, …) and only width/height are real,
    // so reading it divides by zero and yields a NaN plane. Derive from the colour
    // intrinsics instead. The half-pixel terms match `sampleDepthBilinear`
    // (LiDARPlaneFitter.swift:440-441), which already resamples this way.
    //
    // The failure ranked worst here is NOT the half-pixel term (0.433 depth px of
    // principal-point offset, ~0.016° of induced tilt — three orders of magnitude
    // below the 15° gravity cone). It is passing the COLOUR intrinsics through
    // unscaled: the plane barely moves at nadir because z is unchanged, while every
    // mm-denominated radius is corrupted by 7.5× — the 8–25 mm ring silently becomes
    // a 1–3.3 mm ring, which no plane-level assertion catches.
    static func depthIntrinsics(from colour: CameraIntrinsics, depth: DepthMap) -> CameraIntrinsics {
        let sx = Float(depth.width) / Float(max(1, colour.imageWidth))
        let sy = Float(depth.height) / Float(max(1, colour.imageHeight))
        return CameraIntrinsics(
            fx: colour.fx * sx,
            fy: colour.fy * sy,
            cx: (colour.cx + 0.5) * sx - 0.5,
            cy: (colour.cy + 0.5) * sy - 0.5,
            distortion: [],
            imageWidth: depth.width,
            imageHeight: depth.height
        )
    }

    // `BinaryMask` is colour-grid; the ring and the candidates are depth-grid. A
    // depth pixel is food when ANY covered colour pixel is food — Req 2.1 requires
    // the fitted set to contain no food pixel, so ambiguity resolves towards
    // exclusion.
    static func downsampleFoodMask(_ mask: BinaryMask, width dw: Int, height dh: Int) -> BinaryMask {
        if mask.width == dw && mask.height == dh { return mask }
        var pixels = [UInt8](repeating: 0, count: dw * dh)
        let sx = Float(mask.width) / Float(dw)
        let sy = Float(mask.height) / Float(dh)
        for dy in 0..<dh {
            let y0 = max(0, Int((Float(dy) * sy).rounded(.down)))
            let y1 = min(mask.height - 1, Int((Float(dy + 1) * sy).rounded(.up)) - 1)
            guard y0 <= y1 else { continue }
            for dx in 0..<dw {
                let x0 = max(0, Int((Float(dx) * sx).rounded(.down)))
                let x1 = min(mask.width - 1, Int((Float(dx + 1) * sx).rounded(.up)) - 1)
                guard x0 <= x1 else { continue }
                var isFood = false
                scan: for y in y0...y1 {
                    for x in x0...x1 where mask.isFood(x: x, y: y) {
                        isFood = true
                        break scan
                    }
                }
                pixels[dy * dw + dx] = isFood ? 1 : 0
            }
        }
        return BinaryMask(pixels: pixels, width: dw, height: dh)
    }

    // MARK: – Depth-grid geometry

    // Everything downstream reads from one prepared pass over the native depth grid:
    // back-projected points, validity (depth > 0 AND confidence ≥ τ_conf), the
    // downsampled food mask, and the mm-per-pixel scale from the median food depth.
    struct DepthGeometry {
        let intrinsics: CameraIntrinsics       // depth grid
        let foodMask: BinaryMask               // depth grid
        let points: [Vec3]                     // indexed by depth index; junk where !valid
        let valid: [Bool]
        let width: Int
        let height: Int
        let mmPerPx: Float
        let foodSampleCount: Int               // valid-depth food samples
        let foodIndices: [Int]
        let centroidX: Float                   // food-mask centroid, depth grid
        let centroidY: Float
    }

    static func prepare(depth: DepthMap, colourIntrinsics: CameraIntrinsics,
                        foodRegionMask: BinaryMask) -> DepthGeometry? {
        let kd = depthIntrinsics(from: colourIntrinsics, depth: depth)
        let w = depth.width, h = depth.height
        let count = w * h
        guard w > 0, h > 0, kd.fx > 0, kd.fy > 0,
              depth.depthBytesMm.count >= count * 4 else { return nil }

        let mask = downsampleFoodMask(foodRegionMask, width: w, height: h)
        let depths: [Float] = depth.depthBytesMm.withUnsafeBytes { raw in
            (0..<count).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) }
        }
        // No confidence map (N5k RealSense fixtures) means no confidence filtering;
        // invalid returns are zeroed depth and are excluded by the z > 0 guard.
        // τ_conf = 0.40 applies here exactly as it does in the band scan, so
        // `lidar-plane-fit-matte-table-confidence` is not bypassed (Req 7.5).
        let confidence = depth.confidenceBytes
        let hasConfidence = confidence.count >= count

        var points = [Vec3](repeating: Vec3(0, 0, 0), count: count)
        var valid = [Bool](repeating: false, count: count)
        var foodIndices: [Int] = []
        var foodDepths: [Float] = []
        var sumX: Float = 0, sumY: Float = 0
        var maskPixelCount = 0

        for y in 0..<h {
            for x in 0..<w {
                let idx = y * w + x
                let isFood = mask.isFood(x: x, y: y)
                if isFood {
                    sumX += Float(x)
                    sumY += Float(y)
                    maskPixelCount += 1
                }
                let z = depths[idx]
                guard z > 0, z.isFinite else { continue }
                if hasConfidence,
                   Float(confidence[idx]) / 255 < LiDARPlaneFitter.confidenceThreshold { continue }
                points[idx] = Vec3(
                    (Float(x) - kd.cx) / kd.fx * z,
                    (Float(y) - kd.cy) / kd.fy * z,
                    -z
                )
                valid[idx] = true
                if isFood {
                    foodIndices.append(idx)
                    foodDepths.append(z)
                }
            }
        }
        guard maskPixelCount > 0, !foodDepths.isEmpty else { return nil }

        // mm per depth pixel at the food's range: z / f. This is what makes the ring
        // radii mm-denominated and therefore grid-independent (Req 5.1).
        let mmPerPx = median(foodDepths) / kd.fx
        guard mmPerPx > 0, mmPerPx.isFinite else { return nil }

        return DepthGeometry(
            intrinsics: kd, foodMask: mask, points: points, valid: valid,
            width: w, height: h, mmPerPx: mmPerPx,
            foodSampleCount: foodIndices.count, foodIndices: foodIndices,
            centroidX: sumX / Float(maskPixelCount),
            centroidY: sumY / Float(maskPixelCount)
        )
    }

    // MARK: – Contact ring (Req 3.1, 3.6, 3.8)

    // The ring is the 8–25 mm sub-annulus outside the food boundary, resolved into
    // radial bands and angular sectors. The annulus is the wider 2 × ringOuterMm
    // candidate bound. Both are needed: `supportVisibility` counts plane inliers
    // across the whole annulus, which ring indices alone cannot supply.
    struct RingSamples {
        let ring: [Int]        // depth indices, ascending
        let band: [Int]        // parallel to `ring`: 0 = inner … ringBandCount-1
        let sector: [Int]      // parallel to `ring`: inner-band sector, else -1
        let annulus: [Int]     // depth indices, ascending
    }

    static func ringSamples(geometry g: DepthGeometry) -> RingSamples {
        let distancePx = distanceToFoodPx(mask: g.foodMask)
        let bandWidthMm = (ringOuterMm - ringInnerMm) / Float(ringBandCount)
        let annulusOuterMm = annulusOuterMultiple * ringOuterMm

        var ring: [Int] = [], band: [Int] = [], sector: [Int] = [], annulus: [Int] = []
        for y in 0..<g.height {
            for x in 0..<g.width {
                let idx = y * g.width + x
                guard g.valid[idx], !g.foodMask.isFood(x: x, y: y) else { continue }
                let distMm = distancePx[idx] * g.mmPerPx
                guard distMm <= annulusOuterMm else { continue }
                annulus.append(idx)
                guard distMm >= ringInnerMm, distMm <= ringOuterMm else { continue }
                let b = min(ringBandCount - 1, Int((distMm - ringInnerMm) / bandWidthMm))
                ring.append(idx)
                band.append(b)
                sector.append(b == 0 ? sectorIndex(x: x, y: y, geometry: g) : -1)
            }
        }
        return RingSamples(ring: ring, band: band, sector: sector, annulus: annulus)
    }

    // Declared API (design §Components): depth-grid indices in the ring, excluding
    // food and low-confidence samples.
    static func contactRing(foodMask: BinaryMask, depth: DepthMap,
                            intrinsics: CameraIntrinsics) -> [Int] {
        guard let g = prepare(depth: depth, colourIntrinsics: intrinsics,
                              foodRegionMask: foodMask) else { return [] }
        return ringSamples(geometry: g).ring
    }

    // Equal arcs about the food-mask centroid. Cost is one atan2 and a bucket index
    // per inner-band sample, reusing the samples radial banding already collects.
    static func sectorIndex(x: Int, y: Int, geometry g: DepthGeometry) -> Int {
        let angle = atan2(Float(y) - g.centroidY, Float(x) - g.centroidX)
        let normalised = (angle + .pi) / (2 * .pi)
        return min(ringSectorCount - 1, max(0, Int(normalised * Float(ringSectorCount))))
    }

    // Exact squared Euclidean distance transform (Felzenszwalb & Huttenlocher 2012),
    // O(w·h). `large` is finite rather than .infinity so the parabola-intersection
    // arithmetic stays well-defined on columns that contain no food pixel.
    static func distanceToFoodPx(mask: BinaryMask) -> [Float] {
        let w = mask.width, h = mask.height
        let large: Float = 1e10
        var grid = [Float](repeating: 0, count: w * h)
        var column = [Float](repeating: 0, count: h)
        for x in 0..<w {
            for y in 0..<h { column[y] = mask.isFood(x: x, y: y) ? 0 : large }
            let transformed = distanceTransform1D(column)
            for y in 0..<h { grid[y * w + x] = transformed[y] }
        }
        var row = [Float](repeating: 0, count: w)
        for y in 0..<h {
            for x in 0..<w { row[x] = grid[y * w + x] }
            let transformed = distanceTransform1D(row)
            for x in 0..<w { grid[y * w + x] = transformed[x].squareRoot() }
        }
        return grid
    }

    private static func distanceTransform1D(_ f: [Float]) -> [Float] {
        let n = f.count
        guard n > 0 else { return [] }
        var d = [Float](repeating: 0, count: n)
        var v = [Int](repeating: 0, count: n)
        var z = [Float](repeating: 0, count: n + 1)
        var k = 0
        v[0] = 0
        z[0] = -.greatestFiniteMagnitude
        z[1] = .greatestFiniteMagnitude
        for q in 1..<n {
            var s = ((f[q] + Float(q * q)) - (f[v[k]] + Float(v[k] * v[k])))
                / Float(2 * q - 2 * v[k])
            while k > 0, s <= z[k] {
                k -= 1
                s = ((f[q] + Float(q * q)) - (f[v[k]] + Float(v[k] * v[k])))
                    / Float(2 * q - 2 * v[k])
            }
            k += 1
            v[k] = q
            z[k] = s
            z[k + 1] = .greatestFiniteMagnitude
        }
        k = 0
        for q in 0..<n {
            while z[k + 1] < Float(q) { k += 1 }
            d[q] = Float((q - v[k]) * (q - v[k])) + f[v[k]]
        }
        return d
    }

    // MARK: – Ring statistics (Reqs 3.1, 3.2, 3.5, 3.6, 3.8, 3.9)

    // Whether `ringStatistics` can return anything at all for this capture, for ANY
    // candidate plane. The band counts come from `samples.band`, which the plane never
    // touches, so the answer is a property of the capture and can be asked before a
    // single plane is fitted (Decision 32).
    static func ringBandsAreFeasible(samples: RingSamples) -> Bool {
        var counts = [Int](repeating: 0, count: ringBandCount)
        for band in samples.band { counts[band] += 1 }
        return counts.allSatisfy { $0 >= ringMinSamples }
    }

    // nil when any radial band holds fewer than `ringMinSamples` — the floor holds
    // PER band, because radial banding divides the samples (Decision 14) and
    // sectoring divides the inner band again, which is where the 200 comes from
    // (Decision 20).
    static func ringStatistics(samples: RingSamples, geometry g: DepthGeometry,
                               normal: Vec3, d: Float) -> RingStatistics? {
        var bandHeights = [[Float]](repeating: [], count: ringBandCount)
        var allHeights: [Float] = []
        allHeights.reserveCapacity(samples.ring.count)
        var sectorTotal = [Int](repeating: 0, count: ringSectorCount)
        var sectorSupported = [Int](repeating: 0, count: ringSectorCount)

        for (i, idx) in samples.ring.enumerated() {
            let height = normal.dot(g.points[idx]) - d
            allHeights.append(height)
            let b = samples.band[i]
            bandHeights[b].append(height)
            guard b == 0 else { continue }
            let s = samples.sector[i]
            guard s >= 0 else { continue }
            sectorTotal[s] += 1
            if abs(height) <= ringBandMm { sectorSupported[s] += 1 }
        }

        let counts = bandHeights.map(\.count)
        guard counts.allSatisfy({ $0 >= ringMinSamples }) else { return nil }

        let inner = bandHeights[0]
        let supported = inner.reduce(into: 0) { $0 += abs($1) <= ringBandMm ? 1 : 0 }
        // An empty sector counts as neither supporting nor failing, and the bar is
        // absolute — so a ring heavily clipped by the frame edge loses sectors and
        // fails towards fallback rather than passing on a majority of what remains.
        var supporting = 0
        for s in 0..<ringSectorCount where sectorTotal[s] > 0
            && Float(sectorSupported[s]) / Float(sectorTotal[s]) >= sectorSupportMin {
            supporting += 1
        }

        var visible = 0
        for idx in samples.annulus
        where abs(normal.dot(g.points[idx]) - d) <= LiDARPlaneFitter.inlierBandMm {
            visible += 1
        }

        return RingStatistics(
            medianMm: median(allHeights),
            bandMedianMm: bandHeights.map { median($0) },
            supportFraction: Float(supported) / Float(inner.count),
            supportingSectors: supporting,
            bandSampleCount: counts,
            supportVisibility: Float(visible) / Float(max(1, g.foodSampleCount))
        )
    }

    // Req 6.1 requires the ring measure on EVERY depth-derived attempt, including
    // fallbacks — Req 6.2's before/after comparison is unexecutable otherwise.
    public static func ringStatistics(for plane: SupportPlane, depth: DepthMap,
                                      foodMask: BinaryMask,
                                      intrinsics: CameraIntrinsics) -> RingStatistics? {
        guard let g = prepare(depth: depth, colourIntrinsics: intrinsics,
                              foodRegionMask: foodMask) else { return nil }
        return ringStatistics(samples: ringSamples(geometry: g), geometry: g,
                              normal: plane.normal, d: plane.distanceMm)
    }

    // MARK: – Candidate extraction (Reqs 2.2, 2.3, 2.4)

    struct PlaneCandidate {
        let normal: Vec3
        let d: Float
        let residualMm: Float
        let componentSize: Int
        // The raw pixel extent, kept because it is what the component scan produces and
        // what a grid-dependence measurement needs to see; `extentMm` is what the guard
        // reads (Decision 37).
        let extentPx: Int
        let extentMm: Float
        // The budget is sufficient because pass 1 removes the table, not because the
        // pass-1 ratio is high. Reported so that holds as a measurement.
        let residueInlierRatio: Float
        // The denominator of `residueInlierRatio`: how many annulus samples this pass
        // had left to draw from. Reported so `minResidueAreaMm2` — the only floor the
        // corpus can bracket rather than derive — is measurable per pass.
        let residueCount: Int
    }

    // Sequential CC-RANSAC: up to `maxCandidatePlanes` passes over the annulus, each
    // removing its polished inliers within 2 × inlierBandMm before the next.
    static func extractCandidates(annulus: [Int], geometry g: DepthGeometry,
                                  gravity: Vec3, rng: inout SplitMix64) -> [PlaneCandidate] {
        var residue = annulus
        var candidates: [PlaneCandidate] = []
        let scratch = ComponentScratch(width: g.width, height: g.height)
        // Converted once per capture: the floor is an area, and this is the sample count
        // this grid expresses it in (Decision 38).
        let residueFloor = minResidueSamples(mmPerPx: g.mmPerPx)

        for _ in 0..<maxCandidatePlanes {
            guard residue.count >= residueFloor else { break }
            guard let hypothesis = ccRansac(indices: residue, geometry: g, gravity: gravity,
                                            rng: &rng, scratch: scratch) else { break }

            var inliers = hypothesis.members
            guard let refined = try? LiDARPlaneFitter.refine(
                inliers: inliers.map { g.points[$0] }, seedNormal: hypothesis.normal
            ) else { break }
            var normal = refined.0
            var d = refined.1

            // Consensus polish, as on the pre-feature path: re-select against the
            // REFINED plane and re-refine until the consensus set stops changing, so
            // the result no longer depends on which minimal sample won. Re-selection
            // stays component-based, or a straddling re-selection would drag the
            // plane back across the step.
            for _ in 0..<LiDARPlaneFitter.consensusPolishMaxPasses {
                var reselected: [Int] = []
                reselected.reserveCapacity(residue.count)
                for idx in residue
                where abs(normal.dot(g.points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                    reselected.append(idx)
                }
                let component = scratch.largestComponent(of: reselected)
                let next = component.members
                if next == inliers || next.count < LiDARPlaneFitter.minPoints { break }
                guard let (nextNormal, nextD) = try? LiDARPlaneFitter.refine(
                    inliers: next.map { g.points[$0] }, seedNormal: normal
                ) else { break }
                if acos(clampedCosine(nextNormal.dot(gravity))) > LiDARPlaneFitter.gravityAngleMaxRad {
                    break
                }
                inliers = next
                normal = nextNormal
                d = nextD
            }

            let component = scratch.largestComponent(of: inliers)
            candidates.append(PlaneCandidate(
                normal: normal, d: d,
                residualMm: LiDARPlaneFitter.computeResidual(
                    points: inliers.map { g.points[$0] }, normal: normal, d: d
                ),
                componentSize: component.size,
                extentPx: component.minExtentPx,
                extentMm: Float(component.minExtentPx) * g.mmPerPx,
                residueInlierRatio: Float(inliers.count) / Float(residue.count),
                residueCount: residue.count
            ))

            let removalBandMm = inlierRemovalMultiple * LiDARPlaneFitter.inlierBandMm
            residue = residue.filter { abs(normal.dot(g.points[$0]) - d) >= removalBandMm }
        }
        return candidates
    }

    struct RansacHypothesis {
        let normal: Vec3
        let d: Float
        let members: [Int]     // the largest 8-connected inlier component
    }

    // Score a candidate by the size of its largest 8-connected inlier component, not
    // by total inlier count (Gallo, Manduchi & Rafii 2011). What this buys is stated
    // narrowly in the design: it CANNOT prefer the plate over the table — the table
    // is a genuine single surface with a larger component. It excludes a co-height
    // surface elsewhere in the annulus (a second plate, a board), which forms a
    // separate blob. Surfacing the plate is sequential extraction's job.
    static func ccRansac(indices: [Int], geometry g: DepthGeometry, gravity: Vec3,
                         rng: inout SplitMix64, scratch: ComponentScratch) -> RansacHypothesis? {
        let n = indices.count
        guard n >= LiDARPlaneFitter.minPoints else { return nil }
        var best: RansacHypothesis?
        var bestComponent = 0
        var required = maxIterationsPerPass
        var iteration = 0

        while iteration < required && iteration < maxIterationsPerPass {
            iteration += 1
            // Three draws per iteration UNCONDITIONALLY, so the generator sequence
            // stays independent of how many hypotheses are rejected and of how many
            // passes have run before this one (Req 7.7).
            let i = rng.uniformInt(n)
            var j = rng.uniformInt(n); if j == i { j = (j + 1) % n }
            var k = rng.uniformInt(n)
            if k == i || k == j { k = (k + 1) % n }
            if k == i || k == j { k = (k + 2) % n }
            if k == i || k == j { continue }

            let p1 = g.points[indices[i]], p2 = g.points[indices[j]], p3 = g.points[indices[k]]
            var nHat = (p2 - p1).cross(p3 - p1)
            if nHat.lengthSquared < 1e-12 { continue }
            nHat = nHat.normalised()
            if nHat.dot(gravity) < 0 { nHat = -nHat }
            if acos(clampedCosine(nHat.dot(gravity))) > LiDARPlaneFitter.gravityAngleMaxRad { continue }

            let d = nHat.dot(p1)
            var inliers: [Int] = []
            inliers.reserveCapacity(n)
            for idx in indices where abs(nHat.dot(g.points[idx]) - d) < LiDARPlaneFitter.inlierBandMm {
                inliers.append(idx)
            }

            // Amortise the connected-component labelling. Decision 13 puts CC scoring
            // INSIDE the loop, so unamortised it runs up to
            // maxIterationsPerPass × maxCandidatePlanes times over the annulus —
            // order 1e8 operations, on the path that already produced a 32 GB
            // allocation failure. A component can never be larger than the raw inlier
            // count, so a hypothesis whose raw count cannot beat the running best
            // component size cannot win and is never labelled. The bound is exact,
            // which is why it needs no constant of its own.
            if inliers.count <= bestComponent { continue }

            let component = scratch.largestComponent(of: inliers)
            guard component.size > bestComponent else { continue }
            bestComponent = component.size
            best = RansacHypothesis(normal: nHat, d: d, members: component.members)
            // Adaptive stopping: recompute the required N from the best inlier ratio
            // seen so far. maxIterations = 256 was sized to find the DOMINANT plane
            // and must not be inherited on faith — P(clean triple) is 98 % at w = 0.25
            // but 3 % at w = 0.05. Deterministic, because the ratio sequence is.
            required = requiredIterations(inlierRatio: Float(bestComponent) / Float(n))
        }
        return best
    }

    // N = log(1 − p) / log(1 − w³), capped at `maxIterationsPerPass`.
    static func requiredIterations(inlierRatio w: Float) -> Int {
        guard w > 0 else { return maxIterationsPerPass }
        let clean = pow(Double(min(0.999, w)), 3)
        guard clean < 1 else { return 1 }
        let n = log(1 - ransacSuccessProbability) / log(1 - clean)
        guard n.isFinite else { return maxIterationsPerPass }
        return max(1, min(maxIterationsPerPass, Int(n.rounded(.up))))
    }

    // 8-connected component labelling over depth-grid indices, with the stamp arrays
    // reused across calls so each labelling costs O(inliers) rather than O(w·h).
    final class ComponentScratch {
        private var member: [Int32]
        private var visited: [Int32]
        private var generation: Int32 = 0
        private let width: Int
        private let height: Int

        init(width: Int, height: Int) {
            self.width = width
            self.height = height
            member = [Int32](repeating: 0, count: width * height)
            visited = [Int32](repeating: 0, count: width * height)
        }

        // `members` is returned in ascending index order so equality against a
        // previous pass's set is a plain array comparison.
        func largestComponent(of indices: [Int]) -> (size: Int, members: [Int], minExtentPx: Int) {
            guard !indices.isEmpty else { return (0, [], 0) }
            generation += 1
            let stamp = generation
            for idx in indices { member[idx] = stamp }

            var bestMembers: [Int] = []
            var stack: [Int] = []
            for start in indices where visited[start] != stamp {
                visited[start] = stamp
                stack.removeAll(keepingCapacity: true)
                stack.append(start)
                var component = [start]
                while let current = stack.popLast() {
                    let cx = current % width, cy = current / width
                    for dy in -1...1 {
                        let ny = cy + dy
                        if ny < 0 || ny >= height { continue }
                        for dx in -1...1 where !(dx == 0 && dy == 0) {
                            let nx = cx + dx
                            if nx < 0 || nx >= width { continue }
                            let neighbour = ny * width + nx
                            guard member[neighbour] == stamp, visited[neighbour] != stamp else { continue }
                            visited[neighbour] = stamp
                            stack.append(neighbour)
                            component.append(neighbour)
                        }
                    }
                }
                if component.count > bestMembers.count { bestMembers = component }
            }
            bestMembers.sort()

            var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
            for idx in bestMembers {
                let x = idx % width, y = idx / width
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
            let extent = bestMembers.isEmpty ? 0 : min(maxX - minX + 1, maxY - minY + 1)
            return (bestMembers.count, bestMembers, extent)
        }
    }

    // MARK: – Admissibility and selection (Reqs 1.1–1.3, 3.1–3.4, 3.6, 3.8, 3.9)

    // Guards are an ADMISSIBILITY FILTER applied to every candidate; the best
    // admissible candidate then wins. Applying them after selection would let a
    // phantom rim-ramp plane win the score, fail a guard, and drop a capture to
    // fallback while an admissible plate plane sat unexamined in the candidate set.
    enum CandidateRejection: String, Sendable, Equatable {
        case ringUnavailable   // a radial band held fewer than ringMinSamples
        case extent            // badly conditioned normal (Req 2.3)
        case supportFraction   // ring not resting on this plane (Req 3.2)
        case sectors           // ring crossed the support's edge, or straddles (Req 3.6)
        case foodEnvelope      // vessel rim, or a plane on the food top (Req 3.4)
        case ringMedian        // signed: table (+) or raised edge (−) (Reqs 3.1, 3.2)
        case bandStep          // bowl wall, or a rim beginning inside the ring (Req 3.8)
        case visibility        // support surface not observable under the food (Req 3.9)
        case escaped           // region escaped through a depth dropout (Req 3.3)
    }

    // The order short-circuits, so the reason returned is the FIRST guard to fire rather
    // than the only one. Nothing observable depends on it — the reason is not persisted
    // and a rejected candidate is rejected — but it does bound what a measurement pass can
    // see, which is why `SupportPlaneCorpusMeasurementTests` evaluates every guard
    // independently. On the corpus only three of these reasons ever fire (Decision 34).
    static func admissibility(ring: RingStatistics, annulusMedianMm: Float,
                              foodEnvelopeMm: Float, extentMm: Float) -> CandidateRejection? {
        if extentMm < minAcceptedExtentMm { return .extent }
        // The score is the inner-band support fraction, not |median|: a median has a
        // 50 % cliff, and just past it the TABLE plane reads ~0, passes every other
        // guard, and is persisted with a textbook-perfect diagnostic.
        if ring.supportFraction < ringSupportMin { return .supportFraction }
        // THE guard of Decision 18. Without it, food reaching within ~14 mm of a
        // plate's edge selects the table plane and persists a ring median of ~0 —
        // the value this design otherwise treats as proof of correctness.
        if ring.supportingSectors < minSupportingSectors { return .sectors }
        // Decision 22: an upper-envelope test in millimetres, NOT a count fraction.
        // Bread p90 is measured at +26.6 mm → accepted, with the overhanging slice's
        // samples in the lower decile where they belong (the +8 mm this comment carried
        // before was an estimate, low by 3× — Decision 34). Bowl → all food below the rim
        // plane, p90 negative, rejected. Plane on the food top → p90 ≈ 0, rejected.
        if foodEnvelopeMm < foodEnvelopeMinMm { return .foodEnvelope }
        if abs(ring.bandMedianMm[0]) > ringMedianMaxMm { return .ringMedian }
        // Decision 21: inner→mid ONLY. A well plane's own profile rises outward
        // whenever the ring spans well and rim (inner ≈ 0, outer ≈ +18), so a guard
        // firing on any outward rise would reject the exact candidate Decisions 14
        // and 16 exist to rescue.
        if ring.bandMedianMm.count > 1,
           ring.bandMedianMm[1] - ring.bandMedianMm[0] > bandStepMaxMm { return .bandStep }
        if ring.supportVisibility < supportVisibilityMin { return .visibility }
        // Decision 22: the Req 3.3 comparator is the annulus median height with
        // escapeBandMm. "Below the lowest admissible candidate" compares a set
        // minimum against itself, is circular besides, and cannot fire.
        if annulusMedianMm > escapeBandMm { return .escaped }
        return nil
    }

    // The design gives `fitFoodSupportPlane` as returning
    // `(plane, ring, candidateCount)`. It is a struct rather than that tuple because
    // the design ALSO fixes the stats semantics of a `.foodSupport` row —
    // "candidatePointCount / inlierCount mean native depth samples" — and those two
    // counts exist nowhere else: only this function ever sees the annulus and the
    // winning inlier component. The three declared members keep their names.
    public struct FoodSupportFit: Sendable {
        public let plane: SupportPlane
        public let ring: RingStatistics
        // Candidate PLANES extracted by the sequential passes, not points.
        public let candidateCount: Int
        // Native depth samples that competed, and the winner's largest 8-connected
        // inlier component. ~56x smaller than the edge-band path's colour-grid
        // counts, and never comparable across references.
        public let annulusSampleCount: Int
        public let inlierCount: Int
    }

    // nil when no candidate is admissible — the caller then runs the edge-band fit.
    // NEVER throws: rejection is an expected outcome, not an error.
    public static func fitFoodSupportPlane(
        depth: DepthMap, colourIntrinsics: CameraIntrinsics,
        foodRegionMask: BinaryMask, gravityCamera: Vec3
    ) -> FoodSupportFit? {
        guard let g = prepare(depth: depth, colourIntrinsics: colourIntrinsics,
                              foodRegionMask: foodRegionMask) else { return nil }
        let samples = ringSamples(geometry: g)
        // Decision 32: the exact condition, not a proxy for it. `ringStatistics`
        // returns nil unless EVERY radial band clears `ringMinSamples`, and that test
        // reads `samples.band` alone, so it is plane-independent and knowable here.
        // A capture that fails it cannot produce ring statistics for any candidate and
        // therefore cannot produce an admissible one — the extraction below would run
        // in full and return nil regardless. Outcome-identical, and it retires an
        // `[owed]` constant rather than replacing it with another.
        guard ringBandsAreFeasible(samples: samples) else { return nil }

        // Deterministic seed from the depth bytes, threaded through every pass.
        var rng = SplitMix64(seed: Fnv1a64.hash(depth.depthBytesMm))
        let gravity = gravityCamera.normalised()
        let candidates = extractCandidates(annulus: samples.annulus, geometry: g,
                                           gravity: gravity, rng: &rng)
        guard !candidates.isEmpty else { return nil }

        var admissible: [(candidate: PlaneCandidate, ring: RingStatistics)] = []
        for candidate in candidates {
            guard let ring = ringStatistics(samples: samples, geometry: g,
                                            normal: candidate.normal, d: candidate.d) else { continue }
            let annulusMedian = medianHeight(indices: samples.annulus, geometry: g,
                                             normal: candidate.normal, d: candidate.d)
            let envelope = foodEnvelopeMm(geometry: g, normal: candidate.normal, d: candidate.d)
            guard admissibility(ring: ring, annulusMedianMm: annulusMedian,
                                foodEnvelopeMm: envelope, extentMm: candidate.extentMm) == nil
            else { continue }
            admissible.append((candidate, ring))
        }
        guard !admissible.isEmpty else { return nil }

        // Total order, so the winner does not depend on sort stability (Req 7.7).
        admissible.sort { lhs, rhs in
            if lhs.ring.supportFraction != rhs.ring.supportFraction {
                return lhs.ring.supportFraction > rhs.ring.supportFraction
            }
            if lhs.candidate.componentSize != rhs.candidate.componentSize {
                return lhs.candidate.componentSize > rhs.candidate.componentSize
            }
            return lhs.candidate.d > rhs.candidate.d
        }
        // Two candidates 26 mm apart scoring near-equally is exactly the straddling
        // ring, and a coin flip between them moves the carb number 3×.
        if admissible.count >= 2,
           admissible[0].ring.supportFraction - admissible[1].ring.supportFraction < ringSupportMarginMin {
            return nil
        }

        let winner = admissible[0]
        return FoodSupportFit(
            plane: SupportPlane(normal: winner.candidate.normal, distanceMm: winner.candidate.d,
                                residualMm: winner.candidate.residualMm, convergedIterations: nil),
            ring: winner.ring,
            candidateCount: candidates.count,
            annulusSampleCount: samples.annulus.count,
            inlierCount: winner.candidate.componentSize
        )
    }

    // MARK: – Small helpers

    // Median signed height of `indices` above the plane.
    static func medianHeight(indices: [Int], geometry g: DepthGeometry,
                             normal: Vec3, d: Float) -> Float {
        median(indices.map { normal.dot(g.points[$0]) - d })
    }

    // `foodEnvelopePercentile` of the food's signed height above the plane (Req 3.4).
    static func foodEnvelopeMm(geometry g: DepthGeometry, normal: Vec3, d: Float) -> Float {
        percentile(g.foodIndices.map { normal.dot(g.points[$0]) - d },
                   foodEnvelopePercentile)
    }

    static func median(_ values: [Float]) -> Float {
        percentile(values, 0.5)
    }

    static func percentile(_ values: [Float], _ p: Float) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        if p == 0.5, sorted.count % 2 == 0 {
            let hi = sorted.count / 2
            return (sorted[hi - 1] + sorted[hi]) / 2
        }
        let index = Int((p * Float(sorted.count - 1)).rounded())
        return sorted[min(sorted.count - 1, max(0, index))]
    }

    static func clampedCosine(_ value: Float) -> Float {
        max(-1, min(1, value))
    }
}

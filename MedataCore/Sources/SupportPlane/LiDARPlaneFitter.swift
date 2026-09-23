import CardDetection
import CaptureKit
import Foundation
import PortableContracts

// LiDAR support-plane RANSAC fitter per design §6.2. Pure function over the depth
// map, the food-region mask resampled to the colour grid, the camera intrinsics, and
// gravity. RNG is seeded by hashing the depth bytes (per §6.0) so two runs on the
// same fixture produce identical inliers.
public enum LiDARPlaneFitter {
    // Tunable parameters per design §6.2 ("Parameter justification").
    //
    // `lowerEdgeBandMm = 30` stood here and is DELETED rather than measured (Decision 56).
    // It had exactly one occurrence in the repository — its own declaration. The four-edge
    // band scan that `lidar-plane-fit-degenerate-on-clean-capture` added on 2026-06-16
    // sizes each band from `bbox.heightPx` / `bbox.widthPx` and never reads a millimetre
    // bound, so this constant has not defined the fallback's region since that date.
    // Decision 36 prices the fallback at 18.37 mm of plane error over a region it does not
    // set. `collectCandidatePoints` below is the region's only definition.
    //
    // τ_conf: minimum normalised LiDAR confidence for a table pixel to seed the
    // fit. ARKit maps `ARConfidenceLevel.{low,medium,high}` → bytes `{0,127,255}`
    // (§6.0). Lowered from 0.66 (HIGH-only) to 0.40 per Decision 47 so MEDIUM
    // (127/255 = 0.498) is accepted and only genuine LOW/zero returns are dropped.
    // A matte / low-reflectance table returns a weaker LiDAR signal dominated by
    // MEDIUM confidence; the HIGH-only gate starved the fit → `noLidarPoints` →
    // the user-facing "no flat surface". The RANSAC 5 mm inlier band + 20 mm
    // residual gate still reject a bad plane, and σ_plane = exp(−r/5) carries the
    // extra medium-confidence noise into the confidence surface (Decision 46).
    // Bug `lidar-plane-fit-matte-table-confidence` 2026-07-06.
    //
    // `[owed]` to support-plane-reference task 26 as of its Decision 53, and upstream of
    // `inlierBandMm` below: this decides what a SAMPLE is, and every sample the inlier test is
    // applied to has already passed it. Three things that decision measured and this comment
    // must not lose:
    //
    // 1. Its domain is NOT an interval. ARKit reports three levels, so over the whole of
    //    [0, 1] there are three behaviours — accept LOW and up (τ ≤ 0), accept MEDIUM and up
    //    (0 < τ ≤ 127/255 = 0.498, where the 0.40 sits), accept HIGH only (above 0.498). A
    //    value between 0.40 and 0.49 is not a different setting; there is nothing to tune.
    // 2. It MOVES THE PLANE — 2.098 mm at the food on `1785135663727`, past the 1 mm Req 5.1's
    //    transfer is measured at — and it changes the extraction pass count, so `bandMm` above,
    //    `SupportRegion.minResidueAreaMm2` and `maxCandidatePlanes` are all denominated in it.
    // 3. The corpus does NOT reproduce the starvation the paragraph above describes: at HIGH
    //    only both committed captures still fit and the intended candidate's ring support
    //    RISES. The matte-table capture that justifies the 0.40 is not in the corpus, so do
    //    not re-set this from the corpus alone in either direction.
    //
    // The second half of the same constant lives in `Volume.HeightFieldEstimator.tauConfidence`
    // at 0.66, on the FAR side of the MEDIUM level: the support plane is fitted to MEDIUM and
    // HIGH samples while the food volume above it is integrated over HIGH alone. Deliberately
    // not aligned here — closing it adds or removes samples on every capture and moves the
    // answer (Decision 53).
    static let confidenceThreshold: Float = 0.40
    // The fallback's RANSAC budget: a fixed loop bound with no adaptive stopping, read in
    // `ransac` below and nowhere else. `[owed]` to support-plane-reference task 26 as of its
    // Decision 57, and the first constant that feature has measured which only ONE leg reads.
    //
    // It carried no marker and no comment, which is Decisions 47, 48 and 51's shape — but
    // unlike those a derivation for it does exist, it is CORRECT, and it is a REFUTATION.
    // `SupportRegion.ccRansac` and `SupportRegionCandidateTests` both carry "maxIterations =
    // 256 was sized to find the DOMINANT plane and must not be inherited on faith — P(clean
    // triple) is 98 % at w = 0.25 but 3 % at w = 0.05". The promoted leg acted on that and
    // built adaptive stopping; this leg still runs on the number the argument rejects, and
    // the argument is filed on the leg that abandoned it. Four things Decision 57 measured
    // and this comment must not lose:
    //
    // 1. The search it truncates NEVER FINISHES. The running best is monotone in the draws
    //    and nothing here stops it, so doubling the budget to 1024 finds a better hypothesis
    //    on BOTH committed captures (improvements at #689 and #1005, against the #76 and
    //    #210 that 256 stops at). The shipped value is a truncation, not a convergence
    //    point — the exact mirror of `SupportRegion.maxIterationsPerPass`, which never binds
    //    at all because adaptive stopping ends the pass first (Decision 51).
    // 2. It is a FLOOR, not a knob, and the floor is EIGHT DRAWS. The plane spans 23.474 mm
    //    and 0.152 mm at the food over a 1…1024 sweep; from a budget of 8 up the two
    //    captures hold to 0.027 and 0.152 mm, both inside Req 5.1's 1 mm. Second constant
    //    with this shape after `gravityAngleMaxRad` (Decision 55).
    // 3. The promoted leg's own stopping rule, replayed on this leg's own improvement trace,
    //    exits at 39 and 5 draws — 6.6× and 51× cheaper — and lands 0.019 and 0.069 mm from
    //    the plane 256 draws produce. The budget is generous because the surface is easy:
    //    the winning hypothesis holds 0.607 and 0.949 of the points, far above either ratio
    //    the argument above prices.
    // 4. Every iteration is a full O(n) inlier scan over the COLOUR grid — 1,077,427 and
    //    1,475,580 candidate points, two orders of magnitude past the promoted leg's annulus
    //    — so 256 draws cost 2.76e8 and 3.78e8 distance tests, 96.9 % of them past the
    //    8-draw floor. Req 7.6's latency and the OOM this fitter has already produced are
    //    denominated here, in the TIGHTENING direction.
    //
    // Bracketed 8…unbounded by the corpus and 4…unbounded by the committed regression
    // suite — the first owed constant where the corpus binds TIGHTER than the suite, against
    // Decision 41's warning about the reverse. Req 4.3 does NOT pin it: that requirement
    // makes the plane USED equal the plane this fit PRODUCES, and both move together
    // (Decision 54's reading). Both brackets are readings at `gravityAngleMaxRad`, because a
    // rejected triple spends an iteration and buys nothing.
    static let maxIterations: Int = 256
    // ε, the RANSAC inlier band. `[owed]` to support-plane-reference task 26 as of its
    // Decision 52 — this was a bare number with no derivation anywhere, and it is where
    // FOUR of that feature's `[inherited]` provenance markers terminate: `ringBandMm`
    // reads "[inherited] inlierBandMm", `ringMedianMaxMm` reads "[inherited] ringBandMm",
    // `inlierRemovalMultiple` is a multiple OF it, and `supportVisibility` is counted
    // within it. A marker is only as good as the constant it points at, and the chain
    // ended here, one file outside the file whose provenance that feature audits.
    //
    // Measured on the committed corpus it MOVES THE PLANE 18.132 mm and 19.389 mm at the
    // food over a 1…12.5 mm sweep — more than any constant that feature has swept — and
    // its corpus interval is EMPTY at the shipped `ringSupportMin`, because the support
    // bar and `maxCrossedSectors` pull it in opposite directions. Do not treat the 5 as
    // settled; `SupportRegion.ringBandMm` carries the full reading.
    static let inlierBandMm: Float = 5
    // The gravity cone. `[owed]` to support-plane-reference task 26 as of its Decision 55,
    // which is where the ANGLE was finally swept — Decisions 52 and 54 both described this
    // guard's mechanism and neither varied its bar.
    //
    // It is read at FOUR gates, more than any other constant in that feature: the hypothesis
    // test and the polish gate, in `SupportRegion.ccRansac` / `extractCandidates` and again in
    // `ransac` / `fitOutcome` below. Only the two hypothesis tests turn anything away. The
    // polish gates' rejection path is `break`, which keeps the plane the PREVIOUS iteration
    // produced, and the refinement between hypothesis and polish is not gated at all. Four
    // things that decision measured and this comment must not lose:
    //
    // 1. It BOUNDS NOTHING, and the violation is worst where the bar is tightest. At a 1° cone
    //    every candidate extraction produces — 4 of 4 — lies outside 1°, each recorded as
    //    `gravity` at 0 applied iterations. At 2° it is 5 of 6, the worst at 18.955°, NINE
    //    times its own bar, against 20.512° at 1.37× the shipped 15°. It is not monotone
    //    either: 8° leaves nothing outside itself and 15° leaves one candidate at 20.512°.
    // 2. It is a FLOOR, not a knob. The selected plane spans 3.758 mm and 14.584 mm at the
    //    food over a 1…90° sweep, past Req 5.1's 1 mm — and every millimetre of it is below
    //    10°. From 10° to 90°, gate fully off included, the plane is unchanged to 0.000 mm.
    // 3. The floor's derivation is the margin, and this is the number the value stands on.
    //    The corpus's one intended-correct fit is the PLATE TOP at 8.309°, from a hypothesis
    //    at 8.900°, so the shipped 15° carries 6.100° of margin. Its own table candidate in
    //    the same capture is at 2.030° — the surface this feature exists to find sits 6.3° off
    //    the surface the fallback leg finds, and only the promoted leg is near the bar.
    // 4. NO CEILING. At 90° the gate cannot reject anything (both fitters orient onto
    //    gravity's half-space first) and the corpus reads the same planes and the same
    //    `maxCrossedSectors` 2…2. On this corpus the guard could be removed without changing
    //    an answer; the scenes it exists for — a wall, a floor, a counter edge — are not in it.
    //
    // Bracketed 10°…unbounded, shipped value strictly inside. Do NOT re-derive it from
    // `CaptureFlowModel`'s 15° oblique shutter gate: that is a camera-POSE tolerance and this
    // is the angle between a fitted plane's normal and gravity. The coincidence is not a
    // derivation. Not repaired, on Decisions 52-54's precedent — gating the first refinement
    // removes a candidate from `1785135663727` and moves `planeCandidateCount` (Req 6.1).
    static let gravityAngleMaxRad: Float = 15 * .pi / 180
    // Raised from 8 mm to 20 mm per Decision 46 / Req §4.5.
    //
    // `[owed]` to support-plane-reference task 26 as of its Decision 58. The sentences that
    // stood here — "residuals in (8, 20] accept the fit; σ_plane = exp(−r/5) carries the
    // degradation (at r = 20 mm, σ_plane ≈ 0.018, near the ε = 0.01 floor)" — describe an
    // EMPTY interval and a state neither leg can produce. Three things that decision measured
    // and this comment must not lose:
    //
    // 1. The bar CANNOT FIRE, and not because the corpus is clean. Every member of the set
    //    the RMS is taken over lies within one `inlierBandMm` of the plane that SELECTED it,
    //    so RMS(least squares) ≤ RMS(selecting) < `inlierBandMm` = 5 for every input, on both
    //    legs, at every budget and every cone. This bar is FOUR TIMES a quantity the fit's own
    //    geometry cannot reach and `.lidarFitResidualTooHigh` is unreachable at the default.
    //    Its whole live range is (0, residual] — 1.954 and 1.928 mm on the corpus — so the
    //    raise from 8 was a no-op and so was the 8. It is the first constant in this feature
    //    bounded by an ARGUMENT the captures only witness.
    // 2. What the gate reads is NOT that residual. `refine` accumulates its centroid in three
    //    Float `reduce(0, +)` sums, so at this leg's colour-grid inlier counts (641,694 and
    //    1,298,233) the partial sums reach 10⁸ where an ulp is 32 mm, and d = n̂ · centroid
    //    inherits it. The plane it returns is displaced 0.724 and 1.184 mm along its own
    //    normal from the least-squares plane — the second past Req 5.1's 1 mm tolerance — and
    //    the reading is inflated 1.077× and 1.267×. The normal is untouched (0.000° tilt) and
    //    `computeResidual` is not the culprit (8e-5 relative against a Double sum). The
    //    promoted leg refines 10⁴-sample annuli and is accurate. The ceiling in (1) survives
    //    the inflation with 2.5× to spare, so the verdict does not change — but every residual,
    //    σ_plane and fallback plane OFFSET this feature has quoted carries the error.
    // 3. It is `public` and per-call overridable, so 20 is a DEFAULT and not a value. The only
    //    callers that override it — `HarnessCore.FixtureRunner`, `PlateRegionPlaneTests` at
    //    1.0, `LiDARPlaneFitterTests` at 0.1 — pass values inside the live range the default
    //    sits outside of. Both corpus and committed suite floor it at 1.0 for one reason:
    //    below the measured residual `fitOutcome` returns nil and every assertion in
    //    `SupportPlaneRegressionSliceTests` becomes uncomputable rather than wrong.
    //
    // Bracketed 1.0…unbounded, shipped value strictly inside, and NOT set: a bar that cannot
    // fire on a two-capture corpus is not thereby the right bar for a scene that needs it.
    // Not repaired, on Decisions 52-57's precedent — the Double-accumulation fix in
    // `SupportPlaneCorpusMeasurementTests.refineDoubleAccumulated` moves the shipped fallback
    // plane 1.184 mm, which is the plane Decision 36 prices `fallbackPenalty` against.
    public static let residualMaxMm: Float = 20
    // The degeneracy gate `refine` refuses on: σ_min(A)/σ_max(A) for the centred 3×n sample
    // matrix, computed through the 3×3 scatter matrix below. It was the LAST constant in
    // either file with no provenance marker and no sweep.
    //
    // `[owed]` to support-plane-reference task 26 as of its Decision 64, and owed
    // differently from every constant before it — the measurement does not bracket a value,
    // it finds the gate reading a quantity that cannot answer the question. Five things that
    // decision measured and this comment must not lose:
    //
    // 1. It is DISABLED BY SAMPLE COUNT, and the two legs sit either side. Extraction
    //    refines annulus sets bounded at 5,276-12,551 and the gate's reading is exact
    //    there; the fallback leg refines colour-grid sets of 282,430-1,298,233 and on the
    //    two largest it is not. AMENDED BY DECISION 65: the synthetic "refuses up to
    //    50,000, admits from 100,000" is a reading at the NUMBER 350, not at a 350 mm
    //    standoff — on an exactly planar set the crossover is 2^24 / oddSignificand(z), so
    //    350, 700 and 1400 mm share it exactly and a real capture's 336.9 mm crosses at
    //    389. The corpus's own turn is at 581,996…641,694 real-depth samples, 46× above
    //    the largest annulus, and COUNT ALONE DOES NOT SET IT: a 1,475,580-point candidate
    //    set reads 0.9989× where the 1,298,233-point inlier set drawn from it reads
    //    1.2631×, because the inlier set is the thinner of the two. RE-DENOMINATED BY
    //    DECISION 66: neither count nor thickness is the variable — δ/σ is, and the count
    //    enters only through δ. That bracket is the corpus's and not the law's, since
    //    across it the count moves 1.10× while δ moves 5.09×. In the deciding quantity the
    //    annulus clears the bar by 97-39,903×, not by a count. BOUNDED A PRIORI BY DECISION
    //    67: δ/σ has a closed CEILING in the three numbers any set carries before it is
    //    fitted — u·μ·(n−1)·|n̂_z| / 2σ — and it places both legs with no δ measured. The
    //    annulus reads ≤ 0.0186 against the 0.1418 bar, 7.6× of margin ASSERTED rather than
    //    measured, while all four fallback inlier sets read 1.40-9.09 and are over it. So
    //    the extraction leg's safety no longer rests on a per-capture measurement, and the
    //    ceiling is one-sided: it certifies safety, and it refuses all four fallback sets
    //    where two of them measure under the bar. DECISION 69 SETTLES WHICH OF THE TWO
    //    READINGS TO QUOTE: the MEASURED margin is a reading at the shipped scan order and
    //    falls to 72.7× under a permutation of the same points, while the ASSERTED 7.6×
    //    cannot move because n, μ, σ and n̂_z are all held by a permutation. Extraction is
    //    safe under every order by both readings. And the one-sidedness above is VINDICATED
    //    rather than merely conservative — the two fallback sets that measure under the bar
    //    reach 0.1907 and 0.6169 in another order, so the ceiling was right to refuse them.
    // 2. The cause is the CENTROID, not the normal-equations squaring. Accumulating the
    //    scatter and the decomposition in Double while keeping the shipped Float centroid
    //    reproduces the shipped reading on every rung. An offset centroid displaces every
    //    centred sample by the SAME δ along the thin axis, so that axis' second moment
    //    gains exactly n·δ² while σ_max does not move — so Decision 58's defect manufactures
    //    the very conditioning this gate then reads as healthy. DECISION 66 measures the
    //    form: the reading is inflated by √(1 + (δ/σ)²), σ being the set's own RMS thickness
    //    about its least-squares plane, exact to 1e-4 relative over 32 rungs where a linear
    //    δ/σ account is out by 41%. On the corpus: 1.0001× inflation on the extraction sets,
    //    1.0752× and 1.2631× on the two largest fallback sets — and 1.0034× and 1.0018× on
    //    the two smaller ones, which is Decision 65's correction to "the fallback leg ships
    //    with no effective degeneracy guard": what is uniform is that the gate cannot FIRE,
    //    not that its reading is inflated. Thickness enters TWICE — δ itself falls 3.2-21.5×
    //    as a set thickens, because the exactness bound in (1) is about adding the same
    //    value repeatedly and a spread is what breaks that. DECISION 67 gives δ a BOUND and
    //    not a form: swept over an 11× standoff at a count and a thickness held exactly, the
    //    z mean's error sits at 0.0034-0.3117 of u·μ·(n−1)/2 over 32 rungs — the ceiling
    //    holds everywhere and predicts nothing inside itself, the share spanning 91×. It is
    //    DRIFT and not a walk (δ grows as n^1.17, against n^1.0 for drift and n^0.5 for
    //    cancellation), and it grows FASTER than the standoff (μ^1.52-2.06) because a set
    //    whose spread is small against its own standoff is nearer the constant addend the
    //    exactness bound in (1) is about — so the cancellation that keeps δ under the
    //    ceiling is itself what a longer standoff takes away. THAT LAST SENTENCE IS REFUTED
    //    BY DECISION 68, which swept the ratio it names as its own knob: dilating a set
    //    holds σ_z/μ to the last bit and moves the share 40.4×, 1353.2×, 6.1× and 6.8× on
    //    the four captures, so the share is no function of that ratio at all. Nor of any
    //    other shape the set carries — the best power law in (n, μ, σ_z) leaves 946.8× of a
    //    1640.7× span, and 39.6-290.8× fitted per capture with exponents that disagree.
    //    Decision 67's MEASUREMENTS stand (this reads μ^1.52-2.06 again, fitting no plane);
    //    what falls is the account. So the ceiling in (1) is FINAL — the tightest statement
    //    available before a fit — and its one-sidedness is structural rather than a gap.
    //    What the corpus does show is that real captures sit in a narrow band, 3.6× at a
    //    mean of 0.0648 against the family's 1640.7×: four points, and a question for the
    //    capture session rather than a bracket. DECISION 69 CLOSES THAT NEGATIVE IN THE
    //    GENERAL FORM — a PERMUTATION holds the multiset exactly, so every function of the
    //    set's shape is held with it, and δ still moves 6.2-272.8× over ten orders of each
    //    of the eight committed sets. So δ belongs to the summation ORDER and no function of
    //    the set can predict it, whatever its shape. The spread is STRUCTURE, not chance:
    //    six shuffles agree to 1.01-3.37× while the four structural orders span 2.8-272.8×
    //    and hold the noisiest reading on 8 of 8 sets, so the shipped δ is set by how the
    //    depth raster correlates with z. |z| ASCENDING, the textbook error-minimising order,
    //    is the noisiest on 4 of 8 and the quietest on none — these addends are one surface
    //    at one standoff, so a sort orders the RESIDUALS rather than the magnitudes. DO NOT
    //    "FIX" THIS BY SORTING. Every per-set δ in findings (1) and (2) is therefore a
    //    reading at the shipped scan order; the ceiling in (1) is what transfers.
    // 3. σ_min/σ_max IS NOT THE RANK DISCRIMINANT. An exactly planar set (the plane is
    //    exact) and a collinear one (no plane exists) both drive it to zero — measured at
    //    9.5e-9 and 0.0. What separates them is σ_2/σ_max, 0.99999 against 0.0, which this
    //    gate does not read. So no value of this bar distinguishes a perfect fit from a
    //    degenerate one, and the better the fit the closer it comes to being refused.
    // 4. On the case the guard is actually FOR — a strip carrying real sensor noise — only
    //    an exactly zero width is refused. A band 0.02 mm across reads 1e-4, a hundred times
    //    the bar; firing at the shipped value needs a strip under 0.2 µm.
    // 5. It cannot fire on the corpus by four orders. Both legs on both captures read
    //    0.0113-0.0480, so the bar is 11,292-47,989× below every committed reading.
    //
    // Bracketed 0…0.0113 by the corpus, and the ceiling is the only bound that exists: no
    // floor can be measured because (3) says none is there to find. NOT repaired — reading
    // σ_2/σ_max instead, or accumulating the centroid in Double, changes which candidates
    // survive and moves the shipped plane, which is Decisions 52-58's precedent.
    //
    // `SupportRegionScenes.makeDepth`'s ±0.3 mm of noise is derived from this gate and the
    // derivation HOLDS — at the scenes' own few-thousand-sample surfaces an exactly planar
    // scene yields no candidate at all. It is (1) read from the other side, and the same
    // sentence is false at the fallback leg's scale.
    static let stabilityRatioMin: Float = 1e-6
    // Structural: a plane is three points. The only constant in this file the feature has
    // not had to measure — there is no smaller number that names a plane.
    static let minPoints: Int = 3
    // Upper bound on the deterministic consensus-polish passes after the RANSAC
    // winner is refined (estimation-runtime-consistency, PRD estimation-quality).
    //
    // `[owed]` to support-plane-reference task 26 as of its Decision 54. The sentence that
    // stood here — "the loop usually exits earlier because the inlier set reaches a fixed
    // point" — is FALSE on the committed corpus, and false on both legs at once. Four things
    // that decision measured and this comment must not lose:
    //
    // 1. The cap ALWAYS BINDS. At 3 the corpus reaches the stated fixed point on 1 of its 6
    //    extraction passes and on NEITHER fallback fit; the depth it actually needs is 17 in
    //    extraction and 11 in the fallback. The plane both paths ship is a truncated iterate
    //    of the polish, not the fixed point every argument for the guard is stated about.
    //    This is the mirror of `SupportRegion.maxIterationsPerPass`, which never fires at all
    //    (Decision 51).
    // 2. It decides WHICH PLANES COMPETE — the seventh constant that does, and one of the
    //    three that can add a candidate. A shallower polish leaves a different plane, so a
    //    different removal shell, so a different residue: `1785135663727` yields two
    //    candidates at 0-1 passes and three from 2 up. The persisted `planeCandidateCount`
    //    (Req 6.1) is denominated here as well.
    // 3. It moves BOTH legs, and only the promoted one stays inside Req 5.1's 1 mm. Over
    //    0…64 the promoted plane moves 0.490 and 0.106 mm at the food; the FALLBACK plane
    //    moves 0.158 and 1.719 mm. Req 4.3 holds at every value because one constant moves
    //    both — but the plane it names is the one Decision 36 prices `fallbackPenalty`
    //    against and the one that feeds `lidarMmPerPx = |d| / f` on the legacy path.
    // 4. Its DEPTH is not what removes the seed dependence the loop exists to remove. Over
    //    eight seeds the spread at the food reads 2.123 / 2.095 / 2.067 mm at 0, 3 and 64
    //    passes on `1785135663727` — 2.9 % for running the loop to its own fixed point. What
    //    does remove it is `SupportRegion.ransacSuccessProbability` (2.095 → 0.194 mm,
    //    Decision 51), because the residual spread is the seeds disagreeing about which
    //    candidate WINS rather than about where one plane lies.
    //
    // Bracketed 1…unbounded. The floor is the corpus's: at 0 the candidate set is short a
    // plane and `maxCrossedSectors` reads 2…3 rather than the 2…2 Decision 48 determined.
    // There is no ceiling, and the corpus points ABOVE the shipped value rather than at it —
    // what stops that being a proposal is Req 7.6, since this is the innermost loop in
    // extraction and 17 quintuples it on a path that has already produced an OOM.
    static let consensusPolishMaxPasses: Int = 3

    // Where candidate points are sampled relative to `foodRegionMask`.
    public enum CandidateRegion: Sendable, Equatable {
        // §6.2 default: table pixels outside the food mask, in edge bands
        // around its bbox.
        case bandsAroundFoodRegion
        // Restrict candidates to pixels inside the mask; RANSAC then selects
        // the dominant plane within that region. Used by the offline harness
        // to fit the plate-top plane on a flood-filled plate region
        // (nutrition5k-calibration §Support plane, Decision 15 amendment).
        case insideMask
    }

    public struct Inputs: Sendable {
        public let depth: DepthMap
        public let colourIntrinsics: CameraIntrinsics
        public let foodRegionMask: BinaryMask    // colour-image grid
        public let gravityCamera: Vec3           // unit vector in camera-1 frame
        public let residualMaxMm: Float          // §6.2 step 5; default 8
        public let candidateRegion: CandidateRegion

        public init(depth: DepthMap, colourIntrinsics: CameraIntrinsics,
                    foodRegionMask: BinaryMask, gravityCamera: Vec3,
                    residualMaxMm: Float = LiDARPlaneFitter.residualMaxMm,
                    candidateRegion: CandidateRegion = .bandsAroundFoodRegion) {
            self.depth = depth
            self.colourIntrinsics = colourIntrinsics
            self.foodRegionMask = foodRegionMask
            self.gravityCamera = gravityCamera
            self.residualMaxMm = residualMaxMm
            self.candidateRegion = candidateRegion
        }
    }

    // Throwing convenience preserving the pre-outcome call shape for callers
    // that do not need the fit stats (harness, tests).
    public static func fit(_ inputs: Inputs) throws -> SupportPlane {
        let outcome = fitOutcome(inputs)
        if let plane = outcome.plane { return plane }
        throw outcome.refusal ?? SupportPlaneError.noLidarPoints
    }

    public static func fitOutcome(_ inputs: Inputs) -> SupportPlaneFitOutcome {
        // Step 1: collect candidate 3-D points in the colour-image lower-edge band.
        // Counters accumulate into `stats`, returned on both exits (snaq-parity
        // Req 3.1 — previously the `debugLast*` statics).
        var stats = SupportPlaneFitStats()
        let points = collectCandidatePoints(inputs, stats: &stats)
        stats.candidatePointCount = points.count
        guard points.count >= minPoints else {
            return SupportPlaneFitOutcome(plane: nil, stats: stats, refusal: .noLidarPoints)
        }

        // Step 2: RANSAC. Deterministic seed from the depth bytes (§6.0).
        let seed = Fnv1a64.hash(inputs.depth.depthBytesMm)
        var rng = SplitMix64(seed: seed)
        let gravity = inputs.gravityCamera.normalised()
        let (bestNormal, _, bestInliers) = ransac(
            points: points,
            gravity: gravity,
            rng: &rng
        )
        stats.inlierCount = bestInliers.count

        guard bestInliers.count >= minPoints else {
            return SupportPlaneFitOutcome(plane: nil, stats: stats, refusal: .noLidarPoints)
        }

        // Step 3 + 5: least-squares refinement on inliers; stability gate σ_min/σ_max.
        let refinedNormal: Vec3
        let refinedD: Float
        do {
            (refinedNormal, refinedD) = try refine(
                inliers: bestInliers.map { points[$0] },
                seedNormal: bestNormal
            )
        } catch {
            return SupportPlaneFitOutcome(
                plane: nil, stats: stats,
                refusal: (error as? SupportPlaneError) ?? .lidarFitDegenerate
            )
        }

        // Step 3b (additive robustness, estimation-runtime-consistency): consensus
        // polish. The RANSAC winner's ±5 mm inlier band is anchored to a 3-point
        // candidate plane, so points near the band edge flip membership under the
        // millimetre-level depth differences between two captures of the same
        // plate — and the LSQ plane, whose distance feeds the mm/px scale
        // (|d|/f at `Pipeline` stage E) and every height-field sample, inherits
        // that sensitivity straight into the carb reading. Re-selecting inliers
        // against the REFINED plane and re-refining until the consensus set stops
        // changing converges to a fixed point that no longer depends on which
        // minimal sample won. Fully deterministic: fixed pass cap, no RNG, stable
        // ascending point order. Conservative: a re-selection that goes
        // underpopulated, degenerate, or outside the gravity cone keeps the
        // previous pass's plane instead of failing a fit that used to succeed.
        var polishedNormal = refinedNormal
        var polishedD = refinedD
        var polishedInliers = bestInliers
        for _ in 0..<consensusPolishMaxPasses {
            var reselected: [Int] = []
            reselected.reserveCapacity(points.count)
            for idx in 0..<points.count
            where abs(polishedNormal.dot(points[idx]) - polishedD) < inlierBandMm {
                reselected.append(idx)
            }
            if reselected == polishedInliers || reselected.count < minPoints { break }
            guard let (nextNormal, nextD) = try? refine(
                inliers: reselected.map { points[$0] },
                seedNormal: polishedNormal
            ) else { break }
            let angle = acos(max(-1, min(1, nextNormal.dot(gravity))))
            if angle > gravityAngleMaxRad { break }
            polishedInliers = reselected
            polishedNormal = nextNormal
            polishedD = nextD
        }
        stats.inlierCount = polishedInliers.count

        // Step 4: residual_mm = sqrt(mean(squared inlier signed-distances)).
        let residual = computeResidual(points: polishedInliers.map { points[$0] },
                                       normal: polishedNormal, d: polishedD)
        stats.residualMm = residual
        if residual > inputs.residualMaxMm {
            return SupportPlaneFitOutcome(
                plane: nil, stats: stats, refusal: .lidarFitResidualTooHigh
            )
        }

        let plane = SupportPlane(
            normal: polishedNormal,
            distanceMm: polishedD,
            residualMm: residual,
            convergedIterations: nil   // LiDAR fit per §3.3 sentinel
        )
        return SupportPlaneFitOutcome(plane: plane, stats: stats, refusal: nil)
    }

    // MARK: – internals

    static func collectCandidatePoints(
        _ inputs: Inputs, stats: inout SupportPlaneFitStats
    ) -> [Vec3] {
        // Resample depth + confidence onto the colour-image grid (bilinear depth, NN
        // confidence). For each colour-image pixel in an edge band around the food
        // bbox where the pixel is OUTSIDE the food mask AND confidence/255 ≥ τ_conf,
        // back-project to 3-D camera-1 space using K_colour^{-1} · [u,v,1] · z.
        //
        // Bands: bottom, top, left, right of the food bbox, each as thick as the
        // bbox dimension perpendicular to it, clipped to image bounds. The original
        // §6.2 design scanned only the lower-edge band on the assumption that the
        // camera framed the plate from above with the table visible below it. On a
        // centred capture envelope (`App/CaptureFlowModel.swift` gating) the plate
        // fills the middle of the frame and the table is visible on every side; a
        // bbox that extends close to an image edge starves the single-band scan and
        // surfaces as `noLidarPoints` or `lidarFitDegenerate` (near-collinear 3-D
        // points → singular covariance at `refine`). The four-edge scan keeps the
        // fitter's intent (collect table pixels around the plate) while tolerating
        // any side of the bbox sitting against the image edge.
        // Bug `lidar-plane-fit-degenerate-on-clean-capture` 2026-06-16.
        let mask = inputs.foodRegionMask

        if inputs.candidateRegion == .insideMask {
            // Sample every valid-depth pixel INSIDE the mask; the caller has
            // already restricted the mask to the region of interest (e.g. the
            // flood-filled plate region), so no band scan is needed.
            var points: [Vec3] = []
            let kc = inputs.colourIntrinsics
            for y in 0..<mask.height {
                for x in 0..<mask.width {
                    guard mask.isFood(x: x, y: y) else { continue }
                    let conf = sampleConfidenceNearest(depth: inputs.depth, colourX: x, colourY: y,
                                                       colourWidth: mask.width, colourHeight: mask.height)
                    if Float(conf) / 255 < confidenceThreshold { continue }
                    guard let zMm = sampleDepthBilinear(depth: inputs.depth, colourX: Float(x), colourY: Float(y),
                                                        colourWidth: mask.width, colourHeight: mask.height),
                          zMm > 0 else { continue }
                    points.append(Vec3(
                        (Float(x) - kc.cx) / kc.fx * zMm,
                        (Float(y) - kc.cy) / kc.fy * zMm,
                        -zMm
                    ))
                }
            }
            return points
        }

        guard let bbox = foodBBox(mask: mask) else { return [] }
        stats.foodBBoxX = bbox.minX
        stats.foodBBoxY = bbox.minY
        stats.foodBBoxW = bbox.widthPx
        stats.foodBBoxH = bbox.heightPx

        var points: [Vec3] = []
        let kc = inputs.colourIntrinsics
        let xMin = bbox.minX, xMax = bbox.maxX
        let yMin = bbox.minY, yMax = bbox.maxY
        // Below-bbox band starts AT bbox.maxY (food row, filtered by `isFood`) per
        // the original §6.2 design; the top/left/right bands mirror that convention
        // by starting one pixel outside the bbox in their respective directions.
        let scanRegions: [(xRange: ClosedRange<Int>, yRange: ClosedRange<Int>)] = [
            // Below
            (xMin...xMax,
             yMax...min(mask.height - 1, yMax + bbox.heightPx)),
            // Above
            (xMin...xMax,
             max(0, yMin - bbox.heightPx)...yMin),
            // Left
            (max(0, xMin - bbox.widthPx)...xMin,
             yMin...yMax),
            // Right
            (xMax...min(mask.width - 1, xMax + bbox.widthPx),
             yMin...yMax),
        ]

        for (xRange, yRange) in scanRegions {
            for y in yRange {
                for x in xRange {
                    if mask.isFood(x: x, y: y) { continue }
                    let conf = sampleConfidenceNearest(depth: inputs.depth, colourX: x, colourY: y,
                                                       colourWidth: mask.width, colourHeight: mask.height)
                    if Float(conf) / 255 < confidenceThreshold { continue }
                    guard let zMm = sampleDepthBilinear(depth: inputs.depth, colourX: Float(x), colourY: Float(y),
                                                        colourWidth: mask.width, colourHeight: mask.height) else {
                        continue
                    }
                    if zMm <= 0 { continue }
                    // Back-project: p = (X, Y, Z) with Z<0 in §6.0 (-Z forward). The
                    // depth value is positive distance along the optical axis, so:
                    //   p = ((u-cx)/fx, (v-cy)/fy, -1) · zMm
                    let p = Vec3(
                        (Float(x) - kc.cx) / kc.fx * zMm,
                        (Float(y) - kc.cy) / kc.fy * zMm,
                        -zMm
                    )
                    points.append(p)
                }
            }
        }
        return points
    }

    static func ransac(
        points: [Vec3],
        gravity: Vec3,
        rng: inout SplitMix64
    ) -> (normal: Vec3, d: Float, inliers: [Int]) {
        var bestScore = 0
        var bestInliers: [Int] = []
        var bestNormal = gravity
        var bestD: Float = 0
        let n = points.count

        for _ in 0..<maxIterations {
            // Sample 3 distinct indices.
            let i = rng.uniformInt(n)
            var j = rng.uniformInt(n); if j == i { j = (j + 1) % n }
            var k = rng.uniformInt(n)
            if k == i || k == j { k = (k + 1) % n }
            if k == i || k == j { k = (k + 2) % n }
            if k == i || k == j { continue }

            let p1 = points[i], p2 = points[j], p3 = points[k]
            let edge1 = p2 - p1
            let edge2 = p3 - p1
            var nHat = edge1.cross(edge2)
            if nHat.lengthSquared < 1e-12 { continue }     // degenerate triple
            nHat = nHat.normalised()
            // Orient so n̂ · gravity > 0 (table normal points "up" in §6.0 +Y).
            if nHat.dot(gravity) < 0 { nHat = -nHat }
            let angle = acos(max(-1, min(1, nHat.dot(gravity))))
            if angle > gravityAngleMaxRad { continue }

            let d = nHat.dot(p1)
            // Inliers within ±5 mm.
            var inliers: [Int] = []
            inliers.reserveCapacity(n)
            for idx in 0..<n {
                let dist = abs(nHat.dot(points[idx]) - d)
                if dist < inlierBandMm {
                    inliers.append(idx)
                }
            }
            if inliers.count > bestScore {
                bestScore = inliers.count
                bestInliers = inliers
                bestNormal = nHat
                bestD = d
            }
        }
        return (bestNormal, bestD, bestInliers)
    }

    static func refine(inliers: [Vec3], seedNormal: Vec3) throws -> (Vec3, Float) {
        // Centroid; then SVD of the 3×3 scatter matrix M = Σ (pᵢ − c)(pᵢ − c)ᵀ
        // to find the smallest singular vector = plane normal. d = n̂ · centroid.
        //
        // M's left singular vectors equal A's left singular vectors (where A is
        // the 3×n centred matrix), and M's singular values are A's squared, so
        // the stability gate becomes √(M.s[2])/√(M.s[0]) ≥ stabilityRatioMin.
        // The 3×n SVD is avoided because `LinearAlgebra.svdFull` requests
        // JOBVT='A' and allocates an n×n V^T (~32 GB at the 1920×1440 inlier
        // counts observed on iPhone 13 Pro Max). See bugfix spec
        // `specs/bugfixes/lidar-plane-fit-oom-on-device-1920x1440/`.
        //
        // THE CENTROID BELOW IS NOT ACCURATE AT THOSE SAME COUNTS, and support-plane-reference
        // Decision 58 measures it: three Float `reduce(0, +)` sums over coordinates of
        // magnitude ~350 mm reach partial sums of 10⁸, where a Float ulp is 32 mm. At the
        // 641,694 and 1,298,233 inlier counts the fallback leg produces, `d = n̂ · centroid`
        // lands 0.724 and 1.184 mm off the least-squares plane — the second past Req 5.1's
        // 1 mm tolerance. The normal is unaffected: the scatter terms are centred, so they
        // stay small. The promoted leg refines 10⁴-sample annuli and drifts under 0.01 mm.
        // The fix is to accumulate the centroid (and the scatter) in Double; it is NOT made
        // here because it moves the shipped fallback plane by that same 1.184 mm.
        let n = inliers.count
        guard n >= 3 else { throw SupportPlaneError.lidarFitDegenerate }
        let cx = inliers.map { $0.x }.reduce(0, +) / Float(n)
        let cy = inliers.map { $0.y }.reduce(0, +) / Float(n)
        let cz = inliers.map { $0.z }.reduce(0, +) / Float(n)
        let centroid = Vec3(cx, cy, cz)

        // Accumulate the symmetric 3×3 scatter matrix in one O(n) pass.
        var m00: Float = 0, m01: Float = 0, m02: Float = 0
        var m11: Float = 0, m12: Float = 0, m22: Float = 0
        for idx in 0..<n {
            let p = inliers[idx] - centroid
            m00 += p.x * p.x
            m01 += p.x * p.y
            m02 += p.x * p.z
            m11 += p.y * p.y
            m12 += p.y * p.z
            m22 += p.z * p.z
        }
        // Column-major 3×3.
        let mCol: [Float] = [
            m00, m01, m02,
            m01, m11, m12,
            m02, m12, m22
        ]
        let svd = try LinearAlgebra.svdFull(mCol, rows: 3, cols: 3)
        // svd.s holds the singular values of M, i.e., the squared singular
        // values of A. Compare √-magnitudes to keep the existing 1e-6 gate.
        let sMaxA = svd.s[0].squareRoot()
        let sMinA = svd.s[2].squareRoot()
        guard sMaxA > 0, sMinA / sMaxA >= stabilityRatioMin else {
            throw SupportPlaneError.lidarFitDegenerate
        }
        // U columns are the eigenvectors of M, ordered by descending singular
        // value. Column 2 is the smallest — the plane normal.
        let nHatCandidate = Vec3(svd.u[6], svd.u[7], svd.u[8])
        var nHat = nHatCandidate.normalised()
        if nHat.dot(seedNormal) < 0 { nHat = -nHat }
        let d = nHat.dot(centroid)
        return (nHat, d)
    }

    static func computeResidual(points: [Vec3], normal: Vec3, d: Float) -> Float {
        guard !points.isEmpty else { return .infinity }
        var sumSq: Float = 0
        for p in points {
            let dist: Float = normal.dot(p) - d
            sumSq += dist * dist
        }
        return (sumSq / Float(points.count)).squareRoot()
    }

    // Minimum (smallest pixel x/y) and maximum (largest pixel x/y) of the food mask.
    struct BBox {
        let minX, maxX: Int
        let minY, maxY: Int
        var heightPx: Int { max(1, maxY - minY) }
        var widthPx: Int { max(1, maxX - minX) }
    }

    static func foodBBox(mask: BinaryMask) -> BBox? {
        var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                if mask.isFood(x: x, y: y) {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX >= 0 else { return nil }
        return BBox(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    }

    // Nearest-neighbour confidence sample. The depth grid may be lower-resolution
    // than the colour grid (256×192 on iPhone 12 Pro vs 4032×3024); we map colour
    // (x,y) to depth (x',y') by simple proportional scaling.
    static func sampleConfidenceNearest(
        depth: DepthMap, colourX: Int, colourY: Int,
        colourWidth: Int, colourHeight: Int
    ) -> UInt8 {
        // No confidence map (e.g. N5k RealSense fixtures) means no confidence
        // filtering: invalid returns are zeroed depth, excluded by the zMm > 0
        // guard. Device captures always carry ARKit confidence.
        guard !depth.confidenceBytes.isEmpty else { return .max }
        let dx = min(depth.width - 1,
                     max(0, Int((Float(colourX) + 0.5) * Float(depth.width) / Float(colourWidth))))
        let dy = min(depth.height - 1,
                     max(0, Int((Float(colourY) + 0.5) * Float(depth.height) / Float(colourHeight))))
        return depth.confidenceBytes[dy * depth.width + dx]
    }

    // Bilinear depth sample (Float32 mm). Returns nil when out of range.
    static func sampleDepthBilinear(
        depth: DepthMap, colourX: Float, colourY: Float,
        colourWidth: Int, colourHeight: Int
    ) -> Float? {
        let fx = (colourX + 0.5) * Float(depth.width) / Float(colourWidth) - 0.5
        let fy = (colourY + 0.5) * Float(depth.height) / Float(colourHeight) - 0.5
        if fx < 0 || fy < 0 { return nil }
        let x0 = Int(fx.rounded(.down))
        let y0 = Int(fy.rounded(.down))
        let x1 = min(depth.width - 1, x0 + 1)
        let y1 = min(depth.height - 1, y0 + 1)
        if x0 >= depth.width || y0 >= depth.height { return nil }
        let ax = fx - Float(x0)
        let ay = fy - Float(y0)
        let z00 = depthValueMm(depth, x: x0, y: y0)
        let z10 = depthValueMm(depth, x: x1, y: y0)
        let z01 = depthValueMm(depth, x: x0, y: y1)
        let z11 = depthValueMm(depth, x: x1, y: y1)
        let zx0 = (1 - ax) * z00 + ax * z10
        let zx1 = (1 - ax) * z01 + ax * z11
        return (1 - ay) * zx0 + ay * zx1
    }

    static func depthValueMm(_ depth: DepthMap, x: Int, y: Int) -> Float {
        let offset = (y * depth.width + x) * 4
        // Float32 LE per §6.0; on little-endian Apple silicon this is a direct read.
        var value: Float = 0
        depth.depthBytesMm.withUnsafeBytes { rawPtr in
            value = rawPtr.loadUnaligned(fromByteOffset: offset, as: Float.self)
        }
        return value
    }
}

# Design: Support Plane Reference

## Overview

Replace "largest gravity-aligned plane in the frame" with "the gravity-aligned plane the food is resting on", by bounding the candidate samples to the food's neighbourhood, scoring candidates on the size of their largest connected inlier component rather than raw inlier count, and selecting on measured contact with the food. Rejection routes to today's fit unchanged.

## Architecture

### What changes and what does not

`ransac`'s minimal sampling, the 15° gravity cone, `refine`'s scatter-matrix SVD and the deterministic consensus polish are correct and reused. Three things change: **which samples compete**, **how a candidate is scored**, and **which candidate wins**.

### Bound the candidate set to an annulus

**Today's set is already bounded — an earlier draft of this design asserted otherwise and was wrong.** `collectCandidatePoints` defaults to `.bandsAroundFoodRegion` (`LiDARPlaneFitter.swift:61`) and scans four bands around the food bbox, each as thick as the bbox dimension perpendicular to it (`:237-250`), added by `lidar-plane-fit-degenerate-on-clean-capture`. `.insideMask` has exactly one caller, `FixtureRunner` (`:251`). Floors and hobs are not competing for candidate slots; the table is, from inside a region of roughly `4 · w · h`.

That refutes the earlier proposal rather than refining it. `dilate(foodMask, 2 × foodRadius)` spans ≈ `(2.9 s)² ≈ 8.3 s²` against the bands' `4 s²` for an `s × s` bbox — **looser than today, not tighter** — so none of the three benefits that draft claimed follow from it.

The bound that does deliver them is an **annulus of `annulusOuterMm` around the food mask**: 50 mm of support surface, concentric with the food rather than square with its bbox. (It was written as `2 × ringOuterMm` until Decision 49 measured what that coupling cost and re-denominated it in millimetres at the same value.) It is tighter than the bands for any food that does not fill its bbox, and it is the same region the ring measure already reads, so it introduces no new scene-dependence.

**Where the sample reduction actually comes from.** The ~56× is the native-depth-grid move (Req 2.4), not the bound: 1920×1440 ÷ 256×192 = 56.25. That change stands on its own, and it is where the CPU headroom for the extra passes comes from. Crediting it to bounding, as the earlier draft did, double-counted one saving and hid that the bound was doing the opposite of what was claimed.

**Where the iteration budget actually comes from.** ~~Not from a raised pass-1 inlier ratio. At the diagnosed capture's ~6 % plate fraction, `maxIterationsPerPass = 2048` reaches only ~36 % probability of a clean triple — an order of magnitude short. The budget is sufficient because extraction is **sequential**: pass 1 removes the table's inliers, and it is the plate's fraction *of the residue* that pass 2's formula applies to.~~ **Superseded by Decision 51**: measured on the corpus, the pass-1 inlier ratio is **0.402 and 0.698**, six to twelve times the ~6 % quoted here, and at those ratios the 0.99 target is met in 69 and 12 iterations. The budget is sufficient because the dominant plane is *easy*; the sequential structure is not what pays for it, and `maxIterationsPerPass` never fires at all. The implementation MUST report the per-pass residue inlier ratio so this holds as a measurement rather than an assumption — which is what caught it.

### Native depth grid, and the intrinsics trap

Sampling moves to the native 256×192 grid (Req 2.4), which removes the ~56× replication that made the wrong fit look confident. Two consequences the implementation must handle explicitly:

**`depth.depthIntrinsics` is unusable on device.** `ARKitCaptureEngine` writes `CameraIntrinsics(fx: 0, fy: 0, cx: 0, cy: 0, …)` — only width and height are real, and it has no production readers today. Back-projection must derive depth intrinsics from the colour ones:

```
fx_d = fx_c · W_d/W_c        cx_d = (cx_c + 0.5) · W_d/W_c − 0.5
```

The convention matches `sampleDepthBilinear` (`LiDARPlaneFitter.swift:440-441`), which already resamples this way, so the derivation is consistent with existing code rather than a new claim.

**Severity, corrected — an earlier draft ranked these backwards.** The three failure modes are not comparable:

| Mistake | Consequence | Severity |
|---|---|---|
| Read `depth.depthIntrinsics` | fx = 0 → divide-by-zero → NaN plane | **Fatal, obvious** |
| Pass `colourIntrinsics` through unscaled | fx wrong by 7.5×. At nadir the *plane* barely moves (z is unchanged), but every mm-denominated radius is corrupted — the 8–25 mm ring silently becomes a 1–3.3 mm ring | **Fatal, silent — the one to guard** |
| Drop the half-pixel terms | principal point off by `0.5(1 − s)` = 0.433 depth px = **3.25 colour px** (not 3.75). Induced plane tilt ≈ 0.016° | **Cosmetic here** |

The half-pixel terms are still correct and should be implemented, but they were previously called "the most likely implementation bug in the feature" on the strength of a tilt that is three orders of magnitude below the gravity cone. The unscaled-intrinsics case earns that label: it leaves the plane fit looking healthy while every ring radius is 7.5× too small, which no plane-level assertion catches.

**Mask downsampling needs a stated rule.** `BinaryMask` is colour-grid; the ring and candidates are depth-grid. A depth pixel is marked food if **any** covered colour pixel is food (conservative — Req 2.1 requires the fitted set to contain no food pixel, so ambiguity must resolve towards exclusion).

`.insideMask` is **not** reused: its branch iterates the colour grid and is the replication being removed. It stays for the harness's existing callers until they are migrated.

### Candidate scoring — CC-RANSAC

Score a candidate by **the size of its largest 8-connected inlier component**, not by total inlier count (Gallo, Manduchi & Rafii 2011). This subsumes the connected-component adjacency filter Decision 11 staged second: adjacency becomes a property of the score rather than a separate pass with its own constant.

**What component scoring does and does not buy, stated narrowly.** An earlier draft claimed it defeats the straddling plane and that this is what stops the plate rim being mis-fitted. Adversarial review refuted both halves.

It cannot prefer the plate over the table: the table is a genuine single surface with a far *larger* connected component, so component scoring makes the table win a pass more decisively, not less. What surfaces the plate is sequential extraction removing the table in pass 1, and then ring-based selection choosing among the residue.

**Whether the smeared ramp bridges the two inlier sets is contested and unresolved.** One review argued it does: the rim descends ~26 mm over ~5–6 depth pixels, so a plane tilted 6.7° (inside the 15° cone) crosses it and joins plate-side to table-side inliers through a stripe ~1–2 px wide, which 8-connectivity needs only 1 px to use. A second review refuted that from the cone: the ramp's own slope is ~73°, a 15°-capped plane rises only ~2.1 mm across its whole width, so the plane cannot *track* the ramp and any bridge is local to a single crossing rather than an annular seam. Both are right about their own claim — a plane cannot follow the ramp, but it does not need to if one crossing suffices. **Task 26 settles it by measurement; neither reading may be assumed.**

**What the source paper does settle, and it is more useful.** Gallo et al. state outright that *"for large enough values of ε, an incorrect plane straddling across the two patches will produce a large number of connected inliers"*, and their Fig. 4 gives the operating envelope: reliable while **ε/h ≲ 0.25–0.35** (h = 5 reliable to ε = 1.25; h = 10 reliable to ε = 3.5). With `inlierBandMm = 5`:

| Step | h | ε/h | |
|---|---|---|---|
| Plate above table | 26 mm | 0.19 | inside the validated envelope |
| Rim above well, deep plate | 28 mm | 0.18 | inside |
| Rim above well, narrow rim | 12 mm | 0.42 | **outside** |
| Rim above well, minimum | 10 mm | 0.50 | **outside** |

So component scoring is validated for the defect this feature fixes and **not** validated for the rimmed-plate case Req 3.8 and Decision 14 exist to handle. Three further transfer gaps: the paper's model is orthographic with a hard step and vertically-i.i.d. noise — no ramp, no perspective, no spatially-correlated smoothing; the paper warns CC-RANSAC is *worse* than plain RANSAC at very small ε, because components become too small to support the correct plane, which bears on this design's ~4× smaller sample set; and the rim measurement the envelope depends on is one of the ruler measurements prerequisites asks for.

What actually rejects such a straddler is the ring guards. The aggregate bar sits close to its threshold — for a 6.7° tilt over the inner ring, support fraction ≈ 0.56 against a 0.60 minimum — but the sector guard does not: a tilted plane's in-band samples concentrate in the arcs near its zero-crossings, so its supporting sectors fall well short of the bar. The aggregate margin is a measurement to confirm on the corpus, not one to rely on.

Component scoring is retained for the case it genuinely handles — a co-height surface elsewhere in the annulus (a second plate, a board) forms a separate blob and is excluded on connectivity.

**Extraction loop.** Up to `maxCandidatePlanes` passes; each removes the **polished** inlier set within `inlierRemovalMultiple × inlierBandMm`. (The multiple was justified here by "a thin shell left at 1× seeds near-duplicate planes on the next pass"; Decision 50 measured that and found it false — no adjacent pass pair is a near-duplicate at any multiple, because CC-RANSAC keeps the largest *connected* component and what a 1× shell leaves is a thin ring around a surface already taken. The constant is `[owed]` and bracketed 1…2.5×.) Stops early when the residue falls below `minResidueAreaMm2` — named for the one question it asks, since the whole-fit sufficiency question it also used to answer is now asked exactly (Decision 32, below), and denominated in millimetres² so the pass count follows the scene rather than the depth grid (Decision 38, below).

**Iteration budget.** `maxIterations = 256` was sized to find the *dominant* plane. `P(clean triple) = 1 − (1 − w³)^N` gives 98 % at w = 0.25 but 23 % at w = 0.10 and 3 % at w = 0.05. Bounding the sample set keeps the plate well above 0.25 in the common case, but the budget must not be inherited on faith: each pass uses **adaptive stopping** — recompute the required `N` from the best inlier ratio seen so far and stop when reached, capped at `maxIterationsPerPass`. Deterministic, because the ratio sequence is deterministic.

### Selection and admissibility

**Guards are an admissibility filter applied to every candidate, then the best admissible candidate wins.** Applying them after selection would let a phantom rim-ramp plane win the score, fail a guard, and drop a capture to fallback while an admissible plate plane sat in the candidate set.

| Guard | Rejects | Req |
|---|---|---|
| ring support fraction < `ringSupportMin` | ring not resting on this plane | 3.2 |
| supporting sectors < `minSupportingSectors` | ring crossed the support's edge, or straddles two surfaces — in-band support confined to an arc | 2.3, 3.6 |
| food's p90 signed height above the plane < `foodEnvelopeMinMm` | vessel rim, or a plane on the food top | 3.4 |
| \|ring median\| outside the documented band, **signed** | table (+) or raised edge (−) — the sign is what separates them | 3.1, 3.2 |
| **inner→mid** band step > `bandStepMaxMm` rising outward | the surface the ring rests on is not flat — bowl wall, or a rim beginning inside the ring | 3.8 |
| support visibility < `supportVisibilityMin` | support surface not observable under the food | 3.9 |
| plane below the annulus median height by > `escapeBandMm` | region escaped through a depth dropout | 3.3 |
| fewer than `minAcceptedExtentMm` inlier bbox extent | badly conditioned normal | 2.3 |

**Support is measured per angular sector, because the aggregate fraction is a majority vote.** Divide the inner band into `ringSectorCount` equal sectors — arcs of equal angle about the food-mask centroid — and count those whose own support fraction meets `sectorSupportMin`. A ring lying wholly on the support surface supports uniformly; a ring that has crossed the support's edge supports in an arc — 65 % on the table is 100 % table across ~235° and 0 % across the rest, which the aggregate reports as a healthy 0.65. Without this, food reaching within ~14 mm of a plate's edge selects the *table* plane, passes every other guard, and persists a ring median of ≈ 0 — the value this design treats as proof of correctness (Decision 18). Cost is one `atan2` and a bucket index per ring sample, reusing the samples radial banding already collects. A sector with no samples counts as neither supporting nor failing, and the bar stays absolute — so a ring heavily clipped by the frame edge loses sectors and fails towards fallback rather than passing on a majority of what remains.

**Sectoring is statistically viable at realistic captures, and the sample floor is derived from it.** At 350 mm range the depth grid resolves ~2 mm/px (the same ~4-px smear figure §Stated limits rests on), so each radial band is 17/3 ≈ 5.7 mm ≈ 2.8 px wide, and a 35 mm-radius food's inner band holds ≈ 400 samples — ~50 per sector; at 500 mm the same food yields ≈ 260, ~33 per sector. The regime that fails is small-and-far: at 25 samples a 0.5 sector bar has binomial σ ≈ 0.10 and separates a supported sector (p ≈ 0.9) from a crossed one (p ≈ 0.3) by > 4σ, but at the previous floor of `ringMinSamples = 60`, sectors averaged 7 samples (σ ≈ 0.19) and a uniformly supported ring at true support 0.6 false-failed the guard roughly two captures in five — noise, not measurement. `ringMinSamples = 200` (= `ringSectorCount` × 25) closes that regime without adding a per-sector constant; the cost is that food smaller than ~25 mm across at 350 mm (~50 mm at 500 mm) falls back — the items the perimeter-smear bias measures worst anyway (Decision 20).

**There is no MAD guard — the sector measure is the dispersion bar Req 2.3 requires.** Decision 16 gave the straddle guard to inner-band MAD; checking its arithmetic against the admissibility floor shows it cannot fire on any candidate that matters. For a two-surface mixture, the in-band majority puts the median on the supported surface, so MAD collapses to the noise scale at any mixture away from 50/50 — and a near-50/50 candidate scores ≈ 0.5 aggregate support and fails `ringSupportMin = 0.6` first. The one straddler the aggregate bar misses, the 6.7° rim-ramp tilt, reads MAD ≈ 5.6 mm and slips under the 6 mm bar. That is the same class of defect as the residual bar Decision 16 itself removed: a bar positioned where it cannot fire. The sector guard covers the whole mixture range instead — support confined to an arc fails it at any fraction beyond roughly two sectors' width — so the MAD bar, its constant and its persisted field are deleted rather than carried as a third inner-band statistic (Decision 19).

**Score.** Among admissible candidates, maximise the ring support fraction — the share of ring samples within ±`ringBandMm` of the plane. **Not** `|median|` closest to zero, which has a 50 % cliff: a ring half on the plate and half on the table has a median that jumps 26 mm as the mixture crosses half, and just past the cliff the *table* plane reads ≈ 0, passes every guard, and is persisted with a textbook-perfect diagnostic. The support fraction degrades continuously instead, and the sector guard reads the straddle's spatial arrangement directly.

**Ambiguity margin.** If the top two admissible candidates are within `ringSupportMarginMin` of each other, reject to fallback. Two candidates 26 mm apart both scoring near-equally is exactly the straddling-ring case, and a coin flip between them moves the carb number 3×.

### Why there is no separate residual bar

An earlier draft added `restrictedResidualMaxMm = 8`, justified by "a straddling region fits at ~13 mm RMS". That is a property of plain least squares over a fixed region — the flood-fill option Decision 11 rejected. Under RANSAC the residual is computed over `polishedInliers`, each within `inlierBandMm = 5` of the plane, so RMS is **≤ 5 mm by construction** and the bar can never fire (`LiDARPlaneFitter.swift:25, 136-140`). It would also push matte-table captures onto the fallback, since pipeline Decision 46 raised the general bar to 20 mm for genuine single-surface depth noise. The sector measure reads the straddle directly and does fire; the inner-band MAD bar Decision 16 first put here turned out to share the residual bar's cannot-fire defect and is deleted in turn (Decision 19).

Req 2.3 originally mandated the residual bar. It has been **amended** rather than quietly ignored — it now requires a dispersion bar on the ring's inner band and explicitly forbids a plane-residual bar for this purpose (Decision 16). The sector support measure is that dispersion bar: it bounds the angular dispersion of in-band support and rejects the straddling fit Req 2.3 names (Decision 19). A design that refutes a requirement without amending it leaves two documents disagreeing in writing.

### Fallback ladder (Req 4, Decision 5 ordering)

Restricted fit **first**; on any rejection, the edge-band fit runs and returns byte-identical results (Req 4.3). The edge-band fit is **lazy** — computed only on the rejection path. The below-fallback guard uses the lowest admissible candidate rather than the edge-band plane, so nothing needs it eagerly.

This preserves Decision 5's stated sequence and has a second benefit: `lidar-plane-fit-degenerate-on-clean-capture` widened the bands because the band scan starves on clean captures. The restricted path samples natively and is immune to that failure, so attempting it first recovers captures that would otherwise refuse.

**Cost, stated honestly.** This is *added* work on the success path, not a replacement — the earlier draft's "not slower than today" compared against the harness's deleted path, not the device's. Added: bounded depth-grid collection, up to 3 adaptive RANSAC passes, ring construction, per-band medians. Removed on the success path: the full edge-band colour-grid scan. Req 7.6's budget is measured on device, not asserted here.

**Connected-component labelling is the dominant term and an earlier draft omitted it.** Decision 13 puts CC scoring *inside* the loop, so it runs per hypothesis, not per pass winner: up to `maxIterationsPerPass × maxCandidatePlanes` labellings over the annulus. That is order 10⁸ operations on the path that already produced a 32 GB allocation failure. **Amortise it** — label only hypotheses whose raw inlier count is within a constant factor of the running best, since a hypothesis that cannot win on raw count cannot win on component size either. Without the amortisation the CC cost, not the extra passes, is what Req 7.6 will fail on.

**Confidence.** `sigmaPlane` gains a third factor, 1.0 on `.foodSupport` and `fallbackPenalty` on `.edgeBand` (Decision 12). The factor is denominated in millimetres of plane error — σ_plane is exp(−r/5), so p charges −5·ln(p) mm — and the shipped 0.9 charges 0.53 mm against a measured 18.37 mm (Decision 36, below).

### The rimmed-plate case

Food rests on a plate's **well**; the **rim** sits 10–28 mm above it. If the ring lands on the rim, the rim plane is selected and food height is clipped — a silent under-read, and the inversion Decision 3's harm ordering assumes cannot happen.

**Exposure, measured against ordinary dinnerware.** With the ring at 8–25 mm outside the food boundary, it lands wholly on the rim only once food covers **78–86 % of the well area** — a heaped plate, not a normal serving. Below that the ring is mostly on the well. But when it does hit, the error is large and in the dangerous direction:

| Plate | Rim above well | Food 25 mm tall | Food 40 mm tall |
|---|---|---|---|
| Dinner, wide rim | 18 mm | −72 % | −45 % |
| Dinner, narrow rim | 12 mm | −48 % | −30 % |
| Pasta / deep plate | 28 mm | — | −70 % |

Today's table reference over-reads by +26 mm; a rim reference under-reads by 12–28 mm. Comparable magnitude, opposite sign — so for this case alone the correction could move the error the wrong way.

**Radial ring profile.** The ring is resolved into inner / mid / outer bands rather than reduced to one median. The profile is diagnostic, and it distinguishes the cases a single median conflates:

| Radial profile | Scene |
|---|---|
| flat across bands | plate well, board, or table — one surface |
| **rises outward** | **rimmed plate with the well partly visible** |
| rises steeply outward | bowl wall |
| falls outward | ring has leaked past the plate edge onto the table |

Selection then uses the **inner band** as authoritative (Req 3.8) — the support surface is by definition the one immediately adjacent to the food — with the outer bands as shape detection. This resolves the partial-fill case *correctly* rather than merely rejecting it: the well plane is already in the candidate set, it was simply not being preferred. It also subsumes the leaked-ring detection, which the earlier single-median design needed MAD to catch.

**The step guard reads the inner→mid step only (Decision 21).** The well plane's own profile *rises outward* whenever the ring spans well and rim — inner ≈ 0, outer ≈ +18 — so a guard firing on any outward rise would reject the exact candidate Decisions 14 and 16 exist to rescue, the same contradiction Decision 16 removed from whole-ring MAD. A rise between mid and outer is a rim beginning ≥ ~14 mm out: shape detection, inner band stays authoritative, well plane wins. A rise already present at inner→mid means the surface the ring itself rests on is not flat — a bowl wall, or a rim hard against the food — and rejects to fallback, the conservative direction.

**Support visibility, for the case that cannot be solved.** When food fills the well, the well surface produces **no depth samples at all** — nothing in the frame touches it. No candidate plane can be fitted to an unobserved surface, and no ring geometry recovers one; this is a sensing limit, not an algorithm choice. It is however detectable: when the visible support region is too thin relative to the food region (`supportVisibilityMin`), the support surface cannot be verified and the fit falls back (Req 3.9). That routes the unobservable case to the edge-band over-read, which is the direction a human catches.

This is the `region area ÷ food-mask area` check Decision 9 kept as a secondary guard and an earlier draft dropped. It returns with a job it is suited to — an observability test, not a selection score, which is what it was rejected as.

**Residual risk, stated.** A fully-filled rimmed plate whose food mounds well above the rim can still pass the visibility test with the ring flat on the rim, and will under-read by the rim height. The persisted radial profile identifies the case only when the ring extends past the rim and the profile falls outward; a ring lying wholly on a wide rim records a flat profile, uniform sectors and a median of ≈ 0 — indistinguishable from a correct fit in the record. This is the one wrong-plane path that survives with healthy diagnostics, and it is bounded by the weighed-truth checks (Reqs 7.2, 7.3, 7.8) rather than by the record.

### Three guards that did not do what their requirement says

Found by adversarial review; all three are stated in the requirements and were mis-implemented in the design rather than merely unmeasured (Decision 22).

**`foodAboveFractionMax = 0.05` rejected this feature's own acceptance capture.** Decision 4 brackets `1785901032716` at 236–262 cm³, an ~11 % spread attributable entirely to the overhanging bread slice. Overhanging food sits *below* the plate plane, so at roughly uniform thickness ~11 % of food samples are "above the plane" by this guard's reckoning — against a 5 % bar. The capture would fall back, return 714.84 cm³, and **fail Req 7.2**, while also contradicting Reqs 1.3 and 3.4 and the design's own "overhanging food — guards must not fire" test case.

The root cause is one constant serving two opposed purposes. Decision 3 uses "plane above a share of food points" to route **bowls** to fallback, where it must fire; Req 3.4 uses the same test to tolerate **overhang**, where it must not. Bowls want the bar low, overhang needs it above 11 %. No value serves both.

Replaced by an **upper-envelope test**: reject when the food's `foodEnvelopePercentile` signed height above the plane falls below `foodEnvelopeMinMm`. Bread — p90 **measured at +26.6 mm** above the plate plane (the +8 mm first written here was an estimate, low by 3× — Decision 34), accepted, and the overhanging slice's samples simply sit in the lower decile where they belong. Bowl — all food lies below the rim plane, so p90 is negative, rejected. Plane on the food top — p90 ≈ 0, rejected. One constant, three cases, and it is denominated in millimetres, which is what Req 3.4 asks for and what the fraction quietly substituted away.

**Req 3.3's guard could not fire.** "Plane below the lowest admissible candidate" compares the minimum of a set against itself, and is circular besides, since admissibility is defined partly by this test. Req 3.3 names the *edge-band* plane as the comparator; the substitution existed only to keep the edge-band fit lazy, which is an optimisation preference, not a comparator. Replaced by the **annulus median height**, already computed and free, with `escapeBandMm` as the band. A plane that escaped through a depth dropout lands far below the surrounding surface and is caught; the edge-band fit stays lazy.

**Req 3.2's signed guard was never implemented.** The design persists `medianMm` but the guard table contained no `|median|` test — only the unsigned support fraction, which cannot distinguish a plane *above* the ring from one *below* it. Req 3.1 is explicit that the sign carries the meaning: table reads strongly positive, a vessel rim reads negative. Restored as a guard row.

### The ring crossing the support's edge

Distinct from the rimmed-plate case above, and more dangerous, because it reinstates the defect this feature exists to remove while recording a clean diagnostic. Food reaching within ~14 mm of a flat plate's edge puts the majority of the *inner* band on the table; aggregate support then favours the table plane. The radial profile is **flat**, not falling — Decision 14's "leaked outward" row describes a ring only partly past the edge and does not fire here.

The sector guard is the answer (Req 3.6, Decision 18), and its constants are corpus measurements rather than assertions (Req 3.7). Two further consequences are carried deliberately:

- **A ring median of ≈ 0 is not evidence of a correct fit.** Req 6.2's before/after comparison still holds — the pre-feature fit does read +18…+26 mm — but the converse does not, and Req 6.4 exists so the record carries the sector evidence needed to tell the cases apart.
- **A known-better alternative is deliberately unbuilt.** Preferring the highest admissible candidate encodes the physical constraint directly and is deferred, not rejected (Decision 18). If corpus measurement shows the sector guard rejecting captures it should accept, that is the next mechanism, not a new constant.

**`ringSupportMin = 0.6` is in tension with the matte-table evidence and must be measured against it.** A ±5 mm band at 0.6 support implies σ_z ≲ 5.9 mm on the support surface. `lidar-plane-fit-matte-table-confidence` and pipeline Decision 46 exist because matte tables produce genuine single-surface noise large enough to justify a 20 mm residual bar. If that noise exceeds ~6 mm in practice, every matte-table capture falls back and Req 4.5's fallback-rate defect fires for a reason unrelated to plane selection. Task 26 must measure the support-surface noise distribution before this constant is fixed.

### Stated limits (Req 2.5)

**The limit is on food *width*, not food height — an earlier draft had this the wrong way round.** It read "minimum resolvable food height ≈ 8 mm", derived from "~4 depth pixels of smoothing, so a step spreads to 4–6 mm/px". That conflates a lateral extent with a vertical one: 4–6 mm/px is the gradient of one particular plate step, and ~8 mm is the smear's *lateral* footprint.

Smoothing is approximately a unit-DC-gain low-pass filter: it preserves the amplitude of any plateau wider than its kernel and only widens the transition. So the two real limits are:

| Limit | Value | Mechanism |
|---|---|---|
| **Minimum food width** | ≈ 8 mm at 350 mm range | Food narrower than the ~4-px kernel is amplitude-attenuated and genuinely unrecoverable |
| **Minimum food height** | ≈ 2–4 mm | Bounded by depth noise and support-plane fit error, not by lateral smear |

A 3 mm-tall item 100 mm across occupies ~2,700 depth samples, so per-pixel noise averages down by ~50× and its plateau survives intact. Req 2.5 must therefore state a *width* bound; stating an 8 mm height bound excludes a measurable class of flat food for no sensing reason. Both figures scale with capture range — the ~8 mm width floor is ~6 mm at 300 mm and ~10 mm at 500 mm — so Req 2.5's statement must carry the capture-distance envelope rather than a bare constant.

**The same range dependence bounds `ringInnerMm`, and it is left as a range bound rather than repaired (Decision 39).** The width floor above and the ring's inner radius are the same 4 px measured twice, so `ringInnerMm = 8` covers the smear only out to `ringInnerMm × f_d / 4` — **364.1 mm** and **366.4 mm** on the two committed captures, which stand at **93.1 %** and **92.0 %** of it. Scaling the radius with `mmPerPx`, as Decision 29 instructed, is measured and rejected: `mmPerPx` is `z/f_d` and carries range and grid resolution alike, while only range moves the smear, so at 128 px it reads 14.9 mm for a physical smear still near 7.4 mm and leaves three ring bands each narrower than one depth pixel — costing the 2× transfer Req 5.1 is stated against. This is the boundary of the conversion Decisions 37 and 38 rely on: `mmPerPx` repairs grid dependence and cannot repair range dependence. The envelope is closed by recording the capture range, which `prerequisites.md` now requires per capture.

Edge behaviour is the residual: the smear under-reads a border strip roughly half a kernel wide around the food's perimeter, which is a perimeter-proportional bias and therefore worst on small items.

### Voxel-carve exposure (Req 1.6)

**Measured: correcting the plane changes the excluded-voxel count by zero.** The prediction in the parity audit — that raising the plane ~26 mm deletes a slab of voxels, and compounds with Decision 4's overhang — assumed a grid fixed in space with the plane sliding through it. The grid is not fixed. `VoxelGridSizer` anchors `originCamera1` **on** the support plane (the food-mask centroid back-projected onto it), and `VoxelGrid.voxelCentre` offsets every voxel along `axisZ` by `dz = (iz + 0.5) · edgeMm`, which is strictly one-signed. Raising the plane translates the entire grid with it, so every voxel keeps its signed distance and `signedDistance < 0` decides identically before and after. `VoxelCarvePlaneExclusionTests` measures this at the diagnosed 26.1 mm rise and asserts the delta is 0.

The real consequence is a **translation, not a deletion**: the ~26 mm between the table and the plate top used to lie inside the grid and now lies outside it. Food overhanging below the plate leaves the grid rather than being dropped by the plane test — the same under-measurement Decision 4 already accepts and brackets at ~11 %, reached by a different route. **Nothing compounds**, because both mechanisms are the same 26 mm counted once.

**A separate defect the measurement surfaced, deliberately not fixed here.** The absolute counts are not benign even though the delta is zero. Under the convention `Pipeline` actually passes — `nadir.gravity`, which `CameraGravity` documents as world-**up** in the camera frame — `axisZ = −gravity` points down, the grid extends *below* the plane, and **every voxel is excluded**: 23,040 of 23,040 in the measured case, before and after. Under the opposite convention the volume tests use (`(0,0,−1)`, commented as gravity pointing down) none is. The two-view carve therefore recovers no volume at all on a LiDAR device whose depth-derived plane reaches it, which is consistent with the ~10× under-read measured on 2026-08-05. That belongs to `bugfixes/two-view-carve-no-volume`; the two-view carve's accuracy is an explicit Non-Goal here, and the Req 1.6 answer holds under either convention, so this feature does not turn on resolving it.

### Document amendments (Reqs 1.4, 5.2)

Edits, not cross-references: pipeline Req 4.2, pipeline design §6.2, the pipeline glossary, `DECISIONS.md` MD-9 (superseding entry, not a silent rewrite), and — added after review — the `nutrition5k-calibration` transfer contract (Req 5.2), which Req 3.6 of that spec already contradicts.

### Pattern parity audit

| Site | Needs the new path? | Rationale |
|---|---|---|
| `Pipeline.fitSupportPlane` (`Pipeline.swift:638`) | **Yes**, via the fitter | The device path being fixed |
| `HarnessCore/FixtureRunner.run` single-view | **Yes** | Req 5.1 parity; private copy deleted |
| `FixtureRunner` two-view branch | **No** | Silhouette carve, no depth plane (Decision 7) |
| `CardOnlyPlaneFitter` | **No** | No depth map |
| `CalibrationArtifact.mixtureObservation` (`:157`) | **Yes — and it cannot take the new path** | Live caller of `fitPlateRegionPlane`. No mask exists at this site; see below |
| `CalibrationArtifact` artefact fields | **Metadata only** | Records the reference (Req 5.3) |
| `VoxelCarveEstimator` | **Consumer, no change** | Excludes `signedDistance < 0` — a **hard** exclusion, unlike the height field's `max(0, ·)` clamp. This row previously predicted that raising the plane 26 mm would delete a slab and compound with Decision 4's overhang. **Measured under Req 1.6 and superseded: the excluded-voxel count does not change** — see "Voxel-carve exposure" below |
| `HeightFieldEstimator.integrate` | **Consumer** | Formula unchanged |
| `DiagProbe/main.swift` | **No** | Throwaway probe from the diagnosis; delete. (It is *tracked*, not untracked as this row first recorded — `git rm`, and the `CHANGELOG` entry that introduced it stays as history) |
| `PlateRegionPlaneTests` | **Keep** | The flood fill survives for the mixture path (above), so its tests survive with it |
| `PlateTopSupportPlaneTests` (`Tests/VolumeTests/`, `XCTSkip` at `:55`) | **Yes** | Un-skip; it encodes this resolution |

### Deleting `fitPlateRegionPlane` rebases the N5k corpus

Device bundles stamp `estimatorPath = "single_dominant"`, so both device replays and single-dominant N5k fixtures currently take `fitPlateRegionPlane` via `FixtureRunner.run:82`. Moving them to the promoted path changes N5k outputs and therefore every previously recorded `nutrition5k-calibration` result. Those results must be regenerated, and the corpus then spans two references — which is what Req 5.4 exists to handle.

**Mixture fixtures do not move** (above), so the rebase covers the single-dominant slice only. The regenerated corpus therefore spans two references *by construction*, not merely in transition, and Req 5.4's within-reference fitting rule is permanent rather than a migration measure.

The harness has no food mask at that call site today (`fitPlateRegionPlane` takes only depth, intrinsics, gravity). It derives one from `nadirSeg`'s argmax, the same source the device's segmenter produces, so Req 5.1 parity holds.

### The mixture calibration path keeps the flood fill

`fitPlateRegionPlane` has a **second** caller that an earlier draft's audit recorded as metadata-only: `CalibrationArtifact.mixtureObservation` (`:157`), reached from `HarnessCLI/main.swift:397` and `:542`. Deleting the function without an answer here breaks the mixture β_c path.

The `FixtureRunner` migration does not transfer. **Mixture fixtures carry neither `probs_hwc` nor `argmax_hw`** (`docs/agent-notes/nutrition5k-ingestion.md`), and `mixtureObservation` feeds `TotalHullVolume.integrate`, which is plate-wide rather than per-class. There is no segmentation output at that site from which to derive a `foodRegionMask`, and `fitFoodSupportPlane` requires one. This is a data limitation, not a wiring gap.

**Decision: `plateRegionMask` and `fitPlateRegionPlane` survive as the mixture path's fitter, scoped to it.** The mixture corpus is a fixed overhead rig where the flood fill's frame-centre seed assumption *does* hold — the assumption Req 2.2 rejects for handheld capture. Retaining it there is correct for that corpus rather than a concession.

Consequences that must be carried:

- The Req 5.2 transfer contract records `supportPlaneReference` per artefact. Mixture artefacts record the plate-region reference, single-dominant artefacts record `foodSupport`, and Req 5.4 keeps β_c fitted within a reference. Nothing may mix them.
- `PlateRegionPlaneTests` is **not** deleted — the earlier audit's "delete with the code" row is withdrawn for the mixture path's sake.
- Failure at this site must not stay silent. Both callers wrap `mixtureObservation` in `try?`/`catch` and convert a throw into a skip (`planeFitSkipped`, `officialSkipped["plane_fit_failed"]`), so a broken fitter would empty the mixture corpus while the run still reported success. The skip counts MUST be reported, not just collected.

## Components and Interfaces

```swift
// MedataCore/Sources/SupportPlane/SupportRegion.swift

public enum SupportPlaneReference: String, Sendable, Codable {
    case foodSupport, edgeBand
    // Superseded by Decision 25: a third case, `plateRegion`, is added for the
    // mixture calibration path. With two cases a mixture artefact has no value to
    // record, so Req 5.4's within-reference rule is unenforceable and Req 5.3
    // treats the mixture β as absent-and-therefore-blocked. Never produced on
    // device or by the single-view replay.
    case plateRegion
}

public struct RingStatistics: Sendable, Equatable {
    public let medianMm: Float          // whole ring; ≈ 0 on a correct fit, +18…+26 on the table.
                                        // Persisted for Req 6.2; NOT used for selection.
    public let bandMedianMm: [Float]    // inner/mid/outer; rises outward on a rimmed plate.
                                        // Persisted (Decision 14) — the rim/bowl signal.
                                        // The step guard reads [0]→[1] only (Decision 21).
    public let supportFraction: Float   // share within ±ringBandMm, INNER band — the score
    public let supportingSectors: Int   // inner-band sectors meeting sectorSupportMin; empty
                                        // sectors count as neither supporting nor failing.
                                        // Persisted (Req 6.4): a median of ~0 is NOT
                                        // evidence of a correct fit on its own
    public let bandSampleCount: [Int]   // ringMinSamples holds PER band (Decisions 14, 20)
    public let supportVisibility: Float // see below; computed from the annulus, not the ring
}

public enum SupportRegion {
    // Radii in MILLIMETRES, converted per capture from median food depth.
    // Provenance: [derived] derivation in this document; [measured] derivation
    // confirmed against the committed corpus (Decision 29); [inherited] from a named
    // tested constant; [owed] a task 26 corpus measurement — shipping an [owed]
    // value as-asserted is a defect, and for the sector trio Req 3.7 says so.
    public static let ringInnerMm: Float = 8   // [measured] 4 px smear is 7.45 and
                                               // 7.36 mm at 338.9 and 336.9 mm; the
                                               // envelope is ≈ 365 mm (Decision 29)
    public static let ringOuterMm: Float = 25  // [owed] the "inside the smallest measured
                                               // plate margin" rule is unsatisfiable —
                                               // measured margins reach 4 mm, inside
                                               // ringInnerMm (Decision 33); bracketed
                                               // 22…32 mm, floor from Req 5.1's halving
                                               // and ceiling from the committed suite,
                                               // and NOT a constant that moves the
                                               // selected plane after all — 0.000 mm at
                                               // every radius once the candidate bound is
                                               // pinned, so Decision 46's movement and its
                                               // "do not interpolate" belong to
                                               // annulusOuterMm (Decision 49)
    public static let ringBandCount = 3        // [owed], bracketed 2…3 — the tightest
                                               // bracket in the feature, shipped value ON
                                               // the ceiling. Floor from the bandStep
                                               // guard's EXISTENCE (silent at one band) and
                                               // from the suite; ceiling from Req 5.1's
                                               // halving, the third constant off it. Moves
                                               // no plane (0.000 mm) (Decision 47)
    public static let bandStepMaxMm: Float = 6 // [owed] below the smallest measured rim
                                               // step; UNEXERCISED — every corpus step is
                                               // a fall, −0.5…−6.5 mm (Decision 34);
                                               // denominated in ringBandCount, whose suite
                                               // interval collapses 13.470→0.211 mm over
                                               // 2…6 bands and inverts above (Decision 47)
    public static let supportVisibilityMin: Float = 0.15 // [owed] capture 4 sets the value;
                                               // firable — the ratio is over the annulus,
                                               // ceilings 1.710/1.426 (Decision 29) — but
                                               // never fired; corpus floor 0.246 (Dec. 34)
    public static let ringBandMm: Float = 5    // [inherited] inlierBandMm = 5
    public static let ringSupportMin: Float = 0.6 // [owed] measured per-sample σ is
                                                  // 3.44 and 6.98 mm at the same range —
                                                  // the corpus straddles ringBandMm and
                                                  // a matte capture is needed (Decision 29)
    // Sector measure (Req 3.6, Decisions 18–20). Sectors are equal arcs about the
    // food-mask centroid; empty sectors count as neither supporting nor failing,
    // and the bar is absolute, so heavy frame clipping fails towards fallback.
    public static let ringSectorCount = 8            // [owed] Req 3.7; and Decision 30 —
    public static let sectorSupportMin: Float = 0.5  // the count takes |height|, so a
    public static let minSupportingSectors = 6       // correct plane whose ring escaped
                                                     // and a table plane both score 5 of 8.
                                                     // The replacement rule is stated and
                                                     // its bar inherited (Decision 40); the
                                                     // count it needs — maxCrossedSectors,
                                                     // bracketed 0…2 AT EIGHT SECTORS — is
                                                     // [owed] to capture 6, so nothing is
                                                     // rewired yet. ringSectorCount is the
                                                     // UNIT of the other two and of
                                                     // maxCrossedSectors, not their peer:
                                                     // bracketed 4…8 with a hard Req 5.1
                                                     // ceiling of 11 (Decision 44).
                                                     // sectorSupportMin selects the
                                                     // POPULATION that rule reads, and is
                                                     // bracketed 0…0.5 with the shipped
                                                     // value ON the ceiling — one notch
                                                     // higher and ringBandMm's room falls
                                                     // 10× and stops being inherited. The
                                                     // count's own bracket moves with it,
                                                     // so the two are fixed JOINTLY, not
                                                     // in sequence (Decision 45)
    public static let ringSupportMarginMin: Float = 0.15 // [owed] unreachable on the
                                                     // corpus — no capture yields two
                                                     // admissible candidates; the gaps
                                                     // real ones open, 0.312 and 0.117,
                                                     // straddle it (Decision 34)
    public static let escapeBandMm: Float = 30       // [owed] Decision 22 — the Req 3.3
                                                     // comparator; "below the lowest
                                                     // admissible candidate" cannot fire.
                                                     // One-sidedness confirmed correct;
                                                     // corpus reaches +5.7 mm (Dec. 34)
    // [measured] ringSectorCount × 25: at 25 samples per sector a 0.5 bar has
    // binomial σ ≈ 0.10; at the old floor of 60, sectors averaged 7 samples
    // (σ ≈ 0.19) and the guard was noise (Decision 20). Holds per radial band;
    // outer bands always exceed the inner, so one constant covers all three.
    // Corpus bands hold [1120, 1132, 1213] and [1294, 1347, 1392] — 5.6–7.0× the
    // floor — and inner-band sectors carry 102–184 apiece (Decision 29).
    // [measured] on an [owed] INPUT: it rises with ringSectorCount, so finer arcs
    // raise the floor the ring must clear. The 2× grid halving of Req 5.1 leaves the
    // thinnest band at 292, so 292/25 = 11 caps the count (Decision 44).
    public static let ringMinSamples = 200
    // [derived] Decision 22 — replaces foodAboveFractionMax, which rejected this
    // feature's own acceptance capture. Reject when the plane lies above the
    // food's upper envelope: percentile of signed food height, in MILLIMETRES
    // as Req 3.4 states, not a sample-count fraction.
    public static let foodEnvelopePercentile: Float = 0.90
    public static let foodEnvelopeMinMm: Float = 0    // [owed] Decision 22; bracketed
                                                 // 7.154…21.041 mm by the corpus — floor
                                                 // from a plane ABOVE the surface whose
                                                 // envelope is positive, ceiling from
                                                 // Req 3.1's candidate rather than the
                                                 // ranking's (Decision 48, correcting
                                                 // Decision 34's "no floor" and 25.8 mm)
    public static let maxCandidatePlanes = 3     // [owed] bracketed 2…∞ (Decision 48) —
                                                 // the cap NEVER fires: lifted to 8 both
                                                 // captures still stop at 3, starved by
                                                 // minResidueAreaMm2. Floor 2 because the
                                                 // intended plane on 1785901032716 is
                                                 // pass 2. Set the removal band and then
                                                 // the residue floor FIRST — "never fires"
                                                 // is a reading at inlierRemovalMultiple
                                                 // = 2×, and below it the cap truncates
                                                 // (Decision 50)
    public static let minResidueAreaMm2: Float = 1691 // [owed] extraction-pass floor only
                                                 // (Decision 32); corpus bounds it above
                                                 // at 2013 mm², not below. Was 500
                                                 // samples, re-denominated so
                                                 // planeCandidateCount transfers across
                                                 // depth grids — the value did not move
                                                 // (Decision 38)
    public static let minAcceptedExtentMm: Float = 44 // [owed] corpus brackets it at
                                                 // 22.3…47.8 mm (Decisions 32, 37); was
                                                 // 24 px, re-denominated so it transfers
                                                 // across depth grids — the value did
                                                 // not move (24 px = 44.7/44.1 mm here)
    public static let maxIterationsPerPass = 2048 // [measured] never fires — bracketed
                                                  // 128…unbounded, largest draw 250
    static let ransacSuccessProbability = 0.99   // [owed] bracketed 0.9…unbounded, NOT
                                                 // interpolable — the end of the clamp
                                                 // that binds, and moves the plane 3.704 mm
    public static let annulusOuterMm: Float = 50 // [owed] bracketed 50…75 mm by the corpus
                                                 // alone — the suite cannot see it, since
                                                 // the scenes never run extraction. Was
                                                 // annulusOuterMultiple × ringOuterMm; the
                                                 // value did not move (2 × 25 = 50) but the
                                                 // coupling made a bracket-only constant
                                                 // move the plane 18.719 mm (Decision 49)
    static let inlierRemovalMultiple: Float = 2  // [owed] bracketed 1…2.5× — floor
                                                 // structural, ceiling the corpus's (at 3×
                                                 // the shell takes the plate with the
                                                 // table). Its stated rule is FALSE: no
                                                 // adjacent pass pair is a near-duplicate
                                                 // at any multiple. Fix it BEFORE
                                                 // minResidueAreaMm2 and maxCandidatePlanes
                                                 // (Decision 50)

    // Depth intrinsics derived from colour (device depthIntrinsics are zeros).
    static func depthIntrinsics(from colour: CameraIntrinsics, depth: DepthMap) -> CameraIntrinsics

    // Depth-grid indices in the annulus, excluding food and low-confidence
    // samples. τ_conf = 0.40 applies here as it does in the band scan, so
    // `lidar-plane-fit-matte-table-confidence` is not bypassed (Req 7.5).
    static func contactRing(foodMask: BinaryMask, depth: DepthMap,
                            intrinsics: CameraIntrinsics) -> [Int]

    // `annulus` is the bounded candidate set (annulusOuterMm around the mask);
    // `ring` is the 8–25 mm sub-annulus. Both are needed: supportVisibility counts
    // plane inliers across the whole annulus, which ring indices alone cannot supply.
    static func ringStatistics(ring: [Int], annulus: [Int], foodSampleCount: Int,
                               plane: SupportPlane, depth: DepthMap,
                               intrinsics: CameraIntrinsics) -> RingStatistics?

    // Whether `ringStatistics` can return anything for this capture, for ANY plane.
    // The band counts read the radial banding alone, so the answer is a property of
    // the capture and is knowable before extraction runs (Decision 32).
    static func ringBandsAreFeasible(samples: RingSamples) -> Bool

    // nil when no candidate is admissible — the caller then runs the edge-band
    // fit. Never throws: rejection is an expected outcome, not an error.
    // Superseded by Decision 24: returns a `FoodSupportFit` struct whose first
    // three members are these, plus `annulusSampleCount` and `inlierCount` —
    // the native-depth-sample counts the Stats semantics below require, which
    // nothing outside this function can see.
    public static func fitFoodSupportPlane(
        depth: DepthMap, colourIntrinsics: CameraIntrinsics,
        foodRegionMask: BinaryMask, gravityCamera: Vec3
    ) -> FoodSupportFit?

    // Req 6.1 requires the ring measure on EVERY depth-derived attempt,
    // including fallbacks — Req 6.2's before/after comparison depends on it.
    public static func ringStatistics(for plane: SupportPlane, depth: DepthMap,
                                      foodMask: BinaryMask,
                                      intrinsics: CameraIntrinsics) -> RingStatistics?
}
```

**`supportVisibility` is defined as a computation, not a description.** An earlier draft gave it as "visible support area ÷ food area", which no declared signature could produce. It is:

```
supportVisibility = |{ i ∈ annulus : |signedDistance(p_i, plane)| ≤ inlierBandMm }| ÷ foodSampleCount
```

Both counts are **native depth samples**, so the ratio is dimensionless and grid-independent (Req 5.1). The numerator is support surface actually observed *and* consistent with the candidate plane — food-mask pixels are already excluded from the annulus, so occluded support does not count itself. The denominator is the food sample count, making it food-relative as Decision 14 intends.

`contactRing` and `ringStatistics` are internal but directly unit-tested: they carry the geometry that decides the fit.

**Stats semantics.** On a `.foodSupport` row, `candidatePointCount` / `inlierCount` mean *native depth samples*; on `.edgeBand` they mean colour-grid points, as today. The two differ by ~56× and must not be compared across references — the persisted `planeReference` is what disambiguates them.

## Data Models

`EstimationAttemptRecord` gains five optionals, absent (not defaulted) on pre-feature rows so Req 6.3's distinction survives:

| Field | Type | Meaning |
|---|---|---|
| `planeReference` | `String?` | `foodSupport` / `edgeBand` |
| `planeRingMedianMm` | `Float?` | ≈ 0 on a correct fit |
| `planeRingBandMediansMm` | `[Float]?` | inner/mid/outer medians — the persisted radial profile Decision 14's residual risk depends on; rising identifies a rim, falling a leaked ring |
| `planeCandidatePlaneCount` | `Int?` | candidate planes extracted. Superseded name (Decision 23): `planeCandidateCount` already exists and counts candidate POINTS, so reusing it would redefine a field pre-feature rows already carry |
| `planeSupportingSectors` | `Int?` | inner-band sectors meeting the bar (Req 6.4) — distinguishes a correct fit from a ring that crossed the support's edge, which both read median ≈ 0 |

Req 3.5's mask-coverage recording needs no new field: `foodRegionCoveragePercent` already persists on `EstimationAttemptRecord` (`PipelineDiagnostics.swift:200`) and lands on the same row as `planeReference`, so a reference flip is attributable to mask movement after the fact.

Calibration artefacts gain `supportPlaneReference`; absent blocks β_c application (Decision 10). Nothing breaks today because every β is `uncalibrated_unity`.

**The guard has two granularities, because a mixed artefact is the permanent shape (Decision 26).** The artefact records the reference `betaPool` was fitted under, *and* each class entry records the reference its own β was fitted under — the corpus spans two references by construction under Decision 17, so one value per artefact cannot describe it. An absent or mismatched artefact-level value aborts the bake before anything is written, which is the pre-feature case Req 5.3 names. A class entry under a different reference is left at its uncalibrated default and reported, not aborted on: aborting would reject every artefact the harness will produce from here on. On the fitting side `CalibrateRun.applyReferenceGate` admits only inputs matching the reference β will be applied under, and the excluded fixture IDs land in the run summary — an attempt recording *no* reference is excluded, since absent blocks rather than permits.

**Fallback-rate reporting (Req 4.4).** `AccuracyReport` carries a `FallbackRateReport`: counts segmented by reference, the depth-derived denominator, the `.edgeBand` numerator, and the rate. Attempts that derived no plane from depth — two-view, card-only — stay out of the denominator, and the rate is *absent* rather than zero when nothing was depth-derived, since 0 % would read as "the fallback never fired" on a run where the restricted fit never ran. It is computed over every meal rather than the scored ones: a device replay scores nothing, and that is the run whose rate matters most.

## Error Handling

No new refusals — every rejection resolves to the fallback, which is pre-feature behaviour.

| Condition | Result |
|---|---|
| Any band has fewer than `ringMinSamples` valid samples | fallback, refused up front by `ringBandsAreFeasible` rather than after a full extraction (Decision 32) |
| Residue below `minResidueAreaMm2` before any candidate | fallback |
| No candidate admissible | fallback |
| Top two candidates within `ringSupportMarginMin` | fallback |
| Edge-band fit itself fails | existing refusal (pipeline Req 4.5), unchanged |

## Testing Strategy

**Synthetic unit tests** (`MedataCore/Tests/SupportPlaneTests/`), constructed depth maps:

| Case | Asserts |
|---|---|
| Plate 20 mm above table, table dominant ~9:1 | selects the plate; the case today's fitter fails |
| Ring straddling plate and table ~50/50 | rejected on sectors — support confined to arcs; a MAD bar cannot fire here (Decision 19) |
| Rimmed plate, well partly visible, rim in the outer band | inner band selects the well, not the rim |
| Rimmed plate, rim step inside the mid band | rejected on the inner→mid step → fallback, not a rim fit (Decision 21) |
| Rimmed plate, well fully covered | support visibility fails → fallback, not a rim under-read |
| Bowl, walls above the food | rejected; `reference == .edgeBand` |
| Co-height board elsewhere in frame | component scoring excludes it |
| Overhanging food below the plane | accepted — guards must not fire (Req 1.3) |
| Food to within 10 mm of a flat plate's edge, ring 65 % on table | rejected on sectors; **must not** select the table with median ≈ 0 (Req 3.6) |
| Candidate below the lowest admissible | rejected (Req 3.3) |
| Winning plane below `minAcceptedExtentMm` | rejected |
| Depth grid ≠ 256×192 (N5k identity grid) | mm-based radii transfer (Req 5.1) — measured at ≤ 1 mm across a 2× halving. `minAcceptedExtentPx` was the one bar that did **not** transfer (Decision 35); it is now `minAcceptedExtentMm` and does, with zero verdict flips across the same halving (Decision 37). `planeCandidateCount` was the other, three passes natively against two halved; the residue floor is now `minResidueAreaMm2` and the count is 3 → 3 (Decision 38) |
| Food mask at frame edge | short ring → fallback, no crash |
| Same bytes twice | identical plane and reference (Req 7.7) |

**Deliberately no randomised generator.** An earlier draft proposed property tests; both were near-tautologies (fallback totality is guaranteed by the ordering contract; same-process determinism has no failure mode), `swift-testing`'s `arguments:` is parameterised rather than generative and has no shrinking, and CLAUDE.md's MVP gate says not to add test scaffolding unasked. The perturbation-stability property that *would* find counterexamples — ε < 1 mm of noise must not flip the reference — is expressed instead as a fixed parameterised sweep over seeded perturbations of the two real captures, which needs no new harness.

**Regression against real captures.** Reqs 6.2, 7.1–7.3 via `make harness-accuracy`. The 195/204 MB bundles are large because of RGB; a **depth-only slice** (256×192 Float32 depth + confidence + food mask, ~290 KB) is committed to the repo so Reqs 6.2 and 7.1 are executable by anyone, with the full bundles pulled from the device only for the volume criteria that need imagery.

`tools/fixture_slice.py` cuts the slices; `SupportPlaneRegressionSliceTests` runs the criteria. Two properties of that suite are deliberate. Every assertion measures a **named** plane — the pre-feature edge-band fit, or the highest-support candidate taken *before* admissibility — never the plane the guards selected, so nothing in it moves when task 26 sets the `[owed]` constants. And the food mask is carried on the depth grid, which makes the slice small but means the pre-feature comparison has to expand it back to 1920×1440: `LiDARPlaneFitter` sizes its bands from the mask's own bbox, so a depth-grid mask against colour intrinsics fits nothing meaningful. The expansion quantises to one depth pixel (~7.5 colour pixels) against bands hundreds of pixels thick, and the check that this is immaterial is that both pre-feature volumes reproduce the recorded figures within 5 %.

Three figures the criteria state do **not** reproduce and are superseded by Decision 28 — Req 6.2's +18…+26 mm, Req 7.1's 235.96 cm³ and Req 7.2's ~200 cm³. Reqs 7.3 and 7.4 stay blocked on captures that do not exist rather than on code.

**Numbers this design owes the requirements** — to be fixed during implementation against the fixture corpus, not asserted now. Every `SupportRegion` constant is annotated `[derived]`, `[measured]`, `[inherited]`, or `[owed]`; the `[owed]` ones are task 26 corpus measurements, with the sector trio under Req 3.7's explicit ban on shipping asserted values, and each measured value lands with its derivation recorded in `decision_log.md` (Req 3.7). Beyond the constants: the Req 4.5 fallback-rate defect threshold, ~~Req 5.1's device/replay plane tolerance and named fixture~~ (**measured, Decision 35** — see below), Req 7.6's latency and memory budget, and `fallbackPenalty` (**bounded above, Decision 36** — see below; the value is owed to the same Bucket C gate as the fallback rate). Each is a measurement, and stating a value here would be inventing evidence. Two `[owed]` constants have had their **denomination** settled without their value being set — `minAcceptedExtentMm` (Decision 37) and `minResidueAreaMm2` (Decision 38) — which is a separate thing from being measured and does not remove them from the list. The sector trio's replacement **rule** is settled without its count being set (Decision 40 — see below), which adds `maxCrossedSectors` to the list rather than removing anything from it. Six of the `[owed]` constants also carry a **second** bracket, from the committed test suite rather than the corpus, and on three of them it is the binding one (Decision 41 — see below). `maxCrossedSectors` carries one too, and it is the only constant on which the two sources agree exactly (Decision 43 — see below). **Every sector bracket on this list is denominated in `ringSectorCount`, which is `[owed]` itself** — bracketed 4…8 with a hard Req 5.1 ceiling of 11, and to be fixed before the capture session rather than beside the constants it is the unit of (Decision 44 — see below). It is denominated in `sectorSupportMin` too, bracketed 0…0.5, and the two must be fixed **jointly** rather than in sequence (Decision 45 — see below). And in `ringOuterMm`, bracketed 22…32 mm, which makes it a **triple** and which is the one owed constant that moves the *selected plane* rather than only a bracket — 18.719 mm at the food across its sweep, against Req 5.1's 1 mm (Decision 46 — see below).

**The committed scenes are a second constraint on six owed constants (Decision 41).** The regression slices were built so that "nothing in it moves when task 26 sets the `[owed]` constants" — that holds for the slices and not for the scene suites, which reference owed constants twenty-eight times. Every reference is symbolic, but a test that fixes a synthetic scene and asserts the scene's measured value against a constant flips as soon as the constant crosses it. Measured per assertion rather than per scene: `ringSupportMin` ≤ **0.676**, `minSupportingSectors` **6…7**, `bandStepMaxMm` **0.024…9.288 mm**, `supportVisibilityMin` ≤ **2.667**, `foodEnvelopeMinMm` **−6.758…8.233 mm**, `escapeBandMm` ≥ **14.868 mm**. Two of these are the only bound that exists — the corpus gives `ringSupportMin` no ceiling (Decision 29) and `bandStepMaxMm` no floor (Decision 34). Two bind tighter than the corpus does: `foodEnvelopeMinMm` at 8.233 mm against the corpus's 25.793 mm, and `escapeBandMm` at 14.868 mm against a corpus that reaches +5.750 mm. And one **contradicts** it: Decision 33 measured that a real intended candidate scores 5 of 8 sectors, so `minSupportingSectors` must come down to 5 or below, while the silent-failure scene the guard exists to reject *also* scores 5 and floors the suite at 6. That is Decision 30's finding — the unsigned count cannot separate the two cases — reappearing as a suite constraint. ~~It means the scene has to move when Decision 40's crossed-sector rule lands.~~ **Superseded by Decision 43**: it does not. The collision belongs to the unsigned count, and the rule that replaces it clears every committed scene untouched.

**Req 5.1's tolerance, and the one bar that does not transfer (Decision 35).** The tolerance is **1 mm** of plane movement at the food and the named fixture is **`1785135663727`**. Device and replay share one implementation, so identical bytes give an identical plane and the tolerance is not about arithmetic; what differs is the depth grid. Measured across a 2× halving, the plane moves 0.835 mm on `1785135663727` and 0.037 mm on `1785901032716`, normals tilting 0.945° and 0.063°. The comparison is taken where each plane cuts the food-mask centroid ray, because volume is integrated per-pixel above the plane and a millimetre there is a millimetre on every food pixel. Three riders. The transfer has a floor at the ring, not the plane: at 64×48 the inner band holds 37 and 32 samples against `ringMinSamples = 200`, and since `mmPerPx = z / f_d` this is the ≈ 365 mm range envelope of Decision 29 reached by coarsening `f_d` instead of raising `z`. `planeCandidateCount` is grid-dependent where the plane is not — three passes natively, two at half resolution; **that rider is closed by Decision 38** — see below. And `minAcceptedExtentPx` was the only bar in `admissibility` denominated in **pixels** rather than millimetres or a fraction, so it halved with the grid: a surface admitted at 44 px was rejected as a sliver at 22 px. That bracket was a 256×192 bracket, and N5k's pinned f = 617 px against the device's measured f_d = 182.033 px makes the same physical extent span 3.389× more pixels there. **That rider is closed by Decision 37** — see below. The device leg of Req 5.1 stays task 27's: decimation models a coarser grid, not a different sensor.

**The extent bar is re-denominated, and the rider closes (Decision 37).** `minAcceptedExtentPx = 24` becomes `minAcceptedExtentMm = 44`, converted through the `mmPerPx` the ring radii already use, so no bar in `admissibility` is denominated in pixels any longer and Req 5.1's transfer claim carries no exception. **The value does not move**: 24 px at the corpus's `mmPerPx` of 1.8616 and 1.8393 is 44.68 mm and 44.14 mm, and 44 mm is the largest whole millimetre at or below both, so every corpus verdict is unchanged. The bracket becomes physical — **22.339…47.821 mm**, from measured extents of 228.973/141.479/22.339 mm and 285.084/80.927/47.821 mm — where 13…26 px meant different physical sizes on the two captures and nothing at all on another grid. Across the same 2× halving, four paired surfaces have their pixel extents halve (123→61, 76→38, 155→77, 44→22) while their millimetre extents drift 1.698, 0.102, 1.839 and 0.000 mm, at most half a halved-grid pixel; verdict flips fall from one to **zero**, and the 44 px → 22 px pair Decision 35 named now reads 80.927 mm on both grids. The constant stays `[owed]` — re-denominating it does not set it — and it now assumes the candidate surface lies at roughly the food's range, the same assumption every ring radius makes.

**The residue floor is re-denominated, and the second rider closes (Decision 38).** `minResidueSamples = 500` becomes `minResidueAreaMm2 = 1691`, converted per capture through the same `mmPerPx`. A raw sample count divides by four under a 2× halving where the surface it stands for does not, and that is what made `planeCandidateCount` — a **persisted** field (Req 6.1) — read the sensor's grid rather than the scene. **The value does not move**: 500 samples at the corpus's pixel areas of 3.465 mm² and 3.383 mm² is 1732.6 mm² and 1691.5 mm², so 1691 mm² is the largest whole millimetre² at or below both and every corpus pass keeps its verdict. What the measurement shows is that the residue's **area** is the invariant: the annulus itself agrees to 0.3 % and 1.2 % across the halving (36 280 → 36 176 mm², 42 458 → 41 961 mm²) where its sample count quarters, and later passes drift further — 5.0 %, 4.9 %, 6.4 %, 22.7 % — because each pass removes its own inliers within a millimetre band and that removal is resolved on the grid. The pass the old floor cut now runs: 155 and 180 samples on the halved grid, below the 500 the count floor was and above the 122 and 125 the area floor is there, so the candidate count is **3 → 3** on both captures and the plane at the food does not move (0.835 mm and 0.037 mm, unchanged). The constant stays `[owed]`; the corpus still bounds it from above only, now at **2013 mm²**, and the smallest residue on the halved grid clears it by 1.44× against 1.86× natively.

**What falling back costs, and what the penalty charges (Decision 36).** `supportPlaneFallbackPenalty` is a price, not a bar, and Req 4.6 — "no higher than a restricted fit of *equal* residual" — is met by any value in (0, 1), so it cannot choose one. The denomination is the curve's: σ_plane = exp(−r/5) with r in millimetres, so p charges −5·ln(p) mm, and 0.9 charges **0.53 mm**. Measured per food sample on `1785135663727`, the edge-band plane adds **18.37 mm** to the mean food pixel (p10 7.96, p90 28.61 — the two planes are 7.18° apart, which is why the measure is a per-sample mean rather than Decision 35's single ray), pricing the fallback at **0.025**: a **35.5×** over-report, corroborated by the 408 cm³ the regression suite measures between the pre-feature and corrected volumes. Two riders. The residual channel works *against* the penalty — the edge-band plane is a good fit to the wrong surface, so its residual is lower than the restricted fit's (1.95 vs 2.33 mm) and exp(−r/5) rewards it; 71 % of the penalty is spent cancelling that, and the net reduction on the same capture is **3.1 %**. And the bound is one-sided: the fallback is the *correct* plane when food rests directly on the surrounding surface, so a single constant prices a mixture whose weight is Req 4.5's fallback rate, absent until Bucket C. Pricing it per capture from the persisted ring measure is measured and rejected — the ratio of ring median to offset at the food is 0.231 and 2.471, wrong in both directions, for Decision 33's reason.

**What the corpus pass settled (Decision 29).** `SupportPlaneCorpusMeasurementTests` is the instrumented, guards-disabled pass over the committed slices. It confirms `ringInnerMm = 8` with a stated ≈ 365 mm range envelope, confirms `ringMinSamples = 200` per band at 5.6–7.0× margin, and establishes that `supportVisibilityMin` is firable — the ratio is computed over the annulus, not the ring, so it does see a thin support strip. It cannot settle the rest, for two measured reasons: neither committed capture is a clean correct fit (both rings cross the plate edge — per-sector inner medians reach −32.6 mm on one and +19.8 mm on the other), and per-sample noise on a flat surface measures 3.44 mm on one and 6.98 mm on the other at the same range, straddling `ringBandMm`. Decision 30 records that the sector count is additionally blind to the sign that distinguishes the two cases; Decision 40 states the rule that restores it and shows its bar is inherited.

**How much of the guard table the corpus reaches (Decision 34).** Three of the nine rejection reasons ever fire on it — `extent`, `supportFraction`, `sectors` — and a fourth, `ringMedian`, only when the guards are evaluated independently rather than short-circuited. The other five never fire, and four `[owed]` constants sit behind them: `foodEnvelopeMinMm` (bounded above at 25.8 mm by the intended candidate's envelope, not below, since every corpus envelope is positive), `bandStepMaxMm` (the guard reads an outward rise; every corpus step is a fall of −0.5 to −6.5 mm), `supportVisibilityMin` (firable, never fired — the corpus floor is 0.246 against a 0.15 bar), and `escapeBandMm` (one-sidedness confirmed correct against Req 3.3, but the corpus reaches +5.7 mm against a 30 mm bar). `ringSupportMarginMin` is not reachable at all: it compares the top two **admissible** candidates and neither capture produces one. These four are therefore not merely unset — nothing in the corpus exercises the guards they gate, so the capture session has to produce the scenes that fire them, not just the scenes that set their values.

**Why both rings cross the plate edge (Decision 33).** The same pass measures the **support margin** per sector — the distance from the food boundary at which the surface departs from itself by more than `ringBandMm`. Measured margins are 16, 40, 10, 42, 6, 4, 6, 44 mm and 34, 4, 46, 8, 30, 14, 12, 6 mm, every in-ring departure a fall of 5.1–15.6 mm, so they are plate edges rather than rims. Three consequences. `ringOuterMm`'s stated rule — inside the smallest measured plate margin — is **unsatisfiable**, because that margin is 4 mm on both captures, inside `ringInnerMm`. Only 3 of 8 sectors reach `ringOuterMm` and only 4 of 8 reach the inner band's 13.7 mm, which is below `minSupportingSectors = 6`, so plate geometry caps the supporting count before `sectorSupportMin` is consulted. And the crossings Decision 29 attributes to the captures are therefore in part a property of the ring's radial extent, which the capture session must record per sector so the trio and `ringOuterMm` are derived together.

**The sector rule, and the one axis of it that costs nothing (Decision 40).** Decision 30 measured the blindness and declined to state a rule, on the ground that a signed rule needs a threshold with the same evidence problem as every other `[owed]` constant. Measured, that holds on one axis only. The rule is: a **failing** sector — below `sectorSupportMin` — whose signed inner-band median exceeds `+ringBandMm` is **crossed**, and a candidate is rejected when more than `maxCrossedSectors` sectors are crossed; a failing sector below `−ringBandMm` has **escaped**, which is the plate ending and not grounds for rejection. The magnitude bar is `ringBandMm`, already `[inherited]` and already the bar deciding which samples in those sectors count as supported, so **no new millimetre constant is created**: the plate candidate's highest failing median is −6.794 mm and the table candidate's lowest is +16.603 mm, a **23.397 mm** window with `ringBandMm = 5` sitting 11.794 mm above its floor and 11.603 mm below its ceiling. Restricting to failing sectors is what earns that — across *all* sectors the window is +3.846 to +5.974 mm, **2.128 mm** wide, and a bar surviving that narrowly is fitted rather than inherited. The rule is the per-arc form of `ringMedianMaxMm`, which on the table candidate reads +3.04 mm and does **not** fire while three of its sectors read +16.6 to +19.8 mm — Decision 18's silent-failure case measured rather than argued. What stays `[owed]` is the count: the corpus brackets `maxCrossedSectors` at **0…2** (0 crossed on the plate candidate, 3 on the table one) and prerequisites capture 6 sets it. Shipped code is unchanged, because shipping the rule means asserting that count and Req 3.7 names these constants specifically.

**The rule clears both constraint sets where the count clears neither (Decision 43).** Read through the rule, the committed suite brackets `maxCrossedSectors` at **0…2** as well — five scenes whose assertions require the sector guard to pass carry 0 crossed sectors, and the silent-failure scene carries 3. The joint interval is 0…2 against an **empty** 6…5 for the unsigned count on the same eight scenes, so Decision 41's "the scene has to move" is withdrawn: the collision belongs to the count, not to the suite. This is the only `[owed]` constant whose two sources agree exactly, so the session sets it from captures with no suite interaction to track. Nothing in hand distinguishes 0, 1 and 2 — every committed scene and both corpus candidates return the same verdict at each — which is why it stays owed rather than becoming measured. Two side findings: `overhangingFood` is the first committed scene to exercise the rule's **escape** half, at −20.024 mm; and neither rimmed-plate scene exercises Decision 40's stated blind spot, because their rims never reach the inner band the sector median is computed over, so prerequisites captures 3 and 4 remain the only source for a correct plane whose ring meets a genuine rim.

**The sector count is the unit those brackets are in, and Req 5.1 caps it at 11 (Decision 44).** `ringSectorCount = 8` had never been varied. Re-cut both corpus rings and all eight committed scenes at nine counts and the joint bracket on `maxCrossedSectors` takes eight distinct values — **0…0** at four sectors, 0…1 at six, **0…2** at eight, 1…2 at ten and eleven — so "0…2, and nothing narrows it" means "at eight sectors", and the count must be fixed **before** the sitting rather than read out of it beside the constants it denominates. It is bracketed **4…8**, not set. There is **no floor**: the crossed-sector rule separates the plate-top candidate from the table candidate at every count from 4 to 32, so a coarse cut does not average the crossing away inside one sector. The top comes from the *pass* side — the plane a correct fit must admit reads 0 crossed sectors at 4, 6 and 8 and **1** from 10 upward, because narrow enough arcs resolve the direction its own ring ran off the plate onto the table (Decision 33 read a third way). Above that is a hard ceiling of **11**: `ringMinSamples` *is* `ringSectorCount × 25`, so finer arcs raise the very floor the ring must clear, and Req 5.1's 2× halving leaves the thinnest radial band at 292 samples where the native grid's 1120 would have carried 44. Two consequences worth stating plainly. `ringMinSamples` is `[measured]` on an `[owed]` input, a coupling no annotation recorded. And the trade runs **backwards** — a coarser cut leaves *less* freedom, widths 1, 2, 3 at counts 4, 6, 8 — so at four sectors `maxCrossedSectors` is *determined* at 0 by evidence already committed. That is not a shortcut to take: it asserts `ringSectorCount` in order to avoid asserting `maxCrossedSectors`, and whether a 90° arc resolves Req 3.6's straddle is a property of scenes the corpus does not contain. It does mean Decision 43's headline is weaker than it read — the freedom it reports belongs to the count that happens to maximise it.

**The support bar selects the population that rule reads, and the shipped value is on a cliff (Decision 45).** `sectorSupportMin` had never been varied either, and it is not a peer of the other two: the crossed-sector rule reads the sign of sectors that **fail** it, so the bar chooses the population Decision 40's inheritance claim is a statement about. Re-classify the same two candidates and the same eight scenes at eleven bars and the window `ringBandMm` has — how far it may move before either candidate changes its crossed count — reads 49.167 mm at 0.1–0.3, 26.283 at 0.4, **23.397 at 0.5**, then **2.263 at 0.6** and 2.128 at 0.9–1.0. That is a **10.339× collapse in one notch**, the largest step in the sweep, and it sits exactly at the shipped value. Decision 40 supplied the criterion without knowing it was one — 2.128 mm is "fitted", 23.397 mm is "inherited" — so the cliff picks the ceiling and no new threshold is needed: `sectorSupportMin` is bracketed **0…0.5**, with the shipped 0.5 **on** the ceiling rather than inside. Both edges converge on the bar from opposite sides as it rises: sectors sitting *on* the correct plane but noisy start failing and read near zero, lifting the floor from −32.564 to +3.846, while sectors holding the table plane at a small positive offset fail and become crossed, dropping the ceiling from +16.603 to +5.974. The floor is the rule's own — at 0 nothing fails, the population is empty, and a rule with nothing to read admits the plane Decision 18 exists to reject. Two riders. Decision 40's all-sector contrast **understates itself**: read without conditioning on where `ringBandMm` currently sits, the all-sector failing medians *interleave* (table's lowest +0.426 below the plate's highest +3.846, a separation of −3.419 mm), so restricting the rule to failing sectors is more necessary than recorded, not less. And Decision 44's ordering is **superseded** — the count's own pass-side bracket moves with the bar (counts with a clean pass side: 6, 8, 10, 11 at 0.1–0.2; all five at 0.3; 4, 6, 8, 10 at 0.4; 4, 6, 8 from 0.5 up), so the erosion above eight sectors is itself a consequence of the bar being at 0.5 and the two constants must be fixed **jointly**. One positive: over the whole 5 × 11 grid **no cell collides** — wherever the rule fires, the suite and the corpus admit a common `maxCrossedSectors` — so Decision 43's agreement is a property of the rule rather than of the shipped pair.

**The ring radius re-selects the candidates, and it is the first owed constant that moves the answer (Decision 46 — superseded in two places by Decision 49, marked below).** `ringOuterMm` had no derivation at all — Decision 33 found its stated rule unsatisfiable and nothing replaced it — and it is upstream of the other two, because the sector rule reads the inner band, whose outer edge is `ringInnerMm + (ringOuterMm − ringInnerMm) / ringBandCount` = 13.667 mm at the shipped value. It also differs in **kind** from them: the count re-cuts a fixed ring and the bar re-classifies a fixed set of sectors, but the radius moves the **annulus**, `2 × ringOuterMm`, which is the candidate bound — so extraction runs on a different sample set at every value. Re-ringed and **re-extracted** at seventeen radii, the *selected* plane moves **18.719 mm** at the food on `1785901032716` and 4.162 mm on `1785135663727`, against the **1 mm** Decision 35 measures Req 5.1's grid transfer at. Decisions 44 and 45 both closed with "no value moves"; that stops here. The bracket is **22…32 mm** and both ends are new. The **floor** is Req 5.1's, the mirror of the ceiling Decision 44 read off the same halving — a narrower ring holds fewer samples per band and the 2× halving quarters them, so below 22 mm `ringBandsAreFeasible` refuses on a grid where the plane still transfers within a millimetre (halved bands [78, 111, 48] at 13 mm against the 200 floor). The **ceiling** is the committed suite's, arriving exactly as Decision 41 predicted: the scenes place their features at fixed pixel radii, so at 35 mm the ring reaches the rim a scene put outside it, every sector of a scene that must *pass* reads crossed, and both suite intervals go empty together. ~~**The bracket must not be interpolated inside.**~~ *(superseded by Decision 49: the alternation is the annulus's, and with the bound pinned the intended candidate reads 0 crossed at every radius in the sweep. The bracket may be interpolated.)* The pass side alternates at 1 mm steps — the corpus's only intended-correct candidate reads 0 crossed sectors at 22, 23, 25, 26, 28, 29 and 31 mm and **2** at 24, 27, 30 and 32 mm, its plane oscillating over 4.162 mm with them — so a radius between two clean radii is implied by neither. A control separates that from extraction noise: held at the shipped radius over eight RANSAC seeds the plane moves **2.095 mm** on `1785135663727` and 0.001 mm on `1785901032716`, but the sector verdict is single-valued on both, so the radius is *reordering* the candidates rather than re-rolling them. Three consequences. ~~Decision 45's joint pair is a **triple**, and the radius is fixed first because it selects the candidates the other two are read on.~~ *(superseded by Decision 49: it no longer selects them, so the pair is a pair and the radius is fixed beside it.)* `maxCrossedSectors` is denominated in all three — the joint bracket reads 0…0, 0…1, 0…2 and 2…2 over the sweep with no ordering in the radius, and at 22 and 24 mm the two constraint sets admit no common value at all, so Decision 45's collision-free grid is a slice at the shipped radius. And selection is confirmed **verdict-stable under the seed**, which is the first evidence that any bracket in Decisions 40–45 is a property of the captures rather than of one draw — though the plane figures those decisions quote (Decision 35's 0.835 mm, Decision 36's 18.370 mm) each carry ~2 mm of draw dependence that was never recorded.

**The band count is the divisor that was never varied, and two values survive (Decision 47).** Of the seven constants the sector measure reads, `ringBandCount` was the only one carrying no provenance marker — "structural: inner/mid/outer" — and Decision 46 had swept the numerator of the inner-band edge while leaving its divisor fixed. Re-banded at nine counts, it is bracketed **2…3**: two values, the tightest bracket in the feature, with the shipped 3 **on** the ceiling. The **floor** of 2 arrives twice independently, and one of those is unlike any other bound here — a guard stops *existing*. At one band there is no mid band, `admissibility`'s `bandMedianMm.count > 1` test is false, and the `bandStep` guard neither fires nor reports that it did not, while two committed scenes assert that it does; separately, at one band the inner band *is* the whole 8…25 mm ring, the rimmed-plate rims fall inside it, a scene that must pass reads 8 of 8 crossed, and both suite intervals collapse together (`maxCrossedSectors` 8…2, `minSupportingSectors` 6…0) — Decision 41's prediction on a third constant. The **ceiling** of 3 is Req 5.1's, for the third time after Decision 44's count and Decision 46's radius, and it lands hardest here because this constant *is* how many bands `ringMinSamples` is floored per: halved counts read [322, 361, 323] and [313, 292, 299] at three bands and [237, 197, 215, 255] and [258, 264, 204, 280] at four. It **does not move the answer** — the selected plane at the food is unchanged to 0.000 mm on both captures at every count, against Decision 46's 18.719 mm — which turns that decision's attribution of the movement to the annulus from an argument into a measurement, since this constant divides the inner band without touching the annulus. Two constants are denominated in it. `bandStepMaxMm`'s suite interval collapses (ceilings 13.470, 9.288, 6.755, 5.496, 0.211 mm at 2…6 bands) and then **inverts** from seven, because a rim spanning a fixed radial distance stops being a step between adjacent bands once the bands are narrower than the rim; the shipped 6 holds across the whole Req 5.1 bracket, so the pair is coupled but does not collide. And `maxCrossedSectors` reads **1…2 at two bands** against 0…2 at three, so Decision 43's "nothing in hand narrows 0…2" is a reading at three bands — moved by Decision 43's own recorded blind spot, since at two bands the inner band ends at 16.5 mm and a rimmed-plate rim does reach it. The rule still separates the two corpus candidates at every band count (plate 0 crossed, table 3…6). The bracket is a **slice at the shipped radius**, the same caveat Decision 46 attached to Decision 45's grid; unlike the other three, though, this constant is bracketed by committed evidence alone and so is fixed *before* the sitting rather than at it.

**The pass cap never fires, and lifting it determines a constant three decisions could not (Decision 48).** `maxCandidatePlanes = 3` was the last "structural:" comment standing in for a derivation, and it is the second constant after `ringOuterMm` that changes which planes *compete* rather than how a fixed set is read — the only one that can **add** a candidate. Lifted to 8, both captures still stop at **three** passes, and both stop **starved**: the residue left after the last pass is 1330.7 mm² and 155.6 mm² against a `minResidueAreaMm2` of 1691. It is the residue floor that ends extraction, so no value at or above 3 is distinguishable on this corpus. That makes the two constants **coupled with an order** — `1785135663727` sits at 78.7 % of the floor, so a session that lowers it below 1331 mm² gives that capture a fourth pass and this cap something to truncate. **Set the residue floor first**; Req 7.6's device latency is denominated here too, since the RANSAC bound is `maxIterationsPerPass × maxCandidatePlanes`. The **floor** of 2 is the corpus's, and it is where sequential extraction earns its keep: on `1785901032716` the plane a correct fit must select is **pass 2**, nearest Req 3.1's zero at a ring median of −2.658 mm, while the *ranking's* winner is pass 1, the **table**, at +3.039 mm — so below a cap of 2 the intended plane is not in the candidate set at all and no owed constant recovers it. The committed suite agrees independently (`sequentialExtractionSurfacesThePlate` puts the plate on pass 2). Two consequences belong elsewhere. Read at full pass depth with the intended plane identified by its **ring median** rather than by the ranking, the corpus **determines `maxCrossedSectors` at 2** — floor 2 from that pass-2 plane, ceiling 2 from the table's 3 — where Decisions 40, 43, 44 and 47 all read a bracket whose floor came from the highest-*support* candidate, which on that capture is the plane the guard exists to reject. It stays `[owed]`, because this is a slice at the shipped `(ringOuterMm, ringSectorCount, sectorSupportMin, ringBandCount)` and all four are bracketed, but the session no longer chooses freely within 0…2 at the shipped four. And Decision 34's "`foodEnvelopeMinMm` has no floor" is **withdrawn**: the corpus does contain a plane above the support surface — the same capture's pass 3, 9.736 mm above the plate with 6 escaped sectors — and its envelope is not negative but **positive at 7.154 mm**, because a plane above a surface still has food above *it* wherever the food is taller than the gap. The corpus ceiling tightens to **21.041 mm** by the same re-identification, and against Decision 41's suite ceiling of 8.233 mm the joint window is **1.079 mm**, the narrowest in the feature. Decision 38's 3 → 3 grid agreement is also confirmed **unconditional**: both counts were at the cap and could have been it truncating both; lifted, the grids still agree.

**The candidate bound is a constant of its own, and it carried the radius's movement (Decision 49).** `annulusOuterMultiple = 2` was the third constant that changes which planes *compete*, and the only one of the three that had never been varied — because it could not be. With the bound written as a multiple of `ringOuterMm`, there is no radius at which the bound is held still and no bound at which the radius is, so Decision 46 swept both at once, Decision 47 attributed the movement to the annulus by elimination, and Decision 48 varied only how many times the annulus may be drawn from. Pin the bound at 50 mm and re-run Decision 46's own 13…40 mm sweep: the selected plane moves **0.000 mm** at the food on both captures — not within a tolerance, exactly, because `extractCandidates` reads the annulus and nothing else, and the ranking picks the same candidate at every radius even though the ring moves under it. Swept itself at a fixed ring, the bound moves the plane **18.843 mm** and 1.978 mm, which is Decision 46's 18.719 mm rather than a fraction of it. So the constant is re-denominated as **`annulusOuterMm = 50`**, `[owed]`, exactly as Decisions 37 and 38 re-denominated the extent bar and the residue floor and for the same reason — the value does not move (`2 × 25` is 50), every corpus candidate and committed scene is unchanged by construction, and what changes is that a *measure* parameter stops resizing the candidate *set*. Two of Decision 46's riders go with it: the 22…32 mm bracket **may** be interpolated, and the radius is fixed **beside** the count and the bar rather than before them. The bound is bracketed **50…75 mm** by the corpus, reading `maxCrossedSectors` as Decision 48 reads it — below the floor the plane a correct fit must admit is itself crossed (3…unbounded at 31.25 mm, empty at 25, 37.5 and 43.75 mm, and at 25 mm the bound collapses onto the ring and extraction yields two candidates), and at 100 mm the interval collapses the other way as the plate capture's intended candidate reads **6** crossed sectors with the annulus reaching surfaces beyond the plate. The shipped 50 mm sits **on the floor**, as `sectorSupportMin` sits on its ceiling and `ringBandCount` on its, and it is the only value in the sweep at which the corpus determines `maxCrossedSectors` at 2 — 62.5 and 75 mm both widen it to 2…4, so Decision 48's determination is a slice at **five** constants and not four. The committed **suite is silent** here, for the first time since Decision 41 predicted it would cap constants: the scenes never run extraction, so the bound reaches them only through `visibility` and `escaped`, two of the five guards Decision 34 found never fire, and every scene keeps its verdict at 25 mm and at 100 mm alike. One side finding belongs to `escapeBandMm`: Decision 41's suite floor of ≥ 14.868 mm is an *annulus* median, so it is a reading at the shipped bound — over the sweep the same scenes read 0.131 to 14.868 mm, a 14.737 mm span, because a wider annulus reaches past the plate a scene sits on. And Req 7.6's latency is denominated here too: the annulus holds 10 469 and 12 551 samples at 50 mm against 19 427 and 25 659 at 100 mm, and RANSAC iterates over all of them.

**The removal band is what one pass hands the next, and its one stated rule is false (Decision 50).** `inlierRemovalMultiple = 2` is the **fourth** constant that decides which planes *compete*, and the only one that acts *between* passes: `annulusOuterMm` fixes the set extraction draws from, `maxCandidatePlanes` fixes how many times it may draw, `ringOuterMm` re-rings a set already chosen — this one decides what each draw **leaves**. It was also the last constant in `SupportRegion` carrying a claim in place of a provenance marker, and the claim was "a 1× shell seeds near-duplicate planes on the next pass". Read in the removal's own units — the largest gap between two planes' signed heights over the annulus, against one `inlierBandMm` — **no** adjacent pass pair anywhere in the sweep is a near-duplicate: 0 of 33 across eight multiples, the closest at 1× diverging by **30.807 mm** and the closest at any multiple by **23.973 mm**, nearly five bands. CC-RANSAC is why: a pass keeps the largest *connected* component, so what a 1× shell leaves behind is a thin ring around a surface already taken and it does not form one. The shipped value therefore stands on nothing, exactly as `ringOuterMm` did once Decision 33 measured its stated rule. It does **not** move the answer — 0.000 mm at the food on both captures at every multiple, because removal happens *after* a pass, so pass 1 is drawn from an annulus this constant never touched, and the ranking picks pass 1 on both captures throughout — so it joins the count, the bar, the band count and the radius as bracket-only, leaving `annulusOuterMm` the only owed constant that moves the plane. It is bracketed **1…2.5×**, and the shipped 2× is the first owed constant in this feature to sit strictly *inside* its bracket rather than on an edge. The **ceiling** is where a shell wide enough to take the table takes the plate with it: on `1785901032716` the intended plane (pass 2, nearest Req 3.1's zero) degrades −2.203, −2.309, −2.377, −2.658, −3.011 mm over 1…2.5× and then stops existing — at 3× the nearest-to-zero candidate is pass 1, the **table**, with 3 crossed sectors of its own, so `maxCrossedSectors` reads 3…unbounded and the guard would have to admit the plane Decision 18 exists to reject. The **floor of 1** is structural, not measured: below it a pass leaves samples it selected within `inlierBandMm` and the next pass can re-find the same plane. Unlike Decision 46's radius the readings are monotone, so nothing forbids interpolating inside the bracket. Two riders. `maxCandidatePlanes` is **coupled with an order**: natural extraction depth runs [7, 5] passes at 1×, [5, 3] at 1.25×, [4, 3] at 1.5×, [3, 3] at 2× and down to [2, 1] at 6×, so the cap truncates below the shipped value and 2× is the *smallest* multiple at which it does not — Decision 48's "the cap never fires" is a reading at 2×, and its ordering (residue floor before pass cap) gains a member before both, with Req 7.6's latency denominated here for the same reason. And the committed **suite cannot bound it at all**, structurally rather than by measurement: Decision 49's bound at least reached the scenes through `visibility` and `escaped`, but no scene runs extraction, so no suite reading is even definable — the only owed constant of which that is true. One positive: `maxCrossedSectors` reads **2…2 at every multiple the bracket admits**, so unlike the candidate bound this constant does not denominate Decision 48's determination and the session sets the two apart.

**The iteration budget is set by the constant that carries no marker (Decision 51).** `maxIterationsPerPass = 2048` and `ransacSuccessProbability = 0.99` are one mechanism — `requiredIterations` returns `min(cap, log(1 − p) / log(1 − w³))` — and the shipped code never reports which end binds. The target was the **last constant in `SupportRegion` carrying no provenance marker at all**, after Decision 47's band count and Decision 48's pass cap, and it had never been varied. Measured per pass on both captures, the target is *always* the smaller: the passes spend **72, 11, 250** and **12, 41, 5** iterations against a cap of 2048, so `maxIterationsPerPass` **never fires** — the third thing in the file of which that is true — and truncates nothing at or above 256, since the largest draw the corpus ever needs is 250. That makes the cap's `[derived]` argument checkable, and its own quantity refutes it: the paragraph above prices pass 1 at a ~6 % inlier ratio, measured it is **0.402 and 0.698**, and at those ratios a 0.99 target is met in 69 and 12 iterations. The target is the live half and it **moves the answer**, which only `annulusOuterMm` otherwise does — swept 0.5…0.99999 the selected plane at the food moves **3.704 mm** on `1785135663727` (351.620, 349.473, 353.130, 351.328, 349.426, 349.426 mm), past the 1 mm Decision 35 measures Req 5.1's transfer at. The readings *wander* rather than climb, so like Decision 46's radius and unlike Decision 50's removal band **the bracket must not be interpolated**. And it is what Decision 46's caveat is **denominated in**, measured rather than inferred by elimination: that decision's eight-seed control re-run against the **cap** does not move at all (1.992 mm at 64, 2.095 mm at 256, 2048 and 8192, because the cap is not what ends a pass), and re-run against the **target** collapses **2.095 → 0.194 mm** from 0.99 to 0.99999, a 10.8× fall that takes it under the Req 5.1 bar. So the ~2 mm of draw dependence every bracket in Decisions 40–50 carries is neither a property of the captures nor a price of the cap: it is this constant, and it is **removable**. The cap is bracketed **128…unbounded** from below — at 64 the sector verdict on `1785135663727` flips from 5 supporting / 0 crossed to 3 / 2, the guard every one of those brackets is read from, and at 32 the plane moves 1.9 mm, while at 128 and above it is the shipped plane to 0.000 mm — with the ceiling open because above the largest required draw there is nothing to distinguish, so Req 7.6's worst-case latency sets it and the low-inlier-ratio scene where it would fire is one the corpus does not contain. The target is bracketed **0.9…unbounded**: `1785901032716` is draw-stable at 0.001 mm at every value from 0.9 up and jumps to 2.376 mm at 0.5. Tightening it is paid for out of the cap's 8× headroom, so the two do not compete — and it is the **only owed constant the committed corpus alone can set**, needing no capture session.

**The inlier band is where four provenance markers terminate (Decision 52).** Decision 51 closed with "every constant in `SupportRegion` now carries a provenance marker". Four of them read `[inherited]`, and a marker is a pointer: `ringBandMm` is "[inherited] `inlierBandMm`", `ringMedianMaxMm` is "[inherited] `ringBandMm`", `inlierRemovalMultiple` is a multiple *of* it, `supportVisibility` is a count *within* it. All four resolve to `LiDARPlaneFitter.inlierBandMm = 5`, which in its own file was a bare `static let` with no comment, one file outside the file this feature audits, and which had never been varied. It is the **fifth** constant that decides which planes *compete* and the most upstream of them — `annulusOuterMm` fixes the set extraction draws from, `maxCandidatePlanes` how many times it may draw, `inlierRemovalMultiple` what each draw leaves, `ringOuterMm` re-rings a set already chosen; this one decides what an **inlier is**, in three places at once (the RANSAC inlier test, the polish's re-selection, and the removal band the multiple is denominated in). It **moves the answer** by more than anything swept so far: over 1…12.5 mm the selected plane at the food moves **18.132 mm** and **19.389 mm**, the first owed constant to move *both* captures past Req 5.1's 1 mm, where `annulusOuterMm` moved 18.843 and 1.978 mm and `ransacSuccessProbability` 3.704 mm on one. Readings **wander** rather than climb, because extraction re-runs and the candidate is re-selected under the sweep, so the bracket **must not be interpolated**. Its corpus interval is **empty at the shipped bars**: three constraints bound it, all read on the plane a correct fit must select, and two of them are disjoint on `1785901032716` — `ringSupportMin` is reached only at 10 mm and above, `maxCrossedSectors` = 2 is held only at 5 mm and below, and `ringMedian` is a bar that *is* the band, failing below 4 mm on both captures. The interval is non-empty only once `ringSupportMin` falls to **0.362** or below, and there it is exactly the shipped 5 mm — so the corpus determines the band *conditionally* and hands `ringSupportMin` its first ceiling in the same reading, on a constant Decision 29 recorded as having none. That makes the band, the support bar and the crossed count **one joint set** — the feature's first three-way one, after Decision 45's pair — and it puts the band at the head of Decision 50's ordering, since the removal band is a multiple of it and Req 7.6's latency follows all four. Two riders. Extraction falls from three passes to two on both captures at 6 mm and to one at 12.5 mm, so Decision 48's "the cap never fires" and Decision 50's pass-depth table are readings at this band as much as at that multiple. And the committed **suite gives it nothing for a third distinct reason**: Decision 49's bound was silent by measurement, Decision 50's removal band was unreadable structurally, but this one *does* reach the scenes and every reading from 1 to 12.5 mm is identical — `SPRScene.makeDepth` adds ±0.3 mm of synthetic noise, an order of magnitude below the smallest band swept, so **the committed scenes validate every guard's logic and no tolerance in any of them**.

**Device-gated:** Req 7.6's budget, Req 7.8's weighed on-device verification, and Req 7.10's weighed single-view rimmed-plate capture — no such capture exists yet (the 2026-08-05 session's lipped-plate capture landed on the two-view path; prerequisites capture 4 is the retake). Per Req 7.11, a weighed capture counts as evidence only where it completed on the single-view LiDAR path — check `capturePath` before grading anything against it.

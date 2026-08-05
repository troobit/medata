# Design: Support Plane Reference

## Overview

Replace "largest gravity-aligned plane in the frame" with "the gravity-aligned plane the food is resting on", by bounding the candidate samples to the food's neighbourhood, scoring candidates on the size of their largest connected inlier component rather than raw inlier count, and selecting on measured contact with the food. Rejection routes to today's fit unchanged.

## Architecture

### What changes and what does not

`ransac`'s minimal sampling, the 15° gravity cone, `refine`'s scatter-matrix SVD and the deterministic consensus polish are correct and reused. Three things change: **which samples compete**, **how a candidate is scored**, and **which candidate wins**.

### Bound the candidate set to an annulus

**Today's set is already bounded — an earlier draft of this design asserted otherwise and was wrong.** `collectCandidatePoints` defaults to `.bandsAroundFoodRegion` (`LiDARPlaneFitter.swift:61`) and scans four bands around the food bbox, each as thick as the bbox dimension perpendicular to it (`:237-250`), added by `lidar-plane-fit-degenerate-on-clean-capture`. `.insideMask` has exactly one caller, `FixtureRunner` (`:251`). Floors and hobs are not competing for candidate slots; the table is, from inside a region of roughly `4 · w · h`.

That refutes the earlier proposal rather than refining it. `dilate(foodMask, 2 × foodRadius)` spans ≈ `(2.9 s)² ≈ 8.3 s²` against the bands' `4 s²` for an `s × s` bbox — **looser than today, not tighter** — so none of the three benefits that draft claimed follow from it.

The bound that does deliver them is an **annulus of `2 × ringOuterMm` around the food mask**: 50 mm of support surface, concentric with the food rather than square with its bbox. It is tighter than the bands for any food that does not fill its bbox, and it is the same region the ring measure already reads, so it introduces no new scene-dependence.

**Where the sample reduction actually comes from.** The ~56× is the native-depth-grid move (Req 2.4), not the bound: 1920×1440 ÷ 256×192 = 56.25. That change stands on its own, and it is where the CPU headroom for the extra passes comes from. Crediting it to bounding, as the earlier draft did, double-counted one saving and hid that the bound was doing the opposite of what was claimed.

**Where the iteration budget actually comes from.** Not from a raised pass-1 inlier ratio. At the diagnosed capture's ~6 % plate fraction, `maxIterationsPerPass = 2048` reaches only ~36 % probability of a clean triple — an order of magnitude short. The budget is sufficient because extraction is **sequential**: pass 1 removes the table's inliers, and it is the plate's fraction *of the residue* that pass 2's formula applies to. The implementation MUST report the per-pass residue inlier ratio so this holds as a measurement rather than an assumption.

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

**Extraction loop.** Up to `maxCandidatePlanes` passes; each removes the **polished** inlier set within `2 × inlierBandMm` (a thin shell left at 1× seeds near-duplicate planes on the next pass). Stops early when the residue falls below `minResidueAreaMm2` — named for the one question it asks, since the whole-fit sufficiency question it also used to answer is now asked exactly (Decision 32, below), and denominated in millimetres² so the pass count follows the scene rather than the depth grid (Decision 38, below).

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

An earlier draft added `restrictedResidualMaxMm = 8`, justified by "a straddling region fits at ~13 mm RMS". That is a property of plain least squares over a fixed region — the flood-fill option Decision 11 rejected. Under RANSAC the residual is computed over `polishedInliers`, each within `inlierBandMm = 5` of the plane, so RMS is **≤ 5 mm by construction** and the bar can never fire (`LiDARPlaneFitter.swift:25, 136-140`). It would also push matte-table captures onto the fallback, since Decision 46 raised the general bar to 20 mm for genuine single-surface depth noise. The sector measure reads the straddle directly and does fire; the inner-band MAD bar Decision 16 first put here turned out to share the residual bar's cannot-fire defect and is deleted in turn (Decision 19).

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

**`ringSupportMin = 0.6` is in tension with the matte-table evidence and must be measured against it.** A ±5 mm band at 0.6 support implies σ_z ≲ 5.9 mm on the support surface. `lidar-plane-fit-matte-table-confidence` and Decision 46 exist because matte tables produce genuine single-surface noise large enough to justify a 20 mm residual bar. If that noise exceeds ~6 mm in practice, every matte-table capture falls back and Req 4.5's fallback-rate defect fires for a reason unrelated to plane selection. Task 26 must measure the support-surface noise distribution before this constant is fixed.

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
                                               // ringInnerMm (Decision 33)
    public static let ringBandCount = 3        // structural: inner/mid/outer
    public static let bandStepMaxMm: Float = 6 // [owed] below the smallest measured rim
                                               // step; UNEXERCISED — every corpus step is
                                               // a fall, −0.5…−6.5 mm (Decision 34)
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
                                                     // bracketed 0…2 — is [owed] to capture
                                                     // 6, so nothing is rewired yet
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
    public static let ringMinSamples = 200
    // [derived] Decision 22 — replaces foodAboveFractionMax, which rejected this
    // feature's own acceptance capture. Reject when the plane lies above the
    // food's upper envelope: percentile of signed food height, in MILLIMETRES
    // as Req 3.4 states, not a sample-count fraction.
    public static let foodEnvelopePercentile: Float = 0.90
    public static let foodEnvelopeMinMm: Float = 0    // [owed] Decision 22; bounded above
                                                 // at 25.8 mm by the intended candidate,
                                                 // not below — every corpus envelope is
                                                 // positive (Decision 34)
    public static let maxCandidatePlanes = 3     // structural: table, support, one more
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
    public static let maxIterationsPerPass = 2048 // [derived] adaptive stopping caps it;
                                                  // per-pass residue ratio is reported

    // Depth intrinsics derived from colour (device depthIntrinsics are zeros).
    static func depthIntrinsics(from colour: CameraIntrinsics, depth: DepthMap) -> CameraIntrinsics

    // Depth-grid indices in the annulus, excluding food and low-confidence
    // samples. τ_conf = 0.40 applies here as it does in the band scan, so
    // `lidar-plane-fit-matte-table-confidence` is not bypassed (Req 7.5).
    static func contactRing(foodMask: BinaryMask, depth: DepthMap,
                            intrinsics: CameraIntrinsics) -> [Int]

    // `annulus` is the bounded candidate set (2 × ringOuterMm around the mask);
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

**Numbers this design owes the requirements** — to be fixed during implementation against the fixture corpus, not asserted now. Every `SupportRegion` constant is annotated `[derived]`, `[measured]`, `[inherited]`, or `[owed]`; the `[owed]` ones are task 26 corpus measurements, with the sector trio under Req 3.7's explicit ban on shipping asserted values, and each measured value lands with its derivation recorded in `decision_log.md` (Req 3.7). Beyond the constants: the Req 4.5 fallback-rate defect threshold, ~~Req 5.1's device/replay plane tolerance and named fixture~~ (**measured, Decision 35** — see below), Req 7.6's latency and memory budget, and `fallbackPenalty` (**bounded above, Decision 36** — see below; the value is owed to the same Bucket C gate as the fallback rate). Each is a measurement, and stating a value here would be inventing evidence. Two `[owed]` constants have had their **denomination** settled without their value being set — `minAcceptedExtentMm` (Decision 37) and `minResidueAreaMm2` (Decision 38) — which is a separate thing from being measured and does not remove them from the list. The sector trio's replacement **rule** is settled without its count being set (Decision 40 — see below), which adds `maxCrossedSectors` to the list rather than removing anything from it.

**Req 5.1's tolerance, and the one bar that does not transfer (Decision 35).** The tolerance is **1 mm** of plane movement at the food and the named fixture is **`1785135663727`**. Device and replay share one implementation, so identical bytes give an identical plane and the tolerance is not about arithmetic; what differs is the depth grid. Measured across a 2× halving, the plane moves 0.835 mm on `1785135663727` and 0.037 mm on `1785901032716`, normals tilting 0.945° and 0.063°. The comparison is taken where each plane cuts the food-mask centroid ray, because volume is integrated per-pixel above the plane and a millimetre there is a millimetre on every food pixel. Three riders. The transfer has a floor at the ring, not the plane: at 64×48 the inner band holds 37 and 32 samples against `ringMinSamples = 200`, and since `mmPerPx = z / f_d` this is the ≈ 365 mm range envelope of Decision 29 reached by coarsening `f_d` instead of raising `z`. `planeCandidateCount` is grid-dependent where the plane is not — three passes natively, two at half resolution; **that rider is closed by Decision 38** — see below. And `minAcceptedExtentPx` was the only bar in `admissibility` denominated in **pixels** rather than millimetres or a fraction, so it halved with the grid: a surface admitted at 44 px was rejected as a sliver at 22 px. That bracket was a 256×192 bracket, and N5k's pinned f = 617 px against the device's measured f_d = 182.033 px makes the same physical extent span 3.389× more pixels there. **That rider is closed by Decision 37** — see below. The device leg of Req 5.1 stays task 27's: decimation models a coarser grid, not a different sensor.

**The extent bar is re-denominated, and the rider closes (Decision 37).** `minAcceptedExtentPx = 24` becomes `minAcceptedExtentMm = 44`, converted through the `mmPerPx` the ring radii already use, so no bar in `admissibility` is denominated in pixels any longer and Req 5.1's transfer claim carries no exception. **The value does not move**: 24 px at the corpus's `mmPerPx` of 1.8616 and 1.8393 is 44.68 mm and 44.14 mm, and 44 mm is the largest whole millimetre at or below both, so every corpus verdict is unchanged. The bracket becomes physical — **22.339…47.821 mm**, from measured extents of 228.973/141.479/22.339 mm and 285.084/80.927/47.821 mm — where 13…26 px meant different physical sizes on the two captures and nothing at all on another grid. Across the same 2× halving, four paired surfaces have their pixel extents halve (123→61, 76→38, 155→77, 44→22) while their millimetre extents drift 1.698, 0.102, 1.839 and 0.000 mm, at most half a halved-grid pixel; verdict flips fall from one to **zero**, and the 44 px → 22 px pair Decision 35 named now reads 80.927 mm on both grids. The constant stays `[owed]` — re-denominating it does not set it — and it now assumes the candidate surface lies at roughly the food's range, the same assumption every ring radius makes.

**The residue floor is re-denominated, and the second rider closes (Decision 38).** `minResidueSamples = 500` becomes `minResidueAreaMm2 = 1691`, converted per capture through the same `mmPerPx`. A raw sample count divides by four under a 2× halving where the surface it stands for does not, and that is what made `planeCandidateCount` — a **persisted** field (Req 6.1) — read the sensor's grid rather than the scene. **The value does not move**: 500 samples at the corpus's pixel areas of 3.465 mm² and 3.383 mm² is 1732.6 mm² and 1691.5 mm², so 1691 mm² is the largest whole millimetre² at or below both and every corpus pass keeps its verdict. What the measurement shows is that the residue's **area** is the invariant: the annulus itself agrees to 0.3 % and 1.2 % across the halving (36 280 → 36 176 mm², 42 458 → 41 961 mm²) where its sample count quarters, and later passes drift further — 5.0 %, 4.9 %, 6.4 %, 22.7 % — because each pass removes its own inliers within a millimetre band and that removal is resolved on the grid. The pass the old floor cut now runs: 155 and 180 samples on the halved grid, below the 500 the count floor was and above the 122 and 125 the area floor is there, so the candidate count is **3 → 3** on both captures and the plane at the food does not move (0.835 mm and 0.037 mm, unchanged). The constant stays `[owed]`; the corpus still bounds it from above only, now at **2013 mm²**, and the smallest residue on the halved grid clears it by 1.44× against 1.86× natively.

**What falling back costs, and what the penalty charges (Decision 36).** `supportPlaneFallbackPenalty` is a price, not a bar, and Req 4.6 — "no higher than a restricted fit of *equal* residual" — is met by any value in (0, 1), so it cannot choose one. The denomination is the curve's: σ_plane = exp(−r/5) with r in millimetres, so p charges −5·ln(p) mm, and 0.9 charges **0.53 mm**. Measured per food sample on `1785135663727`, the edge-band plane adds **18.37 mm** to the mean food pixel (p10 7.96, p90 28.61 — the two planes are 7.18° apart, which is why the measure is a per-sample mean rather than Decision 35's single ray), pricing the fallback at **0.025**: a **35.5×** over-report, corroborated by the 408 cm³ the regression suite measures between the pre-feature and corrected volumes. Two riders. The residual channel works *against* the penalty — the edge-band plane is a good fit to the wrong surface, so its residual is lower than the restricted fit's (1.95 vs 2.33 mm) and exp(−r/5) rewards it; 71 % of the penalty is spent cancelling that, and the net reduction on the same capture is **3.1 %**. And the bound is one-sided: the fallback is the *correct* plane when food rests directly on the surrounding surface, so a single constant prices a mixture whose weight is Req 4.5's fallback rate, absent until Bucket C. Pricing it per capture from the persisted ring measure is measured and rejected — the ratio of ring median to offset at the food is 0.231 and 2.471, wrong in both directions, for Decision 33's reason.

**What the corpus pass settled (Decision 29).** `SupportPlaneCorpusMeasurementTests` is the instrumented, guards-disabled pass over the committed slices. It confirms `ringInnerMm = 8` with a stated ≈ 365 mm range envelope, confirms `ringMinSamples = 200` per band at 5.6–7.0× margin, and establishes that `supportVisibilityMin` is firable — the ratio is computed over the annulus, not the ring, so it does see a thin support strip. It cannot settle the rest, for two measured reasons: neither committed capture is a clean correct fit (both rings cross the plate edge — per-sector inner medians reach −32.6 mm on one and +19.8 mm on the other), and per-sample noise on a flat surface measures 3.44 mm on one and 6.98 mm on the other at the same range, straddling `ringBandMm`. Decision 30 records that the sector count is additionally blind to the sign that distinguishes the two cases; Decision 40 states the rule that restores it and shows its bar is inherited.

**How much of the guard table the corpus reaches (Decision 34).** Three of the nine rejection reasons ever fire on it — `extent`, `supportFraction`, `sectors` — and a fourth, `ringMedian`, only when the guards are evaluated independently rather than short-circuited. The other five never fire, and four `[owed]` constants sit behind them: `foodEnvelopeMinMm` (bounded above at 25.8 mm by the intended candidate's envelope, not below, since every corpus envelope is positive), `bandStepMaxMm` (the guard reads an outward rise; every corpus step is a fall of −0.5 to −6.5 mm), `supportVisibilityMin` (firable, never fired — the corpus floor is 0.246 against a 0.15 bar), and `escapeBandMm` (one-sidedness confirmed correct against Req 3.3, but the corpus reaches +5.7 mm against a 30 mm bar). `ringSupportMarginMin` is not reachable at all: it compares the top two **admissible** candidates and neither capture produces one. These four are therefore not merely unset — nothing in the corpus exercises the guards they gate, so the capture session has to produce the scenes that fire them, not just the scenes that set their values.

**Why both rings cross the plate edge (Decision 33).** The same pass measures the **support margin** per sector — the distance from the food boundary at which the surface departs from itself by more than `ringBandMm`. Measured margins are 16, 40, 10, 42, 6, 4, 6, 44 mm and 34, 4, 46, 8, 30, 14, 12, 6 mm, every in-ring departure a fall of 5.1–15.6 mm, so they are plate edges rather than rims. Three consequences. `ringOuterMm`'s stated rule — inside the smallest measured plate margin — is **unsatisfiable**, because that margin is 4 mm on both captures, inside `ringInnerMm`. Only 3 of 8 sectors reach `ringOuterMm` and only 4 of 8 reach the inner band's 13.7 mm, which is below `minSupportingSectors = 6`, so plate geometry caps the supporting count before `sectorSupportMin` is consulted. And the crossings Decision 29 attributes to the captures are therefore in part a property of the ring's radial extent, which the capture session must record per sector so the trio and `ringOuterMm` are derived together.

**The sector rule, and the one axis of it that costs nothing (Decision 40).** Decision 30 measured the blindness and declined to state a rule, on the ground that a signed rule needs a threshold with the same evidence problem as every other `[owed]` constant. Measured, that holds on one axis only. The rule is: a **failing** sector — below `sectorSupportMin` — whose signed inner-band median exceeds `+ringBandMm` is **crossed**, and a candidate is rejected when more than `maxCrossedSectors` sectors are crossed; a failing sector below `−ringBandMm` has **escaped**, which is the plate ending and not grounds for rejection. The magnitude bar is `ringBandMm`, already `[inherited]` and already the bar deciding which samples in those sectors count as supported, so **no new millimetre constant is created**: the plate candidate's highest failing median is −6.794 mm and the table candidate's lowest is +16.603 mm, a **23.397 mm** window with `ringBandMm = 5` sitting 11.794 mm above its floor and 11.603 mm below its ceiling. Restricting to failing sectors is what earns that — across *all* sectors the window is +3.846 to +5.974 mm, **2.128 mm** wide, and a bar surviving that narrowly is fitted rather than inherited. The rule is the per-arc form of `ringMedianMaxMm`, which on the table candidate reads +3.04 mm and does **not** fire while three of its sectors read +16.6 to +19.8 mm — Decision 18's silent-failure case measured rather than argued. What stays `[owed]` is the count: the corpus brackets `maxCrossedSectors` at **0…2** (0 crossed on the plate candidate, 3 on the table one) and prerequisites capture 6 sets it. Shipped code is unchanged, because shipping the rule means asserting that count and Req 3.7 names these constants specifically.

**Device-gated:** Req 7.6's budget, Req 7.8's weighed on-device verification, and Req 7.10's weighed single-view rimmed-plate capture — no such capture exists yet (the 2026-08-05 session's lipped-plate capture landed on the two-view path; prerequisites capture 4 is the retake). Per Req 7.11, a weighed capture counts as evidence only where it completed on the single-view LiDAR path — check `capturePath` before grading anything against it.

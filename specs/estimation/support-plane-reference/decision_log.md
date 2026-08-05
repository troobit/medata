# Decision Log: Support Plane Reference

## Decision 1: Folder named `support-plane-reference`

**Date**: 2026-07-27
**Status**: accepted

### Context

The feature needed a name before requirements could be written, and the candidates each pre-committed to an answer the requirements had not yet reached.

### Decision

Name the feature `support-plane-reference`.

### Rationale

It names the thing being corrected — which surface the support plane refers to — without asserting what that surface is. That matters because the bowl question (Decision 3) could have made "the plate top" wrong: food in a bowl rests on the bowl interior, not on a plate.

### Alternatives Considered

- **`plate-top-support-plane`**: Direct and descriptive — Rejected: pre-commits to a plate being the reference, which the bowl case complicates.
- **`flat-food-volume-overread`**: Names the observed symptom — Rejected: symptom-named and understates scope; rice over-read 2.1× and apple is affected too, so the defect is not flat-food-specific.

### Consequences

**Positive:**
- The name stays accurate whichever way the bowl question is decided.

**Negative:**
- Less immediately obvious to a reader looking for the over-read bug; mitigated by cross-references from the bugfix diagnosis.

---

## Decision 2: Full spec, not a smolspec

**Date**: 2026-07-27
**Status**: accepted

### Context

The project's smolspec bar is under 80 LOC across 1–3 files. A scope assessment put this work at ~300–450 production LOC across 8+ files and five subsystems.

### Decision

Use the full spec workflow: requirements, design, decision log, tasks.

### Rationale

Every full-spec criterion is tripped, and three genuinely ambiguous questions needed a user decision before any code could be written. A smolspec has no phase in which to ask them.

### Alternatives Considered

- **Smolspec**: Faster to start — Rejected: exceeds the LOC and file bar several times over, and reverses three documented decisions across other specs.
- **Bugfix report only**: The defect is diagnosed and a fix exists offline — Rejected: the code correctly implements the current specification, so this is a specification change, not a defect repair.

### Consequences

**Positive:**
- The breaking changes to pipeline Req 4.2, MD-9 and `lidar-plane-fit-degenerate` Decision 1 get recorded rather than made silently.

**Negative:**
- Slower than patching the plane fit directly.

---

## Decision 3: Bowls fall back to the existing reference rather than being modelled

**Date**: 2026-08-05
**Status**: accepted

### Context

Food in a bowl rests on the bowl interior. The two candidate techniques diverge precisely here: an annulus hugging the food mask would fit the bowl rim, and a flood fill may climb the inner wall to the rim. Either way the fitted plane can land *above* the food surface, clamping per-pixel heights to zero and collapsing volume — worse than today's over-read. A cereal bowl is an MVP capture target (`myfoodrepo-bridge` task 7).

### Decision

When the restricted region does not describe a flat support surface — detected by the fitted plane lying above a stated share of the food region's depth points — fall back to the existing edge-band fit. Bowls keep today's behaviour; plates get the correction (Reqs 3.1–3.4, 4.1).

### Rationale

The failure mode being avoided is not inaccuracy but inversion: a collapsed volume reads as near-zero carbs, whereas today's bowl behaviour merely over-reads.

**The harm ordering needs the argument written down, because it is not self-evident.** Review challenged it, and fairly: a 3.57x over-read turns 34 g into 108 g, roughly seven extra units at 1:10, which is an acute hypoglycaemia hazard, while an under-read causes correctable hyperglycaemia. On physiological consequence alone the ordering inverts.

The defence is **detectability, not consequence**. A near-zero reading on a real plate of food is silent and plausible — a small portion reads small, and nothing about the number invites a second look. A 3x reading on two slices of bread is implausible on inspection and gets caught by the human holding the phone. An error that announces itself is safer than one that does not, at equal magnitude. That asymmetry is what justifies preferring the over-read, and it holds only while a human reviews every number — it would not survive automated dosing.

Detection is cheap and uses information the fit already has. Modelling the bowl interior properly is the only option that makes bowls accurate, but it is the largest piece of work here and has no proven in-repo technique behind it — it can be a later feature once the plate case is measured and correct.

### Alternatives Considered

- **Refuse the capture when the region is not flat**: Consistent with the project's fail-closed invariant — Rejected: it fails the cereal-bowl MVP capture target, and a bowl is an ordinary way to eat a meal.
- **Model the bowl interior as the support surface**: Most correct in principle and the only option that makes bowls accurate — Rejected for now as the largest scope with no proven technique; deferred rather than dismissed.
- **Restrict the spec to flat plates and leave bowls undefined**: Smallest scope — Rejected: leaves an MVP capture target unaddressed and the failure silent.

### Consequences

**Positive:**
- No capture regresses; the collapse-to-zero failure cannot occur.
- The correction ships for the plate case, which is where the weighed evidence is.

**Negative:**
- Bowls keep a 2–3× over-read, and the fallback makes that invisible unless the recorded reference (Reqs 4.4, 6.1) is consulted.
- The flatness test needs a threshold with no field evidence behind its specific value yet.

---

## Decision 4: Overhanging food is accepted and documented, not compensated

**Date**: 2026-08-05
**Status**: accepted

### Context

In the diagnosed capture the lower bread slice overhangs the plate onto the worktop, so a plate-referenced plane under-measures it. True volume is bracketed at 236–262 cm³ — about an 11 % spread — depending on how far the reference is taken to extend.

### Decision

Measure overhanging food against the same fitted support plane, with no extension, detection, or compensation (Req 1.3). Record the bracket as a known limitation.

### Rationale

An 11 % residual sits against a 3.2× error being removed. Correcting it now would be tuning a rounding error while the dominant defect is live, and doing so requires assuming geometry the depth map does not support — an extension of the plane past its evidence, which is how the table became the reference in the first place.

### Alternatives Considered

- **Detect and flag in diagnostics**: Cheap, makes the error visible per capture — Rejected for now: it adds a diagnostic whose consumer (the per-capture error log) does not exist yet. Reconsider once that log is in place.
- **Compensate by extending the plane across overhanging pixels**: Removes the under-measurement — Rejected: the extension is an assumption the depth data cannot support and risks reintroducing the table as a reference by the back door.

### Consequences

**Positive:**
- Keeps the change focused on the dominant error.
- No new assumption about scene geometry.

**Negative:**
- Overhanging food stays under-measured by up to ~11 %, partly offsetting the correction and making the fixed figure harder to attribute exactly.

---

## Decision 5: Starvation falls back to the edge-band fit, with the reference recorded

**Date**: 2026-08-05
**Status**: accepted

### Context

`lidar-plane-fit-degenerate-on-clean-capture` Decision 2 widened the sampling bands specifically to avoid candidate starvation. Restricting the region to the surface under the food narrows sampling again and risks reintroducing exactly that failure.

### Decision

Attempt the restricted fit first; on insufficient candidates or a failed residual bar, fall back to the existing edge-band fit and complete the estimate. Record which reference produced the plane on every attempt (Reqs 4.1–4.4).

### Rationale

The invariant Decision 2 exists to protect is that a capture which succeeds today must not start failing. A fallback guarantees that structurally rather than by tuning. Recording the reference is what keeps the guarantee honest: without it, a silent fallback would mix two geometric bases in the accuracy log and make per-capture error unattributable — the same class of problem as mixing checkpoints in a harness run.

### Alternatives Considered

- **Progressive widening before falling back**: Recovers more captures onto the correct reference — Rejected for now: each stage is a tuning knob with no evidence behind it, and it makes the outcome harder to attribute. The recorded reference will show whether enough captures fall back to justify it.
- **Refuse rather than fall back**: Never returns a number from the wrong reference — Rejected: breaks the Decision 2 invariant directly; captures that produce a usable number today would start failing.

### Consequences

**Positive:**
- No capture that works today can regress.
- The accuracy log can segment by reference, so the fallback rate is measurable rather than assumed.

**Negative:**
- Some captures keep the old over-read while appearing to have succeeded normally.
- Two code paths to maintain and test instead of one.

---

## Decision 6: Stored meals are left untouched

**Date**: 2026-08-05
**Status**: accepted

### Context

Every meal already stored was estimated against the table reference and is therefore over-read — 3.2× on the bread capture. Fixing the reference makes new records incomparable with old ones.

### Decision

Leave stored meals exactly as recorded. No re-estimation, no rewrite, no migration (Req 7.9). The plane-reference diagnostic (Req 6.3) is what distinguishes old records from new.

### Rationale

The event log is append-only and a stored meal is a record of what the app said at the time, not a live calculation. Rewriting a past record the user may have dosed against is its own hazard, independent of whether the new number is better.

Re-estimation is also not available in general: capture bundles exist only from the recorder onward, so older meals have nothing to replay, and replay is not bit-exact — measured at −4.6 % against the device on the same attempt. A migration would therefore produce a third basis rather than converging on one.

### Alternatives Considered

- **Re-estimate stored meals from their capture bundles**: Makes history internally consistent — Rejected: bundles do not exist for older meals, replay is not bit-exact, and rewriting a dosed-against record is hazardous.
- **Flag pre-fix records in the UI**: Honest about incomparability — Rejected during the developer phase, where the no-disclaimer rule applies (design-handoff-00 Decision 21). Revisit before any non-developer release.

### Consequences

**Positive:**
- No migration, no schema rewrite, no risk of corrupting history.
- Error analysis can still segment cleanly, via the recorded reference.

**Negative:**
- Historical carb figures remain over-read, so any trend spanning the fix has a step change in it that only the diagnostic explains.

---

## Decision 7: The non-LiDAR two-view path is explicitly out of scope

**Date**: 2026-08-05
**Status**: accepted

### Context

The two-view + ID-1-card path is retained, not descoped (`segmenter-foundation` Decision 26), and it has no depth map. A reader could reasonably assume a feature about the support-plane reference must say something about it.

### Decision

State plainly that the path is unaffected: it derives volume from card-scaled silhouettes and references no depth-derived support plane, so this defect cannot occur there (Req 1.5).

### Rationale

Saying nothing would leave a reader to wonder, and inventing an equivalent reference would add work to a path that is not exhibiting this defect. That path has real accuracy problems — today's bread capture read 4× *under* on it, and misclassified the bread as carrot — but they are separate defects with separate causes.

### Alternatives Considered

- **Define an equivalent reference from the detected card's plane**: Conceptually unifies the two paths — Rejected: assumes the card is coplanar with the food's support, and adds scope to a path with a different, unrelated failure.

### Consequences

**Positive:**
- Keeps the feature scoped to the defect it is fixing.

**Negative:**
- The two paths now reason about the support surface differently, which must be remembered when comparing their outputs.

---

## Decision 8: The plane-reference diagnostic is persisted, not logged

**Date**: 2026-08-05
**Status**: accepted; the *choice of measure* is superseded by Decision 9 (persistence over logging still holds)

### Context

No existing diagnostic could have caught this defect. On the wrong plane the residual was 1.95 mm, the inlier count 510,499, and coverage healthy — every signal said the fit was good. What was missing was any measure of *which* surface was fitted.

### Decision

Persist the reference used and the chosen plane's height above the next strongest consensus plane into the per-attempt outcome record, alongside the existing plane diagnostics (Req 6.1).

### Rationale

That is where `planeResidualMm` and `planeInlierCount` already live, so the new fields sit with the ones they qualify. It survives log eviction — this project has already lost plane-fit diagnostics to log flooding (`capture-log-flood-evicts-plane-fit-diagnostics`) — and it is queryable from a pulled database, which is precisely how the defect was quantified on 2026-08-05. A height above the next consensus plane is the one number that distinguishes a plate-top fit from a table fit; either alone looks healthy.

### Alternatives Considered

- **Log only**: No schema change — Rejected: os_log is exactly the channel that already evicted this class of diagnostic, and it is not queryable from a pulled database.
- **Both log and persist**: Immediate visibility plus durable history — Rejected: the log copy answers nothing the persisted row cannot, at the cost of more surface and more flood risk.

### Consequences

**Positive:**
- The defect class becomes detectable rather than needing an offline investigation to find.
- Old and new attempts are distinguishable without a separate migration flag.

**Negative:**
- Adds fields to the persisted outcome measurements, which every consumer of that record must tolerate.
- Computing the next-strongest consensus plane is work the fit does not currently do.

---

## Decision 9: The diagnostic is the contact-ring median signed height, not a next-plane gap

**Date**: 2026-08-05
**Status**: accepted (supersedes Decision 8's choice of measure; its persist-not-log conclusion stands)

### Context

Decision 8 chose to record "the height of the chosen plane above the next strongest consensus plane in the scene". Review found that measure weak on several independent grounds, and the objections hold up.

It measures the *scene's planar structure* rather than the relationship between the plane and the food. A tightly framed plate-filling shot — geometrically the best capture available — has no meaningful second plane, so the clearest captures yield the least interpretable number. It is not monotone in the defect: a correct plate fit reads +3 mm with a placemat in frame and +880 mm with the floor in frame. A near-zero gap is consistent with both "correctly on the plate, with a co-height placemat nearby" and "wrongly on the table, with clutter at table height". And "consensus plane" already means something else in `LiDARPlaneFitter` — `consensusPolishMaxPasses` names the deterministic polish loop — so the term would be misread.

### Decision

Record instead the **median signed height, above the candidate plane, of non-food depth samples in a thin ring immediately outside the food region boundary** (Reqs 3.1, 6.1). Use the same measure as the rejection test in Req 3.2 and as the persisted diagnostic.

### Rationale

It measures the thing that actually matters — whether the plane passes through the surface the food is touching — and it has a physical zero rather than a tuned threshold. Food rests on its support, so the ring reads about zero for a correct fit, strongly positive for the table plane, and negative for a vessel rim. One signed number separates all three cases, and the sign carries the diagnosis.

The evidence for it already exists in the diagnosis, computed by hand: the median signed-height map recorded "a ring of plate at **+18…+26 mm** hugging the food" against a worktop at 0 mm. That ring *is* this measure. Req 6.2 turns that into a falsifiable expectation on a named capture, so the diagnostic is testable rather than merely recorded — which the Decision 8 version never was, since no criterion said what any of its values meant.

It also costs less than the alternative: a median over a few thousand samples, against a second RANSAC pass over the scene.

### Alternatives Considered

- **Height above the next strongest consensus plane** (Decision 8): captures the "two plausible planes" intuition — Rejected on the grounds above: scene-dependent, non-monotone, sign-ambiguous, undefined referent, and colliding with existing vocabulary.
- **Region area ÷ food-mask area**: cheap gross-leakage check — Rejected as the primary measure: it is scene-dependent (a grape on a dinner plate gives ~50×, a full plate ~1.2×, so no fixed bound works), it says nothing when the fallback fires, and decisively it measures the *region* rather than the *plane*, so it cannot detect a wrong plane fitted to a correct region. Worth keeping as a secondary sanity check.
- **Persist nothing; rely on the residual**: no new fields — Rejected: the residual was 1.95 mm on the wrong plane and 2.27 mm on the right one, so it points the wrong way. This is the whole reason the defect survived.

### Consequences

**Positive:**
- One number, with a physical zero, that is meaningful on both the restricted and the fallback path.
- Already validated by hand against the diagnosed capture, so Req 6.2 can assert an expected value.
- Serves as both the rejection test and the recorded diagnostic, so the thing that gates the decision is the thing that gets logged.

**Negative:**
- Depends on the food mask boundary, so mask error perturbs it — the same coupling Req 3.5 exists to record.
- Segmentation leakage onto a vessel rim biases the ring, in the direction of accepting a rim fit.
- The band around zero is still a tuned constant, though a physically anchored one.

---

## Decision 10: β_c application fails closed on a missing plane reference

**Date**: 2026-08-05
**Status**: accepted (revises the draft form of Req 4.3)

### Context

The requirement was first drafted as "IF a calibration artefact records a support-plane reference *different* from the one in use, THEN do not apply its β_c values." Review pointed out the default is inverted: an artefact recording *no* reference does not satisfy that antecedent, so it is applied — and every artefact produced before this feature records no reference. Those are exactly the artefacts calibrated on the old basis.

### Decision

Apply β_c only when the artefact records a reference *matching* the one in use. Absent metadata blocks application (Req 5.3). Where a corpus spans both references, fit β_c on the subset sharing the reference it will be applied under (Req 5.4).

### Rationale

The requirement exists to stop a 26 mm geometric offset being absorbed into calibration constants as if it were a bulk-density property of food, where it becomes very hard to detect. A guard that passes unlabelled artefacts fails at precisely the moment it is needed. Fail-closed also matches the project's existing posture — the harness already refuses a fixture whose checkpoint SHA does not match rather than assuming compatibility.

The corpus-subset rule closes the adjacent hole: if field captures are a mix of two references, no single β_c is valid across them, and fitting on the mixture would bake in a blend of two geometries.

### Alternatives Considered

- **Treat a missing reference as a match**: no migration needed for existing artefacts — Rejected: it is the failure this requirement exists to prevent, and it fails silently.
- **Warn and apply anyway**: preserves current behaviour while surfacing risk — Rejected: β = 1 for every food today, so nothing is lost by blocking, and a warning nobody acts on is not a guard.

### Consequences

**Positive:**
- The calibration transfer contract cannot be satisfied by an artefact that does not state its basis.
- Consistent with the checkpoint-SHA guard already in the harness.

**Negative:**
- Any future calibration artefact must carry the reference or be rejected, which is a migration cost the moment calibration begins.
- Currently unfalsifiable in practice: every β is `uncalibrated_unity` and calibration is a Non-Goal, so this guard has nothing to act on until then.

---

## Decision 11: Multi-plane extraction with contact-based selection, not region growing

**Date**: 2026-08-05
**Status**: accepted

### Context

The requirements say the fitted region must be food-derived and exclude food pixels (Reqs 2.1–2.2) but not how it is found. Three techniques were assessed: promoting the existing flood fill with a food-derived seed; sequential RANSAC extracting several gravity-aligned planes and selecting by contact with the food; and the latter plus a connected-component filter keeping only the plane fragment adjacent to the food.

Two claims made against the ambitious options during the interview did not survive checking, and the record should say so.

**The out-of-memory objection was largely spent.** The 1920×1440 failure was `svdFull(A, rows: 3, cols: n)` allocating O(n²); `lidar-plane-fit-oom` Decision 1 replaced it with a 3×3 scatter matrix accumulated in one O(n) pass into nine floats. Memory no longer scales with point count, so fitting more planes does not reintroduce it. The cost of extra passes is CPU, not memory — and the move to native depth-grid sampling (~49k samples against ~2.7M colour-grid enumerations, Req 2.4) more than pays for them.

**The testability objection did not hold at all.** All three candidates are pure deterministic functions of `(depth, mask, intrinsics, gravity)`, inheriting determinism from the existing depth-hash-seeded RNG. All are unit-testable against synthetic depth maps, all replay identically through the harness against the two real bundles, and all are equally observable in the field through the Req 6.1 persisted fields. The multi-plane options need *more* test cases because they have more behaviour; that is not the same as being less testable.

### Decision

Extract up to `maxCandidatePlanes` gravity-aligned planes by sequential RANSAC on non-food native depth samples, select the plane whose contact-ring median signed height is closest to zero, and retain only the inlier component adjacent to the ring. Reject to the edge-band fallback when no candidate passes the guards.

Component adjacency is staged second: extraction and selection are verified against both real bundles first, and adjacency lands when a fixture demonstrates the co-height-surface failure it exists to prevent.

### Rationale

The flood fill has a structural limit, not a tuning one: it compares only neighbouring pixels, so it cannot distinguish a flat surface from a gradual curve. A bowl wall defeats it at every threshold value. ARKit's depth is fused and upsampled from a sparse dot pattern and smoothed over several pixels, so a 20 mm plate rim spread across ~4 depth pixels is 4–6 mm per pixel — at or under the 5 mm continuity threshold, and the gradient flattens further with capture distance. Its evidence base is also thinner than the scratch notes implied: Nutrition5k fixtures on a fixed overhead rig plus one synthetic hard-step unit test, and no evidence at all on ARKit `sceneDepth` at 256×192.

Multi-plane extraction tests **global planarity over a candidate set** rather than local pixel steps, so smoothing degrades it gracefully instead of defeating it. Selecting on proximity to the object rather than on area is the standard tabletop-segmentation rule, and it is the rule the current code is missing — area is precisely what makes the worktop win 510,499 votes to ~64,000.

Most of the machinery already exists and is tested: the gravity cone filter, the seeded RNG, `refine`, and the deterministic consensus polish. Only the inlier-removal loop and the selection rule are new.

The decisive argument is that Req 4.5 makes a **high fallback rate a defect, not a success**. The flood fill's known failure on curved vessels and its plausible failure on smoothed plate edges both route to the fallback — which is the 3.2× over-read this feature exists to remove. The cheap option risks satisfying every completion criterion while delivering little, and would leave the Req 3 guards doing primary work rather than acting as a backstop.

### Alternatives Considered

- **Promote the flood fill with a food-derived seed**: smallest change (~60 LOC), reuses code with existing tests, one tuning constant — Rejected: local continuity cannot separate flat from gradually curved, ARKit's smoothing collides with the 5 mm threshold, and both failures land on the fallback that Req 4.5 treats as a defect.
- **Multi-plane extraction without the component filter**: most of the benefit for ~120 LOC — Adopted as the first stage; the component filter is additive and follows once a fixture justifies it.
- **Keep area-based selection, correct it with a bias term**: no new region logic — Rejected: tuning a wrong criterion rather than replacing it, and no bias value makes a large table lose to a small plate in general.

### Consequences

**Positive:**
- Handles the curved-vessel case the flood fill structurally cannot, so fewer captures fall back to the over-read.
- Selection evidence, rejection test and persisted diagnostic are the same quantity, so what decides the fit is what gets recorded.
- Moving to native depth samples removes a ~56× replication that inflated every count-based signal, including the inlier counts that made the wrong fit look confident.

**Negative:**
- Three new tuning constants beyond the flood fill's one, none with field evidence yet.
- Sequential RANSAC multiplies fit passes; CPU at the shutter is the quantity to watch, and only the device step can measure it.
- More new code, and all of its tests are new rather than inherited.

---

## Decision 12: Fallback carries a multiplicative confidence penalty

**Date**: 2026-08-05
**Status**: accepted

### Context

Req 4.6 requires a fallback fit not to report higher confidence than a restricted fit of equal residual. Decision 5 accepted as a negative consequence that fallback captures "appear to have succeeded normally", and the developer-phase no-disclaimer rule explicitly carves out functional accuracy signals, so a confidence signal is permitted where copy would not be.

### Decision

`sigmaPlane = exp(−r/5) · iter_penalty · fallbackPenalty`, where `fallbackPenalty` is 1.0 for `.foodSupport` and a documented constant below 1 for `.edgeBand`.

### Rationale

It matches the existing shape — `sigmaPlane` already carries a multiplicative `iter_penalty` — so nothing new is introduced into the confidence model. Keeping it separate from the residual matters: the alternative of inflating the residual before the curve is applied would make the persisted `planeResidualMm` no longer the measured residual, corrupting exactly the diagnostics this feature adds.

The constant has no field evidence and is revisited once the fallback rate is measured across a corpus.

### Alternatives Considered

- **Inflate the residual before `exp(−r/5)`**: one mechanism instead of two — Rejected: it falsifies the recorded residual, which several diagnostics and the σ_plane audit trail depend on being the measurement.
- **A separate factor in the confidence product**: keeps the residual clean and makes the penalty visible in the persisted breakdown — Rejected as changing the shape of the confidence model for one flag; the reference is already persisted separately, so the breakdown is reconstructable.

### Consequences

**Positive:**
- A capture on the old reference is visibly less certain, at the point the number is used.
- Persisted residual stays the measured residual.

**Negative:**
- One more unevidenced constant.
- Confidence now mixes fit quality with reference provenance, so a fallback fit with an excellent residual reads worse than its geometry alone warrants — which is the intent, but it makes σ_plane less directly interpretable.

---

## Decision 13: Score candidates by largest connected inlier component, on a bounded sample set

**Date**: 2026-08-05
**Status**: accepted (refines Decision 11's mechanism; the choice of multi-plane extraction stands)

### Context

Decision 11 chose multi-plane extraction with contact-based selection, staging a connected-component adjacency filter second. Review of the resulting design found three linked problems.

Sequential RANSAC's documented failure mode is a plane **straddling two surfaces separated by a step**, because such a plane holds more inliers than either surface alone. A plate rim is exactly that step, so the algorithm's known weakness lands precisely on this feature's subject. The design's defence against it — a tighter residual bar — was verified in code to be inoperable: the residual is computed over `polishedInliers`, each within `inlierBandMm = 5` of the plane, so RMS is ≤ 5 mm by construction and no bar can fire.

Second, the candidate set was every non-food pixel in the frame, so floors, hobs and second plates competed for three candidate slots — the same scene-dependence Decision 9 rejected the next-plane-gap diagnostic for, re-entering at the extraction stage.

Third, `maxIterations = 256` was inherited unexamined. It was sized to find the *dominant* plane; for a minority plane at a 10 % inlier ratio it has a 23 % chance of ever drawing a clean triple, and 3 % at 5 %.

### Decision

Bound candidate samples to `dilate(foodMask, 2 × foodRadius)` before extraction. Score each candidate by the size of its **largest 8-connected inlier component** (CC-RANSAC) rather than by total inlier count. Use adaptive per-pass iteration stopping rather than a fixed 256. Drop `restrictedResidualMaxMm` entirely and detect straddling with ring MAD.

### Rationale

Component scoring addresses the straddle *inside* the loop by changing which plane wins, where the staged adjacency filter could only reject after the fact — and a post-hoc filter is nearly useless against a genuinely co-height surface, which barely moves the plane it contaminates. It also subsumes the adjacency filter, so Decision 11's fourth constant disappears rather than being deferred.

Bounding the sample set is five lines and fixes three things at once: clutter stops consuming candidate slots, the plate's inlier ratio rises out of the region where 256 iterations is a coin flip, and the point count drops enough to pay for the extra passes.

Ring MAD replaces the residual bar because it measures the actual failure — a ring resting on two surfaces is bimodal, and MAD is large exactly then. The residual could not measure it, and setting the bar to 8 mm would additionally have pushed matte-table captures onto the fallback, regressing `lidar-plane-fit-matte-table-confidence` (Decision 46 raised that bar to 20 mm for genuine single-surface depth noise).

### Alternatives Considered

- **Keep inlier-count scoring plus the staged adjacency filter**: fewer moving parts up front — Rejected: leaves the documented straddle failure unaddressed until the filter lands, and the filter can only reject, never correct.
- **Organized-point-cloud segmentation (PEAC / `OrganizedMultiPlaneSegmentation`)**: the canonical tool for this data shape, yields planes and adjacency in one pass, comfortably real-time at 256×192 — Rejected for MVP as a wholesale replacement of a fitter that is otherwise correct and tested; worth revisiting if CC-RANSAC proves insufficient on the corpus.
- **Gravity-projected height histogram**: gravity is known and the cone is 15°, so the support plane has effectively one unknown degree of freedom; mode-seeking on a 1-D histogram needs no RNG and no iteration budget — Rejected for now because taking the normal from the ring samples is well conditioned only while the ring is a full annulus, and it degrades to an arc when food meets the frame edge. Recorded as the simplest fallback design if the RANSAC path proves fragile.
- **PROSAC-style sampling near the ring**: minimal change targeting the iteration budget alone — Not needed once the sample set is bounded.

### Consequences

**Positive:**
- The straddling-plane failure is addressed by the scoring rule rather than by a guard that cannot fire.
- One fewer tuning constant than Decision 11 planned, and the iteration budget is derived rather than inherited.
- Bounding the sample set removes the frame-clutter dependence and funds the extra passes.

**Negative:**
- Connected-component labelling per candidate is new work in the inner loop.
- `2 × foodRadius` is another tuned quantity, though a geometric one rather than a threshold on a measurement.
- Adaptive stopping makes per-capture iteration count data-dependent, so latency varies with scene complexity — which Req 7.6's budget must be measured against, not asserted.

---

## Decision 14: Radial ring profile plus a support-visibility test for rimmed plates

**Date**: 2026-08-05
**Status**: accepted (closes the residual risk Decision 13 left open)

### Context

Food rests on a plate's well; the rim sits 10–28 mm above it. Review flagged that a ring drawn 8–25 mm outside the food boundary can land on the rim rather than the well, selecting a plane above the surface the food rests on and clipping food height — the inversion Decision 3's harm ordering assumes cannot happen.

Measured against ordinary dinnerware, the exposure is narrower than feared but sharper when it lands. The ring falls wholly on the rim only once food covers **78–86 % of the well area** — a heaped plate, not a normal serving. When it does, the under-read is −30 % to −72 % depending on rim depth and food height. Today's table reference over-reads by +26 mm; a rim reference under-reads by 12–28 mm. Comparable magnitude, opposite sign, and the under-read is the direction a human does not catch.

The case also splits in two, and the halves need different answers. When the well is *partly* visible the correct plane is in the candidate set and is simply not being preferred. When food fills the well the surface produces **no depth samples at all**, and no algorithm can fit a plane to a surface nothing observes.

### Decision

Resolve the ring into `ringBandCount` radial bands rather than reducing it to a single median. Treat the **inner band as authoritative** for selection, and use the outward profile as shape detection: flat means one surface, rising means a rim or bowl wall, falling means the ring has leaked past the plate edge onto the table.

Separately, reject to the fallback when the visible support region is too thin relative to the food region (`supportVisibilityMin`) — the observability test for the half that cannot be solved.

### Rationale

The support surface is by definition the one immediately adjacent to the food, so the innermost samples are the ones that carry the answer; averaging them with samples 25 mm out was discarding that ordering. Resolving radially costs nothing new — the same samples, bucketed by distance — and it *resolves* the partial-fill case rather than merely rejecting it, which a bimodality guard alone would have done.

The profile also subsumes work the previous design split across two measures: a ring leaking onto the table falls outward, which the band step detects directly, so MAD becomes corroboration rather than the primary detector.

For the unobservable half, falling back is the only honest answer. It routes the capture to the edge-band over-read — wrong, but wrong in the direction a person notices, which is the same asymmetry Decision 3 rests on. The visibility ratio is the `region area ÷ food-mask area` check Decision 9 kept as a secondary guard and the first design draft dropped; it returns here with a job it actually fits — an observability test rather than the scene-dependent selection score it was rejected as.

### Alternatives Considered

- **Keep the single ring median and accept the rimmed-plate risk**: no new mechanism — Rejected: a −30 % to −72 % under-read is worse than the defect being fixed for the affected captures, and it is silent.
- **Shrink `ringInnerMm` so the ring stays on the well**: directly targets the geometry — Rejected: the inner radius is already at the ~7 mm depth smear floor, below which samples blend food and support. It cannot shrink further, and it would not help once food fills the well.
- **Infer the well depth from the rim and the table**: the plate's rim height above the table is measurable — Rejected: well depth varies 5–30 mm across ordinary dinnerware and is not derivable from rim height, so this would substitute an assumed constant for an unobserved measurement.
- **Refuse the capture when support visibility fails**: never returns a number from an unverifiable reference — Rejected: breaks the Decision 5 invariant that nothing completing today may start failing.

### Consequences

**Positive:**
- The partial-fill rimmed plate — the larger half of the exposure — resolves to the correct surface rather than being rejected.
- One measure now distinguishes four scene types (flat, rim, bowl, leaked) where the previous design needed the median plus MAD and still conflated rim with well.
- The unobservable case is detected and routed to the error direction a human catches.

**Negative:**
- Two more constants (`bandStepMaxMm`, `supportVisibilityMin`), neither with field evidence.
- Radial banding divides the ring's samples among bands, so each band is noisier; `ringMinSamples` now has to hold per band, not just overall.
- A fully-filled rimmed plate with food mounded high can still pass the visibility test with a flat rim-borne ring and under-read by the rim height. Detectable in the persisted profile, not prevented.

---

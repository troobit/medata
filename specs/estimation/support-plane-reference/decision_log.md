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

Ring MAD replaces the residual bar because it measures the actual failure — a ring resting on two surfaces is bimodal, and MAD is large exactly then. The residual could not measure it, and setting the bar to 8 mm would additionally have pushed matte-table captures onto the fallback, regressing `lidar-plane-fit-matte-table-confidence` (pipeline Decision 46 raised that bar to 20 mm for genuine single-surface depth noise).

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

## Decision 15: The candidate bound is an annulus, and the sample reduction comes from the native depth grid

**Date**: 2026-08-05
**Status**: accepted (amends Decision 13's rationale; the algorithm it selected is unchanged)

### Context

Decision 13 justified bounding the candidate set with "today's candidate set is every non-food pixel in the frame, so floors, hobs, draining boards and a second plate all compete", and claimed `dilate(foodMask, 2 × foodRadius)` fixed three problems at once: clutter, inlier fraction, and a ~4× point-count drop.

Re-validation against the code found the premise false. `LiDARPlaneFitter.CandidateRegion` defaults to `.bandsAroundFoodRegion` (`LiDARPlaneFitter.swift:61`), which scans four bands around the food bbox, each as thick as the bbox dimension perpendicular to it (`:237-250`) — added deliberately by the `lidar-plane-fit-degenerate-on-clean-capture` bugfix. `.insideMask` has one caller, `FixtureRunner` (`:251`). The existing set is already bounded to the food's neighbourhood.

Worse, the proposed replacement is looser. For an `s × s` food bbox the bands cover ≈ `4 s²`; `dilate(foodMask, 2 × foodRadius)` spans ≈ `(2.9 s)² ≈ 8.3 s²`. The bound roughly doubled the candidate region while being described as restricting it.

### Decision

Bound the candidate set to an **annulus of `2 × ringOuterMm` around the food mask**, not `dilate(foodMask, 2 × foodRadius)`. Attribute the ~56× sample reduction to the native-depth-grid move (Req 2.4), which is a separate change. Attribute the iteration budget's sufficiency to sequential extraction removing the table in pass 1, and require the per-pass residue inlier ratio to be reported so the claim is measured rather than assumed.

### Rationale

The annulus is concentric with the food rather than square with its bbox, so it is tighter than today's bands for any food that does not fill its bbox, and it is the region the ring measure already reads — no new scene-dependence is introduced. This delivers what Decision 13 wanted; the dilation did not.

Separating the two claims matters beyond bookkeeping. The 56× is real (1920×1440 ÷ 256×192 = 56.25) but belongs to the grid change, and crediting it to bounding concealed that the bound was doing the opposite of what was claimed. The iteration budget needed the same correction: at the diagnosed capture's ~6 % plate fraction, `maxIterationsPerPass = 2048` gives only ~36 % probability of a clean triple, an order of magnitude short. The budget works, but because pass 2 draws from a residue with the table already removed — an argument Decision 13 never made.

### Alternatives Considered

- **Keep `dilate(foodMask, 2 × foodRadius)` and correct only the prose**: least churn - Rejected: the bound would then be knowingly looser than the code it replaces, and the inlier ratio would fall rather than rise, worsening the iteration budget the design depends on.
- **Drop bounding entirely and rely on the native grid alone**: the grid move supplies the whole measured saving - Rejected: the annulus still raises the plate's inlier fraction within each pass, and the ring geometry needs the annulus computed regardless, so it is free.
- **Keep the four-band scan and change only the grid**: smallest possible change - Rejected: the bands are square with the bbox and admit table corners that the annulus excludes, and a bbox-shaped region cannot supply the radial band profile Decision 14 requires.

### Consequences

**Positive:**
- The stated rationale now matches the code, so the next reader is not misled about what the existing fitter does.
- The annulus serves both candidate bounding and ring construction, removing a duplicate region computation.
- The per-pass residue ratio becomes a reported quantity, making the iteration budget falsifiable.

**Negative:**
- An annulus is more expensive to compute than four rectangles, on a path with a measured memory failure.
- The design now depends on sequential extraction working as argued; if pass 1 fails to remove the table, pass 2's budget is insufficient and there is no fallback within the extraction loop.
- `ringOuterMm` now sizes two things — the ring and the candidate bound — so changing it moves both.

### Impact

Design §"Bound the candidate set to an annulus"; tasks 5 and 6 (bounded sampling tests and implementation).

---

## Decision 16: Ring dispersion is measured per band, and Req 2.3's residual bar is superseded

**Date**: 2026-08-05
**Status**: accepted (supersedes the residual bar in Req 2.3; amends Decision 14); the inner-band MAD guard is superseded by Decision 19 — the per-band sample counts, the radial profile, and the Req 2.3 amendment stand

### Context

Two related defects surfaced together during re-validation.

Req 2.3 mandates "a residual bar tighter than the 20 mm gate of pipeline Req 4.5", justified by a straddling region fitting at ~13 mm RMS. That figure is a property of plain least squares over a fixed region. Under RANSAC the residual is computed only over `polishedInliers`, each within `inlierBandMm = 5` of the plane (`LiDARPlaneFitter.swift:25, 136-140`), so RMS is ≤ 5 mm by construction and the bar can never fire. The design correctly refuted this but left the requirement standing, so the two documents disagreed in writing.

Separately, the guard table applied `ring MAD > ringMadMaxMm` to the whole ring while `supportFraction` was explicitly inner-band. A ring spanning a well at 0 mm and a rim at +18 mm has whole-ring MAD ≈ 9 mm, above the 6 mm bar — so the partly-visible rimmed plate is rejected. That is precisely the candidate Decision 14 exists to rescue, and the design's own "rimmed plate, well partly visible" test case could not have passed.

### Decision

Compute MAD and sample counts **per radial band**, and read the **inner band** for the straddle guard. Amend Req 2.3 to require a dispersion bar on the ring's inner band and to explicitly forbid a plane-residual bar for that purpose.

### Rationale

The two failure modes are geometrically distinct and were being conflated by one number. Bimodality *across* bands is the rim or bowl signal, and the band-step guard already reads it. Bimodality *within* the inner band is the straddle signal — the ring sitting half on the plate and half on the table — and that is the only thing MAD should be asked to detect. Measuring it over the whole ring makes the rim signal masquerade as the straddle signal, which is why Decision 14's fix was being cancelled by a guard from the previous design revision.

Amending Req 2.3 rather than leaving the design to refute it keeps the requirement executable. A criterion that cannot fire is not a safeguard; it is a line of text that makes a reviewer believe a safeguard exists.

### Alternatives Considered

- **Keep the whole-ring MAD and raise `ringMadMaxMm` above the rim step**: one constant change - Rejected: a bar above ~18 mm no longer detects the plate/table straddle at 26 mm with any margin, so it would trade the rimmed-plate case for the case the feature exists to fix.
- **Drop MAD entirely and rely on the band-step guard**: the profile already distinguishes four scene types - Rejected: band step compares medians *between* bands and is blind to a straddle that contaminates every band equally, which is what a ring on a plate edge produces.
- **Leave Req 2.3 as written and note the conflict in the design**: no requirements churn - Rejected: `tasks.md` tasks 5 and 6 already cite Req 2.3 for CC scoring rather than for a residual bar, so the drift was propagating into the task list.

### Consequences

**Positive:**
- The partly-visible rimmed plate can now actually reach selection, making Decision 14 operative rather than nominal.
- Requirements and design agree in writing, and the amended Req 2.3 states a bar that can fire.
- Persisting per-band MAD makes a straddle distinguishable from a rim after the fact, not just at selection time.

**Negative:**
- Per-band MAD over ≥60 samples per band is noisier than a whole-ring MAD over the pooled set, so `ringMadMaxMm` is now measured against a noisier statistic.
- `RingStatistics` grows from one dispersion number to an array, and the persisted `planeRingMadMm` must document which band it carries.
- Req 2.3's amendment invalidates any reading of the requirements predating this entry.

### Impact

Requirements Req 2.3; design guard table, `RingStatistics`, §"Why there is no separate residual bar"; tasks 3 and 4 (ring statistics tests and implementation).

---

## Decision 17: The mixture calibration path keeps the flood-fill plate-region fit

**Date**: 2026-08-05
**Status**: accepted (amends Decision 13's parity audit)

### Context

The parity audit recorded `HarnessCore/CalibrationArtifact` as "metadata only — records the reference". It is not: `CalibrationArtifact.mixtureObservation` (`:157`) is a live caller of `FixtureRunner.fitPlateRegionPlane`, reached from `HarnessCLI/main.swift:397` and `:542`. Task 16 deletes that function.

The `FixtureRunner` migration does not transfer to it. Mixture fixtures carry neither `probs_hwc` nor `argmax_hw` (`docs/agent-notes/nutrition5k-ingestion.md`), and `mixtureObservation` feeds `TotalHullVolume.integrate`, which is plate-wide rather than per-class. `fitFoodSupportPlane` requires a `foodRegionMask` and there is no segmentation output at that site to derive one from. This is a property of the data, not a wiring omission.

Both call sites convert a throw into a skip (`planeFitSkipped`, `officialSkipped["plane_fit_failed"]`), so deleting the fitter and letting the site throw would empty the mixture corpus silently while the run still reported success.

### Decision

Retain `plateRegionMask` and `fitPlateRegionPlane` as the mixture path's fitter, scoped to that path. Retain `PlateRegionPlaneTests` with them. Require the skip counts at both call sites to be reported rather than merely collected.

### Rationale

The flood fill's frame-centre seed assumption — the one Req 2.2 rejects — holds on the N5k mixture corpus, which is a fixed overhead rig that centres the plate under the camera. Req 2.2 rejects it for handheld capture, where the user centres the food rather than the plate. Keeping the flood fill where its assumption is true is correct for that corpus rather than a concession to migration cost.

Reporting the skips matters independently of this decision. A calibration run that silently drops its entire corpus and reports success is a failure mode worth closing whatever fitter is in use.

### Alternatives Considered

- **Derive a food mask for mixture fixtures from a depth threshold above the plate plane**: would let the mixture path take the promoted fitter - Rejected: circular, since the plate plane is what is being fitted, and it would invent a mask the ingestion pipeline deliberately does not produce.
- **Re-ingest the mixture corpus with argmax maps so a mask exists**: removes the data limitation at source - Rejected: `model-production.md` records the full fixture bundle as ~16 GB for no new information, and Req 5.4 already handles a corpus spanning two references.
- **Delete `fitPlateRegionPlane` and let mixture fixtures skip**: smallest change, and β is `uncalibrated_unity` today so nothing breaks immediately - Rejected: it empties the mixture corpus while reporting success, and the emptiness would only surface whenever β_c calibration is next run.

### Consequences

**Positive:**
- The mixture β_c path keeps working, and its fitter's assumption is documented as valid for its corpus rather than inherited unexamined.
- Silent corpus loss at both call sites becomes a reported number.
- `PlateRegionPlaneTests` survives, keeping coverage on code that survives.

**Negative:**
- Two support-plane fitters remain in the tree, against Req 5.1's one-implementation intent. The mixture path is the stated exception and must not widen.
- The regenerated N5k corpus spans two references permanently rather than transitionally, so Req 5.4's within-reference rule is now a standing constraint.
- The flood fill's frame-centre assumption stays in the codebase and could be copied to a handheld path by a future reader who misses this entry.

### Impact

Design parity audit and §"The mixture calibration path keeps the flood fill"; tasks 16, 17 and 23.

---

## Decision 18: Ring support is evaluated per angular sector, not only in aggregate

**Date**: 2026-08-05
**Status**: accepted (closes the silent-failure case Decision 14's radial profile does not cover)

### Context

Two independent adversarial reviews of the design — one with full spec context, one given only the domain and the code — were each asked to find how the design could report a confidently wrong carb number in the field. Both converged on the same scene without knowledge of the other's reasoning.

Selection maximises the **inner-band ring support fraction**: the share of inner-band ring samples within ±`ringBandMm` of the candidate plane. That is a majority vote. The inner band sits 8–13.7 mm outside the food boundary, so whenever the food reaches within roughly that distance of the plate's edge, the band spills onto the surrounding table. Take a ring 65 % on the table: the table plane scores 0.65 against the plate plane's 0.35.

Every guard passes. `ringSupportMin = 0.6` passes at 0.65. The ambiguity margin passes, since 0.65 − 0.35 = 0.30 exceeds `ringSupportMarginMin = 0.15`. Inner-band MAD is ~0, because the majority of deviations are zero. The radial profile is **flat**, not falling — the "leaked onto the table" row of Decision 14's table describes a ring that is *partly* past the edge, and does not fire when the majority of even the inner band is on the table. `foodAboveFractionMax` passes, because food is above the table. Req 3.3's below-fallback guard passes, because the edge-band fit *is* the table.

The table plane is selected, recorded as `planeReference = .foodSupport` with `fallbackPenalty` of 1.0 and `planeRingMedianMm ≈ 0`, and the 26 mm offset is reinstated in full.

This is worse than the defect being fixed, in three ways. The diagnostic **certifies** the wrong answer: today's defect leaves a +18…+26 mm ring median in the record, which is what Req 6.2 rests on, whereas this failure writes the value the specification treats as proof of a correct fit. Confidence is full, so Req 4.6's signal never fires. And it contaminates calibration — Req 5.4 fits β_c within-reference on rows labelled `foodSupport`, so these rows fold the 26 mm offset into β_c for precisely the flat, wide, overhang-prone classes worst affected, defeating Decision 10 by way of a correctly-labelled wrong plane.

The trigger is not exotic. `1785901032716` — two slices of bread with the lower slice overhanging the plate onto the worktop, the weighed capture that motivates this feature — is an instance of the geometry.

### Decision

Evaluate ring support in **angular sectors** as well as in aggregate, and reject a candidate whose supporting samples are confined to a subset of sectors. Persist the count of sectors meeting the per-sector bar, so the failure is identifiable from the record. Derive the sector count, the per-sector bar and the failing-sector rejection threshold from the fixture corpus rather than asserting them (Req 3.7).

Preferring the **highest admissible candidate** is recorded as a viable second mechanism and explicitly **not ruled out**: it is deferred, to be built if the sector measure proves insufficient, not rejected.

### Rationale

The sector measure attacks the failure at its cause. An aggregate fraction is blind to *where* the support lies; the pathology is entirely one of spatial arrangement, since a ring 65 % on the table is 100 % table across roughly 235° and 0 % across the remainder. Sectors expose instantly what the aggregate conceals, and they discriminate the two cases that matter — a ring wholly on the support surface supports uniformly, while a ring that has crossed an edge supports in an arc.

It is also the smaller change. The ring samples already exist and already carry positions; sector membership is one `atan2` and a bucket index per sample, reusing the machinery `bandMedianMm` established for radial banding. No new sampling, no new pass, no new geometry — the same samples, bucketed by a second coordinate. That matters on a path already carrying a measured allocation failure and an unamortised connected-component cost.

Height ordering is held in reserve rather than discarded because it encodes a genuine physical constraint the sector measure does not: the surface the food rests on cannot lie below the surrounding surface. The two are complementary rather than competing — sectors detect a bad ring, height ordering chooses correctly when the ring is ambiguous — so building sectors first and adding height ordering only if measurement shows it is needed keeps the mechanism count down without foreclosing the option.

### Alternatives Considered

- **Prefer the highest admissible candidate**: order candidates by plane height rather than by ring support, since the support cannot be below the surrounding surface and the top end is already bounded by `foodAboveFractionMax` and the band-step guard - **Not rejected; deferred.** It is a larger change to the selection rule, it inverts rather than refines the existing score, and its interaction with the rimmed-plate case needs its own measurement — a rim is also "higher". Build it if the sector measure is shown insufficient.
- **Raise `ringSupportMin` above the majority-vote failure**: one constant change - Rejected: no aggregate threshold separates the cases. A ring 65 % on the table and a ring 65 % on a genuinely noisy support surface produce the same aggregate number, so raising the bar trades this failure for a matte-table fallback storm.
- **Shrink `ringOuterMm` so the ring cannot reach the plate edge**: directly targets the geometry - Rejected: the inner radius is already at the depth-smear floor and cannot shrink to compensate, and the failure occurs at the *inner* band, which is the closest samples available. There is no radius at which food reaching a plate's edge leaves clean support samples outside it.
- **Detect the plate edge and reject rings that cross it**: attacks the cause directly - Rejected as the primary mechanism: it requires a reliable depth-discontinuity detector at the ~4-pixel smear scale, which is new machinery with its own constants, where sectors reuse samples already collected. Retained as the fallback if sectors prove insufficient.

### Consequences

**Positive:**
- The failure mode both reviews independently identified as the design's most dangerous is detected rather than certified.
- The evidence is persisted, so a capture whose ring crossed the plate edge is identifiable from the record without re-running the estimate (Req 6.4).
- Reuses the existing ring samples, adding one angular bucket per sample and no new collection pass.
- Height ordering stays available as a second mechanism, so this decision does not foreclose the stronger fix.

**Negative:**
- Three more constants (sector count, per-sector bar, failing-sector threshold), all requiring corpus measurement before they can be set — and Req 3.7 now forbids asserting them, which lengthens the path to a working implementation.
- Sectoring divides the ring's samples again, on top of Decision 14's radial banding. `ringMinSamples` must now hold per band *and* the sector measure needs its own sufficiency rule, or both statistics degrade into noise on a small ring.
- Food that legitimately sits near a plate's edge will now fall back rather than being measured, so the correction's coverage narrows in exchange for not being silently wrong.
- The design carries a known-better alternative it has chosen not to build, which is a standing invitation to revisit.

### Impact

Requirements 3.6, 3.7, 6.4; design guard table, `RingStatistics`, and the residual-risk section; tasks 3, 4, 7, 8 and 26.

---

## Decision 19: The inner-band MAD guard is deleted — the sector measure is the straddle detector

**Date**: 2026-08-05
**Status**: accepted (supersedes the MAD guard of Decision 16; its per-band sample counts, radial profile, and Req 2.3 amendment stand)

### Context

Re-validation after Decision 18 left three measures reading the inner band: the aggregate support fraction, the inner-band MAD guard, and the new sector guard. Checking the MAD guard's arithmetic against the admissibility floor shows it occupies a firing window that does not exist.

For a two-surface mixture with fraction f of the inner band on the far surface, the in-band majority puts the median on the supported surface whenever f is away from 0.5, so MAD collapses to the depth-noise scale (~1–2 mm) — including at the 65/35 mixture Decision 18 documented. MAD exceeds the 6 mm bar only when f is within a few percent of 0.5, and any such candidate scores ≈ 0.5 aggregate support, failing `ringSupportMin = 0.6` before the MAD guard is consulted. The one straddler the aggregate bar misses — the 6.7° rim-ramp tilt — reads MAD ≈ 5.6 mm by the design's own figures and slips under the bar. The guard cannot fire on any admissible candidate: the same defect class as the residual bar Decision 16 itself removed, one revision later.

### Decision

Delete the inner-band MAD guard, the `ringMadMaxMm` constant, the `bandMadMm` statistic and the persisted `planeRingMadMm` field. The sector guard of Decision 18 is the straddle detector, and it is the dispersion bar Req 2.3 requires: it bounds the angular dispersion of in-band support on the inner band and rejects the straddling fit Req 2.3 names.

### Rationale

The sector guard dominates MAD across the whole mixture range: support confined to an arc fails it at any fraction beyond roughly two sectors' width (f ≳ 0.25 at 8 sectors and a 6-sector bar), where MAD fires only in the knife-edge neighbourhood of 50/50 — a neighbourhood already rejected by the aggregate bar. The tilted straddler that slips under both the MAD bar and (marginally) the aggregate bar concentrates its in-band samples in the arcs near its zero-crossings and fails sectors decisively. Carrying a third inner-band statistic that cannot fire adds a constant, a persisted field and a false sense of coverage on a path whose constant count is already a stated concern.

The deletion is analytic, not asserted: the firing-window arithmetic is shown above and in the design, so this is a derivation rather than a corpus claim. If corpus measurement under Req 3.7 surfaces a bimodal ring the sectors pass — which requires angularly interleaved surfaces no tabletop scene produces — the statistic can return with evidence attached.

### Alternatives Considered

- **Keep MAD as a persisted diagnostic without the guard**: preserves post-hoc analysis - Rejected: its diagnostic value has the same hole as the guard — it reads ≈ 0 on most straddles — so it would persist a number that looks meaningful and is not, which is this feature's founding defect in miniature.
- **Widen the MAD bar's window by scoring against a fixed zero rather than the median**: makes the far-surface mass visible at any fraction - Rejected: that statistic is the mean absolute ring height, which the ring median plus support fraction already carry between them; it adds no information the persisted fields lack.
- **Keep both guards and let the corpus decide**: no analysis risk - Rejected: the corpus cannot vindicate a guard whose firing region is covered twice over by other guards; it would only measure noise around zero firings, and the constant would survive by inertia.

### Consequences

**Positive:**
- One fewer guard, one fewer constant, one fewer persisted field on the path with a stated constant-count concern.
- The straddle rejection now degrades continuously with mixture fraction instead of depending on a knife-edge statistic.
- Req 2.3's dispersion bar is a mechanism that can actually fire.

**Negative:**
- An angularly interleaved bimodal ring — no known tabletop scene — would now pass the dispersion check and be caught only by the aggregate bar.
- `RingStatistics` and the persisted schema diverge from what Decision 16 published, and any reader of that entry must follow the supersession note.

### Impact

Design guard table, `RingStatistics`, `SupportRegion` constants, Data Models, §"Why there is no separate residual bar"; tasks 3, 4, 8, 11, 12; prerequisites dump instructions.

---

## Decision 20: The ring sample floor is derived from sector statistics, and empty sectors fail conservatively

**Date**: 2026-08-05
**Status**: accepted (closes the sufficiency gap Decision 18 flagged as an open negative consequence)

### Context

Decision 18 noted that sectoring divides the inner band's samples on top of Decision 14's radial banding, and that the sector measure "needs its own sufficiency rule, or both statistics degrade into noise on a small ring". The design carried no such rule, and `ringMinSamples = 60` had no derivation.

The arithmetic at realistic captures: at 350 mm range the depth grid resolves ~2 mm/px, each radial band is ~2.8 px wide, and a 35 mm-radius food's inner band holds ≈ 400 samples (~50 per sector); at 500 mm, ≈ 260 (~33 per sector). At the 60-sample floor, however, sectors average 7 samples: a 0.5 support bar at n = 7 has binomial σ ≈ 0.19, and a uniformly supported ring at true support 0.6 false-fails the guard roughly two captures in five. At 25 samples per sector, σ ≈ 0.10 and a supported sector (p ≈ 0.9) separates from a crossed one (p ≈ 0.3) by more than 4σ.

Separately, sectors can be empty for a reason unrelated to plane choice — the ring clipped by the frame edge — and the guard needed a stated behaviour for them.

### Decision

Set `ringMinSamples = ringSectorCount × 25 = 200`, holding per radial band as before. Sectors are equal arcs about the food-mask centroid. A sector with no samples counts as neither supporting nor failing, and `minSupportingSectors` stays an absolute count, so a heavily clipped ring cannot pass on a majority of its surviving sectors. Task 26 confirms the floor against the corpus fallback rate.

### Rationale

Deriving the floor from the sector statistic gives one constant two jobs and gives the previously asserted 60 a derivation at the same time. It needs no per-sector constant: the outer bands always hold at least as many samples as the inner band on a full annulus, so the single per-band floor covers all three bands and the sector split. The cost lands on food smaller than ~25 mm across at 350 mm (~50 mm at 500 mm), which falls back — the items the design's perimeter-smear bias measures worst anyway, and falling back is the error direction a human catches.

The empty-sector rule is conservative by construction: emptiness from clipping and non-support from edge-crossing are distinguishable (no samples against off-plane samples), and both push towards fallback rather than towards a silently accepted fit.

### Alternatives Considered

- **A separate `sectorMinSamples` constant**: precise about what it gates - Rejected: adds a constant on a path whose constant count is a stated concern, when the existing floor can carry the derivation.
- **Evaluate the sector guard only when sectors are well populated, keep `ringMinSamples = 60`**: preserves coverage of small food - Rejected: it reopens Decision 18's silent failure exactly for small food near a plate's edge, trading a certified wrong answer for coverage.
- **Scale the bar to a fraction of populated sectors**: tolerant of clipping - Rejected: a ring reduced to a narrow arc could then pass on that arc alone, which is the geometry of the edge-crossing failure.

### Consequences

**Positive:**
- The sector guard is measurement rather than noise wherever it is allowed to run, with the binomial arithmetic recorded.
- `ringMinSamples` acquires a derivation; the constant count does not grow.
- Frame-clipped rings resolve to fallback instead of being judged on a fragment.

**Negative:**
- Food under ~25 mm across at 350 mm (~50 mm at 500 mm) now always falls back to the edge-band over-read.
- The floor tightens 60 → 200, so the fallback rate rises for small-and-far captures and Req 4.5's threshold must be read against that.

### Impact

Design §"Sectoring is statistically viable", `SupportRegion` constants, `RingStatistics` comments; tasks 3, 4, 26.

---

## Decision 21: The band-step guard reads the inner→mid step only

**Date**: 2026-08-05
**Status**: accepted (makes Decisions 14 and 16 mutually consistent; amends the guard table)

### Context

The guard table rejected any candidate whose radial profile rises outward beyond `bandStepMaxMm`. But the well plane of a partly-visible rimmed plate — inner band ≈ 0 on the well, outer ≈ +18 on the rim — *is* a rising profile, so the guard as written rejected the exact candidate Decision 14 exists to rescue and Decision 16's spanning-ring example says must be selectable. That is the same self-contradiction Decision 16 removed from whole-ring MAD, sitting one row away in the neighbouring guard.

### Decision

The band-step guard compares the inner and mid band medians only. A rise between mid and outer is shape detection — a raised vessel edge beginning ≥ ~14 mm out (Req 3.8) — and leaves the inner band authoritative, so the well plane wins. A rise already present at inner→mid means the surface the ring itself rests on is not flat — a bowl wall, or a rim hard against the food — and rejects to fallback.

### Rationale

The discriminator between rescue and rejection is where the rise begins, not whether it exists. If the surface immediately adjacent to the food is flat, that surface is the support by Req 3.8's own definition, and geometry further out is the vessel's shape, not evidence against the fit. If the rise reaches into the inner band's neighbour, the "support" the ring measured is partly wall or rim, and no band of it is trustworthy — fallback is the conservative direction, and it is the direction Decision 3's harm ordering prefers. Decision 16's rescue of the spanning ring is only coherent under this reading; the alternative reading makes Decisions 14 and 16 dead letters for every intermediate fill level.

### Alternatives Considered

- **Reject on any outward rise**: simplest reading of the table - Rejected: rejects the partly-visible well whenever the rim enters the ring, cancelling Decision 14 for intermediate fills exactly as whole-ring MAD did before Decision 16.
- **Reject on the total inner→outer rise instead**: one comparison - Rejected: identical failure, since the well-to-rim step dominates the total wherever it falls in the ring.
- **Drop the step guard and rely on inner-band support alone**: fewest guards - Rejected: a bowl wall's base can support the inner band at marginal fractions while the profile climbs; the step guard is the only reader of that shape, and bowls are the case Decision 3 routes to fallback.

### Consequences

**Positive:**
- The partly-visible rimmed plate is selectable at every fill level where the rim stays out of the mid band, which is what Decisions 14 and 16 promised.
- Bowls and hard-adjacent rims still reject, in the conservative direction.

**Negative:**
- A rim step falling inside the mid band produces fallback rather than a well fit, narrowing the rescue to rims ≥ ~14 mm from the food boundary.
- The guard now reads two of three bands, so the outer band influences selection only through shape diagnostics, and a reader of the persisted profile must know that.

### Impact

Design guard table and §"The rimmed-plate case"; tasks 7 and 8; Req 3.8 traceability.

---

## Decision 22: Three guards replaced because they could not do what their requirement says

**Date**: 2026-08-05
**Status**: accepted (amends Decisions 3, 13 and 14; supersedes `foodAboveFractionMax`)

### Context

A third adversarial review, which read Gallo et al. 2011 directly rather than citing it, found three guards that were stated in the requirements and mis-implemented in the design. None is a matter of an unmeasured constant; each is a guard doing something other than what its criterion asks.

**`foodAboveFractionMax = 0.05` rejects this feature's own primary acceptance capture**, provable from the design's own numbers with no new measurement. Decision 4 brackets `1785901032716` at 236–262 cm³, an ~11 % spread attributed entirely to the overhanging bread slice. Overhang sits *below* the plate plane, so at roughly uniform thickness ~11 % of food samples count against a 5 % bar. The capture falls back, returns 714.84 cm³ and fails Req 7.2 — while contradicting Reqs 1.3 and 3.4 and the design's own "guards must not fire on overhang" test case. The cause is one constant serving two opposed purposes: Decision 3 uses this test to route bowls to fallback, where it must fire, and Req 3.4 uses it to tolerate overhang, where it must not.

**Req 3.3's guard cannot fire.** "Plane below the lowest admissible candidate" compares a set's minimum against itself, and is circular besides, since admissibility is defined partly by this test. Req 3.3 names the edge-band plane; the substitution existed to keep that fit lazy.

**Req 3.2's signed guard was never implemented.** The design persisted `medianMm` but its guard table carried no `|median|` test, only the unsigned support fraction — which cannot separate a plane above the ring from one below it, though Req 3.1 makes the sign carry the meaning.

### Decision

Replace `foodAboveFractionMax` with an **upper-envelope test** in millimetres: reject when the food's `foodEnvelopePercentile` signed height above the plane falls below `foodEnvelopeMinMm`. Replace Req 3.3's comparator with the **annulus median height** and `escapeBandMm`. Restore the **signed** `|median|` admission guard for Req 3.2.

### Rationale

The envelope test separates the three cases one bar could not. Bread's p90 sits ~8 mm above the plate plane and is accepted, with the overhanging slice's samples falling into the lower decile where they belong rather than voting against the fit. A bowl's food lies entirely below the rim plane, so p90 is negative and it is rejected. A plane resting on the food top gives p90 ≈ 0 and is rejected. It is also denominated in millimetres, which is what Req 3.4 asks for; the fraction had quietly changed the physical quantity between the two documents.

The annulus median is already computed for the ring, so the Req 3.3 replacement costs nothing and keeps the edge-band fit lazy. A plane that escaped through a depth dropout lands far below the surrounding surface, which is exactly what the median detects.

Restoring the signed median costs one comparison against a value already persisted, and it is the only guard that reads the sign — the support fraction is unsigned by construction, so without it a plane above the ring and a plane below it are indistinguishable to the admissibility filter.

### Alternatives Considered

- **Raise `foodAboveFractionMax` above 11 % so the bread capture passes**: one constant change - Rejected: it would have to sit above the overhang fraction of the worst acceptable capture and below the food fraction of a bowl, and Decision 3 needs it low for exactly the case Req 3.4 needs it high. The conflict is structural, not a matter of tuning.
- **Exclude overhanging samples from the fraction before applying the bar**: keeps the existing test - Rejected: identifying which samples overhang requires knowing the support's extent, which is what is being fitted. Circular.
- **Compute the edge-band fit eagerly to give Req 3.3 the comparator it names**: implements the requirement literally - Rejected: it restores the full colour-grid scan to every success path, which is the cost this design removes, for a guard the annulus median serves at no cost.
- **Amend Req 3.3 away entirely**: the dropout case may be covered by the residual and extent guards - Rejected: neither bounds absolute plane position, and a dropout-escaped plane can be well-conditioned and low-residual over the samples it did find.

### Consequences

**Positive:**
- Req 7.2 becomes satisfiable; the feature's own weighed acceptance capture is no longer rejected by a guard.
- Bowl detection (Decision 3) and overhang tolerance (Req 3.4) stop fighting over one constant and are separated onto quantities that suit each.
- Req 3.4's stated physical quantity — millimetres — is honoured rather than silently swapped for a count fraction.
- Two guards that could never fire are replaced by two that can, so the admissibility filter is no longer partly decorative.

**Negative:**
- A percentile over food samples is a sort or a selection pass per candidate, where the fraction was a count — more work on a path already carrying an unamortised connected-component cost.
- `foodEnvelopeMinMm` and `escapeBandMm` are new owed constants; the sector trio already added three, so the count keeps rising despite Decision 20 folding one away.
- The envelope test assumes the food mask is trustworthy at its lower decile, and Req 3.5 already records that mask error changes which reference is selected.

### Impact

Design guard table, constants block and the new "Three guards that did not do what their requirement says" section; tasks 3, 4, 7 and 8; prerequisites (the overhang query is now answered and its conclusion recorded here).

---

## Decision 23: The new candidate-plane count is named apart from the pre-existing point count

**Date**: 2026-08-05
**Status**: accepted

### Context

The design's Data Models table adds `planeCandidateCount: Int?` to `EstimationAttemptRecord`, meaning "candidates extracted" — the number of candidate PLANES the sequential CC-RANSAC passes produced. `EstimationAttemptRecord` already carries a field of exactly that name (`PipelineDiagnostics.swift`), populated from `SupportPlaneFitStats.candidatePointCount` and meaning the number of candidate POINTS the fit sampled. The collision was not visible when the table was written and surfaced while implementing task 12.

The two quantities differ by three orders of magnitude on a real capture — a few thousand annulus samples against at most `maxCandidatePlanes = 3` planes. Reusing the name would silently redefine a field that pre-feature rows already carry, which is the failure Req 6.3 exists to prevent.

### Decision

Keep `planeCandidateCount` with its existing meaning (candidate points, units set by `planeReference`) and add the plane count as a separate optional field, `planeCandidatePlaneCount`.

### Rationale

Req 6.3 requires pre-feature rows to stay distinguishable from post-feature ones. A field whose meaning changes under a fixed name defeats that at the point it matters most: a stored row cannot say which definition it was written under, and the in-app browser and the accuracy report would silently mix a point count with a plane count across the schema boundary. A new name leaves every stored row exactly as recorded (Decision 6) and costs one extra optional.

### Alternatives Considered

- **Redefine `planeCandidateCount` as the plane count**: matches the design table verbatim - Rejected: pre-feature rows carry point counts under that key, so the field would mean two different things with no way to tell which, breaking Req 6.3 and requiring the migration Decision 6 forbids.
- **Rename the existing field to `planePointCount` and take the freed name**: the clearest end state - Rejected: it is the same break in the other direction; every already-persisted row would decode the old key into nothing, and the field is a live diagnostic for three prior plane-fit bugfixes.
- **Drop the plane count and infer it from the reference**: `.foodSupport` implies at least one candidate - Rejected: the count is the evidence that sequential extraction actually surfaced more than the table, which is the mechanism Decision 15's bound rests on; a boolean does not carry it.

### Consequences

**Positive:**
- Stored meals are untouched and every row's fields keep one meaning for the life of the schema.
- The two counts stay separately queryable, so a fallback-rate investigation can read sample starvation and candidate starvation apart.

**Negative:**
- The record's field name no longer matches the design's Data Models table, so the table is a stale reference until amended.
- `planeCandidateCount` keeps a name that reads like a plane count and is not one; the units also depend on `planeReference`, so it now carries two footnotes.

### Impact

`EstimationAttemptRecord`, `PipelineDiagnostics.recordSupportPlane`, and the design's Data Models table. Task 19's fallback-rate reporting reads `planeReference`, not either count.

---

## Decision 24: `fitFoodSupportPlane` returns a struct carrying the two point counts

**Date**: 2026-08-05
**Status**: accepted

### Context

The design declares `fitFoodSupportPlane` as returning `(plane, ring, candidateCount)?` and, separately, fixes the stats semantics of a `.foodSupport` row: `candidatePointCount` and `inlierCount` mean native depth samples there, against colour-grid points on an `.edgeBand` row. Task 10 requires the fitter to populate those two counters, and nothing outside `fitFoodSupportPlane` ever sees the annulus sample set or the winning inlier component — the declared tuple cannot supply them.

### Decision

Return a `FoodSupportFit` struct whose first three members keep the declared names and meanings, extended with `annulusSampleCount` and `inlierCount`.

### Rationale

The counts have to cross the boundary somehow, and every alternative either re-derives them (repeating the prepare/ring pass, the expensive part of the fit) or leaves the `.foodSupport` row's stats at their zero defaults, which contradicts the design's own stats semantics and leaves the snaq-parity diagnostics blank on the new primary path. A struct also names the members at the call site, where a five-element tuple would not.

### Alternatives Considered

- **Keep the tuple and recompute the counts in the fitter**: no signature change - Rejected: `prepare` plus `ringSamples` is the dominant non-RANSAC cost, and the recomputed inlier component would be a second labelling of the winner rather than the one that was actually selected.
- **Leave `candidatePointCount` / `inlierCount` at zero on a `.foodSupport` row**: smallest change - Rejected: it discards the counters three prior plane-fit bugfixes were diagnosed with, exactly when the fit path changed underneath them.
- **Return the counts through `RingStatistics`**: it already crosses the boundary - Rejected: they are candidate-extraction quantities, not ring measurements, and `RingStatistics` is computed per candidate including rejected ones.

### Consequences

**Positive:**
- The `.foodSupport` row's stats carry the units the design specifies, so the fallback rate and the point counts can be read from the same record.
- Named members make the ~56x unit difference legible at the call site rather than positional.

**Negative:**
- The design's Components signature is stale until amended.
- Two more members to keep in step with the fit as the selection rules change.

### Impact

`SupportRegion.fitFoodSupportPlane`, `LiDARSupportPlaneFitter`, the `SupportRegionScenes` test helper, and the design's Components and Interfaces block.

---

## Decision 25: `SupportPlaneReference` gains a `plateRegion` case for the mixture path

**Date**: 2026-08-05
**Status**: accepted

### Context

The design's Components block declares `SupportPlaneReference` with two cases, `foodSupport` and `edgeBand`. Its "mixture calibration path keeps the flood fill" section then states that mixture artefacts "record the plate-region reference" while single-dominant artefacts record `foodSupport`, and that Req 5.4 keeps β_c fitted within a reference. Those two statements contradict each other: with a two-case enum there is no value a mixture artefact can record, so the reference it was fitted under is either absent — which Req 5.3 says must block application — or misrecorded as one of the two the device produces.

Decision 17 made this permanent rather than transitional: mixture fixtures carry neither `probs_hwc` nor `argmax_hw`, so `fitPlateRegionPlane` survives for that corpus indefinitely and the calibration corpus spans two references by construction.

### Decision

Add a third case, `plateRegion`, to `SupportPlaneReference`. It is never produced on device or by the single-view replay; it exists so a calibration artefact can state which basis each β was fitted on.

### Rationale

Req 5.4 is only enforceable if every β can name its reference. A third case is the minimum that makes the partition total, and it keeps the partition in one type rather than splitting it across an enum plus a "some other basis" convention that each consumer would re-invent. The device path is unaffected because nothing on it can produce the value: `fitFromDepth` returns `foodSupport` or `edgeBand` and no other writer exists.

### Alternatives Considered

- **Leave the mixture reference absent**: no type change - Rejected: Req 5.3 makes absent block application, so every mixture β would be permanently unbakeable, which is a harsher outcome than the Req 5.4 partition asks for and hides the distinction rather than recording it.
- **Record the mixture reference as `edgeBand`**: reuses an existing case for "not the food-support plane" - Rejected: the flood-filled plate region is not the edge band; conflating them makes the fallback rate of Req 4.4 unreadable, since the same value would mean both "the restricted fit was rejected" and "this plate came from the mixture corpus".
- **A separate `CalibrationBasis` enum in HarnessCore**: keeps the shipped enum at two cases - Rejected: two enums over the same domain must be kept in step by hand, and the artefact would then carry a value that no runtime type can be compared against.

### Consequences

**Positive:**
- Req 5.4's within-reference rule becomes checkable in code rather than by convention.
- The fallback rate stays a clean two-way split on the depth-derived subset, because `plateRegion` rows are counted separately.

**Negative:**
- A case the device can never produce sits in a shipped enum, so every exhaustive switch must handle a branch that cannot occur there.
- The design's Components block is stale until amended.

### Impact

`SupportPlaneReference`, `CalibrationArtifact`, `CalibrateRun.applyReferenceGate`, and the design's Components and Interfaces block.

---

## Decision 26: The calibration reference guard blocks per artefact and skips per class

**Date**: 2026-08-05
**Status**: accepted

### Context

Req 5.3 requires β_c to be applied only when the calibration artefact records a support-plane reference matching the one in use, and says an artefact recording none must block. Req 5.4 requires β_c to be fitted on the subset sharing the reference it will be applied under. Decision 17 makes a mixed-reference artefact the permanent expected shape, not a transitional one — so a guard that aborted on any mismatch would reject every artefact the harness will ever produce, while a guard that only warned would apply `plateRegion` β to `foodSupport` volumes and reintroduce the ~3× error through the calibration path.

### Decision

Enforce at two granularities in `tools/food_db/generate.py`: an absent or mismatched **artefact-level** `support_plane_reference` aborts the bake before anything is written; a **class entry** whose own reference differs from the one in use is not applied, is left at its uncalibrated default, and is reported on stderr and in a `calibration_reference_skipped_classes` meta row. On the fitting side, `CalibrateRun.applyReferenceGate` admits only inputs matching the reference β will be applied under, and the excluded fixture IDs land in the run summary.

### Rationale

The two granularities answer two different questions. The artefact-level value says what basis this calibration run was conducted on; a pre-feature artefact has no answer, and that is the case Req 5.3 names explicitly. The per-class value says what basis one β was fitted on, and a mismatch there is ordinary — it identifies a mixture-corpus class in an artefact whose pool is single-dominant. Aborting on the ordinary case would make the bake unusable; silently applying it would make the guard decorative.

Recording the skipped classes rather than dropping them quietly matters for the same reason the fallback rate does: an artefact where most classes are skipped is measuring corpus coverage, not calibrating, and that must be visible in the output rather than inferable from a diff of β values.

### Alternatives Considered

- **Abort on any per-class mismatch**: strictest reading of "nothing may mix them" - Rejected: a mixed artefact is the permanent expected shape under Decision 17, so this rejects every future artefact and forces the guard to be disabled rather than obeyed.
- **Warn on mismatch and apply anyway**: preserves current β coverage - Rejected: it is the defect this feature exists to remove, applied one level up — a β fitted above the flood-filled plate region against volumes measured above the food-support plane.
- **Filter mismatched classes in the Swift writer instead**: the artefact would carry only applicable β - Rejected: the artefact is the audit record of a calibration run, and dropping the mixture β from it destroys the evidence that the mixture corpus was fitted at all. It also moves the guard away from the point of application, where Req 5.3 places it.

### Consequences

**Positive:**
- Pre-feature artefacts, the ones calibrated on the old basis, cannot bake at all.
- A mixed-reference artefact bakes exactly the subset that is valid, and says which classes it left out.
- The fitting side and the application side enforce the same rule, so a mismatch cannot be introduced between them.

**Negative:**
- Mixture-provenance β never reach the shipped database while the runtime integrates above `foodSupport`, so classes calibrated only on the mixture corpus stay at unity. Nothing breaks today because every β is `uncalibrated_unity` (Decision 10), but this bounds what the N5k mixture corpus can contribute later.
- Two enforcement points in two languages that must agree on one string constant.

### Impact

`tools/food_db/generate.py`, `CalibrationArtifact`, `CalibrateRun.applyReferenceGate`, `HarnessCLI/main.swift`, and the design's Data Models section.

---

## Decision 27: The voxel-carve exposure is a grid translation, and the excluded-voxel count does not change

**Date**: 2026-08-05
**Status**: accepted

### Context

Req 1.6 requires the voxel carve's use of the support plane as a lower carving bound to be evaluated against the corrected plane, and any change in excluded voxels to be stated. The design's pattern-parity audit had already committed to an answer in advance: `VoxelCarveEstimator` drops a voxel outright when `signedDistanceToPlane(centre) < 0`, a hard exclusion where the height field only clamps with `max(0, ·)`, so raising the plane 26.1 mm was expected to delete a slab of voxels — and, because overhanging food (Decision 4) sits inside that slab, to compound with the ~11 % under-measurement Decision 4 already accepts.

That prediction was never measured. Task 24 measures it.

### Decision

State the measured result: correcting the support plane changes the excluded-voxel count by **zero**. The exposure is a translation of the voxel grid, not a deletion of voxels from it, and it does not compound with Decision 4. The measurement is pinned as `VoxelCarvePlaneExclusionTests` rather than recorded only in prose.

### Rationale

The prediction assumed a grid fixed in space with the plane sliding through it. The grid is not fixed. `VoxelGridSizer.size` anchors `originCamera1` **on** the support plane — the food-mask centroid back-projected onto it — and `VoxelGrid.voxelCentre` offsets each voxel along `axisZ` by `dz = (iz + 0.5) · edgeMm`, which is strictly one-signed. Raising the plane translates the whole grid with it, so every voxel keeps the signed distance it had and the exclusion decides identically before and after.

What does change is where the grid sits: the ~26 mm between the table and the plate top used to lie inside it and now lies outside it. Food overhanging below the plate leaves the grid rather than failing the plane test. That is the same under-measurement Decision 4 brackets at ~11 %, reached by a different mechanism — so it is the same 26 mm counted once, and there is nothing to compound.

Pinning the measurement as a test rather than a number in the design matters because the conclusion is contingent on two implementation details a future change could quietly reverse: the origin being on the plane, and `dz` being one-signed. A prose statement would go stale silently; `testVoxelHeightOffsetsAreOneSigned` fails loudly.

### Alternatives Considered

- **State the predicted slab deletion without measuring** - Carry the parity-audit row's figure into the requirements as the Req 1.6 answer - Rejected because it is wrong, and wrong in the direction that overstates this feature's risk: it would have booked a compounding error against Decision 4 that does not exist, and might have bought an unnecessary mitigation.
- **Change `VoxelCarveEstimator` to clamp rather than exclude** - Match the height field's `max(0, ·)` so the two consumers treat the plane alike - Rejected as out of scope. The exclusion is not what makes the two-view carve wrong (see below), the two-view carve's accuracy is an explicit Non-Goal, and changing a carving bound to fix a defect that is not this feature's would move the number without evidence.
- **Fix the `gravityCamera` sign disagreement found while measuring** - Resolve whether the parameter means world-up or gravity-down, and make callers agree - Rejected here and referred to `bugfixes/two-view-carve-no-volume`. The Req 1.6 answer is zero under **both** conventions, so this feature does not depend on the resolution, and folding an unrelated defect into it would make the accuracy change unattributable.

### Consequences

**Positive:**

- Req 1.6 is answered with a measurement rather than an assumption, and the assumption turned out to be wrong.
- No compounding with Decision 4, so the accepted overhang bracket stays ~11 % rather than needing to widen.
- The measurement surfaced a real and more serious defect: under the convention `Pipeline` actually passes (`nadir.gravity`, world-up), `axisZ = −gravity` points down, the grid extends below the plane, and **every** voxel is excluded — 23,040 of 23,040 in the measured case. The two-view carve recovers no volume at all on a LiDAR device whose depth-derived plane reaches it, which is consistent with the ~10× under-read measured on 2026-08-05.

**Negative:**

- That defect is now known and left unfixed in this feature, which is a deliberate scope choice but means the two-view path stays broken while this spec closes.
- The zero-change result rests on two implementation details of `VoxelGridSizer`/`VoxelGrid` rather than on a stated contract; the pinning test is the mitigation, not a guarantee.
- The design's parity-audit row had to be superseded rather than merely updated, since a reader who had already taken the compounding claim as given needs to see it withdrawn.

### Impact

`specs/estimation/support-plane-reference/design.md` (parity audit row and the new "Voxel-carve exposure" section), `MedataCore/Tests/VolumeTests/VoxelCarvePlaneExclusionTests.swift`. No production code changes. `bugfixes/two-view-carve-no-volume` gains a concrete mechanism and a measured figure.

---

## Decision 28: Three acceptance figures do not reproduce and are superseded by the committed slices

**Date**: 2026-08-05
**Status**: accepted

### Context

Reqs 6.2, 7.1 and 7.2 each name a number taken from the original diagnosis of the flat-food over-read: a pre-feature contact-ring measure of +18…+26 mm on capture `1785135663727`, a corrected volume of 235.96 cm³ on the same capture, and ~200 cm³ on the weighed capture `1785901032716`. All three were recorded by a throwaway probe (`DiagProbe/main.swift`) against the full 195 MB bundles, on a machine holding the device. Nothing in the repository could execute them, which is why task 22 commits depth-only slices of both captures.

With the slices in place the figures became checkable for the first time. Two of the three do not reproduce, and the third cannot be reached by any candidate plane.

### Decision

Supersede the three figures with the measurements the committed slices produce, and re-express the criteria they support in terms that the data sustains:

| Criterion | Stated | Measured | Disposition |
|---|---|---|---|
| Req 6.2 pre-feature ring measure | +18…+26 mm | **+4.2 mm** | Range superseded; the *sign and separation* are asserted instead |
| Req 6.2 corrected ring measure | ≈ 0 | **−0.93 mm** | Holds |
| Req 7.1 pre-feature volume | 682.96 cm³ | **714.8 cm³** (+4.7 %) | Holds, inside Req 7.1's own 5 % band |
| Req 7.1 corrected volume | 235.96 cm³ | **306.8 cm³** (+30 %) | Superseded; a >50 % reduction is asserted instead |
| Req 7.2 pre-feature volume | 714.84 cm³ | **735.7 cm³** (+2.9 %) | Holds |
| Req 7.2 corrected volume | ~200 cm³ ± 20 % | **646.7 cm³** best candidate | Unreachable; recorded as mask-bound, not plane-bound |

`SupportPlaneRegressionSliceTests` asserts the surviving claims. Reqs 6.2, 7.1 and 7.2 keep their stated figures in the requirements document with the measured ones recorded beside them, so the disagreement stays visible rather than being edited away.

### Rationale

The two pre-feature volumes reproduce within 5 % and 3 %. That agreement is what makes the rest of the table trustworthy: it establishes that the slice is faithful to the bundle and that integrating on the native depth grid agrees with the shipped colour-grid height field. A disagreement of 30 % on the corrected volume, against that background, is a disagreement about *which plane the diagnosis fitted*, not about the data — and volume on this capture moves ~70 cm³ per 3 mm of plane height, so a probe fitting the plate 3 mm differently accounts for the whole gap. The probe is gone (task 23), so the 235.96 figure is no longer reconstructible and cannot be treated as ground truth.

The Req 7.2 case is different in kind and more useful. No candidate plane yields ~200 cm³ because the constraint is not the plane: the food mask covers ~298 cm² of depth samples, where two slices of bread are ~200 cm², and 200 cm³ over 298 cm² implies a mean food height of 6.7 mm against the ~11 mm the depth map shows. That is a segmentation error, which Req 7.2 half-anticipated by pinning the class as a precondition. Recording it as mask-bound keeps this feature from being graded on a defect it does not control — and, equally, stops a future plane change from being tuned to hit 200 cm³ by compensating for a bad mask.

Asserting reductions and separations rather than absolute figures is the honest form for a criterion whose reference implementation has been deleted. Req 7.1 already describes itself as "a parity check against a known implementation, not an accuracy claim"; with the known implementation gone, what remains checkable is the claim the feature actually makes — that correcting the reference removes most of the over-read.

### Alternatives Considered

- **Re-state the criteria at the measured values** - Replace +18…+26 mm with +4.2 mm and 235.96 cm³ with 306.8 cm³, and assert those - Rejected because it is circular: the measurement would become its own acceptance criterion, and any error in the slice or the integration would be baked in as the target. Asserting a *reduction* is falsifiable in a way that asserting the number just measured is not.
- **Keep the stated figures and let the tests fail** - Leave Reqs 6.2/7.1 asserting +18…+26 mm and 235.96 cm³ until someone reconciles them - Rejected because a permanently red suite stops being read, and the reconciliation cannot happen: the probe that produced the figures no longer exists and the captures have no weighed truth to appeal to.
- **Rebuild `DiagProbe` and reconcile against it** - Restore the deleted probe, re-run it, and find the 3 mm - Rejected as a poor trade. It would reinstate code task 23 deletes for good reasons, to reconcile a figure that Req 7.1 itself says is not an accuracy claim, on a capture with no weighed truth. Task 27's weighed on-device capture is the evidence that would actually settle it.
- **Widen Req 7.2's band until 646.7 cm³ fits** - Treat the gap as tolerance rather than as a mask defect - Rejected outright. It would hide a segmentation error inside a support-plane criterion and make the feature look accurate by loosening the thing measuring it.

### Consequences

**Positive:**

- Reqs 6.2, 7.1 and 7.2 are executable by anyone with the repository for the first time, which is what Req 6.2's "falsifiable rather than merely recorded" asks for.
- The surviving assertions are constant-free — each measures a named plane rather than the selected one — so they do not move when task 26 sets the `[owed]` thresholds.
- The Req 7.2 finding attributes a real defect to segmentation rather than leaving it to be absorbed into plane tuning.
- The corrected ring measure of −0.93 mm is direct evidence that the geometry works on real device data, independent of whether the guards currently admit it.

**Negative:**

- Three figures the requirements state are now known to be wrong, and the requirements keep stating them; a reader must reach this decision to learn that.
- The corrected-volume criterion is weaker than it was — "less than half" instead of a 5 % band — so a fit that removed 55 % rather than 57 % of the over-read would pass. Task 27's weighed capture is what restores a hard bound.
- Both slices currently fall back, so the criteria exercise candidate planes the selection does not yet choose. That gap closes only when task 26 measures the constants.

### Impact

`tools/fixture_slice.py`, `MedataCore/Tests/SupportPlaneTests/{DepthSlice.swift,SupportPlaneRegressionSliceTests.swift,Fixtures/}`, `Package.swift`, and the Reqs 6.2/7.1/7.2 notes in `requirements.md`. Task 26 gains its first real corpus measurements; task 27 gains a specific figure to check on device.

---

## Decision 29: The corpus measurement pass settles four constants and cannot settle the rest

**Date**: 2026-08-05
**Status**: accepted

### Context

Task 26 commits to determining the constants the design deliberately left unstated — every value marked `[owed]` in `SupportRegion`, plus Req 4.5's fallback-rate threshold, Req 5.1's device/replay tolerance and `fallbackPenalty` — by measurement against the fixture corpus rather than by assertion. Req 3.7 makes this binding for the sector trio in particular: the sector count, the per-sector support bar and the number of failing sectors that constitutes a rejection MUST be derived from measurement, and the derivation recorded.

Two things narrowed the available corpus after the task was written. Task 17 established that the promoted fitter never runs on Nutrition5k: pre-checkpoint ingestion stamps every plate `mixture`, `run_summary.json` records `single_dominant: 0`, and — decisively — pre-checkpoint ingestion runs no segmenter at all, so those 3,490 fixtures carry no food mask and `fitFoodSupportPlane` has no input on them. N5k becomes available only after model-production Bucket C lands and ingestion re-runs with `--checkpoint`. And the 2026-08-05 device session produced no usable capture: all 22 single-view attempts refused and all three successes were two-view, which Req 7.11 excludes as evidence.

What remains is the two committed depth slices from task 22 — `1785135663727` and `1785901032716`, both flat bread on a plate at ~337 mm. `SupportPlaneCorpusMeasurementTests` is the instrumented pass `prerequisites.md` asks for, run over them with the guards disabled: per-candidate `supportFraction`, `bandMedianMm`, `supportVisibility`, per-sector support fractions, per-sector inner-band medians, and the raw signed-height distribution.

### Decision

Four constants are settled by the pass and their provenance markers change; the rest stay `[owed]` on named captures.

**Settled.**

- `ringInnerMm = 8` — confirmed, with a stated range envelope. Measured `mmPerPx` is 1.862 and 1.839 at median food depths of 338.9 mm and 336.9 mm, so the ~4 px depth smear spans **7.45 mm and 7.36 mm** — inside 8 mm on both. Because the smear is a fixed pixel count, `smear_mm = 4z/f_d` with `f_d ≈ 182 px`, so 8 mm covers capture range up to **≈ 365 mm** and no further. The constant is correct for the corpus and for ordinary handheld range; beyond ~365 mm it must become `max(ringInnerMm, 4 × mmPerPx)`.
- `ringMinSamples = 200`, per band — confirmed with large margin. Measured band counts are `[1120, 1132, 1213]` and `[1294, 1347, 1392]`, **5.6× to 7.0×** the floor. Decision 20's derivation (`ringSectorCount × 25`) is validated from the other end too: inner-band sectors carry **102–184** samples apiece against the 25 the derivation targets, so a 0.5 sector bar has binomial σ ≈ 0.042 rather than the σ ≈ 0.19 that made the guard noise at the old floor of 60.
- `supportVisibilityMin` is **firable**, and task 26's argument that it is not was based on the wrong region. That argument computes the ratio over the contact ring (8–25 mm), where a support strip thinner than `ringInnerMm` is indeed invisible. The implementation computes it over the **annulus** (0–50 mm), which begins at the food boundary and therefore does see a thin strip. Measured ceilings — every annulus sample an inlier — are **1.710 and 1.426**, and the highest-support candidate achieves **0.880 and 1.032**, so 0.15 sits at roughly a tenth of the achievable range. The guard is live; its *value* is still owed to prerequisites capture 4.
- The **pipeline Decision 46 tension is resolved in kind, not in value**. Pipeline Decision 46's 20 mm bar is a whole-plane residual over a matte table; `ringBandMm = 5` is a per-sample window. They are not the same quantity and were never in conflict. The per-sample figure is measured below and is what `ringSupportMin` actually rests on.

**Not settled, and why.** `ringSupportMin`, `sectorSupportMin`, `ringSectorCount`, `minSupportingSectors`, `ringSupportMarginMin`, `ringOuterMm`, `bandStepMaxMm`, `foodEnvelopeMinMm`, `minCandidateSamples`, `minAcceptedExtentPx`, `supportVisibilityMin`, Req 4.5's fallback-rate threshold, Req 5.1's tolerance and `fallbackPenalty` all stay `[owed]`. The corpus cannot set them for two measured reasons.

> **`minCandidateSamples` is superseded by Decision 32.** It was two constants under one name. Its whole-fit half is retired — `fitFoodSupportPlane` now tests ring-band feasibility against the already-`[measured]` `ringMinSamples` — and its extraction-pass half survives as `minResidueSamples`, still `[owed]` but bounded above at 581 by this same pass. `minAcceptedExtentPx` also stays `[owed]` and gains a corpus bracket of 13…26.

*The corpus contains no clean correct-fit case.* On `1785135663727` the plate-top candidate reads a ring median of −0.93 mm and a support fraction of 0.629, but its per-sector inner-band medians are `[+3.7, −0.4, +0.8, +1.4, −6.8, −32.6, −9.7, +3.8]`: sectors 4–6 form a contiguous arc sitting up to 32.6 mm below the plate, so the ring genuinely escapes onto the table over ~135°. On `1785901032716` the highest-support candidate is **the table, not the plate** — its per-sector medians are `[+16.6, +4.4, +3.0, +6.0, +19.8, +18.0, +4.7, +0.4]`, with three sectors a plate-height above it. Both captures are near-instances of the Req 3.6 silent-failure geometry rather than clean successes, so a bar fitted to make them pass would be fitted to the wrong side.

*Per-sample noise on a flat surface straddles `ringBandMm`.* The tightest inner-band mode — robust σ over samples within 15 mm of the band median, taken across every candidate so a contaminated winner cannot set it — measures **3.44 mm** on `1785135663727` (over 75.5 % of the band) and **6.98 mm** on `1785901032716` (over 92.0 %). At essentially the same range, 338.9 mm against 336.9 mm, that is a 2× disagreement, so it is a *surface* difference and not a range one — which is what pipeline Decision 46's matte-table evidence predicts. `ringBandMm = 5` falls between the two, and `ringSupportMin = 0.6` is a statement about exactly this distribution.

`prerequisites.md`'s suggestion to "capture at least one on a matte surface" is therefore promoted to a requirement of the capture session.

### Rationale

The alternative to recording a partial result is to set the numbers anyway, and the corpus actively argues against that. A bar tuned until both committed captures pass would be tuned on two captures whose rings demonstrably straddle the plate edge — it would encode "admit a ring that has escaped onto the table" as the definition of a correct fit, which is the precise defect Req 3.6 exists to prevent and the circularity Req 3.7 forbids.

The four settled constants are settled because each rests on a measurement whose answer does not depend on which plane is correct. Sample counts, millimetres per depth pixel, and the ratio of annulus samples to food samples are properties of the capture geometry. They would read the same on a clean capture, so a two-capture corpus is enough for them, where it is not enough for a threshold that must separate two populations the corpus only supplies one side of.

Promoting the matte-surface capture from suggestion to requirement follows directly from the 2× noise spread. Before the measurement it was a hypothesis that surface material dominates depth noise at this range; the two captures are now a demonstration, and `ringSupportMin` cannot be derived until the spread is characterised rather than merely observed.

### Alternatives Considered

- **Set every constant from the two committed slices** - Fit each bar until both captures admit their plate-top candidate, and record that as the corpus derivation - Rejected under Req 3.7. Both captures' rings cross the plate edge, so the fit would be to the failure side; it would also make `minSupportingSectors ≤ 5`, which admits the Decision 18 case outright (see Decision 30).
- **Run the pass over Nutrition5k for a larger corpus** - Call `FixtureRunner.fitSupportPlane` directly on the 3,490 ingested fixtures, bypassing the `mixture` estimator-path stamp - Rejected because it is not merely blocked by routing: pre-checkpoint ingestion runs no segmenter, N5k ships no ground-truth mask, and `fitFoodSupportPlane` requires a food mask. There is no input to give it until Bucket C.
- **Defer the whole of task 26 to the capture session** - Record nothing until captures 1–6 exist - Rejected because four constants are answerable now, two open `prerequisites.md` items are closed by the same pass, and the pass itself is the instrument the session needs. Deferring would mean building it twice.
- **Relax `ringSupportMin` to admit the measured 0.480** - Take the corpus's best support fraction as the achievable ceiling and set the bar below it - Rejected because 0.480 was scored by the **table** plane on `1785901032716`. Setting the bar below it admits precisely the wrong surface.

### Consequences

**Positive:**

- Four constants move from asserted to measured, and two `prerequisites.md` items — the `ringInnerMm` smear envelope and the pipeline Decision 46 tension — are closed without a capture session.
- The instrumented pass exists, is committed, and runs from a clean checkout, so the capture session feeds an instrument rather than starting one.
- The reason both committed captures fall back is now attributed to a measured geometry — rings crossing the plate edge — rather than left as an unexplained placeholder effect.
- The assertions are written so that new evidence breaks them: if a future capture stops straddling `ringBandMm`, `supportSurfaceNoiseStraddlesTheBand` fails and forces the derivation to be revisited rather than silently inherited.

**Negative:**

- Task 26 cannot be completed, and the remaining `[owed]` constants are now known to need specific captures rather than merely more data.
- The measurement pass lives in the test target because `SupportRegion`'s internals are not public; anyone wanting the numbers must run `swift test`, not a CLI.
- `1785901032716` yields no usable support-surface noise figure at all — its tightest mode spans plate and table — so the 3.44 mm figure rests on a single capture.
- The `ringInnerMm` range envelope of ~365 mm is stated but not enforced; a capture beyond it silently uses a ring inside the smear until the adaptive form lands.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (new), the provenance markers in `MedataCore/Sources/SupportPlane/SupportRegion.swift` and `design.md`, `prerequisites.md`, and task 26's detail in `tasks.md`. No shipped behaviour changes: no constant's value moves.

---

## Decision 30: The sector guard discards the sign that separates its two failure modes

**Date**: 2026-08-05
**Status**: superseded by Decision 40

**Superseded in part.** The finding — that the count takes `|height|` and so reads the same 5 of 8 for two opposite scenes — stands and is unchanged. What Decision 40 supersedes is this entry's *disposition*: the reason given below for leaving the proposal open, that "a rule for rejecting on signed sectors needs a threshold, and that threshold has the same evidence problem as every other `[owed]` constant", is measured and holds on only one of the rule's two axes. The magnitude bar is `ringBandMm`, already `[inherited]`; only a sector count is owed, and the corpus brackets it. Decision 40 states the rule precisely and carries the remaining owing forward. The **Decision** section below, which declines to state a rule, is the part that no longer applies.

### Context

Req 3.6 adds the sector measure because an aggregate support fraction cannot distinguish a ring lying wholly on the surface the food rests on from one that has crossed onto the surrounding surface. Decision 18 states the case: a ring 65 % on the table is 100 % table across roughly 235° and 0 % across the remainder, scores 0.65 in aggregate, and reproduces the defect this feature exists to remove while recording a ring median of approximately zero.

Decision 29's measurement pass ran that guard against the two committed captures and found it does not separate the case it was written for. `SupportRegion.ringStatistics` counts an inner-band sector as supporting when the share of its samples with `|height| ≤ ringBandMm` reaches `sectorSupportMin`. The absolute value is taken, so the count is blind to whether a failing sector sits above the candidate plane or below it.

Measured, at the shipped trio of `ringSectorCount = 8`, `sectorSupportMin = 0.5`, `minSupportingSectors = 6`:

| Capture | Candidate | Supporting sectors | Failing-sector inner medians |
|---|---|---|---|
| `1785135663727` | plate top (ring median −0.93 mm) | 5 of 8 | −6.8, −32.6, −9.7 mm |
| `1785901032716` | table (ring median +3.04 mm) | 5 of 8 | +16.6, +19.8, +18.0 mm |

Both score 5. Decision 18's geometry produces a supporting count within ±1 of `0.65 × ringSectorCount`, i.e. 4 to 7, and 5 sits inside it. No value of `minSupportingSectors` admits the first row and rejects the second.

The sign does separate them, and it separates them cleanly. Where the candidate is the raised support and the ring has escaped downward, failing sectors read strongly **negative** — the surrounding surface is below. Where the candidate is the surrounding surface and part of the ring lies on the support, failing sectors read strongly **positive**. The two rows differ by ~36 mm in the failing sectors while agreeing exactly in the count the guard uses.

### Decision

Record the finding and propose, without implementing, that the per-sector measure carry the signed median alongside the unsigned support fraction, and that the guard reject on *negative* failing sectors — a support surface whose ring has left it — separately from *positive* ones, which indicate the candidate is below the support rather than on it.

The change is not made here. Task 26 is scoped to determining constants, and this alters what the sector measure computes, which is a design change. It is recorded as proposed so that the capture session measures the signed quantity — `prerequisites.md` already asks for per-sector support fractions, and the sign costs nothing to record alongside them — and so that the sector trio is not set against a measure that is about to change.

### Rationale

Setting `ringSectorCount`, `sectorSupportMin` and `minSupportingSectors` against the current unsigned measure would spend the capture session deriving constants for a guard the same session's data would then show needs replacing. The measurement that reveals the problem is already in hand; deriving the trio first and discovering the blindness afterwards is the more expensive order.

The signed form is also what the rest of the design already relies on. Req 3.1 defines the ring measure as a *signed* median precisely because "the table plane reads strongly positive; a plane on a vessel rim reads negative", and Decision 22 restored the signed `|median|` admission guard on the grounds that "the support fraction is unsigned and cannot separate a plane above the ring from one below it". The sector measure is the same statistic computed per arc, and it lost the sign the whole-ring version was careful to keep.

Leaving it as `proposed` rather than accepted reflects that the corpus is two captures. The sign separation is 36 mm and unambiguous on both, but a rule for rejecting on signed sectors needs a threshold, and that threshold has the same evidence problem as every other `[owed]` constant.

### Alternatives Considered

- **Raise `minSupportingSectors` to 7 or 8** - Demand near-total sector support so the Decision 18 case at 4–7 is excluded - Rejected because it excludes the correct plate plane too: `1785135663727` scores 5 with a genuinely escaped ring, and a clean capture has not been measured, so there is no evidence any real capture reaches 7. It trades a false accept for a guaranteed false reject.
- **Increase `ringSectorCount` for finer angular resolution** - More arcs make a contiguous 235° failure more visible - Rejected because it does not address the blindness. Decision 18's case scales with the count: at 16 sectors it produces ~10 supporting, and a correct-but-escaped ring produces ~10 as well. It also halves the samples per sector, from ~140 towards the noise floor Decision 20 set the 200 sample floor to avoid.
- **Require contiguity of the failing arc rather than a count** - Reject when failing sectors form one contiguous run - Rejected as insufficient on the measured data: both rows have contiguous failing runs (sectors 4–6 in the first, 4–5 plus 0 wrapping in the second). Contiguity describes both failure modes; only the sign distinguishes them.
- **Implement the signed measure now** - Change `ringStatistics` in this task and set the trio against it - Rejected as out of scope and premature. It changes a persisted diagnostic (Req 6.4), and the threshold it needs is owed to the same captures as the constants it would replace.

### Consequences

**Positive:**

- The capture session will record the signed per-sector medians, so the evidence for or against this proposal arrives with the same six captures rather than requiring a further sitting.
- The sector trio is not set against a measure with a known blind spot.
- The finding is attributable: a supporting-sector count of 5 currently means two opposite things, and the record says which captures show each.

**Negative:**

- Req 3.6's guard remains, in its shipped form, unable to separate the case it cites — and the feature ships with that gap open until the proposal is decided.
- A proposed decision that the capture session does not resolve leaves the sector trio blocked on a design question as well as on evidence.
- Persisting a signed per-sector statistic would widen `RingStatistics` and the `EstimationAttemptRecord` fields task 12 added, after those were settled.

### Impact

No code changes. `SupportPlaneCorpusMeasurementTests` records the measurement; `prerequisites.md` adds the sign to the session's dump list. If accepted, it would touch `SupportRegion.ringStatistics`, `RingStatistics`, `SupportRegion.admissibility` and the Req 6.4 persisted fields.

---

## Decision 31: The third capture bundle is sliceable but not corpus-grade

**Date**: 2026-08-05
**Status**: accepted

### Context

Decision 29 recorded that task 26 stalls on a two-capture corpus, both of them flat bread on a white plate, and that the constants still `[owed]` need scenes the corpus does not contain. The most acute gap is a non-flat capture: `prerequisites.md` calls it capture 2 and states why it matters — the defect adds a roughly constant *height* to every food pixel, so a fix that overcorrects tall food passes every criterion the flat corpus can express.

A third bundle was already in hand. `1785054950406-success.fixture` is the 208 g mounded-rice capture from the 2026-07-26 session, pulled from the device and sitting in `tmp/device_captures/`. `field-truth-sessions.md` records it as unusable because `FixtureLoader` loads zero meals from it, and adds "not diagnosed — a fresh weighed capture is cheaper than repairing a July bundle". That verdict was reached through the replay path, which is not the path this feature's measurement pass uses: `tools/fixture_slice.py` reads the capture proto directly and needs only the depth map and the argmax mask.

Sliced, it produces a well-formed 295 KB `.depthslice` and runs through the whole pass. So the loader's failure is not a slice-level one, and the question of whether the bundle can serve as the non-flat anchor had to be answered on the depth data rather than inherited from the loader.

### Decision

The slice is committed and **excluded from the measurement corpus**, in a named `rejectedCaptures` list with the disqualifying measurement asserted in `rejectedCaptureIsNotCorpusGrade`. It is not the capture 2 anchor and does not reduce the capture session's scope; the session still needs all six.

The exclusion rests on the depth confidence map. **43.2 %** of the capture's food-mask samples carry ARKit's low confidence and are discarded by `SupportRegion.prepare` at τ_conf, against **0.0 %** on both admitted captures, and frame-wide it is 41.1 % against 22.7 % and 0.1 %. The discarded samples are the **near** ones — median 247.9 mm against the 277.8 mm of those that survive — which is to say the mound itself. What reaches the fit is the flat remnant around the pile, spanning 13.4 mm from p10 to p90, and the best candidate consequently reports a food envelope of **−9.0 mm**: the surviving food sits *below* the plane fitted around it. After filtering, the capture no longer contains a mound to anchor anything against.

### Rationale

Every check that does not read the confidence map passes, which is precisely why the exclusion is worth committing a fixture for. The capture fills all three ring bands at `[1391, 1405, 1541]`, comfortably clear of `ringMinSamples`; its 4 px smear is 6.06 mm at 277.8 mm range, inside `ringInnerMm`; and its confident food median sits 15.1 mm above its confident surroundings, which is a plate. A future session re-running the pass over `tmp/device_captures/` would find nothing wrong with it short of the confidence map.

And admitting it does not merely weaken the corpus, it produces a wrong answer. Its best candidate scores **3** supporting sectors, outside the 4…7 band Decision 18's geometry produces — so `sectorTrioDoesNotSeparateTheDecision18Case` flips from failing-as-designed to passing, reporting that the corpus can now separate a correct fit from the silent-failure case. It cannot. The count is 3 because the mound is missing, not because the ring is clean, and the sector trio would then be derived from a capture whose food is absent. That is the same circularity Req 3.7 forbids, arriving by a route Decision 29 did not anticipate: not a bar fitted to the failure side, but a bar fitted to a capture that no longer contains the thing being measured.

The finding also closes a question `field-truth-sessions.md` left open. The 208 g bundle's unusability is now attributed — depth confidence collapsed across the frame during that capture — rather than merely observed at the loader.

### Alternatives Considered

- **Admit it to `captures` as the third corpus capture** - Take the non-flat anchor the session is missing, on the grounds that three captures beat two - Rejected on the measurement: τ_conf removes 43 % of its food region including the whole mound, so it is not a non-flat capture by the time the fit sees it, and admitting it silently converts the sector derivation into a false positive.
- **Admit it with a τ_conf exemption for this capture** - Lower the confidence bar so the mound's samples survive and the capture becomes the anchor - Rejected because the low-confidence returns are what `lidar-plane-fit-matte-table-confidence` exists to exclude (Req 7.5), and their depth spread — p10 158.8 mm against a 277.8 mm surface — shows them to be wrong rather than merely uncertain. Deriving the noise constants from samples the shipped path discards would set bars the shipped path can never meet.
- **Leave the slice out of the repository entirely** - Record the finding in the decision log and delete the fixture - Rejected because the exclusion is not self-evident: the capture is well-formed at every level a reader would check, and the next session to notice an unused mounded-rice bundle would repeat this work. 295 KB buys a reproducible answer and a trap for the false positive.
- **Repair the bundle so `FixtureLoader` reads it** - Fix the loader path and recover the capture properly - Rejected as beside the point. The slice already bypasses the loader and reaches the pass; the defect is in the captured depth, which no loader fix recovers.

### Consequences

**Positive:**

- The one remaining "maybe we already have this capture" question is answered on measurement, so the capture session's scope is settled at six rather than argued.
- A false positive that would have set the sector trio from an empty mound is trapped by an assertion rather than left to a future reader's care.
- `field-truth-sessions.md`'s undiagnosed bundle is diagnosed, and the diagnosis — frame-wide confidence collapse — is a capture-technique lesson for the session rather than a code defect.
- The pass now records what makes a capture corpus-grade, which the six new captures will be measured against on arrival.

**Negative:**

- A third 295 KB fixture is committed that no derivation reads.
- The corpus is still two captures and every `[owed]` constant from Decision 29 stays owed; this changes none of them.
- The low-confidence share bar is asserted at 0.4 against a 0.0/0.43 split with nothing in between, so it separates the captures in hand but is not a calibrated admission threshold.
- Task 26 remains open, and task 27 remains blocked behind it.

### Impact

`MedataCore/Tests/SupportPlaneTests/Fixtures/1785054950406.depthslice` (new, not read by any derivation), `SupportPlaneCorpusMeasurementTests` (`rejectedCaptures` and `rejectedCaptureIsNotCorpusGrade`), `prerequisites.md`, `docs/agent-notes/field-truth-sessions.md` and task 26's detail. No shipped code changes and no constant's value moves.

---

## Decision 32: One sufficiency constant answered two questions, and one of them has an exact answer

**Date**: 2026-08-05
**Status**: accepted

### Context

Task 26 is measurement, not invention: every constant marked `[owed]` in `SupportRegion` has to be derived against the fixture corpus and the derivation recorded. Decisions 29 and 31 established that most of them cannot be, because the corpus is two captures of flat bread on a white plate and the missing scenes — a rimmed plate, a bowl, food at a small plate's edge, a matte surface — are what the remaining bars have to separate.

`minCandidateSamples = 500` is on that owed list, and re-reading its call sites shows it is not one constant. It is used twice, for questions that have nothing to do with each other. In `extractCandidates` it stops the sequential passes once the residue is too thin to be worth another RANSAC draw. In `fitFoodSupportPlane` it refuses the whole fit when the annulus is too small — a sufficiency test on the capture, asked before any plane exists.

The second use has an exact answer sitting beside it. `ringStatistics` returns nil unless *every* radial band clears `ringMinSamples`, and that test reads `samples.band` — the radial banding — and nothing else. It never touches a candidate plane. `ringSamples` is already computed one line above the guard, so the condition that actually decides whether this capture can produce a support fit is knowable there, exactly, for free.

### Decision

Split the constant and retire the half that has an exact answer.

`fitFoodSupportPlane`'s guard becomes `ringBandsAreFeasible(samples:)` — every radial band clears `ringMinSamples` — replacing the annulus count entirely. `ringMinSamples` is `[measured]` (Decision 29), so no `[owed]` value is involved.

What remains is renamed `minResidueSamples`, keeps the value 500 unchanged, and stays `[owed]` for the one question it now asks. The corpus bounds it **from above only**: measured residue per pass is `[10469, 3310, 581]` and `[12551, 2811, 932]`, so any floor above 581 cuts a pass the corpus produces. Nothing in the corpus fails for want of residue, so there is no measured floor and the lower end is owed to the capture session.

`minAcceptedExtentPx = 24` is **bracketed, not set**. Measured extents are 123, 76, 12 px and 155, 44, 26 px. The 12 px candidate is a 153-sample sliver sitting 32.9 mm off the ring, correctly rejected here, so the floor is above 12. The ceiling is soft: 26 px is the smallest extent reaching the later guards, and that candidate is rejected on `supportFraction` anyway, so the corpus never shows a 26 px candidate that deserved admission. 24 sits inside 13…26 with 2 px to spare.

### Rationale

The substitution is outcome-preserving by construction rather than by measurement, which is what makes it safe to ship against a two-capture corpus. The ring is built inside the annulus loop under a narrower radial test, so it is a strict subset. If the annulus holds fewer than 500 samples the ring holds fewer than 500 across three bands, so some band is under 167 and therefore under `ringMinSamples` — everything the retired floor rejected, ring feasibility rejects too. In the other direction a capture that passed 500 but cannot fill three bands used to run a full sequential extraction and then find every candidate's `ringStatistics` nil, returning nil after the work rather than before it. Same answer, less work, and one fewer asserted number on the shipped path.

Keeping `minResidueSamples` at 500 is deliberate. Raising it to the corpus ceiling would look like a derivation and is not one: 581 is where a floor starts *cutting* passes, not where a pass starts being worthless. Both third-pass candidates are rejected on their own merits, so cutting them changes no plane on this corpus — but `planeCandidateCount` is persisted (Req 6.4's neighbourhood), so a cut pass changes the record, and pass 3 is where a plate under a dominant table can still surface. Moving a value on evidence that only says "this is where it would start costing something" is the circularity Req 3.7 forbids, in a smaller shape.

Recording the extent bracket rather than the extent value follows the same line. The corpus supplies one clear sliver and no clear counter-example, so it can say where the bar is *not* and cannot say where it is.

### Alternatives Considered

- **Derive an annulus floor from the measured ring share** - Ring share is 0.331 and 0.321, close to the 17/50 the radial widths predict, so the annulus floor implying three feasible bands is ≈ 1,800; set `minCandidateSamples` there - Rejected because it replaces an exact test with a calibrated proxy for the same test. The ring share depends on mask shape and frame clipping, so the proxy needs an error bar the exact condition does not.
- **Leave `minCandidateSamples` as one constant and simply record the two uses** - Note the ambiguity in the decision log and change no code - Rejected because the ambiguity is the finding. A single number cannot be derived while it answers two questions, and the whole task is derivation; leaving it fused means neither half can ever be settled.
- **Raise `minResidueSamples` to 1200** - Take a value comfortably above both third-pass residues, on the grounds that a 581-sample residue is too thin for a meaningful RANSAC draw - Tried and rejected on measurement: it cuts pass 3 on both captures, dropping `planeCandidateCount` from 3 to 2 with no evidence that either cut candidate was worthless. The thinness is asserted, not measured.
- **Set `minAcceptedExtentPx` to 13, the bottom of the bracket** - Take the most permissive value the corpus admits, so no legitimate candidate is lost - Rejected because the guard's purpose is conditioning, not permissiveness: a 13 px component is a sliver by the Req 2.3 argument regardless of what this corpus happens to contain. The bracket is evidence about the bar's location, not an argument for its lower end.

### Consequences

**Positive:**

- One `[owed]` constant leaves the shipped path entirely, replaced by a `[measured]` one already derived in Decision 29 — the first owed value this feature has retired rather than deferred.
- A capture that cannot fill its ring bands now falls back before extraction instead of after it, so the wasted sequential RANSAC on a starved capture is gone.
- `minResidueSamples` has one job, so the capture session can derive it against one question instead of two.
- The extent bracket is asserted, so a future capture that narrows it below 2 px fails the test rather than silently losing a candidate to the guard.

**Negative:**

- `minResidueSamples` and `minAcceptedExtentPx` both remain `[owed]`; this narrows what they owe without paying it.
- The extent bracket rests on a single sliver, and its upper end on a candidate rejected for an unrelated reason, so 13…26 is weaker evidence than the interval's width suggests.
- `PlaneCandidate` gains a `residueCount` field read only by the measurement pass.
- Task 26 stays open and task 27 stays blocked behind it.

### Impact

`MedataCore/Sources/SupportPlane/SupportRegion.swift` (`ringBandsAreFeasible`, the constant split, `PlaneCandidate.residueCount`), `SupportPlaneCorpusMeasurementTests` (three derivation tests), `SupportRegionSelectionTests` (a stale comment), `design.md` and task 26's detail. No plane moves and no persisted value changes on any capture in the corpus.

---

## Decision 33: The plate margin is measured, and `ringOuterMm`'s derivation rule cannot be met

**Date**: 2026-08-05
**Status**: accepted

### Context

`ringOuterMm = 25` is `[owed]` against a rule its own comment states: it "must sit inside the smallest measured plate margin". Unlike the noise thresholds Decisions 29 and 32 could not settle, that rule asks for a property of the **capture geometry** — how far the plate extends beyond the food — and Decision 29's rationale is explicit that such properties are exactly what a two-capture corpus can answer, because they read the same on a clean capture as on a straddling one.

Decision 29 also left a question open in its account of why both captures fall back. It attributes the fallback to rings that "demonstrably straddle the plate edge" and treats that as a property of the two captures. It does not measure how far the plate actually extends, so it cannot say whether the ring escapes because the captures are unlucky or because the ring is wider than the plates it is being asked to sit on.

`SupportPlaneCorpusMeasurementTests` gains the instrument that answers both: the **support margin** per sector. For each of the eight arcs, the median height is profiled outward from the food boundary in 2 mm bins, referenced to the strip within 4 mm of the boundary — whatever the food rests on, that strip is on it — and the margin is the distance at which the profile departs from that reference by more than `ringBandMm`. Denominating the departure in `ringBandMm` means the margin bounds the guard it feeds rather than being a separate quantity. The winning candidate's normal is borrowed to remove camera tilt; its offset is not used, so the measure is valid on `1785901032716`, whose best candidate is the table.

### Decision

Record the measured margins, and restate what `ringOuterMm` owes rather than setting it. No code changes and no constant moves.

**Measured.** Per-sector support margins are **16, 40, 10, 42, 6, 4, 6, 44 mm** on `1785135663727` and **34, 4, 46, 8, 30, 14, 12, 6 mm** on `1785901032716`. Every departure inside the ring is a **fall**, of 5.1 to 15.6 mm, so these are plate edges and not the raised rim of a vessel.

**The rule is unsatisfiable.** The smallest margin is 4 mm on both captures — inside `ringInnerMm = 8`, where no ring can be placed. There is no value of `ringOuterMm`, including one below the ring's own inner edge, that sits inside the smallest measured plate margin. The rule as written cannot be met by any capture whose food reaches within 8 mm of the plate edge, which both of these do.

**What it explains.** Only **3 of 8** sectors reach `ringOuterMm` on each capture, and only **4 of 8** reach the inner band's outer radius of 13.7 mm — the radius the sector measure is actually decided at. `minSupportingSectors = 6` therefore cannot be met on either capture *by geometry*, before `sectorSupportMin` or any noise threshold is consulted. The measured supporting counts of 5 (Decisions 29, 30) exceed the 4 fully-on-plate sectors only because a sector whose plate ends mid-band can still clear a 0.5 share.

`ringOuterMm` stays `[owed]`, now against the margin the **sector measure** needs in **enough** sectors — a joint derivation with the trio, owed to the same captures.

### Rationale

The finding changes what the capture session has to establish. Decision 29 and Decision 30 both read the corpus as supplying no clean correct-fit case, and both treat that as a fact about the two captures. It is partly a fact about the ring: at 8–25 mm around the food, the ring extends past the plate in five of eight directions on captures whose food is ordinarily placed. A session that captures six new scenes without recording the margin would produce the same stalled derivation and attribute it, again, to the captures.

Restating the rule rather than repairing it follows Decision 30's shape and for the same reason. A rule of the form "inside the smallest margin" presumes the ring can always be placed wholly on the support surface, and the measurement shows that presumption is false for real food on real plates — food is put in the middle of a plate, not concentrically inside a 25 mm collar. Tolerating a partial crossing is precisely the job Decisions 18 and 19 gave the **sector** measure, so the surviving question is how much margin the sector measure needs and in how many sectors, which is one derivation and not two.

Leaving `ringOuterMm` at 25 while recording that it is too wide for the corpus's plates is deliberate. Shrinking it — to 13 mm, say, so more sectors stay on-plate — would narrow the ring towards the smear at `ringInnerMm`, collapse the three radial bands `bandStepMaxMm` reads, and be fitted to two captures' plate diameters. That is the circularity Req 3.7 forbids, and it would trade a measured, understood failure for an unmeasured one.

### Alternatives Considered

- **Set `ringOuterMm` to the smallest measured margin** - Take 4 mm as the corpus's answer and shrink the ring to fit - Rejected because 4 mm is inside `ringInnerMm`: the resulting ring is empty. The measurement disproves the rule rather than supplying a value for it.
- **Set `ringOuterMm` to the median margin (≈ 13 mm)** - Size the ring so a majority of sectors stay on the plate - Rejected because it leaves 5 mm of radial width for three bands, roughly one depth pixel apiece at corpus range, which starves `ringMinSamples` and makes `bandStepMaxMm` unreadable. It also fits the constant to two plate diameters, which Req 3.7 forbids.
- **Treat the margins as evidence that the captures are unusable** - Add a margin bar to the corpus-grade criteria, as Decision 31 did with depth confidence - Rejected because there is nothing wrong with these captures. Bread in the middle of a dinner plate is the modal case this feature exists for; a corpus admitting only food inside a 25 mm collar would be selected to make the ring work.
- **Implement a sector-relative ring now** - Size the ring per sector from the measured margin so it always sits on the support surface - Rejected as out of scope and unevidenced. Task 26 determines constants; this changes what the ring is. It would also make the ring's radial extent scene-dependent, and the sector measure's whole premise is that arcs are comparable to one another.

### Consequences

**Positive:**

- The reason both corpus captures fall back is now measured to the sector rather than described: the plate ends inside the ring in five of eight directions, and the supporting count is capped at 4–5 against a bar of 6 by geometry alone.
- `ringOuterMm` has a rule that can be satisfied, so the capture session can derive it instead of discovering mid-session that it cannot.
- The trio and `ringOuterMm` are now known to be one derivation, which removes a false independence from the session's plan.
- The assertions break in the right direction: a capture whose plate reaches the inner band in six sectors fails `plateMarginCannotSetRingOuter`, forcing the derivation to be revisited rather than inherited.

**Negative:**

- `ringOuterMm` remains `[owed]` and the ring ships wider than the plates in the corpus, so the shipped guard's sector counts are depressed by geometry on ordinary captures — the feature falls back where it should fit, which is the safe direction but not the correct one.
- The margin rests on the food mask's boundary, so a segmentation that leaks onto the plate shortens the margin it measures; the corpus cannot separate the two.
- One more open design question — how much margin the sector measure needs — now waits on the same six captures as Decision 30's proposal, and the two interact.
- The measure reports the margin at 2 mm resolution and censors at the annulus edge (50 mm), so the three wide sectors per capture are lower bounds rather than distances.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`SectorMargin`, `sectorMargins`, `plateMarginCannotSetRingOuter`), the `ringOuterMm` comment in `MedataCore/Sources/SupportPlane/SupportRegion.swift`, `design.md`, `prerequisites.md` and task 26's detail. No shipped behaviour changes and no constant's value moves.

---

## Decision 34: Five of the nine rejection reasons never fire on the corpus

**Date**: 2026-08-05
**Status**: accepted

### Context

Decisions 29, 32 and 33 each took one `[owed]` constant, measured what the two committed captures can say about it, and recorded the bound rather than inventing a value. Each treated the constant in isolation. Reading them together raises a question none of them asks: of the guards these constants gate, which does the corpus ever *reach*?

`admissibility` applies nine rejection reasons in a fixed order and short-circuits at the first that fires, so the reason it returns says which guard came first, not which guards would have fired. Nothing observable depends on that order — the reason is not persisted, and a rejected candidate is rejected either way — but it bounds what a measurement pass can see. A constant behind a guard the corpus never reaches is in a weaker position than one the corpus bounds from a single side: nothing in the corpus says it is even correctly oriented.

`SupportPlaneCorpusMeasurementTests` gains `allRejections`, which restates the shipped conditions and evaluates all of them independently. The restatement is pinned against drift by asserting that its first entry equals what `admissibility` returns for the same candidate.

### Decision

Record what the corpus exercises, and bound the four constants behind the guards it does not. No constant moves and no shipped behaviour changes.

**Under the shipped order, three reasons fire**: `extent`, `supportFraction`, `sectors`. Evaluated independently a fourth does — `ringMedian`, on four of the six candidates. **Five never fire**: `ringUnavailable`, `foodEnvelope`, `bandStep`, `visibility`, `escaped`.

**`foodEnvelopeMinMm = 0` is bounded from above at 25.8 mm** — the envelope of the candidate the design intends to select on `1785901032716`, and 26.6 mm on `1785135663727`. Above that the guard rejects the fit this feature exists to produce. Every envelope in the corpus is positive (7.2 to 39.6 mm), so the negative-envelope cases the guard is written for — a bowl, a plane on the food top — are absent and there is no floor. The design's illustrative "bread p90 ≈ +8 mm" is measured at **+26.6 mm**, low by 3×; the figure is corrected, the argument it supports is unaffected.

**`bandStepMaxMm = 6` is approached from the wrong side.** It fires on an outward *rise*; every inner→mid step in the corpus is a *fall*, from −0.5 to −6.5 mm, because a flat plate ends and the table begins. The corpus is 6.5 mm from the bar on the side that cannot reach it, and its ceiling still waits on the ruler measurement `prerequisites.md` carries.

**`escapeBandMm = 30` is correctly one-sided.** Req 3.3 rejects a plane lying *below* the surrounding surface, which reads a **positive** annulus median, and that is the comparison shipped. Corpus annulus medians span −36.6 to +5.7 mm: the largest positive is a fifth of the bar, and the one candidate far from its surroundings is far *above* them — a plane on the food top, which `ringMedianMaxMm` rejects and Req 3.3 makes no claim about.

**`supportVisibilityMin = 0.15` is firable (Decision 29) but never fired**: the lowest visibility any corpus candidate reaches is 0.246, 1.6× the bar.

**`ringSupportMarginMin = 0.15` is not reachable at all.** It compares the top two *admissible* candidates and neither capture produces even one. The gaps real candidates open are **0.312 and 0.117**, so 0.15 falls between them and would call one capture's pair distinct and the other's ambiguous — with no known-correct winner on either to say which verdict is right.

### Rationale

The finding changes what the capture session has to do, in the same way Decision 33 did. Its brief so far is "produce the scenes that set the values". For these four it is "produce the scenes that *fire the guards*", which is a stronger requirement and maps onto specific captures: capture 5, the bowl, is the only source of a negative food envelope; captures 3 and 4, the rimmed plate, are the only source of an outward band rise and of a visibility below 0.246; and no planned capture produces a positive annulus median anywhere near 30 mm, so `escapeBandMm` will still be unexercised after the session unless one is arranged.

Stating that as a measurement rather than a worry is what the pass is for. "These constants are owed" and "these guards have never run" read alike in a task list, and they are different problems: the first needs a value, the second needs evidence that the guard does anything at all. Decision 22 retired two guards on exactly this ground — a bar positioned where it cannot fire — and the only reason `escapeBandMm` and `ringSupportMarginMin` are not in the same position is that the corpus is too small to tell.

`ringSupportMarginMin`'s straddle is the same shape as `ringBandMm`'s in Decision 29, and gets the same treatment. A corpus that brackets a constant from both sides at once is a corpus that cannot set it, and asserting the straddle is what makes a future capture that closes it fail the test rather than pass unnoticed.

The guard-order note is recorded because it is a live trap rather than a defect. A future reader measuring "why was this candidate rejected" from `admissibility` alone would conclude the corpus exercises three guards and that the rest are fine; the independent evaluation says a fourth fires and five do not. Reordering the guards would change every such reading while changing no behaviour.

### Alternatives Considered

- **Set `foodEnvelopeMinMm` to a positive value inside the measured ceiling** - The corpus shows envelopes from 7.2 to 39.6 mm, so a floor at, say, 5 mm sits below all of them and would reject a plane on the food top - Rejected because it fits the bar to the pass side alone, which Req 3.7 forbids. The guard exists to catch bowls and food-top planes; the corpus contains neither, so a value chosen inside it is calibrated against the cases the guard is *not* for.
- **Reorder `admissibility` so the cheap, always-computable guards run last** - Put `extent` and `supportFraction` after the geometric ones so a measurement pass sees more reasons fire - Rejected because it treats the pass's convenience as a reason to change shipped code, and it does not help: the guards that never fire are never fired by these captures at any position in the order. `allRejections` gets the same information without touching the shipped path.
- **Retire `escapeBandMm` and `ringSupportMarginMin` as unfirable, following Decision 22** - Two guards no capture has ever fired look exactly like the residual bar and the MAD bar that were deleted - Rejected because the evidence is not the same. Those two were shown unfirable by *arithmetic* — a bar below a floor the algorithm enforces elsewhere. These two are firable in principle and merely unreached by a two-capture corpus, and deleting a guard on absence of evidence from two captures is how the Decision 18 silent failure got in.
- **Record the finding in the task detail and add no assertions** - The numbers are in the dump already - Rejected because the value of the finding is that it *breaks* when the corpus improves. A capture that fires `bandStep` or produces two admissible candidates should fail a test and force the derivation, not pass quietly into a dump nobody re-reads.

### Consequences

**Positive:**

- The capture session's brief for four constants changes from "set a value" to "fire the guard", and each is now mapped to the specific planned capture that can do it.
- `escapeBandMm`'s orientation is verified against Req 3.3 rather than assumed, which is the one thing about it the corpus *can* settle.
- The design's bread envelope figure is a measurement instead of an estimate that was 3× low.
- Every finding is an assertion that fails when the corpus improves, so the next session is told what changed rather than having to re-derive it.
- The restatement of the guard conditions is pinned to `admissibility`, so the two cannot drift apart silently.

**Negative:**

- Five findings, no values: this narrows what four constants owe without paying any of them, and `ringSupportMarginMin` is now known to be untestable on anything the corpus contains.
- `escapeBandMm` will likely still be unexercised after the six planned captures, so a constant on the shipped path may ship having never been demonstrated to do anything.
- The guard conditions are now written twice — once in `SupportRegion.admissibility`, once in the pass's `allRejections` — and only the first entry of the second is pinned; a drift in a later condition would show up as a wrong count rather than a failed pin.
- Task 26 stays open and task 27 stays blocked behind it.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`CandidateMeasurement`, `measurements`, `allRejections` and five derivation tests), the constant comments and the `admissibility` order note in `MedataCore/Sources/SupportPlane/SupportRegion.swift`, `design.md`, `prerequisites.md` and task 26's detail. No shipped behaviour changes and no constant's value moves.

---

## Decision 35: Req 5.1's tolerance is a grid-transfer measurement, and one bar does not transfer

**Date**: 2026-08-06
**Status**: accepted

### Context

Req 5.1 asks for support-plane coefficients "equal within a documented tolerance, verified on a named fixture", and `design.md` lists that tolerance and that fixture among the numbers the design owes. Decisions 29 to 34 each took an `[owed]` constant; this one takes the two owed figures that are not constants at all.

Half the question was answered by construction and has been since task 16. Device and offline replay run **one** implementation, so on identical bytes the arithmetic is identical — `fitIsDeterministic` asserts it for Req 7.7 — and a tolerance over that measures nothing. What legitimately differs between a device capture and a replay is the **depth grid**: `design.md`'s own transfer table names the N5k identity grid as the case the millimetre-denominated radii exist to survive. Until now that claim was tested only on a synthetic scene built to satisfy it (`fitTransfersAcrossDepthGrids`), where the geometry is exact by construction and the answer is the premise.

`SupportPlaneCorpusMeasurementTests` gains three tests that measure it on the committed captures instead: decimate the depth grid, refit, and compare where the plane cuts the food-mask centroid ray. That comparison point is chosen because volume is integrated per-pixel above the plane, so a millimetre of movement there is a millimetre added to every food pixel — the units the tolerance has to be in to constrain anything.

### Decision

**The tolerance is 1 mm, and the named fixture is `1785135663727`.** Across a 2× depth-grid halving — 256×192 to 128×96, a different RANSAC seed, and a quarter of the samples — the plane moves **0.835 mm** on `1785135663727` and **0.037 mm** on `1785901032716`, with normals tilting 0.945° and 0.063° and the ring measure moving 0.52 mm and 0.06 mm. One millimetre is the wider of those rounded up; the corpus meets it at 84 %, so it is a measured bar rather than a comfortable one. The fixture named is the wider capture, which is already the fixture Reqs 6.2 and 7.1 name.

Two things this bounds and two it does not.

**The transfer has a resolution floor, and the floor is the ring's.** Halving again refuses the fit outright: at 64×48 the inner band holds **37** and **32** samples against `ringMinSamples = 200`, so `ringBandsAreFeasible` returns false before any plane is fitted. The inner band is the narrowest in millimetres and therefore the first to fall under a pixel of width. Both bounds that decide this are the same quantity — `mmPerPx = z / f_d` — so coarsening the grid divides `f_d` exactly as increasing the range multiplies `z`, and this is Decision 29's ~365 mm range envelope reached from the other direction. Note also that at 128×96 the 4 px smear is already **14.9 mm** against `ringInnerMm = 8` and the plane still transfers within a millimetre: the smear bound governs how clean the ring *measure* is, not where the plane lands.

**`planeCandidateCount` is grid-dependent where the plane is not.** Both captures extract three candidates natively and two at half resolution, because each pass leaves a smaller residue. That field is persisted (Req 6.1, task 12), so a device/replay comparison must read it as a property of the capture's resolution rather than of the scene.

**`minAcceptedExtentPx` does not transfer at all.** It is the only bar in `admissibility` denominated in pixels; every other one is millimetres or a dimensionless fraction, which is precisely what Req 5.1's transfer rests on. Extents halve with the grid — 123→61, 155→77, 44→22 — and the third of those crosses the bar: a surface the guard admits at 44 px is rejected as a sliver at 22 px, same scene, same plane, same 24. Decision 32's 13…26 bracket is therefore a **256×192** bracket, and nothing said so where the constant is defined.

### Rationale

The tolerance had to be denominated in something the requirement cares about. Plane coefficients are not comparable in the abstract — `d` is in millimetres but the normal is dimensionless, and a small tilt on a distant plane moves the surface more than a large tilt on a near one. Evaluating both planes on one fixed camera ray through the food gives a single number in millimetres that is exactly the per-pixel volume error, which is the quantity Req 5.1 exists to protect.

Decimation was chosen over interpolation or synthetic rescaling because it is the only resampling that invents no depth values. It subsamples one sensor's output, and that is also its limit: it models a coarser **grid**, not a different sensor, so it carries this sensor's smoothing with it. The device leg of Req 5.1 — the same capture fitted on the phone and in replay — stays task 27's, and this measurement does not pre-empt it. What it does is give task 27 a bar to report against instead of a blank.

The `minAcceptedExtentPx` finding is the reason this is worth a decision rather than a line in the dump. Req 5.1's transfer argument is stated as a property of the design — "everything downstream is millimetre-denominated off `mmPerPx`" — and it is true of every constant but one. The exception is not hypothetical: `tools/nutrition5k/ingest.py` pins N5k at f = 617 px against the device's measured f_d = 182 px, so the same physical extent spans **3.4×** more pixels on the N5k grid, and 24 px is a materially stricter bar on the device than on the corpus the calibration will be fitted against. Nothing has hit it yet only because pre-checkpoint N5k ingestion runs no segmenter, so those fixtures carry no food mask and never reach the guard. Model-production Bucket C is when they do.

### Alternatives Considered

- **Document the tolerance as exact equality** - One implementation, same bytes, same plane; state 0 mm and cite `fitIsDeterministic` - Rejected because it answers a question nobody is at risk from. Req 5.1 exists so that a β_c fitted offline is valid on device, and the two corpora differ in depth resolution, not in arithmetic. A tolerance of zero would be true and would license nothing.
- **Derive the tolerance from the ~5 % device-to-replay volume divergence Req 7.2 quotes** - There is already a figure in the spec; convert it to millimetres - Rejected because that figure is a *volume* divergence measured on the pre-feature path, and it bundles segmentation, class, and density with the plane. Converting it back into a plane tolerance would attribute all of it to geometry.
- **Test the transfer by upsampling instead of decimating** - Replicate each depth pixel 2×2 to reach a finer grid, closer to the N5k direction - Rejected because it adds no information: a nearest-neighbour upsample is the same surface sampled redundantly, so the RANSAC draws land on duplicated points and the fit is bounded to agree. Decimation removes information, which is the direction that can fail.
- **Re-denominate `minAcceptedExtentPx` in millimetres now** - Replace the pixel bar with `extentMm ≥ k` and set k from the corpus - Rejected as out of scope and premature in the same way Decision 30's sector fix is. It changes what `admissibility` computes, the constant is `[owed]` and bracketed rather than set, and the capture session is what settles the bracket. Recorded here and in the constant's comment so the session sets it in the right units.

### Consequences

**Positive:**

- Two of the four figures `design.md` lists as owed beyond the constants are now measured, and one of the four gates on task 27's device leg rather than on a capture session.
- Req 5.1's transfer claim is verified on real captures for the first time; it was previously verified only on a scene constructed to satisfy it.
- The resolution floor is a number — 128×96 holds, 64×48 refuses — and it is shown to be the same `mmPerPx` bound as Decision 29's range envelope, so two envelopes become one.
- A live defect in the calibration path is identified before it can fire: `minAcceptedExtentPx` is 3.4× stricter on the device than on the N5k grid it will be fitted against, and Bucket C is when that starts to matter.
- `planeCandidateCount`'s grid dependence is recorded before someone compares it across references and reads a resolution change as a scene change.

**Negative:**

- The tolerance is derived from decimation, which models a coarser grid rather than a different sensor, so it does not bound sensor-to-sensor divergence — and the device/replay pair Req 5.1 literally names is still unmeasured until task 27.
- Two captures, one halving: 0.835 mm and 0.037 mm differ by 20×, so the corpus says little about what governs the spread, and a third capture could exceed 1 mm.
- `minAcceptedExtentPx` is now known to be wrongly denominated and is not fixed, so the feature ships a guard whose verdict depends on the sensor grid.
- Task 26 stays open and task 27 stays blocked behind it; nothing here needs a capture, and nothing here closes a constant.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`GridFit`, `decimated`, `foodCentroidRay`, `planeDepthMm`, `gridTransferToleranceMm` and three derivation tests), the `minAcceptedExtentPx` comment in `MedataCore/Sources/SupportPlane/SupportRegion.swift`, `requirements.md` Req 5.1, `design.md`, `prerequisites.md` and task 26's detail. No shipped behaviour changes and no constant's value moves.

---

## Decision 36: The fallback penalty is priced in millimetres, and the corpus measures 35× what it charges

**Date**: 2026-08-06
**Status**: accepted

### Context

`Confidence.supportPlaneFallbackPenalty = 0.9` is the last `[owed]` figure in task 26 that no derivation has touched. Unlike every `SupportRegion` constant, it is not a bar a guard fires on — it is a price, and Req 4.6 states the only compliance test it has: when the fallback fires, the reported confidence must be "no higher than for a restricted fit of equal residual". At *equal* residual any value in (0, 1) satisfies that, so the criterion cannot choose the number and never could.

The number's denomination comes from the curve it multiplies. `sigmaPlane` is exp(−r/5) with r in millimetres and r₀ = 5 mm, so a multiplicative penalty p asserts that the fallback carries −5·ln(p) millimetres of extra plane error. **0.9 prices the fallback at 0.53 mm.** That is a measurable quantity: it is the height the edge-band plane adds to a food pixel relative to the plane the design intends to select, which is exactly what volume integration adds.

`SupportPlaneCorpusMeasurementTests` gains two tests that measure it on the committed slices. The measure is taken **per food sample and averaged**, not on the food-centroid ray Decision 35 uses: that ray is legitimate for Req 5.1, where the two planes are two fits of the *same* surface and are near-parallel, but here they are 7.18° apart on one capture and a single ray would stand for nothing.

### Decision

**The corpus bounds `supportPlaneFallbackPenalty` from above at 0.025 and cannot bound it from below. The constant does not move.** The over-report is recorded, with its three components measured.

**The price.** On `1785135663727` the edge-band plane adds **18.370 mm** to the mean food pixel (p10 7.956, p90 28.606, centroid ray 18.352 mm), which prices the fallback at exp(−18.37/5) = **0.025**. The shipped 0.9 is **35.5× above** it. The figure is corroborated outside this pass: 18.37 mm over the capture's ≈ 212 cm² equivalent-disc food footprint is ≈ 390 cm³, against the **408 cm³** `SupportPlaneRegressionSliceTests` measures between the pre-feature and corrected volumes (714.8 → 306.8 cm³), the residue being the `max(0, ·)` clamp and off-axis pixel area.

**The residual channel works against the penalty rather than with it.** The edge-band plane is a *good* fit to the wrong surface, so its residual is **lower** than the restricted fit's on both captures — 1.954 mm against 2.327 mm, and 1.928 against 2.365 — and exp(−r/5) rewards it for that. The advantages are 0.373 mm and 0.437 mm, i.e. **71 % and 83 %** of the 0.527 mm the penalty prices. The penalty is therefore mostly spent cancelling an advantage before it prices anything, and the net effect measured on the same capture is a **3.1 %** confidence reduction (σ_plane 0.609 against 0.628) for a plane 18 mm wrong and a 2.33× volume over-read.

**Only one capture can price it, and the sign is what says so.** On `1785901032716` the same subtraction gives 2.787 mm, and that is not a fallback error: Decision 30 established that this capture's highest-support candidate is the **table**, so the two planes are two fits of one surface. The discriminator is Decision 30's proposed sign, used here as an analysis tool rather than a guard — the median signed inner-band height of the failing sectors is **−9.680 mm** on the first capture (the candidate is the raised support, the ring escaped downward) and **+18.021 mm** on the second (the candidate is what the ring escaped onto). The 2.787 mm is kept as what it is: a Req 4.3 agreement figure between two independent fitters on one surface, inside `ringBandMm`.

**The obvious per-capture substitute is measured and rejected.** The fallback path already persists a ring measure (Req 6.1), so pricing each fallback from it looks free. It does not track the quantity: the ring median reads 4.244 mm against an 18.370 mm offset (**0.231×**) and 6.888 mm against 2.787 mm (**2.471×**) — low where the offset is real, high where it is not. The cause is Decision 33's: the ring sits 8–25 mm out and the plate ends inside it in five of eight directions, so the median averages support and surroundings instead of reading either. Wrong in both directions is worse than wrong in one, because no scale factor repairs it.

### Rationale

Setting the constant to the measured ceiling would be the same circularity Req 3.7 forbids for the sector trio, arriving from the other side. The fallback fires in two distinct situations: when a raised support exists and the restricted fit was rejected, where the error is the support height and the honest penalty is ≈ 0.025; and when the food rests directly on the surrounding surface, where the edge-band plane *is* the support plane and the honest penalty is 1. One multiplicative constant must price the mixture, and the mixture weight is precisely Req 4.5's fallback rate — which has no denominator until model-production Bucket C. The two owed figures are therefore one dependency, not two, and pricing the constant at 0.025 today would charge every capture for a plate that half of them do not have.

Measuring per food sample rather than on one ray is not a refinement, it is the difference between a number and an artefact. The 7.18° tilt between the two planes spreads the offset from 7.96 mm to 28.61 mm across a single food region — a 3.6× range — so even a per-capture price is a single number for an error that is not uniform over the food it is charged against. That is worth recording against any future proposal to make the penalty adaptive.

The residual finding is the part that changes how Req 4.6 should be read. The criterion compares against "a restricted fit of *equal* residual", and no such fit exists on either capture: the fallback's residual is lower, because a plane fitted to a large clean table is better conditioned than one fitted to a plate top. So the penalty's first 0.4 mm buys nothing, and Req 4.6 is satisfied on the real comparison by 3 % rather than by the 10 % the constant appears to give. Decision 12's argument for keeping the penalty multiplicative and separate from the residual is strengthened by this — the residual genuinely cannot carry the error — but its sufficiency at 0.9 is not.

### Alternatives Considered

- **Set the penalty to the measured ceiling of 0.025** - The corpus has priced it; charge what it costs - Rejected because the corpus contains one raised-support capture and no capture of the other leg. A fallback on food resting directly on the table is a *correct* plane, and 0.025 would report it at a fortieth of the confidence it earns. The mixture weight is Req 4.5's fallback rate, absent until Bucket C.
- **Price each fallback from its persisted ring median** - The measurement is already recorded on the fallback path, so the constant could become a per-capture function at no storage cost - Rejected on measurement: the ratio of ring median to offset at the food is 0.231 on one capture and 2.471 on the other. It is the right *sign* (Req 3.1) and the wrong size, in both directions.
- **Retire the penalty and let the residual carry the fallback's error** - One channel is simpler than two - Rejected, and the measurement is what rejects it: the fallback's residual is *lower* than the restricted fit's on both captures, so the residual channel would report the fallback as the better fit. This is Decision 12's argument, now with numbers.
- **Record Req 4.6 as satisfied and close the figure** - The shipped 0.9 does make the fallback report lower confidence than the restricted fit on both captures - Rejected because "satisfied" and "correct" are different claims and the gap between them is 35×. A criterion any value in (0, 1) meets is not evidence for the value chosen, and task 26 exists to say where numbers come from.

### Consequences

**Positive:**

- The last untouched figure in task 26 now has a derivation, a denomination, and a measured bound, rather than a value that mirrored an unrelated constant.
- The over-report is attributable and reproducible: 35.5×, from one capture, with the volume cross-check agreeing to ≈ 5 %.
- A plausible design change — pricing the fallback from the persisted ring median — is closed on evidence before anyone builds it.
- Decision 12's separation of the penalty from the residual is confirmed by measurement rather than by argument, and the reason is the opposite of the intuitive one: the fallback's residual is *better*, not worse.
- Decision 30's proposed sign earns a second use. It is what tells a priceable capture from an unpriceable one here, which is independent evidence that the sector measure should carry it.
- `fallbackPenalty` is now known to depend on Req 4.5's fallback rate, so two owed figures collapse into one gate at Bucket C.

**Negative:**

- The shipped 0.9 is now known to be wrong on the only evidence in existence and is left in place, so the feature ships a confidence signal that under-reports the fallback's cost by a factor of 35 on a capture like `1785135663727`.
- The ceiling rests on **one** capture; the second cannot price the fallback at all, and no planned capture supplies the other leg — food resting directly on the surrounding surface, where the honest penalty is 1.
- The offset is not uniform over the food (7.96–28.61 mm across one capture), so a single multiplicative constant is a coarse instrument even once the mixture is known.
- Task 26 stays open and task 27 stays blocked behind it; nothing here needs a capture, and nothing here closes a constant.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`fallbackPlane`, `foodOffsetsMm` and two derivation tests), the `supportPlaneFallbackPenalty` comment in `MedataCore/Sources/Confidence/Confidence.swift`, the `SupportPlaneTests` dependency list in `Package.swift`, `design.md`, `prerequisites.md` and task 26's detail. No shipped behaviour changes and no constant's value moves.

---

## Decision 37: The extent bar is re-denominated in millimetres, and Req 5.1 loses its exception

**Date**: 2026-08-06
**Status**: accepted

### Context

Decision 35 measured Req 5.1's transfer across depth grids and found it holds — the plane moves 0.835 mm and 0.037 mm across a 2× halving — with one exception. `minAcceptedExtentPx = 24` was the only bar in `admissibility` denominated in **pixels**; every other one is millimetres or a dimensionless fraction, which is precisely what the transfer rests on. A pixel count on the winning inlier component halves when the grid halves, so a surface admitted at 44 px was rejected as a sliver at 22 px by the same constant. Decision 35 recorded the defect and deferred the repair, and the constant's own comment stated the two ways out: "re-derive it against `mmPerPx`, or state the grid it is denominated on, before any capture at another depth resolution is admitted to the corpus."

The gap is not hypothetical. `tools/nutrition5k/ingest.py` pins f = 617 px against the device's measured f_d = 182.033 px, so at equal range the same physical extent spans **3.389×** more pixels on the N5k grid — measured, not assumed. Model-production Bucket C is when N5k fixtures first carry a food mask and reach this guard at all, and at that point a bar tuned on the device grid becomes 3.4× looser there without anything in the code saying so.

Nothing about the repair needs a capture. `mmPerPx = median food depth / f_d` is already computed in `prepare` and already used to convert every ring radius, so the conversion is the module's existing one rather than a new one.

### Decision

**`minAcceptedExtentPx = 24` becomes `minAcceptedExtentMm: Float = 44`.** `PlaneCandidate` gains `extentMm` alongside the raw `extentPx`, computed once at construction as `Float(component.minExtentPx) * g.mmPerPx`; `admissibility` takes `extentMm` and compares it against the new constant. The pixel extent is kept because it is what the component scan produces and what a grid-dependence measurement has to see.

**The value does not move.** 24 px at the corpus's measured `mmPerPx` of 1.8616 and 1.8393 is 44.68 mm and 44.14 mm, so 44 mm is the largest whole millimetre at or below both and **every corpus verdict is unchanged** — at either capture's range the mm bar admits at ≥ 24 px exactly as the pixel bar did.

**The bracket becomes a physical bracket.** Measured extents are 228.973, 141.479, 22.339 mm and 285.084, 80.927, 47.821 mm, so the corpus brackets the constant at **22.339…47.821 mm** where it previously bracketed it at 13…26 px. Those two pixel numbers meant different physical sizes on the two captures, whose `mmPerPx` differ, and meant nothing at all on another grid.

**The transfer is measured, not argued.** Across the same 2× halving Decision 35 used, four surfaces pair across the grids. Their pixel extents halve — 123→61, 76→38, 155→77, 44→22 — while their millimetre extents drift by **1.698, 0.102, 1.839 and 0.000 mm**, at most half a pixel of the halved grid (3.68 mm). Verdict flips fall from one to **zero**. The 44 px → 22 px pair is the exact case Decision 35 named: it now reads 80.927 mm on both grids.

### Rationale

Of the two ways out the constant's comment offered, only one removes the defect. Stating the grid documents that a bar does not transfer; converting it means there is no longer a bar that does not transfer, and Req 5.1's transfer claim stops carrying an exception. That is worth more than the documentation because the exception was load-bearing — Req 5.1 is what makes a β_c constant derived offline valid on device, and a guard whose answer depends on the sensor's grid is exactly the kind of thing that invalidates it silently.

Holding the value fixed while changing its units is the same discipline `minResidueSamples` records: the corpus brackets this constant, it does not set it, so a change of denomination must not smuggle in a change of behaviour. Choosing 44 mm rather than the bracket's midpoint keeps the derivation honest — the number still traces to the pixel value someone once chose, and it is still `[owed]` until a capture session shows what a support surface can legitimately be.

Storing `extentMm` on the candidate rather than passing `mmPerPx` into `admissibility` keeps one conversion in one place. The candidate is built where the geometry is in hand; the guard is called from two sites that would otherwise each have to agree on the conversion.

The repair did not wait for Bucket C because the corpus already demonstrates the failure. A verdict that flips under decimation of the committed slices is evidence in hand, and the N5k ratio only says what the same defect would have cost later.

### Alternatives Considered

- **State the grid the constant is denominated on** - The other option the constant's own comment offered: annotate 24 px as a 256×192 value and require restatement for any other grid - Rejected because it preserves the defect and adds a manual step to every future corpus admission. Req 5.1 would still have to be stated with an exception, and the exception is the part that can invalidate a calibration transfer.
- **Set the value to the bracket midpoint (~35 mm)** - The corpus brackets 22.3…47.8 mm and 44 sits near the top, with only 3.8 mm of headroom above - Rejected because nothing measured justifies moving the value. The corpus never shows a 47.8 mm candidate deserving admission — that one is rejected on `supportFraction` anyway — so the ceiling is soft and a midpoint would be an invention dressed as a derivation.
- **Pass `mmPerPx` into `admissibility` and convert at the guard** - Keeps `PlaneCandidate` unchanged - Rejected: two call sites would each have to perform the conversion and agree, where the candidate already knows its own geometry at construction.
- **Leave it in pixels until Bucket C can measure the N5k leg** - The device grid is fixed at 256×192, so the bar is well defined for every capture that exists today - Rejected on the measurement: decimating the committed slices already flips a verdict, so the defect is demonstrable now and does not need the corpus that would first suffer from it.

### Consequences

**Positive:**

- Req 5.1's transfer claim no longer carries an exception: every bar in `admissibility` is now a millimetre or a dimensionless fraction, and the grid-transfer measurement shows zero verdict flips where it previously showed one.
- The corpus bracket becomes physical (22.3…47.8 mm) instead of grid-relative (13…26 px), so a capture at another depth resolution can be admitted to the corpus without restating it — which is what `prerequisites.md`'s session will produce.
- The N5k grid's 3.389× pixel-density difference is now measured and neutralised before Bucket C rather than discovered during it.
- No shipped behaviour changes on the corpus: the value was chosen so that every candidate keeps its verdict, and the full `SupportPlane` suite passes unchanged.
- `SupportPlaneCorpusMeasurementTests` now asserts the repair rather than the defect, so a future change that reintroduces a grid-dependent bar fails a test instead of being noticed three decisions later.

**Negative:**

- The constant is still `[owed]`. Re-denominating it does not set it, and 44 mm remains a value traced to a chosen pixel count rather than to a measured property of any support surface.
- The conversion uses `mmPerPx`, which is derived from the **median food depth**, so the bar now assumes the candidate surface lies at roughly the food's range. That assumption is the same one every ring radius already makes, but it is newly load-bearing for this guard: a candidate surface far behind the food is measured against a `mmPerPx` that is not its own.
- The headroom above the bar is 3.8 mm on the corpus — the same 2 px as before, restated — so a capture with smaller support surfaces can still close the bracket, and the assertion that guards it now fires in millimetres.
- `extentPx` and `extentMm` both exist on `PlaneCandidate`. The redundancy is deliberate, but it leaves two numbers where a future reader could reach for the wrong one; only `extentMm` is a bar.

### Impact

`MedataCore/Sources/SupportPlane/SupportRegion.swift` (`minAcceptedExtentMm`, `PlaneCandidate.extentMm`, `extractCandidates`, `admissibility`, `fitFoodSupportPlane`), `MedataCore/Tests/SupportPlaneTests/` (`SupportRegionSelectionTests`, `SupportPlaneRegressionSliceTests`, `SupportPlaneCorpusMeasurementTests` — the bracket derivation and the grid-transfer test, which changes sense), `requirements.md` Req 5.1, `design.md` (the `SupportRegion` block, the transfer table, and the owed-numbers section) and task 26's detail. Shipped behaviour is unchanged on the corpus by construction.

---

## Decision 38: The residue floor is re-denominated in millimetres², and the pass count stops reading the grid

**Date**: 2026-08-06
**Status**: accepted

### Context

Decision 35 measured Req 5.1's transfer across depth grids and left three riders. Decision 37 closed one of them — `minAcceptedExtentPx`, the only bar in `admissibility` denominated in pixels. The second stands: **`planeCandidateCount` is grid-dependent where the plane is not**, three extraction passes natively against two at half resolution.

The cause is one constant. `extractCandidates` stops when the residue falls below `minResidueSamples = 500`, a raw count of native depth samples. Halving the grid quarters every sample count while the surface those samples stand for is unchanged, so pass 3 — which enters with 581 and 932 samples natively — enters with roughly a quarter of that and is cut. `planeCandidateCount` is persisted (Req 6.1, task 12), so the record of how many candidate planes a capture produced was a property of the sensor's resolution rather than of the scene.

This is the same defect class Decision 37 repaired, and the same conversion repairs it: `mmPerPx` is already computed in `prepare` and already converts every ring radius and the extent bar. Nothing here needs a capture.

### Decision

**`minResidueSamples = 500` becomes `minResidueAreaMm2: Float = 1691`**, converted per capture by `minResidueSamples(mmPerPx:)`, which rounds **up** so the bar is never weaker than the area it stands for. `extractCandidates` converts once per capture and compares residue counts against that.

**The value does not move.** 500 samples at the corpus's measured pixel areas of 3.465 mm² and 3.383 mm² is 1732.6 mm² and 1691.5 mm², so 1691 mm² is the largest whole millimetre² at or below both — the floor is 488 and 500 samples on the two captures, and every corpus pass keeps its verdict.

**The area is the invariant, and it is measured rather than argued.** Pass 1 draws from the annulus, which no removal has touched, and its area agrees across the halving to **0.29 %** and **1.17 %** (36 279.6 → 36 175.7 mm², 42 458.0 → 41 961.0 mm²) where its sample count quarters. Later passes drift further — **5.02 %, 6.43 %** and **4.94 %, 22.75 %** — because each pass removes its own polished inliers within a millimetre band and that removal is resolved on the grid, so the coarser run removes a slightly different set. Every drift is an order below the 4× the sample count moves by.

**The rider closes.** The pass the old floor cut enters with 155 and 180 samples on the halved grid, below the 500 the count floor was and above the 122 and 125 the area floor expresses itself as there. `planeCandidateCount` is now **3 → 3** on both captures, and the plane at the food is unchanged: 0.835 mm and 0.037 mm of movement, the figures Decision 35 recorded.

### Rationale

The choice between denominations is a question about what the floor is *for*, and the two questions it could be asking have different answers. If it is a statistical floor — enough draws for RANSAC — a sample count is right and the grid-dependence is correct behaviour, as it is for `ringMinSamples`, whose 200 comes from binomial separation per sector (Decision 20) and whose refusal at 64×48 is the transfer's legitimate floor. But the residue floor does not ask that: `ccRansac` already guards its own minimum at `LiDARPlaneFitter.minPoints`, and `admissibility` decides whether whatever the pass finds is usable. What is left for this constant to ask is physical — is there enough **surface** left that another pass could find something — and surface is area.

Holding the value while changing its units is the discipline Decision 37 records and `minResidueSamples` itself already carried from Decision 32: the corpus brackets this constant, it does not set it, so a change of denomination must not smuggle in a change of behaviour. 1691 mm² is chosen the same way 44 mm was — the largest whole unit at or below the shipped value on every corpus capture — so the bar is never stricter than the one it replaces.

The repair did not wait for the capture session because the corpus already demonstrates the failure, on the committed slices, at a resolution one halving down. The session will supply captures at whatever grid the device gives; a floor that means a different physical thing on each of them is a floor that cannot be set by them.

### Alternatives Considered

- **Record the grid-dependence and leave the constant in samples** - Decision 35's own resolution: note that `planeCandidateCount` must be read as a property of resolution and move on - Rejected for the reason Decision 37 gives: documenting a quantity that does not transfer preserves the defect and leaves Req 5.1's transfer claim carrying an exception. The field is persisted, so the exception would have to be carried by every future reader of the estimation record, not just by this design.
- **Denominate the floor as a fraction of the annulus** - The residue-to-annulus ratio is also grid-stable (0.316/0.334 and 0.224/0.215 entering pass 2) and needs no `mmPerPx` - Rejected because it makes the floor depend on food size: a large plate has a large annulus, so the same physical scrap of surface would be sufficient on a small capture and insufficient on a big one. Area is the quantity the question is actually about.
- **Derive the value from `minAcceptedExtentMm` rather than holding it** - A candidate is admissible only if its component spans 44 mm in both axes, so a residue smaller than 44² = 1936 mm² looks like it cannot produce one - Rejected because the bound is not sound: a component whose bounding box is 44 × 44 mm need not fill it — a diagonal run of ~24 depth pixels spans the same box — so a residue below 1936 mm² can still yield an admissible candidate. That 1691 mm² sits just under 1936 mm² is a corroboration that the floor is permissive relative to the extent bar, not a derivation of it.
- **Set the floor at the measured ceiling of 2013 mm²** - The corpus shows exactly where a floor starts costing a pass - Rejected as the circularity Req 3.7 forbids, in the same shape Decision 32 rejected raising it to 1200 samples: 2013 mm² is where a floor begins cutting passes the corpus produces, not where a pass stops being worth running.

### Consequences

**Positive:**

- Req 5.1's second rider closes: `planeCandidateCount` is 3 → 3 across a 2× halving where it was 3 → 2, so a persisted field now records a property of the scene.
- The bracket becomes physical — bounded above at **2013 mm²** — where 581 samples meant different physical areas on the two captures and nothing at all on another grid.
- Only one Decision 35 rider is left, the ring's sample floor, and that one is correct as it stands: `ringMinSamples` is a statistical requirement per sector, so its refusal at 64×48 is the transfer's honest resolution floor rather than a denomination defect.
- The measurement distinguishes what the grid does to a fixed set of surface (0.3 %, 1.2 %) from what sequential inlier removal does on top of it (up to 22.7 %), which is a figure any future change to the removal band can be checked against.
- N5k's 3.389× pixel-density gap is neutralised for this constant as well as for the extent bar, before Bucket C rather than during it.

**Negative:**

- The constant is still `[owed]`. Re-denominating it does not set it, and 1691 mm² remains a value traced to a chosen sample count rather than to any measured property of a surface worth another pass.
- The margin above the floor narrows on coarser grids: the smallest residue clears it by 1.86× natively and **1.44×** at half resolution, so the halved grid is closer to losing the pass than the native one is.
- A third pass now runs on 155 samples where it previously ran on 581. Nothing in the corpus is decided by it — both third-pass candidates are rejected on `extent` and `supportFraction` — but a RANSAC pass over 155 samples is a weaker draw than the count floor used to permit, and no capture in hand exercises what it produces.
- `minResidueAreaMm2` needs a conversion where `minResidueSamples` was directly comparable to `residueCount`, so a reader of `extractCandidates` has one more indirection between the constant and the guard.

### Impact

`MedataCore/Sources/SupportPlane/SupportRegion.swift` (`minResidueAreaMm2`, `minResidueSamples(mmPerPx:)`, `extractCandidates`, the `PlaneCandidate.residueCount` comment), `MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`residueFloorIsBoundedFromAboveOnly` restated in mm², the new `residueAreaTransfersAcrossAGridHalving`, and the candidate-count assertion in `planeTransfersAcrossADepthGridHalving`, which changes sense), `design.md`, `docs/agent-notes/support-plane-fit.md` and task 26's detail. Shipped behaviour is unchanged on the corpus by construction; on a coarser grid the pass count rises to what the native grid already produced.

---

## Decision 39: The smear-tracking inner radius is measured and refused, and the envelope stays a range bound

**Date**: 2026-08-06
**Status**: accepted

### Context

Decisions 37 and 38 each found a bar whose denomination made it read the depth grid rather than the scene, and repaired it by converting through `mmPerPx`. One instruction of the same shape was still outstanding, and it was written as an obligation rather than a proposal. `ringInnerMm = 8` stands for ARKit's ~4 px depth smear at the food boundary, and Decision 29 measured that the smear spans 7.45 mm and 7.36 mm on the two committed slices — inside 8 mm, but by under 8 %. Since a smear is a fixed count of pixels, `smear_mm = 4z/f_d`, so 8 mm covers capture range only to about 365 mm. Decision 29 concluded, and both `SupportRegion`'s own comment and the `prerequisites.md` item of the same name repeat, that the radius "must become `max(ringInnerMm, 4 × mmPerPx)`" before any capture beyond that range is trusted.

Taken at face value this is the third instance of the Decision 37/38 pattern and the last one available: a bar that means a different physical thing on a different grid, with the conversion already computed in `prepare` and used by every other radius. The two prior repairs each held their value while changing their units, and each closed a rider on Req 5.1. This one was expected to do the same.

It does not, and the difference is what `mmPerPx` is made of. `mmPerPx` is `z/f_d`; coarsening the grid divides f_d exactly as increasing the range multiplies z, so the quantity cannot tell the two apart. Only one of them moves the smear. A coarser grid subsamples a map ARKit has *already* smoothed, so the physical smear is unchanged while `4 × mmPerPx` doubles.

### Decision

**The repair is rejected and the instruction is withdrawn.** `ringInnerMm` stays at a fixed 8 mm with no `mmPerPx` term. The envelope it carries is restated as what it is — a **range** bound of `ringInnerMm × f_d / 4`, computed from the corpus at **364.1 mm** and **366.4 mm** — and left to the capture session rather than paid for in code.

**The session gains one recording requirement.** `prerequisites.md` now asks for the capture range alongside the plate diameter, the surface material and the depth resolution it already asks for. This is the cheapest of the four to record and the only one with a hard bound already measured against it.

**The measurement is committed** as `smearTrackingInnerRadiusCollapsesTheRing` and `smearEnvelopeIsARangeBoundTheCorpusNearlyReaches`, so the rejection is reproducible and the instruction cannot be re-derived from the same reasoning a third time.

### Rationale

The measurement is one-sided at corpus range and decisive one halving down. Natively the repair is a no-op — `max` picks the constant on both captures, because the smear is 7.45 and 7.36 mm against 8 — so nothing in the corpus argues *for* it either. At 128 px the smear-tracking radius reads **14.9 mm** and **14.7 mm** for a physical smear still near 7.4 mm, and the cost is structural before it is statistical: the radius eats 6.9 mm of a 17 mm ring, so the three bands it leaves are **3.37 mm and 3.43 mm wide against depth pixels of 3.73 mm and 3.68 mm**. Each band is narrower than one pixel. Decision 14 resolved the ring radially in order to tell the surface immediately beside the food from the one beyond it, and a band the grid cannot resolve cannot make that distinction whatever its samples total.

What the sample counts then do is confirm it. `1785135663727` loses ring feasibility outright, its inner band falling to **166** against `ringMinSamples = 200`, and `1785901032716` clears the floor by nothing at all at exactly **200**. Two captures of the same scene type, taken 2 mm of range apart, landing either side of the bar is the signature of a quantisation artefact rather than of support. Both clear it comfortably under the shipped radius, at [313, 292, 299] and [322, 361, 323] — and that is the grid on which Req 5.1's documented 2× transfer envelope rests, where the plane moves 0.835 mm and 0.037 mm. Obeying the instruction would spend a measured transfer on a smear the grid does not have.

Refusing it leaves the range envelope open, and that is the honest place for it. `f_d` is the sensor's and does not vary; `z` is the photographer's and does. The corpus stands at **93.1 %** and **92.0 %** of its own envelope on two captures framed as tightly as flat bread on a plate allows, so the headroom is under 8 % on the most favourable scenes the feature has. A session that shoots one plate from a little further back crosses it, and nothing in the record would say so — which makes recording the range a prerequisite of closing the constant rather than a nicety.

This also draws the line the previous two decisions did not have to. Decision 38 already noted that `ringMinSamples`'s refusal at 64×48 is "the transfer's honest resolution floor and not a denomination defect", because a statistical requirement per sector is legitimately grid-dependent. The same test applies here and gives the same answer for a different reason: `ringInnerMm` is not grid-dependent at all, it is *range*-dependent, and `mmPerPx` is the wrong instrument because it conflates the two. Not every constant that can be multiplied by `mmPerPx` should be.

### Alternatives Considered

- **Implement `max(ringInnerMm, 4 × mmPerPx)` as Decision 29 instructed** - Take the third instance of the Decision 37/38 pattern and close the envelope in code - Rejected on the measurement: it is a no-op at corpus range and costs ring feasibility on one of two captures at 128 px, leaving three sub-pixel bands on both. It buys nothing measurable and spends Req 5.1's 2× transfer envelope.
- **Refuse the fit outright when `4 × mmPerPx` exceeds `ringInnerMm`** - Make the envelope a feasibility guard rather than a moving radius, in the shape Decision 38 endorsed for `ringMinSamples` - Rejected because it refuses on the same conflated quantity: it would reject the 128 px grid, where the plane demonstrably transfers within 0.9 mm and all three bands are full, and `gridTransferRefusesBelowTheRingSampleFloor` already asserts that fit as feasible. A guard that fires on the transfer test's passing case is measuring the wrong thing.
- **Key the envelope on the native grid width rather than on `mmPerPx`** - Recover `z` by assuming 256×192 and compare that against the envelope, so range and resolution are separated - Rejected as an assumption dressed as a measurement. `SupportRegion` sees one depth map and cannot know whether a coarse one is a subsampled ARKit frame or a coarser sensor's native output; hard-coding 256×192 would break exactly the N5k grid Decision 37 went out of its way to neutralise.
- **Raise `ringInnerMm` to cover a longer range unconditionally** - Set it at, say, 12 mm so the envelope reaches ~545 mm - Rejected because it is the circularity Req 3.7 forbids, applied to a `[measured]` constant. Nothing measures a scene that needs 12 mm; it would narrow the ring by a quarter on every capture in hand to buy an envelope no capture has ever approached, and `ringOuterMm` is itself `[owed]` against a restated rule (Decision 33), so the ring's width is not a free parameter.
- **Leave the instruction standing and record the doubt** - Note in the decision log that the repair may be wrong and defer - Rejected because the instruction appears in three places as a "must", and the next session to look for a Decision 37/38-shaped repair would find it and implement it. The measurement exists and settles it; leaving it open invites the wrong work.

### Consequences

**Positive:**

- An instruction that reads as an obvious repair, and would have cost Req 5.1's measured 2× transfer envelope, is refused on measurement rather than followed on pattern.
- The envelope is now a computed figure — `ringInnerMm × f_d / 4`, 364.1 mm and 366.4 mm — asserted against the corpus rather than a "≈ 365 mm" quoted in prose across three documents.
- The corpus's headroom is stated as a fraction, 93.1 % and 92.0 %, which says the constant is near its bound in a way "inside 8 mm on both" does not.
- The capture session gains a recording requirement that costs one number per capture and is the only thing that can close the envelope.
- The limit of the `mmPerPx` conversion is now recorded. Decisions 37 and 38 established it as the repair for grid dependence; this establishes that it cannot repair range dependence, and says why.

**Negative:**

- `ringInnerMm` remains correct only below ~365 mm, and the feature ships with that gap open. Nothing in the shipped path detects a capture beyond it or marks the ring measure as contaminated.
- The rejection rests on two captures 2 mm of range apart, both flat bread on a white plate. The sub-pixel-band argument is structural and does not depend on them, but the 166-against-200 figure that makes it concrete does.
- One more thing is added to a capture session that already carries plate diameter, food placement, surface material, depth resolution, weighed mass, class and vessel per capture.
- A future device with a different f_d moves the envelope, and nothing recomputes it outside the test.

### Impact

`MedataCore/Sources/SupportPlane/SupportRegion.swift` (the `ringInnerMm` comment, which stated the repair as required), `MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`smearTrackingInnerRadiusCollapsesTheRing`, `smearEnvelopeIsARangeBoundTheCorpusNearlyReaches`, and the `geometry(_:decimation:)` and `bandCounts(geometry:innerMm:)` helpers), `prerequisites.md` (the `ringInnerMm` item and the capture-recording list), `design.md` (Stated limits, Req 2.5) and task 26's detail. **No shipped behaviour changes at any grid or range** — the decision is to leave a constant alone, and the measurement is what says that is the right thing to do.

---
## Decision 40: The sector rule is stated over failing sectors, and its bar is inherited rather than owed

**Date**: 2026-08-06
**Status**: accepted (settles Decision 30's proposal; supersedes its disposition, not its finding)

### Context

Task 26's sector trio — `ringSectorCount`, `sectorSupportMin`, `minSupportingSectors` — is blocked on two things at once. Captures 1–6 are one. Decision 30 is the other: it measured that the supporting-sector count takes `|height|`, so a correct plane whose ring has run off the plate and a table plane with part of its ring still on the plate both score **5 of 8**, and no `minSupportingSectors` separates them. It proposed carrying the sign, declined to state a rule, and gave one reason for declining — "a rule for rejecting on signed sectors needs a threshold, and that threshold has the same evidence problem as every other `[owed]` constant".

Every other remaining item in task 26 waits on the capture session or on model-production Bucket C. This proposal is the one blocker that is a design question rather than a missing scene, and the corpus already holds both of the failure modes it is about — which is how Decision 30 found them. So the question of whether a signed rule needs a threshold of its own is answerable now.

Decision 33 also arrived after Decision 30 and bears on it. The support margin is 4 mm in the tightest sector of both captures, the plate ends inside the ring in five of eight directions, and only 4 of 8 sectors reach the inner band's 13.7 mm. A low supporting count is therefore in part a statement about plate size, which is exactly the reading the sign is needed to separate from a wrong plane.

### Decision

The sector rule is: **a failing sector — one below `sectorSupportMin` — whose signed inner-band median exceeds `+ringBandMm` is a *crossed* sector, and a candidate is rejected when more than `maxCrossedSectors` of its sectors are crossed.** A failing sector reading below `−ringBandMm` is an *escaped* sector and is not grounds for rejection: the support surface ended, which is plate geometry, not a wrong plane.

The magnitude bar is `ringBandMm`, `[inherited]` from `LiDARPlaneFitter.inlierBandMm` and already the bar that decides which samples in those same sectors count as supported. **No new millimetre constant is created.** `maxCrossedSectors` is a new `[owed]` count, bracketed **0…2** by the corpus and set by prerequisites capture 6.

Shipped code is unchanged. `SupportRegion.ringStatistics` still computes the unsigned count and `admissibility` still reads `minSupportingSectors`; the rule above is recorded with its measured basis and lands with the capture that sets its count, because shipping it now would mean asserting `maxCrossedSectors`, which is what Req 3.7 forbids for exactly these constants.

### Rationale

Measured over all six candidate planes on the two committed captures, the sign classifies cleanly and the two intended candidates are pure:

| Capture | Candidate | Supporting | Failing-sector medians | Crossed | Escaped |
|---|---|---|---|---|---|
| `1785135663727` | plate top (ring median −0.93 mm) | 5 of 8 | −6.79, −32.56, −9.68 mm | 0 | 3 |
| `1785901032716` | table (ring median +3.04 mm) | 5 of 8 | +16.60, +19.80, +18.02 mm | 3 | 0 |

The supporting counts agree exactly, which is Decision 30's premise; the crossed counts are 0 and 3. Neither capture's intended candidate mixes signs.

The threshold objection fails on the magnitude axis because the separating window is wide and the design already owns a bar inside it. The plate candidate's highest failing median is **−6.794 mm** and the table candidate's lowest is **+16.603 mm**: any bar in that **23.397 mm** window separates them, and `ringBandMm = 5` sits 11.794 mm above the floor and 11.603 mm below the ceiling — near the centre, and not chosen to be there.

Restricting the rule to *failing* sectors is what earns that. Applied to every sector, the window is the plate candidate's highest median of +3.846 mm against the table candidate's lowest crossed median of +5.974 mm — **2.128 mm** wide, a tenth of the other, with `ringBandMm` inside it by about a millimetre on each side. A bar surviving in a 2 mm window on two captures is being fitted to the corpus; one surviving in a 23 mm window is being inherited. The `sectorSupportMin` gate is therefore doing real work in the rule and is not redundant.

The rule is also the per-arc form of a guard the design already has and already justifies. `ringMedianMaxMm = 5` is the signed whole-ring admission bar Decision 22 restored precisely because "the support fraction is unsigned and cannot separate a plane above the ring from one below it". On the table candidate that whole-ring guard reads **+3.04 mm** and does not fire — inside ±5 — while the same statistic at the same bar, computed per arc, reads +16.6, +19.8 and +18.0 in three sectors. This is Decision 18's silent-failure case measured rather than argued: an aggregate median of approximately zero over a ring that has crossed.

The count stays owed because the corpus bounds it two-sidedly but loosely — 0 admits the plate candidate, and anything above 2 admits the table one, so 0, 1 and 2 all survive. Three values is a bracket, not a derivation. Capture 6, food filling a small plate to within ~10 mm of the edge, is the scene that produces a correct fit with several genuinely escaped sectors, and it is what says how many crossed sectors a correct fit can carry.

Not implementing follows from the same place. The rule needs one constant, that constant is owed, and Req 3.7 bans shipping it asserted. What the session needs in order to set it — the signed per-sector medians — the measurement pass already dumps, so nothing is gained by moving the statistic into `RingStatistics` before there is a count to compare it against, and Decision 30's cost note stands: it would widen a persisted Req 6.4 field.

### Alternatives Considered

- **Accept Decision 30 and implement the guard now, choosing `maxCrossedSectors`** - Replace `minSupportingSectors` with the crossed-sector ceiling in this task, since the corpus shows the direction is right - Rejected because choosing among 0, 1 and 2 is inventing evidence, and Req 3.7 names the sector constants specifically. It would also make the plate candidate admissible on a capture with no weighed ground truth, which is the false positive Decision 31 committed a fixture to trap.
- **State the rule over all sectors rather than failing ones** - Simpler: drop `sectorSupportMin` from the rule and count any sector whose median exceeds `+ringBandMm` - Rejected on the measured window. It separates the corpus (0 against 4) but only within 2.128 mm, so `ringBandMm` would be surviving by luck rather than by inheritance and the bar would become owed after all.
- **Reject on sign alone, with no magnitude bar** - A failing sector reading positive is crossed, whatever its size - Rejected because it has no noise floor. Per-sample σ on a flat surface measures 3.44 mm and 6.98 mm (Decision 29), so a sector median a millimetre above zero is not evidence of anything, and the rule would fire on noise wherever a sector fails for coverage reasons.
- **Leave Decision 30 proposed until the captures arrive** - Change nothing; let the session settle the design question and the constants together - Rejected because it spends the session's evidence twice. The session would arrive at a measure whose shape was still unfixed, and the magnitude question it would then answer is one the corpus in hand answers already.
- **Keep `minSupportingSectors` and add the crossed-sector ceiling beside it** - Two sector guards, one floor and one ceiling - Rejected as unreachable rather than wrong: Decision 33 measured that only 4 of 8 sectors reach the inner band's 13.7 mm on either capture, so a floor of 6 cannot be met by plate geometry before support is consulted at all. Retaining it would keep a bar no capture can clear.

### Consequences

**Positive:**

- The sector trio's non-capture blocker is removed. Task 26's detail said the trio waits on captures 1–6 *and* on Decision 30's proposal; it now waits on captures only.
- One axis of the rule costs no new constant. The magnitude bar is inherited from `ringBandMm` with 11.6 mm of headroom on each side, so the capture session has one count to set rather than a count and a threshold.
- The rule is stated, so capture 6 has a defined quantity to produce rather than a proposal to adjudicate, and the measurement pass already dumps the statistic it needs.
- Decision 18's silent-failure case is measured end to end for the first time: an aggregate ring median of +3.04 mm — inside `ringMedianMaxMm` — over three sectors reading +16.6 to +19.8 mm.
- Applying the rule across all six corpus candidates rather than the two intended ones shows it is not degenerate: one plane reads 6 crossed and 0 escaped, one reads 0 and 7, and one is genuinely mixed at 2 and 4.

**Negative:**

- Req 3.6's guard still ships in its blind form. The shipped `minSupportingSectors = 6` is both asserted and, per Decision 33, unreachable, and this decision does not change that — it records what will replace it.
- One `[owed]` constant is traded for another. `minSupportingSectors` and `sectorSupportMin` do not leave the list, and `maxCrossedSectors` joins it; the net count of owed sector constants rises until capture 6 arrives.
- The classification rests on two captures and six planes, both captures flat bread on a white plate. The sign separation is 23 mm and unambiguous, but "no correct fit carries a crossed sector" is asserted of scenes the corpus does not contain — a rimmed plate is the obvious counter-case, where a correct plane's ring reaches a rim that is genuinely above it, and that is capture 3/4's scene rather than capture 6's.
- Implementing later means `RingStatistics` and the Req 6.4 persisted fields widen after task 12 settled them, as Decision 30 noted.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`failingSectorSignSeparatesWhatTheCountCannot` and the `SectorSigns` helper), `MedataCore/Sources/SupportPlane/SupportRegion.swift` (the sector-trio comment), `design.md` (the owed-numbers section and the `SupportRegion` sketch), `prerequisites.md` (capture 6's second job), `decision_log.md` (Decision 30's status) and task 26's detail. **No shipped behaviour changes**: no constant's value moves and no guard is rewired.

---

## Decision 41: The committed scenes bound six owed constants, and on one they contradict the corpus

**Date**: 2026-08-06
**Status**: accepted

### Context

`prerequisites.md` has carried one open item since before task 8 that is explicitly **not** a hardware gate: "set the guard constants before task 8 hard-codes them", flagged because `tasks.md` orders task 8 — `fitFoodSupportPlane`, which carries every threshold — ahead of task 26, so "the numbers get baked into code and tests before anything measures them". Task 8 shipped long ago, so the item can no longer be answered by reordering. It is the last item on the list that no capture and no Bucket C run unblocks.

What replaced the reorder was a provenance discipline: every `SupportRegion` constant is annotated `[derived]`, `[measured]`, `[inherited]` or `[owed]`, Req 3.7 bans shipping the sector constants asserted, and the regression slices were built to assert only *named* planes so that "nothing in it moves when task 26 sets the `[owed]` constants" (design, §Regression fixtures). That covers the slices. It says nothing about the twenty-eight references to owed constants in `SupportRegionSelectionTests`, `SupportRegionRingTests`, `SupportRegionCandidateTests` and `PlateTopSupportPlaneTests`.

Those references are all **symbolic** — `SupportRegion.ringSupportMin`, never a literal — which looks like insulation and is not. Two shapes hide behind it. A test that expresses its *input* in terms of the constant (`extentMm: minAcceptedExtentMm - 1`) tracks it wherever it goes. A test that fixes a synthetic scene and asserts the scene's *measured* value against the constant flips the moment the constant crosses that value. `SupportRegionSelectionTests` says so in prose — "the window in which the aggregate passes and the sectors fail is therefore narrow, and this scene sits inside it by construction" — without ever measuring how narrow, or against what.

### Decision

The committed suite is recorded as a **second, independent source of bounds** on the owed constants, measured rather than assumed, and is now the binding constraint on three of them. `committedScenesBoundTheOwedConstants` computes, per constant, the interval over which every committed assertion keeps its verdict:

| Constant | Suite interval | Corpus bracket | Which binds |
|---|---|---|---|
| `ringSupportMin` | ≤ **0.676** | none — needs a matte capture (Decision 29) | suite (the only ceiling that exists) |
| `minSupportingSectors` | **6…7** | ≤ **5** (Decision 33) | **they contradict** |
| `bandStepMaxMm` | **0.024…9.288** mm | no floor at all (Decision 34) | suite (the only floor that exists) |
| `supportVisibilityMin` | ≤ **2.667** | ≥ 0.246 (Decision 34) | two-sided for the first time |
| `foodEnvelopeMinMm` | **−6.758…8.233** mm | ≤ 25.793 mm (Decision 34) | **suite, 3.1× tighter** |
| `escapeBandMm` | ≥ **14.868** mm | reaches +5.750 mm (Decision 34) | **suite, 2.6× higher** |

No constant's value moves and no shipped code changes. What changes is that the capture session now has to satisfy two constraint sets rather than one, and one of the two owes a scene change.

### Rationale

A scene bounds a constant only where a committed assertion would change verdict, which is not the same as where the scene happens to satisfy the guard. The bowl fails almost every guard, but the only assertion made about it is on its inner→mid step, so it caps `bandStepMaxMm` and bounds nothing else. Encoding participation per assertion rather than per scene is what makes the intervals real; the first cut of this measurement tagged each scene with the one guard it exists to fire and produced nonsense — a ceiling of 0.000 on `ringSupportMin`, an empty sector interval — because the bowl and the covered well were counted as passing guards no test asks them to pass.

The eight scenes and what each is required to do:

| Scene | Fraction | Sectors | Inner→mid | Visibility | Envelope | Annulus | Required |
|---|---|---|---|---|---|---|---|
| plate above table | 1.000 | 8 | 0.021 | 4.016 | 8.242 | −19.753 | fit succeeds |
| flat surface | 1.000 | 8 | 0.024 | 8.188 | 8.242 | 0.005 | fit succeeds |
| rim in the outer band | 1.000 | 8 | 0.021 | 2.667 | 8.242 | 14.868 | fit succeeds |
| overhanging food | 0.676 | 7 | −0.024 | 2.704 | 8.233 | −19.857 | fit succeeds |
| food across the plate edge | 0.681 | **5** | 0.009 | 5.626 | 28.242 | 0.171 | every guard passes, verdict `.sectors` |
| rim in the mid band | 0.770 | 8 | 14.923 | 1.309 | 8.242 | 14.950 | verdict `.bandStep` |
| bowl | 0.000 | 0 | 9.288 | 0.376 | 8.242 | 48.539 | step exceeds the bar |
| fully covered well | 1.000 | 8 | 0.018 | 3.835 | **−6.758** | −0.054 | envelope below the floor |

**The contradiction.** Decision 33 measured that the plate ends inside the 8–25 mm ring in five of eight directions on both captures, so a real intended candidate scores **5 of 8** and `minSupportingSectors` has to come down to admit it — Decision 40 records the same figure and calls a floor of 6 "unreachable by plate geometry before support is consulted at all". The suite's floor is **6**, and it is 6 for a reason that is not arbitrary: the silent-failure scene the sector guard exists to reject *also* scores 5. Both the case the guard must admit and the case it must reject sit at the same count, which is precisely Decision 30's finding — the unsigned count cannot separate them — now showing up as a test-suite constraint rather than a corpus one. No value of `minSupportingSectors` satisfies both, so the session cannot set this constant without the scene moving with it.

**The two the suite binds tighter.** `foodEnvelopeMinMm`'s corpus ceiling is 25.793 mm, from the intended candidate's own envelope; the suite's is **8.233 mm**, from the overhanging-food scene, 3.1× lower. `escapeBandMm`'s corpus evidence tops out at +5.750 mm; the suite floors it at **14.868 mm**, from the rim-in-the-outer-band scene whose annulus median sits on the rim. A session setting either against captures alone would land inside the corpus's bracket and outside the suite's, and would discover this only when the suite went red.

**The two the suite bounds where the corpus could not.** Decision 29 concluded `ringSupportMin` "cannot be derived until a matte-surface capture characterises the spread" — the suite supplies a ceiling of 0.676 regardless, from the overhanging-food scene, which the shipped 0.6 clears by 0.076. Decision 34 found every corpus inner→mid step to be a fall, so the corpus gives `bandStepMaxMm` no floor at all — the suite gives 0.024 mm, and a ceiling of 9.288 mm from the bowl, making it two-sided for the first time.

The measurement recomputes the corpus figures from `Self.measurements` rather than quoting Decisions 33 and 34, and reproduces 25.793 mm and +5.750 mm exactly, so the two constraint sets are compared on one run rather than across documents.

### Alternatives Considered

- **Loosen the silent-failure scene now so the sector interval admits 5** - Move `foodAcrossPlateEdge`'s `edgeOffsetPx` until the scene scores 4 or fewer, clearing room for `minSupportingSectors = 5` - Rejected because it fixes the symptom in the wrong place. Decision 40 already settled that the unsigned count is the wrong measure and the crossed-sector rule replaces it; re-tuning the scene to prop up a guard that is being retired spends effort on both and buys nothing the rule does not.
- **Treat the suite bounds as advisory and let the session set constants from captures alone** - Record the intervals in the decision log and fix the tests afterwards if they break - Rejected because it inverts the evidence. A committed assertion that a correct fit is admitted is a claim about the feature, not scaffolding; discovering the conflict when the suite goes red would put the session under pressure to change whichever side is cheaper rather than whichever side is wrong.
- **Delete the coupled assertions so the constants are free** - Strip the `>= SupportRegion.ringSupportMin`-style assertions from the scene tests, leaving only the verdict assertions - Rejected because those assertions are what makes the silent-failure test mean anything: "every guard except sectors reads healthy" is the whole content of Decision 18's case, and without them the test only says a scene is rejected, not that it is rejected for the reason that matters.
- **Assert the intervals without comparing them to the corpus** - Report the suite's brackets and stop - Rejected as half the finding. Three of the six only matter because they sit on the other side of the corpus's bracket, and that is not visible from either source alone.

### Consequences

**Positive:**

- The last non-hardware item on `prerequisites.md` is answered, and answered with a measurement rather than a reorder.
- The capture session gains ceilings for two constants the corpus could not bound at all (`ringSupportMin`, `bandStepMaxMm`'s floor), so fewer constants arrive at the sitting completely unbounded.
- The `minSupportingSectors` conflict is found **before** the sitting rather than after, when its resolution would compete with the session's own evidence.
- The comparison is reproducible in one run: the corpus figures are recomputed, not quoted, so the two constraint sets cannot drift apart in the documents.
- The measurement is written against the assertions rather than the scenes, so a test that stops asserting a guard automatically stops bounding its constant.

**Negative:**

- Six owed constants now carry two brackets each, and the documents have to keep both current — a maintenance surface that did not exist before.
- The intervals are properties of eight synthetic scenes at one range on one grid, so they are not evidence about the world in the way the corpus is. They constrain what the session may set without also editing tests; they do not say what is correct.
- The `minSupportingSectors` collision is recorded, not resolved. ~~Task 26 gains a dependency — the scene must move when the crossed-sector rule lands — that Decision 40 did not anticipate.~~ **Superseded by Decision 43**: measured against the same eight scenes, the crossed-sector rule's joint interval is 0…2 where the count's is empty, so no committed scene moves when the rule lands. The collision is a property of the unsigned count alone.
- `bandStepMaxMm`'s suite floor of 0.024 mm is nearly vacuous, being sensor noise on a flat scene; it is a floor in form more than in force.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`committedScenesBoundTheOwedConstants`, `SceneReading` and `sceneReadings`), `design.md` (the owed-numbers section), `prerequisites.md` (the "during implementation" item, now answered) and task 26's detail. **No shipped behaviour changes**: no constant's value moves, no guard is rewired, and no existing test is edited.

---

## Decision 42: The fallback rate is a readout of the owed constants, and an inherited bar is the only thing between a 0 % rate and Decision 18's failure

**Date**: 2026-08-06
**Status**: accepted

### Context

Req 4.5 asks for a fallback rate above which this feature counts as a defect rather than a success, "since a change where every capture falls back satisfies 4.1–4.3 while delivering nothing". `prerequisites.md` has carried the open question as a choice of **denominator**: N5k has none until model-production Bucket C (pre-checkpoint ingestion stamps every plate `mixture`, so `single_dominant: 0` and `fitFoodSupportPlane` never runs), and the device corpus is two captures, far too small for a percentage. Decision 36 put `fallbackPenalty` behind the same gate, because a penalty prices a mixture whose weight is this rate.

`SupportPlaneRegressionSliceTests` already records that both committed captures fall back today, and that every candidate rejection on both is on a constant marked `[owed]`. What nobody had measured is what the rate is a function OF. If it moves with the owed constants and with nothing else, then the denominator is not the first problem with Req 4.5 — a threshold stated before the constants are set grades the placeholders, which is exactly the circularity Req 3.7 forbids for the sector trio, arriving at Req 4.5 by another route.

### Decision

Req 4.5's threshold stays deferred, and the recorded reason is now the stronger one. On the corpus that exists the fallback rate takes **every value it can take** as the owed constants move, so it is recorded as a function rather than as a number, with two figures pinned: the rate the shipped placeholders produce, and the rate at the most permissive setting the owed constants could ever be given.

| Setting | Fallback rate | Plane selected |
|---|---|---|
| shipped placeholders | **1.000** (2 of 2) | none — both captures fall back |
| `minSupportingSectors` ≤ 5, all else shipped | **0.500** | `1785135663727` selects its plate top |
| every owed bar at its loosest | **0.000** | both captures select the candidate nearest Req 3.1's zero |

`ringMedianMaxMm` — `[inherited]` from `ringBandMm`, not owed — is what rejects every remaining candidate at the loosest setting, and it clears the closest of them by **0.338 mm**. No constant's value moves and no shipped code changes.

### Rationale

**The rate is a readout of the placeholders, not of the algorithm.** Swept alone with everything else shipped, `minSupportingSectors` produces `8→1.000 7→1.000 6→1.000 5→0.500 4→0.500 3→0.500 2→0.500 1→0.500 0→0.500`: one owed bar, crossing the 5 of 8 sectors Decision 33 measured as what a real intended candidate scores, halves the rate on its own, and nothing below 5 moves it again because a second owed bar (`ringSupportMin`) stands in front of the other capture. Set every owed bar as permissive as it could ever be and the rate is 0. A threshold asserted today would therefore be satisfied or violated by the placeholders alone, on captures that never changed.

**And the rate reaching zero does not cost a wrong plane.** At the loosest owed setting each capture selects the candidate whose inner-band median is nearest zero — **−0.521 mm** on `1785135663727` and **−1.023 mm** on `1785901032716` — which is Req 3.1's own signature of the surface the food rests on. So the geometry finds the right surface on both captures, nothing structural is wrong, and the whole distance between a 100 % fallback rate and a 0 % one is constants the committed suite currently contradicts (Decision 41).

**What holds the wrong planes out is not owed, and its margin is 0.338 mm.** Every candidate rejected at the loosest setting is rejected by `ringMedianMaxMm`, and the closest is the table candidate on `1785901032716` — Decision 40's crossed-sector case, three of its sectors reading +16.6 to +19.8 mm — whose inner band reads **5.338 mm against a 5 mm bar**, 6.8 % of it. That is the entire separation between this corpus at a 0 % fallback rate and the Decision 18 silent failure the feature exists to prevent. `ringMedianMaxMm` was never sized for that job: Decision 22 gave it the Req 3.2 signed-admission role, and it is `ringBandMm` reused. It is standing in for the sector guard by accident of arithmetic.

**The 0.000 is a bound, not a proposal.** On `1785901032716` the correct plane is selected there with support **0.362 over 2 of 8 sectors** — thinner than any bar the design would plausibly set, and rejected by the shipped 0.6 and 6 with room to spare. That capture's plate ends inside the 8–25 mm ring in five of eight directions (Decision 33), so its right plane is admissible only when the guards are effectively off. Read from the rate's side, this is the same finding: the corpus cannot simultaneously have a low fallback rate and meaningful guards, and only a capture whose plate extends further past the food can. That is what the session's plate-size variation is for.

**So Req 4.5's own denominator problem is real but second.** Both blockers now stand: there is no corpus that can carry a percentage until Bucket C, and the rate on the corpus that exists is not yet a measurement of anything. The `prerequisites.md` item stays open with both reasons rather than being closed on one.

### Alternatives Considered

- **Set the threshold from the device corpus now** - Take "below 100 %" or "below 50 %" as Req 4.5's bar, since both figures are measured - Rejected because either is met by lowering one owed bar and says nothing about correctness. A rate of 0.500 is reachable by setting `minSupportingSectors` to 5, which Decision 41 records the committed suite as forbidding; a bar that a forbidden setting satisfies is not grading the feature.
- **Close the prerequisites item by splitting Req 4.5 into an N5k rate and a device count** - The two-figure form that item has been carrying - Rejected as premature rather than wrong. It is still the defensible shape, but this measurement says the denominator is not the only blocker, and closing the item on half the reason would lose the other half.
- **Widen `ringMedianMaxMm` so the 0.338 mm margin is comfortable** - Raise the bar, or re-derive it against the table candidate - Rejected because nothing measured supports moving it and the direction is wrong besides. It is `[inherited]`, the corpus's per-sample σ straddles `ringBandMm` at 3.44 and 6.98 mm (Decision 29), and widening it would *weaken* the only guard currently doing this work. The correct repair is Decision 40's crossed-sector rule, which rejects that candidate on three crossed sectors rather than on a third of a millimetre.
- **Map the rate over all owed constants jointly as a feasible region** - Sweep the full product rather than one bar at a time - Rejected as more than two captures can carry: a two-capture corpus has exactly three possible rates, so a joint map would report structure the corpus does not contain.

### Consequences

**Positive:**

- Req 4.5's deferral now rests on a measurement rather than on the absence of a denominator, and the measurement is reproducible in one run.
- The feature is shown to be sound where it matters: at every owed setting that admits anything, both captures select the plane Req 3.1 identifies, so the remaining work is constants and not geometry.
- The 0.338 mm margin is on record. It is a concrete argument for implementing Decision 40's crossed-sector rule that does not depend on capture 6 — the rule replaces an accidental sub-millimetre separation with a signed one holding 11.7 mm on each side.
- Task 27's likely failure mode is stated in advance: under shipped constants a device capture of this kind records `.edgeBand`, so "confirm the reference recorded is `.foodSupport`" fails for constant reasons, not implementation ones.
- The parameterised guards are pinned against `SupportRegion.admissibility` at the shipped bars, so the sweep cannot drift into measuring a different guard set.

**Negative:**

- The corpus's headline figure is that the shipped feature falls back on 100 % of the captures it was built from — true, previously recorded only as a per-capture fact, and now unavoidable in the aggregate.
- A rate over two captures has three possible values, so the curve above is coarse by construction and the 0.500 step is one capture changing its mind.
- The 0.338 mm finding creates pressure to implement Decision 40's rule before capture 6 sets `maxCrossedSectors`, which Req 3.7 forbids. The tension is recorded, not resolved.
- `prerequisites.md` gains a second reason on an item that was already blocked, without moving it any closer to being answerable.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`OwedBars`, `admissible(_:bars:)`, `selection(_:bars:)` and `fallbackRateIsAFunctionOfTheOwedConstantsAlone`), `prerequisites.md` (the Req 4.5 denominator item, still open with a second reason), task 26's detail and task 27's, and `docs/agent-notes/support-plane-fit.md`. **No shipped behaviour changes**: no constant's value moves, no guard is rewired, and no existing test is edited.

---

## Decision 43: The crossed-sector rule clears both constraint sets where the count clears neither

**Date**: 2026-08-06
**Status**: accepted (discharges Decision 41's third negative consequence)

### Context

Decision 41 measured the committed suite as a second source of bounds on six `[owed]` constants and found one outright contradiction: `minSupportingSectors` is floored at **6** by the silent-failure scene the guard exists to reject and capped at **5** by what a real intended candidate scores on the corpus (Decision 33). It recorded the collision rather than resolving it, and drew a consequence — "the scene has to move when Decision 40's crossed-sector rule lands", a dependency task 26 did not previously carry.

Decision 42 then measured that the only thing keeping a wrong plane out of a 0 % fallback rate is `ringMedianMaxMm` clearing the table candidate by **0.338 mm** on a 5 mm bar, and called that "a concrete argument for implementing Decision 40's crossed-sector rule that does not depend on capture 6".

Both point at the same unasked question. The contradiction is a property of the unsigned *count*, not of the scenes: the count takes `|height|`, so the case that must be admitted and the case that must be rejected land on the same number (Decision 30). The scenes are unchanged. So the replacement rule can be measured against exactly the two constraint sets that broke the count — the same eight committed scenes and the same corpus candidates — before capture 6 exists, and the claim that a scene must move can be checked rather than assumed.

### Decision

`maxCrossedSectors` is recorded as bracketed **0…2 by the committed suite**, which is the corpus's own bracket unchanged. The joint interval is **0…2**, three admissible values, and no committed scene and no corpus candidate distinguishes them: every one returns the same verdict at 0, at 1 and at 2. The same two sources give the unsigned count a joint interval of **6…5** — empty.

**Decision 41's third negative consequence is withdrawn.** No committed scene has to move when the crossed-sector rule lands. The dependency was a property of the count it replaces.

The rule is still **not implemented**. The interval has three values, nothing in hand narrows it, and Req 3.7 bans shipping the count asserted. No constant's value moves and no shipped code changes.

### Rationale

The eight scenes read through Decision 40's rule, each at the plane its own committed test evaluates:

| Scene | Supporting | Failing-sector medians | Crossed | Escaped |
|---|---|---|---|---|
| plate above table | 8 of 8 | — | 0 | 0 |
| flat surface | 8 of 8 | — | 0 | 0 |
| rim in the outer band | 8 of 8 | — | 0 | 0 |
| overhanging food | 7 of 8 | −20.024 mm | 0 | **1** |
| food across the plate edge | **5 of 8** | +19.967, +19.947, +19.980 mm | **3** | 0 |
| rim in the mid band | 8 of 8 | — | 0 | 0 |
| bowl | 0 of 8 | +15.047 … +15.591 mm | 8 | 0 |
| fully covered well | 8 of 8 | — | 0 | 0 |

**The brackets.** Five scenes' committed assertions require the sector guard to pass; the largest crossed count among them is **0**, so the suite floors `maxCrossedSectors` at 0. One scene requires it to fire, at 3 crossed, so the suite caps it at **2**. That is 0…2, and the corpus is 0…2 as well — the plate-top candidate carries 0 crossed sectors and the table candidate carries 3. Unlike Decision 41's six constants, where the suite bound three of them *tighter* than the corpus, here it adds no constraint the corpus did not already impose. The capture session can set this constant against captures alone with no risk of turning the suite red.

**Why the collision does not recur.** On the corpus the admit case and the reject case both score 5 of 8 supporting sectors and are 3 apart in the crossed reading; in the suite the reject scene scores 5 as well while every admit scene scores 7 or 8. The count therefore has to be simultaneously ≤ 5 and ≥ 6 and the rule has to be simultaneously ≥ 0 and ≤ 2. This is Decision 30's finding discharged rather than restated: the statistic that separates the two cases is the one the rule reads.

**The escape half now has a committed scene.** `overhangingFood` is the first committed scene to produce a failing sector at all, and it reads **−20.024 mm** — an escape, which Decision 40's rule declines to reject on. Until now the escape reading was exercised only by `1785135663727`'s plate top on the corpus. A rule whose non-rejecting half fires on no test is a rule half-checked.

**The margin the rule replaces.** At the loosest admissible ceiling the table candidate is rejected by 3 crossed sectors against 2 — a margin of one whole sector, and of three at `maxCrossedSectors = 0`. Decision 42's 0.338 mm on a 5 mm bar is 6.8 % of an inherited constant sized for a different job.

**What the agreement is not.** `foodAcrossPlateEdge` is authored as "the geometry of capture `1785901032716`", so both ceilings come from one physical situation modelled twice, and their agreement at 3 is not two independent measurements. The floor of 0 is the independent part — five synthetic scenes and one real candidate. The finding does not rest on independence: what it says is that the *same* evidence which is infeasible under the count is feasible under the rule.

**And one limit stands.** Decision 40's stated blind spot is a rimmed plate where a correct plane's ring reaches a rim genuinely above it. The suite has two rimmed-plate scenes and neither exercises it — both read 8 of 8 supporting and no failing sector, because their rims never reach the inner band the sector median is computed over. Prerequisites captures 3 and 4 remain the only source for that case, and the suite's silence on it is now measured rather than assumed.

### Alternatives Considered

- **Implement the rule now at `maxCrossedSectors = 0`** - Both constraint sets floor it at 0, so 0 is the one value both sources reach directly - Rejected because floors and ceilings are not evidence of a value. All three of 0, 1 and 2 return identical verdicts on everything in hand, so choosing 0 is choosing the end of a bracket, which is what Req 3.7 names these constants to prevent. Capture 6 exists to say how many crossed sectors a *correct* fit can carry, and no scene in hand carries one.
- **Move `foodAcrossPlateEdge` now so `minSupportingSectors = 5` becomes feasible** - Decision 41's own first alternative, revisited - Rejected on the same ground and now with a measurement behind it: the collision is not in the scene, and the rule that replaces the count clears the scene untouched. Editing it would repair a guard being retired and lose the corpus's own geometry from the suite.
- **Record the suite bracket without comparing it to the count's** - Report 0…2 and stop - Rejected as half the finding. That the interval is non-empty matters only against the fact that the other formulation's is empty on the same eight scenes; neither number says it alone.
- **Extend a rimmed-plate scene until its rim reaches the inner band, closing Decision 40's blind spot in the suite** - Author the counter-case rather than wait for captures 3/4 - Rejected because it would invent the evidence the capture is for. Where a real rim sits relative to a real food boundary is exactly what is being measured, and a synthetic scene would set the constant to whatever radius was chosen for it.

### Consequences

**Positive:**

- Decision 41's third negative consequence is discharged with a measurement. Task 26 loses a dependency rather than gaining one, and no committed scene has to move.
- `maxCrossedSectors` is the first `[owed]` constant whose two constraint sets **agree exactly**, so the session sets it from captures with no suite interaction to track.
- The rule's escape half is exercised by a committed scene for the first time, at −20.024 mm.
- The verdict invariance is asserted rather than assumed: every committed scene and both corpus candidates are checked at each of 0, 1 and 2, so "the value cannot be narrowed by what exists" is a test result and not a reading of one.
- Decision 42's argument for the rule is strengthened in the currency it was made in — a one-sector margin at the loosest ceiling against 0.338 mm on a 5 mm bar.

**Negative:**

- Both ceilings trace to one physical situation, `foodAcrossPlateEdge` being a model of capture `1785901032716`, so the two sources are less independent than the two brackets look.
- The rule is now checked from two directions and still cannot ship, which sharpens the tension Decision 42 recorded rather than relieving it: the better guard stays out of the binary until capture 6.
- Decision 40's rimmed-plate blind spot is confirmed uncovered by the suite, so captures 3 and 4 acquire a job the documents had left implicit.
- The suite adds no constraint here, so unlike Decision 41 this measurement gives the capture session nothing it did not have — its value is in what it rules out.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`crossedSectorRuleIsBracketedByBothConstraintSets`, and `SceneReading` gains its `signs` member), `MedataCore/Sources/SupportPlane/SupportRegion.swift` (the sector-trio comment), `design.md` (the owed-numbers section and the Decision 40/41 paragraphs), `prerequisites.md` (capture 6, captures 3/4, and the suite-bracket table), `decision_log.md` (Decision 41's consequence), task 26's detail and `docs/agent-notes/support-plane-fit.md`. **No shipped behaviour changes**: no constant's value moves, no guard is rewired, and no existing test is edited.

---

## Decision 44: The sector count is the unit the other sector constants are denominated in, and Req 5.1 caps it at 11

**Date**: 2026-08-06
**Status**: accepted (re-denominates the brackets of Decisions 40, 41 and 43)

### Context

Every bracket this feature has recorded for the sector measure is a **count of sectors**: Decision 40's `maxCrossedSectors` 0…2, Decision 41's `minSupportingSectors` 6…7, Decision 43's empty joint interval 6…5. Each was read at `ringSectorCount = 8`, and none of them says so. `ringMinSamples = 200` is worse placed still — it is annotated `[measured]`, and its whole derivation is `ringSectorCount × 25`, so a constant marked settled takes an `[owed]` constant as its input.

Req 3.7 names three constants the design may not ship asserted — `ringSectorCount`, `sectorSupportMin`, `minSupportingSectors` — and the feature has treated them as three peers. Decisions 30, 40, 41, 42 and 43 all attacked `minSupportingSectors` and the rule that replaces it. Nothing has measured the count itself, and if the capture session moves it, every sector bracket in the documents is void.

The question is answerable without a capture: the committed rings can be re-cut into any number of equal arcs and re-read. `SupportRegion.sectorIndex` is one `atan2` and a bucket index about the food-mask centroid, so the same ring samples support any count.

### Decision

`ringSectorCount` is recorded as **bracketed 4…8, not set**, with a hard ceiling of **11** from Req 5.1's grid-transfer claim. It stays `[owed]`.

Every sector bracket already recorded is restated as **denominated in the count**: `maxCrossedSectors` 0…2 means 0…2 *at eight sectors*, and reads 0…0 at four and 1…2 at eleven. So the count must be fixed **before** the capture session, not read out of it alongside the constants it denominates.

Nothing is rewired and no value moves.

### Rationale

Both corpus captures' best candidates and all eight committed scenes, re-sectored at nine counts. `crossed` is Decision 40's failing-sector rule; `joint` is the intersection of the corpus and suite brackets on `maxCrossedSectors`, exactly as Decision 43 computes it at 8.

| N | plate crossed | table crossed | corpus | suite | joint | min sector samples | `ringMinSamples` | halved grid |
|---|---|---|---|---|---|---|---|---|
| 4 | 0 | 2 | 0…1 | 0…0 | **0…0** | 248 | 100 | feasible |
| 6 | 0 | 3 | 0…2 | 0…1 | 0…1 | 137 | 150 | feasible |
| **8** | **0** | **3** | **0…2** | **0…2** | **0…2** | 102 | 200 | feasible |
| 10 | **1** | 5 | 1…4 | 0…2 | 1…2 | 80 | 250 | feasible |
| 11 | 1 | 6 | 1…5 | 0…2 | 1…2 | 73 | 275 | feasible |
| 12 | 1 | 7 | 1…6 | 0…3 | 1…3 | 66 | 300 | **refused** |
| 16 | 1 | 7 | 1…6 | 0…4 | 1…4 | 45 | 400 | refused |
| 24 | 1 | 13 | 1…12 | 0…6 | 1…6 | 29 | 600 | refused |
| 32 | 1 | 18 | 1…17 | 0…9 | 1…9 | 21 | 800 | refused |

**Nine counts, eight distinct joint intervals.** `maxCrossedSectors` is a count of sectors, so of course it scales — but it was recorded as "0…2, and nothing in hand narrows it", which reads as a range the session may choose from. It is a range *conditional on a constant that is itself owed*.

**The ceiling is Req 5.1's, and the constraint is self-tightening.** `ringMinSamples = ringSectorCount × 25` rises with the count, so asking for finer arcs raises the very floor the ring must clear. The native corpus is nowhere near it — the thinnest radial band holds 1120 samples, which would carry 44 sectors. The 2× halved grid is: its thinnest band holds **292**, so 292/25 = **11** is the last count at which `ringBandsAreFeasible` still passes on both captures. Decision 35 recorded that Req 5.1's transfer "floors at the ring, not the plane"; this measures the count as the knob that sets where that floor sits. Above 11 the plane still transfers and the ring measure does not, which is the same refusal Decision 39 declined to engineer around with `mmPerPx`.

**No floor, and that is a negative result worth having.** Decision 40's rule works by finding an arc of the ring sitting above the candidate plane while the rest supports it, so a coarse cut might have averaged the crossing away inside one sector. It does not: the corpus separates its plate-top candidate from its table candidate at **every** count from 4 to 32. The rule's separation is robust to the count; only its bracket is not.

**The pass side erodes above 8, and that is where the bracket's top comes from.** The plate-top candidate — the plane a correct fit must admit — reads **0** crossed sectors at 4, 6 and 8 and **1** from 10 upward. Narrow enough arcs resolve the direction in which its own ring ran off the plate onto the table, which is Decision 33's plate margin read a third way, and the rule's floor stops being zero. So the count is bracketed 4…8 by the pass side, inside the Req 5.1 ceiling of 11.

**And the trade inside that bracket runs backwards.** A *coarser* cut leaves *less* freedom in the constant it denominates: joint bracket widths are 1 at four sectors, 2 at six, 3 at eight. At four, `maxCrossedSectors` is **determined** at 0 by evidence already committed — the suite's silent-failure scene reads 1 crossed sector there and the plate candidate reads 0, so no value but 0 survives. Decision 43's "any choice among the three is asserting" is therefore partly an artefact of the shipped count, which is precisely the count at which the freedom is widest.

That does not make four the answer. At four sectors an arc is 90°, and whether that resolves the straddle Req 3.6 and Decision 18 describe is exactly what the corpus cannot say — the corpus has no clean correct fit (Decision 29) and its only straddle is the table candidate, which four sectors happen to catch. Buying determinacy in `maxCrossedSectors` by asserting `ringSectorCount` moves the assertion rather than removing it.

### Alternatives Considered

- **Set `ringSectorCount = 8` now, as the largest count with a clean pass side inside the Req 5.1 ceiling** - The bracket has a defensible top and the shipped value is already there - Rejected because 4 and 6 are equally clean on both sides, so the top of a three-value bracket is still an end of a bracket. Req 3.7 names this constant for exactly this move.
- **Set `ringSectorCount = 4` and discharge `maxCrossedSectors` with it** - It would close two owed constants at once from evidence in hand, and the joint bracket collapses to a single value - Rejected because it buys determinacy in one constant by asserting another, and the 90° arc's adequacy against Decision 18's straddle is a property of scenes the corpus does not contain. It also halves the resolution of the guard whose whole job is angular.
- **Re-denominate `ringMinSamples` so it stops moving with the count** - Fix it at 200 regardless, and the Req 5.1 ceiling disappears - Rejected because the 25-samples-per-sector derivation is what gives the 0.5 support bar its binomial footing (Decision 20, σ ≈ 0.10 at 25 samples against σ ≈ 0.19 at the old floor of 60 overall). Decoupling them leaves the sector fraction unfloored at high counts, which is the noise regime Decision 20 removed.
- **Record the count as settled at 8 because nothing has ever moved it** - It has survived every decision from 18 onward - Rejected because surviving is not measurement. This pass is the first thing to vary it, and it finds every recorded sector bracket depends on it.
- **Sweep `sectorSupportMin` in the same pass** - The third member of the trio is equally unmeasured - Deferred rather than rejected: the support bar is a fraction of a sector's samples, not a count of sectors, so it is not re-denominated by this finding and its measurement is a separate one. Recorded here so the omission is deliberate.

### Consequences

**Positive:**

- `ringSectorCount` gets its first two-sided bracket — 4…8 from the pass side, 11 as a hard ceiling — where before it had no measurement at all.
- Req 5.1's transfer claim acquires a stated ceiling on the count, so a later session cannot raise `ringSectorCount` without re-reading Decision 35. The coupling was invisible before: `ringMinSamples` is `[measured]` and takes an `[owed]` input.
- Decisions 40, 41 and 43's brackets are restated in their true units, and the capture session's ordering changes with them — the count is fixed first, and capture 6 then reads `maxCrossedSectors` in whatever unit that fixed.
- The rule's separation is confirmed robust to the count over an 8× range, which is a stronger statement about Decision 40 than any single-count reading could make.

**Negative:**

- Three counts survive both sides, so nothing is set. The feature gains another bracket rather than a value, and `ringSectorCount` joins the list task 27 waits on.
- The shipped count is the one leaving `maxCrossedSectors` *least* determined, so Decision 43's headline — two constraint sets agreeing on 0…2 with nothing to narrow it — is weaker than it read.
- The ceiling of 11 comes from a 2× halving of two captures. A sensor with a different native grid moves it, and the corpus cannot say by how much.
- The 4…8 bracket's top rests on one candidate on one capture — `1785135663727`'s plate top is the only intended-correct plane the corpus has, and Decision 29 already records that it is not a clean one.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`sectorCountIsTheUnitOfTheSectorTrio`; `sectorSigns` gains a count parameter and a `sectorSampleCounts` member, and `SceneReading` carries its ring so it can be re-sectored), `MedataCore/Sources/SupportPlane/SupportRegion.swift` (the sector-trio and `ringMinSamples` comments), `prerequisites.md`, task 26's detail and `docs/agent-notes/support-plane-fit.md`. **No shipped behaviour changes**: no constant's value moves, no guard is rewired, and no existing assertion is edited.

---

## Decision 45: The support bar selects the population the crossed-sector rule reads, and the shipped value sits on a cliff

**Date**: 2026-08-06
**Status**: accepted (qualifies Decisions 40 and 44; strengthens Decision 43)

### Context

`sectorSupportMin` is the third constant Req 3.7 names and the only one nothing has ever varied. Decision 44 measured `ringSectorCount` and deferred this one in as many words — "the support bar is a fraction of a sector's samples, not a count of sectors, so it is not re-denominated by this finding and its measurement is a separate one".

It is not a peer of the other two either, and Decision 40 is where that shows. The crossed-sector rule reads the sign of sectors that **fail** this bar, so `sectorSupportMin` selects the population the rule is computed over. Decision 40's central claim — that the rule's magnitude bar is `[inherited]` rather than fitted, because failing sectors separate over **23.397 mm** where all sectors separate over **2.128 mm** — is a statement about that population. And "all sectors" is precisely this constant at 1.0, so the contrast Decision 40 draws is its own sweep's other endpoint. The claim is a reading at 0.5 of a quantity that moves with the bar, and nothing recorded what it does in between.

Decision 44 also left an ordering instruction that assumes the two constants are separable: fix the count **before** the sitting, then read `maxCrossedSectors` in whatever unit that fixed. Whether the count's own bracket depends on the bar was never asked.

### Decision

`sectorSupportMin` is recorded as **bracketed 0…0.5 at eight sectors, with the shipped 0.5 sitting ON the ceiling rather than inside the bracket**. It stays `[owed]`.

Decision 44's ordering is **superseded**: `ringSectorCount` and `sectorSupportMin` must be fixed **jointly**, not in sequence, because the count's pass-side bracket is a function of the bar.

Nothing is rewired and no value moves.

### Rationale

The same two corpus candidates and the same eight committed scenes, re-classified at eleven bars. The window is Decision 40's, recomputed: how far `ringBandMm` may move before either candidate changes its crossed count — lower edge the plate candidate's highest failing median, upper edge the table candidate's lowest crossed median.

| `sectorSupportMin` | plate supporting / crossed | table supporting / crossed | invariance window | joint `maxCrossedSectors` |
|---|---|---|---|---|
| 0.0 | 8 / 0 | 8 / **0** | — (rule silent) | empty |
| 0.1 | 7 / 0 | 6 / 2 | −32.564…+16.603 (**49.167**) | 0…0 |
| 0.2 | 7 / 0 | 6 / 2 | −32.564…+16.603 (49.167) | 0…0 |
| 0.3 | 7 / 0 | 6 / 2 | −32.564…+16.603 (49.167) | 0…1 |
| 0.4 | 6 / 0 | 5 / 3 | −9.680…+16.603 (26.283) | 0…2 |
| **0.5** | **5 / 0** | **5 / 3** | **−6.794…+16.603 (23.397)** | **0…2** |
| 0.6 | 4 / 0 | 3 / 4 | +3.711…+5.974 (**2.263**) | 0…2 |
| 0.7–0.8 | 4 / 0 | 1 / 4 | +3.711…+5.974 (2.263) | 0…2 |
| 0.9–1.0 | 3 / 0 | 1–0 / 4 | +3.846…+5.974 (**2.128**) | 0…2 |

**The ceiling is a cliff, and the shipped value is standing on it.** The window collapses **10.339×** in one notch, 23.397 mm at 0.5 to 2.263 mm at 0.6, and it is the largest single step in the sweep by a wide margin. Decision 40 supplied the criterion without knowing it was one: 2.128 mm is "being fitted to the corpus", 23.397 mm is "being inherited". So the criterion needs no threshold of its own — the collapse picks the ceiling, and the ceiling is 0.5. Raise `sectorSupportMin` by one notch and `ringBandMm` stops being inherited, which is the ground Decision 40 rejected the all-sector formulation on.

**Both edges converge on the bar, from opposite sides.** As `sectorSupportMin` rises, sectors that sit *on* the plate candidate's plane but are noisy start failing, and they read near zero, so the lower edge climbs from −32.564 to +3.846. Meanwhile sectors holding the table candidate's plane at a small positive offset fail too and become crossed, so the upper edge falls from +16.603 to +5.974. The bar is squeezed from both directions by the same constant.

**Decision 40's contrast understates its own case.** At 1.0 the reading reproduces its all-sector figure exactly, +3.846…+5.974. But that is the room the bar has *at its current value*, not a gap between the two populations: read without conditioning on where `ringBandMm` sits, the all-sector failing medians **interleave** — the table's lowest is +0.426, *below* the plate's highest +3.846, a separation of **−3.419 mm**. At the shipped bar the same reading is +23.397 mm and genuinely positive. Restricting the rule to failing sectors is therefore more necessary than Decision 40 recorded, not less.

**The floor is the rule's own.** At 0.0 nothing fails, the population the rule reads is empty, and a rule with nothing to read admits the plane Decision 18 exists to reject. At eight sectors that is the only silent bar; at four it is 0.0…0.2, which is the coupling arriving from the other side.

**And the count is not separable from the bar** — the finding that supersedes Decision 44's ordering. The counts with a clean pass side and a firing rule, per bar:

| `sectorSupportMin` | counts with a clean pass side |
|---|---|
| 0.1–0.2 | 6, 8, 10, 11 |
| 0.3 | **4, 6, 8, 10, 11** |
| 0.4 | 4, 6, 8, 10 |
| 0.5–1.0 | **4, 6, 8** |

Decision 44's 4…8 is a reading at 0.5. Lower the bar and the fine end opens up — at 0.3 every count Req 5.1 permits has a clean pass side, so the "pass-side erosion above 8" that gave the bracket its top is itself a consequence of the bar being at 0.5. Raise it and nothing changes, because 0.5 is already at the ceiling. Fixing the count first and the bar afterwards therefore fixes the count against a value that has not been chosen yet.

**Decision 43 is strengthened, not qualified.** Over the whole grid — five counts × eleven bars — **no cell collides**: wherever the rule fires at all, the suite and the corpus admit a common `maxCrossedSectors`. Decision 43 could only say that at one pair; it is now a property of the rule rather than of the shipped pair.

### Alternatives Considered

- **Set `sectorSupportMin = 0.5` now, since it is the ceiling of a measured bracket** - The cliff is sharp, the shipped value is exactly at it, and Decision 40's criterion picks it without a free parameter - Rejected because a ceiling is an end of a bracket, and 0.1…0.4 are all admissible on the same criterion with *wider* windows. Req 3.7 names this constant for exactly this move. The cliff says where the bar may not go, not where it should sit.
- **Set `sectorSupportMin` low — 0.3 — to buy back the count's fine end** - It would restore counts 10 and 11 to the pass side and widen the invariance window to 49.167 mm, so both other sector constants gain room - Rejected because it optimises the corpus's two candidates. A low bar means a sector counts as supporting on a small share of its samples, which is the noise regime Decision 20 removed the old 60-sample floor to escape, and the corpus contains no scene where that misfires. It is fitting, in the direction the measurements happen to reward.
- **Keep Decision 44's ordering and note the bar dependence as a caveat** - Less churn in `prerequisites.md`, and the ordering is still better than no ordering - Rejected because the ordering's whole purpose was to stop capture 6 measuring a number in a unit that was still moving. If the unit itself moves with a third owed constant, the instruction gives false assurance.
- **Sweep the bar against the fallback rate as well (Decision 42's function)** - The rate is a readout of the owed constants and this is one of them - Deferred rather than rejected: Decision 42 already sweeps `minSupportingSectors` and reads 1.000 → 0.500 → 0.000, and the crossed rule is not wired into `admissibility`, so a rate swept on this bar would grade the shipped guard rather than the replacement. Recorded so the omission is deliberate.
- **Treat the interleaving at 1.0 as a defect in Decision 40's window** - It reports 2.128 mm where the honest separation is −3.419 mm - Rejected: the invariance interval is the right statistic for asking how much room an inherited bar has, and Decision 40 uses it consistently. The interleaving is an additional finding in the same direction, not a correction.

### Consequences

**Positive:**

- `sectorSupportMin` gets its first bracket — 0…0.5 at eight sectors — where before it had no measurement at all. All three constants Req 3.7 names are now bracketed rather than merely owed.
- Decision 40's inheritance claim acquires the condition it was always subject to: `ringBandMm` is inherited *while `sectorSupportMin` ≤ 0.5*, and one notch above that it is fitted. A later session cannot raise the bar without re-reading Decision 40.
- The capture session's ordering is corrected before the sitting rather than after it: the count and the bar are fixed together, and capture 6 reports in a unit fixed by both.
- Decision 43's agreement between the two constraint sets is confirmed over a 55-cell grid instead of a single pair — the strongest statement the feature has about the crossed-sector rule.
- The all-sector interleaving strengthens the case for the `sectorSupportMin` gate inside the rule, which Decision 40 flagged as the thing someone would be tempted to drop as redundant.

**Negative:**

- Another bracket rather than a value, and the bracket's ceiling is where the shipped placeholder already sits — so the measurement constrains the session's freedom without reducing what it owes.
- Two owed constants are now known to be jointly determined, which makes the sitting harder to plan: `prerequisites.md` can no longer give a sequence, only a pair to choose before the captures.
- The cliff rests on the two corpus candidates. It is sharp because a handful of sectors cross the bar together between 0.5 and 0.6, and a corpus of two captures cannot say whether that coincidence generalises.
- `maxCrossedSectors` is now denominated in **two** owed constants, so Decision 43's "the two sources agree exactly" holds per (count, bar) pair rather than absolutely.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`supportBarSelectsThePopulationTheRuleReads`; `sectorSigns` and `SceneReading.signs(at:)` gain a `supportMin` parameter), `MedataCore/Sources/SupportPlane/SupportRegion.swift` (the sector-trio comment), `design.md`, `prerequisites.md`, task 26's detail and `docs/agent-notes/support-plane-fit.md`. **No shipped behaviour changes**: no constant's value moves, no guard is rewired, and no existing assertion is edited.

---

## Decision 46: The ring radius re-selects the candidates, and it is the first owed constant that moves the answer

**Date**: 2026-08-06
**Status**: accepted (replaces the rule Decision 33 found unsatisfiable; extends Decisions 44 and 45's joint pair to a triple; qualifies Decisions 43 and 45)

> Not to be confused with **pipeline Decision 46**, the 20 mm LiDAR residual bar, which several
> documents in this feature cite. Every reference to that one is qualified as "pipeline
> Decision 46" from this entry onward.

### Context

`ringOuterMm` is `[owed]` and has no derivation at all. Decision 33 measured its stated rule — "inside the smallest measured plate margin" — and found it **unsatisfiable**, because the tightest margin is 4 mm and `ringInnerMm` is 8, so no ring can be placed inside it. Nothing replaced the rule. It has sat since as the one owed constant with neither a bracket nor a criterion.

Decisions 44 and 45 measured the sector measure's other two free constants and concluded they must be fixed **jointly**. `ringOuterMm` is upstream of both. The crossed-sector rule reads the **inner band**, whose outer edge is `ringInnerMm + (ringOuterMm − ringInnerMm) / ringBandCount` = 13.667 mm at the shipped value — so Decision 33's "only 4 of 8 sectors reach the inner band" and Decision 43's rimmed-plate blind spot ("their rims never reach the inner band the sector median is computed over") are both readings of this constant, taken at 25 mm and recorded without saying so.

And it differs in kind from the other two. The count re-cuts a fixed ring; the bar re-classifies a fixed set of sectors. The radius moves the **annulus**, `2 × ringOuterMm`, which is the candidate bound — so extraction runs on a different sample set at every value and the constant can change **which plane is selected**, not only how a fixed selection is read.

### Decision

`ringOuterMm` is recorded as **bracketed 22…32 mm**, floor from Req 5.1's grid halving and ceiling from the committed suite, with the shipped 25 inside rather than on an edge. It stays `[owed]`.

It is the **first owed constant that moves the answer**: across the sweep the selected plane moves **18.719 mm** at the food on `1785901032716` and **4.162 mm** on `1785135663727`, against the **1 mm** Decision 35 measures Req 5.1's grid transfer at. Decisions 44 and 45 both closed with "no value moves"; that does not extend here.

Decision 45's instruction to fix `ringSectorCount` and `sectorSupportMin` jointly becomes a **triple** — the radius joins them, and it is fixed first, because it selects the candidates the other two are read on.

Nothing is rewired and no shipped value moves.

### Rationale

The same two corpus captures and the same eight committed scenes, re-ringed at seventeen radii. Extraction is **re-run** at each, not re-read. "Best" is the highest inner-band support, as `bestCandidate` computes it. "Plane at food" is where the selected plane cuts the food-centroid ray, the instrument Decision 35 measures Req 5.1's tolerance with.

| `ringOuterMm` | inner band ends | best on `…3727` supporting / crossed | best on `…2716` ring median | `…2716` plane at food | joint `maxCrossedSectors` | Req 5.1 halving | committed suite |
|---|---|---|---|---|---|---|---|
| 13 | 9.667 | 5 / 0 | −1.757 | 342.372 | 0…1 | **refused** | holds |
| 15 | 10.333 | 5 / 0 | −1.142 | 346.249 | 0…2 | **refused** | holds |
| 17 | 11.000 | 5 / 0 | −2.461 | 342.053 | 0…0 | **refused** | holds |
| 20 | 12.000 | 5 / 0 | −1.796 | 344.484 | 0…1 | **refused** | holds |
| **22** | 12.667 | 5 / 0 | −12.231 | 338.413 | **empty** | feasible | holds |
| 23 | 13.000 | 5 / 0 | −2.706 | 344.194 | 0…1 | feasible | holds |
| 24 | 13.333 | **3 / 2** | −4.897 | 343.378 | **empty** | feasible | holds |
| **25** | **13.667** | **5 / 0** | **+3.039** | **356.280** | **0…2** | feasible | holds |
| 26 | 14.000 | 5 / 0 | +2.938 | 356.341 | 0…2 | feasible | holds |
| 27 | 14.333 | **3 / 2** | +2.867 | 356.394 | 2…2 | feasible | holds |
| 28 | 14.667 | 5 / 0 | +2.652 | 356.300 | 0…2 | feasible | holds |
| 29 | 15.000 | 5 / 0 | +2.753 | 356.533 | 0…2 | feasible | holds |
| 30 | 15.333 | **3 / 2** | +2.610 | 356.545 | 2…2 | feasible | holds |
| 31 | 15.667 | 5 / 0 | +2.555 | 356.600 | 0…2 | feasible | holds |
| **32** | 16.000 | **3 / 2** | +2.552 | 356.738 | 2…2 | feasible | holds |
| 35 | 17.000 | 5 / 0 | +2.290 | 356.823 | 0…2 | feasible | **red** |
| 40 | 18.667 | 5 / 0 | +2.022 | 357.132 | 0…3 | feasible | **red** |

**The bracket is two-sided, and neither side existed before.** The **floor is Req 5.1's**, and it is the mirror of the ceiling Decision 44 read off the same transfer. A narrower ring holds fewer samples per radial band and the 2× halving quarters them, so below 22 mm `ringBandsAreFeasible` refuses on a grid where the plane still transfers within a millimetre — halved bands read [78, 111, 48] and [65, 148, 45] at 13 mm against the 200 floor, and [237, 242, 248] and [258, 264, 272] at 22 mm. The **ceiling is the committed suite's**, and it arrives exactly as Decision 41 warned: the scenes place their features at fixed pixel radii, so a wide enough ring reaches the rim a scene deliberately put outside it. At 35 mm and 40 mm every sector of a scene the suite requires to **pass** reads crossed, the suite's floor on `maxCrossedSectors` jumps to 8 and its ceiling on `minSupportingSectors` falls to 0, and both intervals go empty together. Between 32 and 35 mm the committed suite goes red.

**The radius denominates `maxCrossedSectors` too, and it reorders it rather than scaling it.** Decision 44 recorded the constant as a count of sectors and Decision 45 as a count read at a bar. It is also a count read at a radius: the joint bracket reads 0…0, 0…1, 0…2 and 2…2 over the sweep, with no ordering in the radius at all. Where Decision 44's counts gave eight *monotonically widening* intervals, these interleave.

**And the pass side alternates at 1 mm steps.** The best candidate on `1785135663727` — the corpus's only intended-correct plane — reads **0** crossed sectors at 22, 23, 25, 26, 28, 29 and 31 mm and **2** at 24, 27, 30 and 32 mm. Clean and dirty alternate inside the bracket at the sweep's own resolution, and its plane at the food oscillates over 4.162 mm with them. A radius between two clean radii is therefore not implied by either, so this constant **cannot be bracketed by interpolation** the way the count and the bar were. That is the direct consequence of it re-running extraction: the other two constants could only move a verdict, this one moves the input the verdict is computed on.

**The separation Decision 44 found robust is not robust to this.** Decision 44 measured that the crossed-sector rule separates the two corpus candidates at every sector count from 4 to 32 — "a coarse cut does not average the crossing away". The radius breaks it: at 22 and 24 mm the two constraint sets admit **no common `maxCrossedSectors`**. Decision 45's headline — no cell collides over its 55-cell (count × bar) grid — therefore holds *at the shipped radius* and not outright. Wherever the rule fires the agreement is real; the radius decides whether it fires on the planes the rule was measured against.

**The bifurcation, and what it is not.** On `1785901032716` the selection changes sign at 24/25 mm: at 13…24 mm the best-support candidate reads a **negative** ring median and sits ~10 mm nearer the camera; from 25 mm up it reads **positive** and is the plane Decision 30 identified as the table. Which surface this capture selects is a function of an owed constant. This is *not* a claim that the narrow radii find the correct plate plane — those readings are not clean either (2–3 supporting sectors, 1–3 crossed, and at 22 mm a plane 12.2 mm above its own ring), and the corpus still has no clean correct fit. What it establishes is narrower and firmer: Decision 42's finding that only `ringMedianMaxMm`'s 0.338 mm holds the wrong plane out is a statement about the shipped radius, because at a smaller one the wrong plane is not the one selected.

**The control, and it changes what the sweep means.** The 1 mm-step alternation admits a second reading: extraction is unstable and moving the annulus merely re-rolls it. Held at the shipped radius with only the RANSAC seed varied over eight draws:

| capture | distinct planes at the food | spread | supporting | crossed |
|---|---|---|---|---|
| `1785135663727` | 349.232 / 350.948 / 351.328 | **2.095 mm** | 5 | 0 |
| `1785901032716` | 356.280 | **0.001 mm** | 5 | 3 |

Both halves matter. The **plane** is seed-dependent by 2.095 mm on the capture that carries the corpus's intended-correct fit — twice the figure Decision 35 measures the grid transfer at, and a quantity nothing had recorded. This is **not** a Req 5.1 failure: the seed is `Fnv1a64.hash(depthBytesMm)`, so identical bytes draw identically and replay reproduces device exactly, which is what the requirement asks. What it bounds is how much of any plane figure this feature quotes is the capture and how much is the draw.

The **verdict** is not. Across eight draws per capture the supporting and crossed counts are single-valued, so the brackets Decisions 40–45 read off one draw each are properties of the captures. And that is what separates the control from the sweep: the seed never moves the crossed count, the radius moves it four times in eleven millimetres. The alternation is the radius reordering the candidates, not extraction re-rolling them.

### Alternatives Considered

- **Set `ringOuterMm = 25` now, since it is inside a measured two-sided bracket and no other value is better supported** - The bracket exists for the first time and the shipped value is comfortably inside it, away from both edges - Rejected because "inside a bracket" is what the other ten values in 22…32 also are, and four of them read a dirty pass side. Choosing among them on the corpus's two captures is fitting, and the constant is `[owed]` for that reason. The bracket says where the session may look, not what it should pick.
- **Set `ringOuterMm = 22`, the smallest radius that survives Req 5.1** - It maximises the plate margin available in each sector, which is the pressure Decision 33 measured, and it is a principled end rather than an arbitrary interior point - Rejected because 22 mm is the one radius in the bracket where the two constraint sets **collide** — the rule stops separating the corpus's candidates entirely. Picking the end of a bracket because it is an end is what Decision 44 rejected for the count and Decision 45 for the bar; here the end is also measurably worse.
- **Re-denominate the inner band so the sector rule stops moving with `ringOuterMm`** - Fix the inner band at a stated width rather than `(ringOuterMm − ringInnerMm) / ringBandCount`, and the radius would then bound only the annulus - Rejected because it does not touch the finding. The annulus is `2 × ringOuterMm` and the annulus is what re-selects the candidates, so decoupling the band leaves the 18.719 mm of plane movement exactly where it is while adding a fourth radial constant to own. Decisions 37 and 38 re-denominated constants whose *unit* was wrong; this one's unit is correct and its *value* is unset.
- **Treat the alternating pass side as extraction noise and report the bracket without it** - Simpler, and the seed control does show 2.095 mm of instability on the same capture - Rejected by the control itself: the seed moves the plane and never the verdict, the radius moves the verdict four times. Reporting the bracket alone would let a session interpolate inside it, which is the one thing this measurement says it may not do.
- **Sweep `ringInnerMm` in the same pass** - It is the ring's other radial edge and would complete the geometry - Deferred rather than rejected: `ringInnerMm` is `[measured]` against the depth smear (Decisions 29, 39) and is not owed, so sweeping it would measure a settled constant. Recorded so the omission is deliberate.

### Consequences

**Positive:**

- `ringOuterMm` gets a bracket at all — 22…32 mm, two-sided — where Decision 33 left it with an unsatisfiable rule and nothing else. It is the last owed constant that had no criterion.
- Req 5.1's grid transfer now bounds the ring from **both** ends: Decision 44's ceiling of 11 on `ringSectorCount` and this floor of 22 mm on the radius come off the same halving, so the transfer claim constrains the ring's angular and radial resolution alike.
- The committed suite acquires a stated ceiling on the radius, so a later session cannot widen the ring past 32 mm without re-authoring scenes — the dependency Decision 41 predicted, now measured on a second constant.
- The capture session's ordering is corrected again before the sitting: three constants are fixed together, and the radius is fixed first because it selects the candidates the other two are read on.
- Selection is confirmed **verdict-stable under the RANSAC seed**, which is the first evidence that any bracket in Decisions 40–45 is a property of the captures rather than of one draw. Nothing had checked.

**Negative:**

- Another bracket rather than a value, and this one cannot be interpolated inside — so it constrains the session more tightly than it reduces what the session owes.
- `maxCrossedSectors` is now denominated in **three** owed constants. Decision 43's "the two sources agree exactly" holds per (radius, count, bar) triple, and Decision 45's collision-free grid is a slice of a larger one that does collide.
- The plane at the food is seed-dependent by 2.095 mm on the corpus's one intended-correct capture. Req 5.1 is satisfied by determinism, but every plane figure this feature quotes — Decision 35's 0.835 mm transfer, Decision 36's 18.370 mm fallback price — is one draw, and their error bars are wider than recorded.
- The bracket rests on two captures whose plates end inside the ring in five of eight directions (Decision 33). The ceiling in particular is a property of the committed **scenes**, so it moves if they are re-authored, and the corpus cannot say whether 32 mm is physically right.
- The sweep costs ~87 s. It re-runs extraction seventeen times per capture, and the measurement suite is now the slowest thing in `make test`.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`ringRadiusIsTheRadialUnitOfTheSectorRule` and `candidateSelectionIsSeedUnstableAtTheShippedRadius`; a `ringSamples(geometry:outerMm:)` mirroring the shipped builder, an `innerSupportFraction` that reads below the `ringMinSamples` floor, and the eight committed scenes lifted into a `SceneSpec` list so they can be re-ringed), `MedataCore/Sources/SupportPlane/SupportRegion.swift` (the `ringOuterMm` comment), `design.md`, `prerequisites.md`, task 26's detail and `docs/agent-notes/support-plane-fit.md`. **No shipped behaviour changes**: no constant's value moves, no guard is rewired, and no existing assertion is edited.

---

## Decision 47: The band count is the divisor the sector measure was never varied over, and two values survive

**Date**: 2026-08-06
**Status**: accepted (adds a fourth constant to Decision 46's triple; qualifies Decisions 41 and 43; confirms Decision 46's attribution)

### Context

Of the seven constants the sector measure reads — `ringInnerMm`, `ringOuterMm`, `ringBandCount`, `ringBandMm`, `ringSectorCount`, `sectorSupportMin`, `ringMinSamples` — six carry a provenance marker. `ringBandCount` carries none. Its whole comment is "Structural: inner / mid / outer", which is an assertion in a word that does not look like one, and it has never been varied.

Decision 46 is what turns that into a gap. It found `ringOuterMm` upstream of the count and the bar because the crossed-sector rule reads the **inner band**, whose outer edge is `ringInnerMm + (ringOuterMm − ringInnerMm) / ringBandCount` — and then swept only the numerator. The divisor sets the same edge. It also divides in a second place at once: `ringMinSamples` is floored **per band**, so raising the count narrows every band and starves the floor in the same move that sharpens the rule.

Three things separate it from the other three constants in advance of measuring it. It does **not** move the annulus, so unlike the radius the candidate set is fixed. It does move the inner band, and `bestCandidate` ranks on inner-band support, so unlike the count and the bar it is not obviously a pure re-reading. And it is the only one of the four bounded from below by a guard's **existence**: `admissibility` reads `bandMedianMm[1] − bandMedianMm[0]` behind a `count > 1` test.

### Decision

`ringBandCount` is recorded as **bracketed 2…3**, floor from the `bandStep` guard's existence and from the committed suite, ceiling from Req 5.1's grid halving. The shipped 3 sits **on the ceiling**, the position Decision 45 found `sectorSupportMin` in. It is marked `[owed]`; "structural" is withdrawn.

It does **not** move the answer. The selected plane at the food is unchanged to 0.000 mm on both captures at every band count in the sweep, so Decision 46's "first owed constant that moves the answer" is confirmed as a property of the **annulus** specifically rather than of radial geometry generally.

Decision 46's triple stays a triple for the *sitting*. This constant is bracketed to two values by evidence already committed and does not need the captures, so it is fixed **before** them, not with them.

Nothing is rewired and no shipped value moves.

### Rationale

The same two corpus captures and the same eight committed scenes, re-banded at nine counts at the shipped radius. Extraction is re-run but the annulus does not move, so the candidate set is the shipped one at every count and only the reading changes.

| `ringBandCount` | band width | inner band ends | `…3727` sup / crossed | `…2716` sup / crossed | joint `maxCrossedSectors` | `bandStepMaxMm` suite | Req 5.1 halving | `bandStep` guard |
|---|---|---|---|---|---|---|---|---|
| 1 | 17.000 | 25.000 | 5 / 0 | 5 / 3 | **empty** | n/a | feasible | **silent** |
| **2** | 8.500 | 16.500 | 5 / 0 | 5 / 3 | **1…2** | 0.214…13.470 | feasible | runs |
| **3** | **5.667** | **13.667** | **5 / 0** | **5 / 3** | **0…2** | **0.024…9.288** | feasible | runs |
| 4 | 4.250 | 12.250 | 5 / 0 | 3 / 5 | 0…2 | 0.024…6.755 | **refused** | runs |
| 5 | 3.400 | 11.400 | 5 / 0 | 2 / 6 | 0…2 | 0.042…5.496 | **refused** | runs |
| 6 | 2.833 | 10.833 | 5 / 0 | 5 / 3 | 0…2 | 0.009…0.211 | **refused** | runs |
| 7 | 2.429 | 10.429 | 5 / 0 | 3 / 5 | 0…2 | **empty** | **refused** | runs |
| 8 | 2.125 | 10.125 | 5 / 0 | 2 / 6 | 0…2 | **empty** | **refused** | runs |
| 10 | 1.700 | 9.700 | 5 / 0 | 2 / 6 | 0…2 | **empty** | **refused** | runs |

**The floor is 2, and it arrives twice independently.** The first reason is that a guard stops existing. At one band there is no mid band, `admissibility`'s `bandMedianMm.count > 1` test is false, and the `bandStep` guard does not fire and does not report that it did not — while two committed scenes, `bowl` and `rim in the mid band`, assert that it *does*. That is the shape of failure Decision 18 exists to prevent, reached through a constant nobody was watching. The second reason is the committed suite, arriving as Decision 41 predicted and for the third time: at one band the inner band **is** the whole 8…25 mm ring, so the rims the rimmed-plate scenes place at fixed pixel radii fall inside it, a scene that must *pass* reads all eight sectors crossed, and both suite intervals go empty together — `maxCrossedSectors` 8…2 and `minSupportingSectors` 6…0. Either reason alone excludes 1.

**The ceiling is 3, and it is Req 5.1's for the third time.** Decision 44 read this bound on `ringSectorCount` (≤ 11) and Decision 46 on `ringOuterMm` (≥ 22 mm). The same 2× depth-grid halving reads it here, and it lands hardest, because `ringMinSamples` is floored per band and this constant *is* how many bands there are. Halved band counts are [322, 361, 323] and [313, 292, 299] at three bands, and [237, 197, 215, 255] and [258, 264, 204, 280] at four — refused on a grid where the plane still transfers within a millimetre. One partition, three constants dividing it, one bound; this is the constant that divides it most directly.

**Two values, which is the tightest bracket any owed constant in this feature has** — and the shipped value is on its ceiling rather than inside it.

**It denominates `bandStepMaxMm`, and not by scaling.** The step is a difference between two bands this constant creates, so narrowing them moves the quantity the bar is read against. The suite interval collapses monotonically — 13.470, 9.288, 6.755, 5.496, 0.211 mm of ceiling at 2 through 6 bands — and then **inverts**: from seven bands the scene that must fire on `bandStep` reads a *smaller* step than the scene that must pass, and no value of the constant satisfies the suite at all. A rim spanning a fixed radial distance stops being a step between adjacent bands once the bands are narrower than the rim. Decision 41's 0.024…9.288 mm is a reading at three bands and says so nowhere.

The two shipped values are consistent, but by a margin nothing records: `bandStepMaxMm = 6` sits inside the suite interval at 2, 3 and 4 bands and above its ceiling from 5 up. That covers the whole Req 5.1 bracket, so the pair does not collide — the coupling is real and currently harmless.

**It denominates `maxCrossedSectors` too, which makes a fourth.** Decision 44 recorded that constant as a count of sectors, Decision 45 as a count read at a bar, Decision 46 as a count read at a radius. It is also a count read at a band count: the joint bracket is **1…2 at two bands** and 0…2 at three and above. So Decision 43's headline — that 0 is admissible and nothing in hand narrows 0…2 — is a reading at three bands. What moves it is Decision 43's own recorded blind spot: the rimmed-plate rims "never reach the inner band the sector median is computed over" at three bands, and at two the inner band ends at 16.5 mm instead of 13.667 and one of them does. The blind spot Decision 43 attributed to the scenes is a property of this constant.

**What does not move.** The selected plane is identical at every band count on both captures — 351.328 mm and 356.280 mm at the food throughout, 0.000 mm of movement against Decision 46's 18.719 mm on the radius. The candidate set is fixed because the annulus is, and although selection ranks on inner-band support, the ranking never flips. Decision 46's attribution of the movement to the annulus was an argument; it is now a measurement.

The crossed-sector rule also separates the two corpus candidates at **every** band count — the plate-top candidate reads 0 crossed sectors throughout and the table candidate 3 to 6 — so, as Decision 44 found for the sector count, a coarse divisor does not average the crossing away. And Decision 41's collision on `minSupportingSectors` is band-count invariant: the suite floors it at 6 and the corpus caps it at 5 at every count from 2 up.

### Alternatives Considered

- **Set `ringBandCount = 3` now, since the bracket has two values and 3 is shipped** - The bracket is the tightest in the feature and the value is already in the code, so setting it costs nothing and closes an owed constant - Rejected because 3 is on the **ceiling**, not inside the bracket, and Decision 45 established what that position means: the constraint that produces the edge is the one under-measured there. Req 5.1's halving refuses 4 by 3 samples in the tightest band (197 against 200) on a two-capture corpus, which is not a margin to sit against. Two values is a narrow choice, not an automatic one.
- **Set `ringBandCount = 2`, the other admissible value, for the sample-count headroom** - Halved bands read [434, 470] and [522, 484] at two bands against [313, 292, 299] and [322, 361, 323] at three, so it clears Req 5.1 with roughly 50 % more margin - Rejected because it is the value at which `maxCrossedSectors` loses 0 from its joint bracket, and because it discards the mid band the outward *profile* is read from — Decision 14's shape detection needs three bands to distinguish flat from rising from falling, and at two "outward" has one meaning only. The headroom is real; it is not free.
- **Leave `ringBandCount` unmarked as structural, since three bands is what "inner / mid / outer" means** - The name states the intent and the design's Decision 14 describes exactly a three-way shape reading - Rejected because the sweep shows the word carrying weight it has not earned: the constant sets the inner-band edge the sector rule reads, bounds `bandStepMaxMm`'s suite interval, moves `maxCrossedSectors`'s bracket, and is capped by Req 5.1. A constant with four downstream dependants is not structural notation. Decision 14's three-way reading is a *reason* for 3, and it is now recorded as one — in the alternative above, where it belongs.
- **Sweep the band count jointly with the radius rather than at the shipped radius** - Both divide the same ring and Decision 46 showed the radius reorders what the count reads, so the honest measurement is the 2-D grid - Rejected for this pass and recorded as a limitation instead. The bracket here is produced by Req 5.1's halving and the suite, both of which the radius also moves, so 2…3 is a **slice at `ringOuterMm` = 25** exactly as Decision 45's collision-free grid was. Running the grid means re-extracting at seventeen radii × nine band counts; the sweep at one radius already costs ~35 s.
- **Re-denominate the bands in millimetres, as Decisions 37 and 38 re-denominated the extent and residue bars** - A band width in millimetres would not move with `ringOuterMm`, and the Req 5.1 ceiling would then be a statement about width rather than count - Rejected on the same ground Decision 46 rejected the matching proposal for the inner band: the unit here is not wrong. A count of bands is what the shape reading needs, and converting it would replace an owed count with an owed width plus an implied count, which is more to own rather than less.

### Consequences

**Positive:**

- `ringBandCount` is bounded at all, and by two values — the tightest bracket in the feature — where it previously had no marker and no measurement. It is the last constant the sector measure reads that had neither.
- Decision 46's central attribution is confirmed rather than assumed: the plane movement belongs to the annulus, and a constant that divides the inner band without moving the annulus moves nothing at the food.
- A silent-failure mode is found and bounded before it could be reached: at one band the `bandStep` guard stops firing without saying so, and two committed scenes assert against exactly that.
- Req 5.1's grid transfer now bounds **three** of the ring's constants — angular resolution (Decision 44), radial extent (Decision 46) and radial resolution (here) — off one halving. The transfer claim is doing more work than any single decision recorded.
- The capture session's list shortens by one item that was never on it: this constant is settled to two values by committed evidence and needs no capture.

**Negative:**

- The shipped value is on the ceiling of its own bracket, and the constraint producing that ceiling clears by 3 samples in one band on a two-capture corpus.
- `maxCrossedSectors` is now denominated in **four** owed constants. Decision 43's "nothing in hand narrows 0…2" is a reading at one point of a four-dimensional space, and 2 bands already gives 1…2.
- The bracket is a slice at the shipped radius, so the same caveat Decision 46 attached to Decision 45's grid attaches here — and the two constants that produce both ends of this bracket are the two the radius also moves.
- `bandStepMaxMm`'s suite interval is now known to go empty above six bands, which means the guard the interval belongs to is only measurable on the committed scenes at coarse partitions. Nothing says whether that is the scenes or the guard.
- The measurement suite grows by another ~35 s and is now decisively the slowest thing in `make test`.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`theBandCountIsTheRadialDivisorOfTheSectorRule`; a `ringSamples(geometry:bandCount:)` mirroring the shipped builder, a `bandMediansMm` reading below the `ringMinSamples` floor, and `sceneSigns`/`sceneStepMm` overloads that re-band the committed scenes), `MedataCore/Sources/SupportPlane/SupportRegion.swift` (the `ringBandCount` and `bandStepMaxMm` comments), `design.md`, task 26's detail and `docs/agent-notes/support-plane-fit.md`. **No shipped behaviour changes**: no constant's value moves, no guard is rewired, and no existing assertion is edited.

---

## Decision 48: The pass cap never fires, and lifting it determines a constant three decisions could not

**Date**: 2026-08-06
**Status**: accepted (narrows Decision 43; corrects Decision 34; confirms Decision 38 unconditionally; couples `maxCandidatePlanes` to `minResidueAreaMm2`)

### Context

Decision 47 closed the ring geometry: every constant the sector measure reads now carries a provenance marker. `maxCandidatePlanes` sits outside it, in extraction, and carries the same kind of comment the band count did — "Structural: table, support, one more" — with no marker at all. It had never been varied either.

Decision 46 is what makes it worth varying. That decision found `ringOuterMm` moves the selected plane *because* it moves the annulus, and Decision 47 confirmed the attribution by moving radial geometry without moving the annulus and watching the plane stand still. The annulus is the sample set extraction draws from; this constant is how many times it may draw. It is the second constant that changes which planes **compete**, and the only one that can *add* a candidate rather than reshuffle a fixed set.

It also sits under two claims that were never tested at a lifted cap. Decision 38 restored the native/halved candidate counts to 3 → 3 and read that agreement as the residue **area** being grid-invariant — but both numbers were *at* the cap, so the agreement could equally have been the cap truncating both. And `planeCandidateCount` is a persisted field (Req 6.1) that Decisions 35 and 38 worked to make a property of the scene rather than of the sensor grid; if the cap binds, it is a property of the cap.

### Decision

`maxCandidatePlanes` is recorded as **`[owed]`, bracketed from below at 2 and unbounded above**. "Structural" is withdrawn.

The cap **never fires on the corpus**. Lifted to 8, both captures still stop at three passes, and both stop **starved** — the residue left after the last pass is 1330.7 mm² and 155.6 mm² against a `minResidueAreaMm2` of 1691. It is the residue floor that ends extraction, so no value at or above 3 is distinguishable on this corpus and the ceiling stays open.

That makes the two constants **coupled**, in one direction and with an order: `minResidueAreaMm2` is itself `[owed]` and bounded from above only, and `1785135663727` leaves 78.7 % of the floor after its last pass — so a session that lowers the floor below 1331 mm² gives that capture a fourth pass and this cap something to truncate. **Set the residue floor first**; a ceiling here is unreadable until it is.

Two consequences belong to other constants and are recorded against them.

Read at full pass depth with the intended plane identified by **Req 3.1's ring median** rather than by the ranking, the corpus **determines `maxCrossedSectors` at 2**, where Decision 43 recorded 0…2 and "nothing in hand narrows it".

And Decision 34's finding that `foodEnvelopeMinMm` has **no floor** is withdrawn. The corpus contains a plane above the support surface after all, and its envelope is positive rather than negative.

No shipped value moves and nothing is rewired.

### Rationale

**The negative first, because it is the opposite of Decision 46's.** Every constant swept since Decision 44 either moved a verdict or moved a plane. This one moves nothing, because it is never reached. The measurement that says so is not the candidate count — that reads 3 either way — but the residue *left over*: replaying the removal chain past the last pass gives 384 and 46 samples against floors of 488 and 500. Extraction on this corpus is stopped by `minResidueAreaMm2`, in both captures, at both grid resolutions.

| capture | natural depth at cap 8 | residue after last pass | floor | stopped by |
|---|---|---|---|---|
| `1785135663727` | 3 | 1330.7 mm² (0.787×) | 1691 mm² | residue floor |
| `1785901032716` | 3 | 155.6 mm² (0.092×) | 1691 mm² | residue floor |

**Which makes Decision 38's repair unconditional.** Lift the cap and the two grids still stop at three passes each. The 3 → 3 agreement that decision quotes is the residue area being grid-invariant, as recorded, and not the cap truncating both — a reading that was available to it and that nothing in hand had excluded.

**The floor of 2 is the corpus's, and it is where sequential extraction earns its keep.** On `1785901032716` the plane a correct fit must select is **pass 2**, nearest Req 3.1's zero at a ring median of −2.658 mm, while the **ranking's** winner is pass 1, the table, at +3.039 mm. The candidates are:

| capture | pass | plane at food | ring median | inner support | crossed | escaped | envelope |
|---|---|---|---|---|---|---|---|
| `1785135663727` | 1 | 351.328 mm | **−0.928 mm** | **0.629** | 0 | 3 | 26.628 mm |
| | 2 | 371.282 mm | +6.366 mm | 0.317 | 6 | 0 | 39.601 mm |
| | 3 | 316.216 mm | −32.917 mm | 0.183 | 0 | 7 | 8.958 mm |
| `1785901032716` | 1 | 356.280 mm | +3.039 mm | **0.480** | 3 | 0 | 25.793 mm |
| | 2 | 344.883 mm | **−2.658 mm** | 0.362 | 2 | 4 | 21.041 mm |
| | 3 | 335.147 mm | −12.844 mm | 0.304 | 0 | 6 | 7.154 mm |

Below a cap of 2 the intended plane on the second capture is not in the candidate set at all, and no setting of any owed constant recovers it — the capture falls back by construction. The committed suite agrees independently: `sequentialExtractionSurfacesThePlate` asserts the plate arrives on pass 2. Two sources, one floor, no disagreement — the second time that has happened, after Decision 43's.

**And the corpus determines `maxCrossedSectors` at 2.** Every reading of that constant since Decision 40 takes its bracket from the **highest-support** candidate on each capture: floor from `1785135663727`'s (0 crossed), ceiling from `1785901032716`'s (3 crossed, minus one). But the highest-support candidate on the second capture *is the table* — the plane the guard exists to reject. The plane the feature must **admit** there is pass 2, which carries 2 crossed sectors and was never entered into the bracket. Floor 2, ceiling 2:

| source | floor | ceiling |
|---|---|---|
| Decision 43, corpus (highest-support candidates) | 0 | 2 |
| Decision 43, committed suite | 0 | 2 |
| here, corpus at full pass depth (Req 3.1's candidate) | **2** | 2 |

This is the first thing in hand that narrows 0…2, and it needed both the rule and the full pass depth to see: the plane that supplies the floor is only in the set because `maxCandidatePlanes` ≥ 2. The constant stays `[owed]` — this is a slice at the shipped `(ringOuterMm, ringSectorCount, sectorSupportMin, ringBandCount)`, as every reading since Decision 44 is — but the session no longer chooses freely within 0…2 at the shipped four. It either reads 2 or moves one of them.

**The ranking is what makes all of this load-bearing.** `fitFoodSupportPlane` ranks admissible candidates by `supportFraction`, and on `1785901032716` the table outranks the intended plane 0.480 to 0.362. So selection there depends entirely on the table being *rejected* by a guard — Decision 18's silent-failure case arriving one level above the guard written for it. The pass cap's floor, `maxCrossedSectors`'s determination and Decision 42's 0.338 mm of accidental `ringMedianMaxMm` separation are three readings of that same fact.

**`foodEnvelopeMinMm` has a floor, and Decision 34's reasoning for saying it does not is the part that fails.** That decision recorded the guard's cases — a bowl, a plane on the food top — as *negative-envelope* scenes the corpus does not contain. The corpus contains one: the second capture's pass 3 sits 9.736 mm above the plate with 6 escaped sectors, and its envelope is **positive at 7.154 mm**. A plane above a surface still has food above *it* wherever the food is taller than the gap, so "plane on the food top → p90 ≈ 0" holds only once the plane reaches the food's own top. The same reading tightens the ceiling: 25.8 mm is the *table's* envelope, and the intended plane's is 21.041 mm.

| bound | Decision 34 | here |
|---|---|---|
| floor | none | **7.154 mm** (the above-surface candidate) |
| corpus ceiling | 25.8 mm | **21.041 mm** (Req 3.1's candidate, not the ranking's) |
| suite ceiling (Decision 41) | 8.233 mm | 8.233 mm |

Against the suite that leaves a **1.079 mm** joint window, the narrowest any owed constant in this feature has. The above-surface candidate is currently rejected by `ringMedianMaxMm` anyway — `[inherited]`, firing at |−12.844| > 5 — so the floor is a bound rather than a repair, and it is the same inherited bar Decision 42 found holding the table out by 0.338 mm.

### Alternatives Considered

- **Mark `maxCandidatePlanes` `[measured]` and close it, since the corpus shows it never fires** - Never firing is a measurement, the sweep is reproducible, and a constant with no effect needs no capture - Rejected because "never fires" is contingent on `minResidueAreaMm2`, which is `[owed]` with its floor still owed to the session. `1785135663727` is 78.7 % of the way to a fourth pass. Marking this settled would record as a property of the scene something that is a property of an unset constant — the exact defect Decision 35 found in `planeCandidateCount` and Decision 38 repaired.
- **Lower `maxCandidatePlanes` to 2, the measured floor, since nothing on the corpus uses the third pass** - It would tighten the RANSAC cost bound Req 7.6 measures, the third pass produces a rejected candidate on both captures, and a value at its own floor is at least derived - Rejected because the third pass is where a plate under a dominant table can still surface, which is the case the corpus does not contain and prerequisites capture 6 is for; and because the third-pass candidate is exactly what determines `maxCrossedSectors` here. The corpus's own evidence for 2 being sufficient is two captures of flat bread on a white plate.
- **Raise the cap so the corpus can be measured at its natural depth** - The cap would then never be the binding constraint by construction, and `planeCandidateCount` would be unambiguously a scene property - Rejected because it is already never binding, so the change would buy nothing measurable and would raise the `maxIterationsPerPass × maxCandidatePlanes` bound on a path that has produced an OOM before (Decision 13). Req 7.6's device latency is denominated in this constant and task 27 has not measured it yet.
- **Record `maxCrossedSectors = 2` as settled, since the corpus now determines it and the suite agrees** - The two constraint sets close on a single value, which no other owed constant achieves, and Req 3.7's circularity objection is about fitting to the pass side alone rather than about agreement between independent sources - Rejected because the determination is a slice at four constants that are themselves owed and bracketed — Decision 44's count, Decision 45's bar, Decision 46's radius, Decision 47's band count — and Decision 46 measured the two constraint sets colliding outright at two radii inside that bracket. A value determined at one point of a four-dimensional space is not determined.
- **Identify the intended candidate by highest ring support throughout, as Decisions 34 and 43 do, and leave their brackets alone** - It is the criterion the shipped ranking uses, so it is the one selection actually applies, and changing criteria mid-feature invites inconsistent readings - Rejected because it is the criterion under test. Req 3.1 states the target as the plane the food rests on, and the ring median is its direct measure; the support fraction is a *proxy* the design chose for its cliff behaviour (`admissibility`'s own comment says so). On the one corpus capture where the two disagree, the proxy picks the table. Using the proxy to identify the correct plane is what made Decision 43's floor unreadable.

### Consequences

**Positive:**

- `maxCandidatePlanes` carries a provenance marker and a measured floor where it had neither, and the last "Structural:" comment standing in for a derivation in `SupportRegion` is gone.
- `maxCrossedSectors` is narrowed for the first time — from three admissible values to one, at the shipped four — by evidence already committed, on the constant three decisions had recorded as unnarrowable.
- `foodEnvelopeMinMm` gains a floor and a tighter ceiling, so an `[owed]` constant that had one-sided evidence now has a two-sided bracket, and the joint window against the suite is 1.079 mm.
- Decision 38's grid-invariance claim is confirmed at a lifted cap, which excludes the one alternative reading of it that was available.
- The ranking's failure on `1785901032716` is now measured rather than implied: the design's selection rule picks the table on one of two committed captures, and everything holding the right plane in is a guard.

**Negative:**

- The corpus can bound this constant from below only, so `maxCandidatePlanes` joins `ringSupportMin` and `minResidueAreaMm2` as one-sided — and its open end depends on one of the others.
- Two owed constants are now coupled with an *order* (`minResidueAreaMm2` before `maxCandidatePlanes`), which the capture session's list did not previously carry. Decision 46's radius-first triple is now a sequence of two independent orderings.
- `maxCrossedSectors`'s determination at 2 rests on identifying the intended plane by ring median on a capture where the ranking disagrees. If prerequisites capture 6 disagrees with that identification, the narrowing goes rather than moves.
- Decision 34's per-guard survey is now known to have read "intended candidate" as the ranking's winner throughout, so its other bounds — `escapeBandMm`, `supportVisibilityMin`, `ringSupportMarginMin` — carry the same question and have not been re-read here.
- Req 7.6's device latency bound is denominated in a constant with no measured ceiling, and task 27 measures that latency at the shipped value only.

### Impact

`MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`thePassCapIsWhatStopsExtractionOnTheCorpus`, and an `extractCandidates(annulus:geometry:gravity:rng:maxPasses:)` mirroring the shipped extraction with the cap as an argument), `MedataCore/Sources/SupportPlane/SupportRegion.swift` (the `maxCandidatePlanes`, `maxCrossedSectors` and `foodEnvelopeMinMm` comments), `design.md`, task 26's detail, `prerequisites.md` and `docs/agent-notes/support-plane-fit.md`. **No shipped behaviour changes**: no constant's value moves, no guard is rewired, and no existing assertion is edited.

---

## Decision 49: The candidate bound is a constant of its own, and it carried the radius's movement

**Date**: 2026-08-06
**Status**: accepted (supersedes Decision 46's "do not interpolate" and "fix it first"; re-denominates the bound as Decisions 37 and 38 re-denominated the extent bar and the residue floor; qualifies Decisions 41 and 48)

### Context

Three decisions in a row have been readings *through* the annulus. Decision 46 swept `ringOuterMm`, found the selected plane moving 18.719 mm at the food on `1785901032716`, and attributed the movement to the annulus — the candidate bound, written as `annulusOuterMultiple × ringOuterMm`, which the radius therefore moved with it. Decision 47 supported that attribution by elimination: `ringBandCount` re-cuts the ring without touching the annulus, and the plane does not move at all. Decision 48 varied how many times the annulus may be drawn from.

None of the three could vary the annulus **itself**. The shipped path did not let them: with the bound expressed as a multiple of the radius, there is no radius at which the bound is held still, and no bound at which the radius is. `annulusOuterMultiple` carried no provenance marker — it read "The candidate set is an annulus of 2 × ringOuterMm around the food mask (Decision 15)", which is Decision 15's *comparison against the pre-feature band scan*, not a derivation of the 2 — and it had never been swept.

Decision 46 also left the capture session its hardest instruction: the radius must be fixed **first** and its 22…32 mm bracket **must not be interpolated**, because the intended plate candidate reads 0 crossed sectors at 22, 23, 25, 26, 28, 29 and 31 mm and 2 at 24, 27, 30 and 32 mm. That instruction is only justified if the alternation belongs to the radius.

### Decision

`annulusOuterMultiple = 2` becomes **`annulusOuterMm = 50`**, `[owed]`, bracketed **50…75 mm** by the corpus and by nothing else. The value does not move — `2 × 25` is 50 — so every corpus candidate, every committed scene and every persisted field is unchanged by construction.

**The radius does not move the plane. The bound does.** Over the same 13…40 mm radius sweep with the bound pinned at 50 mm, the selected plane moves **0.000 mm** at the food on both captures — not within a tolerance, exactly. Swept itself at a fixed ring, the bound moves it **18.843 mm** and 1.978 mm, which is Decision 46's number rather than a fraction of it.

Two of Decision 46's riders are **superseded**. The bracket **may** be interpolated: with the bound pinned, the intended plate candidate reads 0 crossed sectors at every radius in the sweep, so the alternation was the annulus re-selecting the candidates. And the radius is **not** fixed first: Decision 45's joint `(ringSectorCount, sectorSupportMin)` pair is a pair again, not a triple, because the radius no longer selects the candidates the other two are read on.

`maxCrossedSectors` acquires a fifth denomination. Decision 48 determined it at 2; that determination holds at `annulusOuterMm` = 50 mm and at no other value in the sweep.

### Rationale

**The decomposition is exact, and it is exact for a structural reason.** `extractCandidates` takes the annulus and nothing else. Pin the bound and every radius is handed the same candidates; the ring still moves, so the *ranking* could still pick a different one — and it does not, at any radius from 13 to 40 mm on either capture.

| sweep | `1785135663727` | `1785901032716` |
|---|---|---|
| radius 13…40 mm, bound coupled (Decision 46) | 4.162 mm | 18.719 mm |
| radius 13…40 mm, bound pinned at 50 mm | **0.000 mm** | **0.000 mm** |
| bound 25…100 mm, ring pinned at 25 mm | 1.978 mm | **18.843 mm** |

Against Req 5.1's 1 mm grid-transfer tolerance, the constant that moves the answer is the bound, and the radius is a bracket-only constant like `ringSectorCount` and `sectorSupportMin`.

**The alternation goes with it.** Decision 46's interior exceptions — 24, 27, 30, 32 mm, and 35 mm above the bracket — are radii at which the intended plate candidate reads crossed sectors. With the bound pinned there are none. A radius between two clean radii is implied by both after all, once the candidate set stops resizing underneath it.

**The value does not move, which is what makes this a re-denomination rather than a change.** Decision 37 converted `minAcceptedExtentPx` to millimetres and Decision 38 converted `minResidueSamples` to mm², both without moving the bar, because the *unit* was wrong: a pixel count and a sample count both track the sensor grid where the surface they stand for does not. Here the unit is a length and it is correct; what is wrong is the **denominator**. Expressing the candidate bound as a multiple of a ring radius makes a measure parameter resize the candidate set, and the measurements above are what that costs.

**The corpus brackets it 50…75 mm, reading `maxCrossedSectors` as Decision 48 reads it** — floor from the plane a correct fit must admit (nearest Req 3.1's zero), ceiling from the ranking's winner where that is a different plane.

| bound | candidates (plate / table capture) | corpus `maxCrossedSectors` |
|---|---|---|
| 25 mm | 2 / 2 | 4…−1 **empty** |
| 31.25 mm | 2 / 3 | 3…unbounded |
| 37.5 mm | 2 / 3 | 3…1 **empty** |
| 43.75 mm | 2 / 3 | 3…−1 **empty** |
| **50 mm (shipped)** | 3 / 3 | **2…2** |
| 62.5 mm | 3 / 3 | 2…4 |
| 75 mm | 3 / 3 | 2…4 |
| 100 mm | 3 / 3 | 6…−1 **empty** |

Below the floor the plane a correct fit must admit is itself crossed, and at 25 mm — where the bound collapses onto the ring — extraction produces two candidates on both captures. At 100 mm the interval collapses the other way: the plate capture's intended candidate reads **6** crossed sectors and a ring median of +1.793 mm as the annulus reaches surfaces beyond the plate. The shipped 50 mm is **on the floor** of that window, as `sectorSupportMin` sits on its ceiling (Decision 45) and `ringBandCount` on its (Decision 47), and it is the only value in the sweep at which the corpus determines `maxCrossedSectors` at 2.

**The committed suite cannot bound it at all**, which is the first time since Decision 41 that a constraint set has been silent. The scenes never run extraction — each asserts against a plane its own test states — so the bound reaches them through exactly two guards, `visibility` and `escaped`, and both are among the five Decision 34 found never fire. Every scene keeps its verdict at 25 mm and at 100 mm alike. Decision 41 predicted the suite would cap constants and it capped three (`ringSectorCount`, `ringOuterMm`, `ringBandCount`); this one it leaves entirely to the captures.

**One side finding, and it belongs to `escapeBandMm`.** Decision 41 read that constant's suite floor as ≥ 14.868 mm. That is an *annulus* median, so it is a reading at the shipped bound: over the sweep the same scenes read 0.131, 0.189, 14.743, 14.821, **14.868**, 14.865, 14.719 and 0.214 mm — a 14.737 mm span, because a wider annulus reaches past the plate a scene sits on and the median goes negative. An owed constant that never fires is denominated in one that moves the answer.

**Req 7.6's latency is denominated here too.** The annulus holds 10 469 and 12 551 samples at the shipped bound and 19 427 and 25 659 at 100 mm, and RANSAC iterates over all of them — so the cost bound is `maxIterationsPerPass × maxCandidatePlanes` over a sample count this constant sets. Task 27 measures that at the shipped value only.

### Alternatives Considered

- **Record the measurement and leave `annulusOuterMultiple` as a multiple** - The finding is the decomposition, not the denomination; the numbers stand either way, and a multiple keeps the ring inside the bound by construction, which becomes an invariant to maintain once the two are independent - Rejected because the coupling is what produced Decision 46's headline and its two instructions to the capture session, both of which are wrong. Leaving it would mean the session fixes `ringOuterMm` first, refuses to interpolate a bracket that is interpolable, and re-reads the count and the bar at each radius — work the measurement shows is unnecessary. The invariant is cheap to keep: `SupportRegionRingTests` already asserts every ring sample is inside the bound.
- **Set `annulusOuterMm = 50` as settled, since the corpus brackets it and the shipped value is inside** - It is on the corpus floor with a measured window above it, and it is the only value at which `maxCrossedSectors` is determined - Rejected because "on the floor" is where Decision 45 found `sectorSupportMin` and Decision 47 found `ringBandCount`, and both stayed owed. The floor is read from two captures of flat bread on a white plate, and the failure at 25…43.75 mm is that the *intended* plane is crossed — a property of the plate-size-to-food-size ratio the corpus fixes and the capture session varies.
- **Widen the bound to 62.5 or 75 mm, where the corpus still holds and the candidate set is larger** - More surface competes, `maxCrossedSectors` stays feasible, and a wider annulus is what a large plate needs - Rejected because it asserts an owed constant to buy a wider bracket on another owed constant, and because it costs Decision 48's determination: at 62.5 and 75 mm `maxCrossedSectors` reads 2…4 rather than 2…2. Req 7.6's cost also rises with it and has not been measured on device.
- **Rewrite Decision 46's test to sweep the radius at the pinned bound** - It would then measure the shipped path rather than a coupling that no longer exists - Rejected because that decision's measurement is the coupled one and this decision's comparison is against it. The test now passes the coupled bound explicitly and says why, which keeps the record and stops the coupling being implied by a helper's default.
- **Derive the bound from the food mask instead — `k × foodRadius`, as the design's rejected alternative had it** - It would scale with the scene rather than being a fixed length, and a small food item would not drag in a metre of table - Rejected on Decision 15's own measurement: `dilate(foodMask, 2 × foodRadius)` spans ~8.3 s² against the pre-feature bands' ~4 s², looser than the code this feature replaces. Nothing here reopens that.

### Consequences

**Positive:**

- The one owed constant that moved the answer is identified, and it is not the one three decisions attributed the movement to. `ringOuterMm` is bracket-only, so `ringSectorCount`, `sectorSupportMin`, `ringOuterMm` and `ringBandCount` are now all constants that move verdicts and not planes.
- Decision 46's two instructions to the capture session are withdrawn: the 22…32 mm bracket may be interpolated, and the radius is fixed beside the count and the bar rather than before them.
- The last constant in `SupportRegion` whose comment stood in for a derivation now carries a marker and a two-sided corpus bracket.
- No shipped value moves and no verdict changes, so the repair costs nothing to verify: 537 XCTest and 312 swift-testing cases pass unchanged.
- `escapeBandMm`'s suite floor is known to be a reading at one bound rather than a property of the scenes, which Decision 41 recorded without qualification.

**Negative:**

- The capture session has one more constant to set, and it is one the committed suite cannot help with — the corpus is its only source, and the corpus is two captures of the same food on the same plate.
- The ring-inside-the-bound invariant was free under a multiple ≥ 1 and is now a constraint the session must respect between two owed constants.
- Decision 48's determination of `maxCrossedSectors` at 2 is now a slice at **five** constants rather than four, and the fifth is the one that changes which planes compete.
- Every plane figure quoted by Decisions 44 to 48 is a reading at `annulusOuterMm` = 50 mm. Those decisions swept constants that do not move the plane, so their verdict brackets stand, but their candidate *sets* were never varied.
- Req 7.6's latency bound is denominated in a constant with an open cost profile, and the corpus's 50…75 mm window spans a 1.5× difference in annulus samples.

### Impact

`MedataCore/Sources/SupportPlane/SupportRegion.swift` (`annulusOuterMultiple` → `annulusOuterMm`, its provenance block, the `ringSamples` derivation, and the superseded riders in `ringOuterMm`'s comment), `MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`theCandidateBoundIsAConstantOfItsOwn`, a `ringSamples(geometry:outerMm:annulusOuterMm:)` taking the bound as an argument, and `coupledBoundMm` so Decision 46's sweep states the coupling it measures), `design.md`, `prerequisites.md`, task 26's detail and `docs/agent-notes/support-plane-fit.md`. **No shipped behaviour changes**: `2 × ringOuterMm` is 50 mm, the constant's new value.

---

## Decision 50: The removal band is what one pass hands the next, and its one stated rule is false

**Date**: 2026-08-06
**Status**: accepted

### Context

Decisions 46 to 49 worked through the constants that decide which planes *compete*. `ringOuterMm` re-rings a candidate set already chosen; `annulusOuterMm` fixes the sample set extraction draws from and is the one that moves the plane; `maxCandidatePlanes` fixes how many times that set may be drawn from. One constant in `SupportRegion` sits between the passes and was in none of those sweeps: `inlierRemovalMultiple = 2`, the shell a pass removes its polished inliers within before the next pass runs.

It is the fourth constant that changes which planes compete, and the only one that decides what each draw *leaves*. It was also the last constant in the file carrying a claim in place of a provenance marker: "a pass removes its polished inliers within 2 × `inlierBandMm`; a 1× shell seeds near-duplicate planes on the next pass". That is a statement about what happens at 1×. Like `ringOuterMm`'s "inside the smallest measured plate margin" (Decision 33) and `ringBandCount`'s "structural: inner / mid / outer" (Decision 47), it had never been measured.

### Decision

`inlierRemovalMultiple` is `[owed]` and **bracketed 1…2.5×** by the corpus, with the shipped 2× strictly inside it. Its stated rule is measured and **false**, so the shipped value has no derivation at all; the floor is structural and the ceiling is the corpus's. It does **not** move the answer. `maxCandidatePlanes` is coupled to it with an order — the removal band is fixed before the residue floor, which Decision 48 already puts before the pass cap.

### Rationale

**The stated rule is false, and not marginally.** Read in the removal's own units — the largest gap between two planes' signed heights taken over the whole annulus, against one `inlierBandMm` — **no** adjacent pass pair anywhere in the sweep is a near-duplicate: 0 of 33 pairs across eight multiples. The closest pair at 1× diverges by **30.807 mm** and the closest at any multiple by **23.973 mm**, nearly five bands. CC-RANSAC is why. A pass keeps the largest *connected* component, so what a 1× shell leaves behind is a thin ring around a surface already taken and it does not form one. The shipped 2× therefore stands on nothing, and the floor cannot come from here.

**It does not move the answer, exactly.** The selected plane at the food is unchanged to **0.000 mm** on both captures at every multiple, because removal happens *after* a pass — pass 1 is drawn from an annulus this constant has never touched — and the ranking picks pass 1 on both captures at every multiple. So it joins `ringSectorCount`, `sectorSupportMin`, `ringBandCount` and (since Decision 49) `ringOuterMm` as bracket-only, and `annulusOuterMm` remains the only owed constant that moves the plane.

**The ceiling is where a shell wide enough to take the table takes the plate with it.** On `1785901032716` the plane a correct fit must select is pass 2, nearest Req 3.1's zero (Decision 48). Its ring median degrades over the sweep and then the candidate stops existing:

| multiple | removal band | natural depth (plate / table capture) | intended ring median on `1785901032716` | corpus `maxCrossedSectors` |
|---|---|---|---|---|
| 1× | 5 mm | 7 / 5 | −2.203 mm | **2…2** |
| 1.25× | 6.25 mm | 5 / 3 | −2.309 mm | **2…2** |
| 1.5× | 7.5 mm | 4 / 3 | −2.377 mm | **2…2** |
| **2× (shipped)** | 10 mm | 3 / 3 | −2.658 mm | **2…2** |
| 2.5× | 12.5 mm | 2 / 3 | −3.011 mm | **2…2** |
| 3× | 15 mm | 2 / 2 | +3.039 mm | 3…unbounded |
| 4× | 20 mm | 2 / 2 | +3.039 mm | 3…unbounded |
| 6× | 30 mm | 2 / 1 | +3.039 mm | 3…unbounded |

At 3× the nearest-to-zero candidate is pass 1, the **table**, carrying 3 crossed sectors of its own, so the guard would have to admit the plane Decision 18 exists to reject. That is Decision 49's floor argument arriving on a second constant. The **floor of 1** is structural rather than measured: below 1× a pass leaves samples it selected within `inlierBandMm` and the next pass can re-find the same plane. The corpus does not raise it — at 1× the intended candidate is still admissible and still separable. Unlike Decision 46's radius the readings are monotone across the sweep, so nothing here forbids interpolating inside the bracket.

**`maxCandidatePlanes` is coupled to it with an order.** Decision 48 lifted the cap to 8 and found extraction stopping at three passes on both captures, starved, and concluded that no value at or above 3 is distinguishable. That reading is at 2×. A narrower shell hands the next pass more residue and extraction runs deeper: at 1× it reaches 7 and 5 passes, so the cap truncates, and the shipped 2× is the **smallest multiple in the sweep at which it does not**. Decision 48's headline is a slice at this constant, and that decision's ordering — residue floor before pass cap — gains a member before both. Req 7.6's latency is denominated here for the same reason, since the RANSAC bound is `maxIterationsPerPass` times the passes actually run.

**The committed suite cannot bound it, and here that is structural rather than measured.** Decision 49's bound reached the scenes through `visibility` and `escaped` and was found silent by measurement. This constant reaches them through nothing: no scene runs extraction — each asserts against a plane its own test states — so no suite reading is even definable. It is the only owed constant of which that is true. One positive comes with it: `maxCrossedSectors` reads **2…2 at every multiple this constant's own bracket admits**, so unlike the candidate bound it does not denominate Decision 48's determination and the sitting sets the two apart.

### Alternatives Considered

- **Leave the comment and record only the bracket** - The numbers stand either way, and the claim about 1× is a design note rather than a shipped bar - Rejected because the claim is the only thing standing where a derivation should be, and it is false. Leaving it means the next reader takes 2× as reasoned when it is not, which is the failure Decisions 33 and 47 both found and repaired.
- **Set the multiple to 1×, since the rule that argued against it is false** - It is the structural floor, it keeps the most surface in play for later passes, and the corpus reads `maxCrossedSectors` 2…2 there - Rejected because it asserts an owed constant, which Req 3.7 forbids, and because it is the multiple at which extraction runs deepest — 7 passes on one capture against a cap of 3 — so it moves the pass cap from idle to load-bearing without any measurement of what the extra candidates are worth.
- **Re-denominate it in millimetres as `inlierRemovalBandMm = 10`, on Decisions 37, 38 and 49's pattern** - Those three re-denominations each removed a dependence a measure parameter had no business carrying - Rejected because there is no dependence to remove. `inlierBandMm` is `[inherited]` from `LiDARPlaneFitter` and is itself in millimetres, so the multiple already transfers across depth grids; expressing removal as a multiple of the band a pass *selected* inliers within is the relation that makes the floor of 1 structural, and millimetres would hide it.
- **Widen it toward 2.5×, the top of the bracket, to end extraction sooner and cut Req 7.6's cost** - Fewer passes is less RANSAC, and 2.5× still reads `maxCrossedSectors` 2…2 - Rejected because it buys latency with the margin on the plate candidate: its ring median is already degrading (−2.658 → −3.011 mm) and 3× is where it disappears. Choosing a value inside a bracket is asserting, and this one is asserting toward the failing end.

### Consequences

**Positive:**

- Every constant in `SupportRegion` now carries a provenance marker; no comment stands in for a derivation anywhere in the file.
- The claim that argued for the shipped value is measured and disposed of, so no future reader treats 2× as reasoned.
- The constant is bracketed two-sidedly, and it is the first owed constant in this feature whose shipped value sits strictly inside its bracket rather than on an edge.
- `maxCrossedSectors` is confirmed **not** denominated in it — 2…2 throughout the admissible range — so the capture session sets the two independently, which is true of no other constant that changes the candidate set.
- No shipped value moves and no verdict changes.

**Negative:**

- The capture session has one more constant to set, and the corpus is its only source — the committed suite cannot express a reading on it at all.
- Decision 48's "the pass cap never fires" is a reading at 2× and not a property of the corpus; the ordering the session must follow is now removal band, then residue floor, then pass cap.
- The floor of 1 is structural, not measured, so the bracket is one-and-a-half-sided in the same way `maxCandidatePlanes`'s was before Decision 48.
- Req 7.6's latency is denominated in a fourth constant, and the pass count over the bracket runs from 7 to 2 on one capture — a wider spread than any other owed constant produces.

### Impact

`MedataCore/Sources/SupportPlane/SupportRegion.swift` (`inlierRemovalMultiple`'s provenance block, and `maxCandidatePlanes`'s coupling note), `MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`theRemovalBandIsWhatOnePassHandsTheNext`, and the removal multiple added as an argument to the parameterised extraction the pass-cap sweep already uses), `design.md`, `prerequisites.md`, task 26's detail and `docs/agent-notes/support-plane-fit.md`. **No shipped behaviour changes.**

---

## Decision 51: The iteration budget is set by the constant that carries no marker

**Date**: 2026-08-06
**Status**: accepted

### Context

`SupportRegion` reaches task 26 with every constant carrying a provenance marker except one. `ransacSuccessProbability = 0.99` says only "Target probability of drawing one outlier-free triple, for adaptive stopping" — a description of what it is, not a record of why it is that. It had never been varied. Its neighbour `maxIterationsPerPass = 2048` is marked `[derived]` and carries a paragraph: "the budget is sufficient because extraction is SEQUENTIAL — pass 1 removes the table — not because the pass-1 inlier ratio is high (it is ~6 %, where 2048 iterations reach ~36 %)".

The two are one mechanism. `requiredIterations` returns `min(maxIterationsPerPass, log(1 − p) / log(1 − w³))`, so whichever end of that clamp is smaller is the constant that actually sets a pass's budget, and the shipped code never reports which. Decision 46 gave the question weight: held at the shipped radius over eight RANSAC seeds the selected plane moves 2.095 mm at the food, so every plane figure Decisions 40 to 50 quote carries about 2 mm of draw dependence. That decision recorded the caveat and could not say what it was denominated in — the budget was the one input never swept.

### Decision

Mark `maxIterationsPerPass` `[measured]` with its stated derivation withdrawn and replaced: it never fires on this corpus, and it is bracketed 128…unbounded from below. Mark `ransacSuccessProbability` `[owed]`, bracketed 0.9…unbounded, and record that it is the constant that sets every pass's budget and the one Decision 46's draw dependence is denominated in. Do not choose a value inside either bracket.

### Rationale

The clamp is measured at both ends, per pass, on both captures. The passes spend 72, 11, 250 and 12, 41, 5 iterations against a cap of 2048: the target is always the smaller, so **`maxIterationsPerPass` never fires**, the third thing in the file of which that is true after Decision 48's pass cap and Decision 34's five guards. The largest draw the corpus ever needs is 250, so the cap truncates nothing at or above 256.

That makes the `[derived]` argument checkable, and its own quantity refutes it. The pass-1 inlier ratio is measured at **0.402 and 0.698**, six to twelve times the ~6 % the comment quotes; at those ratios a 0.99 target is met in 69 and 12 iterations. The budget is sufficient because the dominant plane is easy, not because extraction is sequential.

The target is the live half, and it moves the answer — which only `annulusOuterMm` otherwise does. Swept 0.5…0.99999 at the shipped cap the selected plane at the food moves **3.704 mm** on `1785135663727` (351.620, 349.473, 353.130, 351.328, 349.426, 349.426 mm), past the 1 mm Decision 35 measures Req 5.1's transfer at. The readings wander rather than climb, so like Decision 46's radius and unlike Decision 50's removal band **the bracket must not be interpolated**.

And it is what Decision 46's caveat is denominated in, measured rather than inferred by elimination: that decision's eight-seed control was re-run against each end of the clamp. Against the **cap** the spread does not move at all — 1.992 mm at 64 and 2.095 mm at 256, 2048 and 8192 — because the cap is not what ends a pass. Against the **target** it collapses **2.095 → 0.194 mm** from 0.99 to 0.99999, a 10.8x fall that takes it under the Req 5.1 bar. So the draw dependence every bracket in Decisions 40 to 50 carries is neither a property of the captures nor a price of the cap: it is this constant, and it is removable.

The brackets follow. The cap's floor is 128: at 64 the sector verdict on `1785135663727` flips from 5 supporting / 0 crossed to 3 / 2 — the guard every one of those brackets is read from — and at 32 the plane moves 1.9 mm, while at 128 and above it is the shipped plane to 0.000 mm. Its ceiling stays open because above the largest required draw there is nothing to distinguish; what sets it is Req 7.6's worst-case latency, and the scene where it would fire is a low-inlier-ratio one the corpus does not contain. The target's floor is 0.9: `1785901032716` is draw-stable at 0.001 mm at every value from 0.9 up and jumps to 2.376 mm at 0.5. Tightening it is paid for out of the cap's 8x headroom, so the two do not compete.

### Alternatives Considered

- **Leave the pair as shipped and record only the missing marker**: Annotate `ransacSuccessProbability` as `[derived]` from the cap's paragraph and move on - Rejected because the paragraph is about the wrong constant. Attaching the cap's sufficiency argument to the target would document a value that moves the plane 3.704 mm as though it were settled, which is the circularity Req 3.7 forbids.
- **Set `ransacSuccessProbability` to 0.99999 now**: The corpus shows draw dependence falling under the Req 5.1 bar there, and the cap has the headroom to pay for it - Rejected because it is choosing a value inside a bracket, which Req 3.7 forbids for exactly these constants, and because the readings wander rather than climb, so 0.99999 being the best of six sampled values is not evidence that it is the right one.
- **Retire the cap, since it never fires**: Decision 32 retired `minCandidateSamples` on similar grounds - Rejected because the two cases differ. That constant was provably outcome-identical to a bar already measured; this one is a worst-case latency bound for a scene the corpus lacks, and removing it would leave `ccRansac` unbounded on exactly the low-inlier-ratio input it exists to survive.
- **Re-read Decisions 40 to 50's brackets at a tighter target**: The draw dependence they carry is now known to be removable - Rejected as premature. The target is bracketed, not set; re-reading every bracket at a value that has not been chosen would produce a second set of readings owed to the same sitting.

### Consequences

**Positive:**

- Every constant in `SupportRegion` now carries a provenance marker, and none rests on a quantity the corpus contradicts.
- Decision 46's caveat on the whole feature — about 2 mm of draw dependence in every plane figure Decisions 40 to 50 quote — is denominated for the first time, and shown to be removable rather than intrinsic.
- The first owed constant that the committed corpus alone can bracket and set, needing no capture session. Every other one waits on the sitting or on Bucket C.
- The cap's `[derived]` marker no longer rests on a pass-1 inlier ratio that is wrong by an order of magnitude.

**Negative:**

- Task 26 gains an owed constant rather than losing one, and it is one that moves the answer.
- The brackets Decisions 40 to 50 read are now known to be quoted at a draw dependence that a different target would remove, so some of them may need re-reading once the target is fixed.
- The corpus is two captures of flat bread on a plate, so the cap's ceiling and the scene in which it would fire are both outside what can be measured here.
- The measurement is the slowest in the suite (about 70 s), because the eight-seed control now runs against both ends of the clamp.

### Impact

`MedataCore/Sources/SupportPlane/SupportRegion.swift` (`maxIterationsPerPass` and `ransacSuccessProbability` provenance blocks, and `ringOuterMm`'s seed-control note), `MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift` (`theIterationBudgetIsWhatTheSeedSpreadIsDenominatedIn`, with `ccRansac` and the pass chain parameterised on the budget pair), task 26's detail. **No shipped behaviour changes.**

---

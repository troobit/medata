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
- The **Decision 46 tension is resolved in kind, not in value**. Decision 46's 20 mm bar is a whole-plane residual over a matte table; `ringBandMm = 5` is a per-sample window. They are not the same quantity and were never in conflict. The per-sample figure is measured below and is what `ringSupportMin` actually rests on.

**Not settled, and why.** `ringSupportMin`, `sectorSupportMin`, `ringSectorCount`, `minSupportingSectors`, `ringSupportMarginMin`, `ringOuterMm`, `bandStepMaxMm`, `foodEnvelopeMinMm`, `minCandidateSamples`, `minAcceptedExtentPx`, `supportVisibilityMin`, Req 4.5's fallback-rate threshold, Req 5.1's tolerance and `fallbackPenalty` all stay `[owed]`. The corpus cannot set them for two measured reasons.

> **`minCandidateSamples` is superseded by Decision 32.** It was two constants under one name. Its whole-fit half is retired — `fitFoodSupportPlane` now tests ring-band feasibility against the already-`[measured]` `ringMinSamples` — and its extraction-pass half survives as `minResidueSamples`, still `[owed]` but bounded above at 581 by this same pass. `minAcceptedExtentPx` also stays `[owed]` and gains a corpus bracket of 13…26.

*The corpus contains no clean correct-fit case.* On `1785135663727` the plate-top candidate reads a ring median of −0.93 mm and a support fraction of 0.629, but its per-sector inner-band medians are `[+3.7, −0.4, +0.8, +1.4, −6.8, −32.6, −9.7, +3.8]`: sectors 4–6 form a contiguous arc sitting up to 32.6 mm below the plate, so the ring genuinely escapes onto the table over ~135°. On `1785901032716` the highest-support candidate is **the table, not the plate** — its per-sector medians are `[+16.6, +4.4, +3.0, +6.0, +19.8, +18.0, +4.7, +0.4]`, with three sectors a plate-height above it. Both captures are near-instances of the Req 3.6 silent-failure geometry rather than clean successes, so a bar fitted to make them pass would be fitted to the wrong side.

*Per-sample noise on a flat surface straddles `ringBandMm`.* The tightest inner-band mode — robust σ over samples within 15 mm of the band median, taken across every candidate so a contaminated winner cannot set it — measures **3.44 mm** on `1785135663727` (over 75.5 % of the band) and **6.98 mm** on `1785901032716` (over 92.0 %). At essentially the same range, 338.9 mm against 336.9 mm, that is a 2× disagreement, so it is a *surface* difference and not a range one — which is what Decision 46's matte-table evidence predicts. `ringBandMm = 5` falls between the two, and `ringSupportMin = 0.6` is a statement about exactly this distribution.

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

- Four constants move from asserted to measured, and two `prerequisites.md` items — the `ringInnerMm` smear envelope and the Decision 46 tension — are closed without a capture session.
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
**Status**: proposed

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

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

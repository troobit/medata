# Decision Log: Alternative Class Candidates

## Decision 1: Own spec in the estimation domain rather than an extension of `ui/meal-review`

**Date**: 2026-08-07
**Status**: accepted

### Context

`ui/meal-review` Decision 13 established that a relabel shortlist should be ordered by per-class candidate evidence rather than by `perClassMeanProb`, which is the wrong quantity. Decision 18 then deferred the work: specifying it properly grew the estimation-side change rather than shrinking it — a new pass over the full-resolution probability tensor on the timed capture path, a new message on the meal record, a `PaletteMigrator` obligation, and a device performance measurement, all inside a spec filed under `ui/`. That spec shipped recency ordering instead, and recorded that a second spec was owed.

`PROCESS.md` §3 fixes the boundary: a new spec is warranted where the work delivers a capability with its own acceptance bar, and a cross-domain capability gets one home — the domain whose acceptance criteria dominate.

### Decision

`specs/estimation/alternative-class-candidates/`, a full spec in the `estimation` domain. It owns the retained quantity and its persistence; `ui/meal-review` owns the surface that consumes it and is referenced, not restated.

### Rationale

The acceptance criteria are about what the segmentation stage retains, what it costs on the capture path, and whether the retained quantity survives palette migration and harness replay. Every one of those is an estimation concern. The only user-visible consequence is the order of a list that already works — Req 7.1 makes ordering the whole of the change, and Req 7.4 forbids it from altering which foods are reachable.

The name is what it delivers, not the layer or the effort: alternative class candidates. Not `shortlist-ranking` (names the consumer's feature), not `candidate-matrix-v2` (effort/phase), not `segmentation-improvement` (vacuous, and this improves nothing about segmentation itself).

Full spec rather than smolspec: `PROCESS.md` §5 requires the full loop for anything touching the estimation maths, the data model, or a public contract. This touches all three — a post-processing pass, `PbMealRecord`, and the portable record contracts in `MedataCore/Sources/PortableContracts`.

### Alternatives Considered

- **Extend `ui/meal-review` with a new requirement section**: No new folder, and the shortlist requirement lives beside its ordering source - Rejected because it puts a pipeline change and a device performance bar inside a `ui/` spec, which is exactly what Decision 18 refused; and `ui/meal-review` is already through its design gate, so re-opening it would reset a completed phase.
- **Extend `estimation/segmenter-foundation`**: The segmenter's own spec, already in flight - Rejected because that spec's acceptance bar is mean IoU against staple floors. This adds no accuracy and would be judged against a bar it cannot move.
- **Smolspec**: The pass is arguably small - Rejected on `PROCESS.md` §5: estimation path, data model and a public contract each independently require the full loop.

### Consequences

**Positive:**
- The estimation change is judged against an estimation bar (Req 8.1: measured shortlist hit rate) rather than against a UI impression.
- `ui/meal-review` can ship and be used before this exists; `shortlist_source` already partitions the corpus across the transition.
- The spec has one deliverable and can be dropped whole if Req 8.1 does not improve.

**Negative:**
- Two specs must agree on the seam. Req 7 states it explicitly, but a change to `ui/meal-review` Req 3.1–3.4 now requires checking this spec.
- The owed work is now visible and unstarted rather than quietly folded into a larger spec.

---

## Decision 2: Retain candidate evidence beside `perClassMeanProb`, leaving that contract unchanged

**Date**: 2026-08-07
**Status**: accepted

### Context

`perClassMeanProb` is the natural place to look for this quantity and cannot supply it. `PostProcessing.swift:172-178` increments `perClassSum[cId]` and `perClassCount[cId]` only for the class that **won** the argmax at that pixel, so the resulting map is keyed only on classes already detected — each of which already has its own row in the estimate — and its value is the winner's own mean top probability. It is a per-class confidence readout, and it is doing that job correctly.

It is also a persisted, tested contract: `SegmentationResult.perClassMeanProb` (`SegmentationTypes.swift:60`), surfaced through `CoreMLSegmenter.swift:133`, with dedicated coverage at `PostProcessingTests.swift:234-253` asserting exact values and the exclusion of background.

### Decision

Introduce candidate evidence as a new retained quantity. `perClassMeanProb` keeps its current definition, its field, and its tests, unchanged (Req 2.2).

### Rationale

The two answer different questions — "how sure was the winner" and "what else might this be" — and both are wanted. Redefining `perClassMeanProb` to mean the second would silently change a value that σ_seg reporting and existing tests read, for no gain, since the new quantity needs its own shape anyway: a ranked set per detected class, not one scalar per class.

Leaving it alone also keeps this spec's blast radius honest. Req 2.2 can then be a flat prohibition — nothing existing changes — which is a far cheaper thing to verify than a diff of two similar-looking maps.

### Alternatives Considered

- **Redefine `perClassMeanProb` as the candidate matrix**: One quantity instead of two, no new field - Rejected because it changes the meaning of a persisted contract and its tests to express something of a different shape, and destroys a confidence readout that is currently correct.
- **Derive candidates on demand from the capture bundle**: No pipeline change and no new field at all — the full probability tensor is already written to the bundle - Rejected because the bundle is ~200 MB and would have to be read during a screen transition, and because bundles are not retained for every meal, so the shortlist would work only for some captures.

### Consequences

**Positive:**
- No existing value, test, or reader changes; Req 2.2 is verifiable by inspection.
- The confidence readout and the candidate readout can evolve independently.

**Negative:**
- Two similarly-named per-class maps now exist, and the difference between them is precisely the mistake `ui/meal-review` Decision 13 made. The naming must make it hard to repeat.

---

## Decision 3: Compute candidates over the persisted mask, not the raw argmax

**Date**: 2026-08-07
**Status**: accepted

### Context

Where the accumulation happens decides both what it costs and what it means.

The existing σ_seg accumulation (`PostProcessing.swift:164-182`) runs **before** `regulariseLabelMap` (`:201`), deliberately — the comment at `:193-200` records that σ_seg, the silhouette test and `perClassMeanProb` are computed from the raw argmax so they stay byte-identical to the pre-cleanup pipeline, while the cleanup reshapes only the label map that feeds the overlay, `MaskArtefactWriter` and the volume stage. Accumulating candidates in that loop would be nearly free: it is a serial pass already touching `resized[off + cId]`, and extending it to all channels turns an O(pixels) loop into an O(pixels × classes) one.

Nearly free, and answering the wrong question. The pixels the user sees outlined, and the pixels whose volume produced the carbohydrate figure, are the **cleaned** ones. Candidates gathered from the raw argmax would describe a region that speckle removal has since altered.

Two figures in `ui/meal-review` Decision 18 are corrected here. The tensor is 36 channels, not 33 — `ClassPalette.v2Standard` is 25 solid + 8 liquid + background + `unknown_food` + `unsupported_liquid` — so a full-resolution pass at 1920 × 1440 is ~99.5 M reads, not ~91 M. And the loop that decision proposed extending is serial, not parallelised; the parallelised pass is the argmax at `:141-152`, which runs before regularisation too.

### Decision

Candidate evidence is computed over the pixels the **persisted** mask assigns to each detected food — the regularised label map — and not over the pre-regularisation argmax (Req 2.1).

### Rationale

A shortlist is offered against a region the user is looking at. If the evidence describes different pixels than the outline does, the shortlist is answering a question nobody asked, and the discrepancy is invisible: both sets look plausible and neither can be checked from the record.

It also keeps the retained quantity consistent with the volume and macro figures, which are computed from the cleaned map. A correction record pairs the prediction, the figures, and the alternatives offered; those three describing two different pixel sets would poison the corpus this whole line of work exists to build.

The cost of that choice is a separate pass rather than a free ride on an existing loop. Requirement 3.1 bounds it at 50 ms median on the hardware floor and Req 3.3 makes the pass abandonable, so the correctness choice cannot become a capture-latency regression. Whether the pass runs at full resolution or on a reduced grid is a design question and is deliberately left open here.

### Alternatives Considered

- **Accumulate in the existing σ_seg loop, pre-regularisation**: Nearly free — the loop, the tensor and the offsets are all already in hand - Rejected because it describes pixels that speckle removal then changes, so the alternatives offered would not match the region outlined or the volume measured.
- **Regularise earlier so one pass serves both**: One pass, and everything agrees - Rejected because `PostProcessing.swift:193-200` shows σ_seg's byte-identity with the pre-cleanup pipeline is a deliberate, documented contract; moving the cleanup earlier changes σ_seg for every capture, which is a segmentation-accuracy change smuggled in under a shortlist feature.
- **Accept the mismatch and document it**: No cost at all - Rejected because the mismatch is unobservable from the record, which makes it the worst kind of defect for a corpus intended to outlive the code that wrote it.

### Consequences

**Positive:**
- The alternatives, the outline and the volume all describe the same pixels.
- σ_seg, the refusal predicate and `perClassMeanProb` are provably untouched (Req 2.2).

**Negative:**
- A distinct pass over the probability tensor, with a latency budget to defend on the hardware floor.
- The pass runs on the timed capture path while `support-plane-reference` is rewriting the volume path in the same package; sequencing needs care.

---

## Decision 4: Absence of candidate evidence must be distinguishable from an empty set

**Date**: 2026-08-07
**Status**: accepted

### Context

Three situations produce a record with no candidates, and they mean different things:

1. The record predates this spec.
2. Candidates were computed and nothing qualified — no other class carried support over that food's pixels.
3. The pass was abandoned under the Req 3.3 budget escape, or the evidence was discarded by a palette migration (Req 5.1).

A proto3 map cannot tell them apart: an absent map and an empty map decode identically. A consumer that cannot distinguish them either reports "the shortlist offered nothing" for records that were never eligible to offer anything, or falls back to recency for records where the model genuinely had nothing to say — and Req 8.1's measurement, which is the whole acceptance bar, is computed over exactly this population.

### Decision

The record carries an explicit marker of whether candidate evidence was produced for it, independent of how many candidates resulted (Req 4.3). A migration that discards evidence leaves the record indistinguishable from one that never carried it (Req 5.2).

### Rationale

Req 8.1 measures how often the chosen food was in the shortlist offered. That denominator is "captures where a shortlist could be ordered by evidence", and without the marker it is not computable — old records would silently inflate the miss rate and make the feature look worse than it is, or be excluded by a heuristic that is itself unverifiable.

Requiring it at the requirements level rather than leaving it to design is deliberate: it is the kind of distinction that is free to build in and impossible to reconstruct afterwards, because the records that need it are already written by then.

Migration is folded into case 1 rather than given a fourth state because nothing consumes the difference: a migrated record has no evidence under its current palette and cannot get any without re-running segmentation, which Req 3.2 forbids. Collapsing it keeps the marker binary.

### Alternatives Considered

- **Treat empty as absent**: Simplest, no extra field - Rejected because it makes the acceptance bar uncomputable and biases it in the flattering direction, which is the worst way for a measurement to be wrong.
- **Infer from the record's schema or build stamp**: The build stamp is already retained per correction record - Rejected because it would be right only by coincidence: the Req 3.3 budget escape and a palette migration both produce evidence-free records under a build that supports evidence.
- **Store a sentinel candidate meaning "none"**: No schema change beyond the map - Rejected as a value that every reader must know to filter out, and that a naive reader will show to a user as a food.

### Consequences

**Positive:**
- Req 8.1 is computable without heuristics, over the exact population it should cover.
- The Req 3.3 escape hatch can be used freely without corrupting the measurement.

**Negative:**
- One more field on the record, which must be set on every write path including the harness (Req 6.1) or it will be wrong in the direction that looks fine.

---

## Decision 5: A neutral result is a valid outcome, and the bar is measured against recency

**Date**: 2026-08-07
**Status**: accepted

### Context

`ui/meal-review` ships recency ordering. That is not a placeholder that obviously loses: on a universe of 25 solid classes, a five-item shortlist already covers a fifth of the candidates, the full list is one interaction away, and people eat the same foods repeatedly — recency is a strong prior for a single-user app. It is entirely possible that model-derived candidates order no better.

This spec is being written because the model's own evidence is being discarded, which is a real waste. That is a reason to measure, not a reason to assume the answer.

### Decision

The acceptance bar is a measured increase in shortlist hit rate (Req 8.1) against **the recency prior alone** as the baseline (Req 8.3), drawn from the same corpus, on the hardware floor, within the Req 3.1 latency budget. The result is reported split by whether the user had chosen the corrected class before (Req 8.4). A neutral or negative result is recorded as the outcome and the retained field is left in place or removed on its own merits; it is not tuned around.

### Rationale

`shortlist_source` on every correction record (`ui/meal-review` Req 3.3) makes this comparison available for free — the corpus partitions into recency-ordered and candidate-ordered rows and the same metric runs over both. Building the measurement into the acceptance criteria is what stops this from becoming a feature that is kept because it was expensive.

The same pattern is already the repository's practice: `segmenter-foundation` Decision 24 recorded a NEGATIVE verdict on a training recipe and kept the incumbent model, and `snaq-parity` is explicitly scoped to "complete on evidence-backed verdicts, not on hitting the target". A shortlist ordering deserves no more indulgence than a model does.

### Alternatives Considered

- **Ship on the reasoning alone**: The evidence is obviously better than nothing, and the pass is cheap - Rejected because "obviously better" is exactly the claim `perClassMeanProb` failed, and a wrong ordering costs capture latency on every meal forever.
- **Bar it on offline dataset accuracy instead of the live corpus**: Faster to run, no waiting for real corrections - Rejected because the question is which ordering puts the food *this user* wanted in the top five, and a dataset's class distribution is not this user's diet.

### Consequences

**Positive:**
- The spec can be judged, and dropped, on evidence rather than sunk cost.
- The baseline costs nothing to collect: `ui/meal-review` is already recording it.

**Negative:**
- The verdict cannot be reached until enough recency-ordered corrections exist, so this spec's closure is gated on real use of the surface that precedes it.
- A neutral result still leaves the retained field on the record and the pass on the capture path until a removal is done.
- Splitting the measurement by first-versus-repeat correction (Req 8.4) shrinks each cell, so a verdict on the first-correction case needs more corpus than an aggregate one would.

---

## Decision 6: The recency prior is a component of the ordering, not the thing being replaced

**Date**: 2026-08-07
**Status**: accepted, amends Decision 5

### Context

The spec was first written with candidate evidence **superseding** recency: order by evidence where the record carries it, fall back to recency where it does not. That framing treats recency as a stop-gap that this spec retires.

It is not one. MeData is a single-user app whose owner eats the same foods repeatedly, so "what this person chose before for a food that looked like this" is a strong prior over a 25-class universe — strong enough that a five-item shortlist drawn from it will often be right on the first entry. `ui/meal-review` Decision 18 already conceded as much when it shipped recency, calling ordering "a convenience rather than a functional gate".

The prior has one structural gap: a food the user has never chosen carries no recency at all. That is precisely the case where the segmenter was wrong about something new, and precisely where the model's own runner-up is the only evidence available.

### Decision

The shortlist is ordered by a fixed, stated, deterministic combination of the recency prior and candidate evidence (Req 7.1, 7.5). Recency is retained as a live component: a food carrying recency is never demoted for lacking candidate evidence (Req 7.2), and a record with no candidate evidence yields exactly the shortlist `ui/meal-review` would have produced (Req 7.4).

### Rationale

Superseding a strong prior with an unproven signal risks a regression on the common case — repeat foods — to win the rare one. Combining them makes the downside bounded: the worst case for the new signal is that it adds nothing, not that it displaces something better.

It also changes what the acceptance bar means. Under the superseding framing the comparison was "evidence versus recency", and losing meant reverting. Under the combining framing the comparison is "recency plus evidence versus recency alone" (Req 8.3), losing means deleting an addition, and no correction path regresses either way. That is a cheaper experiment for the same information.

Requiring the combination to be *fixed and stated* (Req 7.5) rather than learned keeps this a single question. A weighted blend tuned against the corpus would confound "does the model's evidence help" with "was the weighting fitted well", and the first question has to be answered before the second is worth asking — hence the explicit non-goal.

Req 8.4's first-versus-repeat split follows directly: if the gap the evidence fills is first corrections, the aggregate number is dominated by exactly the population where it cannot help, and a real gain would be diluted below detection.

### Alternatives Considered

- **Candidate evidence supersedes recency where present** (the original framing): Simpler ordering, one signal at a time, and the model's evidence is the more principled quantity - Rejected because it stakes the common case on an unproven signal, and because a negative verdict then means reverting an ordering rather than removing an addition.
- **Two separate shortlist sections, recency then candidates**: Both signals visible, neither displaces the other, and no combination rule is needed at all - Rejected because `ui/meal-review` Req 3.2 caps the shortlist at five before further interaction; splitting it into two sections spends that budget on structure rather than on candidates, and the user does not care which signal produced an entry.
- **Learn the weighting from the corpus**: Adapts to the actual user rather than assuming a combination - Rejected as premature: it cannot be evaluated until the fixed combination has shown the second signal carries information, and it would make a negative result uninterpretable.

### Consequences

**Positive:**
- No correction path can regress: the worst case is the shipped ordering, unchanged.
- The acceptance bar tests one thing — whether the model's evidence adds anything to a prior that already works.
- Req 7.4 gives a free correctness check: on a record without evidence, the two orderings must be byte-identical.

**Negative:**
- A combination rule is now a design obligation with its own justification, where superseding needed none.
- Two signals ordering one list makes an individual shortlist harder to explain after the fact; `shortlist_source` (Req 7.6) records which ordering ran, not why a given entry placed where it did.
- The recency prior stays on the read path permanently, so its cost is never recovered even if candidate evidence proves dominant.

---

## Decision 7: Recency first, evidence fills the remaining slots

**Date**: 2026-08-10
**Status**: accepted

### Context

Decision 6 made the combination rule a design obligation: fixed, stated, deterministic (Req 7.5), with recency never regressing. Two candidate shapes survived: evidence fills only the slots recency leaves empty, or an interleave in which evidence can promote a candidate above a recency item subject to a "no recency item ends lower than its recency-alone position" floor.

### Decision

*(Amended same day after design-critic review: the shipped shortlist is not recency alone — `buildShortlist` tops up from the eligible list after recency. The rule below states all three layers.)*

The combined ordering has three layers: (1) recency entries in their exact shipped positions; (2) candidate evidence fills, in descending mean-probability order with ties broken by palette declaration order, skipping entries already present; (3) the shipped eligible top-up for any slots still empty. Evidence displaces only the blind top-up, never a recency entry; with no evidence the result is byte-identical to the shipped list. `shortlist_source` takes a new value (`recency_plus_candidates`) exactly when the record's produced-marker is true — the ordering that ran, independent of whether the fills changed anything.

### Rationale

The worst case is literally the shipped shortlist, which makes Req 7.2 and 7.4 verifiable by construction rather than by argument. The interleave's extra power serves repeat foods — exactly the population recency already wins (Decision 6) — while its cost lands on the same population when a promotion is wrong. The gap this spec exists to close is first corrections, and fills address precisely that gap. Tying the source value to the marker rather than to "did a fill land" keeps the Req 8.2 partition well-defined: an empty evidence set under the combined ordering is a combined-population row, not a recency row.

### Alternatives Considered

- **Interleave with a recency floor**: more room for the model signal - Rejected: harder to state and verify, spends its power on the population recency already serves, and a mis-promotion costs a repeat-food correction an extra glance on every meal.
- **Source value only when a fill landed**: partitions by observable difference - Rejected: makes the partition depend on plate content rather than on the code path, so identical builds produce mixed populations and Req 8.3's baseline comparison muddies.

### Consequences

**Positive:**
- Req 7.2/7.4 hold by construction; the Req 7.4 byte-identity check is a trivial test.
- The acceptance measurement isolates one question: do evidence fills get chosen.

**Negative:**
- Evidence can never outrank recency even when the model is near-certain; if the corpus later shows strong fills being chosen from low slots, an interleave revisit is a new decision against real data.

---

## Decision 8: Stride-4 sampled accumulation with an eight-class cap

**Date**: 2026-08-10
**Status**: accepted

### Context

Decision 3 left the pass's grid open: full resolution is ~99.5 M reads (1920 × 1440 × 36), comparable to the argmax pass — one of the two dominant passes in post-processing — and Req 3.1 allows 50 ms median on the hardware floor, with Req 3.3 requiring the pass be abandonable. Separately, Req 4.4's 1 KB record budget cannot survive a pathological plate (25 detected classes × 5 candidates).

### Decision

The pass samples the regularised label map on a fixed stride-4 grid in both axes, anchored at (0,0) — ~6.2 M reads, 1/16 of full resolution. Candidate sets are retained for at most the eight detected classes with the most sampled pixels (ties by declaration order). Both bounds are deterministic and identical on device and replay.

### Rationale

The budget is met by construction, so no timeout machinery runs on the capture path and Req 3.3's escape reduces to the structural case (no tensor available). A ranking needs relative means, not exact ones: at stride 4 a food still contributes one sample per 16 pixels, and a food too small to sample meaningfully carries no usable evidence anyway — its absence is the honest output. Determinism (Req 7.5) and replay parity (Req 6.1) fall out of a fixed grid where a timeout-based abandon would break both. The eight-class cap bounds the record at ~960 B worst case while covering any realistic plate.

### Alternatives Considered

- **Full-resolution parallel pass with an elapsed-time abandon**: exact means - Rejected: rivals the argmax pass's cost on every capture, and the abandon path makes evidence presence timing-dependent — a replay could produce evidence the device abandoned, violating Req 6.1's spirit and making the Req 8 population depend on device load.
- **Resolution-adaptive stride targeting a fixed sample count**: bounds work for any future camera - Rejected for now: one more parameter to state and replay; the capture resolution is pinned in the pipeline today, and a future resolution change fails loudly in the latency measurement rather than silently.

### Consequences

**Positive:**
- No timing dependence anywhere in the evidence path; device and harness agree bit-for-bit.
- Worst-case capture cost and record size are both fixed at design time.

**Negative:**
- Means are estimates over 1/16 of the pixels; a genuinely borderline candidate ranking can differ from the full-resolution answer (unobservable in practice — both are valid orderings of an estimate).
- Foods smaller than the stride can carry no evidence; the record shows a produced marker with no entry for them, which consumers must treat as "nothing usable", not "error".

---

## Decision 9: One shared compute function; harness parity by construction, not by pipeline reuse

**Date**: 2026-08-10
**Status**: accepted

### Context

Req 6.1 requires a replayed capture to produce the device's evidence given the same tensor and palette. The device computes evidence inside `PostProcessing`; the harness does not run `PostProcessing` at all — `FixtureRunner` synthesises a `SegmentationResult` directly from a fixture's cached probabilities and argmax. Any design that puts the evidence computation only inside the device pipeline makes replay parity impossible without duplicating code, and duplicated accumulation loops are exactly how the Decision 17 (cross-dataset-calibration) class of drift starts.

### Decision

The computation is one pure static function, `CandidateEvidence.compute(probabilities:labelMap:palette:)`, in the Segmentation module. `PostProcessing` calls it with the regularised map on device; harness replay paths call it with the fixture's tensor and persisted argmax. `SegmentationResult` gains an optional `candidateEvidence` field (default nil) so every existing constructor and hand-built test result is untouched.

### Rationale

Parity by construction is the only kind that survives maintenance: there is no second implementation to drift. The function is pure over value types already shared by both sides (`ProbabilityTensor`, `ArgmaxMap`, `ClassPalette`), so the seam costs nothing. The optional field keeps Req 2.2's blast radius flat — nil means "not produced" and doubles as the source for the Decision 4 marker at record-assembly time.

### Alternatives Considered

- **Run the full PostProcessing in the harness**: one pipeline - Rejected: the harness deliberately consumes cached segmenter outputs (no Core ML on macOS runners, and fixtures pin the tensor); rerunning post-processing would recompute σ_seg and the label map, changing replayed figures that are currently byte-stable.
- **Compute in the harness from the persisted meal record instead of recomputing**: no harness call site - Rejected: Req 6.1 is a parity check of the computation; reading the answer back verifies nothing.

### Consequences

**Positive:**
- One implementation; the parity test is two calls to the same function plus a golden.
- Hand-built `SegmentationResult`s across the test suites compile unchanged.

**Negative:**
- The function's inputs must stay expressible in fixture terms; any future dependence on device-only state (e.g. capture timing) would break the seam and must be refused at review.

---

## Decision 10: Parallel-array permille encoding and a five-set cap, sized against the persisted JSON

**Date**: 2026-08-10
**Status**: accepted, amends Decision 8

### Context

Design-critic review caught the Req 4.4 arithmetic being computed in an encoding the record is not stored in. Meal records persist as protobuf-**JSON** (the persistence layer's Decision 31; `MealRecord.jsonString()`), where a nested per-candidate object (`{"className":"mixed_vegetables","meanProb":0.123456}`) costs ~50 B — Decision 8's eight-set cap lands at ~2.2 KB worst case, over double the budget. Worse, Req 1.1's unconditional "each detected food", Req 1.5's five candidates, and Req 4.4's 1 KB are jointly unsatisfiable on a pathological 25-class plate in any reasonable JSON shape: the requirements needed an amendment, not just a smaller constant.

### Decision

`CandidateSet` persists as parallel arrays — `repeated string class_names` (ranked) plus `repeated uint32 mean_permille` (0…1000) — and evidence is retained for at most the **five** detected classes with the greatest sampled-pixel support (ties by declaration order). Requirements amended at the gate: Req 1.8 sanctions the budget cap explicitly; Req 4.4 binds the budget to the persisted encoding. Worst case (5 sets × 5 longest-name candidates) ≈ 1.0 KB of JSON, asserted by a test rather than assumed. Equal-length arrays are a writer-enforced, reader-checked invariant; a mismatch reads as no evidence for that class.

### Rationale

The budget is only real in the bytes that actually land in SQLite. Parallel arrays remove the per-candidate object framing (the dominant JSON cost), and permille quantisation both shortens the literal and honestly reflects the magnitude's role — it exists to order five entries, not to carry six significant figures into a corpus analysis. Five sets cover any realistic plate; the cap binds only on plates whose long tail of tiny detections carries no usable evidence anyway, and Req 1.8 makes the truncation deterministic and observable rather than an undocumented exception to Req 1.1.

### Alternatives Considered

- **Keep nested candidate objects, cap at three sets**: fits the budget without a new shape - Rejected: three sets is below a realistic plate's detected-class count, so the cap would bind routinely rather than pathologically.
- **Store ranked names only, no magnitude**: smallest possible (~0.9 KB at eight sets) - Rejected: Req 1.3 requires each candidate carry a magnitude, and the margins are the only signal a future corpus analysis of "how close was the second guess" could use.
- **Re-scope Req 4.4 to binary proto**: makes Decision 8's arithmetic true - Rejected: the record is not stored in binary proto; a budget met in an encoding not in use protects nothing.

### Consequences

**Positive:**
- The Req 4.4 bound holds in the bytes that exist, with a test asserting it on the worst case.
- The requirements are again jointly satisfiable, with the cap visible in the spec rather than smuggled in by design.

**Negative:**
- Parallel arrays are uglier than nested messages and need the length-invariant check at every reader.
- Permille quantisation caps future analysis resolution at 0.1 %; margins tighter than that are indistinguishable in the corpus.

---

## Decision 11: A pre-implementation probe fixes the ranking statistic; a 64-sample floor guards small foods

**Date**: 2026-08-10
**Status**: accepted

### Context

Peer review of the design identified the ranking statistic as the load-bearing risk that no prior decision argued. Mean probability over a food's region has two plausible degenerate modes: boundary bleed (a ±2 px band around every mask edge contributes more mass to the physically adjacent class than a genuine confusion contributes to the right answer, so rank 1 tends to be whatever touches the food) and prior domination (after the winner takes its share, the residual simplex is shaped by the model's marginal class prior, so every plate gets the same top-5). Either mode reproduces the `perClassMeanProb` failure `ui/meal-review` Decision 13 diagnosed — a plausible number answering the wrong question — and either would send Req 8 to a neutral verdict for reasons unrelated to whether retained evidence can help. Separately, the frame-wide coverage gate (`minimumFoodCoverageFraction`) does not bound per-food sample counts: a 200-pixel second class yields ~12 stride samples, and a top-5 selected from ~34 noisy means is selection bias presented as evidence.

### Decision

Implementation is gated on an offline probe: run the compute over admissible real tensors and report top-5 set constancy across plates, the adjacency share of rank-1 candidates, and both figures under a second-argmax-share statistic (fraction of sampled pixels where the channel is the top non-winner) beside the mean. The statistic ships only after this evidence picks it, recorded as a further decision; a probe showing neither statistic carries plate-specific signal is a valid early exit for the spec. Independently, a detected class with fewer than 64 sampled pixels receives no evidence entry — honest absence, extending Req 2.3's zero-pixel case.

### Rationale

The probe costs one offline script and answers the only question that matters before code is written into the capture path, the record schema, and the migrator: does the model's discarded mass vary by plate, or is it a popularity list. Choosing the statistic from data rather than argument is the same discipline Decision 5 applies to the feature as a whole, one level down. The floor converts "too small to measure" from a confident wrong answer into a recorded absence, which consumers already must handle (Req 2.3), and 64 samples (~1,024 px at stride 4) is the point below which a max over 30-odd near-identical means is noise by construction.

### Alternatives Considered

- **Ship the mean and let the Req 8 corpus decide**: no probe needed - Rejected: a corpus verdict costs months of captures and, if the statistic is degenerate, returns neutral without saying why; the probe answers the same question offline this week.
- **Adopt second-argmax share now on the boundary-bleed argument alone**: plausible fix, no data - Rejected: it trades one unmeasured statistic for another; the probe measures both for the same price.
- **Persist per-class sample counts instead of a floor**: lets analysis stratify later - Rejected: it spends record budget to defer a judgement the pipeline can make now, and a shortlist consumer cannot be expected to re-derive "was this evidence meaningful" per read.

### Consequences

**Positive:**
- The degenerate-statistic failure mode is detected for the price of a script, before any schema or capture-path cost is paid.
- Small foods can no longer manufacture confident evidence; their absence is observable and honest.

**Negative:**
- The design phase does not fully fix the algorithm; one decision (the statistic) is deliberately deferred to probe evidence, and tasks must sequence the probe first.
- The 64-sample floor is a judgement constant of exactly the kind the support-plane-reference sweeps exist to interrogate; it ships marked as such.

---

## Decision 12: The Req 8 comparison is intention-to-treat with a stated temporal confound and its mitigations

**Date**: 2026-08-10
**Status**: accepted

### Context

`shortlist_source` partitions the corpus by code path, and the two arms are separated in time: every recency-only row predates the feature, every combined row postdates it, and the recency prior strengthens monotonically as the corpus grows. A naive arm comparison is therefore biased in the flattering direction — the exact class of measurement error Decision 4 refuses elsewhere. Two further facts shape what analysis is possible: the as-offered shortlist is not reconstructible offline (`updated_at` on correction rows is rewritten by later mutations, destroying the ordering recency used at offer time), and the produced-marker is meal-level while evidence is per-class, so the combined arm contains rows whose shortlist was byte-identical to the control arm's.

### Decision

The primary Req 8.3 comparison is intention-to-treat by code path, as the requirements state. The design records the temporal confound and mandates two mitigations in the measurement: stratification by reconstructed recency depth (the count of distinct earlier predicted-to-corrected pairs at each record's timestamp, which survives `updated_at` mutation even though order does not), and an as-treated secondary analysis using the meal record's persisted evidence map to identify combined-arm rows whose evidence was empty for the predicted class.

### Rationale

Intention-to-treat keeps the partition a property of the build, not of plate content or history depth — the same reasoning as Decision 7's marker-tying, extended honestly to its cost. Depth stratification addresses the confound with a quantity the corpus can actually reconstruct; pretending the full counterfactual re-ranking is available would found the analysis on data the store provably destroys. The as-treated secondary is possible only because Decision 4 put the evidence on the meal record — the attenuation the meal-level marker introduces is boundable, not merely acknowledged.

### Alternatives Considered

- **Persist the as-offered shortlist on the correction record**: exact reconstruction - Rejected: Req 4.2 forbids changing the correction-record schema shared verbatim with the clinical track; the offered list is derivable at write time only at that cost.
- **Freeze `updated_at` semantics so recency is replayable**: fixes reconstruction at the source - Rejected: a persistence-layer behaviour change owned by `ui/meal-review`'s store, with consumers beyond this spec; out of scope here, though worth its own consideration if the depth stratification proves too coarse.

### Consequences

**Positive:**
- The confound is in the spec where the analyst will find it, with the two analyses that survive the store's actual semantics.
- No schema changes beyond the two meal-record fields already decided.

**Negative:**
- Req 8.4's first-correction cell, already the smallest, shrinks further under depth stratification; the verdict may need meaningfully more corpus than the aggregate number would.
- The as-offered list remains unrecoverable; any future analysis wanting it must change store semantics first.

---

## Decision 13: Candidate magnitude is mean probability over eligible channels; the probe found bleed but also a usable hit rate

**Date**: 2026-08-11
**Status**: accepted, closes the Decision 11 gate

### Context

Decision 11 deferred the ranking statistic to evidence and gated all implementation on an offline probe (`tools/candidate_probe.py`). The probe has run. Two corpora were used, and the difference between them matters more than any single figure.

The five device capture bundles turned out to be **single-food plates** — four bread, one rice. Rank-1 adjacency is unmeasurable on them (a candidate cannot touch another food class when none is present) and constancy across foods rests on n=2, so the device leg cannot answer either question Decision 11 asked. It did establish one thing: the second-argmax statistic **as literally specified** in the design — "the fraction of the food's sampled pixels where the channel is the top non-winner" — returns nothing at all, because the top non-winner is `background` at 99–100% of bread pixels. Every eligible class scores zero and the ranking is empty.

The probe therefore also ran the leg Decision 11 allowed but did not require: the shipped checkpoint `ab812dc3aa9d` over 200 plates of the merged validation split — 676 scored foods, 27 distinct foods, 160 plates carrying more than one food. That split has ground-truth masks, which permits a measurement neither Decision 11 nor Req 8 anticipated being available offline: on regions the segmenter got *wrong*, is the true class in the candidate set?

### Decision

Candidate magnitude is the **mean probability of the channel over the food's sampled pixels**, computed over eligible channels only — the food's own class, background, both sentinels and the opposite phase are removed *before* the statistic is taken, not ranked and then filtered. The second-argmax-share alternative is rejected. Req 1.3's "derived from the same probability distribution the argmax was taken from" is satisfied unchanged; the design's provisional marking is lifted.

### Rationale

On the measurement that matters — the true class being present in a five-slot candidate set for a region the segmenter got wrong — mean beats second-argmax share on both counts:

| statistic | true class in top-5 | true class at rank 1 |
|---|---|---|
| mean | **78.2%** | **46.3%** |
| second-argmax share | 68.6% | 43.7% |

over 229 wrong regions of 613 scored, against ~20.8% for a random 5-of-24 draw. That is the closest offline analogue of Req 8.1 available, and it says the discarded mass carries the right answer nearly four times in five.

Both degenerate modes Decision 11 named were looked for. **Prior domination is absent at the top**: rank 1 matches the corpus-wide prior's rank 1 only 15.7% of the time, across 29 distinct rank-1 classes with a mean pairwise Jaccard of 0.205 between top-5 sets. The whole-vector Spearman against the pooled prior is high (+0.747), but that statistic is dominated by the ordering of the near-zero tail, where agreement is cheap and irrelevant to a five-slot shortlist.

**Boundary bleed is present and was not explained away.** Rank 1 physically touches the food 69.7% of the time (mean) against a 9.1% chance baseline. Eroding each region before accumulating — the direct test — does not remove it: at 16 px of interior-only sampling the share falls only to 57.7% while discarding 27% of scored foods. The adjacency is intrinsic, not an edge-band artefact.

What reframes it is the hit rate above. The two facts are consistent because **the adjacent class is frequently the correct one**: when the segmenter mislabels a region it has usually smeared a neighbouring food's label across it, so "what touches this food" and "what this food actually is" are the same answer in the cases that matter. The probe cannot fully separate bleed from genuine confusion — that separation needs corrections, which is Req 8's job — but a statistic that surfaces the true class 78.2% of the time is not the `perClassMeanProb` failure this gate existed to catch.

The eligible-channel restriction is not a tuning choice. Without it the second-argmax statistic does not exist, and the comparison Decision 11 mandated could not have been made at all.

### Alternatives Considered

- **Second-argmax share (the design's stated alternative)**: fraction of sampled pixels where the channel is the strongest eligible alternative - Rejected on the evidence: 10 points worse on top-5 hit rate (68.6% vs 78.2%), and it produces very short sets — on the device bundles it returned one or two candidates where five slots were available, because a single class wins the alternative vote at almost every pixel. A shortlist input that cannot fill its slots forfeits Req 1.5.
- **Interior-only sampling (erode the region before accumulating)**: the direct remedy for boundary bleed - Rejected: measured and it does not work. Adjacency falls 69.7% → 57.7% at 16 px, nowhere near the 9.1% chance floor, at a cost of 27% of scored foods and a new judgement constant. Paying samples for a partial fix to something the hit rate suggests is largely signal is a bad trade.
- **Early exit — abandon the spec**: the outcome Decision 11 explicitly permits - Rejected: the exit condition was "neither statistic carries plate-specific signal", and both do. 29 distinct rank-1 classes and 15.7% agreement with the prior is plate-specific by any reading.
- **Defer the choice to the live corpus under Req 8**: ship both and compare - Rejected for the reason Decision 11 gave: a corpus verdict costs months and returns a single neutral number without saying which statistic was at fault.

### Consequences

**Positive:**
- The gate is closed on measurement rather than argument, and tasks 3 onward are unblocked.
- The statistic ships with a documented offline hit rate (78.2% top-5), so Req 8's eventual verdict has a prior expectation to be read against rather than being the first evidence anyone sees.
- `tools/candidate_probe.py` is committed and re-runnable: a later model, palette or statistic can be measured the same way in one command.

**Negative:**
- Boundary bleed is real, unmitigated, and shipping. If Req 8 returns neutral, this is the first place to look, and Decision 5's removal obligation (task 19) applies.
- The deciding evidence comes from the validation leg, not the device: dataset plates under a softmax over logits and **without** the speckle regularisation the device path applies, because `regulariseLabelMap` is Swift and reimplementing it in the probe would risk divergence from what ships. The 64-sample floor absorbs most of what that filter would remove, but the two paths are not identical and the figures should not be quoted as device figures.
- The hit rate measures the **segmenter's** errors on dataset plates, not a user's corrections on their own meals. It is an upper-bound-shaped indicator, not a substitute for Req 8.
- The device corpus remains unable to test either Decision 11 question; closing that gap needs multi-food captures, which no session can manufacture.

### Impact

`design.md`'s behavioural-contract row loses its provisional marking and its Testing Strategy gate is marked discharged. `tools/candidate_probe.py` joins the repository as the probe of record. Tasks 1 and 2 close; task 3 (`CandidateEvidence.compute`) is unblocked and must implement the eligible-channels-first ordering this decision fixes, not a rank-then-filter equivalent — they differ whenever a sentinel would have occupied a slot.

---

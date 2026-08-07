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

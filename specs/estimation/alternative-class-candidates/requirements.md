# Requirements: Alternative Class Candidates

**Status:** requirements — awaiting approval gate before design
**Owed by:** `ui/meal-review` [Decision 18](../../ui/meal-review/decision_log.md), which deferred this work and shipped recency ordering in its place.

## Introduction

The segmenter computes a probability over every palette channel for every pixel, takes the argmax, and discards the rest. So on every capture the model states what else each region might have been, and the app throws that away.

`SegmentationResult.perClassMeanProb` is not the missing quantity. `PostProcessing.swift:172-178` accumulates it only where a class **won** the argmax, so the map holds an entry only for classes already detected on the plate — each of which already has its own row in the estimate — and the value is the winner's own mean confidence, not a posterior for any alternative. The food a user actually ate, when the segmenter got it wrong, has no entry at all.

This spec retains the discarded evidence: for each detected food, the ranked alternative classes the model's own output supports over that food's pixels, persisted on the meal record. Its consumer is the relabel shortlist in `ui/meal-review` Req 3.1.

**Recency is not the thing being replaced.** For a single-user app whose owner eats the same foods repeatedly, "what this person has chosen before for a food that looked like this" is a strong prior, and on a 25-class universe it is a hard baseline to beat. The gap it cannot close is a first correction — a food the user has never chosen has no recency at all, and that is exactly the case where the segmenter was wrong about something new. Candidate evidence is retained to fill that gap and to break ties within it, not to supplant a prior that works. The ordering that consumes both is judged against recency alone ([8](#8)).

## Definitions

- **Detected food** — one entry in the estimate, keyed by class id; all pixels the persisted mask assigns to that class. As defined by `ui/meal-review`.
- **Candidate** — a food class other than the detected food's own, together with a magnitude expressing how strongly the segmenter's output supports it over that food's pixels.
- **Candidate evidence** — the ranked candidate set retained for one detected food.
- **Recency prior** — the ordering shipped by `ui/meal-review` Req 3.1: foods the user has recently chosen for a food of that kind, most recent first.
- **Combined ordering** — the shortlist ordering that consumes both the recency prior and candidate evidence, introduced by this spec.
- **Hardware floor** — iPhone 16 Pro, per `CLAUDE.md` and `segmenter-foundation` Decision 22.

## Non-Goals

- Changing the argmax, the refusal predicate, σ_seg, `perClassMeanProb`, or any stored volume, mass or carbohydrate figure. This spec adds a retained quantity; it corrects none.
- A new model, retraining, a second inference pass, or any change to the segmenter weights.
- Per-instance or per-blob identity. Candidate evidence is per class, exactly as the estimate is.
- Retaining the full probability tensor on the meal record — that is the capture bundle's job, and the bundle is ~200 MB.
- Suggesting foods outside the palette. The palette bounds the candidate universe; a food the app has never heard of stays the `absent` path (`ui/meal-review` Req 5).
- Any user-facing surface. The consuming surface is specified by `ui/meal-review`; this spec supplies its ordering input and nothing else.
- Replacing the recency prior. It is retained as a component of the combined ordering ([7.1](#7.1)) and as the baseline the spec is judged against ([8.3](#8.3)).
- Learning a weighting between the two signals from the corpus. The combination is fixed and stated; adapting it is a later question, and one that cannot be asked before [8](#8) says whether the second signal helps at all.
- Network access of any kind.

## Requirements

### 1. <a name="1"></a>Candidate Evidence For A Detected Food

**User Story:** As someone whose bread was called rice, I want the app to already know that bread was its second guess, so that correcting it is a single tap rather than a hunt through a list.

**Acceptance Criteria:**

1. <a name="1.1"></a>For each detected food in an estimate, THE SYSTEM SHALL retain a ranked set of alternative food classes supported by the segmenter's own output over that food's pixels.
2. <a name="1.2"></a>The candidate set SHALL be capable of containing a class that won no pixel anywhere on the plate.
3. <a name="1.3"></a>Each candidate SHALL carry a magnitude sufficient to order the set, derived from the same probability distribution the argmax was taken from.
4. <a name="1.4"></a>The candidate set SHALL exclude the detected food's own class, the background class, and any channel the palette does not treat as a food.
5. <a name="1.5"></a>The system SHALL retain at most five candidates per detected food, and WHERE fewer classes carry any support, SHALL retain only those.
6. <a name="1.6"></a>A candidate set SHALL NOT mix solid and liquid classes: WHERE the detected food is a liquid class the candidates SHALL be liquid classes, and WHERE it is solid they SHALL be solid.
7. <a name="1.7"></a>Candidates SHALL be identified by a name that resolves without the palette in force at the time of reading.

### 2. <a name="2"></a>Agreement With The Estimate As Shown

**User Story:** As the developer, I want the alternatives offered for a marked region to describe the region as it is marked, so that the shortlist is not answering a question about a different set of pixels.

**Acceptance Criteria:**

1. <a name="2.1"></a>Candidate evidence for a detected food SHALL be computed over the pixels the **persisted** mask assigns to that food, not over a pre-regularisation label assignment.
2. <a name="2.2"></a>Retaining candidate evidence SHALL NOT alter the argmax label map, the refusal predicate, σ_seg, `perClassMeanProb`, or any volume, mass or carbohydrate figure produced for the same capture.
3. <a name="2.3"></a>WHERE the persisted mask assigns no pixels to a class carried in the estimate, THE SYSTEM SHALL retain no candidate evidence for it rather than an arbitrary set.

### 3. <a name="3"></a>Cost On The Capture Path

**User Story:** As someone photographing a plate with a fork in my other hand, I do not want the app to get slower so that a list can be sorted better.

**Acceptance Criteria:**

1. <a name="3.1"></a>Retaining candidate evidence SHALL NOT increase the end-to-end duration of a capture on the hardware floor by more than 50 ms at the median.
2. <a name="3.2"></a>The system SHALL NOT perform an additional model inference, an additional image decode, or a read of the capture bundle in order to produce candidate evidence.
3. <a name="3.3"></a>WHEN candidate evidence cannot be produced within budget for a capture, THE SYSTEM SHALL complete the estimate without it rather than delay or fail the capture.
4. <a name="3.4"></a>Estimation SHALL NOT fail, refuse, or degrade any existing figure because candidate evidence could not be produced.

### 4. <a name="4"></a>Persistence And Portability

**User Story:** As the developer improving the shortlist, I want the evidence stored with the meal it describes, so that a correction made a week later still knows what the model thought.

**Acceptance Criteria:**

1. <a name="4.1"></a>Candidate evidence SHALL be persisted on the meal record, keyed by detected class, and SHALL survive an app restart.
2. <a name="4.2"></a>It SHALL be carried in the portable meal-record contract (`MedataCore/Sources/PortableContracts`), additive such that an existing reader of that contract remains valid, and SHALL NOT require a change to the correction-record schema that `estimation/pipeline` Req 14.4 shares verbatim with the clinical track.
3. <a name="4.3"></a>A meal record written before this spec SHALL remain readable, and the **absence** of candidate evidence on a record SHALL be distinguishable from a computed but **empty** candidate set.
4. <a name="4.4"></a>Candidate evidence SHALL contain no imagery, and SHALL add no more than 1 KB to a meal record.

### 5. <a name="5"></a>Palette Migration

**User Story:** As the developer promoting a new palette, I want a migrated meal to carry no evidence keyed under the palette it left, so that a shortlist never offers a class the record no longer uses.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN a stored meal is migrated between palette versions, THE SYSTEM SHALL migrate or discard its candidate evidence, and SHALL NOT leave candidates keyed under one palette beside figures keyed under another.
2. <a name="5.2"></a>WHERE candidate evidence is discarded during migration, THE SYSTEM SHALL alter no other value on the record, and the result SHALL be indistinguishable from a record that never carried it ([4.3](#4.3)).

### 6. <a name="6"></a>Replay And Harness Parity

**User Story:** As the developer evaluating the shortlist offline, I want a replayed capture to produce the evidence the device produced, so that corpus rows from the harness and from the phone are comparable.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN a capture bundle is replayed through the harness, THE SYSTEM SHALL produce the same candidate evidence the device produced for that capture, given the same palette and the same stored probability tensor.
2. <a name="6.2"></a>A replayed capture SHALL NOT yield an empty candidate set WHERE the device yielded a populated one.

### 7. <a name="7"></a>Seam With The Review Surface

**User Story:** As the developer, I want this evidence to change only the order of the shortlist and never to cost me the prior that already works, so that landing it cannot make a correction path worse than it was.

**Acceptance Criteria:**

1. <a name="7.1"></a>The relabel shortlist specified by `ui/meal-review` Req 3.1 SHALL be ordered by a combination of the recency prior and candidate evidence, in which the recency prior is retained as a component and is not superseded.
2. <a name="7.2"></a>WHERE a food carries recency for the detected class, its position SHALL NOT be lowered by the absence of candidate evidence for it.
3. <a name="7.3"></a>Candidate evidence SHALL be capable of placing a food the user has never chosen into the shortlist, which the recency prior alone cannot do.
4. <a name="7.4"></a>WHERE a record carries no candidate evidence ([4.3](#4.3)), the shortlist SHALL be ordered by the recency prior alone, and SHALL be identical to the shortlist `ui/meal-review` would have produced.
5. <a name="7.5"></a>The combination SHALL be stated in the design and SHALL be deterministic — the same recency history and the same candidate evidence SHALL always produce the same order.
6. <a name="7.6"></a>Each correction record SHALL name the ordering that produced its shortlist per `ui/meal-review` Req 3.3; the combined ordering SHALL be named distinctly from the recency prior, and a change to how the two are combined SHALL be distinguishable in the corpus from the ordering that preceded it.
7. <a name="7.7"></a>No score, percentage, or confidence tier derived from candidate evidence or from the combination SHALL be displayed, per `ui/meal-review` Req 3.2.
8. <a name="7.8"></a>The presence or absence of candidate evidence SHALL NOT change which foods are reachable for relabel; the full eligible list of `ui/meal-review` Req 3.4 remains the same set.
9. <a name="7.9"></a>The combined ordering SHALL remain subject to `ui/meal-review` Req 3.8 and 3.9 — only foods the bundled database gives both a density and a carbohydrate coefficient are offered, and no relabel crosses the solid/liquid boundary.

### 8. <a name="8"></a>Measurability

**User Story:** As the developer, I want to be able to tell whether this was worth building, so that the shortlist is judged on the corpus rather than on impression.

**Acceptance Criteria:**

1. <a name="8.1"></a>The system SHALL make it possible to measure, from the corrections corpus, how often the food a user chose was present in the shortlist they were offered.
2. <a name="8.2"></a>That measurement SHALL be partitionable by ordering source, so that records made under the recency prior alone do not contaminate records made under the combined ordering.
3. <a name="8.3"></a>The measurement SHALL support comparing the combined ordering against the recency prior alone as its baseline, rather than against no ordering.
4. <a name="8.4"></a>The measurement SHALL be reportable separately for a detected food whose corrected class the user had chosen before and one whose corrected class they had not, so that the case the recency prior cannot serve is not averaged away by the case it serves well.

## Acceptance Bar

This spec is worth its cost only if [8.1](#8.1) improves **against the recency prior alone** ([8.3](#8.3)), on the hardware floor, within the [3.1](#3.1) budget. Recency is a strong baseline, not a straw one: it is the ordering already shipped, and beating it on aggregate is a real result rather than a formality.

The first-correction split ([8.4](#8.4)) is the measurement that matters most. Aggregate hit rate is dominated by repeat foods, where recency already wins and candidate evidence can add little; if the combined ordering is going to earn its cost it will show up on foods the user has never chosen before, and an aggregate number can hide that in either direction.

A neutral or negative result is a valid outcome and is recorded as such rather than tuned around. The recency prior is retained as a live component throughout ([7.1](#7.1)), not as a fallback that has to be reinstated, so reverting costs the retained field and the pass — no correction path regresses.

## Dependencies

- `ui/meal-review` — supplies the consuming surface and the corrections corpus that [8.1](#8.1) is measured from. That spec ships first, with recency ordering and `shortlist_source` on every record; this spec is what makes `shortlist_source` carry more than one value.
- `estimation/pipeline` Req 14.4 — the correction-record schema is shared verbatim with the clinical track. [4.2](#4.2) puts candidate evidence on the meal record precisely so that schema does not have to move; only `shortlist_source`, which `ui/meal-review` Req 3.3 already defines, changes value.
- `estimation/support-plane-reference` — in flight over the volume path. This spec touches the segmentation post-processing path, not the volume path, but both land in `MedataCore`; sequencing is a scheduling question for the design phase.

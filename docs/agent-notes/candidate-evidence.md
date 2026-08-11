# Candidate evidence — the ranking statistic and its known defect

Module note for `estimation/alternative-class-candidates`: the retained per-food
alternative-class evidence that orders the relabel shortlist. **Read this before
touching `CandidateEvidence.compute` or the Req 8 analysis.** The spec is
authoritative (`specs/estimation/alternative-class-candidates/`); this note
carries the mechanics and the gotchas that are easy to get wrong from the
documents alone.

## The statistic, and why it is what it is

Candidate magnitude is the **mean probability of a channel over the food's
sampled pixels**, fixed by Decision 13 from the Decision 11 probe. Two things
about it are load-bearing and non-obvious:

**Eligibility is applied to the channel set BEFORE the statistic, not after
ranking.** Rank-then-filter looks equivalent and is not: it differs whenever a
sentinel would otherwise have occupied a slot. This matters more than it sounds
— `background` is the top non-winner at ~100% of food pixels, so any statistic
computed over all channels and filtered afterwards is dominated by a class that
can never be a candidate.

**The design's original second-argmax wording is unusable as written.** "The
fraction of the food's sampled pixels where the channel is the top non-winner"
returns an empty set for every food, for the reason above. Decision 13 records
this; do not reintroduce the literal form.

## Where it lives, and the two ordering constraints

`MedataCore/Sources/Segmentation/CandidateEvidence.swift` — one pure enum,
`compute(probabilities:labelMap:palette:)`. Called from
`SegmenterPostProcessor.process` and surfaced on `SegmentationResult.candidateEvidence`
(optional, defaulting to `nil`, so every existing constructor and hand-built test
result still compiles). `nil` means the pass did not run; non-nil however empty
means it ran and nothing qualified — that is the distinction the persisted marker
carries.

Two orderings in `PostProcessing.swift` are load-bearing and look arbitrary:

- The `ProbabilityTensor` is built **before** the pass, not at its original
  position further down. The pass must read the FP16 bytes a replayed bundle
  carries, not the intermediate `resized` FP32 buffer — the low bits differ and
  could flip a borderline ranking, breaking harness replay parity.
- The pass runs **after** `regulariseLabelMap`, on the regularised map, because
  those are the pixels the persisted mask assigns.

Inside `compute`, the tensor is read through a strided per-pixel accessor.
`FP16Bytes.decode` is the whole-tensor path (~398 MB of FP32 for a full frame)
and must not be used here.

From there `Pipeline.swift`'s meal-record assembly copies the map onto
`PbMealRecord` fields 16/17 through `PipelineBridges.pbCandidateEvidence`, which
splits each ranked set into the parallel arrays the record persists. The persisted
shape, the marker's meaning and the copy-site hazards are in
`docs/agent-notes/persistence.md`.

`process` takes `retainCandidateEvidence: Bool = true`. It exists for the Req 2.2
non-interference test in `PostProcessingTests` (`with` vs `without` on the same
input, exact equality on the argmax bytes, σ_seg, `perClassMeanProb`, the tensor
bytes and the refusal outcome) — not as a product switch. Nothing else should
pass `false`.

## The consuming ordering

`MedataCore/Sources/Foods/ShortlistOrdering.swift` — `combined(recency:candidates:topUp:limit:)`,
three layers in order: recency, evidence fills, the shipped eligible top-up.
Evidence displaces only the blind top-up, never a recency entry, and with an
empty `candidates` the result is the list `ui/meal-review` shipped. All three
inputs are already-eligible class ids; eligibility and the solid/liquid boundary
stay with the caller (`MealReviewModel.eligibleFoods`), exactly as before.

Two things about the call site in `App/MealReviewModel.swift` are worth knowing:

- **The marker gates the evidence, not the function.** `buildShortlist` always
  calls `combined`; `candidateFills` returns `[]` unless
  `record.candidateEvidenceProduced` is true. The design describes this as
  "marker false takes the shipped path", which is the observable contract —
  a single code path with a proven-empty fills layer delivers it without a
  second copy of the ordering to keep in step. The degeneracy is pinned by
  `ShortlistOrderingTests`, which reimplements the shipped loop as its reference
  rather than asserting against a hand-written expectation.
- **`shortlistSource` follows the marker, not the fills.** A combined-arm record
  whose evidence set was empty for its predicted class still reads
  `recency_plus_candidates`. That is deliberate: it keeps the Req 8.2 partition
  a property of the code path rather than of what was on the plate, and the
  as-treated cut (Decision 12) is recoverable offline because the meal record
  persists the evidence map.

## Replay parity, and what it actually claims

`MedataCore/Tests/HarnessCLITests/CandidateEvidenceReplayParityTests.swift` is
the **only** harness caller of `compute`. There is no candidate-evidence code in
`HarnessCore` or `HarnessCLI`: the harness runs no `PostProcessing`, writes no
meal record and sets no marker, so parity is structural — device and replay
reach one function with the same bytes. Req 6.1's coverage is that shared
function plus this test's golden, and nothing more is claimed.

The golden is a literal in the same file as the synthetic fixture that produces
it, not a separate committed artifact. Each figure is `round(FP16(v) × 1000)`
over a region whose pixels all carry the same declared vector, so the expected
values are arithmetic rather than a recording of what the code last did.

One channel in the fixture is load-bearing: `pasta` is declared **0.2005**, which
quantises to **200** per mille read as FP16 and **201** read as FP32. A ranking
taken off the post-processor's intermediate FP32 buffer instead of the bytes a
replayed bundle carries fails on that one slot and nothing else — which is the
whole point of it being there. Do not "tidy" it to a round number.

**Admissible fixtures are capture-bundle-derived and synthetic only.** A bundle
records the cleaned prediction, so its argmax IS the persisted mask; a fixture
with `source_dataset` set is Nutrition5k-derived and carries the ground-truth
mask in that same field, so evidence computed over truth regions would be a
plausible-looking wrong number. The test's `admissible` predicate makes the same
refusal `tools/candidate_probe.py` does.

## The known defect: boundary bleed

Rank-1 candidates physically touch the food **69.7%** of the time against a
**9.1%** chance baseline. The shortlist is substantially ordered by what is
adjacent on the plate. This ships unmitigated, deliberately.

Interior-only sampling is **already measured and rejected** as the remedy —
eroding each region before accumulating reaches only 57.7% at 16 px while
discarding 27% of scored foods. The adjacency is intrinsic, not an edge-band
artefact. Do not re-propose erosion without new evidence.

It ships because the same probe found the true class in the top five on **78.2%**
of the segmenter's wrong regions (46.3% at rank 1), against ~20.8% for a random
5-of-24 draw. Those two facts are consistent: **the adjacent class is frequently
the correct one**, because a mislabelled region has usually had a neighbour's
label smeared across it. Bleed and signal are the same measurement until real
corrections separate them.

That separation is the required boundary-bleed partition of the Req 8 analysis
(the "Build the shortlist hit-rate analysis over the corrections corpus" task):
split the combined-arm hit rate by whether the corrected class was adjacent to
the predicted region. Adjacent hits with non-adjacent misses means bleed is
crowding genuine confusions out of the five slots, and the conditional mitigation
task fires. Adjacency is recomputable offline from a surviving capture bundle's
persisted argmax; rows whose bundle is gone are reported unknown, never assumed
non-adjacent.

## The Req 8 analysis: `tools/shortlist_hit_rate.py`

The corpus-side measurement — how often the food the user chose was already in
the shortlist, per `shortlist_source` arm. It adds no fields; the corrections
corpus already carries everything the four criteria need.

```
python3 tools/shortlist_hit_rate.py tmp/device_pulls/*.sqlite --bundles tmp/device_captures
python3 tools/shortlist_hit_rate.py corrections.jsonl
```

Reads device pulls / archive exports (`correction_records` for the corpus, the
`events` meal rows for the as-treated cut) or the app's Corrections JSONL export
(no meal records, so as-treated is all `unknown`). Several pulls of the same
device can be passed at once: rows deduplicate on the store's own primary key,
`(meal_id, predicted_class)`, newest `updated_at` winning.

Four things about it are load-bearing:

- **Hit is `shortlist_rank > 0` over relabel rows only** (`class_corrected`).
  Rank 0 means the full list or no relabel, and proto3 omits defaults, so an
  absent rank reads 0 exactly as the app's decoder reads it.
- **First-vs-repeat and recency depth are reconstructed from `created_at`, not
  `updated_at`.** A later edit rewrites `updated_at`, so it cannot order the
  corpus as it stood when a shortlist was offered. Rows sharing a timestamp (the
  several foods of one plate) are not earlier than each other. Depth is the
  count of distinct corrected classes already recorded for the predicted class —
  the *size* of the pool recency drew from, which is reconstructible even though
  its order is not.
- **The bundle join is timestamp-then-verify.** A bundle is stamped when
  estimation starts and the meal record when it finishes, so the candidate is
  the nearest bundle strictly before the record within `--bundle-window-ms`
  (60 s). Timestamp alone would be a guess, so the candidate must also explain
  the meal: every class the estimate carries must be present in the bundle's
  argmax — not the converse, since speckle the estimate drops below its area
  threshold is still in the mask. A meal no bundle explains reports `unknown`,
  never non-adjacent.
- **`bleed_verdict` is a token, not a rate**: `bleed_hurting` (adjacent
  corrections hit while non-adjacent miss — the mitigation task fires),
  `bleed_not_hurting`, or `insufficient` until both cells clear `--min-cell`
  (default 10).

**Corpus as of 2026-08-12: the analysis runs and answers nothing.** The device
pulls carry 8 correction rows across 6 meals, all `shortlist_source=recency`,
and **zero** of them are relabels — every cell is `n=0 rate=na`. The output
shape is fixed and the arithmetic is exercised, but the verdict task waits on
real corrections in both arms. `bundles_matched=3` of those meals, so the
adjacency join is live rather than theoretical; adjacency itself is unexercised
on real rows because the field plates are single-food (see below).

## The probe: `tools/candidate_probe.py`

Re-runnable against a later model, palette or statistic. Two modes:

```
python3 tools/candidate_probe.py tmp/device_captures/*.fixture --json out.json
tools/segmenter/.venv/bin/python tools/candidate_probe.py --validation --limit 200
```

Reads capture bundles through a hand-rolled minimal protobuf reader (the
`tools/fixture_slice.py` pattern — no protobuf dependency). `--erode N` strips N
sampled-grid layers off each region first, which is the boundary-bleed test.
Output is compact `key=value` lines; per-food detail goes to `--json`.

### Corpus gotchas

- **The device bundles cannot answer the probe's questions.** All five field
  captures are single-food plates (four bread, one rice). A rank-1 candidate
  cannot touch another food class when none is present, so adjacency is
  unmeasurable there and constancy across foods rests on n=2. Any future field
  session wanting to inform this spec needs **multi-food plates**.
- **The deciding figures are validation-leg figures, not device figures.** The
  `--validation` leg omits the Swift speckle regularisation (`regulariseLabelMap`
  is Swift; reimplementing it in Python would risk divergence from what ships)
  and reads a softmax over logits rather than an FP16 round trip. The 64-sample
  floor absorbs most of what the filter would remove, but do not quote these as
  device numbers.
- **Palette stamps on bundles lie.** One field bundle stamps `"v1"` and another
  `"v2"`, both carrying 36-channel tensors — i.e. the current palette. The probe
  verifies the channel count and ignores the label; a genuine 24-solid palette
  would give 35 channels. Refusing on the stamp would discard real captures over
  a string. Same provenance-stamp defect class the palette expunge cleaned up
  (pipeline Decision 50).
- **N5k fixtures are inadmissible.** Their `nadir_argmax` carries the
  ground-truth mask, not a persisted prediction. The probe refuses any bundle
  with `source_dataset` set.
- Capture bundles have no ground truth, so the hit-rate figures appear only on
  the `--validation` leg.

## Baseline figures (2026-08-11, checkpoint `ab812dc3aa9d`)

200 validation plates, 676 scored foods, 27 distinct foods, 160 multi-food:

| | mean | second-argmax share |
|---|---|---|
| true class in top-5 (wrong regions) | 78.2% | 68.6% |
| true class at rank 1 | 46.3% | 43.7% |
| rank-1 adjacency (chance 9.1%) | 69.7% | 59.8% |
| mean pairwise Jaccard of top-5 | 0.205 | 0.130 |
| distinct rank-1 classes | 29 | 29 |

Prior domination is absent at the top: rank 1 matches the corpus-wide prior only
15.7% of the time. The whole-vector Spearman against the pooled prior is high
(+0.747) but is dominated by the near-zero tail, where agreement is cheap and
irrelevant to a five-slot shortlist — do not quote it as evidence of the prior
driving the ranking.

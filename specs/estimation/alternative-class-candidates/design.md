# Design: Alternative Class Candidates

**Status:** approved 2026-08-10 (design gate passed after design-critic + peer review); the Decision 11 probe ran 2026-08-11 and fixed the ranking statistic (Decision 13) — implementation unblocked from task 3
**Requirements:** [requirements.md](requirements.md) · Decisions 1–13 in [decision_log.md](decision_log.md) bind this design.

## Overview

A strided post-regularisation pass over the probability tensor retains, per detected food, the top-five other classes the model supported over that food's persisted pixels. The evidence rides two additive fields on `PbMealRecord`, survives replay by construction, and is consumed by one pure function that inserts never-chosen foods into the recency shortlist ahead of its blind top-up.

## Architecture

### The evidence pass

One new pure function in the Segmentation module:

```swift
// MedataCore/Sources/Segmentation/CandidateEvidence.swift
public enum CandidateEvidence {
    public struct Candidate: Equatable, Sendable {
        public let className: String     // Req 1.7: palette-independent key
        public let meanPermille: UInt32  // quantised magnitude, 0…1000 (Decision 10)
    }
    /// Deterministic; same output for same (probs, labelMap, palette) on
    /// device and in harness replay (Req 6.1 — parity by construction,
    /// Decision 9). Decodes the FP16 `ProbabilityTensor` internally on BOTH
    /// call sites — never the pipeline's intermediate FP32 buffer, whose
    /// low bits differ from the FP16 bytes a replayed bundle carries and
    /// could flip a borderline ranking. Reads the label map on a fixed
    /// stride-4 grid in both axes, anchored at (0,0) (Decision 8): ~6.2 M
    /// of the ~99.5 M full-resolution reads, so the Req 3.1 budget is met
    /// by construction and Req 3.3's escape reduces to "tensor unavailable".
    /// Serial raster accumulation — Float sum order is fixed, so parity
    /// needs no deterministic-reduction machinery.
    public static func compute(
        probabilities: ProbabilityTensor,
        labelMap: ArgmaxMap,          // the REGULARISED map (Req 2.1, Decision 3)
        palette: ClassPalette
    ) -> [String: [Candidate]]
}
```

Behavioural contract (each line traces to a requirement):

| Rule | Req |
|---|---|
| Accumulate per-channel probability sums per detected class over sampled pixels of the regularised map | 1.1, 2.1 |
| Candidate magnitude = mean probability of that channel over the food's sampled pixels, quantised to permille; a class needs no argmax win anywhere. **Fixed by the Decision 11 probe (Decision 13)**: mean beat second-argmax share on offline hit rate (true class in the top five on 78.2% of the segmenter's wrong regions, against 68.6%). Eligibility is applied to the channel set **before** the statistic is taken, not after ranking — the two differ whenever a sentinel would otherwise occupy a slot, and the literal second-argmax definition returns nothing at all because `background` is the top non-winner at ~100% of food pixels. Boundary bleed is real and unmitigated (rank 1 touches the food 69.7% vs 9.1% by chance; erosion does not remove it) — see Decision 13 for why it ships anyway | 1.2, 1.3 |
| Exclude: the food's own channel, background, `unknown_food`, `unsupported_liquid`, and cross-phase channels (`isFoodClass`/`isLiquidClass` decide phase) | 1.4, 1.6 |
| Rank descending by mean (pre-quantisation); ties broken by channel declaration order (determinism) | 1.3, 7.5 |
| Retain top 5 with strictly positive mean; fewer where fewer qualify. (In practice softmax mass never underflows, so full sets are the norm — the empty-computed case arises via the sampling floor and the no-tensor path, not this filter) | 1.5 |
| A detected class with fewer than **64 sampled pixels** gets no entry — a top-5 max over a handful of noisy means is selection bias, not evidence; honest absence extends Req 2.3's zero-pixel case (Decision 11) | 2.3 |
| Retain sets for at most the **5** detected classes with the most sampled pixels (ties: declaration order) — the persisted-encoding budget bound (Req 1.8, 4.4, Decision 10) | 1.8, 4.4 |
| Purely additive: reads tensor/label map, writes nothing else — σ_seg, refusal, `perClassMeanProb`, figures untouched | 2.2 |

**Call sites (Decision 9 — one function, two callers):**

- **Device:** `PostProcessing.swift`, after `regulariseLabelMap` (:201). The `ProbabilityTensor` is currently constructed at :209; the pass needs it constructed first — a trivial reorder, noted so the FP16 contract above is not accidentally satisfied from the FP32 `resized` buffer. Result lands on `PostProcessedOutput` (PostProcessing.swift:14–19) as a new field, surfaced by `CoreMLSegmenter` onto `SegmentationResult.candidateEvidence: [String: [Candidate]]?` — a new optional, default `nil`, so every existing constructor and hand-built test result is unchanged. `nil` = not produced; non-nil (however empty) = produced, feeding the Decision 4 marker.
- **Harness:** the parity test only (`HarnessCLITests`), calling `compute` with a fixture's FP16 tensor and its persisted argmax. **Admissible fixtures: capture-bundle-derived and synthetic only.** Bundle fixtures record the *cleaned prediction* (PostProcessing.swift:214), so their argmax IS the persisted mask; N5k fixtures carry the **ground-truth** mask in the same field (`make_fixtures.py` contract) and computing evidence over truth regions would be a plausible-looking wrong number — they are excluded from Req 6.1 coverage. The harness runs no `PostProcessing`, writes no meal records, and therefore sets no marker; Req 6.1's coverage is the shared function plus this test, and nothing more is claimed.
- **FP16 access:** `FP16Bytes.decode` is whole-tensor (~398 MB of FP32 for a full frame); `compute` reads the tensor through a strided per-pixel FP16 accessor instead, decoding only the ~6.2 M sampled positions.

### Data flow

```
PostProcessing (device)
  └─ CandidateEvidence.compute(FP16 tensor, cleaned map, palette)
       └─ PostProcessedOutput.candidateEvidence
            └─ SegmentationResult.candidateEvidence (via CoreMLSegmenter)
                 └─ Pipeline.swift MealRecord assembly (~:539, where
                    segmenterSource/macros land) → fields 16/17
                      └─ Stage L persistence (protobuf-JSON, Decision 31)
                           ├─ MealRecord.swift pb bridge + withPhotoAssetID
                           │    (member-wise copies — MUST carry both fields)
                           ├─ PaletteMigrator.reDerive: fresh record ⇒ evidence
                           │    dropped, marker false BY CONSTRUCTION (Req 5)
                           └─ MealReviewModel → ShortlistOrdering.combined(...)
                                └─ PbCorrectionRecord.shortlist_source (Req 7.6)

HarnessCLITests parity test: compute(fixture FP16 tensor, fixture argmax) — Req 6.1
```

### The combined ordering (Decision 7, amended — recency, evidence fills, then top-up)

The shipped shortlist is **not** recency alone: `buildShortlist` (App/MealReviewModel.swift:714–727) tops up from the eligible list after recency so the list is useful before history exists. The combined ordering therefore has three layers, stated fully:

1. recency entries, in their exact shipped positions;
2. evidence fills — candidates for the detected class, in evidence rank order, skipping entries already present;
3. the shipped eligible top-up, unchanged, for any slots still empty.

Evidence displaces only the blind top-up, never a recency entry; with no evidence, layers 1+3 are byte-identical to the shipped list (Req 7.4).

```swift
// MedataCore/Sources/Foods/ShortlistOrdering.swift
public enum ShortlistOrdering {
    public static let recencySource = "recency"                  // shipped value
    public static let combinedSource = "recency_plus_candidates" // Req 7.6

    /// All three inputs are already-eligible class ids — eligibility and
    /// phase filtering (Req 7.8/7.9) stay with the caller, exactly as
    /// shipped. Deterministic; duplicates skipped in layer order.
    public static func combined(
        recency: [String],
        candidates: [String],   // evidence-ranked ids for the detected food
        topUp: [String],        // the shipped eligible-list order
        limit: Int = 5
    ) -> [String]
}
```

- `MealReviewModel.buildShortlist` always calls `combined`; the record's marker gates the *evidence*, not the function — marker false passes an empty `candidates` layer, which is `recencySource` and the byte-identical shipped list by Req 7.4. (An earlier reading of this line, "marker false takes a separate shipped path", is superseded: the observable contract is the byte-identical list, and one code path with a proven-empty fills layer delivers it without a second copy of the ordering to keep in step.)
- `shortlist_source` takes `combinedSource` exactly when the marker is true — the ordering that *ran*, not whether fills landed, keeping the Req 8.2 partition a property of the code path rather than of plate content.

### Measurement (Req 8)

No new fields: the corpus already carries what the four criteria need.

| Criterion | Derivation from shipped corpus fields |
|---|---|
| 8.1 hit rate | `shortlist_rank > 0` on relabel correction records (rank 0 = full-list/no-relabel) |
| 8.2 partition | `shortlist_source` per record ("recency" vs "recency_plus_candidates") |
| 8.3 baseline | same metric over the two partitions |
| 8.4 first-vs-repeat | a corrected class X for predicted class P is a *repeat* iff an earlier correction record (by timestamp) corrects P → X — the same relation recency ranks from (`recentCorrectedClassIds(forPredictedClass:)`); reconstructible because every record is timestamped |

**Boundary-bleed partition (Decision 13), a required cut of the combined arm:** the probe measured rank-1 candidates touching the food 69.7% of the time against a 9.1% chance baseline, and erosion does not remove it, so the shortlist is substantially ordered by what is adjacent. Splitting the combined-arm hit rate by whether the corrected class was adjacent to the predicted region is what distinguishes the two readings of that number — adjacency as genuine confusion (a neighbour's label smeared over the region, in which case bleed *is* the signal) from adjacency as noise crowding real confusions out of the five slots. Adjacency is recomputable offline from a surviving capture bundle's persisted argmax; rows whose bundle is gone are reported unknown rather than assumed non-adjacent, with the unknown count printed beside the figure. A harmful verdict fires the boundary-bleed mitigation task, not the removal gate — the ranking is repaired before the feature is removed. Mechanics and full figures: `docs/agent-notes/candidate-evidence.md`.

**Known confound, stated up front (Decision 12):** the two `shortlist_source` arms are separated in time, and recency strengthens monotonically as the corpus grows — a naive comparison flatters the combined arm. Mitigations: (a) stratify by **reconstructed recency depth** — the *count* of distinct earlier P → X corrections at each record's timestamp is reconstructible even though the offered *order* is not (`updated_at` is rewritten by later mutations, so the as-offered list cannot be replayed); (b) an as-treated secondary analysis is possible because the meal record persists the evidence map — combined-arm rows whose evidence set was empty for the predicted class are identifiable offline, bounding the attenuation that the meal-level marker introduces into the per-class question. The primary Req 8.3 comparison remains intention-to-treat by code path.

### Consumer audit (additive-field blast radius)

| Site | Needs change | Why |
|---|---|---|
| `Pipeline.swift` MealRecord assembly (~:539) | yes | copy evidence + marker from the segmentation result onto the record |
| `MealRecord.swift` pb bridge (both directions, :105–158) | yes | member-wise reconstruction MUST carry fields 16/17 or evidence silently drops (Decision 4's "wrong in the direction that looks fine") |
| `MealRecord.swift` `withPhotoAssetID` (:70–80) | yes | same member-wise copy hazard, runs after every capture |
| `MealReviewModel.buildShortlist` / `relabel` | yes | combined ordering + `shortlist_source` value |
| `PaletteMigrator` | no code change | `reDerive` builds a fresh record, so evidence drops and the marker defaults false by construction; Req 5.2 verified by test |
| Corrections JSONL export, records browse | no | serialise the whole record; additive fields pass through |
| Records deletion / retention paths | no | operate on whole records |
| Harness fixture contract (`MealFixture.proto`) | no | evidence is a meal-record quantity; fixtures carry tensor + argmax, from which the parity test recomputes it |
| App/App.swift `CaptureFlowModel` | no | its `segmenterSource` feeds slim capture-stage refusal records, not the meal record — not on this path |

**Forward-compatibility caveat (Req 4.2):** records persist as protobuf-JSON (Decision 31), and SwiftProtobuf's JSON decoding throws on unknown fields by default — so a *downgraded* reader would fail on a record carrying fields 16/17. Downgrade is not a supported path for this single-device developer-phase app; binary-proto readers (none currently) are unaffected. The Req 4.2/4.3 tests pin the JSON path, the one actually in use.

## Data Models

```protobuf
// MealRecord.proto — additive (Req 4.2)
message CandidateSet {
    repeated string class_names = 1;    // ranked, ≤ 5 (Req 1.5)
    repeated uint32 mean_permille = 2;  // parallel to class_names, 0…1000
}
// on MealRecord:
map<string, CandidateSet> candidate_evidence = 16;  // keyed by detected class name
bool candidate_evidence_produced = 17;              // Decision 4: absence ≠ empty
```

Parallel arrays and permille quantisation are budget-driven (Decision 10): the record persists as protobuf-JSON, where nested per-candidate objects cost ~50 B each and would blow Req 4.4 at ~2.2 KB worst case. This shape bounds the worst case (5 sets × 5 longest-name candidates) at ≈ 1.0 KB of JSON. Equal-length arrays are an invariant the writer enforces and the reader checks (mismatch ⇒ treat as no evidence for that class). The marker is the only way to distinguish "never produced / migrated away" from "produced, nothing qualified" (Req 4.3); the device write path sets it whenever segmentation ran with a tensor.

## Error Handling

No new failure modes on the capture path by design: the pass is bounded work (no timeout), throws nothing, and runs after the estimate's figures are already computed. If the tensor is unavailable (dev-stub segmenter without probabilities, or any future path that drops it), `candidateEvidence` stays `nil` and the record writes marker `false` — the Req 3.3/3.4 degrade, exercised rather than exceptional. A malformed persisted set (unequal parallel arrays) reads as no evidence for that class, never as an error.

## Testing Strategy

**Pre-implementation gate (Decision 11): DISCHARGED 2026-08-11 — see Decision 13.** `tools/candidate_probe.py` is the probe of record and stays re-runnable against a later model, palette or statistic. Outcome: mean-over-region ships; the exit condition ("neither statistic carries plate-specific signal") was not met — rank 1 agrees with the corpus prior only 15.7% of the time across 29 distinct rank-1 classes. Two findings bind the implementation below. The device bundles are **single-food plates**, so the deciding figures come from the validation leg (200 plates, 676 scored foods, 27 distinct foods, checkpoint `ab812dc3aa9d`) and are not device figures — that leg omits speckle regularisation and reads a softmax over logits rather than an FP16 round trip. And boundary bleed is present, unmitigated, and shipping; if Req 8 returns neutral it is the first place to look.

MedataCore tests only (the App-target files are documentation contracts, not an executable suite):

- **`CandidateEvidenceTests` (SegmentationTests):** synthetic FP16 tensors with known per-channel structure → exact expected rankings; exclusion of self/background/sentinels/cross-phase; strictly-positive-support filter; the 5-set cap picks the largest sampled foods; stride anchoring (a food entirely off the stride grid yields no entry); determinism (two runs bit-equal). One seeded-randomised invariant test (no new dependency): for arbitrary tensors, every returned set obeys count ≤ 5, excludes the key class, and is sorted by descending mean.
- **Req 2.2 non-interference:** run PostProcessing with and without the pass on the same input; assert argmax bytes, σ_seg, `perClassMeanProb`, and refusal outcome identical.
- **`ShortlistOrderingTests` (FoodsTests):** recency positions invariant under any candidate input (Req 7.2); evidence displaces top-up only; empty-candidates degeneracy (Req 7.4 byte-identity against a shipped-shape fixture: recency + top-up); limit and duplicate handling.
- **Replay parity (HarnessCLITests):** a fixture's FP16 tensor + persisted argmax through `compute` → equal against a committed golden expected set, pinning both the algorithm and the FP16-decode contract.
- **Persistence (PersistenceTests):** JSON round-trip of fields 16/17 including through the pb bridge and `withPhotoAssetID` (the member-wise copy sites); a pre-spec JSON record decodes with marker false and no evidence (Req 4.3); `PaletteMigrator.reDerive` output carries no evidence and a false marker while all other fields match the migration's expected transform (Req 5.2); a worst-case record (5 sets × 5 longest names) measures ≤ 1 KB of added JSON (Req 4.4, asserted not assumed).
- **Device (human-gated, tethered session):** Req 3.1's ≤ 50 ms median on the 16 Pro measured via the existing capture timing log; Req 8's corpus measurement waits on accumulated corrections (Decision 5 gates closure, not implementation).

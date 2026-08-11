---
references:
    - specs/estimation/alternative-class-candidates/requirements.md
    - specs/estimation/alternative-class-candidates/design.md
    - specs/estimation/alternative-class-candidates/decision_log.md
---
# Alternative Class Candidates

## Probe gate (Decision 11)

- [x] 1. Offline probe of the ranking statistic over real tensors <!-- id:67qnbf3 -->
  - Standalone offline script (tools/, not shipped code) — runs a prototype of the compute over admissible tensors only: device capture bundles and segmenter validation outputs. Nutrition5k fixtures are excluded, their argmax field carries the ground-truth mask, not a persisted prediction
  - Report (a) top-5 set constancy across foods and plates, (b) adjacency share of rank-1 candidates, (c) both figures again under a second-argmax-share statistic
  - Use the same sampling the design fixes: stride-4 in both axes anchored at (0,0), FP16 tensor decode, regularised label map, 64-sample floor per detected class
  - DONE 2026-08-11: tools/candidate_probe.py. The five device bundles are single-food plates (four bread, one rice), so adjacency is unmeasurable there and constancy rests on n=2 — the deciding run is the validation leg Decision 11 permits (checkpoint ab812dc3aa9d, 200 plates, 676 scored foods, 27 distinct foods, 160 multi-food plates)
  - Findings: rank-1 adjacency 69.7% vs 9.1% chance and erosion does not remove it (57.7% at 16 px, -27% scored foods); prior domination absent at the top (rank 1 matches the corpus prior 15.7%, 29 distinct rank-1 classes); the true class is in the top five on 78.2% of the segmenter wrong regions under mean vs 68.6% under second-argmax share
  - The literal second-argmax definition returns nothing — background is the top non-winner at 99-100% of food pixels, so eligibility must be applied before the statistic, not after ranking
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3)

- [x] 2. Fix the ranking statistic and record it as a decision <!-- id:67qnbf4 -->
  - Decision 13 added to decision_log.md: mean over eligible channels ships; second-argmax share, interior-only sampling and early exit all rejected with measured reasons
  - design.md behavioural-contract row no longer marked provisional; the Testing Strategy gate is marked discharged and carries the corpus caveats
  - Boundary bleed ships unmitigated and is named as the first place to look if Req 8 returns neutral — see "Mitigate boundary bleed in the candidate ranking" and, failing that, the removal gate
  - Blocked-by: 67qnbf3 (Offline probe of the ranking statistic over real tensors)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3)

## The evidence pass (MedataCore Segmentation)

- [x] 3. CandidateEvidence.compute over a strided FP16 accessor <!-- id:67qnbf5 -->
  - New file MedataCore/Sources/Segmentation/CandidateEvidence.swift — one pure enum with Candidate (className: String, meanPermille: UInt32) and compute(probabilities:labelMap:palette:) -> [String: [Candidate]]
  - Decode the FP16 ProbabilityTensor through a per-pixel strided accessor, never FP16Bytes.decode (whole-tensor, ~398 MB of FP32 for a full frame) and never the pipeline's intermediate FP32 buffer — the FP32 low bits differ from the FP16 bytes a replayed bundle carries and could flip a borderline ranking
  - Stride 4 in both axes anchored at (0,0); serial raster accumulation so Float sum order is fixed and replay parity needs no deterministic-reduction machinery
  - Exclusions: the food's own channel, background, unknown_food, unsupported_liquid, and cross-phase channels — isFoodClass/isLiquidClass decide phase
  - Decision 13: apply eligibility to the channel set BEFORE taking the statistic, not by ranking all channels and filtering after. The two differ whenever a sentinel would otherwise occupy a slot, and background outscores every food channel at ~100% of food pixels
  - Rank descending by the statistic pre-quantisation, ties broken by channel declaration order; retain the top 5 with strictly positive support
  - Floor: a detected class with fewer than 64 sampled pixels gets no entry at all (Decision 11)
  - Cap: retain sets for at most the 5 detected classes with the most sampled pixels, ties by declaration order (Decision 10, the persisted-encoding budget bound)
  - Purely additive — reads the tensor and the label map, writes nothing else
  - Blocked-by: 67qnbf4 (Fix the ranking statistic and record it as a decision)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [1.8](requirements.md#1.8), [2.1](requirements.md#2.1), [2.3](requirements.md#2.3), [3.2](requirements.md#3.2)

- [x] 4. Call the pass from PostProcessing and surface it on SegmentationResult <!-- id:67qnbf6 -->
  - Call site is PostProcessing.swift after regulariseLabelMap (:201), on the regularised map — not a pre-regularisation assignment
  - The ProbabilityTensor is currently constructed at :209; reorder so it exists before the pass, so the FP16 contract is not accidentally satisfied from the FP32 resized buffer
  - New field on PostProcessedOutput (PostProcessing.swift:14-19), surfaced by CoreMLSegmenter onto SegmentationResult.candidateEvidence: [String: [Candidate]]? — a new optional defaulting to nil, so every existing constructor and hand-built test result compiles unchanged
  - nil means not produced; non-nil however empty means produced — this is what feeds the Decision 4 marker
  - No tensor (dev-stub segmenter, or any future path that drops it) leaves it nil and completes the estimate normally; no timeout, no throw, no new failure mode
  - Blocked-by: 67qnbf5 (CandidateEvidence.compute over a strided FP16 accessor)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4)

- [x] 5. CandidateEvidenceTests <!-- id:67qnbf7 -->
  - Synthetic FP16 tensors with known per-channel structure asserting exact expected rankings
  - Exclusion of self, background, sentinel and cross-phase channels; strictly-positive-support filter; a class that won no pixel anywhere can still appear
  - The 5-set cap picks the largest sampled foods; the 64-sample floor yields honest absence
  - Stride anchoring: a food entirely off the stride grid yields no entry
  - Determinism: two runs bit-equal
  - One seeded-randomised invariant test, no new dependency — for arbitrary tensors every returned set has count <= 5, excludes its key class, and is sorted by descending magnitude
  - Blocked-by: 67qnbf5 (CandidateEvidence.compute over a strided FP16 accessor)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.8](requirements.md#1.8), [2.3](requirements.md#2.3), [7.5](requirements.md#7.5)

- [x] 6. Non-interference test for the existing figures <!-- id:67qnbf8 -->
  - Run PostProcessing with and without the pass on the same input; assert the argmax bytes, sigma_seg, perClassMeanProb and the refusal outcome are identical
  - This is the guard on the hard invariant — the spec adds a retained quantity and corrects none
  - Blocked-by: 67qnbf6 (Call the pass from PostProcessing and surface it on SegmentationResult)
  - Stream: 1
  - Requirements: [2.2](requirements.md#2.2)

## Persistence contract (MedataCore)

- [x] 7. MealRecord.proto gains candidate_evidence and its produced marker <!-- id:67qnbf9 -->
  - message CandidateSet { repeated string class_names = 1; repeated uint32 mean_permille = 2; } — parallel arrays, not nested per-candidate objects, which cost ~50 B each in protobuf-JSON and would blow the budget at ~2.2 KB worst case (Decision 10)
  - On MealRecord: map<string, CandidateSet> candidate_evidence = 16 keyed by detected class name, bool candidate_evidence_produced = 17; regenerate MealRecord.pb.swift
  - Additive only — the correction-record schema that estimation/pipeline Req 14.4 shares verbatim with the clinical track does not move
  - Equal-length parallel arrays are a writer-enforced invariant that the reader checks; a mismatch reads as no evidence for that class, never as an error
  - Blocked-by: 67qnbf4 (Fix the ranking statistic and record it as a decision)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4)

- [x] 8. Carry evidence and marker through the meal-record assembly <!-- id:67qnbfa -->
  - Pipeline.swift MealRecord assembly (~:539, where segmenterSource and macros land) copies the evidence map and sets the marker from the segmentation result
  - Marker true whenever segmentation ran with a tensor, independent of whether any set qualified — that is what keeps the Req 8.2 partition a property of the code path rather than of plate content
  - Blocked-by: 67qnbf6 (Call the pass from PostProcessing and surface it on SegmentationResult), 67qnbf9 (MealRecord.proto gains candidate_evidence and its produced marker)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.3](requirements.md#4.3)

- [x] 9. Member-wise copy sites in MealRecord.swift <!-- id:67qnbfb -->
  - The pb bridge in both directions (MealRecord.swift:105-158) reconstructs member-wise and MUST carry fields 16/17 or evidence silently drops — Decision 4's wrong-in-the-direction-that-looks-fine
  - withPhotoAssetID (:70-80) has the same hazard and runs after every capture
  - No change needed at the JSONL export, records browse, deletion or retention paths — they serialise or operate on whole records
  - Blocked-by: 67qnbf9 (MealRecord.proto gains candidate_evidence and its produced marker)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2)

- [x] 10. PersistenceTests for the round trip, back-compatibility and the size budget <!-- id:67qnbfc -->
  - Protobuf-JSON round trip of fields 16/17 including through the pb bridge and withPhotoAssetID — the member-wise copy sites
  - A pre-spec JSON record decodes with the marker false and no evidence, so absence stays distinguishable from a computed empty set
  - A worst-case record (5 sets x 5 longest-name candidates) measures <= 1 KB of added JSON — asserted, not assumed
  - Pin the JSON path specifically: SwiftProtobuf JSON decoding throws on unknown fields, so a downgraded reader would fail on a record carrying 16/17. Downgrade is not a supported path for this app; note it, do not design around it
  - Blocked-by: 67qnbfb (Member-wise copy sites in MealRecord.swift)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4)

- [x] 11. Palette migration drops evidence by construction <!-- id:67qnbfd -->
  - No PaletteMigrator code change — reDerive builds a fresh record, so evidence drops and the marker defaults false
  - Test that reDerive output carries no evidence and a false marker while every other field matches the migration's expected transform, and that the result is indistinguishable from a record that never carried evidence
  - Blocked-by: 67qnbfb (Member-wise copy sites in MealRecord.swift)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)

## Combined ordering (Foods and App)

- [x] 12. ShortlistOrdering.combined <!-- id:67qnbfe -->
  - New file MedataCore/Sources/Foods/ShortlistOrdering.swift with recencySource = "recency" (the shipped value) and combinedSource = "recency_plus_candidates"
  - combined(recency:candidates:topUp:limit:) -> [String] — three layers: recency entries in their exact shipped positions, then evidence fills in rank order skipping duplicates, then the shipped eligible top-up for any slots still empty
  - Evidence displaces only the blind top-up, never a recency entry; with no evidence, layers 1+3 are byte-identical to the shipped list
  - All three inputs are already-eligible class ids — eligibility and phase filtering stay with the caller, exactly as shipped
  - Deterministic: same recency history plus same evidence always yields the same order
  - Blocked-by: 67qnbf4 (Fix the ranking statistic and record it as a decision)
  - Stream: 2
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)

- [x] 13. ShortlistOrderingTests <!-- id:67qnbff -->
  - Recency positions invariant under any candidate input
  - Evidence displaces top-up entries only
  - Empty-candidates degeneracy: byte-identity against a shipped-shape fixture of recency + top-up
  - Limit and duplicate handling
  - Blocked-by: 67qnbfe (ShortlistOrdering.combined)
  - Stream: 2
  - Requirements: [7.2](requirements.md#7.2), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)

- [x] 14. MealReviewModel consumes the combined ordering <!-- id:67qnbfg -->
  - buildShortlist (App/MealReviewModel.swift:714-727) always calls combined; the record's marker gates the evidence layer, not the function — marker false passes an empty candidates layer and produces the byte-identical shipped list (design.md, amended)
  - shortlist_source on PbCorrectionRecord takes combinedSource exactly when the marker is true — the ordering that ran, not whether fills landed
  - No score, percentage or confidence tier from the evidence reaches the screen
  - The full eligible list stays the same set; Req 3.8/3.9 of ui/meal-review still bound what is offered — density and carbohydrate coefficient required, no relabel across the solid/liquid boundary
  - Blocked-by: 67qnbfe (ShortlistOrdering.combined), 67qnbfa (Carry evidence and marker through the meal-record assembly)
  - Stream: 2
  - Requirements: [7.1](requirements.md#7.1), [7.4](requirements.md#7.4), [7.6](requirements.md#7.6), [7.7](requirements.md#7.7), [7.8](requirements.md#7.8), [7.9](requirements.md#7.9)

## Replay parity

- [x] 15. HarnessCLITests replay parity against a committed golden <!-- id:67qnbfh -->
  - The parity test is the only harness caller: compute(fixture FP16 tensor, fixture persisted argmax, palette) compared against a committed golden expected set
  - Admissible fixtures are capture-bundle-derived and synthetic only — bundle fixtures record the cleaned prediction (PostProcessing.swift:214) so their argmax is the persisted mask. Nutrition5k fixtures carry the ground-truth mask in the same field and are excluded
  - Pins both the ranking algorithm and the FP16-decode contract; the harness runs no PostProcessing, writes no meal records and sets no marker, and nothing beyond the shared function is claimed as parity coverage
  - Blocked-by: 67qnbf5 (CandidateEvidence.compute over a strided FP16 accessor)
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)

## Corpus measurement (Req 8)

- [x] 16. Build the shortlist hit-rate analysis over the corrections corpus <!-- id:67qnbfi -->
  - Agent-executable and runnable the day it is written — the recency arm has been accumulating since ui/meal-review shipped 2026-08-09, so the analysis can be exercised and its output shape fixed before the combined arm exists
  - No new fields — the corpus already carries what all four criteria need
  - Hit rate is shortlist_rank > 0 on relabel correction records (rank 0 means full-list or no relabel); partition by shortlist_source; the same metric over both arms is the baseline comparison
  - First-vs-repeat: a corrected class X for predicted class P is a repeat iff an earlier correction record by timestamp corrects P to X — the same relation recency ranks from
  - Decision 12 mitigations are part of the deliverable, not optional: stratify by reconstructed recency depth (count of distinct earlier P-to-X corrections at each record's timestamp), and run an as-treated secondary that identifies combined-arm rows whose evidence set was empty for the predicted class
  - BOUNDARY-BLEED PARTITION (Decision 13), also not optional: split the combined-arm hit rate by whether the corrected class was ADJACENT to the predicted region on that plate. The probe measured rank-1 adjacency at 69.7% against a 9.1% chance baseline and erosion does not remove it, so the shortlist is substantially ordered by what touches the food. This partition is what says whether that helps or hurts: if adjacent corrections hit and non-adjacent ones miss, bleed is crowding genuine confusions out of the five slots and "Mitigate boundary bleed in the candidate ranking" fires
  - Adjacency is recoverable offline for meals whose capture bundle survives (recompute from the persisted argmax); where no bundle survives the row is reported as unknown rather than assumed non-adjacent, and the unknown count is printed beside the figure
  - The output states the temporal confound: the two arms are separated in time and recency strengthens as the corpus grows, so a naive comparison flatters the combined arm
  - Emit the per-arm counts alongside every figure, so a verdict is never read off cells too small to carry one
  - DONE 2026-08-12: tools/shortlist_hit_rate.py. Reads device pulls and archive exports (correction_records plus the events meal rows) or the app's Corrections JSONL, deduplicating on the store's own key (meal_id, predicted_class) with the newest updated_at winning, so successive pulls of one device can be passed together
  - Cuts emitted, each with its cell count: hit rate per arm, first-vs-repeat, recency-depth strata, the as-treated states (evidence, no_evidence, marker_false, no_meal_record) and the boundary-bleed partition, whose bleed_verdict token stays insufficient until both cells clear --min-cell
  - Adjacency joins a meal to its capture bundle by timestamp and then verifies the match against the meal's detected classes; an unverifiable row reports unknown, never non-adjacent. First-vs-repeat and recency depth are reconstructed from created_at, because updated_at is rewritten by later mutations
  - The temporal confound is stated as data rather than prose — per-arm first and last date beside the median recency depth, next to the depth strata that are the only cut separating a better ordering from a deeper history
  - Corpus as of 2026-08-12: 8 correction rows over 6 meals, all shortlist_source=recency, and zero of them relabels, so every cell is n=0. The output shape is fixed and the arithmetic exercised; the numbers wait on real corrections in both arms
  - Blocked-by: 67qnbfg (MealReviewModel consumes the combined ordering)
  - Stream: 1
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.3](requirements.md#8.3), [8.4](requirements.md#8.4)

- [ ] 17. Mitigate boundary bleed in the candidate ranking (conditional) <!-- id:67qnbfm -->
  - Fires only if the boundary-bleed partition in "Build the shortlist hit-rate analysis over the corrections corpus" shows bleed is HURTING — adjacent corrections hitting the shortlist while non-adjacent ones miss, meaning what touches the food is crowding genuine confusions out of the five slots. A partition showing the opposite closes this task as no-change-needed
  - Evidence that put it here (Decision 13, probe 2026-08-11): rank-1 candidates physically touch the food 69.7% of the time against a 9.1% chance baseline. Intrinsic, not an edge artefact — eroding each region before accumulating reaches only 57.7% at 16 px and costs 27% of scored foods, so interior-only sampling is already measured and rejected as the remedy
  - Why it ships unmitigated: the same probe found the true class in the top five on 78.2% of the segmenter wrong regions, consistent with bleed BECAUSE the adjacent class is frequently the correct one — a mislabelled region has usually had a neighbour label smeared across it. Bleed and signal are the same measurement until corrections separate them
  - Candidate mitigations, none yet evidenced: subtract a co-occurrence baseline so a candidate ranks by how far it exceeds what mere adjacency predicts; weight sampled pixels by distance from the region boundary instead of excluding a hard margin; or drop candidates whose support sits only on pixels bordering that class own region
  - Measure any mitigation against the committed baseline with tools/candidate_probe.py — it takes --erode and prints adjacency beside the chance floor, so a change is one command
  - Not the same lever as "Remove the pass and the retained field if the verdict is negative": that removes the feature on a negative Req 8 verdict, this repairs the ranking while keeping it. Removal is the fallback if this fails or is not worth its cost
  - See docs/agent-notes/candidate-evidence.md for the probe mechanics and the full figures
  - STILL PENDING 2026-08-12: the analysis exists and runs, but the partition it fires on returns bleed_verdict=insufficient — the corpus carries no relabels at all yet, so neither the adjacent nor the non-adjacent cell has a row. This task cannot be closed either way until corrections accumulate
  - Blocked-by: 67qnbfi (Build the shortlist hit-rate analysis over the corrections corpus)
  - Stream: 1
  - Requirements: [1.3](requirements.md#1.3), [8.1](requirements.md#8.1)

## Acceptance gates (not agent-executable)

- [ ] 18. Capture-path cost on the hardware floor (STOP) <!-- id:67qnbfj -->
  - NOT agent-executable. Human-gated tethered session on the iPhone 16 Pro; an autonomous run halts here rather than attempting it
  - Match the launch buildStamp before trusting any device output
  - Read the median end-to-end capture duration off the existing capture timing log with and without the pass; the added median must be <= 50 ms
  - Also confirm on device that a capture with no tensor completes the estimate with the marker false rather than delaying or failing
  - Blocked-by: 67qnbfg (MealReviewModel consumes the combined ordering)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4)

- [ ] 19. Record the acceptance verdict against the recency baseline (STOP) <!-- id:67qnbfk -->
  - NOT agent-executable. Waits on real use of the surface — Decision 5 gates spec closure, not implementation, and no session can manufacture the corrections the verdict reads from
  - Run the "Build the shortlist hit-rate analysis over the corrections corpus" analysis once both shortlist_source arms carry enough rows, and record the outcome as a decision in decision_log.md
  - The first-correction split is the measurement that matters most; aggregate hit rate is dominated by repeat foods where recency already wins
  - A neutral or negative result is a valid outcome and is recorded as such rather than tuned around — the repository precedent is segmenter-foundation Decision 24, which recorded a negative verdict and kept the incumbent
  - Blocked-by: 67qnbfi (Build the shortlist hit-rate analysis over the corrections corpus)
  - Stream: 1
  - Requirements: [8.3](requirements.md#8.3), [8.4](requirements.md#8.4)

- [ ] 20. Remove the pass and the retained field if the verdict is negative (STOP) <!-- id:67qnbfl -->
  - NOT agent-executable as a standing task — conditional on the "Record the acceptance verdict against the recency baseline" outcome, and a no-op if the verdict is positive
  - Decision 5 states the obligation: a neutral result still leaves the retained field on the record and the pass on the capture path until a removal is done. This task is where that lands rather than going unrecorded
  - Reverting costs the two record fields, the compute pass and its call site; no correction path regresses because the recency prior stayed a live component of the ordering throughout
  - Records already written keep fields 16/17 — removal drops the writer, not the reader, so historical rows stay decodable
  - Blocked-by: 67qnbfk (Record the acceptance verdict against the recency baseline STOP)
  - Stream: 1
  - Requirements: [8.3](requirements.md#8.3)

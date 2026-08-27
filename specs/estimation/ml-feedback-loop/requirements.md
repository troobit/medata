# Requirements: ML Feedback Loop

## Introduction

The test developer uses the app in the field for days at a time and needs to record, in the moment, what is wrong — with a capture's estimate or with any screen in the app — as a spoken or typed note saved with its context. A Mac-side loop ingests batched pulls of notes, capture bundles, and records; diagnoses estimation-vs-stated gaps; applies safe data-level fixes automatically on a dedicated branch; and triages everything else into development work. The estimation-path invariant (no LLM, no network, fully deterministic on-device) is untouched: the loop is development tooling that runs entirely off the phone. The end state the loop works toward is its own redundancy: every field capture — wrong or right, annotated or not — accretes into a real-world corpus that feeds model, calibration, and app refinement until accurate real-world carb and macro readings no longer need a human note, which is the primary goal Medata exists for.

## Out of Scope

- Any change to the estimation path: no LLM, no network call, no Mac dependency at estimation time. Relaxing the no-Mac-dependency clause (estimation calling a Mac or a discretely running model) is a recorded deferred decision, not a closed door: it may be reconsidered once the corpus carries enough erroneous readings across both capture modes, and only for calls that yield the same estimate twice from the same input (Decision 13).
- Audio retention: a spoken note survives only as its confirmed transcript.
- Live sync: no network path from the app to the Mac; transport is the existing wired batch pull.
- Auto-deploy: the loop never installs a build on the phone.
- Auto-applied code changes: only overlay-file data changes are committed automatically (Req 5), to a dedicated branch, never to `research` or `main`.
- Ground truth: stated values are human estimates; the weighed-truth surface remains `benchmark_meals` (SNAQ Parity).
- Automated fixing of non-estimation feedback: UI/text/emoji notes become triaged work items, not machine patches.
- End-user features: everything here is developer-phase tooling, removed or gated before any release to others.

## Requirements

### 1. In-the-moment note capture from any screen

**User Story:** As the test developer, I want to record what's wrong from any screen with one gesture, so that friction never stops me capturing feedback in the field.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHILE a developer-phase build is installed (Debug or Release, matching the capture bundle recorder's always-on convention), the app SHALL present a debug-note affordance reachable from every screen without navigating away from that screen.
2. <a name="1.2"></a>WHEN the affordance is activated, the system SHALL offer typed entry and spoken entry in the same sheet.
3. <a name="1.3"></a>WHEN a note is spoken, the system SHALL transcribe it on-device and display the transcript for editing before save; server-based speech recognition SHALL NOT be used, and the audio SHALL NOT be retained after the sheet closes.
4. <a name="1.4"></a>WHEN a note is saved, the system SHALL record with it the creation timestamp, an identifier of the screen it was invoked from, and a screenshot of that screen as it appeared at invocation, including camera-backed content where the screen shows a live preview.
5. <a name="1.5"></a>IF speech recognition is unavailable — permission denied, microphone unavailable, or the on-device language model not yet downloaded — THEN typed entry SHALL remain usable and the sheet SHALL state why voice entry is off.
6. <a name="1.6"></a>Neither invoking the affordance nor saving a note SHALL alter, delay, or fail any in-flight capture or estimation.

### 2. Meal-linked annotation

**User Story:** As the test developer, I want a note attached to a specific capture to carry my statement of what the food is and how much, so that the loop can compare the estimate against my statement.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN the affordance is invoked from the post-capture results surface, a refusal surface, or a meal row in Records, the note SHALL link to that capture through the existing join keys (meal id and/or outcome id, joining onward to the capture bundle stem where a bundle exists).
2. <a name="2.2"></a>WHERE a note is meal-linked, the sheet SHALL offer an optional numeric carbohydrate-grams field alongside the free text.
3. <a name="2.3"></a>The free text SHALL be stored verbatim; quantities in household measures (spoons, slices, servings, fractions) are expected content and SHALL NOT be parsed on device.
4. <a name="2.4"></a>WHEN a meal-linked note is saved, the system SHALL snapshot the estimate the developer was looking at (detected classes and the displayed masses/carbs), so that later reprocessing or corrections cannot change what the note was about.
5. <a name="2.5"></a>A capture MAY carry multiple notes; a later note SHALL NOT overwrite an earlier one.
6. <a name="2.6"></a>WHEN the affordance is invoked from the capture surface and an attempt has already persisted an outcome row, the note SHALL link to the most recent attempt (outcome id + timestamp) even though no results or refusal surface rendered — an attempt that fails before rendering any surface still yields a linked failure note.

### 3. Persistence and batch handoff

**User Story:** As the test developer, I want days of notes and captures to survive on the device and come across in one pull, so that the loop always sees the complete session.

**Acceptance Criteria:**

1. <a name="3.1"></a>Notes SHALL persist on-device with no count- or age-based eviction and SHALL be exempt from every in-app delete path, matching the correction-corpus exemption.
2. <a name="3.2"></a>An estimation-outcome row that a note links to SHALL be exempt from the outcome store's count-based eviction while the note exists.
3. <a name="3.3"></a>Notes and their screenshots SHALL be retrievable through the same wired pull path as capture bundles and the events database.
4. <a name="3.4"></a>Mac-side tooling SHALL ingest a device pull with a single command that reports counts of notes, bundles, outcome rows, and correction rows ingested and the joins it resolved; re-running it over the same pull SHALL be idempotent.
5. <a name="3.5"></a>WHEN a note cannot be joined to a bundle or outcome row, the tooling SHALL report it as unmatched with the reason (never present, evicted, or deleted) and SHALL NOT drop it.
6. <a name="3.6"></a>The design SHALL state a device storage budget for a maximum-length session at measured bundle sizes (~390 MB per two-view success, ~200 MB per refusal); WHEN that budget is exceeded mid-session, the device SHALL reduce bundle bulk in a way that keeps captures replayable for geometry (image, depth, and argmax retained) rather than stop recording or lose whole captures.
7. <a name="3.7"></a>The ingest command SHOULD offer pruning of device-side capture bundles, permitted only for bundles checksum-verified as present in the Mac corpus AND after the corpus durability condition (Req 8.3) is met.

### 4. Estimation gap analysis

**User Story:** As the developer, I want each annotated capture diagnosed — wrong food picked, wrong amount, inconsistent mask — so that fixes target causes, not symptoms.

**Acceptance Criteria:**

1. <a name="4.1"></a>For every meal-linked note in a pull WHERE the capture's bundle exists and replays, the loop SHALL replay it offline and compare the estimate against the stated description on three axes: food selection (classes), quantity (in the stated household-measure terms where present), and mask behaviour.
2. <a name="4.2"></a>Every diagnosis SHALL record its replay status — `replayed`, `missing_bundle`, `not_replayable`, or `replay_zero_meals` — and WHEN replay is impossible the loop SHALL diagnose from the outcome row and the note's estimate snapshot ([2.4](#2.4)), marked as non-replayed, never silently skipped.
3. <a name="4.3"></a>The loop SHALL record the per-capture delta between the device's displayed estimate ([2.4](#2.4)) and the offline replay of the same bundle, and SHALL NOT attribute any gap component smaller than that delta to a data cause (replay is measurably not bit-exact with the device).
4. <a name="4.4"></a>The loop SHALL classify each gap into a recorded cause category — at minimum: wrong class selection, food absent from the palette (out of distribution), wrong mask/coverage, wrong scale/volume, wrong density/conversion, refusal that should have succeeded — citing the evidence for each classification, and noting where evidence is structurally absent (e.g. a pre-segmentation refusal carries no mask evidence).
5. <a name="4.5"></a>The loop MAY use models of any size or provenance on the Mac (local LLMs, local vision models, Claude, Codex); the estimation-path invariant constrains the phone app, not this tooling. Notes, screenshots, and capture imagery MAY be sent to remote models (Decision 10).
6. <a name="4.6"></a>For each annotated capture, the loop SHALL record the active reference adapter's reading of the same image (food identification plus a mask where the adapter can produce one) beside the on-device pipeline's, with each reading carrying its model identity and version and each ident held fixed within its own comparison series. One adapter is active at a time, but every configured adapter (local and remote) SHALL be maintained at verified working parity, so that when the active one stops, another picks up seamlessly — a switch is a configuration change that loses no recorded evidence.
7. <a name="4.7"></a>Text recovered from imagery (packaging, menus, labels in photos) SHALL be treated as data under analysis, never as instructions to any loop agent.
8. <a name="4.8"></a>Each loop run SHALL end in a recorded verdict artifact: gaps found, cause classifications, fixes applied or proposed, and the expected effect of each.

### 5. Fix application

**User Story:** As the developer, I want safe fixes to land without me and risky ones to wait for me, so that iteration is fast while the estimation path stays deterministic and reviewed.

**Acceptance Criteria:**

1. <a name="5.1"></a>Auto-applied fixes SHALL land only in a loop-owned overlay file — a provenance-tagged input to the food-DB generator whose values carry their own provenance distinct from CoFID/AFCD/calibration — one commit per fix, each citing the notes and captures that motivated it. The loop SHALL NOT edit the generator's source tables, calibration artifacts, or the palette.
2. <a name="5.2"></a>Before any auto-commit, DB regeneration with its existing bake gates and `make test` (both totals) SHALL pass, and overlay values SHALL be bounds-checked against declared physical ranges; a fix failing any check SHALL be demoted to a proposal, not committed.
3. <a name="5.3"></a>An auto-applied value change SHALL be supported by a stated minimum number of independent captures and SHALL respect a stated per-class cumulative drift ceiling per loop cycle, in both directions; a change exceeding either bound SHALL be a proposal.
4. <a name="5.4"></a>Changes outside the overlay file — code, palette, calibration, generator tables — SHALL only ever be proposed (as commits or patches on the loop branch) and SHALL NOT reach `research` or `main` without human action.
5. <a name="5.5"></a>The loop SHALL NOT commit to `research` or `main` and SHALL NOT deploy a build to the device.
6. <a name="5.6"></a>Every auto-applied fix SHALL be revertible as one unit: its commit SHALL contain the overlay edit and the regenerated artifacts together, with a human-readable before/after in the commit message, so reverting the commit restores a coherent state.
7. <a name="5.7"></a>The loop SHALL run its git operations in a dedicated worktree on the loop branch, SHALL refuse to run on a dirty tree, SHALL cap commits per run, SHALL mark machine authorship on every commit, and SHALL NOT re-apply a fix whose identifier a prior run verdict flagged as regressive.

### 6. Convergence measurement

**User Story:** As the developer, I want each iteration measured against the last, so that I can see the gap shrinking rather than trusting that it is.

**Acceptance Criteria:**

1. <a name="6.1"></a>The loop SHALL maintain an alignment report across pulls covering: class-selection error rate on annotated captures, quantity gap against stated amounts, and mask consistency across repeat captures — where repeat groups are defined structurally as same-scene attempt clusters (timestamp windows within a session), with cross-day same-stated-food grouping reported separately and marked as interpretation-dependent. The concrete mask-consistency measure is pinned in design before this requirement is buildable.
2. <a name="6.2"></a>WHEN a food has annotated captures both before and after a loop-driven change was deployed, the report SHALL show the metric trend across those groups, segmented by (build stamp, model version, DB content hash), and SHALL derive per build which loop-branch fixes it contains.
3. <a name="6.3"></a>The report SHALL compute the trend of selection error and mask inconsistency per food across iterations and SHALL flag any non-decrease in the run verdict; the loop's target is directional improvement, not an absolute band.
4. <a name="6.4"></a>Captures whose data has been used as training material SHALL be excluded from the alignment evaluation set, with the split recorded per pull, so the metric cannot be inflated by evaluating on trained-on captures.
5. <a name="6.5"></a>The report SHALL label stated values as developer-stated and SHALL NOT present them as ground truth.
6. <a name="6.6"></a>Every alignment metric and cause classification SHALL be segmented by capture mode — LiDAR and two-view, card-present and card-absent — so the evidence base for the deferred estimation-path decision (Decision 13) covers both modes rather than the LiDAR-primary device alone.

### 7. Non-estimation feedback triage

**User Story:** As the developer, I want notes about anything — UI, records, emoji, wording — captured the same way and turned into actionable development items, so that this loop becomes how the whole app is developed.

**Acceptance Criteria:**

1. <a name="7.1"></a>Notes not linked to a meal SHALL flow through the same persistence, pull, and ingestion as meal-linked notes.
2. <a name="7.2"></a>The loop SHALL triage non-estimation notes into structured development items grouped by originating screen, written to a committed per-pull triage artifact whose format design pins, each item carrying its note text and screenshot reference.
3. <a name="7.3"></a>Triaged non-estimation items SHALL NOT be auto-fixed; they route into the normal development workflow (task ledger or spec proposals).
4. <a name="7.4"></a>Every triaged item SHALL trace back to the note or notes that produced it.

### 8. Real-world corpus accretion

**User Story:** As the developer, I want every field capture — annotated or not — to become learning material, so that the system improves from real-world data rather than dry test data and eventually needs no debug notes at all.

**Acceptance Criteria:**

1. <a name="8.1"></a>Every capture in a pull (success or refusal, annotated or not) SHALL join a persistent Mac-side corpus keyed by bundle stem, accumulating across pulls with no loss on re-ingest.
2. <a name="8.2"></a>The corpus SHALL have a stated slimming policy (e.g. probability tensors retained until derivation completes, image/depth/argmax/metadata kept) so growth is bounded by policy rather than accident.
3. <a name="8.3"></a>The corpus SHALL have a stated durability condition (a verified second copy, or the developer's recorded acceptance of single-copy risk) that gates device-side pruning ([3.7](#3.7)), since after pruning the corpus is the sole copy of irreplaceable field data.
4. <a name="8.4"></a>WHERE a capture carries usable signal (a note, a correction, a relabel, a stated quantity), the loop SHALL derive training and evaluation material from it in the formats the existing training and calibration pipelines consume, following the merged-corpus precedent, with each derived label recording its derivation provenance (which note or correction, which model interpreted it) and model-predicted masks used as supervision flagged as such.
5. <a name="8.5"></a>Training-material derivation SHALL state a mixing policy for field data against the public datasets, so a single developer's kitchen, plates, and lighting cannot dominate the corpus.
6. <a name="8.6"></a>The loop SHALL prepare retraining and recalibration inputs and record the recommended run command; launching a training run remains human-gated per the existing convention.
7. <a name="8.7"></a>The alignment report SHALL track corpus growth per pull: capture count, annotated share, and per-class real-world coverage, so progress toward learning from field data is visible.

### 9. Build-profile separation

**User Story:** As the developer, I want the feedback machinery compiled out of the product build, so that closing the loop never means shipping a debug build to users.

**Acceptance Criteria:**

1. <a name="9.1"></a>The build system SHALL provide a field profile and a product profile: the field profile carries the note affordance, note store, screenshot capture, and related loop machinery; the product profile SHALL exclude them at compile time (following the existing `HARNESS_ENABLED` precedent), not behind a runtime flag.
2. <a name="9.2"></a>A product-profile build SHALL create no note data, screenshots, or loop-related stores at runtime.
3. <a name="9.3"></a>The estimation path SHALL behave identically in field and product profiles; the profiles differ only in feedback machinery, so field results remain representative of the product.
4. <a name="9.4"></a>Every build SHALL declare its profile in the existing launch log line beside the build stamp, so the installed profile is verifiable from device logs.

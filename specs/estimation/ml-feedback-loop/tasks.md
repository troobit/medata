---
references:
    - requirements.md
    - design.md
    - decision_log.md
---
# ML Feedback Loop

## Swift core

- [x] 1. Write failing XCTests for protected estimation outcomes <!-- id:i6u18bj -->
  - Beside the existing eviction tests for saveEstimationOutcome in MedataCore
  - Cover: markOutcomeProtected(id:) API, exemption in the non-benchmark branch AND both benchmark per-meal-per-lineage branches, schema stamp bumps to 11, protected rows may exceed the bounds
  - CREATE TABLE IF NOT EXISTS retrofit — no ALTER migration
  - Stream: 1
  - Requirements: [3.2](requirements.md#3.2)

- [x] 2. Implement protected_outcomes table (schema v11) and eviction exemptions <!-- id:i6u18bk -->
  - GRDBPersistenceStore: new table, markOutcomeProtected(id:), AND id NOT IN (SELECT outcome_id FROM protected_outcomes) in all three eviction branches
  - Profile-neutral MedataCore API — no FIELD_LOOP condition
  - make test both totals green
  - Blocked-by: i6u18bj (Write failing XCTests for protected estimation outcomes)
  - Stream: 1
  - Requirements: [3.2](requirements.md#3.2)

- [x] 3. Write failing HarnessCLITests for the diagnose subcommand <!-- id:i6u18bl -->
  - Per-fixture JSON: predictedCarbsPerClass, perClassVolumesCm3, dominantClass, supportPlaneReference, residuals, totals
  - Replay status values: replayed / not_replayable / replay_zero_meals (missing_bundle is Mac-side)
  - Output records the replaying checkpoint SHA and DB hash for version-skew stamping
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3)

- [x] 4. Implement HarnessCLI diagnose <!-- id:i6u18bm -->
  - New subcommand beside accuracy/calibrate in HarnessCLI/main.swift; stages via existing FixtureLoader/FixtureRunner; emits the MealCalibrationInput data the accuracy path discards
  - Non-zero exit only on I/O failure — zero meals is a reported status, not a crash (calibrate-silently-drops precedent)
  - Blocked-by: i6u18bl (Write failing HarnessCLITests for the diagnose subcommand)
  - Stream: 1
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3)

- [x] 5. Write failing tests for the wire-level bundle slimmer <!-- id:i6u18bn -->
  - Against a committed miniature .fixture: slimmed output still loads, image/depth/argmax/intrinsics/gravity/mask fields intact, probability tensors absent, temp-file + atomic replace, .slimmed sidecar written
  - fixture_revision NOT mutated — the sidecar marks content state, the revision marks schema
  - Stream: 1
  - Requirements: [3.6](requirements.md#3.6)

- [x] 6. Implement the wire-level bundle slimmer in MedataCore <!-- id:i6u18bo -->
  - Varint field-skip over the proto wire format (Swift equivalent of tools/fixture_slice.py's reader) — no full SwiftProtobuf decode of a ~390 MB bundle
  - Profile-neutral MedataCore code; App-layer FieldMaintenance triggers it later
  - Blocked-by: i6u18bn (Write failing tests for the wire-level bundle slimmer)
  - Stream: 1
  - Requirements: [3.6](requirements.md#3.6)

## On-device capture

- [x] 7. Add FIELD_LOOP build profiles and the product gate <!-- id:i6u18bp -->
  - FIELD_LOOP joins SWIFT_ACTIVE_COMPILATION_CONDITIONS in project-level Debug (currently DEBUG $(inherited)) and a new Release-block setting; new ProductRelease configuration duplicates Release without FIELD_LOOP
  - Makefile: build-product / deploy-product targets; NO CLI SWIFT_ACTIVE_COMPILATION_CONDITIONS override (replaces the whole value, falsely implies package-graph control)
  - profile=field|product appended to the launch log line at App/App.swift logLaunchIdentity(); product gate = strings-grep asserting the binary lacks the profile=field literal
  - Config/wiring task — TDD exempt
  - Stream: 2
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4)

- [x] 8. Build FieldNoteWindow, FieldNoteContext, and the affordance button <!-- id:i6u18bq -->
  - Separate passthrough UIWindow at .alert+1 created on scene connection, hitTest returns nil outside the draggable button; all files App/FieldNote*.swift gated #if FIELD_LOOP at line 1 with manual pbxproj entries
  - FieldNoteContext (@Observable) composes screen id from ActiveSheet + stack top + CaptureState via ~8 .fieldScreen() mount points; sheets inside covers fall back to hosting cover id
  - UI wiring — TDD exempt (no executable app test target; gate is build + device look)
  - Blocked-by: i6u18bp (Add FIELD_LOOP build profiles and the product gate)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.4](requirements.md#1.4)

- [x] 9. Build the note sheet, note store, and screenshot service <!-- id:i6u18br -->
  - Sheet: typed entry + optional carbs-grams field on meal-linked notes; save = one JSON + one PNG per note in Documents/notes/ (CaptureBundleRecorder pattern), log-and-swallow on failure
  - EstimateSnapshot Codable frozen at save (displayed corrected values — quickPresetDraft precedent); verbatim free text, no on-device parsing; multiple notes per capture as distinct files
  - FieldScreenshot fires at tap against a retained main-scene-window reference (never key window); capture screen composites ARView.snapshot beneath ImageRenderer chrome
  - Blocked-by: i6u18bq (Build FieldNoteWindow, FieldNoteContext, and the affordance button)
  - Stream: 2
  - Requirements: [1.2](requirements.md#1.2), [1.4](requirements.md#1.4), [1.6](requirements.md#1.6), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.5](requirements.md#2.5), [3.1](requirements.md#3.1)

- [x] 10. Wire meal-link surfaces and the refusal outcome stash <!-- id:i6u18bs -->
  - Context set by MealReviewView, ResultView/overview, refusal overlay, EstimationOutcomeDetailView, Records meal-row context menu
  - CaptureFlowModel.persistAttemptRecord stashes (outcomeID, timestampMs) on the model so the refusal overlay can link
  - Meal-linked note save calls markOutcomeProtected
  - Blocked-by: i6u18br (Build the note sheet, note store, and screenshot service), i6u18bk (Implement protected_outcomes table schema v11 and eviction exemptions)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.4](requirements.md#2.4), [3.2](requirements.md#3.2)

- [x] 11. Add spoken entry via SpeechAnalyzer/SpeechTranscriber <!-- id:i6u18bt -->
  - On-device only (no server path exists in this API); AssetInventory locale asset requested at first field launch; check supportedLocales/en_IE mapping; convert to bestAvailableAudioFormat; editable transcript only after finalizeAndFinish; audio discarded
  - Degraded state (1.5) for permission denied / mic unavailable / asset absent / locale unsupported
  - NSMicrophoneUsageDescription + NSSpeechRecognitionUsageDescription in both INFOPLIST_KEY_* blocks
  - Blocked-by: i6u18br (Build the note sheet, note store, and screenshot service)
  - Stream: 2
  - Requirements: [1.3](requirements.md#1.3), [1.5](requirements.md#1.5)

- [x] 12. Implement FieldMaintenance: manifest processing and slimming triggers <!-- id:i6u18bu -->
  - Two-phase manifest (temp name + ready-sentinel with hash/length); runs at launch, foreground, post-capture; hash-gated deletes of pulled bundles/notes, prunes their protected_outcomes rows, then removes manifest+sentinel
  - Slimming: post-capture check + BGProcessingTask; budget 25 GB, low-watermark 20 GB, oldest-first, thermal/battery deferral; manifest processing runs BEFORE slimming and slimming skips manifest-listed stems
  - If watermark unreachable: keep recording, surface condition in next pull summary
  - Blocked-by: i6u18bo (Implement the wire-level bundle slimmer in MedataCore), i6u18br (Build the note sheet, note store, and screenshot service)
  - Stream: 2
  - Requirements: [3.6](requirements.md#3.6), [3.7](requirements.md#3.7)

## Overlay and generator

- [x] 13. Write failing pytest for the loop overlay in generate.py <!-- id:i6u18bv -->
  - tools/food_db/tests/: bounds per allowlisted column, *_source rewritten to LOOP_OVERLAY, beta_status/beta_provenance invalidated to uncalibrated_overlay_base on touched classes, overlay applied to in-memory rows before INSERT and before _apply_calibration, default committed path + fail-closed inverse guard (prior DB has LOOP_OVERLAY provenance but overlay absent aborts), palette-lock interaction, idempotent re-bake, meta overlay_json lineage
  - Stream: 3
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)

- [x] 14. Implement _load_overlay in generate.py and the make food-db target <!-- id:i6u18bw -->
  - Mirrors _load_calibration's fail-before-write contract; allowlist: density (0.05-2.0), solid_servings.grams_per_unit (5-500, respecting the <100 precision rule), liquid_servings.serving_ml, composition columns (0-100)
  - make food-db = python3 tools/food_db/generate.py && python3 -m pytest tools/food_db/tests/ -q (closes the no-make-entry gap)
  - Blocked-by: i6u18bv (Write failing pytest for the loop overlay in generate.py)
  - Stream: 3
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)

## Field loop tooling

- [x] 15. Write failing pytest for pull and ingest <!-- id:i6u18bx -->
  - tools/field_loop/tests/ (stdlib-only, lazy heavy imports): ingest-twice yields identical index dump; join note to outcome to (timestampMs,outcome) to stem with timestamp-window + detected-class fallback; unmatched reasons via the decision procedure (deleted / never_present; evicted = defect signal); Req 3.4 counts printed (notes, bundles, outcome rows, correction rows, joins); PRAGMA integrity_check gating; manifest+sentinel emission; corpus accretes keyed by stem
  - Stream: 3
  - Requirements: [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.7](requirements.md#3.7), [8.1](requirements.md#8.1)

- [x] 16. Implement field_pull.py, ingest, and the corpus index <!-- id:i6u18by -->
  - Corpus at <repo-parent>/medata-corpus/ resolved from git rev-parse --git-common-dir; devicectl enumerate + per-file copy incl. meals.sqlite WAL/shm/journal siblings; SHA-256 everything; INSERT OR REPLACE index writers; make field-pull target
  - Every run summary prints corpus size + the Decision 14 single-copy acceptance line
  - Blocked-by: i6u18bx (Write failing pytest for pull and ingest)
  - Stream: 3
  - Requirements: [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [3.7](requirements.md#3.7), [8.1](requirements.md#8.1), [8.3](requirements.md#8.3)

- [x] 17. Write failing pytest for diagnosis and cycle-file generation <!-- id:i6u18bz -->
  - Cluster chaining at 120s max gap, split on dominant-class change or disjoint argmax class sets; replay-delta attribution floor from skew-free pairs only; replay_version_skew stamping; cause taxonomy incl. food-absent-from-palette and structurally-absent evidence; cycle tasks.md contains only corpus-fireable tasks, ends in a terminal close task, unfireable work as STOP lines
  - Stream: 3
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.8](requirements.md#4.8)

- [x] 18. Implement field_diagnose.py <!-- id:i6u18c0 -->
  - Stages single fixtures to temp dirs for HarnessCLI diagnose; direct-proto fallback via candidate_probe reader import (never fork the reader); generates specs/estimation/ml-feedback-loop/cycles/cycle-<n>/tasks.md rune-parseable; make field-diagnose target
  - Blocked-by: i6u18bz (Write failing pytest for diagnosis and cycle-file generation), i6u18bm (Implement HarnessCLI diagnose), i6u18by (Implement field_pull.py, ingest, and the corpus index)
  - Stream: 3
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.8](requirements.md#4.8)

- [x] 19. Write failing pytest for the alignment report <!-- id:i6u18c1 -->
  - Metrics: class-selection error, quantity gap in stated household terms, mask consistency (within-cluster dominant-class agreement + mean pairwise argmax IoU + carbs CoV); segmentation by capture mode and (build stamp, model version, DB hash); dirty stamps bucketed unattributable; training_used rows excluded with both set sizes printed; evaluation-floor guard; per-food non-decrease flag; developer-stated labelling; corpus growth incl. per-class coverage; key=value output with cell counts and insufficient floors
  - Stream: 3
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [8.7](requirements.md#8.7)

- [x] 20. Implement field_report.py <!-- id:i6u18c2 -->
  - shortlist_hit_rate.py output conventions; per-build loop-fix containment via git merge-base --is-ancestor over the loop branch
  - Blocked-by: i6u18c1 (Write failing pytest for the alignment report), i6u18by (Implement field_pull.py, ingest, and the corpus index)
  - Stream: 3
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6), [8.7](requirements.md#8.7)

- [x] 21. Write failing pytest for the reference-model adapters <!-- id:i6u18c3 -->
  - RefModel protocol (ident + read); stub transports for anthropic/openai/google/local_torch — the openai adapter takes a configurable base URL so OpenAI-compatible local servers (LM Studio) are covered without a dedicated adapter
  - One active adapter at a time, all four at verified parity: stub suite covers every adapter equally; per-cycle one-image health probe of every enabled adapter recorded in the verdict; active-adapter switch = config edit, cached readings and per-ident series survive
  - Per-adapter mask contract (mask vs polygon/box vs none, recorded); cache keyed (image sha256, ident); per-ident comparison series with cross-ident pooling refused; recovered image text quarantined as data fields
  - Stream: 3
  - Requirements: [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7)

- [x] 22. Implement the refmodel package <!-- id:i6u18c4 -->
  - tools/field_loop/refmodel/ with refmodel.json at <repo-parent>/medata-corpus/ holding the enabled set (each entry pinned to a model/version) and naming the single active adapter; all four adapters maintained at working parity for seamless handover per Decision 16 (amended)
  - Blocked-by: i6u18c3 (Write failing pytest for the reference-model adapters)
  - Stream: 3
  - Requirements: [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7)

- [x] 23. Write failing pytest for field_close guards, commits, and triage <!-- id:i6u18c5 -->
  - Six ordered guards: cause-specific evidence, 5-captures/2-clusters floor, bounds + 15% per cycle + 30% lifetime anchored to source values, one-DOF-per-class-per-cycle + column cooldown, weighed-truth veto (synthetic benchmark meal replayed before/after, worsening demotes), make food-db + make test gates; denylist refusal for regressive fix ids; max 5 commits/cycle in a throwaway git repo; git-diff-style proposal patches; verdict artifact contents; triage.md format with quarantined evidence fields and note traceability
  - Stream: 3
  - Requirements: [4.7](requirements.md#4.7), [4.8](requirements.md#4.8), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7), [6.3](requirements.md#6.3), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)

- [x] 24. Implement field_close.py and loop_config.json <!-- id:i6u18c6 -->
  - Sole committer; dedicated worktree, dirty-tree refusal, [ml-feedback-loop] subjects, Co-Authored-By + Loop-Fix-Id trailers, one commit per fix pairing overlay edit with regenerated sqlite artifacts and a before/after table
  - Constants (floors, ceilings, budgets, eval floors, denylist) in tools/field_loop/loop_config.json; make field-close target
  - Blocked-by: i6u18c5 (Write failing pytest for field_close guards, commits, and triage), i6u18bw (Implement _load_overlay in generate.py and the make food-db target), i6u18by (Implement field_pull.py, ingest, and the corpus index)
  - Stream: 3
  - Requirements: [4.8](requirements.md#4.8), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.6](requirements.md#5.6), [5.7](requirements.md#5.7), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.4](requirements.md#7.4)

- [x] 25. Write failing pytest for training-data derivation <!-- id:i6u18c7 -->
  - fld_ stem prefix; contributes train/val only, frozen anchor heldout asserted untouched; mixing cap field max 10% of train recorded in splits.json; per-label provenance JSON (note id, interpreting model ident, self_training flag on predicted masks); evaluation-floor guard blocks derivation that would starve an eval cell; calibration derivation emits .fixture + run_summary.json per the canonical contract
  - Stream: 3
  - Requirements: [8.2](requirements.md#8.2), [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [8.6](requirements.md#8.6)

- [x] 26. Implement derive_dataset.py <!-- id:i6u18c8 -->
  - Emits the prepare_dataset.py layout (<split>/images, <split>/masks, splits.json, co_stats.json) following merge_corpus_foodrec2022.py; marks consumed captures training_used in the index; writes recommended retrain/recalibration commands into the cycle verdict (launch stays human-gated)
  - Blocked-by: i6u18c7 (Write failing pytest for training-data derivation), i6u18by (Implement field_pull.py, ingest, and the corpus index)
  - Stream: 3
  - Requirements: [8.2](requirements.md#8.2), [8.4](requirements.md#8.4), [8.5](requirements.md#8.5), [8.6](requirements.md#8.6)

## Integration and docs

- [x] 27. Build the loop-rehearsal dry-run test and miniature fixtures <!-- id:i6u18c9 -->
  - pytest executing one full cycle with everything external stubbed: committed miniature fixtures (slimmed bundle + two synthetic notes + one synthetic benchmark meal), agent drafts as fixtures, field_close against a throwaway git repo
  - Asserts ingest, diagnose, task generation (terminal task, STOP lines), close (guard chain fires, one weighed-guard demotion, commit cap holds)
  - Blocked-by: i6u18c0 (Implement field_diagnose.py), i6u18c2 (Implement field_report.py), i6u18c4 (Implement the refmodel package), i6u18c6 (Implement field_close.py and loop_config.json), i6u18c8 (Implement derive_dataset.py)
  - Stream: 3
  - Requirements: [3.3](requirements.md#3.3), [4.8](requirements.md#4.8), [5.7](requirements.md#5.7)

- [x] 28. Write the module agent note and Makefile/docs touch-ups <!-- id:i6u18ca -->
  - docs/agent-notes/ml-feedback-loop.md: cycle contract, corpus layout, guard chain, profile mechanics, gotchas; Makefile help text for the new targets; make spell clean
  - Blocked-by: i6u18c9 (Build the loop-rehearsal dry-run test and miniature fixtures)
  - Stream: 3

## Device verification (STOP)

- [ ] 29. STOP: field-profile on-device pass <!-- id:i6u18cb -->
  - Human-gated device checklist: affordance reachable on every screen incl. covers and capture; sheet typed+spoken (and degraded state with speech off); screenshots correct incl. capture-screen composite; notes+screenshots visible in Files; refusal and Records-row linking; manifest cleanup after a real pull; slimming triggers on budget
  - No agent may attempt this task
  - Blocked-by: i6u18bs (Wire meal-link surfaces and the refusal outcome stash), i6u18bt (Add spoken entry via SpeechAnalyzer/SpeechTranscriber), i6u18bu (Implement FieldMaintenance: manifest processing and slimming triggers)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.4](requirements.md#2.4), [3.6](requirements.md#3.6)

- [ ] 30. STOP: product-profile on-device pass <!-- id:i6u18cc -->
  - Build + deploy ProductRelease: strings gate passes, launch log shows profile=product, no debug affordance, no Documents/notes/ created, estimation behaviour identical
  - No agent may attempt this task
  - Blocked-by: i6u18bs (Wire meal-link surfaces and the refusal outcome stash), i6u18bt (Add spoken entry via SpeechAnalyzer/SpeechTranscriber), i6u18bu (Implement FieldMaintenance: manifest processing and slimming triggers)
  - Stream: 2
  - Requirements: [9.1](requirements.md#9.1), [9.2](requirements.md#9.2), [9.3](requirements.md#9.3), [9.4](requirements.md#9.4)

- [ ] 31. STOP: first real feedback cycle end-to-end <!-- id:i6u18cd -->
  - A real field session: captures + notes over at least a day, make field-pull / field-diagnose, an agent phase over the generated cycle file, make field-close; verdict artifact recorded with the alignment report baseline
  - No agent may attempt this task
  - Blocked-by: i6u18c9 (Build the loop-rehearsal dry-run test and miniature fixtures), i6u18cb (STOP: field-profile on-device pass)
  - Stream: 2
  - Requirements: [4.8](requirements.md#4.8), [6.1](requirements.md#6.1), [6.3](requirements.md#6.3), [8.7](requirements.md#8.7)

## Field-test fixes

- [x] 32. Fix the affordance hit region: follow the dragged button <!-- id:i6u18ce -->
  - First device session: one drag parked the window hit region at the home corner forever (.offset is render-only, invisible to onGeometryChange); the persisted offset kept the button dead across relaunches
  - FieldNoteOverlay reports homeFrame.offsetBy(offset), re-reports on every offset change, and clamps a committed park to the window bounds
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1)

- [x] 33. Link capture-screen notes to the most recent attempt and show link state in the sheet <!-- id:i6u18cf -->
  - An attempt can fail before rendering any results or refusal surface; the capture cover now always carries the persistAttemptRecord stash so the note still links (Req 2.6)
  - Sheet context section: linked attempt shows short id + relative time; an unlinked note reads Attempt: none linked — first device session could not tell whether a capture-screen note was tied to an attempt
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.6](requirements.md#2.6)

- [x] 34. field_pull: per-copy progress, size-verified resume, wire timeouts <!-- id:i6u18cg -->
  - A silent multi-gigabyte backlog copy is indistinguishable from a hang (2026-08-27: interrupted twice, three sibling pull dirs, 9+ GB re-copied); one key=value line per wire copy now shows throughput
  - Copies land as .partial then rename; resolve_pull_dir resumes the newest same-day dir without a pull_complete.json marker, skipping files already present at their listed size
  - devicectl calls carry timeouts (300 s listing; 120 s + ~1 s/MB per copy) so a wedged copy fails the file and moves on; failures leave the marker unwritten so the next run retries exactly the misses
  - Stream: 3
  - Requirements: [3.3](requirements.md#3.3), [3.4](requirements.md#3.4)

- [x] 35. field_pull: byte-based progress with ETA, and the DB snapshot made required
  - Progress is bytes, not files: bundles span 2-400 MB. Each copy line carries pct, MB/s and an ETA once three copies have set a rate. Measured 10.6 GB / 100 bundles / 12 min = ~14.5 MB/s.
  - meals.sqlite moved from optional to required (DB_PRIMARY vs DB_SIBLINGS): the first real pull landed 100 bundles with db_integrity=absent and joins_resolved=0 because one silent copy failure scrolled past.
  - Requirements: [3.8](requirements.md#3.8), [3.10](requirements.md#3.10)

- [x] 36. make field-notes: a notes-only pull for feedback on work in flight
  - --notes-only pulls notes + the DB snapshot and skips capture bundles: ~6 s against the device that takes 12 min for a full pull.
  - Separate <date>-notes-<n> dir series so it cannot resume or renumber an interrupted backlog pull; refuses --prune, which would retire an outcome protection before its bundle is ashore.
  - Verified on device 2026-08-27: 3 notes + 152 outcome rows + 23 correction rows ingested, db_integrity=ok.
  - Requirements: [3.9](requirements.md#3.9)

## Triage routing

- [x] 37. Rolling triage ledger: field_triage.py, make field-triage, merge-preserving regeneration
  - Extract the triage writer from field_close into field_triage.py: rolling ledger at cycles_dir.parent/triage.md; merge not rewrite (checked state and routed: details preserved by note-keyed ids task_id(0; triage/<note-id>)); refuse a dirty ledger; field_close refreshes the same file; make field-triage target
  - Requirements: [7.2](requirements.md#7.2)

- [x] 38. First routing pass over the rolling triage ledger
  - Route every unchecked ledger item to one destination per the design's routing contract and check it off with routed: <destination>; <date>
  - Requirements: [7.3](requirements.md#7.3)

# Decision Log: ML Feedback Loop

## Decision 1: Full-spec mode, homed at `specs/estimation/ml-feedback-loop/`

**Date**: 2026-08-26
**Status**: accepted

### Context

The feature spans device UI (a note affordance on every screen), speech input, a new persistent store, the wired pull path, and Mac-side AI tooling that commits fixes. PROCESS.md requires full-spec mode for anything touching the data model, and gives every spec one home domain named for the capability. The working branch is `ml-feedback-loop`.

### Decision

Run the full spec workflow. Home the spec in `estimation/` under the name `ml-feedback-loop`, matching the branch.

### Rationale

The dominating acceptance criterion is closing the estimation gap, which puts the home in `estimation/` even though the note surface is UI. The name is kept aligned with the branch for traceability, accepting that PROCESS.md would prefer a capability-flavoured name.

### Alternatives Considered

- **Smolspec**: Single lightweight document - Rejected: far over the 80-LOC/3-file bar and it adds a data contract.
- **`capture/field-annotations`**: Home the spec on the annotation supply side - Rejected: frames the mechanism, not the outcome; the analysis loop would need a second spec immediately.
- **Rename to `field-annotation-loop`**: Convention-conforming name - Rejected by the developer in favour of branch-name traceability.

### Consequences

**Positive:**
- One spec owns the whole loop, supply side and analysis side.
- Branch, worktree, and spec share a name.

**Negative:**
- The name reads as effort-flavoured against the PROCESS.md §3 naming rule; recorded here so the deviation is deliberate.

---

## Decision 2: One universal note mechanism, two consumers of different rigor

**Date**: 2026-08-26
**Status**: accepted

### Context

The original framing was per-capture annotation. The developer widened it: the note mechanism should capture what is wrong anywhere in the app — UI, records, emoji, wording — with screen context, and asked whether that scope is too broad.

### Decision

Build one capture mechanism (note + screen identifier + screenshot, meal-linked when invoked from a meal surface) and split consumption: meal-linked notes feed the measured estimation loop with auto-applied data fixes; everything else is triaged into structured development items and never machine-patched.

### Rationale

A universal affordance is simpler than a meal-only special case, and the field-friction argument (record it in the moment or lose it) applies app-wide. The scope risk lives in the fixing, not the capturing — so the fix automation is confined to the estimation domain where gaps are measurable, and the rest routes into the existing spec/task workflow.

### Alternatives Considered

- **Meal-only annotation**: Confine notes to capture surfaces - Rejected: the developer explicitly wants app-wide feedback capture to drive UI/records/text development too.
- **One auto-fix loop for everything**: Let agents patch UI from notes - Rejected: UI acceptance is a person looking at a screen (test-gate convention); auto-patching it is unmeasurable and unsafe.

### Consequences

**Positive:**
- One store, one pull, one ingest for all feedback.
- The estimation loop's measurability is not diluted by unmeasurable UI feedback.

**Negative:**
- The spec carries a triage requirement (Req 7) whose output quality depends on note quality.
- Screenshot capture must work on every screen, not just capture surfaces.

---

## Decision 3: Data-level fixes auto-commit to a dedicated loop branch; code changes are proposals

**Date**: 2026-08-26
**Status**: accepted

### Context

The loop must turn diagnosed gaps into change. The estimation path is deterministic code plus bundled data (food DB, mappings, calibration inputs), all baked into the binary — nothing reaches the phone without a rebuild and deploy regardless of who authors the change.

### Decision

The loop auto-commits data-level fixes (class mappings, densities, serving definitions, calibration inputs) to a dedicated loop branch, one commit per fix with lineage to the motivating notes and captures. Code changes are only ever proposed on that branch. The loop never commits to `research`/`main` and never deploys.

### Rationale

Data fixes are bounded, individually revertible, and carry lineage — safe to accumulate unattended. Code changes alter behaviour in ways only review and the on-device gate can judge. Keeping both off `research` preserves the existing human merge gate; keeping deploy manual preserves the build-stamp verification discipline.

### Alternatives Considered

- **Diagnosis reports only**: Human applies everything - Rejected by the developer: too slow for a loop meant to iterate over days of captures.
- **Auto-commit + auto-deploy**: Loop pushes builds to the docked phone - Rejected: collides with the build-stamp/attempt-tag verification workflow and removes the human from a step that flashes hardware.

### Consequences

**Positive:**
- Fast iteration on the safe class of change; every fix is one revertible commit.
- `research` stays human-curated.

**Negative:**
- The loop branch needs periodic human merging or it drifts from `research`.
- "Data-level" needs a precise definition in design so the boundary cannot creep.

---

## Decision 4: Spoken notes survive as transcript only

**Date**: 2026-08-26
**Status**: accepted

### Context

Voice is the lowest-friction entry in the field. The audio clip could be kept for Mac-side re-transcription of mis-heard notes, at ~100 KB per note plus microphone-retention semantics.

### Decision

Transcribe on-device, let the developer edit the transcript before save, discard the audio.

### Rationale

The developer confirms the transcript at save time, so the confirmed text is the authoritative statement; keeping audio adds storage and a second source of truth for marginal recovery value.

### Alternatives Considered

- **Transcript + retained audio**: Re-transcribe on Mac with a better model - Rejected by the developer: the edited transcript is already the confirmed statement.
- **Audio only, Mac-side transcription**: No on-device speech dependency - Rejected: the developer could not verify what was captured in the moment.

### Consequences

**Positive:**
- Smaller notes, no audio lifecycle to manage, single source of truth.

**Negative:**
- A mis-transcription the developer fails to catch at save time is unrecoverable.

---

## Decision 5: Transport is the wired batch pull, run when docked

**Date**: 2026-08-26
**Status**: accepted

### Context

Bundles run ~200 MB each; a multi-day field session is many GB. The app currently has no outbound network path, and the pull convention (`devicectl` over cable into `tmp/device_captures/` / `tmp/device_pulls/`) already exists.

### Decision

Notes accumulate on device for the whole session; the loop ingests via the existing wired pull when the phone is docked. No new network code in the app.

### Rationale

Multi-GB transfers belong on the cable; batching matches how the loop consumes data (corpus passes, not single captures); and adding no network surface keeps the app's privacy/simplicity story intact during the developer phase.

### Alternatives Considered

- **Live push over local network**: Notes and slimmed captures stream to the Mac as they happen - Rejected: new network machinery in the app for a latency win the batch loop does not need.
- **Same-day polling pull**: Mac repeatedly pulls while at home - Rejected: same machinery cost as batch with none of the simplicity; docking is not onerous.

### Consequences

**Positive:**
- Zero new app network surface; reuses a proven pull path.
- The loop always sees whole sessions, which suits corpus-level analysis.

**Negative:**
- Feedback latency is the docking cadence — gaps surface after the session, not during it.
- Device storage must survive the whole session (hence the pull-side pruning criterion, Req 3.5).

---

## Decision 6: Note form is free text plus an optional structured carbohydrate field

**Date**: 2026-08-26
**Status**: accepted

### Context

The note carries what the food is, a human carb estimate, and what the results view should have shown. Fully structured entry costs taps in the field; pure prose forces the Mac side to parse the one number that matters most.

### Decision

One verbatim free-text field (spoken or typed) plus an optional numeric carb-grams field on meal-linked notes. Household measures (spoons, slices, servings) stay in prose, unparsed on device.

### Rationale

The carb number is the single value the alignment metric needs unambiguously, so it gets a field; everything else is context the Mac-side models are good at reading. The developer stated quantity estimates ground better in household measures than exact grams, so prose keeps that fidelity.

### Alternatives Considered

- **Pure free text**: One field, AI parses everything - Rejected: makes the core metric depend on parsing quality.
- **Fully structured entry**: Separate fields for identity, quantity, expected view - Rejected: too many taps for field use; friction kills logging (the activity-events lesson).

### Consequences

**Positive:**
- The alignment metric reads a number, not a parse.
- Notes stay fast to record.

**Negative:**
- Food identity and household quantities still require Mac-side interpretation before use.

---

## Decision 7: Convergence is directional, on selection error and mask consistency; stated values are never ground truth

**Date**: 2026-08-26
**Status**: accepted

### Context

Notes are human estimates, deliberately not gravimetric truth (`benchmark_meals` owns that). The developer defined success as less error in food selection, more consistent maskings, and smoother data ingestion — with quantities grounded in household measures rather than exact grams.

### Decision

The loop's target is directional: for foods with repeat annotated captures, class-selection error and mask inconsistency must decrease across iterations, quantity gaps are tracked in stated household-measure terms, regressions are flagged in run verdicts, and reports label all stated values as developer-stated.

### Rationale

A fixed absolute band against non-truth values would manufacture false precision. Directional metrics over repeats are honest about what human estimates can support, and the classification/masking axes are exactly where the developer locates the pain.

### Alternatives Considered

- **Absolute accuracy band** (e.g. ±10 g of stated): Simple pass/fail - Rejected: treats human estimates as truth, which the developer explicitly declined.
- **Verdict-only, no metrics**: Human judges the trend - Rejected: the trend across days of captures is exactly what unaided judgement gets wrong.

### Consequences

**Positive:**
- Honest metrics; no false claim of gravimetric accuracy.
- Per-build-stamp segmentation ties movement to specific deployed changes.

**Negative:**
- Directional targets never declare "done"; closure needs a separate judgement call.
- Mask-consistency needs a concrete definition in design before it is measurable.

---

## Decision 8: Every field capture accretes into a learning corpus; the loop's end state is its own redundancy

**Date**: 2026-08-26
**Status**: accepted

### Context

Mid-requirements, the developer reframed the goal: the mechanism should eventually not be necessary at all. Every capture, wrong or right, annotated or not, is real-world data the models should learn from — the agents should structure data pipelines feeding model, math, and app refinement toward accurate real-world carb and macro content, which is why Medata exists.

### Decision

All pulled captures join a persistent Mac-side corpus (Req 8). Where signal exists (notes, corrections, relabels, stated quantities), the loop derives training and calibration material in the formats the existing pipelines consume, following the merged-corpus precedent that shipped `ab812dc3aa9d`. Training runs remain human-gated.

### Rationale

The annotated slice is the labelled tip of a much larger real-world dataset the device is already recording; discarding unannotated captures would waste exactly the distribution shift (real plates, real light, real tables) the public datasets lack. Feeding the existing pipeline formats means no parallel training stack.

### Alternatives Considered

- **Annotated-captures-only corpus**: Smaller, fully labelled - Rejected: forfeits the real-world distribution the developer named as the point; unannotated captures still carry masks, depth, and outcomes.
- **Separate field-data training stack**: New pipeline tuned to phone captures - Rejected: the merged-corpus path already exists and is proven; a second stack doubles maintenance.

### Consequences

**Positive:**
- Real-world data compounds across sessions; every capture has value even without a note.
- Reuses proven dataset-bridge machinery.

**Negative:**
- Corpus storage grows without bound at ~200 MB per capture until slimming or pruning policy is designed.
- Deriving labels from prose notes introduces AI interpretation into training data provenance, which design must make auditable.

---

## Decision 9: Auto-apply lands only in a loop-owned overlay file, gated by the existing bake and tests, with evidence floors and symmetric drift ceilings

**Date**: 2026-08-26
**Status**: accepted (amends Decision 3's scope)

### Context

Review verified that every data surface Decision 3 named — densities, class mappings, servings, β — lives inside `tools/food_db/generate.py` value tables or Swift calibration artifacts, each owned by another pipeline with its own provenance gate: β provenance has no enum value that could represent a loop-authored fix, composition values are licensed CoFID/AFCD transcriptions, and a palette change is a model retrain. A loop edit to any of them is mechanically a code edit and semantically provenance falsification. Review also found no validation gate before auto-commit, and that a loop optimising toward developer-stated values could drift reported carbs unattended on a tool the developer doses insulin from.

### Decision

Auto-applied fixes land only in a new loop-owned overlay file — a provenance-tagged input to the DB generator, distinct from CoFID/AFCD/calibration provenance. Before any auto-commit: DB regeneration with its existing bake gates plus `make test` (both totals) must pass, and values are bounds-checked; failures demote the fix to a proposal. Every auto-applied change needs a stated minimum number of independent supporting captures and respects a per-class cumulative drift ceiling per cycle, applied in both directions; beyond either bound it becomes a proposal. Commits pair the overlay edit with the regenerated artifacts so a revert restores a coherent state. The loop runs in its own worktree, refuses a dirty tree, caps commits per run, and never re-applies a fix a prior verdict flagged as regressive.

### Rationale

The overlay is the only way "auto-applied where safe" survives honestly: it gives loop-authored values a legitimate provenance home instead of forging someone else's, and it makes the auto-apply boundary a file path rather than a judgement call. The drift ceiling is deliberately symmetric, diverging from the reviewer's one-sided rule (carb-reducing changes proposal-only): the repo records under-reads as the harm direction for dosing, but an unattended carb inflation causes over-dosing toward hypoglycaemia, which is acutely dangerous — both directions need the cap, and the evidence floor (echoing the ≥30-meal calibration precedent, exact N set in design) prevents any single misread note from moving a value at all.

### Alternatives Considered

- **Propose-only v0**: No auto-apply until proposals prove reliable - Rejected by the developer: forfeits the fast iteration the loop exists for; the overlay makes auto-apply safe enough to keep.
- **Direct edits to `generate.py` value tables with bounds checks**: No new surface needed - Rejected: provenance falsification; every value would claim a source it no longer has.
- **One-sided cap (reductions proposal-only)**: Reviewer recommendation - Rejected in favour of symmetric caps; both harm directions are real for a dosing tool.

### Consequences

**Positive:**
- The auto-apply boundary is a file path, checkable in CI and in review.
- Every landed value carries loop provenance and per-fix lineage; reverts are coherent.

**Negative:**
- The DB generator gains an overlay input and a provenance value — real scope added to a stable tool.
- Genuinely safe fixes outside the overlay's expressive range still wait for a human.

---

## Decision 10: All field data may be sent to remote models

**Date**: 2026-08-26
**Status**: accepted

### Context

The loop uses Claude and Codex alongside local models. Screenshots can contain health readings (glucose surfaces), and capture imagery is photographs of the developer's home. The app itself makes no network calls, and the spec must not let a future maintainer read "no network in the estimation path" as covering the Mac tooling by accident.

### Decision

Notes, screenshots, and capture imagery may all be sent to remote models from the Mac, under the developer's own accounts.

### Rationale

This is the developer's own data about themselves, in their own accounts, during the developer phase; restricting it would cost analysis capability for no third party protected. Recording the boundary makes the egress deliberate rather than an accident of tooling defaults.

### Alternatives Considered

- **Imagery local-only**: Text may go remote, photos stay local - Rejected: the vision-model comparison (Req 4.6) is central to the headroom question.
- **Fully local analysis**: Remote models see only code and statistics - Rejected: forfeits Claude/Codex on exactly the interpretation work they are best at.

### Consequences

**Positive:**
- Full-capability analysis; the boundary is recorded, not accidental.

**Negative:**
- This decision must be revisited before any second user's data ever enters the loop.

---

## Decision 11: Measurement integrity — replay-delta attribution floor, structural repeat grouping, train/eval exclusion, versioned reference model

**Date**: 2026-08-26
**Status**: accepted

### Context

Review found three ways the loop could report convergence while degrading the estimator: replay is measurably not bit-exact with the device (a recorded −4.6 % delta on the same attempt), so diagnosing against replay silently misattributes a several-percent artefact to data causes; "same stated food" grouping via LLM interpretation makes metric membership drift with the interpreting model; and captures used as training material would also be evaluation material, making improvement self-fulfilling after one retrain.

### Decision

The loop records the per-capture device-vs-replay delta and never attributes a gap component smaller than it to a data cause (Req 4.3). Repeat groups are defined structurally as same-scene timestamp clusters, with cross-day stated-food grouping reported separately as interpretation-dependent (Req 6.1). Trained-on captures are excluded from the alignment evaluation set, split recorded per pull (Req 6.4). The Mac reference model is designated and versioned, held fixed within a comparison series (Req 4.6). Trend segmentation keys on (build stamp, model version, DB content hash) (Req 6.2).

### Rationale

Each rule closes a path by which the metric could move without the estimator improving. Structural grouping exploits data the developer's multi-attempt habit already produces for free; the exclusion rule is the standard train/test discipline applied to a corpus that is both label source and benchmark.

### Alternatives Considered

- **Diagnose against replay alone**: Simpler, one code path - Rejected: bakes a known −4.6 % artefact into every diagnosis.
- **LLM-grouped repeats as the primary metric**: Matches human intuition of "same food" - Rejected as primary: metric membership would change when the interpreting model changes; kept as a secondary, labelled view.
- **"Best-available" reference model**: Always use the strongest current model - Rejected: untestable and drifts monthly; designation with recorded identity keeps comparisons interpretable.

### Consequences

**Positive:**
- Trends are attributable to deployed changes, not to tooling drift or contamination.

**Negative:**
- The annotated evaluation set shrinks as captures graduate into training data, so evaluation needs a continuing stream of fresh annotated captures.

---

## Decision 12: Field and product build profiles split at compile time

**Date**: 2026-08-26
**Status**: accepted

### Context

Mid-requirements, the developer stated that once the loop closes, the feedback machinery must not ship: a closed loop otherwise means shipping a debug/iterative build as the final product. The repo already has the precedent: `HARNESS_ENABLED` gates harness code out of the shipping binary at compile time, and shipped code never depends on it.

### Decision

Two build profiles (Req 9): a field profile carrying the note affordance, note store, screenshot capture, and loop machinery; and a product profile that excludes them at compile time. Estimation behaviour is identical across profiles, and every build declares its profile in the launch log beside the build stamp.

### Rationale

Compile-time exclusion is the standard for this development profile — a runtime flag ships the machinery and trusts a boolean; a compile-time gate ships a binary that cannot collect. The identical-estimation constraint preserves the field build's evidential value: what was measured in the field is what the product does.

### Alternatives Considered

- **Runtime developer flag**: One binary, machinery toggled off - Rejected: the machinery (and its attack/bug surface) still ships; contradicts the `HARNESS_ENABLED` precedent.
- **Separate app target**: A distinct field app - Rejected: two targets drift; a profile on one target keeps one code base with one estimation path.

### Consequences

**Positive:**
- The product can never collect notes or screenshots, by construction.
- Profile is verifiable from device logs, matching the build-stamp discipline.

**Negative:**
- Two profiles to build and occasionally to test; profile-conditional code needs the same discipline `HARNESS_ENABLED` already demands.

---

## Decision 13: Estimation-path Mac/model calls — deferred, evidence-gated, determinism-barred

**Date**: 2026-08-26
**Status**: proposed (deliberately deferred; not to be accepted inside this spec)

### Context

The repo's hard invariant keeps the estimation path free of LLMs, network calls, and Mac dependency. During requirements approval the developer stated this clause CAN eventually be relaxed — estimation calling a Mac or a discretely running model — because the product goal is a well-founded estimation suite that yields the same estimate twice from the same input, and a structured, reproducible model call could satisfy that. The developer was explicit that this is not an automatic decision: it should be considered only as more data and erroneous readings accumulate from real captures, in both LiDAR and two-view modes, with and without the card.

### Decision

The invariant stands unchanged for this spec. The relaxation is recorded here as a deferred decision with its gate defined: reconsideration requires a corpus of mode-segmented erroneous-reading evidence (Req 6.6), and any reintroduced model call must be deterministic — the same input data yields the same estimate on every run. Nothing in this spec's deliverables may depend on the relaxation happening.

### Rationale

Recording the deferral keeps a future session from either treating the invariant as unquestionable dogma or relaxing it casually. Defining the gate now — evidence volume across both capture modes, determinism as the bar — means the loop's own reports (capture-mode segmentation, cause classifications) are building the decision's evidence base as a side effect of normal operation.

### Alternatives Considered

- **Relax the invariant now**: Let estimation call Mac-hosted models where reachable - Rejected: the developer said explicitly this is not automatic; today's evidence base is a handful of field sessions on one device.
- **Leave it unrecorded**: Revisit if it ever comes up - Rejected: an unrecorded intention is lost to future sessions, and the loop would not know to segment its evidence by capture mode.

### Consequences

**Positive:**
- The loop accumulates exactly the evidence the future decision needs without extra work.
- Determinism is fixed as the bar before any candidate architecture is debated.

**Negative:**
- A deferred decision invites scope pressure; every future session must treat the invariant as binding until this decision is separately taken up and accepted.

---

## Decision 14: Single-copy corpus, and the phone is cleaned after verified pulls via a pushed manifest

**Date**: 2026-08-26
**Status**: accepted

### Context

Req 8.3 demanded either a second copy or recorded acceptance of single-copy risk before device bundles may be pruned. The developer chose acceptance, and added that pulled notes and records should be removed from the phone (or otherwise managed) to avoid duplication and device-storage bloat. `devicectl` has no remote-delete command, so pruning cannot happen from the Mac directly.

### Decision

The corpus lives single-copy in `medata-corpus/`, a sibling directory of the repo clone (concretely `~/repos/medata-corpus/`, resolved from the main checkout root so all worktrees share it), on the internal SSD; the risk acceptance is recorded here and printed in every pull summary. Device cleanup is app-side: the pull tool pushes a `pulled_manifest.json` (stems, note ids, verified SHA-256s) to `Documents/`; at next field-profile launch, `FieldMaintenance` deletes listed files whose hashes still match and then deletes the manifest.

### Rationale

The developer owns the trade-off and the data is theirs alone; a backup mandate they did not ask for adds friction without a stakeholder. Hash-gated app-side deletion is the only mechanism the tooling supports, and it can never delete a file the Mac does not verifiably hold.

### Alternatives Considered

- **Time Machine condition**: Pruning gated on verified backup coverage - Rejected by the developer in favour of recorded acceptance.
- **Files-app manual deletion**: Developer deletes by hand - Rejected: exactly the friction this feature exists to remove, and error-prone against hundreds of bundles.

### Consequences

**Positive:**
- Phone storage is managed automatically; the corpus is the single source of truth.

**Negative:**
- A corpus disk failure loses irreplaceable field data; accepted and kept visible in run summaries.

---

## Decision 15: The loop defines an engine-agnostic cycle contract; the deterministic core decides fireability

**Date**: 2026-08-26 (amended 2026-08-26: the repo stays ignorant of any particular agent runner)

**Status**: accepted

### Context

The interpretation/fix phase is executed by AI agent sessions, but external orchestrators are build tooling, not architecture — this repository must know only its own code and artifacts, so the design cannot name or depend on any runner. Independently, an autonomous runner over a task ledger fails to terminate when the ledger holds tasks it can never fire (work gated on device data or a human), because "contains an unchecked task" reads as "there is work to do".

### Decision

The repo defines a cycle contract and nothing else: `field_diagnose.py` generates a cycle-scoped rune task file containing only tasks fireable from data already in the corpus, ending in a terminal close-the-cycle task, with unfireable work emitted as STOP lines rather than tasks; agent sessions — however launched — write drafts and per-task results into the cycle directory; `field_close.py` closes the cycle as the sole committer under the commit cap (Req 5.7). How sessions are launched is outside the repo.

### Rationale

Fireability judged by the deterministic generator, plus a terminal task, makes any run over the file terminate by construction — the property holds for every runner because it lives in the artifact, not the runner. Keeping the runner out of the design keeps the repo portable across tooling and honest about its boundaries.

### Alternatives Considered

- **Name a specific orchestrator in the design**: Concrete launch instructions - Rejected: couples the spec to external tooling the repo must stay ignorant of.
- **Commit a driver script shelling to `claude -p`/`codex exec`**: One unattended command in-repo - Rejected: first-of-its-kind machinery duplicating what any external runner already provides.

### Consequences

**Positive:**
- Runner-independent: the cycle file and cycle directory are a complete interface any agent tooling can execute.
- Termination is a property of the generated artifact, testable in the dry-run rehearsal.

**Negative:**
- The contract must be self-sufficient — a runner gets no repo-side help beyond the cycle file and directory conventions.

---

## Decision 16: One active reference adapter, four maintained at verified parity for seamless handover

**Date**: 2026-08-26 (amended same day, twice: first to remove the single-designation framing, then to settle the meaning — one adapter runs at a time, but all must be equally enabled so another can pick up seamlessly when it stops)

**Status**: accepted

### Context

Req 4.6 needs versioned reference readings. The developer directed that the interface stay open to local models (torch/MPS, local OpenAI-compatible servers) and all of Anthropic's competitors — the app is strictly not dependent on any one ML provider, model, or structure — and clarified on review: one adapter is active at a time, but limiting *capability* to a single designated model is not good enough; every adapter must be equally ready so that one can stop and another can seamlessly take over, given the right agentic setup.

### Decision

`tools/field_loop/refmodel/` defines a small adapter protocol (`ident` + `read(image) -> RefReading`); adapters for `anthropic`, `openai` (configurable base URL, covering OpenAI-compatible local servers such as LM Studio), `google`, and `local_torch`. `refmodel.json` holds the enabled set (each entry pinning its model/version) and names the single active adapter. Parity is verified, not assumed: the stub test suite covers every adapter equally, and each cycle health-probes every enabled adapter with one image, recording the result in the verdict, so a broken standby is found before it is needed. Readings store their `ident`; each ident forms its own comparison series; a handover is a config edit that starts a new series and loses no cached evidence. The local-runtime evaluation ("have we overestimated the iPhone") is a spike task with a recorded verdict, run through the `openai` adapter against a local server or `local_torch`.

### Rationale

Provider independence is a stated project property, and a dormant, untested standby is not independence — the per-cycle probe is what turns "equally enabled" from a claim into a measurement, at the cost of one image per adapter per cycle. Running one adapter at a time keeps read costs at one call per cluster representative while the per-ident series pinning keeps Req 6.2 trends interpretable across handovers.

### Alternatives Considered

- **Hard-wire Claude vision**: Least code - Rejected: contradicts the stated provider independence.
- **Local-only reference**: No egress - Rejected as the start: weaker food knowledge; remains available through the same adapter.
- **Dedicated ollama adapter**: A fifth adapter for the ollama runtime - Descoped 2026-08-26: LM Studio's OpenAI-compatible endpoint reaches local models through the `openai` adapter's base URL, so a separate adapter adds surface without capability.

### Consequences

**Positive:**
- Switching or re-pinning the active reference model is a config change with lineage intact and no lost evidence.
- A broken standby surfaces as a failed health probe in the next cycle verdict rather than at the moment it was needed.

**Negative:**
- Four adapters to keep genuinely working, and the probe needs credentials/servers for every enabled adapter each cycle.
- The active-adapter series restarts on every handover, so long uninterrupted series require not switching casually.

---

## Decision 17: Notes are files in the App layer; MedataCore stays profile-neutral; field is the default profile

**Date**: 2026-08-26
**Status**: accepted

### Context

Req 3.1 demands deletion-exempt persistence; Req 9 demands compile-time exclusion from product builds. A `meals.sqlite` table would need exemption edits in every delete path and a `FIELD_LOOP` define inside the SwiftPM package, whose defines are configuration-static (the `deploy-release-stub` script has to edit `Package.swift` in place to vary one).

### Decision

One JSON + one PNG per note in `Documents/notes/` (the `CaptureBundleRecorder` pattern), written by `FIELD_LOOP`-gated App-layer code. MedataCore's only change is neutral: schema v11 adds `protected_outcomes`, and the outcome eviction excludes protected ids (Req 3.2). `FIELD_LOOP` is set in Debug and Release pbxproj configs (field is the daily default, matching the always-on recorder convention); the product profile is a Makefile target overriding `SWIFT_ACTIVE_COMPILATION_CONDITIONS` without it.

### Rationale

Files-in-Documents gets deletion exemption, Files-app visibility, wired pull, and pull-side dedup for free, with no migration and no package define. Field-as-default keeps every daily build capable; the product profile exists as an explicit target rather than a fragile default flip mid-development.

### Alternatives Considered

- **`debug_notes` table in meals.sqlite**: Transactional joins - Rejected: needs exemption maintenance across five delete paths and a package-level profile define.
- **Product as the pbxproj default, field via override**: Safer shipping posture - Rejected for the developer phase: a plain Xcode build would silently lose the machinery; revisit at release, when the default should flip.

### Consequences

**Positive:**
- Zero migration for notes; profile machinery touches two Makefile targets and one pbxproj setting.

**Negative:**
- Note↔outcome joins are cross-store (files vs SQLite), resolved at ingest rather than by the database.
- The default-flip at release is a deliberate outstanding step, recorded here so it is not forgotten.

---

## Decision 18: Auto-apply hardening — weighed-truth veto, lifetime bounds, β invalidation, cause-specific evidence

**Date**: 2026-08-26
**Status**: accepted (amends Decision 9)

### Context

Peer review found three blockers in the fix-application design as first written. First, `bake()` applies calibration last, so an overlay density change would ship under a β fitted against the old density — the loop would silently corrupt the one artifact derived from weighed truth. Second, the 15 % per-cycle drift ceiling is a rate limiter, not a bound: 1.15¹⁰ ≈ 4× over ten cycles, on a dosing tool. Third, the loop's only optimisation target was developer-stated values, which Req 6.5 itself says are not truth — label-bias amplification with a clinical direction, while the repo's actual weighed truth (`benchmark_meals`) appeared nowhere in the loop. Reviewers also showed cross-column oscillation is invisible to a `fix_id` denylist, that an underdetermined cause lets any of density/scale/mask/class absorb the same delta, and that regression judged on the derivation corpus is circular.

### Decision

Six ordered guards in `field_close.py`, all in code: cause-specific evidence (else proposal); the ≥ 5-captures/≥ 2-clusters floor; per-cycle 15 % ceiling **plus a lifetime absolute bound anchored to the CoFID/AFCD source value (default 30 % total)**; one degree of freedom per class per cycle with a touched-column cooldown; a weighed-truth veto — `benchmark_meals` captures touching a fix's classes are replayed before/after, any worsening demotes the fix; and the build gates. The overlay applies to in-memory rows before INSERT and before calibration, and any class whose density or composition it touches has its β invalidated to `uncalibrated_overlay_base` until refit. The overlay file is read by default from a fixed committed path, with a fail-closed inverse guard (prior DB carries `LOOP_OVERLAY` provenance but no overlay present ⇒ abort). Regression judgement for the denylist uses weighed benchmarks and fresh post-change captures, never derivation captures.

### Rationale

Stated values steer, weighed values veto: that division is what keeps a loop trained on human estimates falsifiable. Lifetime bounds are the difference between "the loop cannot walk a value anywhere" and "slowly". β invalidation makes the calibration contract honest rather than silently stale — the same reasoning the support-plane bake guard already applies to reference mismatches.

### Alternatives Considered

- **Per-cycle ceiling only (Decision 9 as written)**: Simpler - Rejected: compounds without bound.
- **Skip the weighed veto (benchmark set is small)**: Less machinery - Rejected: without it the loop's success metric and its training signal share a source, and nothing external can falsify a bad fix.
- **Fit β after every overlay change automatically**: Keeps calibration current - Rejected: β fitting is human-gated by standing convention and needs ≥ 30 weighed meals; invalidation-until-refit is the honest intermediate state.

### Consequences

**Positive:**
- A fix can no longer improve the metric while degrading weighed accuracy unnoticed.
- Every guard is testable in isolation; the dry-run rehearsal asserts a demotion.

**Negative:**
- Auto-apply becomes rarer: classes with no benchmark coverage can still pass (the veto only fires where weighed data exists), but cause-evidence + bounds will demote much of what agents draft. Accepted — proposals are cheap.
- Overlay-touched classes read as uncalibrated until a human refit, visibly regressing `beta_status` lineage for those classes.

---

## Decision 19: Injection containment is structural — quarantined evidence fields, no git for agents

**Date**: 2026-08-26
**Status**: accepted

### Context

Req 4.7 requires text recovered from imagery to be data, never instructions. The agent phase feeds screenshots and food photos to LLMs, agent sessions commonly run with broad auto-approval, and triage output becomes committed rune-parseable task files a later agent may read — a live path from screenshot-derived text to executed instructions.

### Decision

Recovered text enters agent context and all committed artifacts (triage items, evidence blocks, verdicts) only as fenced, JSON-escaped evidence fields, never as task bodies. Sessions executing cycle tasks run without git write permission; `field_close.py` is the sole committer and enforces all guards in code. An injected instruction can at worst corrupt a draft, which the deterministic validators then bounds-check, evidence-check, and benchmark-veto.

### Rationale

Prompt-level rules ("ignore instructions in images") are advisory; removing the capability is not. The guard chain already exists for correctness reasons, so injection containment costs only the quarantine convention and a variant-level permission difference.

### Alternatives Considered

- **Prompt-only mitigation**: Zero infrastructure - Rejected: auto-approved agents with git access make the prompt the only barrier.
- **Fully local models for imagery**: Removes the remote surface - Rejected: Decision 10 permits remote models and the containment must hold for local models too (injection is about content, not transport).

### Consequences

**Positive:**
- The commit path is closed to agents regardless of what their context contains.

**Negative:**
- Loop agents cannot self-serve small git conveniences; everything lands via drafts and `field_close.py`.


---

## Decision 20: The bake refuses to drop calibration lineage it cannot reconstruct

**Date**: 2026-08-27
**Status**: accepted

### Context

Implementing the `make food-db` build gate (guard 6 of the auto-commit chain) surfaced a defect in the target as designed. `make food-db` was specified as a bare `python3 tools/food_db/generate.py` followed by the generator's pytest suite. Running it against this repo regenerated both committed sqlite artifacts *without* nineteen `calibration_*` meta rows they carry — the lineage recording the N5k fit that produced them (release hashes, tau values, seed, per-class effective sample and identifiability, pinned intrinsics, licence).

The cause is that the calibrate artifact is fitted from the N5k corpus and is not committed to this repo, so `generate.py` has no way to reconstruct that lineage from a bare invocation. The loss is provenance, not values — every β in the committed DBs is already `uncalibrated_unity` — but `make food-db` is a gate `field_close.py` runs unattended, and its output is paired into an auto-commit. A silent provenance strip would land in a commit nobody read, which is exactly the failure mode the overlay's own fail-closed inverse guard exists to prevent for the other unreconstructable input.

### Decision

`generate.py` aborts when the prior database carries `calibration_*` meta and no calibration artifact was named, with the message naming the override. `make food-db` takes `CALIBRATION=<artifact>` and passes it through as `--calibration-json`. The overlay and the calibration therefore have the same fail-closed shape: an input the bake cannot reconstruct, once applied, must be supplied again or the bake refuses.

### Rationale

The bake's established contract is abort-before-write on any condition that would ship a database making a claim it cannot support — the palette lock, the serving-coverage lock, the support-plane-reference guard, and the overlay inverse guard all take this form. Dropping lineage is the same class of harm one level down: the artifact stops recording where its numbers came from, and nothing in the file says so.

Failing closed also fails in the safe direction for the loop. With no artifact configured, guard 6 fails and every candidate fix demotes to a proposal — the loop stalls visibly instead of committing lineage-stripped databases cycle after cycle. `field_close.py` (task 24) carries the artifact path in `loop_config.json`, which is where the constant belongs.

### Alternatives Considered

- **Leave `make food-db` as designed (bare invocation)**: The literal reading of the design - Rejected: it regresses the committed artifacts on every run, and the loop would commit that regression paired with each overlay fix.
- **Carry the prior lineage forward automatically**: Read the `calibration_*` rows out of the prior DB and rewrite them - Rejected: it re-derives input state from an output artifact, and it would happily preserve a lineage that no longer describes the rows beside it — the appearance of provenance without the substance.
- **Warn on stderr and bake anyway**: Keeps the target always usable - Rejected: `field_close` runs this gate unattended, where a warning is a line in a log nobody reads before the commit lands.

### Consequences

**Positive:**
- The committed databases cannot silently lose their fit lineage.
- The two unreconstructable bake inputs, overlay and calibration, now behave identically, so there is one rule to remember rather than two exceptions.
- The loop's failure mode is a stalled cycle with proposals, not a stream of lineage-stripping commits.

**Negative:**
- A bare `make food-db` aborts on this repo today; regenerating the databases requires the N5k calibrate artifact in hand.
- Guard 6 cannot pass until `loop_config.json` carries that path, so the first cycles will demote fixes to proposals if it is missing.

### Impact

`tools/food_db/generate.py` (`_prior_db_carries_calibration`, the `bake()` guard), the `food-db` Makefile target, and `field_close.py`'s guard-6 configuration in task 24.

---

## Decision 21: Adopt the orbit-impl-1 variant after the first field session

**Date**: 2026-08-27
**Status**: accepted

### Context

The on-device capture layer and field-loop tooling were built as two parallel orbit variants and both were taken through a first real device session: affordance interaction, note capture from the capture screen, and a first `make field-pull` against a three-week capture backlog. Both variants initially shipped an inert or drag-breakable affordance (each for a different mechanism-level reason) and both were fixed before the session completed; the session then differentiated them on note/context UI quality and pull tooling behaviour.

### Decision

Adopt the orbit-impl-1 variant (`orbit-impl-1/ml-feedback-loop`) as the ml-feedback-loop implementation. Field-session fixes land on this branch; the impl-2 variant is retired.

### Rationale

- The note sheet and its context section (screen id, meal/attempt link, frozen estimate, screenshot-failure reason) read clearly on device — the deciding factor for a surface whose whole purpose is fast, unambiguous field annotation.
- Impl-1's `field_pull.py` worked against the real device: it parses the `devicectl info files` `--json-output` envelope structurally, so the pull enumerated and copied the backlog.
- Its remaining pull defect (a silent, restart-from-zero multi-gigabyte copy that read as a hang) was behavioural, not structural, and is fixed on the branch: per-copy progress lines, partial-then-rename copies, size-verified resume via a `pull_complete.json` marker, per-call timeouts.

### Alternatives Considered

- **orbit-impl-2 variant**: Cleaner single-slot context model and an application-delegate window install - Rejected: its `field_pull.py` parsed the human-readable `devicectl` listing instead of `--json-output`, matched no files, copied nothing, and aborted on the missing `meals.sqlite` snapshot (observed: an empty `2026-08-27-1` pull dir); its passthrough window gated touches by view identity, which cannot work against a single SwiftUI hosting view; its note/context UI read worse on device.
- **Merge impl-2's pieces into impl-1**: Cherry-pick its context model, screenshot compositor, or bake gate - Rejected on each: impl-1's stack-based `FieldNoteContext` is strictly more robust (top-of-stack read at save time survives push/pop ordering); impl-2's screenshot composites an `ImageRenderer` re-render of chrome values the capture view must register with it, where impl-1's `CALayer.render(in:)` over `ARView.snapshot` captures the real layer tree with no coupling; and impl-2's `make food-db` hardcodes the calibration artifact path where impl-1 fails closed on a missing `CALIBRATION=`. A full file-level comparison of the two branches found impl-1 a superset everywhere except two module-note cross-references (`estimation-diagnostics.md` for the slimmer, `n5k-calibration-harness.md` for `diagnose`), which were harvested into the merge — a reader changing the pipeline or the harness reads those notes, not the feature note.

### Consequences

**Positive:**
- One branch to verify: the STOP device-checklist tasks (29-31) run once, on the adopted implementation.
- The field-session lessons (hit-region reporting, attempt-link visibility, observable resumable pulls) are recorded as requirements (2.6), design contracts, and completed tasks on the surviving branch.

**Negative:**
- Impl-2's rehearsal-tested tooling (its own pull/ingest/close suite) is discarded rather than salvaged; any latent quality in it is lost. Its sqlite-based rehearsal fixtures are discarded with it — impl-1 rehearses from JSON, so the committed-binary-fixture exemption impl-2 added to `.gitignore` is not carried over.
- The retired branch still holds the only copy of its implementation until deleted; anyone reading both variants' shared corpus should know pull dirs named `2026-08-27-*` (dashed) are impl-2 debris.

---

## Decision 22: A notes-only pull, and the events database made required

**Date**: 2026-08-27
**Status**: accepted

### Context

The first real pull established the cost of the wired path with measurements rather than estimates: 10.6 GB across 100 capture bundles in 12 minutes, ~14.5 MB/s, one `devicectl copy from` per file. That cost is inherent — a two-view success bundle is ~390 MB and even a refusal can reach ~200 MB — so any pull that carries bundles is minutes-to-hours, and even a two-day session is several gigabytes. Meanwhile a field note is a few hundred bytes of JSON plus a ~370 KB screenshot.

The same pull exposed a second problem. `meals.sqlite` was grouped with its WAL siblings as an optional file, on the reasoning that a missing sibling is ordinary. Its copy failed for a transient reason, the single failure line scrolled past under ten gigabytes of copy output, and the pull declared success having landed 100 bundles and 3 notes with `db_integrity=absent`, `outcomes=0` and `joins_resolved=0` — every note unjoined, because the outcome rows a link resolves through were never ashore.

Both matter beyond this feature: the note affordance is a window over every screen in any FIELD_LOOP build, so it is the fastest feedback channel available to work in flight on other branches — but only if reading the notes back does not mean waiting for the capture backlog.

### Decision

Add `--notes-only` (`make field-notes`): pull the notes and the events-database snapshot, leave capture bundles on the device. Give it its own `<UTC-date>-notes-<n>` pull-directory series and refuse `--prune` under it. Separately, split the database group — `meals.sqlite` is required and its WAL siblings stay optional — so a failed database copy fails the pull and leaves it resumable.

### Rationale

- Notes-only measured at ~6 seconds against the device that takes 12 minutes for a full pull. That is the difference between a feedback channel usable during a work session and one usable at the end of a day.
- An unjoined note is not a lost note: `_resolve_joins` re-runs over every note in the corpus on each ingest, so a note pulled ahead of its bundle joins when the bundle arrives. Deferring bundles costs nothing permanent.
- The separate directory series is what keeps the two pull kinds from interfering — resume looks for the newest same-day dir of its own kind, so a quick notes pull can neither be mistaken for an interrupted backlog pull nor renumber it.
- Refusing `--prune` under notes-only follows the same reasoning as the manifest handshake: retiring an outcome's protection before its bundle is verified ashore would let the device evict the row the note joins through.
- Required-versus-optional should track what the corpus needs, not what is usually present. Without the database no note resolves, which makes it the one file whose absence must stop the pull declaring completion.

### Alternatives Considered

- **Rely on device-side slimming to make full pulls fast**: Drop the probability tensors before the pull so every bundle is smaller - Rejected as a substitute: slimming is already the mitigation for the backlog and remains valuable, but a slimmed bundle is still tens of megabytes against a note's kilobytes, so a full pull stays minutes-scale. The two are complementary, not alternatives.
- **A separate notes-only tool**: A small script that copies `Documents/notes` and stops - Rejected: it would duplicate the corpus ingest, index, and join logic, and the join is the whole point — a note outside the corpus index cannot resolve to its capture.
- **Keep the database optional and rely on the ingest summary**: `db_integrity=absent` is already printed - Rejected by evidence: it was printed, and it scrolled past under 10 GB of copy lines. A condition that invalidates the whole pull must fail it, not annotate it.

### Consequences

**Positive:**
- Feedback on work in flight — on any branch carrying FIELD_LOOP, on any screen, capture-related or not — is readable in seconds.
- A pull can no longer report success while having joined nothing; the failure is named on the line that fails and the directory stays resumable.
- The pull states the size of the job before it starts and its progress in bytes, percent, throughput and ETA, so its duration is legible instead of being read as a hang.

**Negative:**
- Notes pulled ahead of their bundles sit unjoined in the corpus until a later full pull, so a report run between the two understates joins.
- Two pull-directory series make the corpus layout slightly less uniform: `pulls/` now holds both `<date>-<n>` and `<date>-notes-<n>` directories.
- Making the database required means a device whose database genuinely cannot be copied blocks a pull that would otherwise land its bundles — the resume path makes this recoverable, but it is a stop rather than a warning.

---

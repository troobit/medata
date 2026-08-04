# MeData roadmap — MVP close-out and the accuracy feedback loop

> **Audience:** the developer sequencing the remaining MVP work.
> **Date:** 2026-08-04. **Branch:** `research`.
> **Scope:** what is left before MVP, ordered quickest-win-first, plus the standardised
> capture → truth → error loop that lets accuracy improve iteratively *after* MVP ships.
> **Companion docs:** [`mvp-unblock-runbook.md`](mvp-unblock-runbook.md) is the operational
> how-to for the device gate; [`agent-notes/mvp-gap-analysis.md`](agent-notes/mvp-gap-analysis.md)
> is the 2026-06-28 subsystem audit. This file is the *order of work*, not a replacement for either.

---

## 1. Where we actually are

**The original MVP blocker is gone.** The gap analysis verdict — "there is no trained CoreML
segmenter" — no longer holds. A model is bundled and promoted (`coreml_ab812dc3aa9d`, 36 channels,
palette v2, myfoodrepo-bridge Decision 27); export gates passed at 22,169,442 B with oracle argmax
parity 0.9999. Runbook steps 0–5 are complete; **only step 6, the on-device verification, is
outstanding.**

**And step 6 is closer than the ledger suggests.** `myfoodrepo-bridge` task 6 is marked `[-]`
partial for a mundane reason: `make deploy-release` **installed** the Release build on the
iPhone 16 Pro, but the launch step failed because the device was locked, so the
`segmenterSource`/`buildStamp` launch-log check never ran. The build is already on the phone.
Unlock it, open MeData, run `make logs-device`, confirm `segmenterSource=coreml_ab812dc3aa9d`
with a matching stamp — that closes task 6 and unblocks tasks 7 and 8, which are *blocked-by* it
and which together are the MVP gate.

**What is left is overwhelmingly not code.** Across the whole spec set, eleven specs sit at
*exactly one* remaining task, and in almost every case that task is a human holding a phone.
The agent-actionable coding backlog outside the accuracy loop is four items, none of them
MVP-blocking.

**The MVP gate is two checkboxes.** `specs/estimation/model-production/requirements.md` Req 6.3
defines it, and `prerequisites.md` §"On-Device Verification (Stage 7)" carries the two unticked
boxes: Apple Neural Engine residency, and a real on-device capture run. They are duplicated as
live rune tasks `myfoodrepo-bridge` **7** and **8**. Nothing else gates MVP — β_c calibration and
the v1 numeric-accuracy bar are explicitly excluded by Req 6.3.

**The feedback loop is half-built.** `CaptureBundleRecorder` already writes a fully replayable
`PbMealFixture` for *every* estimation attempt, in Release, to `Documents/captures/`, visible in
the Files app. The proto already has `ground_truth_*` fields. The harness already computes MAPE,
MAE and bootstrap CIs. What is missing is the join: nothing back-fills truth into a recorded
bundle, and nothing logs per-capture error over time. That gap is §4.

---

## 2. P0 — One device session closes the MVP gate (no code)

This is the single highest-value action available and it needs no engineering. Eleven specs and
four bugfixes are each waiting on one on-device observation. Done piecemeal that is eleven
deploy cycles; batched against **one Release build** it is an afternoon.

Start with the launch-log check described in §1 — the Release build is already installed, so this
costs minutes and unblocks the gate. If the build stamp is stale, redeploy with
`make deploy-release` and re-check. Then work the list below without redeploying again.

| Order | Spec | Task | What to observe |
|---|---|---|---|
| 0 | `myfoodrepo-bridge` | 6 `[-]` | **Unlock the phone, open MeData, `make logs-device`** — confirm `segmenterSource=coreml_ab812dc3aa9d` + matching `buildStamp`. Closes task 6, unblocks 7 and 8 |
| 1 | `estimation/model-production` | prerequisites Stage 7 | **ANE residency** in Xcode's Core ML performance report — the MVP gate; needs Xcode, not the phone |
| 2 | `myfoodrepo-bridge` | 7, 8 | Point the phone at real meals including a cereal bowl; confirm overlay and carb readings. Tick both ledgers with the model-production prerequisites |
| 3 | `capture-bundle-recorder` | 4 `[-]` | Pull one bundle to the Mac, replay through HarnessCLI — **do this early, §4 depends on the answer** |
| 4 | `estimation-quality` | 7 | Overlay speckle gone, readings stable |
| 5 | `bugfixes/no-food-pixels-on-fruit-plate-mvp` | 8 | Single **and** Double mode (currently BLOCKED behind the next row) |
| 6 | `bugfixes/lidar-plane-fit-degenerate-on-clean-capture` | 8 | Single and Double; unblocks the row above |
| 7 | `bugfixes/lidar-plane-fit-oom-on-device-1920x1440` | 3 | Clean run at 1920×1440 |
| 8 | `bugfixes/closeout-trail-mvp-cleanup` | 6 | Single + Double final pass |
| 9 | `ui/home-router` | 9 | Home-router flow |
| 10 | `ui/shutter-blocked-feedback` | 5 | Tap fires, estimation completes, result view appears |
| 11 | `ui/records-deletion` | 4 | Build, device look, docs |
| 12 | `ui/loading-symbol-animation` | 5 | Loader look |
| 13 | `ui/glucose-lock-widget` | 14 | App Group round-trip, gallery kind, StandBy render, staleness ladder, tap-to-Graph |
| 14 | `data/cgm-connect` | 14 | HealthKit backfill + live reading land as bsl events |
| 15 | `serving-adjust` | 7 | Looks-right pass |
| 16 | `snaqui` | 8 | Portion ergonomics, no portrait truncation |

**Two things to settle before starting.** The four bugfix verifications were written against an
iPhone 13 Pro Max, which is now below the hardware floor (segmenter-foundation Decision 22) — either
re-target them to the iPhone 16 Pro or log why the older device still counts. And
`bugfixes/capture-log-flood-evicts-plane-fit-diagnostics` is only *half* fixed: the diagnostic
blindness is resolved but the matte-table plane-fit refusal is not, and it needs one capture on a
matte surface to root-cause. Add that capture to the session.

**Storage warning.** The recorder writes ~200 MB per attempt (full-resolution FP16 probability
tensor). A sixteen-item session is ~3 GB and a field day is ~6 GB. Clear
`Documents/captures/` between sessions, or land §5 first.

---

## 3. P1 — Make the replay loop reachable and honest — **DONE 2026-08-04**

Landed in `specs/bugfixes/accuracy-harness-scores-untruthed-fixtures-as-zero/`. `make test` green
(XCTest 515 executed / 5 skipped / 0 failures; swift-testing 203 in 25 suites), `make spell` clean.

1. **Zero-truth scoring bug — fixed.** `AccuracyHarness.evaluate` now partitions on
   `isScorable(truth) = truth.isFinite && truth > 0`; only scored meals feed MAPE, MAE and the
   bootstrap CI, and `passesBar` gained a `scoredCount > 0` conjunct. The fix is at the aggregation
   layer, **not** in `pointMAPE`/`pointMAE` — `perClassStats` deliberately calls those helpers
   against a zeros array, so changing their semantics would have silently altered the per-class
   block. See Decision 1.
2. **`make harness-accuracy` added** (`FIXTURES=`, `SHA=`, optional `OUT=`), with help text stating
   that untruthed bundles report UNSCORED and exit non-zero, so that is not misread as a defect in
   the captures.
3. **Per-fixture rows emitted.** `AccuracyReport.rows` / `AccuracyJSON.rows` carry `fixtureID`,
   `capturePath`, truth, prediction, `absoluteErrorG` and `percentError` — the last two **null**
   for an unscored meal rather than zero (Decision 2). The report also now lists the distinct
   `checkpointSHAs` across the loaded fixtures, so a run that mixed models is visible.
4. **Checkpoint-SHA relaxation — dropped, deliberately.** The premise was wrong: on a mismatch
   `FixtureLoader.Error.checkpointMismatch` already carries `got:` and the CLI prints it, so the
   operator learns the fixtures' actual stamp from the first failed run. The friction is one extra
   run, and a relaxed flag would let a run silently mix checkpoints — exactly what the new
   `checkpointSHAs` field exists to expose. Not worth trading a guard for.

Two adjacent defects were found and **not** fixed here, both recorded in the bugfix report:
`perClassStats` reports `mape: 0` and `mae` = mean predicted grams for every class by construction
(same category of defect, pre-existing and documented); and `runAccuracy` still builds
`ClassPalette.v1Standard` while the promoted bundled model is 36-channel palette v2.

---

## 4. P2 — Truth back-fill and the durable error log

This is the "standardise the process and log errors for future" ask. The design principle:
**do not build a second truth-entry surface.** One already exists and works.

### Use the in-app benchmark loop as the truth source

`BenchmarkMeal` / `BenchmarkMealItem` / `BenchmarkFidelity` (`PersistenceStore.swift`) already model
weighed truth, `truthCarbsG` is derived at save from per-item grams, `App/BenchmarkView.swift`
already provides the editor with `.weighed` / `.package` fidelity, and `BenchmarkReport.compute`
already produces MAE, MAPE, within-10 g share and per-meal error rows against
`BenchmarkAnchors` (SNAQ 13.1 g MAE). That is the whole loop, built, on device.

Its one structural limit: truth must be attached **before** the capture, via
`EstimationOutcome.benchmarkMealID`. There is no retroactive "the actual value was X g".

Do **not** repurpose `PbUserCorrection` for this. It means "I am adjusting the portion", carries no
fidelity flag, hangs off `MealRecord` rather than the attempt, and nothing consumes it as truth.
Overloading it would make the error log silently mix corrections with measurements.

### The three pieces to build

1. **A truth manifest** — one CSV, the durable off-device record, replacing the prose table in
   `agent-notes/field-truth-sessions.md`:

   ```
   fixture_id, truth_carbs_g, fidelity, source, note
   ```

   `fixture_id` is the attempt `timestampMs`, which is already the bundle filename stem and already
   joins to `EstimationAttemptRecord`. Populate it by export from the benchmark tables when truth was
   entered in-app, or by hand when it was not. This is the retroactive path the app lacks.

2. **Join at evaluation time, not by rewriting bundles.** Prefer a `--truth-manifest` flag on the
   harness over a subcommand that mutates `ground_truth_*` inside recorded `.fixture` files.
   Non-destructive, keeps the bundle a faithful record of what the device saw, and lets truth be
   corrected without re-recording.

3. **An append-only error log** — the substrate for iterative improvement. One row per fixture per
   run:

   ```
   run_at_ms, fixture_id, outcome, truth_carbs_g, truth_fidelity, predicted_carbs_g,
   abs_error_g, pct_error, segmenter_sha, palette_version, database_edition,
   voxel_edge_mm, beta_source
   ```

   Keying on `(fixture_id, segmenter_sha)` is what makes it useful: re-run the corpus after a model
   swap and you can diff per-capture error across lineages, so "did this checkpoint help?" is a query
   rather than an argument. Aggregates alone cannot answer that.

---

## 5. P3 — Replay fidelity defects that make the numbers lie

Until these are addressed, a replayed error figure is **not** the error the device produced. Fixing
them is what makes §4's log trustworthy; they can follow the first log rows but should not lag far.

1. **The plane-fit path is wrong for handheld captures.** `FixtureRunner.run` routes any fixture with
   a non-empty `estimatorPath` to `fitPlateRegionPlane`, a centre-seeded flood fill written for the
   Nutrition5k overhead rig where "the rig centres the plate under the camera". Device bundles always
   stamp `single_dominant`, so every field capture takes that branch — and handheld captures are not
   centred. Expect skips and `volumeEstimationFailed` on replay.
2. **β is pinned to 1.0 on replay** (`let unityBeta = BetaCorrection(entries: [:], defaultBeta: 1.0)`),
   so a replay measures the uncalibrated chain, not the calibrated β the app actually ships.
3. **Bundles always claim `single_dominant`** even when oblique data is present, so a two-view field
   capture can never be replayed on the `twoViewSfS` branch.

### The corpus-size decision this forces

The recorder stores the full-resolution probability tensor because that is the only way to replay
*exactly* with no harness change — a deliberate trade recorded in the smolspec. It costs ~200 MB per
capture and, more importantly, **freezes the segmentation**: you cannot evaluate a *new* checkpoint
against an *old* capture, which is precisely what iterative improvement needs.

The lever is already named in the smolspec's out-of-scope list: a **promote-to-corpus** step that
keeps the PNG, depth, intrinsics, gravity and truth, and drops the probability tensor, re-segmenting
on replay. That turns a 200 MB one-shot artefact into a few-MB durable regression case and makes
model-over-model comparison possible. It is the pivotal decision for everything in §4, and it wants
a decision-log entry before it is built.

---

## 6. P4 — Deferred, explicitly not MVP

- **`estimation/cross-dataset-calibration`** — 0/23 tasks, status Planned. Substantial and not on the
  critical path.
- **`estimation/segmenter-foundation`** — 18/22. Task 14 (the SegFormer-B0 spike) is the only
  agent-actionable item; tasks 20–22 are device/compute-gated. A model-quality investigation, not an
  MVP gate.
- **`estimation/support-plane-reference`** — stalled at Phase 2 with `requirements-notes.md` marked
  "SCRATCH. Not requirements." It has a real defect behind it (the LiDAR support plane fits the table
  26.1 mm too low) and three open questions needing a requirements interview. Worth doing, after MVP.
- **β_c gravimetric calibration** and the **v1 numeric-accuracy bar** (MAPE < 20 %, MAE ≤ 25 g) —
  deferred past MVP by model-production Decision 3 and Req 6.3. §4's error log is what will eventually
  measure the bar; it does not gate the ship.

---

## 7. Spec hygiene (minutes each)

- `specs/OVERVIEW.md` reports `segmenter-foundation` at 19/22; the ledger is 18/22 since commit
  `bc4b060` un-ticked task 14. Regenerate rather than hand-editing.
- `ui/mass-readout` shipped code (`0c6a6b6`) without a `tasks.md`, which fails the PROCESS §11
  checklist item "`tasks.md` exists in `rune`". Either back-fill the ledger or record why the
  smolspec shipped without one.
- `bugfixes/two-view-carve-no-volume` is **Open** and mis-filed: the root cause is a mis-aimed
  capture, not a carve defect. Re-home it to the capture domain or close it with that finding.
- `nextup.md` still points only at glucose-lock-widget task 14. Repoint it at the §2 device session.

---

## 8. Where this work lives — no new specs required

Per PROCESS §3, an **extension** "refines or grows an existing capability and shares its acceptance
bar. Add a requirement section to that spec; do not spawn a folder." All of the above fits existing
homes:

| Work | Home | Why |
|---|---|---|
| §3.1 zero-truth scoring bug | `specs/bugfixes/` | A correctness defect in shipped harness code |
| §3.2–3.4, §4, §5 | `capture/capture-bundle-recorder` | Same capability — record captures so they replay offline. Truth back-fill was deferred in its own out-of-scope list, not ruled out |
| The accuracy bar the log measures against | `estimation/model-production` | Already owns Req 6.3 and the v1 bar |
| §5 corpus-size trade | `capture/capture-bundle-recorder/decision_log.md` | Revises the smolspec's original full-probs trade |

`capture-bundle-recorder` is a smolspec, and §4 + §5 together exceed the smolspec bar (< 80 LOC,
1–3 files). Growing it into a full spec in place — requirements, design, decision log against the
existing folder — is the correct move and is still an extension, not a new capability.

`estimation/estimation-quality` is **not** the right home despite the name: its PRD scopes segmenter
training recipe, mask post-processing and variance reduction, and explicitly non-goals data
collection.

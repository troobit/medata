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
36-channel palette, myfoodrepo-bridge Decision 27); export gates passed at 22,169,442 B with oracle argmax
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

**Session log — 2026-08-04.** Release + real segmenter deployed to the iPhone 16 Pro,
build stamp **`470bb1b-20260804-225023`**, and launched. This build also carries the new
home-page glucose header (§2a), so one build serves the whole list below. `make logs-device`
needs **root** on this machine (`log collect --device-name` refuses otherwise) — run
`sudo make logs-device LOG_LAST=10m` to complete order 0.

| Order | Spec | Task | What to observe |
|---|---|---|---|
| 0 | `myfoodrepo-bridge` | 6 `[-]` | **One capture on the current build** (its new estimation-log row carries the live lineage) **or `sudo make logs-device`**. The 2026-08-04 estimation-log reading was historical — rows show each attempt's own `modelVersion`, newest was 3 Aug — so it proved the 2–3 Aug builds, not this one. Closes task 6, unblocks 7 and 8 |
| 1 | `estimation/model-production` | prerequisites Stage 7 | **ANE residency** in Xcode's Core ML performance report — the MVP gate; needs Xcode, not the phone |
| 2 | `myfoodrepo-bridge` | 7, 8 | Point the phone at real meals including a cereal bowl; confirm overlay and carb readings. Tick both ledgers with the model-production prerequisites |
| 3 | `capture-bundle-recorder` | 4 `[-]` | **Replay half DONE 2026-08-05** — two harness defects found and fixed (palette-shape trap; precondition → throw), device-vs-replay divergence measured at -4.6 %. Device half (Files app, timings, no OOM kill) outstanding |
| 4 | `estimation-quality` | 7 | ~~Overlay speckle gone, readings stable~~ — **speckle confirmed gone 2026-08-04**, but from the shipped `PostProcessing` cleanup, not the retrain. Task 7 gates the *new recipe* and task 6 has not run, so it stays open (`agent-notes/field-truth-sessions.md`). Accuracy is "hugely improved, not yet as hoped" — an impression, not a measurement, until §4 lands |
| 5 | `bugfixes/no-food-pixels-on-fruit-plate-mvp` | 8 | Single **and** Double mode (currently BLOCKED behind the next row) |
| 6 | `bugfixes/lidar-plane-fit-degenerate-on-clean-capture` | 8 | Single and Double; unblocks the row above |
| 7 | `bugfixes/lidar-plane-fit-oom-on-device-1920x1440` | 3 | Clean run at 1920×1440 |
| 8 | `bugfixes/closeout-trail-mvp-cleanup` | 6 | Single + Double final pass |
| 9 | `ui/home-router` | 9 `[-]`, 11 | Routing confirmed fine 2026-08-04; deep-link deferral, AR-session release and Records live-delete still to check. **New task 11**: the latest-glucose header (§2a) |
| 10 | `ui/shutter-blocked-feedback` | 5 | Tap fires, estimation completes, result view appears |
| 11 | `ui/records-deletion` | 4 | Build, device look, docs |
| 12 | `ui/loading-symbol-animation` | 5 | Loader look |
| 13 | `ui/glucose-lock-widget` | 14 | App Group round-trip, gallery kind, StandBy render, staleness ladder, tap-to-Graph |
| 14 | `data/cgm-connect` | 14 | HealthKit backfill + live reading land as bsl events |
| 15 | ~~`serving-adjust`~~ | ~~7~~ | **DONE 2026-08-04** — looks-right pass passed on the iPhone 16 Pro |
| 16 | `snaqui` | 8 | Portion ergonomics, no portrait truncation |

**Two things to settle before starting.** The four bugfix verifications were written against an
iPhone 13 Pro Max, which is now below the hardware floor (segmenter-foundation Decision 22) — either
re-target them to the iPhone 16 Pro or log why the older device still counts. And
`bugfixes/capture-log-flood-evicts-plane-fit-diagnostics` is only *half* fixed: the diagnostic
blindness is resolved but the matte-table plane-fit refusal is not, and it needs one capture on a
matte surface to root-cause. Add that capture to the session.

### 2a. Landed during the session — the home page's latest glucose reading

The device pass on `ui/home-router` task 9 produced one change rather than a defect: the router
itself is fine, but the number the developer checks most often — current blood sugar — needed a
trip to Graph. It is now the topmost content on the home page, with a trend arrow when the
readings support a rate.

This narrows home-router Decision 2 (pure router, no summary data) rather than reversing it:
one live measurement is promoted, every roll-up stays out. Requirements §4 and Decision 15
carry the reasoning; the load-bearing part is that the derivation moved into a shared
`GlucoseSnapshotSource` in `Persistence`, called by both the home model and
`GlucoseWidgetPublisher`, so home and the lock-screen widget cannot drift apart — and it reads
the **store**, not the App Group container, so it is correct on a build whose App Group is still
unverified (`glucose-lock-widget` task 14). The two surfaces differ deliberately past 30
minutes: the widget withholds the number, home shows it with its age. Verification is
`ui/home-router` task 11.

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
a superseded 35-class palette while the promoted bundled model is 36-channel.

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

1. **The plane-fit path is wrong for handheld captures — mechanism confirmed, prediction refuted
   (measured 2026-08-05).** `FixtureRunner.run` routes any fixture with a non-empty `estimatorPath` to
   `fitPlateRegionPlane`, a centre-seeded flood fill written for the Nutrition5k overhead rig where
   "the rig centres the plate under the camera". A pulled device bundle does stamp
   `estimator_path = 'single_dominant'`, so field captures do take that branch. But the predicted
   consequence — "expect skips and `volumeEstimationFailed` on replay" — did **not** happen: the
   flood fill found a plate region and the fit succeeded. The real failure mode is quieter and worse
   for §4's purposes: the replay returned **98.92 g** carbs where the device recorded **103.71 g**
   for the same attempt, a **-4.6 %** divergence with no error raised. A silent few-percent drift is
   harder to catch than a crash and directly limits how finely a replayed error figure can be read.
   One capture is one data point; the divergence needs attributing (plate-region plane vs the
   device's own fit is the prime suspect — replay's `fitPlaneFromDepth` masks the whole frame) and
   measuring across more bundles before §4's log can quote per-capture error to better than ~5 %.
2. **β is pinned to 1.0 on replay** (`let unityBeta = BetaCorrection(entries: [:], defaultBeta: 1.0)`),
   so a replay measures the uncalibrated chain, not the calibrated β the app actually ships.
3. ~~**Bundles always claim `single_dominant`** even when oblique data is present, so a two-view field
   capture can never be replayed on the `twoViewSfS` branch.~~ **Wrong — corrected 2026-08-05.** This
   conflated two proto fields. A pulled two-view bundle records
   `capture_path_canonical = 'two_view_sfs'`, and that is the field `FixtureRunner.run` switches on,
   so a two-view capture replays on the `twoViewSfS` branch as intended. `estimator_path` is the one
   pinned at `single_dominant`, and it only selects the plane-fit method *within* the single-view
   branch (§5.1). No defect here.

### 5a. What a refused bundle actually contains (measured 2026-08-05)

A refusal that fires **before** segmentation records no probability tensor and no argmax — the
support plane is fitted from the pre-shutter mask at Stage D, ahead of the segmenter, so an
`emptyFoodMask` refusal short-circuits the pipeline. Two consequences pull in opposite directions:

- **Bad for diagnosis.** Such a bundle cannot be replayed through `FixtureRunner` at all (it needs
  probs), and the refusal was decided by the *pre-shutter preview* segmenter whose mask is not
  recorded anywhere. So the one thing you would want to inspect — was that mask right? — is exactly
  what is missing. Recording the pre-shutter mask on an `emptyFoodMask` refusal would cost a few KB
  and is the single highest-value addition to the recorder.
- **Good news for §5's corpus trade.** Those bundles are **3.6 MB** and already carry PNG nadir +
  oblique, depth, both intrinsics, `t_1_to_2` and gravity — precisely the promote-to-corpus payload
  §5 proposes, minus the probs, and at 1.8 % of the 200 MB full-probs size. The format is therefore
  already proven recordable; what is missing is only the harness's ability to re-segment on replay
  instead of requiring cached probs.

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

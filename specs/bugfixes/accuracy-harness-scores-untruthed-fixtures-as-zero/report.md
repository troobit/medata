# Bugfix Report: accuracy-harness-scores-untruthed-fixtures-as-zero

**Date:** 2026-08-04
**Status:** Fixed — closed out 2026-08-16 (end-to-end replay confirmed on real device
bundles, 2026-08-05 and 2026-08-11; see Verification)

## Description of the Issue

`HarnessCLI accuracy` reported a **passing accuracy bar for fixtures that carry no
ground truth at all**. A replay of recorded device capture bundles produced
`MAPE 0%` and `MAE` equal to the mean predicted grams — and, whenever those
predictions happened to be ≤ 25 g, `passesBar: true`.

This is the worst failure mode available to an evaluation harness: not a wrong
number, but a confident pass on a measurement that never happened.

**Why it fires on every device bundle.** `CaptureBundleRecorder` deliberately
leaves the `ground_truth_*` proto fields at their proto3 defaults — weighed truth
is back-filled off-device (`specs/capture/capture-bundle-recorder/smolspec.md`,
"Ground-truth fields MAY be left zero at record time"). So `groundTruthTotalCarbsG`
is `0.0` for **every** bundle pulled off the phone.

**Reproduction steps:**
1. Pull any capture bundle from `Documents/captures/` to the Mac.
2. Run the accuracy harness over it against the recorded checkpoint stamp.
3. Observe `mape: 0`, `mae` = the predicted grams, and — for a modest prediction —
   `passesBar: true`, with a zero exit status.

**Impact:** developer-phase tooling only; `HARNESS_ENABLED` is defined on the
`HarnessCore` / `HarnessCLI` / `HarnessCLITests` SPM targets and the shipping iOS
binary never includes this code. No user-facing estimate is affected. The damage
is to the decision loop: the harness is the instrument intended to answer "did this
checkpoint improve accuracy?", and until now it answered "yes, perfectly" to a run
containing no evidence.

## Investigation Summary

- **Root cause:** `AccuracyHarness.pointMAPE` (`HarnessCore/AccuracyHarness.swift`)
  guards `guard act > 0 else { return 0 }`, contributing `0 %` error per untruthed
  meal instead of excluding it; `pointMAE` has no guard at all and averages
  `|predicted − 0|`, i.e. the prediction itself. `evaluate(meals:)` fed every meal
  into both, and `passesBar` consulted only the two resulting numbers, with no
  notion of how many meals were actually measurable.

- **The guard is not simply a bug to delete.** `perClassStats` *depends* on that
  `return 0` behaviour: it deliberately constructs `let dummy: [Float] = Array(repeating: 0, ...)`
  and calls `pointMAPE`/`pointMAE` against it, because per-class ground truth is not
  available in `MealEvalInput` and the per-class block is documented as reporting
  "predicted distribution and status only". Changing the helpers' semantics would
  silently alter that block.

- **Fix therefore applied one level up**, in `evaluate(meals:)`, leaving the pure
  helpers and `perClassStats` untouched. See Decision 1.

**Defect type:** Scope error in an aggregate — unmeasured samples admitted to a
metric, and a pass/fail predicate that did not consult its own sample count.

**Why it occurred:** `pointMAPE`'s `guard act > 0 else { return 0 }` was written for
`perClassStats`, which passes a synthetic zeros array on purpose. Reused from
`evaluate(meals:)` it silently reinterpreted "no truth" as "zero error". Nothing
connected the two call sites. Until `CaptureBundleRecorder` landed there was also no
corpus of zero-truth fixtures to expose it — the harness had only ever been pointed at
Nutrition5k, whose plates carry dataset ground truth — so the guard never fired on a
real run.

**Contributing factor:** proto3 cannot distinguish an unset scalar from zero, so
`groundTruthTotalCarbsG == 0` is genuinely ambiguous at the type level; only the
recorder's smolspec says which it means.

## Resolution for the Issue

`HarnessCore/AccuracyHarness.swift`:

- `evaluate(meals:)` partitions meals on `isScorable(_:)` (`truth.isFinite && truth > 0`).
  Only scored meals feed MAPE, MAE and the bootstrap CI; the `n ≥ 30` CI threshold
  now counts scored meals, not all meals.
- `AccuracyReport` gains `scoredCount`, `unscoredCount` and `rows: [MealErrorRow]`.
- `passesBar` gains a `scoredCount > 0` conjunct — a run that scored nothing cannot
  pass a bar it never measured. An empty run also now fails rather than passing.
- `MealErrorRow` carries per-fixture `fixtureID`, `capturePath`, truth, prediction,
  `absoluteErrorG` and `percentError`. The two error fields are **optional and nil**
  for an untruthed meal: reporting `0` would read as an exact prediction, and
  reporting `|pred − 0|` would read as a large-but-real error. Absent is neither.
- `perClassStats` and `latencyStats` continue to run over *all* meals — they describe
  predicted distribution, calibration status and timing, not error.

`HarnessCLI/main.swift`:

- New `emitAccuracy(_:checkpointSHAs:to:)` helper, shared by `runAccuracy` and
  `runLegacyEval`, which previously carried byte-identical emit-and-exit blocks that
  could drift.
- `AccuracyJSON` gains `scoredCount`, `unscoredCount`, `rows`, and `checkpointSHAs`
  (the distinct segmenter stamps across the loaded fixtures — more than one means the
  aggregate is not attributable to a single checkpoint).
- A run with any untruthed meal prints a stderr warning naming the count and pointing
  at off-device back-fill. A run that scored *nothing* prints
  `FAIL: no meal carried ground truth — nothing was scored.` and exits 1.

`Makefile`: new `harness-accuracy` target (`FIXTURES=`, `SHA=`, optional `OUT=`),
since the harness previously had no Make entry point at all despite the project
convention that tooling runs through `make`. Its help text states up front that
untruthed bundles report UNSCORED and exit non-zero, so that outcome is not read as
a defect in the captures.

**Close-out correction (2026-08-16).** The target's usage text gave the SHA example as
`coreml_ab812dc3aa9d` — the app-facing `EstimationOutcome.modelVersion` lineage form.
`FixtureLoader.validate` compares against `fixture.segmenterCheckpointSha256`, which a
bundle stamps as the bare `ab812dc3aa9d`, so the example named exactly the value that
fails the load. Measured on the 2026-08-05 replay and recorded in the estimation-
diagnostics note, but never propagated back into the target this report added. The
usage text now gives the bare form and names the lineage form as the wrong one.

**Approach rationale:** the defect is one of *scope* — which meals belong in an
aggregate — not one of arithmetic, so it is corrected at the layer that knows the meal
set. `pointMAPE`, `pointMAE` and `perClassStats` stay byte-for-byte identical, so no
existing test of the per-class block needed to change. Adding `scoredCount > 0` to
`passesBar` is what actually closes the hole: even with correct metrics, a run over
zero scored meals yields MAPE 0 / MAE 0, which satisfies `mape < 20 && mae <= 25`.

**Alternatives considered** (full reasoning in [`decision_log.md`](decision_log.md),
Decisions 1 and 2):
- **Guard inside `pointMAPE`/`pointMAE`** — rejected: silently changes `perClassStats`,
  which passes zeros deliberately, and leaves `passesBar` still passable by an
  all-untruthed run.
- **Refuse to run when any fixture lacks truth** — rejected: an all-untruthed replay is
  the *normal* case for a field bundle and is still useful for reading predictions,
  latency and per-class distribution.
- **Report unscored error as `0` or as `|predicted − 0|`** — rejected: the first reads as
  an exact prediction, the second as a large but genuine error. `null` is the only
  encoding that cannot be mistaken for a result.

## Regression Test

**Test file:** `MedataCore/Tests/HarnessCLITests/AccuracyHarnessTests.swift`
**Test names:** `AccuracyHarnessTests.testAllUntruthedMealsScoreNothingAndFailTheBar`,
`…testUntruthedMealsAreExcludedFromMetrics`, `…testScoredRowsCarryPerFixtureError`,
`…testEmptyRunFailsTheBar`, `…testNonPositiveAndNonFiniteTruthIsNotScored`

**What they verify:**
- An all-untruthed run (5 meals, 20 g predicted against proto3-default zero truth —
  the exact shape that previously returned MAPE 0 / MAE 20 g / `passesBar: true`)
  reports `scoredCount == 0`, fails the bar, and emits `nil` on both error fields of
  every row. This is the red-before-fix assertion.
- Untruthed meals are excluded rather than dragged toward zero: a mixed set's MAPE and
  MAE equal those of the truthed subset evaluated alone, with a deliberately wild
  500 g untruthed prediction present to prove it does not move them — and that
  prediction still appears on its row, just unscored.
- Scored rows carry the per-fixture error the aggregates are built from (75 g against
  100 g → `absoluteErrorG == 25`, `percentError == 25`).
- An empty run fails the bar (`scoredCount == 0`, no rows).
- Negative, NaN and infinite truths are not scorable — `isScorable` is
  `truth.isFinite && truth > 0`, not merely `!= 0`.

**Run command:** `swift test --filter AccuracyHarnessTests`

## Affected Files

| File | Change |
|------|--------|
| `HarnessCore/AccuracyHarness.swift` | `evaluate(meals:)` partitions on `isScorable(_:)`; only scored meals feed MAPE/MAE and the n ≥ 30 CI threshold; `AccuracyReport` gains `scoredCount`/`unscoredCount`/`rows`; `passesBar` gains the `scoredCount > 0` conjunct; new `MealErrorRow` with optional error fields |
| `HarnessCLI/main.swift` | New shared `emitAccuracy(_:checkpointSHAs:to:)` replacing two byte-identical emit-and-exit blocks; `AccuracyJSON` gains `scoredCount`, `unscoredCount`, `rows`, `checkpointSHAs`; stderr warning on any unscored meal and `FAIL: no meal carried ground truth` + exit 1 when nothing scored |
| `MedataCore/Tests/HarnessCLITests/AccuracyHarnessTests.swift` | Five regression tests (above) |
| `Makefile` | New `harness-accuracy` target (`FIXTURES=`, `SHA=`, optional `OUT=`); help text states that untruthed bundles report UNSCORED and exit non-zero. **2026-08-16:** usage text's `SHA` example corrected from the lineage form `coreml_ab812dc3aa9d` to the bare stamp `ab812dc3aa9d` that `FixtureLoader.validate` actually compares |
| `specs/bugfixes/accuracy-harness-scores-untruthed-fixtures-as-zero/decision_log.md` | Decisions 1 and 2 |

## Verification

**Automated:**
- [x] Regression tests pass (`swift test --filter AccuracyHarnessTests`)
- [x] Full test suite passes at fix time — XCTest 515 executed, 5 skipped, 0 failures
      (was 510: five new tests); swift-testing 203 tests in 25 suites
- [x] Re-verified on close-out (2026-08-16, `research` at `e82b001`) — XCTest 598
      executed, 3 skipped, 0 failures; swift-testing 456 tests in 52 suites passed.
      All five regression tests observed passing in that run
- [x] `make build` green; `make spell` clean
- [x] `make harness-accuracy` with no arguments prints usage and exits non-zero
      (re-run 2026-08-16, exit 2, with the corrected `SHA` example)

**Manual verification (end-to-end, real device bundles):**
- **2026-08-05** — `1785135663727-success.fixture` (195 MB, 36-channel palette) pulled
  from the iPhone 16 Pro with `devicectl device copy from` and replayed through
  `make harness-accuracy`. Truth is zero as designed, so the run **correctly reported
  UNSCORED and exited non-zero** — the behaviour this fix installed, on real recorded
  data. Recipe and traps: [`docs/agent-notes/estimation-diagnostics.md`](../../../docs/agent-notes/estimation-diagnostics.md)
  §"Replaying a device bundle through HarnessCLI".
- **2026-08-11** — a fresh single-view field bundle pulled and replayed the same day,
  again reporting UNSCORED as designed, with no harness changes needed.
- Both replays are the close-out evidence for
  [`specs/capture/capture-bundle-recorder`](../../capture/capture-bundle-recorder/tasks.md)
  **task 4**, now `[x]`. The "not yet verified end-to-end" caveat this report carried
  at fix time is therefore discharged.

## Prevention

**Recommendations to avoid similar bugs:**
- **A bar must express "measured and met", not "not contradicted".** Any pass/fail
  predicate over an aggregate must consult the sample count it was computed from and
  require it to be non-zero. A metric over an empty set satisfies every inequality.
- **Encode an absent measurement as absent.** `null`/`nil`, never `0` and never a
  difference from a placeholder — both are false statements about a measurement that
  did not happen, and downstream consumers average them without noticing.
- **A proto3 scalar cannot distinguish unset from zero.** Where a producer
  deliberately leaves a field unset, every consumer needs an explicit presence check —
  or the schema needs an explicit presence flag. Document which, at the field.
- **Guards inside pure helpers get reused for purposes their author never saw.**
  Before changing a helper's semantics, grep its call sites; where the defect is one of
  scope rather than arithmetic, fix it at the layer that knows the scope.
- **Distrust a perfect score from an evaluation harness.** MAPE 0 % is far more often
  an instrument fault than a result; treat it as a signal to check the denominator.

## Follow-ups Not Taken Here

- **`perClassStats` is itself misleading** — it reports `mape: 0` and
  `mae` = mean predicted grams for every class, by construction, because it scores
  against a zeros array. That is pre-existing, documented in a comment, and out of
  scope for this fix, but it is the same category of defect and should be either
  given real per-class truth or dropped from the report. **Still live at close-out
  (2026-08-16):** `perClassStats` continues to call `pointMAPE`/`pointMAE` against
  `Array(repeating: 0, count:)`, and those zeros are emitted into the accuracy
  artifact's `perClass` block, where a reader can take `mape: 0` for a perfectly
  estimated class. Left in place deliberately — Decision 1 turns on not changing the
  helpers' semantics, and choosing between "carry per-class truth in `MealEvalInput`"
  and "drop the block" is a design call with its own decision to record, not a
  close-out edit. Applying Decision 2 one level down (make `ClassAccuracyStats.mape`
  /`.mae` optional so the block emits `null`) is the cheapest honest option.
- ~~**`runAccuracy` uses `ClassPalette.v1Standard`** while the promoted bundled model
  is 36-channel palette v2 (`coreml_ab812dc3aa9d`).~~ **CLOSED.** The 2026-08-05 replay
  hit exactly this: `C = 35` against a 36-channel bundle tripped `ProbabilityTensor`'s
  `precondition` and **trapped the process**, losing every other fixture in the
  directory. Fixed under `capture-bundle-recorder` task 4 — since pipeline Decision 50
  there is one palette, `paletteForFixture` resolves every fixture to
  `ClassPalette.standard` (no `v1Standard` reference remains in the tree), and
  `FixtureRunner.run` now throws `probsSizeMismatch` rather than trapping.
- The replay-fidelity defects recorded in
  [`docs/roadmap.md`](../../../docs/roadmap.md) §5 are not addressed by this fix, and
  two of the three have since been revised by measurement (2026-08-05):
  - **Centre-seeded plane fit on handheld captures** — mechanism confirmed, but the
    predicted consequence (skips and `volumeEstimationFailed`) did *not* occur. The
    real failure is quieter: replay returned 98.92 g against the device's recorded
    103.71 g for the same attempt, −4.6 % with no error raised. **A replayed error
    figure is therefore not the device's figure**, which bounds how finely this
    harness's output can be read even once truth is back-filled.
  - **β pinned to 1.0 on replay** — still open; a replay measures the uncalibrated
    chain, not the calibrated β the app ships.
  - ~~`single_dominant` stamped even with oblique data~~ — **retracted, no defect.**
    This conflated two proto fields: `FixtureRunner.run` switches on
    `capture_path_canonical`, which a two-view bundle records as `two_view_sfs`.

## Related

- [`decision_log.md`](decision_log.md) — Decision 1 (exclude in `evaluate`, not in the
  metric helpers) and Decision 2 (absent error is `null`, not zero).
- [`specs/capture/capture-bundle-recorder/smolspec.md`](../../capture/capture-bundle-recorder/smolspec.md)
  — "Ground-truth fields MAY be left zero at record time", the contract that makes every
  field bundle untruthed and this defect reachable on every replay.
- [`specs/capture/capture-bundle-recorder/tasks.md`](../../capture/capture-bundle-recorder/tasks.md)
  task 4 — the on-device close-out that supplied this report's end-to-end evidence.
- [`docs/agent-notes/estimation-diagnostics.md`](../../../docs/agent-notes/estimation-diagnostics.md)
  §"Replaying a device bundle through HarnessCLI" — the replay recipe, the
  `SHA`-format trap, and the device-vs-replay divergence measurement.
- Sibling defects of the same family, both in harness tooling that dropped or
  mis-scored input silently:
  [`calibrate-silently-drops-unreadable-fixtures`](../calibrate-silently-drops-unreadable-fixtures/report.md),
  [`seg-bench-silently-drops-mis-sized-fixtures`](../seg-bench-silently-drops-mis-sized-fixtures/report.md).

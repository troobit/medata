# Bugfix Report: accuracy-harness-scores-untruthed-fixtures-as-zero

**Date:** 2026-08-04
**Status:** Fixed (automated); end-to-end replay against a real device bundle pending

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

## Fix

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

## Verification

- `make test` green: **XCTest 515 executed, 5 skipped, 0 failures** (was 510 — five
  new tests); **swift-testing 203 tests in 25 suites passed**.
- `make spell` clean.
- New tests in `MedataCore/Tests/HarnessCLITests/AccuracyHarnessTests.swift`:
  - all-untruthed run scores nothing, fails the bar, and emits nil error fields —
    the exact scenario that previously passed;
  - untruthed meals are excluded rather than dragged toward zero (metrics equal
    those of the truthed subset evaluated alone, with a deliberately wild 500 g
    untruthed prediction present to prove it does not move them);
  - scored rows carry the per-fixture error the aggregates are built from;
  - an empty run fails the bar;
  - negative, NaN and infinite truths are not scorable.
- `make harness-accuracy` with no arguments prints usage and exits non-zero.

**Not yet verified end-to-end.** No `.fixture` file exists anywhere in the repo, so
the fix is proven at the unit level and through the CLI wiring, not by replaying a
real recorded bundle. That replay is `specs/capture/capture-bundle-recorder`
**task 4** (still `[-]`), scheduled in the P0 device session in
[`docs/roadmap.md`](../../../docs/roadmap.md).

## Follow-ups Not Taken Here

- **`perClassStats` is itself misleading** — it reports `mape: 0` and
  `mae` = mean predicted grams for every class, by construction, because it scores
  against a zeros array. That is pre-existing, documented in a comment, and out of
  scope for this fix, but it is the same category of defect and should be either
  given real per-class truth or dropped from the report.
- **`runAccuracy` uses `ClassPalette.v1Standard`** while the promoted bundled model
  is 36-channel palette v2 (`coreml_ab812dc3aa9d`). Not touched here; flagged for the
  replay work.
- The three replay-fidelity defects (centre-seeded plane fit on handheld captures,
  β pinned to 1.0, `single_dominant` stamped even with oblique data) are recorded in
  `docs/roadmap.md` §5 and are not addressed by this fix.

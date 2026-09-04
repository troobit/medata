# Bugfix Report: calibrate-silently-drops-unreadable-fixtures

**Date:** 2026-08-10
**Status:** Fixed

## Description of the Issue

The HarnessCLI `accuracy` command computed its report over an unstated subset of the fixtures it was given. `buildCalInputs` (`HarnessCLI/main.swift`) ran each fixture through the estimation pipeline with `fixtures.compactMap { try? FixtureRunner.run(...) }` — every pipeline failure (invalid capture path, missing depth, probability-tensor size mismatch, plane-fit or volume-estimation failure) became `nil` and was dropped with no message and no count. The accuracy JSON then reported MAPE/MAE over the survivors as though they were the whole set. In the degenerate case — for example every v2 device bundle mis-sized against a v1 palette, the exact incident capture-bundle-recorder task 4 hit — the run "succeeded" with a report over zero meals.

**Reproduction steps:**
1. Place one processable fixture and one with an empty `capture_path_canonical` (or wrong-size probability tensor) in a fixtures directory.
2. Run `HarnessCLI accuracy --fixtures-dir <dir> --checkpoint-sha256 <sha> ...`.
3. Observe the report contains one row; nothing anywhere states that a second fixture existed and was dropped.

**Impact:** Accuracy numbers used to judge estimation quality could silently exclude exactly the fixtures that fail — a biased sample presented as complete. Flagged in support-plane-reference Decision 60 during the task-26 device-corpus work, where real bundles first made the drop observable.

## Investigation Summary

Systematic (Fagan) inspection of the accuracy path and its siblings.

- **Symptoms examined:** report row count vs on-disk fixture count; the report's own `scoredCount`/`unscoredCount` bookkeeping (counts survivors only — `unscoredCount` means "no ground truth", not "pipeline failed").
- **Code inspected:** `HarnessCLI/main.swift` (`buildCalInputs`, `runAccuracy`, the calibrate-and-eval skip reporting at the `officialSkipped` block, `runSegBench`), `HarnessCore/FixtureRunner.swift` (error surface), `HarnessCore/FixtureLoader.swift` (throws loudly — the swallow is pipeline errors only, not file reads).
- **Hypotheses tested:** whether abort-on-first-error was the intended semantics — ruled out: `FixtureRunner.Error.probsSizeMismatch`'s doc comment states the batch tool must produce "a skipped fixture **with a message**, not a crash". The message half was never implemented at this call site.

## Discovered Root Cause

`buildCalInputs` implemented half of the documented batch-tool error policy: the don't-crash half (`try?`) without the report-the-skip half. Structurally, its return type `[MealCalibrationInput]` had no channel for failures, so no caller could report them even if it wanted to.

**Defect type:** Silent failure (error swallowed without logging), enforced by an information-losing return type.

**Why it occurred:** batch resilience was the design intent (one bad file must not lose the report for a directory of good ones); the skip-and-report half was built only at the calibrate-and-eval call site (`officialSkipped`, reported per reason to stderr including zero counts) and never at the accuracy one.

**Contributing factors:** tests exercised the path exclusively with known-good synthetic fixtures where nothing throws; only replaying real device bundles (support-plane-reference task 26) made a dropped fixture observable.

## Resolution for the Issue

**Changes made:**
- `HarnessCore/FixtureBatch.swift` (new) — `FixtureBatch.partition(fixtures:run:)` runs a throwing per-fixture closure over a batch and returns `(results, skips)`, each skip carrying the fixture id and the thrown error's description. Failures travel in the return value beside the successes, so a call site cannot structurally lose them.
- `HarnessCLI/main.swift:buildCalInputs` — returns `(inputs, skips)` via `FixtureBatch.partition`; the `try?` + `compactMap` is gone.
- `HarnessCLI/main.swift:runAccuracy` — prints one stderr line per skipped fixture (id + reason) plus a summary count that is printed even when zero ("absence is a measurement rather than a silence", the calibrate-and-eval rule), and exits 1 when fixtures were loaded but every one failed — an accuracy report over zero meals is meaningless and no longer emitted.

**Approach rationale:** skip-and-report matches both the documented `FixtureRunner.Error` intent and the calibrate-and-eval precedent; putting the partition in HarnessCore makes the repaired seam unit-testable (HarnessCLI is an executable target that tests cannot import).

**Alternatives considered:**
- Abort on first pipeline error (`try` propagating) — rejected: explicitly the failure mode the `FixtureRunner.Error` doc comment forbids; one corrupt bundle would lose the report for every other bundle in the directory.
- Report skips inline in `buildCalInputs` without changing its return type — rejected: keeps silence structurally possible at future call sites and leaves the all-failed case (exit 1) undecidable by the caller.
- Add a `pipelineSkippedCount` field to the accuracy JSON — not taken: stderr matches the calibrate precedent and keeps the report schema untouched; can be added later if a consumer needs it machine-readable.

## Regression Test

**Test file:** `MedataCore/Tests/HarnessCLITests/FixtureBatchTests.swift`
**Test names:** `mixedBatchPartitions`, `skipReasonIsTheError`, `allFailedBatchKeepsEverySkip`, `realRunnerErrorIsCarried`

**What it verifies:** successes and failures are partitioned with neither lost; the skip carries the thrown error's description, not a generic label; an all-failed batch yields every skip in input order (the condition `runAccuracy`'s exit-1 keys on); and a real `FixtureRunner.run` failure (`invalidCapturePath` on an empty capture path) surfaces its case and fixture id in the skip.

**Red confirmed before the fix:** the test target failed to build against the missing `FixtureBatch` seam (the bug *is* the absence of a failure channel, so the honest red is the API not existing). Green after.

**Run command:** `swift test --filter FixtureBatchTests`

## Affected Files

| File | Change |
|------|--------|
| `HarnessCore/FixtureBatch.swift` | New — batch partition seam carrying skips beside results |
| `HarnessCLI/main.swift` | `buildCalInputs` returns `(inputs, skips)`; `runAccuracy` reports skips to stderr and exits 1 on all-failed |
| `MedataCore/Tests/HarnessCLITests/FixtureBatchTests.swift` | New — four regression tests |

## Verification

**Automated:**
- [x] Regression tests pass (`swift test --filter FixtureBatchTests`, 4/4)
- [x] Full test suite passes (`make test` — XCTest and swift-testing totals both green)
- [x] `make spell` passes

**Manual verification:**
- Inspected the stderr contract against the calibrate-and-eval precedent: per-reason lines plus an always-printed summary count, zero included.

## Prevention

**Recommendations to avoid similar bugs:**
- In batch tools, never `try?` + `compactMap` over operator-supplied inputs — partition into successes and carried failures so reporting is the caller's *only* option, not an extra step it can forget.
- When a doc comment states a two-part policy ("skip **with a message**"), grep the call sites for the second half.
- `runSegBench` (`HarnessCLI/main.swift`) still quietly drops mis-sized fixtures via a `compactMap` guard — its own comment records this as "a quieter failure, equally wrong". Related, deliberately out of scope here; candidate for the same `FixtureBatch` treatment.

## Related

- `specs/estimation/support-plane-reference/decision_log.md` Decision 60 — where the swallow was flagged (device corpus work, task 26).
- `specs/bugfixes/accuracy-harness-scores-untruthed-fixtures-as-zero/` — earlier accuracy-path completeness fix in the same family.
- Calibrate-and-eval skip reporting (`officialSkipped`, `HarnessCLI/main.swift`) — the precedent this fix mirrors.

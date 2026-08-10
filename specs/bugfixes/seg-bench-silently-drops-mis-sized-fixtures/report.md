# Bugfix Report: seg-bench-silently-drops-mis-sized-fixtures

**Date:** 2026-08-10
**Status:** Fixed

## Description of the Issue

The HarnessCLI `seg-bench` command dropped any fixture whose probability tensor did not match the expected `H × W × C × 2` byte count — via a `guard ... else { return nil }` inside a `compactMap` — with no message and no count. The mIoU report was then computed over the survivors as though they were the whole set. The code's own comment acknowledged the defect: the byte-count guard was added so v2 bundles would not trap `ProbabilityTensor`'s size precondition, and the comment recorded the result as "silently dropping every v2 bundle rather than trapping — a quieter failure, equally wrong."

**Reproduction steps:**
1. Place one well-formed fixture and one whose `nadir_probs` length is wrong for its palette (e.g. a v2 bundle resolved against a v1 palette) in a fixtures directory.
2. Run `HarnessCLI seg-bench --fixtures-dir <dir> --checkpoint-sha256 <sha> ...`.
3. Observe the mIoU report covers one sample; nothing states a second fixture existed and was dropped.

**Impact:** Segmenter benchmark numbers (the Req 8.9 mIoU bar) could be computed over an unstated subset — and since mis-sized tensors correlate with palette drift, exactly the bundles most likely to reveal a regression were the ones excluded. An all-mis-sized directory produced a bench over zero samples.

## Investigation Summary

The sibling of `calibrate-silently-drops-unreadable-fixtures`, identified during that fix's inspection of the batch-path family and deliberately deferred there.

- **Symptoms examined:** the `compactMap` guard in `runSegBench` (`HarnessCLI/main.swift`); the self-indicting comment above it.
- **Code inspected:** `runSegBench`, `SegBench.evaluate` (counts only what it receives), `argmaxFromFP16Probs` (sole caller: `runSegBench`).
- **Hypotheses tested:** whether the guard should trap instead — ruled out for the same reason as the sibling: batch tools over operator-supplied files must not lose a directory-wide report to one bad file.

## Discovered Root Cause

Identical family to the sibling fix: the skip half of the batch policy existed (the guard) but the report half did not, and the drop happened inside a `compactMap` where the failure had no channel to travel.

**Defect type:** Silent failure (guard-and-drop without logging).

**Why it occurred:** the guard was added as a hotfix for the `ProbabilityTensor` trap (see the removed comment); making the drop visible was left for later and flagged in prose rather than implemented.

**Contributing factors:** `SegBenchSample` construction lived inline in the executable target, so there was no testable seam that could have pinned the behaviour.

## Resolution for the Issue

**Changes made:**
- `HarnessCore/SegBench.swift` — new `SegBench.sample(from:palette:)` builds one bench sample from a fixture and **throws** `FixtureRunner.Error.probsSizeMismatch` (fixture id, expected, got) on a mis-sized tensor; `argmaxFromFP16Probs` moved in from `main.swift` (its only caller) as an internal helper.
- `HarnessCLI/main.swift:runSegBench` — builds samples through `FixtureBatch.partition` (the seam introduced by the sibling fix), prints one stderr line per skipped fixture plus an always-printed summary count (zero included), and exits 1 when fixtures were loaded but every one failed; the inline `compactMap` guard and the "equally wrong" comment are gone.

**Approach rationale:** identical treatment to `calibrate-silently-drops-unreadable-fixtures` — the failure channel is the return value, reporting is the call site's only option, and the throwing builder lives in HarnessCore where it is unit-testable.

**Alternatives considered:**
- Leave the guard and add an inline counter — rejected: keeps silence structurally possible and diverges from the sibling's established pattern.
- Trap on mismatch — rejected: the original hotfix exists precisely because one malformed bundle must not lose the report for a directory of good ones.

## Regression Test

**Test file:** `MedataCore/Tests/HarnessCLITests/SegBenchTests.swift`
**Test names:** `testMisSizedProbsThrowsWithFixtureIDAndCounts`, `testWellFormedFixtureBuildsSampleWithDecodedArgmax`

**What it verifies:** a mis-sized tensor throws `probsSizeMismatch` carrying the fixture id and both byte counts (the reason the stderr skip line reports); a well-formed fixture builds a sample whose predicted argmax matches the FP16 decode and whose ground-truth argmax passes through. The skip-carrying batch behaviour itself is pinned by `FixtureBatchTests` from the sibling fix.

**Red confirmed before the fix:** the test target failed to build against the missing `SegBench.sample` seam. Green after.

**Run command:** `swift test --filter SegBenchTests`

## Affected Files

| File | Change |
|------|--------|
| `HarnessCore/SegBench.swift` | New throwing `sample(from:palette:)`; `argmaxFromFP16Probs` moved in |
| `HarnessCLI/main.swift` | `runSegBench` uses `FixtureBatch.partition`, reports skips, gates all-failed; decoder removed |
| `MedataCore/Tests/HarnessCLITests/SegBenchTests.swift` | Two new regression tests |

## Verification

**Automated:**
- [x] Regression tests pass (`swift test --filter SegBenchTests`)
- [x] Full test suite passes (`make test` — XCTest and swift-testing totals both green)
- [x] `make spell` passes

**Manual verification:**
- stderr contract matches the sibling fix and the calibrate-and-eval precedent: per-fixture lines plus an always-printed summary count.

## Prevention

**Recommendations to avoid similar bugs:**
- This closes the last known `compactMap`-swallow in the harness batch family (`buildCalInputs` fixed by the sibling; calibrate-and-eval already reported). New batch call sites should start from `FixtureBatch.partition`.
- A prose flag in a comment ("equally wrong") is a deferred bug, not documentation — file it when written.

## Related

- `specs/bugfixes/calibrate-silently-drops-unreadable-fixtures/` — the sibling fix that introduced `FixtureBatch.partition` and flagged this path.
- `specs/bugfixes/capture-bundle-recorder` task 4 incident (palette drift producing mis-sized v2 tensors) — the scenario that motivated the original guard.

# Decision Log: accuracy-harness-scores-untruthed-fixtures-as-zero

## Decision 1: Exclude untruthed meals in `evaluate`, not in the metric helpers

**Date**: 2026-08-04
**Status**: accepted

### Context

`AccuracyHarness.pointMAPE` contains `guard act > 0 else { return 0 }` and
`pointMAE` averages `|predicted − actual|` with no guard. Feeding a meal whose
ground truth is zero therefore contributes 0 % error and an "error" equal to the
prediction itself. Every device capture bundle has zero truth by design, so a
field replay reported a perfect MAPE and could pass the accuracy bar outright.

The obvious fix — make the helpers skip non-positive truth — is unsafe.
`perClassStats` deliberately calls both helpers against a synthetic zeros array
(`let dummy: [Float] = Array(repeating: 0, count: pred.count)`) because per-class
ground truth is not carried in `MealEvalInput`; the block is documented as
reporting predicted distribution and calibration status only. Changing the helper
semantics would silently change that output too.

### Decision

Partition the meals inside `evaluate(meals:)` on a new
`isScorable(_ truth: Float) -> Bool` (`truth.isFinite && truth > 0`). Compute MAPE,
MAE and the bootstrap CI over the scored subset only. Leave `pointMAPE`, `pointMAE`
and `perClassStats` byte-for-byte unchanged. Surface `scoredCount` / `unscoredCount`
on `AccuracyReport` and add `scoredCount > 0` to `passesBar`.

### Rationale

The defect is one of *scope* — which meals belong in an aggregate — not one of
arithmetic. `evaluate` is the layer that knows the meal set; the helpers are pure
functions over two arrays and are reused for a purpose where zero-truth input is
intentional. Fixing at the aggregation layer repairs the real bug and leaves the
deliberate zeros usage alone, so no test of `perClassStats` needed to change.

Adding `scoredCount > 0` to `passesBar` is what actually closes the hole: even with
correct metrics, a run over zero scored meals yields MAPE 0 / MAE 0, which satisfies
`mape < 20 && mae <= 25`. The bar must express "measured and met", not "not
contradicted".

### Alternatives Considered

- **Guard inside `pointMAPE`/`pointMAE`**: Skip non-positive truth in the helpers -
  Rejected: silently changes `perClassStats`, which passes zeros on purpose, and
  leaves `passesBar` still passable by an all-untruthed run.
- **Throw or refuse when any fixture lacks truth**: Make untruthed input a hard error -
  Rejected: an all-untruthed replay is the *normal* case for a field capture bundle
  and is still useful for reading predictions, latency and per-class distribution.
  Refusing to run would block the main use of the recorder.
- **Treat zero truth as a legitimate measurement**: Accept 0 g as a real value -
  Rejected: no meal in scope has zero carbohydrate as a measured result, and proto3
  cannot distinguish "unset" from "zero" on a scalar field, so zero must be read as
  absent.
- **Add an explicit `hasGroundTruth` flag to the proto**: Disambiguate at the schema
  level - Rejected here as out of proportion to a metric bug; it is the right move if
  and when truth back-fill lands, and is recorded in `docs/roadmap.md` rather than
  built now.

### Consequences

**Positive:**
- A run that measures nothing can no longer report a passing bar.
- Untruthed meals no longer drag aggregates toward zero; metrics over a mixed set
  now equal metrics over the truthed subset alone.
- `perClassStats` and its tests are untouched.
- The report now carries per-fixture rows, so a run is inspectable rather than a
  single aggregate.

**Negative:**
- `AccuracyReport` gains three fields, so any future construction site must supply
  them (today there is exactly one, inside `AccuracyHarness`).
- Replaying device bundles now exits non-zero until truth is back-filled. This is
  correct but is a behaviour change for anyone who read exit 0 as success; the
  `make harness-accuracy` help text and a stderr warning both call it out.

### Impact

`HarnessCore/AccuracyHarness.swift`, `HarnessCLI/main.swift`,
`MedataCore/Tests/HarnessCLITests/AccuracyHarnessTests.swift`, `Makefile`.
Developer tooling only — `HARNESS_ENABLED` keeps all of it out of the shipping iOS
binary.

---

## Decision 2: Report absent error as null rather than zero

**Date**: 2026-08-04
**Status**: accepted

### Context

The new per-meal `MealErrorRow` needs to represent a meal that was not scored. The
natural encodings are zero, the raw `|predicted − 0|` difference, or an explicit
absent value.

### Decision

`MealErrorRow.absoluteErrorG` and `.percentError` are `Float?`, nil for an untruthed
meal, serialised as JSON `null`. The row still carries `groundTruthCarbsG` (0) and
the real `predictedCarbsG`, plus a `scored` boolean.

### Rationale

This is the same defect as the aggregate bug, one level down. A zero reads as an
exact prediction; `|predicted − 0|` reads as a large but genuine error. Both are
false statements about a measurement that did not occur. `null` is the only encoding
that cannot be mistaken for a result, and it forces any downstream consumer to handle
the case explicitly rather than averaging a placeholder.

Keeping the prediction on the row matters: an unscored capture is still evidence
about what the model *said*, which is the point of replaying field bundles before
truth exists.

### Alternatives Considered

- **Zero for unscored rows**: Simplest encoding - Rejected: indistinguishable from a
  perfect prediction, reproducing the exact bug being fixed one level down.
- **Omit unscored rows entirely**: Emit only scored rows - Rejected: the predictions
  are the main reason to replay an untruthed field bundle, and a silently shorter
  array hides how much of the run was unmeasured.
- **A sentinel such as −1**: In-band marker - Rejected: in-band sentinels get averaged
  by consumers that do not know about them; `null` fails loudly instead.

### Consequences

**Positive:**
- No consumer can silently average a placeholder into a real metric.
- Unscored predictions remain visible and usable.
- `scored` makes filtering explicit at the JSON level.

**Negative:**
- Consumers must handle optionals rather than plain floats.
- The JSON shape is now heterogeneous across rows, which a naïve CSV conversion has
  to account for.

---

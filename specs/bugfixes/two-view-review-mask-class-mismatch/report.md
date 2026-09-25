# Bugfix Report: Two-View Review Mask Class Mismatch

**Date:** 2026-09-25
**Status:** Fixed

## Description of the Issue

On the two-view path the review screen drew no food outline and highlighted no
row. The product owner reported it as "No pixels shown as food". The estimate
itself was correct — the carbohydrate figure and the row were right; only the
picture was wrong.

**Reproduction steps:**

1. Two-view capture where the nadir segmentation labels the food `unknown_food`
   and the oblique labels it a named class (2026-09-25 outcomes `7845FF40` and
   `BB05A08C`: nadir class 34 only, oblique class 4 `bread_wholemeal`).
2. Estimation succeeds and the row reads "Bread wholemeal".
3. Open the record in review: no outline is drawn over the photo and tapping the
   row highlights nothing.

**Impact:** Every two-view estimate where reconciliation changes the nadir's
labels — which is the whole point of reconciliation, so any split or unnamed
nadir region — produced a review mask whose classes did not match its own rows.
The overlay joins contours to rows by class, so the join silently found nothing.
The estimate was unaffected; the developer's only visual check on what the
segmenter actually measured was.

## Investigation Summary

- **Symptoms examined:** the two 2026-09-25 outcomes above (correct rows, empty
  overlay), and the persisted `mask` artefact, whose class indices were the
  segmenter's own (34) rather than the row's (4).
- **Code inspected:** `Pipeline.estimate`'s two-view branch, `ObjectReconciler
  .reconcile(nadir:oblique:palette:userClass:)` (two-view-trust Decision 6),
  `MaskArtefactWriter.persistMask`, `MealReviewModel` (rows come from
  `record.macros.perClass`; the overlay joins by palette index of the class id).
- **Hypotheses tested:** a broken contour trace or a colour-table mismatch in the
  overlay — ruled out, single-view captures drew correctly with the same code; a
  mask written at the wrong resolution — ruled out, the artefact decoded to the
  frame size with the right silhouette, under the wrong label.

## Discovered Root Cause

`Pipeline.estimate` declares `var measuredArgmax = nadirSeg.argmax` before the
capture-path switch: the label map the volume stage measured and the review
outline shows. Inside `case .twoViewSfS` the reconciled results are bound to a
**shadowed** `let nadirSeg`, so everything after that line reads the reconciled
map — except `measuredArgmax`, which was never reassigned on that path and kept
pointing at the outer, unreconciled map. The single-view branch does reassign it
(it has to, for depth-grown region growth).

**Defect type:** Stale variable on one branch; a shadowed binding that made the
omission invisible at the point of the bug.

**Why it occurred:** Reconciliation was added to the two-view branch after
`measuredArgmax` existed, and the shadowing idiom (`let nadirSeg = reconciled
.nadir`) reads as if it replaced the map everywhere.

**Contributing factors:** Nothing between the reconciliation and Stage L
observes the map, so the mismatch was only visible on a device screen; the mask
write is storage-only and deliberately swallows its own failures, so no log line
contradicted the rows.

## Resolution for the Issue

**Changes made:**

- `MedataCore/Sources/Pipeline/Pipeline.swift` (two-view branch, commit
  `254e5f3`) - `measuredArgmax = nadirSeg.argmax` immediately after the
  reconciled results are bound, with a comment naming what the map feeds.

**Approach rationale:** The review mask must be the map the volume stage
measured. Assigning at the point of reconciliation keeps that invariant local to
the branch that changes the labels, and mirrors the single-view branch.

**Alternatives considered:**

- Write the mask from a value returned by each branch rather than a `var` -
  Cleaner, but a larger refactor of a long function for no behavioural gain.
- Have the review overlay fall back to matching by geometry when the class join
  finds nothing - Hides the disagreement instead of fixing it, and the join by
  class is what makes per-row highlighting possible.
- Drop the shadowing so the outer `nadirSeg` is reassigned - The shadowed `let`
  is what keeps the raw segmenter output available for the capture bundle
  (depth-grown-food-region Req 6); removing it would change what the bundle
  records.

## Regression Test

**Test file:** `MedataCore/Tests/PipelineTests/ReviewMaskReconciledClassTests.swift`
**Test name:** `maskClassesMatchTheRowsAfterReconciliation`

**What it verifies:** a whole two-view `Pipeline.estimate` run — stub segmenter
engine (nadir sees only `unknown_food`, oblique sees the named class), stub
support-plane fitter, synthetic frames, recording store — must persist a mask
artefact whose every carvable class names a row on the returned record, and must
not carry the unreconciled `unknown_food` label. The run is end to end because
the artefact is written at Stage L, after the carve, and nothing earlier
observes the map.

Verified to fail on the pre-fix code: with the one line removed the mask decodes
to `unknown_food` while the row reads `bread_wholemeal`, and both the join
assertion and the sentinel assertion fail.

**Run command:** `swift test --filter ReviewMaskReconciledClass`

## Affected Files

| File | Change |
|------|--------|
| `MedataCore/Sources/Pipeline/Pipeline.swift` | Re-read the review map from the reconciled nadir |
| `MedataCore/Tests/PipelineTests/ReviewMaskReconciledClassTests.swift` | Regression test |

## Verification

**Automated:**

- [x] Regression test passes with the fix and fails without it
- [x] Full test suite passes (`make test`)
- [x] Linters/validators pass (`make spell`)

**Manual verification:**

- Next two-view sitting on the device: a capture whose nadir reads
  `unknown_food` must draw an outline and highlight its row.

## Prevention

**Recommendations to avoid similar bugs:**

- A `var` that both capture-path branches must maintain is a standing hazard in
  `Pipeline.estimate`; when a branch rebinds a stage input under a shadowed
  name, check every outer variable derived from the original.
- Storage-only artefacts that swallow their failures need a test that reads them
  back — nothing else in the system will notice them disagreeing with the record
  they were written beside.

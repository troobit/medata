# Bugfix Report: Anchor Label-Space Mismatch

**Date:** 2026-08-14
**Status:** Fixed

## Description of the Issue

Two remapped FoodSeg103 dataset roots exist with the **same 182 leak-free image
stems** but **different label spaces**:

| Root | `channel_count` | `class_mapping_sha256` | Max class index in the anchor |
|------|-----------------|------------------------|-------------------------------|
| `data/foodseg103_remapped` | 35 | `af6e1cd7…` | 34 |
| `data/foodseg103_remapped_v2` | 36 | `90ff4b4c…` | 35 |

Their class indices agree up to 23 and diverge above it. Scoring a 36-channel
model against the 35-channel masks mis-attributes every class above the
divergence and understates mean food-class IoU by roughly 0.07 — and because
every index it reads is still a *legal* index, nothing raises. The run completes,
prints a plausible number, and writes it into a lineage manifest.

**Reproduction steps:**

1. Take any 36-channel checkpoint (e.g. `build/checkpoint_merged_v2.pt`).
2. Run `run_validation.py --data data/foodseg103_remapped --split heldout_leakfree`.
3. Observe a mean food-class IoU roughly 0.07 below the same checkpoint's figure
   against `data/foodseg103_remapped_v2`, with no warning or error.

Measured on the two checkpoints the bug was found with:

| Checkpoint | v1 anchor (wrong) | v2 anchor (correct) |
|---|---|---|
| `ab812dc3aa9d` (shipped incumbent) | 0.2953 | **0.3927** — its recorded figure |
| `e4e92a9df9d3` (R1) | 0.2472 | **0.3215** |

**Impact:** High, and already realised. The promotion surface for every segmenter
run is the 182-image leak-free anchor, so a silently wrong number here propagates
straight into promote/reject verdicts. R1's validation was run this way and read
0.2472, making the gap to the incumbent look like −0.146 when it is −0.071. The
first draft of that comparison also read R1's spurious `0.0000` entries as a
class-weighting false-positive signature; on the correct anchor that reading
largely dissolves. No shipped artefact was affected — `ab812dc3aa9d` remains
bundled and its recorded 0.3927 was always correct, because Decisions 27 and 30
were measured against the v2 root.

## Investigation Summary

- **Symptoms examined:** a re-measurement of the shipped incumbent returned
  0.2953 where Decisions 27 and 30 both record 0.3927. A discrepancy in the
  *baseline* — not the candidate — is what exposed the bug; had only R1 been
  measured, the low number would have been read as a genuine result.
- **Code inspected:** `merge_corpus_foodrec2022.py` (anchor recording and
  invariants), `run_validation.py` (`per_class_iou_by_name`, arch fail-fast),
  `train.py` (argparse defaults), the `splits.json` / `co_stats.json` manifests
  of both remapped roots.
- **Hypotheses tested and ruled out:**
  - *Different image sets* — ruled out: both anchors hold 182 stems, and the
    merged corpus's leak-free invariants pass against either.
  - *A change in `run_validation.py` since the decisions were written* — ruled
    out: the current script reproduces 0.3927 exactly against the v2 root.
  - *Checkpoint confusion* — ruled out: the rebuilt manifest for
    `checkpoint_merged_v2.pt` stamps `model_version ab812dc3aa9d`, matching the
    version embedded in the bundled `.mlpackage`.
- **Confirmation:** the incumbent's staple mean over its seven measurable staples
  computes to 0.3870 on the v2 root — the exact figure Decision 30 records. Two
  independent published numbers reproduce only against v2, which identifies it as
  the surface those decisions were measured on.

## Discovered Root Cause

`merge_corpus_foodrec2022.py` built the merged corpus from
`data/foodseg103_remapped_v2` (its `--foodseg` default) while defaulting
`--anchor` to `data/foodseg103_remapped/heldout_leakfree` — the **v1** root. The
script's own two defaults disagreed. `splits.json` therefore recorded
`anchor.path` pointing into a label space the corpus was never built in, and that
recorded path was subsequently copied into the runbook and into the command used
to validate R1.

**Defect type:** Missing validation, plus a stale default that was not carried
forward with a migration.

**Why it occurred:** the palette moved from 35 to 36 channels (the cereal solid
appended at index 24). `--foodseg` was repointed at the new `_v2` remap;
`--anchor` was not. Nothing downstream could catch the divergence because the
leak-free invariants that *are* checked — anchor stems all in heldout, none in
train/val — are stem-based, and the stems are identical across both remaps. Only
the mask contents differ, and nothing looked at those.

**Contributing factors:**

- Both roots are plausible-looking sibling directories with identical structure
  and identical stem counts; nothing in the path names signals a label space.
- The failure is silent by construction. A wrong index is still a valid index, so
  the run neither crashes nor produces an obviously absurd number — it produces a
  slightly low one, which reads as a genuine result.
- `train.py` and `run_validation.py` both defaulted `--data` to the v1 root while
  defaulting `--num-classes` to 36, so the same mismatch was reachable by simply
  omitting a flag.

## Resolution for the Issue

**Changes made:**

- `tools/segmenter/validation.py` — added `dataset_channel_count(root)` and
  `assert_label_space(root, expected_channels)`: pure, stdlib-only helpers that
  read a dataset root's self-declared `splits.json` `channel_count` and fail fast
  on a contradiction. Silent when a root carries no manifest, so the guard
  catches contradictions without mandating one.
- `tools/segmenter/merge_corpus_foodrec2022.py:121-127` — `--anchor` default
  moved to `data/foodseg103_remapped_v2/heldout_leakfree`, plus an explicit check
  that the anchor is a split of the `--foodseg` root, with a comment recording
  why the existing stem-based invariants cannot catch this.
- `tools/segmenter/run_validation.py:136-142` — `assert_label_space` called
  before the model loads, beside the existing arch fail-fast. `--data` default
  moved to the v2 root.
- `tools/segmenter/train.py:1091-1094` — the same guard before training starts,
  so a mismatched corpus costs a second rather than a multi-hour run. `--data`
  default moved to the v2 root; `import validation` added.
- Docstring usage examples in `train.py` and `run_validation.py` updated off the
  v1 path.

**Approach rationale:** fixing only the default would have closed this instance
while leaving the class of error open — and R2 through R5 are all judged on this
same surface. The guard is the durable half. It uses each dataset's own recorded
`channel_count` rather than inferring the label space from mask contents, because
the maximum observed index is a weak signal: a split that happens not to contain
the top class would read as either space. The shape deliberately mirrors the
arch-mismatch fail-fast already at `run_validation.py:122-132`, which exists for
the identical reason — that silent wrongness is worse than a loud stop.

**Alternatives considered:**

- **Compare `class_mapping_sha256` from `co_stats.json` instead of
  `channel_count`** — strictly more precise, and it would catch a remap that
  changed indices *without* changing the width. Not chosen: `co_stats.json` is
  not present in every prepared root, the mapping SHA has already legitimately
  churned across contexts (Decision 29 records two dead SHAs), and pinning to it
  would make the guard fire on benign history. `channel_count` is the property
  that actually has to agree for a score to mean anything. Worth revisiting if a
  same-width remap ever ships.
- **Delete `data/foodseg103_remapped` outright** — removes the ambiguity at
  source. Not chosen: it is the label space several historical checkpoints and
  recorded numbers belong to, so deleting it would make older results
  unreproducible, and it would not stop the same mistake against a future pair.
- **Infer the label space from the masks** — no manifest dependency, but it
  requires a full decode pass over the split and is unreliable for the reason
  given above.

## Regression Test

**Test file:** `tools/segmenter/tests/test_anchor_label_space.py`

**Test names:**

- `test_merge_corpus_anchor_default_shares_a_root_with_the_foodseg_default` —
  covers the original defect directly: the `--anchor` default must resolve under
  the same root as `--foodseg`.
- `test_assert_label_space_rejects_a_mismatch` — a 36-channel model against
  35-channel masks raises rather than scores.
- `test_assert_label_space_accepts_a_match` / `…_an_unmanifested_root` — the
  guard does not over-fire.
- `test_dataset_channel_count_reads_the_manifest` / `…_is_none_without_a_manifest`
  — the helper's contract.
- `test_the_two_remapped_roots_really_are_different_label_spaces` and
  `test_the_v1_root_is_refused_for_the_36_channel_palette` — assert the premise
  against the real corpora, skipped automatically where they are absent.

**What it verifies:** that the two roots are genuinely different label spaces,
that a mismatch is refused rather than scored, and that the corpus builder can no
longer record an anchor from a foreign root.

**Run command:** `tools/segmenter/.venv/bin/python -m pytest tools/segmenter/tests/test_anchor_label_space.py -q`

All eight failed before the fix and pass after.

## Affected Files

| File | Change |
|------|--------|
| `tools/segmenter/validation.py` | Added `dataset_channel_count` + `assert_label_space` |
| `tools/segmenter/merge_corpus_foodrec2022.py` | `--anchor` default → v2 root; anchor/corpus root check |
| `tools/segmenter/run_validation.py` | Guard call before model load; `--data` default → v2 |
| `tools/segmenter/train.py` | Guard call before training; `--data` default → v2; import |
| `tools/segmenter/tests/test_anchor_label_space.py` | New regression cover (8 tests) |
| `docs/ml-training.md` | §4 records the correct R1 figures and the anchor trap |

## Verification

**Automated:**

- [x] Regression tests pass — 8/8, having failed 8/8 before the fix
- [x] Full test suite passes — 274 passed (266 pre-existing + 8 new)
- [x] `make spell` clean
- [x] `--help` still resolves for `train.py`, `run_validation.py`,
      `merge_corpus_foodrec2022.py`

**Manual verification:**

- The exact command that produced the bad figure now exits 1 with a message
  naming both channel counts and the corpus to use instead — and refuses
  **before** loading the model or writing any lineage file, so a mismatched run
  can no longer contaminate a manifest.
- Both affected checkpoints were re-measured against the correct anchor and their
  metrics written to per-model manifests (`build/lineage-ab812dc3aa9d.json`,
  `build/lineage-e4e92a9df9d3.json`).

## Prevention

- **A stem-based invariant does not prove a content-based property.** The anchor
  checks in `merge_corpus_foodrec2022.py` were real and passing throughout; they
  simply guaranteed something adjacent to what was assumed. When two artefacts
  share identity but differ in content, check the content.
- **Datasets should be asked what they are, not inferred from their path.** Every
  prepared root already recorded `channel_count`; nothing read it. Prefer a
  cheap manifest assertion at every consumption point over a naming convention.
- **A silent numeric wrongness deserves a fail-fast, not a warning.** This
  follows the precedent already set by the arch-mismatch check.
- **Discrepancies in a baseline are worth chasing.** The bug surfaced only
  because the *incumbent* was re-measured and disagreed with its published
  figure. Re-measuring the baseline alongside each candidate — cheap here, at 182
  images — turns an unfalsifiable candidate number into a checkable pair, and is
  worth making standard for R2 through R5.

## Related

- `docs/ml-training.md` §4 — R1's command, corrected figures, and the anchor trap
- `docs/ml-training.md` §7 — bundled-model swap procedure and per-model lineage
- `specs/estimation/segmenter-foundation/decision_log.md` Decisions 27, 29, 30 —
  the recorded 0.3927 / 0.3870 figures this bug was caught against; all measured
  on the v2 root and therefore **unaffected**
- `specs/estimation/estimation-quality/tasks-segmenter-training-pipeline.md`
  task 6 — R1's verdict, which must be written against the corrected figures

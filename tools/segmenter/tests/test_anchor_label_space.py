"""Label-space agreement between a dataset directory and the model judging it.

Regression cover for the `anchor-label-space-mismatch` bugfix. `data/foodseg103_remapped`
(35 channels, mapping `af6e1cd7…`) and `data/foodseg103_remapped_v2` (36 channels,
mapping `90ff4b4c…`) hold the SAME 182 leak-free stems but different label spaces:
the class indices diverge above 23. Scoring a 36-channel model against the 35-channel
masks therefore mis-attributes every class above the divergence and understates mean
food-class IoU by roughly 0.07 — and, because every index it reads is still a legal
index, it does so silently, returning a plausible number rather than raising.

Measured on the two checkpoints this bug was found with:

    ab812dc3aa9d (incumbent)  v1 anchor 0.2953   v2 anchor 0.3927 (its recorded figure)
    e4e92a9df9d3 (R1)         v1 anchor 0.2472   v2 anchor 0.3215

Two defects, tested separately:

1. `merge_corpus_foodrec2022.py` builds the corpus from the v2 root but defaults its
   `--anchor` to the v1 root, so `splits.json` records `anchor.path` in a label space
   the corpus was never built in.
2. Nothing downstream checks. `run_validation.py` accepts any `--data` and scores
   against it, which is what let defect 1 reach two recorded verdicts.

Torch-free: these read argparse defaults and the datasets' own `splits.json`
manifests, never a model.
"""

import json
from pathlib import Path

import pytest

import validation

REPO_ROOT = Path(__file__).resolve().parents[3]
V1_ROOT = REPO_ROOT / "data" / "foodseg103_remapped"
V2_ROOT = REPO_ROOT / "data" / "foodseg103_remapped_v2"


def _defaults(module) -> dict[str, str]:
    """The argparse defaults a module's ``main`` would run with, without running it."""
    import argparse
    import contextlib
    import io

    captured: dict[str, str] = {}
    real_parse = argparse.ArgumentParser.parse_args

    def spy(self, *args, **kwargs):  # noqa: ANN001
        captured.update({a.dest: a.default for a in self._actions})
        raise SystemExit(0)

    argparse.ArgumentParser.parse_args = spy
    try:
        with contextlib.suppress(SystemExit), \
                contextlib.redirect_stdout(io.StringIO()):
            module.main([])
    finally:
        argparse.ArgumentParser.parse_args = real_parse
    return captured


# ── Defect 1: the corpus builder's own defaults disagree ────────────────────────

def test_merge_corpus_anchor_default_shares_a_root_with_the_foodseg_default():
    """`--anchor` must be a split of the SAME dataset root `--foodseg` is built from.

    Expected: both defaults resolve under `data/foodseg103_remapped_v2`.
    Actual (bug): `--foodseg` is `_v2` but `--anchor` is the v1 root's
    `heldout_leakfree`, so the recorded anchor is in the 35-channel space while the
    corpus is in the 36-channel one.
    """
    merge = pytest.importorskip("merge_corpus_foodrec2022")
    defaults = _defaults(merge)

    foodseg_root = Path(defaults["foodseg"]).resolve()
    anchor_root = Path(defaults["anchor"]).resolve().parent

    assert anchor_root == foodseg_root, (
        f"anchor default lives under {anchor_root}, corpus is built from "
        f"{foodseg_root} — different label spaces"
    )


# ── Defect 2: nothing fails fast on a label-space mismatch ──────────────────────

def test_dataset_channel_count_reads_the_manifest(tmp_path):
    """The helper reports a dataset root's recorded channel count."""
    (tmp_path / "splits.json").write_text(json.dumps({"channel_count": 35}))
    assert validation.dataset_channel_count(tmp_path) == 35


def test_dataset_channel_count_is_none_without_a_manifest(tmp_path):
    """An unmanifested directory is unknown, not a failure — the guard stays advisory."""
    assert validation.dataset_channel_count(tmp_path) is None


def test_assert_label_space_rejects_a_mismatch(tmp_path):
    """A 36-channel model judged against 35-channel masks must raise, not score.

    This is the exact shape of the bug: legal indices, plausible output, wrong answer.
    """
    (tmp_path / "splits.json").write_text(json.dumps({"channel_count": 35}))
    with pytest.raises(SystemExit) as excinfo:
        validation.assert_label_space(tmp_path, 36)
    assert "36" in str(excinfo.value) and "35" in str(excinfo.value)


def test_assert_label_space_accepts_a_match(tmp_path):
    (tmp_path / "splits.json").write_text(json.dumps({"channel_count": 36}))
    validation.assert_label_space(tmp_path, 36)


def test_assert_label_space_accepts_an_unmanifested_root(tmp_path):
    """No manifest means no claim to contradict — do not block the run."""
    validation.assert_label_space(tmp_path, 36)


# ── The real corpora, when they are present on this machine ─────────────────────

@pytest.mark.skipif(not (V1_ROOT / "splits.json").is_file()
                    or not (V2_ROOT / "splits.json").is_file(),
                    reason="remapped corpora not present on this machine")
def test_the_two_remapped_roots_really_are_different_label_spaces():
    """Guards the premise: if these ever converge, the bug and its fix are moot."""
    assert validation.dataset_channel_count(V1_ROOT) == 35
    assert validation.dataset_channel_count(V2_ROOT) == 36


@pytest.mark.skipif(not (V1_ROOT / "splits.json").is_file(),
                    reason="v1 corpus not present on this machine")
def test_the_v1_root_is_refused_for_the_36_channel_palette():
    """The end-to-end assertion: today's palette must not be scored on the v1 root."""
    with pytest.raises(SystemExit):
        validation.assert_label_space(V1_ROOT, len(validation.food_class_names())
                                      + len(validation.special_channel_names()))

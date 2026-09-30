"""Validation scores a checkpoint at the size it trained at.

Scoring a 641-trained checkpoint at the 513 default cost 0.0132 of mask food
IoU and 0.0330 of region IoU on the leak-free anchor — a larger swing than any
recipe lever measured in the R8–R16 series, and silent. The size is therefore
resolved from the lineage's ``train_config.target_size``, the same way the arch
already is, unless ``--target-size`` says otherwise.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_validation import resolve_target_size  # noqa: E402


def test_defaults_to_the_trained_size():
    assert resolve_target_size(None, {"train_config": {"target_size": 641}}) == 641


def test_defaults_to_513_when_lineage_does_not_record_one():
    assert resolve_target_size(None, {"train_config": {}}) == 513
    assert resolve_target_size(None, {}) == 513
    assert resolve_target_size(None, None) == 513


def test_explicit_flag_wins_over_lineage():
    assert resolve_target_size(513, {"train_config": {"target_size": 641}}) == 513

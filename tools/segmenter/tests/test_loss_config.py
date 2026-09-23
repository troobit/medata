"""Loss selection + class-weight derivation tests (PRD: segmenter training pipeline).

Pure arithmetic / pure dispatch over loss_config.py — no torch, no GPU, no
dataset (the conftest.py pattern shared with the export/validation gate tests).
The contract under test: omitting --loss reproduces the historical unweighted
cross-entropy byte-for-byte in the recorded train_config, and the opt-in losses
record enough in provenance to reproduce a run from lineage alone.
"""

import pytest

import loss_config
import train  # torch-free import: heavy deps are lazy, loss_config is pure


# ── Loss-name normalisation / selection ─────────────────────────────────────────

def test_choices_and_default():
    # "co_occurrence" added by segmenter-foundation design §4.3 (task 10).
    assert loss_config.LOSS_CHOICES == (
        "ce", "weighted_ce", "focal", "dice", "combined", "co_occurrence",
    )
    assert loss_config.DEFAULT_LOSS == "ce"


def test_omitted_name_defaults_to_ce():
    assert loss_config.normalise_loss_name(None) == "ce"


def test_unknown_name_is_rejected():
    with pytest.raises(ValueError, match="tversky"):
        loss_config.normalise_loss_name("tversky")


@pytest.mark.parametrize("name,expected", [
    ("ce", False),
    ("weighted_ce", True),
    ("focal", False),
    ("dice", False),
    ("combined", True),
    ("co_occurrence", True),  # CE base (design §4.3)
])
def test_which_losses_consume_class_weights(name, expected):
    # Weights are consumed only under an ACTIVE scheme (snaq-parity Req 6.3);
    # test_class_weighting.py covers the scheme axis.
    assert loss_config.loss_uses_class_weights(name, "sqrt_inverse") is expected


# ── Loss specs (what train.py dispatches on and records) ────────────────────────

def test_default_spec_is_plain_ce():
    assert loss_config.resolve_loss_spec(None) == {"loss": "ce"}
    assert loss_config.resolve_loss_spec("ce") == {"loss": "ce"}


def test_weighted_ce_spec_names_the_weighting_scheme():
    # weighted_ce requires an active scheme (Req 6.3; the none/default case is
    # covered as a launch error in test_class_weighting.py).
    spec = loss_config.resolve_loss_spec("weighted_ce", class_weighting="sqrt_inverse")
    assert spec == {"loss": "weighted_ce", "weighting": "sqrt_inverse"}


def test_focal_spec_carries_gamma():
    assert loss_config.resolve_loss_spec("focal") == {
        "loss": "focal", "focal_gamma": loss_config.DEFAULT_FOCAL_GAMMA,
    }
    assert loss_config.resolve_loss_spec("focal", focal_gamma=1.5)["focal_gamma"] == 1.5


def test_dice_spec_is_parameter_free():
    assert loss_config.resolve_loss_spec("dice") == {"loss": "dice"}


def test_combined_spec_carries_mix_and_weighting():
    spec = loss_config.resolve_loss_spec("combined")
    assert spec == {
        "loss": "combined",
        "dice_weight": loss_config.DEFAULT_DICE_WEIGHT,
        "weighting": "none",
    }


# ── Provenance (train_config byte-for-byte contract) ────────────────────────────

def test_default_loss_records_nothing_in_train_config():
    # THE acceptance criterion: an omitted --loss must leave the recorded
    # train_config byte-for-byte identical to a pre-flag run — no new keys.
    assert loss_config.loss_train_config(loss_config.resolve_loss_spec(None)) == {}
    assert loss_config.loss_train_config(loss_config.resolve_loss_spec("ce")) == {}


@pytest.mark.parametrize("name", ["weighted_ce", "focal", "dice", "combined"])
def test_non_default_losses_record_their_full_spec(name):
    # weighted_ce needs an active scheme (Req 6.3); the others take the default.
    scheme = "sqrt_inverse" if name == "weighted_ce" else None
    spec = loss_config.resolve_loss_spec(name, class_weighting=scheme)
    assert loss_config.loss_train_config(spec) == spec


# Class-weight derivation (the --class-weighting scheme builder) is covered in
# test_class_weighting.py; inverse-frequency weighting itself was removed
# (snaq-parity Req 6.3 / Decision 13, enforcing segmenter-foundation
# Decision 25 in code).


# ── CLI surface (train.py imports and validates torch-free) ─────────────────────

def test_train_cli_rejects_unknown_loss_before_touching_torch(capsys):
    with pytest.raises(SystemExit) as excinfo:
        train.main(["--loss", "tversky"])
    assert excinfo.value.code == 2  # argparse usage error, not a torch ImportError
    assert "--loss" in capsys.readouterr().err


def test_train_help_lists_the_opt_in_flags(capsys):
    with pytest.raises(SystemExit) as excinfo:
        train.main(["--help"])
    assert excinfo.value.code == 0
    out = capsys.readouterr().out
    assert "--loss" in out
    assert "--photometric-augment" in out

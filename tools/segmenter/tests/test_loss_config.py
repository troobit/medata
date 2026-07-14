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
    ("co_occurrence", True),  # weighted_ce base (design §4.3)
])
def test_which_losses_consume_class_weights(name, expected):
    assert loss_config.loss_uses_class_weights(name) is expected


# ── Loss specs (what train.py dispatches on and records) ────────────────────────

def test_default_spec_is_plain_ce():
    assert loss_config.resolve_loss_spec(None) == {"loss": "ce"}
    assert loss_config.resolve_loss_spec("ce") == {"loss": "ce"}


def test_weighted_ce_spec_names_the_weighting_scheme():
    spec = loss_config.resolve_loss_spec("weighted_ce")
    assert spec == {"loss": "weighted_ce", "weighting": "inverse_frequency"}


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
        "weighting": "inverse_frequency",
    }


# ── Provenance (train_config byte-for-byte contract) ────────────────────────────

def test_default_loss_records_nothing_in_train_config():
    # THE acceptance criterion: an omitted --loss must leave the recorded
    # train_config byte-for-byte identical to a pre-flag run — no new keys.
    assert loss_config.loss_train_config(loss_config.resolve_loss_spec(None)) == {}
    assert loss_config.loss_train_config(loss_config.resolve_loss_spec("ce")) == {}


@pytest.mark.parametrize("name", ["weighted_ce", "focal", "dice", "combined"])
def test_non_default_losses_record_their_full_spec(name):
    spec = loss_config.resolve_loss_spec(name)
    assert loss_config.loss_train_config(spec) == spec


# ── Inverse-frequency class weights ─────────────────────────────────────────────

def test_uniform_counts_give_uniform_weights():
    weights = loss_config.inverse_frequency_weights([100, 100, 100, 100], 4)
    assert weights == pytest.approx([1.0, 1.0, 1.0, 1.0])


def test_dominant_class_is_downweighted_and_rare_class_upweighted():
    # Background-heavy split: class 2 owns 90% of pixels.
    weights = loss_config.inverse_frequency_weights([500, 500, 9000], 3)
    assert weights[2] < 1.0 < weights[0]
    assert weights[0] == pytest.approx(weights[1])


def test_kept_weights_are_mean_normalised():
    weights = loss_config.inverse_frequency_weights([10, 200, 5000], 3)
    assert sum(weights) / len(weights) == pytest.approx(1.0)


def test_ignored_classes_are_pinned_and_excluded_from_the_mean():
    base = loss_config.inverse_frequency_weights([10, 200, 5000], 3)
    weights = loss_config.inverse_frequency_weights(
        [10, 200, 5000, 7], 4, ignore_classes=(3,))
    assert weights[3] == 1.0
    # The pinned class must not rescale the real weights.
    assert weights[:3] == pytest.approx(base)


def test_absent_class_is_auto_pinned_not_exploded():
    # A zero-count class never appears as a CE target, so its weight is unused —
    # but naively it would inflate the normalisation mean and squash the rest.
    base = loss_config.inverse_frequency_weights([10, 200, 5000], 3)
    weights = loss_config.inverse_frequency_weights([10, 200, 5000, 0], 4)
    assert weights[3] == 1.0
    assert weights[:3] == pytest.approx(base)


# One near-absent class in a wide palette: after mean normalisation its weight
# approaches num_classes (20 here), well over the clamp.
_EXTREME_COUNTS = [1] + [1_000_000] * 19


def test_extreme_rarity_is_clamped_to_max_weight():
    weights = loss_config.inverse_frequency_weights(_EXTREME_COUNTS, 20)
    assert max(weights) == loss_config.MAX_CLASS_WEIGHT


def test_max_weight_none_disables_the_clamp():
    weights = loss_config.inverse_frequency_weights(
        _EXTREME_COUNTS, 20, max_weight=None)
    assert max(weights) > loss_config.MAX_CLASS_WEIGHT


def test_no_pixels_at_all_falls_back_to_uniform():
    assert loss_config.inverse_frequency_weights([0, 0, 0], 3) == [1.0, 1.0, 1.0]


@pytest.mark.parametrize("counts,num_classes", [
    ([1, 2], 3),          # length mismatch
    ([1, -2, 3], 3),      # negative count
    ([], 0),              # no classes
])
def test_invalid_inputs_are_rejected(counts, num_classes):
    with pytest.raises(ValueError):
        loss_config.inverse_frequency_weights(counts, num_classes)


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

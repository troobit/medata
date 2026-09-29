"""Loss selection + class-weight derivation tests (PRD: segmenter training pipeline).

Pure arithmetic / pure dispatch over loss_config.py — no torch, no GPU, no
dataset (the conftest.py pattern shared with the export/validation gate tests).
The contract under test: omitting --loss reproduces the historical unweighted
cross-entropy byte-for-byte in the recorded train_config, and the opt-in losses
record enough in provenance to reproduce a run from lineage alone.
"""

import math

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


def test_combined_spec_takes_an_explicit_dice_weight():
    spec = loss_config.resolve_loss_spec("combined", dice_weight=0.75)
    assert spec["dice_weight"] == 0.75


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


# ── Repeat-factor sampling (research note §4.4, task 15) ────────────────────────

# Four images over a 4-class palette with background at index 3: class 0 in
# every image, class 1 in half, class 2 in one image. Background is in all.
PRESENT = [[0, 3], [0, 1, 3], [0, 3], [0, 1, 2, 3]]


def test_class_image_frequencies_count_each_class_once_per_image():
    assert loss_config.class_image_frequencies(PRESENT, 4) == [1.0, 0.5, 0.25, 1.0]
    # A class repeated within one image's list still counts once.
    assert loss_config.class_image_frequencies([[1, 1]], 2) == [0.0, 1.0]


def test_repeat_factor_is_max_over_present_classes_of_sqrt_t_over_f():
    factors = loss_config.repeat_factors(PRESENT, 4, 0.5, exclude=(3,))
    # Image 0: f=1 → 1. Image 1: sqrt(0.5/0.5) = 1. Image 3: sqrt(0.5/0.25).
    assert factors == pytest.approx([1.0, 1.0, 1.0, math.sqrt(2.0)])


def test_threshold_at_or_below_every_frequency_gives_all_ones():
    assert loss_config.repeat_factors(PRESENT, 4, 0.25, exclude=(3,)) == [1.0] * 4


def test_background_never_drives_the_repeat_factor():
    # Only background in image 0 and only a rare class in image 1: without the
    # exclusion the rare image would still win, but with background as the
    # rarest "class" it must not be boosted.
    present = [[3], [3], [3], [0, 3]]
    assert loss_config.repeat_factors(present, 4, 0.5, exclude=(3,)) == \
        pytest.approx([1.0, 1.0, 1.0, math.sqrt(2.0)])
    present = [[0], [0], [0], [0, 3]]
    assert loss_config.repeat_factors(present, 4, 0.5, exclude=(3,)) == [1.0] * 4


def test_repeat_factor_threshold_must_be_in_unit_interval():
    with pytest.raises(ValueError, match="threshold"):
        loss_config.repeat_factors(PRESENT, 4, 0.0)
    with pytest.raises(ValueError, match="threshold"):
        loss_config.repeat_factors(PRESENT, 4, 1.5)


def test_train_cli_rejects_out_of_range_repeat_factor_threshold(capsys):
    with pytest.raises(SystemExit) as excinfo:
        train.main(["--repeat-factor-threshold", "2"])
    assert excinfo.value.code == 2
    assert "--repeat-factor-threshold" in capsys.readouterr().err


# ── Boundary-weighted per-pixel loss (MD-29 mask-quality re-scope) ──────────────

np = pytest.importorskip("numpy")  # a torch dependency, but not torch itself

# 6x8 image, class 0 on the left four columns and class 1 on the right four:
# the only label change runs between columns 3 and 4.
TWO_REGIONS = np.concatenate(
    [np.zeros((6, 4), dtype=np.int64), np.ones((6, 4), dtype=np.int64)], axis=1,
)


def test_boundary_band_one_marks_the_pixel_row_either_side_of_the_change():
    out = loss_config.boundary_weight_map(TWO_REGIONS, band_px=1, weight=3.0)
    assert out.dtype == np.float32 and out.shape == TWO_REGIONS.shape
    expected = np.ones((6, 8), dtype=np.float32)
    expected[:, 3:5] = 3.0
    assert np.array_equal(out, expected)


def test_boundary_band_two_widens_the_seam_by_one_on_each_side():
    out = loss_config.boundary_weight_map(TWO_REGIONS, band_px=2, weight=3.0)
    expected = np.ones((6, 8), dtype=np.float32)
    expected[:, 2:6] = 3.0
    assert np.array_equal(out, expected)


def test_boundary_uses_chebyshev_distance():
    # A single class-1 pixel in a class-0 field: band 1 marks its full 3x3
    # neighbourhood (diagonals included), band 2 the 5x5.
    lab = np.zeros((7, 7), dtype=np.int64)
    lab[3, 3] = 1
    out = loss_config.boundary_weight_map(lab, band_px=1, weight=2.0)
    assert (out == 2.0).sum() == 9 and out[2:5, 2:5].min() == 2.0
    out = loss_config.boundary_weight_map(lab, band_px=2, weight=2.0)
    assert (out == 2.0).sum() == 25 and out[1:6, 1:6].min() == 2.0


def test_ignored_labels_produce_no_boundary_and_stay_at_one():
    # The change is between class 0 and an ignored sentinel: no boundary at all.
    out = loss_config.boundary_weight_map(TWO_REGIONS, band_px=2, weight=3.0, ignore=(1,))
    assert np.array_equal(out, np.ones((6, 8), dtype=np.float32))
    # Three columns: class 0 | sentinel | class 2. Each real class touches only
    # the sentinel, so neither edge is a boundary.
    lab = np.array([[0, 0, 9, 2, 2]] * 3, dtype=np.int64)
    out = loss_config.boundary_weight_map(lab, band_px=1, weight=3.0, ignore=(9,))
    assert np.array_equal(out, np.ones((3, 5), dtype=np.float32))
    # A real change next to a sentinel: the band dilates around the change but
    # never onto the sentinel pixels.
    lab = np.array([[0, 0, 2, 2, 9]] * 3, dtype=np.int64)
    out = loss_config.boundary_weight_map(lab, band_px=2, weight=3.0, ignore=(9,))
    assert out[:, 4].tolist() == [1.0] * 3 and (out[:, :4] == 3.0).all()


def test_weight_one_yields_all_ones_and_no_change_yields_all_ones():
    out = loss_config.boundary_weight_map(TWO_REGIONS, band_px=2, weight=1.0)
    assert np.array_equal(out, np.ones((6, 8), dtype=np.float32))
    flat = np.full((4, 4), 5, dtype=np.int64)
    assert np.array_equal(loss_config.boundary_weight_map(flat, 1, 3.0), np.ones((4, 4), np.float32))


def test_image_edges_are_not_boundaries():
    # Background everywhere but one interior class: the canvas border must not
    # light up (the letterbox padding meets the content edge everywhere).
    lab = np.zeros((8, 8), dtype=np.int64)
    lab[3:5, 3:5] = 1
    out = loss_config.boundary_weight_map(lab, band_px=1, weight=3.0)
    assert out[0, :].max() == 1.0 and out[:, 0].max() == 1.0
    assert out[-1, :].max() == 1.0 and out[:, -1].max() == 1.0


def test_boundary_map_rejects_bad_arguments():
    with pytest.raises(ValueError, match="band_px"):
        loss_config.boundary_weight_map(TWO_REGIONS, band_px=0, weight=2.0)
    with pytest.raises(ValueError, match="weight"):
        loss_config.boundary_weight_map(TWO_REGIONS, band_px=1, weight=0.0)
    with pytest.raises(ValueError, match="labels"):
        loss_config.boundary_weight_map(np.zeros((2, 2, 3), dtype=np.int64), 1, 2.0)


@pytest.mark.parametrize("argv,needle", [
    (["--boundary-weight", "0"], "--boundary-weight must be positive"),
    (["--boundary-band-px", "2"], "--boundary-band-px only applies"),
    (["--boundary-weight", "3", "--boundary-band-px", "0"], "at least 1"),
])
def test_train_cli_rejects_bad_boundary_flags(capsys, argv, needle):
    with pytest.raises(SystemExit) as excinfo:
        train.main(argv)
    assert excinfo.value.code == 2
    assert needle in capsys.readouterr().err

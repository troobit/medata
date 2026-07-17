"""Class-weighting scheme tests (snaq-parity task 19, Req 6.3, Decision 13).

segmenter-foundation Decision 25 attributed the staple regression to
inverse-frequency class weighting; snaq-parity Req 6.3 bans it and Decision 13
removes it from code entirely — not defaulted away, removed — so the attributed
failure cause cannot be re-selected by accident. The replacement surface is a
single ``--class-weighting {none, sqrt_inverse}`` flag (default ``none``)
parameterising every weighted loss; ``sqrt_inverse`` is the deliberately
milder re-test scheme Req 6.3 permits.

``--loss weighted_ce --class-weighting none`` is a LAUNCH error: it would be
plain ``ce`` in disguise and corrupt an opportunistic loss-sweep verdict
(Req 6.5). ``combined`` and ``co_occurrence`` keep their non-CE terms under
``none``, so they stay valid choices either way.

Pure arithmetic / dispatch — torch-free (the loss_config pattern); the
criterion wiring for combined/co_occurrence under both schemes is torch-gated
per test.
"""

from __future__ import annotations

import math

import pytest

import loss_config
import train  # torch-free import: heavy deps are lazy


# ── Decision 25 enforced in code: inverse-frequency is GONE ─────────────────────

def test_inverse_frequency_weights_is_removed_entirely():
    assert not hasattr(loss_config, "inverse_frequency_weights")


def test_no_spec_can_name_inverse_frequency():
    for name in loss_config.WEIGHTED_LOSSES:
        scheme = "sqrt_inverse"
        spec = loss_config.resolve_loss_spec(name, class_weighting=scheme)
        assert spec["weighting"] != "inverse_frequency"


# ── Scheme surface ──────────────────────────────────────────────────────────────

def test_weighting_choices_and_default():
    assert loss_config.WEIGHTING_CHOICES == ("none", "sqrt_inverse")
    assert loss_config.DEFAULT_WEIGHTING == "none"


def test_unknown_scheme_is_rejected():
    with pytest.raises(ValueError, match="median_frequency"):
        loss_config.class_weights("median_frequency", [1, 2, 3], 3)


def test_scheme_none_yields_no_weight_vector():
    assert loss_config.class_weights("none", [100, 200, 300], 3) is None


# ── sqrt_inverse arithmetic (the milder scheme) ─────────────────────────────────

def test_sqrt_inverse_orders_rare_above_dominant_with_unit_mean():
    weights = loss_config.class_weights("sqrt_inverse", [10, 200, 5000], 3)
    assert weights[0] > weights[1] > weights[2]
    assert sum(weights) / len(weights) == pytest.approx(1.0)


def test_sqrt_inverse_is_the_square_root_of_the_frequency_ratio():
    # The mildness contract: the spread between two classes is the SQUARE ROOT
    # of what inverse frequency would have produced (w_a / w_b =
    # sqrt((count_b + eps) / (count_a + eps))).
    weights = loss_config.class_weights("sqrt_inverse", [10, 200, 5000], 3)
    assert weights[0] / weights[2] == pytest.approx(math.sqrt(5001 / 11))


def test_sqrt_inverse_uniform_counts_give_uniform_weights():
    weights = loss_config.class_weights("sqrt_inverse", [100, 100, 100, 100], 4)
    assert weights == pytest.approx([1.0, 1.0, 1.0, 1.0])


def test_sqrt_inverse_pins_ignored_and_absent_classes():
    base = loss_config.class_weights("sqrt_inverse", [10, 200, 5000], 3)
    # Explicitly ignored classes are pinned to 1.0 and excluded from the mean.
    weights = loss_config.class_weights(
        "sqrt_inverse", [10, 200, 5000, 7], 4, ignore_classes=(3,))
    assert weights[3] == 1.0
    assert weights[:3] == pytest.approx(base)
    # Zero-count classes are auto-pinned (their weight is never used as a CE
    # target, but a raw near-infinite value would rescale every real weight).
    weights = loss_config.class_weights("sqrt_inverse", [10, 200, 5000, 0], 4)
    assert weights[3] == 1.0
    assert weights[:3] == pytest.approx(base)


def test_sqrt_inverse_extreme_rarity_is_clamped():
    counts = [1] + [1_000_000] * 19
    weights = loss_config.class_weights("sqrt_inverse", counts, 20)
    assert max(weights) == loss_config.MAX_CLASS_WEIGHT


def test_sqrt_inverse_no_pixels_falls_back_to_uniform():
    assert loss_config.class_weights("sqrt_inverse", [0, 0, 0], 3) == [1.0, 1.0, 1.0]


@pytest.mark.parametrize("counts,num_classes", [
    ([1, 2], 3),          # length mismatch
    ([1, -2, 3], 3),      # negative count
    ([], 0),              # no classes
])
def test_sqrt_inverse_invalid_inputs_are_rejected(counts, num_classes):
    with pytest.raises(ValueError):
        loss_config.class_weights("sqrt_inverse", counts, num_classes)


# ── Spec resolution across the weighted-loss surface ────────────────────────────

def test_weighted_ce_with_none_is_rejected_as_ce_in_disguise():
    with pytest.raises(ValueError, match="class.weighting"):
        loss_config.resolve_loss_spec("weighted_ce", class_weighting="none")
    # The default scheme IS none, so a bare weighted_ce is equally invalid.
    with pytest.raises(ValueError, match="class.weighting"):
        loss_config.resolve_loss_spec("weighted_ce")


def test_weighted_ce_records_the_selected_scheme():
    spec = loss_config.resolve_loss_spec("weighted_ce", class_weighting="sqrt_inverse")
    assert spec == {"loss": "weighted_ce", "weighting": "sqrt_inverse"}


def test_combined_allows_none_and_records_the_scheme():
    # combined keeps its dice term under none — not ce in disguise.
    spec = loss_config.resolve_loss_spec("combined")
    assert spec == {
        "loss": "combined",
        "dice_weight": loss_config.DEFAULT_DICE_WEIGHT,
        "weighting": "none",
    }
    spec = loss_config.resolve_loss_spec("combined", class_weighting="sqrt_inverse")
    assert spec["weighting"] == "sqrt_inverse"


def test_co_occurrence_allows_none_and_records_the_scheme():
    # co_occurrence keeps its presence-BCE term under none.
    spec = loss_config.resolve_loss_spec("co_occurrence")
    assert spec == {
        "loss": "co_occurrence",
        "co_lambda": loss_config.DEFAULT_CO_LAMBDA,
        "co_pooling": "max",
        "weighting": "none",
    }
    spec = loss_config.resolve_loss_spec("co_occurrence", class_weighting="sqrt_inverse")
    assert spec["weighting"] == "sqrt_inverse"


def test_unweighted_losses_ignore_the_scheme():
    assert loss_config.resolve_loss_spec("ce", class_weighting="sqrt_inverse") == {
        "loss": "ce",
    }
    assert "weighting" not in loss_config.resolve_loss_spec(
        "focal", class_weighting="sqrt_inverse")


@pytest.mark.parametrize("name,scheme,expected", [
    ("ce", "sqrt_inverse", False),
    ("weighted_ce", "sqrt_inverse", True),
    ("focal", "sqrt_inverse", False),
    ("dice", "sqrt_inverse", False),
    ("combined", "none", False),
    ("combined", "sqrt_inverse", True),
    ("co_occurrence", "none", False),
    ("co_occurrence", "sqrt_inverse", True),
])
def test_weights_are_derived_only_when_a_scheme_is_active(name, scheme, expected):
    assert loss_config.loss_uses_class_weights(name, scheme) is expected


# ── CLI surface (launch errors, torch-free) ─────────────────────────────────────

def test_train_cli_rejects_weighted_ce_with_none(capsys):
    with pytest.raises(SystemExit) as excinfo:
        train.main(["--loss", "weighted_ce", "--class-weighting", "none"])
    assert excinfo.value.code == 2
    assert "class-weighting" in capsys.readouterr().err


def test_train_cli_rejects_bare_weighted_ce_under_the_default(capsys):
    with pytest.raises(SystemExit) as excinfo:
        train.main(["--loss", "weighted_ce"])
    assert excinfo.value.code == 2
    assert "class-weighting" in capsys.readouterr().err


def test_train_cli_rejects_unknown_scheme(capsys):
    with pytest.raises(SystemExit) as excinfo:
        train.main(["--class-weighting", "inverse_frequency"])
    assert excinfo.value.code == 2
    assert "--class-weighting" in capsys.readouterr().err


def test_train_help_lists_class_weighting(capsys):
    with pytest.raises(SystemExit) as excinfo:
        train.main(["--help"])
    assert excinfo.value.code == 0
    assert "--class-weighting" in capsys.readouterr().out


# ── Criterion wiring for combined and co_occurrence (torch-gated) ───────────────

def _co_stats(channel_count):
    """Minimal schema-complete co_stats.v2 (the test_co_occurrence_loss shape)."""
    presence = [0] * channel_count
    joint = [[0] * channel_count for _ in range(channel_count)]
    for image in ({0, 3}, {0, 3}, {5}):
        for c in image:
            presence[c] += 1
            for k in image:
                joint[c][k] += 1
    return {
        "schema": "co_stats.v2",
        "split_seed": 42,
        "class_mapping_sha256": "ab" * 32,
        "channel_count": channel_count,
        "special_channel_indices": [],
        "train_images": 3,
        "pixel_counts": {"train": [0] * channel_count},
        "presence_counts": presence,
        "joint_presence_counts": joint,
    }


@pytest.mark.parametrize("name", ["combined", "co_occurrence"])
def test_criterion_builds_without_weights_under_scheme_none(name):
    torch = pytest.importorskip("torch")

    num_classes = 6
    spec = loss_config.resolve_loss_spec(name)  # weighting: none
    criterion = train._build_criterion(
        spec, class_weights=None, device=torch.device("cpu"),
        co_stats=_co_stats(num_classes) if name == "co_occurrence" else None,
    )
    torch.manual_seed(0)
    logits = torch.randn(2, num_classes, 8, 8, requires_grad=True)
    targets = torch.randint(0, num_classes, (2, 8, 8))
    loss = criterion(logits, targets)
    assert torch.isfinite(loss)
    loss.backward()
    assert torch.isfinite(logits.grad).all()


@pytest.mark.parametrize("name", ["weighted_ce", "combined", "co_occurrence"])
def test_criterion_consumes_sqrt_inverse_weights(name):
    torch = pytest.importorskip("torch")

    num_classes = 6
    spec = loss_config.resolve_loss_spec(name, class_weighting="sqrt_inverse")
    weights = loss_config.class_weights(
        "sqrt_inverse", [10, 200, 5000, 40, 40, 40], num_classes)
    criterion = train._build_criterion(
        spec, class_weights=weights, device=torch.device("cpu"),
        co_stats=_co_stats(num_classes) if name == "co_occurrence" else None,
    )
    torch.manual_seed(0)
    logits = torch.randn(2, num_classes, 8, 8, requires_grad=True)
    targets = torch.randint(0, num_classes, (2, 8, 8))
    loss = criterion(logits, targets)
    assert torch.isfinite(loss)
    loss.backward()
    assert torch.isfinite(logits.grad).all()
